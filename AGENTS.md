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

## Fleet playbook (quote → confirm → buy)

Trigger: Christian says spin up N cold inboxes / lookalike domains for a project.
Do **not** invent sender names or domain lists and buy them. Quote first. Buy only after he names the domains (or says yes to a printed list).

### Sizing

- 3 Microsoft mailboxes per domain (InboxKit + deliverability).
- 25 cold sends/mailbox/day (mailer cap is 30).
- Domains = `ceil(inboxes / 3)`. Add ~30% spare domains only if he asked for a warming pool.
- `.com` only. Buy on **Cloudflare Registrar** (`cloudflare-cli`), then **connect** to InboxKit. Do not let InboxKit register the domain (double-buy).
- Nameservers stay on Cloudflare (`carter` / `ines`). Connect with a **Zone DNS** token, not the registrar-only token. Token file: `~/.config/inboxkit/cloudflare-dns.env` (mode 600). Never print it.

### Prices (live 2026-09-06)

- Domain: **$10.46/yr** via `cloudflare-cli check` (confirm each batch; max 20 per check).
- Microsoft mailbox: **3 InboxKit credits** = **$3** one-shot (not the $2.50 marketing number).
- Warmup: **$3/mailbox/mo**, subscribe after buy; stays `pending_activation` until the box is `active`.
- SMTP/IMAP 404 until mailbox status is `active` (Microsoft can sit in `processing` / `scheduled` for a while).

Quote line:

```
N inboxes → D=ceil(N/3) domains
Year 1 domains: D × $10.46
InboxKit now: N × $3 credits
Monthly: N × $3 mailboxes + N × $3 warmup
```

Example: 50 inboxes → 17 domains → ~$178 year-1 domains + $150 credits now + ~$300/mo.

### Names — do not invent

Local-part = real first names at the project. InboxKit also wants a last name: use the real one, or ask.

| Project | Workspace UID | Default first names | Redirect |
|---|---|---|---|
| ASC | `7426e127-ded5-4319-8edb-da9f9556a49e` | owen, ella, sarah | `https://asc.agsv.com` |
| GXB | `5891fbc9-ef50-46a2-9cad-c7c6221700bf` | ask | `https://gxb.vc` |

2026-09-06 test on `agsvhq.com` used **alex@ / jordan@** because the agent invented them. Wrong. Next ASC boxes are owen / ella / sarah. Leave alex/jordan; do not rename a live box.

Never send from brand-protection domains (`abeliansecurity.com`, `abeliancouncil.com`, `abeliancollective.com`, `abelianhq.com`) even if they are free. Never use typos (`agsvv.com`). Never use `*.agsv.com` (parent DMARC `p=reject`).

### Execute (after yes)

1. `cloudflare-cli check` the exact list. Drop taken names, show the substitute list, wait if the list changed.
2. `cloudflare-cli register DOMAIN --confirm DOMAIN` one at a time. Poll `status` to `succeeded`.
3. Connect: `inboxkit-cli raw POST /v1/api/cloudflare-domains/connect --workspace UID --data '{"auth_type":"api_token","api_token":"<dns token>","connect_all":false,"domains":["agsvhq.com"]}'`
   (`api_token` is required when `auth_type` is `api_token`. Top up wallet first if credits are 0: dashboard billing portal `GET /v1/api/billing/portal` or `POST /v1/api/credits` — probe docs.inboxkit.com `/add-credits-to-wallet-18118396e0`.)
4. `POST /v1/api/mailboxes/buy` with `mailboxes[].first_name`, `last_name`, `email`, `platform: "MICROSOFT"`. Empty body → `mailboxes is required`. Buy before domain connect → `No domains found`.
5. `POST` warmup add on those mailbox UIDs.
6. Apex CNAME/forward to the project URL. The 2026-09-06 forward to asc.agsv.com did not stick — retry and verify.
7. Creds → `~/.config/inboxkit/<domain>-mailboxes.env` mode 600. No passwords in chat.
8. Hook to mailer only after status is `active` (SMTP/IMAP or OAuth).

Workspaces: GXB `5891fbc9-ef50-46a2-9cad-c7c6221700bf`, ASC `7426e127-ded5-4319-8edb-da9f9556a49e`. Team GXB, admin `christian@gxb.vc`.
