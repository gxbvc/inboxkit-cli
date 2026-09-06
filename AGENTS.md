# inboxkit-cli

CLI for InboxKit (app.inboxkit.com) — cold email infra: domains, mailboxes, warmup, workspaces.

## Config

Path: `~/.config/inboxkit/.env` (mode 600, `KEY=VALUE` lines)
```
INBOXKIT_API_KEY=...
INBOXKIT_EMAIL=christian@gxb.vc
INBOXKIT_WORKSPACE_UID=...
```
Env vars (`INBOXKIT_API_KEY`, `INBOXKIT_WORKSPACE_UID`) win over the file if both set.

**Never print, log, or echo the API key.** It is a live Bearer token. Do not
`cat` the .env file in chat output or commit it — it's gitignored, keep it
that way.

`INBOXKIT_WORKSPACE_UID` is the default workspace for `domains`/`mailboxes`.
Pass `--workspace UID` to target a different one.

## Commands

```bash
inboxkit-cli account                                  # credits, plan, mailbox slots
inboxkit-cli workspaces list [--format json]
inboxkit-cli workspaces show UID
inboxkit-cli workspaces create --name NAME [--webhook URL] [--admins-only]
inboxkit-cli domains list [--workspace UID] [--page N] [--limit N] [--format json]
inboxkit-cli mailboxes list [--workspace UID] [--page N] [--limit N] [--format json]
inboxkit-cli raw METHOD PATH [--data JSON] [--query k=v ...] [--workspace UID]
```

`workspaces create` is the one non-read-only wrapped command. Everything
that costs money or destroys data is deliberately NOT wrapped: no domain
registration/renewal, no mailbox provisioning, no credit purchases, no
workspace delete/archive. Use `raw` for those only if you know exactly what
you're doing — it hits the real endpoint and can spend money or delete
things.

## Behaviors

- `domains list` / `mailboxes list` are `POST` under the hood with an
  `X-Workspace-Id` header (InboxKit's API quirk, not a REST GET). The CLI
  hides this.
- `--format json` on any command dumps the raw API response, unmodified.
- Missing workspace on `domains`/`mailboxes list` → exit 2 with a message
  naming the fix, not a stack trace.
- 401 → bad API key. 403 → key lacks permission. 404 → not found. All exit 1.
- `raw` covers the other ~160 endpoints (warmup, sequencers, InfraGuard,
  email insights, registrar credentials). See https://docs.inboxkit.com.

## Notes

- Single file, stdlib Ruby, no gems. No remote (local git repo only).
- Test: `ruby test/test_inboxkit-cli.rb` — offline, stubs a TCP server.
