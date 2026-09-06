# inboxkit-cli

Terminal access to [InboxKit](https://app.inboxkit.com) (cold email infrastructure: domains, mailboxes, warmup). Read-only for domains/mailboxes; can create workspaces. Does not spend money.

## Install

```bash
chmod +x inboxkit-cli
ln -sf "$(pwd)/inboxkit-cli" ~/bin/inboxkit-cli
```

Stdlib Ruby only. No gems, no Gemfile.

## Auth

Reads `INBOXKIT_API_KEY` from the environment, falling back to `~/.config/inboxkit/.env` (simple `KEY=VALUE` lines, one per line, `#` comments allowed):

```
INBOXKIT_API_KEY=eyJhbGci...
INBOXKIT_EMAIL=christian@gxb.vc
INBOXKIT_WORKSPACE_UID=5891fbc9-ef50-46a2-9cad-c7c6221700bf
```

`chmod 600` that file. Env var wins over file if both are set.

`INBOXKIT_WORKSPACE_UID` is the default workspace for `domains`/`mailboxes` commands. Override per call with `--workspace UID`.

## Commands

```bash
inboxkit-cli account                                  # credits, plan, mailbox slots
inboxkit-cli workspaces list [--format json]
inboxkit-cli workspaces show UID [--format json]
inboxkit-cli workspaces create --name NAME [--webhook URL] [--admins-only]
inboxkit-cli domains list [--workspace UID] [--page N] [--limit N] [--format json]
inboxkit-cli mailboxes list [--workspace UID] [--page N] [--limit N] [--format json]
inboxkit-cli raw METHOD PATH [--data JSON] [--query k=v ...] [--workspace UID]
```

### Example output

```
$ inboxkit-cli account
Team:       GXB  (566d8230-055a-4216-8e17-593a00fdb9ca)
Admin:      christian@gxb.vc
Credits:    0 remaining / 0 total (0 used)
Plan:       (none)
Mailbox slots (google):     0/0
Mailbox slots (ms outlook): 0/0
Auto top-up: off

$ inboxkit-cli workspaces list
UID                                   NAME         DOMAINS  TYPE
------------------------------------  -----------  -------  ----
5891fbc9-ef50-46a2-9cad-c7c6221700bf  Prime Pixel        0  user

$ inboxkit-cli domains list
(no domains)
```

`--format json` on any command prints the raw InboxKit API response verbatim.

### raw — the escape hatch

InboxKit's API has ~170 endpoints (warmup, sequencers, InfraGuard, email insights, registrar credentials, etc.). Only the common read paths and workspace creation are wrapped above. Everything else:

```bash
inboxkit-cli raw GET /v1/api/domains/assignable --query workspace_uid=UID
inboxkit-cli raw POST /v1/api/domains/list --workspace UID --data '{"page":1,"limit":50}'
```

## Deliberately not implemented

Anything that spends money or destroys data: domain registration/renewal, mailbox provisioning, credit purchases, subscription changes, workspace delete/archive. Use `raw` if you genuinely need one of these — it will hit the real endpoint, so know what you're doing.

## Docs

Full API reference: https://docs.inboxkit.com

## Test

```bash
ruby test/test_inboxkit-cli.rb
```

Offline — stubs a local TCP server, no network or credentials required.
