#!/bin/bash
set -e

# ── Gmail OAuth2 helper ────────────────────────────────────────────

get_gmail_access_token() {
  curl -s -X POST "https://oauth2.googleapis.com/token" \
    --data-urlencode "client_id=${GMAIL_CLIENT_ID}" \
    --data-urlencode "client_secret=${GMAIL_CLIENT_SECRET}" \
    --data-urlencode "refresh_token=${GMAIL_REFRESH_TOKEN}" \
    --data-urlencode "grant_type=refresh_token" \
    | jq -r '.access_token'
}

send_email() {
  local subject="$1"
  local body_html="$2"

  local ENCODED_SUBJECT
  ENCODED_SUBJECT="=?UTF-8?B?$(echo -n "${subject}" | base64 | tr -d '\n')?="

  local RAW_EMAIL
  RAW_EMAIL=$(cat <<EOF
From: Bunpro Notifier <${FROM_EMAIL}>
To: ${MY_EMAIL}
Subject: ${ENCODED_SUBJECT}
MIME-Version: 1.0
Content-Type: text/html; charset="UTF-8"

${body_html}
EOF
  )

  local ENCODED
  ENCODED=$(printf '%s' "$RAW_EMAIL" | base64 | tr '+/' '-_' | tr -d '=\n')

  local ACCESS_TOKEN
  ACCESS_TOKEN=$(get_gmail_access_token)

  curl -s -X POST \
    "https://gmail.googleapis.com/gmail/v1/users/me/messages/send" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg raw "$ENCODED" '{"raw": $raw}')"
}

# ── Bunpro auth ────────────────────────────────────────────────────

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

echo "Fetching Bunpro CSRF token..."

LOGIN_PAGE=$(curl -sf -c "$COOKIE_JAR" "https://bunpro.jp/users/sign_in")

CSRF_TOKEN=$(echo "$LOGIN_PAGE" \
  | grep -oP 'name="authenticity_token"[^>]*value="\K[^"]+' \
  | head -1)

if [ -z "$CSRF_TOKEN" ]; then
  CSRF_TOKEN=$(echo "$LOGIN_PAGE" \
    | grep -oP '<meta name="csrf-token"[^>]*content="\K[^"]+' \
    | head -1)
fi

[ -z "$CSRF_TOKEN" ] && { echo "Could not extract CSRF token."; exit 1; }

echo "Logging in..."

curl -s -o /dev/null \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -X POST \
  --data-urlencode "user[email]=${BUNPRO_EMAIL}" \
  --data-urlencode "user[password]=${BUNPRO_PASSWORD}" \
  --data-urlencode "authenticity_token=${CSRF_TOKEN}" \
  "https://bunpro.jp/users/sign_in"

echo "Fetching frontend_api_token..."

SETTINGS_HEADERS=$(curl -sf \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -D - -o /dev/null \
  "https://bunpro.jp/settings/account")

FRONTEND_API_TOKEN=$(echo "$SETTINGS_HEADERS" \
  | grep -i "set-cookie" \
  | grep -i "frontend_api_token" \
  | sed 's/.*frontend_api_token=\([^;[:space:]]*\).*/\1/' \
  | tr -d '[:space:]' | head -1)

if [ -z "$FRONTEND_API_TOKEN" ]; then
  FRONTEND_API_TOKEN=$(grep "frontend_api_token" "$COOKIE_JAR" \
    | awk '{print $NF}' | tr -d '[:space:]' | head -1)
fi

[ -z "$FRONTEND_API_TOKEN" ] && { echo "Could not extract frontend_api_token."; exit 1; }

echo "Authenticated."

# ── Fetch review activity ──────────────────────────────────────────

# Today's date in local timezone (offset from UTC)
OFFSET=${TIMEZONE_OFFSET_HOURS:-0}
TODAY=$(date -u -d "+${OFFSET} hours" +"%Y-%m-%d")

echo "Checking review activity for: ${TODAY}"

ACTIVITY=$(curl -sf \
  -b "$COOKIE_JAR" \
  -H "Authorization: Token token=${FRONTEND_API_TOKEN}" \
  -H "Accept: application/json" \
  "https://api.bunpro.jp/api/frontend/user_stats/review_activity")

REVIEW_COUNT=$(echo "$ACTIVITY" | jq -r \
  --arg today "$TODAY" \
  '((.grammar[$today] // 0) + (.vocab[$today] // 0))')

echo "Reviews done today: ${REVIEW_COUNT}"

# ── Send warning if nothing done ───────────────────────────────────

if [ "$REVIEW_COUNT" -eq 0 ]; then
  echo "No reviews done today — sending streak warning..."

  send_email \
    "⚠️ No Bunpro reviews yet today! Streak at risk 📝" \
    "<p>Hey there! 👋</p>
<p>It's almost <strong>${DEADLINE_HOUR:-21}:00</strong> and you haven't done any Bunpro reviews today. 😱</p>
<p>Don't break your streak — go do them now:</p>
<p><a href=\"https://bunpro.jp/review\">https://bunpro.jp/review</a></p>
<p>頑張ってください！📝</p>"

  echo "Streak warning sent."
else
  echo "Streak safe — ${REVIEW_COUNT} reviews done today. 🎉"
fi

echo "Script finished."
