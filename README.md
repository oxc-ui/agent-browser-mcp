# agent-browser-mcp

A browser-use MCP server running on GitHub Actions, exposed via a rotating
Cloudflare **quick-tunnel** (random `*.trycloudflare.com` hostname — no
account, no token required).

**The URL changes every ~5 hours** when the worker handoff fires. Always fetch
the current endpoint from the live JSON at:

- https://raw.githubusercontent.com/oxc-ui/agent-browser-mcp/endpoint/endpoint.json

## Current endpoint

> _The live endpoint is published to the `endpoint` branch at the URL above._
> _Read it with curl or any HTTP client:_

```bash
curl -sL https://raw.githubusercontent.com/oxc-ui/agent-browser-mcp/endpoint/endpoint.json
# {"url": "https://xxxx-yyyy.trycloudflare.com", "mcp_endpoint": "https://.../mcp", ...}
```

## How it works

- `mcp-proxy` bridges browser-use's stdio MCP server to StreamableHTTP
- nginx on `:80` adds bearer-token auth (`MCP_AUTH_TOKEN` secret) and a public `/healthz`
- `cloudflared --url http://localhost` opens a quick-tunnel to a random
  `*.trycloudflare.com` hostname — no Cloudflare account needed
- On successful start the runner publishes the discovered URL to the
  `endpoint` branch (via the Contents API — no race with the workflow's
  own `main`-branch checkout)
- A supervisor loop restarts any of the three processes if they die
- A 5h cron + 5h50m timeout creates overlap so the endpoint is always live

## MCP client config (Claude Desktop, Cursor, etc.)

```json
{
  "mcpServers": {
    "agent-browser": {
      "url": "FETCH_FROM_ENDPOINT_BRANCH",
      "transport": "http",
      "headers": {
        "Authorization": "Bearer ${MCP_AUTH_TOKEN}"
      }
    }
  }
}
```

Replace `FETCH_FROM_ENDPOINT_BRANCH` with the live URL from the
`endpoint/endpoint.json` file. The `MCP_AUTH_TOKEN` secret stays the same
across handoffs — only the URL rotates.

## Repo layout

- `.github/workflows/browser-mcp.yml` — the workflow
- `deploy/start.sh` — launches mcp-proxy + nginx + cloudflared
- `deploy/nginx.conf.template` — bearer-auth + `/healthz`
- `endpoint.json` (main) — placeholder, real one lives on `endpoint` branch
