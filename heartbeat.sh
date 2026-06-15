#!/bin/bash
set -e

echo "Sending heartbeat email..."

ACCESS_TOKEN=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
  --data-urlencode "client_id=${GMAIL_CLIENT_ID}" \
  --data-urlencode "client_secret=${GMAIL_CLIENT_SECRET}" \
  --data-urlencode "refresh_token=${GMAIL_REFRESH_TOKEN}" \
  --data-urlencode "grant_type=refresh_token" \
  | jq -r '.access_token')

RAW_EMAIL=$(cat <<EOF
From: WaniKani Notifier <${FROM_EMAIL}>
To: ${MY_EMAIL}
Subject: =?UTF-8?B?$(echo -n "✅ WaniKani Notifier is alive 🦀" | base64 | tr -d '\n')?=
MIME-Version: 1.0
Content-Type: text/html; charset="UTF-8"

<p>Weekly check-in: your WaniKani notification system is up and running. 🎉</p>
<p>This email also keeps the Gmail OAuth token alive — ignore it if everything looks normal.</p>
<p>頑張ってください！🦀</p>
EOF
)

ENCODED=$(printf '%s' "$RAW_EMAIL" | base64 | tr '+/' '-_' | tr -d '=\n')

curl -s -X POST \
  "https://gmail.googleapis.com/gmail/v1/users/me/messages/send" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg raw "$ENCODED" '{"raw": $raw}')"

echo "Heartbeat sent."
