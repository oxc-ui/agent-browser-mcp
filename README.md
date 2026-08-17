# agent-browser-mcp

A browser-use MCP server running on GitHub Actions, exposed via a
**Docker stack + Cloudflare named tunnel** at the stable hostname
**`agent-browser.oxu.indevs.in`**.

The endpoint stays the same across runs. Each workflow run lives ~5h50m
and a 5h cron keeps a fresh runner always serving — there is a ~50m
overlap between consecutive runs, so the endpoint is always live.

## Stack

- **`mcp` container** — `Dockerfile.mcp` packages browser-use + Chromium +
  mcp-proxy + a tiny `/healthz` supervisor into one image. Exposes port
  8080 on the host.
- **`tunnel` container** — official `cloudflare/cloudflared:latest`, runs
  in `network_mode: host` so its `localhost:8080` is the host's port 8080
  (where docker publishes the mcp container). Connects to the named tunnel
  bound to `agent-browser.oxu.indevs.in`.

## Current endpoint

- **MCP URL:**       `https://agent-browser.oxu.indevs.in/mcp`
- **Health probe:**  `https://agent-browser.oxu.indevs.in/healthz` (open)

## MCP client config (Claude Desktop, Cursor, etc.)

```json
{
  "mcpServers": {
    "agent-browser": {
      "url": "https://agent-browser.oxu.indevs.in/mcp",
      "transport": "http"
    }
  }
}
```

## Verifying end-to-end (no auth required)

```bash
# health
curl https://agent-browser.oxu.indevs.in/healthz

# initialize
curl -X POST https://agent-browser.oxu.indevs.in/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"x","version":"1.0"}}}'

# list tools
curl -X POST https://agent-browser.oxu.indevs.in/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

## Repo layout

- `.github/workflows/browser-mcp.yml` — the workflow
- `Dockerfile.mcp` — browser-use + mcp-proxy + Chromium in one image
- `docker-compose.yml` — `mcp` + `tunnel` (host network)
- `deploy/supervise.py` — ~80-line HTTP server: handles `/healthz`, proxies `/mcp` to mcp-proxy's private port
- `deploy/entrypoint.sh` — container startup: launches mcp-proxy + supervise

## Security

The endpoint is publicly reachable (no auth). Anyone who knows the URL can
hit the MCP. To restrict access, either:

- **Cloudflare Access** — add an app at one.dash.cloudflare.com → Zero Trust → Access → Applications, domain `agent-browser.oxu.indevs.in`, path `/mcp`. First MCP client connection will prompt for OTP/SSO and cache a session cookie.
- **Token in `supervise.py`** — replace the proxy with a simple bearer-token check (the GitHub secret `MCP_AUTH_TOKEN` is already in scope).