# agent-browser-mcp

A **browser-use MCP server** running 24/7 on **GitHub Actions** runners, exposed through a **Cloudflare tunnel**. Built for a tiny VPS (841 MB RAM) that can't run a browser itself — the heavy lifting happens on GitHub's free runners (2 vCPU / 7 GB RAM), and the VPS just consumes the MCP endpoint.

## Architecture

```
GitHub Actions runner (ubuntu-latest, 7 GB RAM)
├── browser-use MCP server   (stdio, spawned by mcp-proxy via uvx)
├── mcp-proxy                (stdio -> Streamable HTTP on rotated port)
├── nginx :80                (bearer-token auth, SSE-friendly timeouts)
└── cloudflared              (named tunnel, token-based)
        │
        ▼
https://agent-browser.oxu.indevs.in/mcp   ← MCP clients connect here
```

## 24/7 strategy

- **`browser-mcp.yml`** runs on a `0 */5 * * *` cron (every 5 h) with a
  350-minute (5 h 50 m) timeout — each run **overlaps** the next by
  ~50 minutes, so there is always a live runner during handoff.
- **Port rotation** prevents two overlapping runs from colliding:
  `port = 8001 + (run_number % 4)` → cycle 8002 → 8003 → 8004 → 8001.
  Consecutive runs always bind different ports; the tunnel ingress
  points at `http://localhost` (port 80, nginx), so the rotation is an
  internal detail that keeps nginx binds from racing.
- **`watchdog.yml`** probes the public endpoint every 15 minutes; if it's
  dead and no `browser-mcp` run is in flight, it re-dispatches the
  workflow. Self-healing.

## MCP endpoint

- **URL:** `https://agent-browser.oxu.indevs.in/mcp`
- **Transport:** Streamable HTTP (stateless)
- **Auth:** `Authorization: Bearer <MCP_AUTH_TOKEN>`
- **Health:** `GET /healthz` (no auth) returns `ok`

### Hermes Agent config

```yaml
mcp_servers:
  agent_browser:
    url: "https://agent-browser.oxu.indevs.in/mcp"
    headers:
      Authorization: "Bearer <token>"
    timeout: 300
    connect_timeout: 60
```

Tools appear as `mcp_agent_browser_browser_navigate`, `..._browser_click`, etc.

## Available tools

Direct control: `browser_navigate`, `browser_click`, `browser_type`,
`browser_get_state`, `browser_scroll`, `browser_go_back`,
`browser_take_screenshot`, `browser_extract_content`, tab management
(`browser_list_tabs`, `browser_switch_tab`, `browser_close_tab`) and
session management. Plus `retry_with_browser_use_agent` for full
LLM-driven automation (needs `OPENAI_API_KEY` secret).

## Repo secrets

| Secret | Purpose |
|---|---|
| `CF_TUNNEL_TOKEN` | Cloudflare named-tunnel token |
| `MCP_AUTH_TOKEN` | Bearer token for the MCP endpoint |
| `OPENAI_API_KEY` | (optional) LLM for the agent tool |
| `OPENAI_API_BASE` | (optional) OpenAI-compatible base URL |

## Notes

- Public repo + secrets: secrets are only injected into workflow runs;
  they never appear in the repo. The MCP endpoint itself is bearer-gated.
- Free-tier Actions on public repos: unlimited minutes, 6 h job cap —
  hence the 5 h schedule + overlap design.
- Logs from every run are uploaded as artifacts (`browser-mcp-logs-run-N`).
