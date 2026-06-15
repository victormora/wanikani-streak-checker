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

  local RAW_EMAIL
  RAW_EMAIL=$(cat <<EOF
From: WaniKani Notifier <${FROM_EMAIL}>
To: ${MY_EMAIL}
Subject: ${subject}
MIME-Version: 1.0
Content-Type: text/html; charset="UTF-8"

${body_html}
EOF
  )

  local ENCODED
  ENCODED=$(printf '%s' "$RAW_EMAIL" | base64 | tr '+/' '-_' | tr -d '=\n')
  local PAYLOAD
  PAYLOAD=$(jq -n --arg raw "$ENCODED" '{"raw": $raw}')

  echo "Fetching Gmail access token..."
  local GMAIL_ACCESS_TOKEN
  GMAIL_ACCESS_TOKEN=$(get_gmail_access_token)

  echo "Sending email via Gmail API..."
  curl -s -X POST \
    "https://gmail.googleapis.com/gmail/v1/users/me/messages/send" \
    -H "Authorization: Bearer ${GMAIL_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"
}

# ── Streak check ───────────────────────────────────────────────────

OFFSET=${TIMEZONE_OFFSET_HOURS:-0}
TODAY_START_UTC=$(date -u -d "today 00:00:00 $(( -OFFSET )) hours" +"%Y-%m-%dT%H:%M:%SZ")

echo "Streak check: looking for reviews since ${TODAY_START_UTC} (UTC)"

RESPONSE=$(curl -s \
  -H "Authorization: Bearer $WANIKANI_API_TOKEN" \
  "https://api.wanikani.com/v2/assignments?updated_after=${TODAY_START_UTC}")

REVIEW_COUNT=$(echo "$RESPONSE" | jq '.total_count')
echo "Assignments updated today: $REVIEW_COUNT"

if [ "$REVIEW_COUNT" -eq 0 ]; then
  echo "No reviews done today — sending streak warning..."

  send_email \
    "⚠️ No WaniKani reviews yet today! Streak at risk 🦀" \
    "<p>Hey there! 👋</p>
<p>It's almost <strong>${DEADLINE_HOUR:-21}:00</strong> and you haven't done any WaniKani reviews today. 😱</p>
<p>Don't break your streak — go do them now:</p>
<p><a href=\"https://www.wanikani.com/\">https://www.wanikani.com/</a></p>
<p>頑張ってください！🦀</p>"

  echo "Streak warning sent."
else
  echo "Streak safe — $REVIEW_COUNT assignments reviewed today. 🎉"
fi

echo "Script finished."
