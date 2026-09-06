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

Trigger: "spin up cold email for X at N/day". **Quote only** until Christian says yes to the printed list and price.

Quote tools: `cloudflare-cli check`, this file, `inboxkit-cli account`. Do **not** fetch docs.inboxkit.com, do not probe `/v1/api/*`, do not invent names, do not register.

### Sizing

- 25 cold sends/mailbox/day. Mailboxes = `ceil(N / 25)`.
- **Max 3 Microsoft mailboxes per domain.** Use 2 if volume does not fill 3 (100/day = 4 boxes = 2 domains × 2 names). Christian may ask; answer with that math.
- Domains = `ceil(mailboxes / names_per_domain)`. Spare warming pool only if he asked.
- `.com` only. `cloudflare-cli` buys them. InboxKit does **not** register (double-buy).

### One Cloudflare account = one InboxKit workspace (not one zone)

Multiple **zones/domains** in one workspace are fine. What InboxKit forbids is linking **one Cloudflare account to two workspaces** (`ACCOUNT_ALREADY_USED` / 409). Disconnect is refused while any mailbox exists.

2026-09-06 we deleted the empty extra workspace and renamed the remaining one **GXB** (`7426e127-ded5-4319-8edb-da9f9556a49e`). That is the only workspace. Tag domains/mailboxes `asc` or `sites` for filtering. Do not create a second workspace. Member access is the only real downside of one bucket (a guest would see every inbox).

Connect uses the Zone DNS token in `~/.config/inboxkit/cloudflare-dns.env` (not the registrar token). **The token must include All zones** (or every new zone). A token scoped to `agsvhq.com` only makes connect say "Domain not found in your Cloudflare zones" even though the zone exists. After buying a domain, wait until it appears in `GET /zones` *and* the token covers it. Never print the token. Cloudflare Registrar **locks nameservers**; do not try InboxKit's own NS as a workaround.

### Prices (live 2026-09-06; re-check domains)

- Domain **$10.46/yr** (`cloudflare-cli check`, max 20 names).
- Microsoft mailbox **3 credits = $3** one-shot (not the $2.50 marketing number).
- Warmup **$3/mailbox/mo**.
- SMTP/IMAP 404 until mailbox `active` (`processing`/`scheduled` can last hours).

### Quote template (fill and stop)

```
Volume: N emails/day
Mailboxes: ceil(N/25) Microsoft, NAMES_PER_DOMAIN per domain
Domains: K × $10.46 = $YEAR1  (list them, live-checked)
InboxKit now: M × $3 credits = $NOW
Monthly: M×$3 boxes + M×$3 warmup = $MO/mo
Names: first names only from the table; last names = ask if missing
Workspace: GXB `7426e127-ded5-4319-8edb-da9f9556a49e` (only workspace; tag the project)
Redirect: project URL
Say yes to this list and I will buy.
```

Example 100/day, 2 names: 4 boxes, 2 domains, ~$21 year-1 + $12 credits + $24/mo.
Example 2500/day, 3 names: 100 boxes, 34 domains, ~$356 year-1 + $300 credits + $600/mo.

### Names — do not invent

| Project | Tag | First / last | Redirect |
|---|---|---|---|
| ASC | `asc` | owen Gilleran; ella (ask last); sarah (ask last) | `https://asc.agsv.com` |
| GXB / sites | `sites` | sarah Genco, katie Bureau (bella if a 3rd) | `https://sites.gxb.vc` |

One workspace UID for all: `7426e127-ded5-4319-8edb-da9f9556a49e` (named GXB). `agsvhq.com` already has invented alex/jordan — leave them.

Never send from `abeliansecurity.com`, `abeliancouncil.com`, `abeliancollective.com`, `abelianhq.com`. No typos. No `*.agsv.com` (DMARC `p=reject`). No `*.gxb.vc` as From (protects the real domain).

### Execute (after yes to the exact list)

1. Re-`check` if the list aged. Substitutes need a new yes.
2. `cloudflare-cli register DOMAIN --confirm DOMAIN` one at a time. Poll `status` to `succeeded`.
3. Confirm the DNS token lists the new zone (`GET /zones` with that token). If not, widen it in the Cloudflare dashboard (All zones) before connect. Then: `inboxkit-cli raw POST /v1/api/cloudflare-domains/connect --workspace 7426e127-ded5-4319-8edb-da9f9556a49e --data '{"auth_type":"api_token","api_token":"<dns token>","connect_all":false,"domains":["example.com"]}'`. Tag `asc` or `sites`. 409 = someone created a second workspace; do not. "Domain not found in your Cloudflare zones" = token still zone-scoped.
4. Top up if credits remaining < 3×mailboxes: `POST /v1/api/billing/wallet` `{"credits":N,"direct_charge":true}` ($1 = 1 credit, card on file). Then `POST /v1/api/mailboxes/buy` with first_name, last_name, email, platform `MICROSOFT`. Buy before connect → `No domains found`.
5. Add warmup on those UIDs.
6. Apex forward to the redirect URL. Verify it stuck (2026-09-06 ASC forward needed a retry).
7. Creds → `~/.config/inboxkit/<domain>-mailboxes.env` mode 600. No passwords in chat.
8. Mailer only after status `active`.
