# Cloudflare Access — one-time setup

The Docker stack tunnels `https://agent-browser.oxu.indevs.in/mcp` directly
to `mcp-proxy` (no nginx). Auth is enforced by Cloudflare Access — requests
without a valid Access session JWT are rejected at the Cloudflare edge
before they ever reach the tunnel.

## One-time dashboard setup

1. Go to **one.dash.cloudflare.com** → **Zero Trust** → **Access** → **Applications**
2. Click **Add an application** → **Self-hosted**
3. Fill in:
   - **Name:** `agent-browser-mcp`
   - **Application domain:** `agent-browser.oxu.indevs.in`
   - **Path:** `/mcp` (only protect the MCP endpoint; leave `/healthz` open)
4. **Identity providers:** allow at minimum one (e.g. "One-time PIN" — sends
   a code to your email) or your GitHub org SSO
5. **Policies:** create a policy called `allow-self`:
   - **Action:** Allow
   - **Include:** your email (e.g. `tndmasud@proton.me`) or your GitHub login
6. Save. Cloudflare will auto-attach to your named tunnel's `agent-browser.oxu.indevs.in`
   route because the application domain matches the tunnel route.

## Client behavior

When the MCP client (e.g. Claude Desktop) connects to
`https://agent-browser.oxu.indevs.in/mcp`, Cloudflare returns a 302/403
redirect to the Access login page. The browser-based flow asks for an OTP
and sets a `cf-authorization` cookie. For headless MCP clients, you need
to:

- Either pre-authenticate via `cloudflared access login` and pass the
  resulting JWT as a `Cf-Access-Jwt-Assertion` header, OR
- Use `cloudflared access ...` to forward requests with the JWT attached

The simplest path for Claude Desktop:

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

Claude Desktop opens a browser window for Access auth the first time and
caches the session cookie. Subsequent connections use the cached cookie.

## If you want simpler auth later

Replace this setup with a tiny Python auth sidecar that adds
`Authorization: Bearer ${MCP_AUTH_TOKEN}` checks. That's a 30-line
rewrite of `deploy/supervise.py` — see git history if needed.
