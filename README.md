# agent-browser-mcp

A browser-use MCP server running on GitHub Actions, exposed via a **named
Cloudflare Tunnel** at the stable hostname **`agent-browser.oxu.indevs.in`**.

The endpoint stays the same across runs (only the auth token rotates if
you reset the `MCP_AUTH_TOKEN` secret). Each workflow run lives ~5h50m
and a 5h cron keeps a fresh runner always serving — there is a ~50m
overlap between consecutive runs, so the endpoint is always live.

## Current endpoint

- **MCP URL:**       `https://agent-browser.oxu.indevs.in/mcp`
- **Auth header:**   `Authorization: Bearer ${MCP_AUTH_TOKEN}`
- **Health probe:**  `https://agent-browser.oxu.indevs.in/healthz` (public, no auth)

## MCP client config (Claude Desktop, Cursor, etc.)

```json
{
  "mcpServers": {
    "agent-browser": {
      "url": "https://agent-browser.oxu.indevs.in/mcp",
      "transport": "http",
      "headers": {
        "Authorization": "Bearer ${MCP_AUTH_TOKEN}"
      }
    }
  }
}
```

## How it works

- `mcp-proxy` (pinned to `mcp<2`) bridges browser-use's stdio MCP server to StreamableHTTP
- nginx on `:80` adds bearer-token auth (`MCP_AUTH_TOKEN` secret) and a public `/healthz`
- `cloudflared tunnel run --token $CF_TUNNEL_TOKEN` connects to the named
  tunnel bound to `agent-browser.oxu.indevs.in` — no random hostname
- A supervisor loop restarts any of the three processes if they die
- A 5h cron + 5h50m timeout creates overlap so the endpoint is always live

## Repo layout

- `.github/workflows/browser-mcp.yml` — the workflow
- `deploy/start.sh` — launches mcp-proxy + nginx + cloudflared
- `deploy/nginx.conf.template` — bearer-auth + `/healthz`
- `endpoint.json` (main) — static endpoint metadata
