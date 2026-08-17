#!/usr/bin/env bash
# entrypoint.sh — launches mcp-proxy + the /healthz supervisor inside
# the container. Both processes run in the background; if either dies
# the supervisor exit triggers the container restart policy.
set -uo pipefail
export PATH="/root/.local/bin:/usr/local/bin:$PATH"

MCP_PROXY_UPSTREAM_PORT="${MCP_PROXY_UPSTREAM_PORT:-8765}"
MCP_PORT="${MCP_PORT:-8080}"

mkdir -p /tmp/abmcp-logs

echo "[entrypoint] PATH=$PATH"
echo "[entrypoint] which mcp-proxy: $(which mcp-proxy 2>&1 || echo NOT_FOUND)"
echo "[entrypoint] which browser-use: $(which browser-use 2>&1 || echo NOT_FOUND)"
echo "[entrypoint] launching mcp-proxy on :${MCP_PROXY_UPSTREAM_PORT}..."
nohup mcp-proxy --host 127.0.0.1 --port "${MCP_PROXY_UPSTREAM_PORT}" --stateless -- \
    browser-use --mcp \
    >> /tmp/abmcp-logs/mcp-proxy.log 2>&1 &
MCP_PROXY_PID=$!
echo "[entrypoint] mcp-proxy pid: ${MCP_PROXY_PID}"

# Quick check: did it survive 3 seconds?
sleep 3
if kill -0 "${MCP_PROXY_PID}" 2>/dev/null; then
  echo "[entrypoint] mcp-proxy still alive after 3s"
else
  echo "[entrypoint] WARNING: mcp-proxy died within 3s"
  echo "=== mcp-proxy.log ==="
  cat /tmp/abmcp-logs/mcp-proxy.log 2>/dev/null || echo "(no log)"
fi

echo "[entrypoint] launching supervise.py on :${MCP_PORT}..."
exec env MCP_PORT="${MCP_PORT}" MCP_PROXY_UPSTREAM_PORT="${MCP_PROXY_UPSTREAM_PORT}" \
    python /usr/local/bin/supervise.py
