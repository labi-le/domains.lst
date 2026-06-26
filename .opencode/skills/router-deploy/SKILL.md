---
name: router-deploy
description: Use when deploying this repo's Mihomo/OpenWrt files to the router, copying mihomo/config.yaml, updating the Mihomo binary, restarting router services, or checking router-side status/logs over SSH.
---

# Router Deploy

Use this skill for router-facing operations. Router writes, service restarts, and binary replacement affect a live shared device; handle them carefully.

## Repo To Router Map

- `mihomo/config.yaml` -> `/etc/mihomo/config.yaml`
- `mihomo/init.d` -> `/etc/init.d/mihomo`
- `mihomo/config` -> `/etc/config/mihomo`
- `pbr` -> `/etc/init.d/pbr`
- `fetch-mihomo.sh` and `mihomo-fetch-router` produce a binary to stage as `/tmp/mihomo.bin`.

Runtime paths on the router:

- `/tmp/mihomo/cache.db`
- `/tmp/mihomo/rules/vpn.txt`
- `/tmp/mihomo/rules/warp.txt`
- `/tmp/mihomo/providers/*.yaml`

Never use `/tmp/mihomo` as a temporary binary filename; it is the runtime directory.

## Safety Gate

Before any router write, confirm the target host/path unless the current user message explicitly includes the exact deploy action and target.

Router writes include:

- `scp` to the router.
- Replacing `/usr/bin/mihomo`.
- Restarting or enabling services.
- Writing files under `/etc`, `/usr/bin`, or `/tmp` on the router.

Read-only SSH checks are allowed when needed.

## Config Deploy Workflow

Validate locally first:

```sh
nix-shell --run 'mihomo-yaml-check && mihomo-validate'
```

Deploy config:

```sh
nix-shell --run 'mihomo-deploy-config router:/etc/mihomo/config.yaml'
```

Router-side validation after deploy:

```sh
ssh router '/usr/bin/mihomo -t -d /tmp/mihomo -f /etc/mihomo/config.yaml'
```

Restart only when explicitly requested/confirmed:

```sh
ssh router '/etc/init.d/mihomo restart'
```

## Binary Update Workflow

Fetch latest ARM64 binary and compress it with UPX:

```sh
nix-shell --run 'mihomo-fetch-router linux-arm64 /tmp'
```

Deploy binary:

```sh
bin="$(nix-shell --run 'mihomo-fetch-router linux-arm64 /tmp')"
scp "$bin" router:/tmp/mihomo.bin
ssh router 'cp /tmp/mihomo.bin /usr/bin/mihomo && chmod 755 /usr/bin/mihomo'
```

Verify version:

```sh
ssh router '/usr/bin/mihomo -v'
```

Restart only when explicitly requested/confirmed:

```sh
ssh router '/etc/init.d/mihomo restart'
```

## Useful Read-Only Checks

```sh
ssh router 'ss -ltnup 2>/dev/null | grep -E "12342|12344"'
ssh router 'logread | grep mihomo | grep -E "RuleSet\(vpn\)|RuleSet\(warp\)|using VPN-PREFERRED|using WARP|using DIRECT"'
ssh router 'ls -lh /tmp/mihomo/cache.db /tmp/mihomo/rules/vpn.txt /tmp/mihomo/rules/warp.txt /tmp/mihomo/providers/'
```

## Reporting

Always report:

- Local validation result.
- Router-side validation result if a deploy happened.
- Whether a service restart was performed.
- Any warnings from `mihomo -t` or `logread`.
