# agent-browser-mcp

A browser-use MCP server running on GitHub Actions, exposed via a
**Docker stack + Cloudflare named tunnel** at the stable hostname
**`agent-browser.oxu.indevs.in`**.

The endpoint stays the same across runs (only the host port on the
Actions runner rotates). Each workflow run lives ~5h50m and a 5h cron
keeps a fresh runner always serving — there is a ~50m overlap between
consecutive runs, so the endpoint is always live.

## Stack

- **`mcp` container** — `Dockerfile.mcp` packages browser-use + Chromium +
  mcp-proxy + a tiny `/healthz` supervisor into one image. Exposes port 8080.
- **`tunnel` container** — official `cloudflare/cloudflared:latest`, connects
  to the named tunnel bound to `agent-browser.oxu.indevs.in`, forwards HTTP
  to the `mcp` container.
- **Auth** — Cloudflare Access (configured once in the dashboard — see
  [`CLOUDFLARE_ACCESS.md`](./CLOUDFLARE_ACCESS.md)). No nginx.

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

The first time Claude Desktop connects, it will open a browser window for
Cloudflare Access auth (one-time PIN to your email, or GitHub SSO). The
session cookie is cached for subsequent connections.

## Repo layout

- `.github/workflows/browser-mcp.yml` — the workflow
- `Dockerfile.mcp` — browser-use + mcp-proxy + Chromium in one image
- `docker-compose.yml` — two services: `mcp` + `tunnel`
- `deploy/supervise.py` — tiny HTTP server exposing `/healthz` + proxying `/mcp`
- `deploy/entrypoint.sh` — container startup: launches mcp-proxy + supervise
- `CLOUDFLARE_ACCESS.md` — one-time Access setup instructions
