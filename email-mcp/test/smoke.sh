#!/usr/bin/env bash
# Runs the chart's pod composition with plain Docker and checks the auth paths.
# Mirrors the Deployment: root volume-permissions init, server on loopback with
# the account in its environment, Caddy sidecar in the same network namespace.
set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST=email-mcp.example.com
TOKEN=$(openssl rand -hex 32)
PASSWORD=$(openssl rand -hex 16)
PREFIX=email-mcp-smoke
UID_GID=1000:1000

SERVER_IMAGE=$(helm show values "$CHART_DIR" | awk '/^  repository:/{print $2; exit}'):$(awk '/^appVersion:/{gsub(/"/,"",$2); print $2}' "$CHART_DIR/Chart.yaml")
PROXY_IMAGE=caddy:$(helm show values "$CHART_DIR" | awk '/^proxy:/{p=1} p&&/tag:/{gsub(/"/,"",$2); print $2; exit}')

cleanup() {
  docker rm -f "$PREFIX-server" "$PREFIX-proxy" >/dev/null 2>&1 || true
  docker volume rm "$PREFIX-data" >/dev/null 2>&1 || true
  rm -f "$CADDYFILE"
}
trap cleanup EXIT

CADDYFILE=$(mktemp)
helm template smoke "$CHART_DIR" --values "$CHART_DIR/ci/default-values.yaml" --show-only templates/configmap-caddy.yaml \
  | awk '/^  Caddyfile: \|/{p=1; next} p && /^    /{sub(/^    /,""); print}' > "$CADDYFILE"

# Same variables the Deployment sets, with the Secret's two keys inlined.
ENV=(-e HOME=/data/config -e MCP_EMAIL_SERVER_CONFIG_PATH=/data/config/config.toml
     -e MCP_EMAIL_SERVER_EMAIL_ADDRESS=smoke@example.com -e "MCP_EMAIL_SERVER_PASSWORD=$PASSWORD"
     -e MCP_EMAIL_SERVER_IMAP_HOST=127.0.0.1 -e MCP_EMAIL_SERVER_IMAP_PORT=993
     -e MCP_EMAIL_SERVER_IMAP_SSL=true -e MCP_EMAIL_SERVER_IMAP_START_SSL=false
     -e MCP_EMAIL_SERVER_ALLOWED_RECIPIENTS=
     -e MCP_HOST=127.0.0.1 -e MCP_PORT=9557
     -e MCP_ALLOWED_HOSTS="$HOST" -e MCP_ALLOWED_ORIGINS="https://$HOST,https://claude.ai")

# Same capability sets and no-new-privileges as the Deployment's securityContexts.
RESTRICT=(--cap-drop ALL --security-opt no-new-privileges)

echo "== volume-permissions (root)"
docker volume create "$PREFIX-data" >/dev/null
docker run --rm -v "$PREFIX-data:/data" --user 0:0 "${RESTRICT[@]}" \
  --cap-add CHOWN --cap-add FOWNER --cap-add DAC_OVERRIDE --entrypoint sh "$SERVER_IMAGE" \
  -c "mkdir -p /data/config && chown $UID_GID /data/config && chmod 0700 /data/config && chmod 0755 /data"

echo "== server (held back a few seconds so the proxy is probed while the upstream is down)"
docker run -d --name "$PREFIX-server" -v "$PREFIX-data:/data" --user "$UID_GID" "${RESTRICT[@]}" "${ENV[@]}" \
  -p 127.0.0.1:18080:8080 --entrypoint sh "$SERVER_IMAGE" \
  -c 'sleep 5; exec tini -- mcp-email-server streamable-http' >/dev/null

echo "== proxy (shares the server's network namespace, like a pod)"
docker run -d --name "$PREFIX-proxy" --network "container:$PREFIX-server" --user "$UID_GID" "${RESTRICT[@]}" \
  --cap-add NET_BIND_SERVICE -e MCP_BEARER_TOKEN="$TOKEN" -v "$CADDYFILE:/etc/caddy/Caddyfile:ro" --read-only \
  --tmpfs /data --tmpfs /config "$PROXY_IMAGE" \
  caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null

for _ in $(seq 1 30); do
  curl -sf -o /dev/null http://127.0.0.1:18080/healthz && break
  sleep 1
done

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
MCP_HEADERS=(-H "Host: $HOST" -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json')
probe() { # label expected [curl args...]
  local label=$1 expected=$2; shift 2
  local code
  code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "${MCP_HEADERS[@]}" -d "$INIT" "$@")
  if [ "$code" = "$expected" ]; then echo "ok   $label -> $code"; else echo "FAIL $label -> $code (want $expected)"; FAILED=1; fi
}
FAILED=0
U=http://127.0.0.1:18080
probe "secret path, upstream down"  502 "$U/$TOKEN/mcp"
for _ in $(seq 1 60); do
  [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "${MCP_HEADERS[@]}" -H "Authorization: Bearer $TOKEN" -d "$INIT" "$U/mcp")" = 200 ] && break
  sleep 1
done
probe "no token on /mcp"            401 "$U/mcp"
probe "wrong secret path"           401 "$U/nope/mcp"
probe "wrong bearer"                401 -H 'Authorization: Bearer nope' "$U/mcp"
probe "bearer header"               200 -H "Authorization: Bearer $TOKEN" "$U/mcp"
probe "x-api-key header"            200 -H "X-Api-Key: $TOKEN" "$U/mcp"
probe "secret path, no header"      200 "$U/$TOKEN/mcp"
probe "secret path + claude origin" 200 -H 'Origin: https://claude.ai' "$U/$TOKEN/mcp"
probe "secret path + other origin"  403 -H 'Origin: https://evil.example' "$U/$TOKEN/mcp"

echo "== account from the environment (one MCP session through the proxy)"
SESSION=$(curl -s -i -m 10 "${MCP_HEADERS[@]}" -H "Authorization: Bearer $TOKEN" -d "$INIT" "$U/mcp" \
  | tr -d '\r' | awk 'tolower($1)=="mcp-session-id:"{print $2}')
call() { # tool-name json-arguments
  curl -s -m 30 "${MCP_HEADERS[@]}" -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $SESSION" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" "$U/mcp"
}
expect() { # label needle haystack
  if [ "${3#*"$2"}" != "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (missing $2)"; FAILED=1; fi
}
curl -s -m 10 "${MCP_HEADERS[@]}" -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$U/mcp" -o /dev/null
ACCOUNTS=$(call list_available_accounts '{}')
expect "account listed"     '"email_address":"smoke@example.com"' "$ACCOUNTS"
expect "account cannot send" '"can_send":false' "$ACCOUNTS"
expect "no allowed recipients" '"result":[]' "$(call list_allowed_recipients '{}')"
# Fails at IMAP (nothing listens), but the index is opened first and logs if it cannot be.
call list_emails_metadata '{"account_name":"default","mailbox":"INBOX","page":1,"page_size":1}' >/dev/null
if docker logs "$PREFIX-server" 2>&1 | awk '/metadata index is unavailable/{f=1} END{exit !f}'; then
  echo "FAIL metadata index did not open on /data/config"; FAILED=1
else
  echo "ok   metadata index opened on /data/config"
fi

echo "== log hygiene"
expect "secret path redacted in proxy log" '"uri":"/REDACTED/mcp"' "$(docker logs "$PREFIX-proxy" 2>&1)"
for pair in "token:$TOKEN" "password:$PASSWORD"; do
  what=${pair%%:*} value=${pair#*:}
  if { docker logs "$PREFIX-proxy"; docker logs "$PREFIX-server"; } 2>&1 | awk -v v="$value" 'index($0, v){f=1} END{exit !f}'; then
    echo "FAIL $what leaked into a log"; FAILED=1
  else
    echo "ok   $what absent from both logs"
  fi
done

[ "$FAILED" = 0 ] && echo "SMOKE TEST PASSED" || { echo "SMOKE TEST FAILED"; docker logs "$PREFIX-server" 2>&1 | tail -20; exit 1; }
