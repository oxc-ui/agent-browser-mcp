# agent-browser-mcp

A browser-use MCP server running on GitHub Actions, exposed via a rotating
Cloudflare **quick-tunnel** (random `*.trycloudflare.com` hostname — no
account, no token required).

**The URL changes every ~5 hours** when the worker handoff fires. Always fetch
the current endpoint from `endpoint.json` at the raw URL:

- JSON:   https://raw.githubusercontent.com/oxc-ui/agent-browser-mcp/main/endpoint.json
- README: https://github.com/oxc-ui/agent-browser-mcp#current-endpoint

## Current endpoint

> _Will be populated by the next workflow run. Fetch `endpoint.json` (linked
> above) for the live URL._

## How it works

- `mcp-proxy` bridges browser-use's stdio MCP server to StreamableHTTP
- nginx on `:80` adds bearer-token auth (`MCP_AUTH_TOKEN` secret) and a public `/healthz`
- `cloudflared --url http://localhost` opens a quick-tunnel to a random
  `*.trycloudflare.com` hostname — no Cloudflare account needed
- The current URL is published back to this repo (`endpoint.json` + this README)
  on every successful start
- A supervisor loop restarts any of the three processes if they die
- A 5h cron + 5h50m timeout creates overlap so the endpoint is always live

## MCP client config (Claude Desktop, Cursor, etc.)

```json
{
  "mcpServers": {
    "agent-browser": {
      "url": "FETCH_FROM_endpoint_json",
      "transport": "http",
      "headers": {
        "Authorization": "Bearer ${MCP_AUTH_TOKEN}"
      }
    }
  }
}
```

Replace `FETCH_FROM_endpoint_json` with the live URL from `endpoint.json`.

## Repo layout

- `.github/workflows/browser-mcp.yml` — the workflow
- `deploy/start.sh` — launches mcp-proxy + nginx + cloudflared
- `deploy/nginx.conf.template` — bearer-auth + `/healthz`
- `endpoint.json` — current live endpoint (auto-updated)
