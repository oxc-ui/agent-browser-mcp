#!/usr/bin/env bash
# Start the browser-use MCP stack on a GitHub Actions runner:
#   mcp-proxy (stdio->streamable HTTP) -> nginx (auth, :80) -> cloudflared quick-tunnel
#
# No Cloudflare account/token needed: --url mode hands out a random *.trycloudflare.com
# hostname. The current URL is written to /tmp/abmcp-logs/tunnel_url.txt so the
# workflow can read it, and to GitHub via a separate commit step.
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"
LOG_DIR=/tmp/abmcp-logs
mkdir -p "$LOG_DIR"

PORT="${MCP_PORT:?MCP_PORT is required}"
AUTH="${MCP_AUTH_TOKEN:-}"

echo "[start] MCP port: $PORT"

# browser-use env: headless, no sandbox (runner is a container), quiet telemetry
export BROWSER_USE_HEADLESS=true
export ANONYMIZED_TELEMETRY=false
export BROWSER_USE_CLOUD_SYNC=false
export BROWSER_USE_LOGGING_LEVEL=info
# LLM keys are only needed for the browser_task agent tool; direct-control
# tools (navigate/click/type/...) work without them.
export OPENAI_API_KEY="${OPENAI_API_KEY:-}"
export OPENAI_API_BASE="${OPENAI_API_BASE:-}"

echo "[start] launching mcp-proxy -> browser-use MCP (stdio)..."
nohup mcp-proxy --host 127.0.0.1 --port "$PORT" --stateless -- \
  uvx --from 'browser-use[cli]' browser-use --mcp \
  >> "$LOG_DIR/mcp-proxy.log" 2>&1 &
echo "[start] mcp-proxy pid: $!"

# wait for the stdio server to come up behind the proxy
for i in $(seq 1 60); do
  if curl -sf --max-time 5 -o /dev/null \
    -X POST "http://127.0.0.1:$PORT/mcp" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"boot","version":"1.0"}}}'; then
    echo "[start] mcp-proxy answering on :$PORT after ${i}s"
    break
  fi
  sleep 1
  if [ "$i" = "60" ]; then
    echo "[start] WARNING: mcp-proxy not answering after 60s (continuing — health check will verify)"
    tail -20 "$LOG_DIR/mcp-proxy.log" || true
  fi
done

echo "[start] launching nginx on :80..."
sudo nginx -c /tmp/nginx.conf
echo "[start] nginx up"

echo "[start] launching cloudflared tunnel (named, token: ${CF_TUNNEL_TOKEN:0:20}...)..."
nohup cloudflared tunnel --no-autoupdate run --token "$CF_TUNNEL_TOKEN" \
  >> "$LOG_DIR/cloudflared.log" 2>&1 &
CFD_PID=$!
echo "[start] cloudflared pid: $CFD_PID"

# Named tunnels don't print a random hostname — they use the
# tunnel-UUID.trycloudflare.com / configured route. For our setup we
# read the hostname from the local Cloudflare config; if missing,
# fall back to a sane default of agent-browser.oxu.indevs.in.
URL="${TUNNEL_PUBLIC_URL:-https://agent-browser.oxu.indevs.in}"
echo "$URL" > "$LOG_DIR/tunnel_url.txt"
echo "[start] tunnel URL configured: $URL"

# Give cloudflared ~10s to authenticate before claiming success
sleep 10

if [ -z "$URL" ]; then
  echo "[start] WARNING: tunnel URL not configured"
  tail -20 "$LOG_DIR/cloudflared.log" || true
fi
