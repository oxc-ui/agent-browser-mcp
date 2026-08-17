#!/usr/bin/env bash
# entrypoint.sh — launches mcp-proxy + the /healthz supervisor inside
# the container. Both processes run in the background; if either dies
# the supervisor exit triggers the container restart policy.
set -uo pipefail
export PATH="/root/.local/bin:/usr/local/bin:$PATH"

MCP_PROXY_UPSTREAM_PORT="${MCP_PROXY_UPSTREAM_PORT:-8765}"
MCP_PORT="${MCP_PORT:-8080}"

# LLM config for browser-use's agent tools. The user's custom provider
# (PXO/indevs proxy) requires model "openrouter/openrouter/free".
BROWSER_USE_MODEL="${BROWSER_USE_MODEL:-openrouter/openrouter/free}"

mkdir -p /tmp/abmcp-logs

# --- Write browser-use config.json (UUID-keyed schema, matches what
# the CLI itself writes) so the agent tools use the right model/key ---
CHROME_BIN=$(ls -d /root/.cache/ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | head -1)
mkdir -p /root/.config/browseruse
python3 - "$CHROME_BIN" "$BROWSER_USE_MODEL" <<'PYEOF'
import json, sys, uuid
from datetime import datetime, timezone
chrome_bin, model = sys.argv[1], sys.argv[2]
now = datetime.now(timezone.utc).isoformat()
cfg = {
    "browser_profile": {
        (bp := str(uuid.uuid4())): {
            "id": bp, "default": True, "created_at": now,
            "headless": True, "chromium_sandbox": False,
            "executable_path": chrome_bin or None,
            "user_data_dir": None, "allowed_domains": None,
            "downloads_path": None,
        }
    },
    "llm": {
        (lid := str(uuid.uuid4())): {
            "id": lid, "default": True, "created_at": now,
            "api_key": "",  # resolved from OPENAI_API_KEY env at runtime
            "model": model,
            "temperature": None, "max_tokens": None,
        }
    },
    "agent": {
        (aid := str(uuid.uuid4())): {
            "id": aid, "default": True, "created_at": now,
            "max_steps": None, "use_vision": None, "system_prompt": None,
        }
    },
}
with open("/root/.config/browseruse/config.json", "w") as f:
    json.dump(cfg, f, indent=2)
print(f"[entrypoint] wrote browser-use config: model={model} chrome={chrome_bin or 'auto'}")
PYEOF

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
