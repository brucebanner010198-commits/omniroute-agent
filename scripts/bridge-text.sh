#!/bin/bash
# bridge-text.sh <prompt-file>
set -euo pipefail

PROMPT_FILE="$1"
OMNIROUTE_BASE="${OMNIROUTE_BASE:-http://localhost:20128/v1}"
OMNIROUTE_MODEL="${OMNIROUTE_MODEL:-auto}"

if ! curl -sf -m 5 "${OMNIROUTE_BASE}/models" >/dev/null 2>&1; then
  echo "ERROR: OmniRoute server not reachable at ${OMNIROUTE_BASE}" >&2
  exit 1
fi

PROMPT_JSON="$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "$PROMPT_FILE")"

RESPONSE="$(curl -sf -m 60 "${OMNIROUTE_BASE}/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${OMNIROUTE_API_KEY:-omniroute-local}" \
  -d "{\"model\":\"${OMNIROUTE_MODEL}\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":${PROMPT_JSON}}]}")"

TEXT="$(echo "$RESPONSE" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "error" in d:
    err = d["error"]
    msg = err.get("message", err) if isinstance(err, dict) else err
    print("ERROR: OmniRoute returned an error: " + str(msg), file=sys.stderr)
    sys.exit(1)
print(d["choices"][0]["message"]["content"])
')"

if [ -z "$TEXT" ]; then
  echo "ERROR: empty response from OmniRoute" >&2
  exit 1
fi

echo "$TEXT"
