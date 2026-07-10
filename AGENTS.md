# AGENTS.md

This repository manages OpenWrt router networking files, primarily Mihomo configuration, rule generation, and helper scripts.

## Project Map

- `mihomo/config.yaml` -> router `/etc/mihomo/config.yaml`
- `mihomo/init.d` -> router `/etc/init.d/mihomo`
- `mihomo/config` -> router `/etc/config/mihomo`
- `pbr` -> router `/etc/init.d/pbr`
- `shell.nix` -> local dev shell for validation, config deploy helpers, and router Mihomo binary fetching
- `fetch-mihomo.sh` -> downloads latest upstream Mihomo binary for the router architecture and optionally compresses it with UPX
- `MIHOMO_INSTALL.md` -> install, validation, deploy, and verification workflow
- `REFERENCE_MAP.md` -> repo-to-router mapping and external source URLs
- `ARCHITECTURE.md` -> DNS, fake-IP, TPROXY, and routing design

## Project Skills

Use these project-local skills when their domain matches the task:

### `mihomo-config-review`

Use for any work involving `mihomo/config.yaml`, including proxy providers, proxy groups, rule providers, DNS fake-IP, health checks, and routing behavior.

Expected workflow:

1. Read the relevant config section.
2. Check references between providers, groups, rules, and fake-IP filters.
3. Validate locally with:

   ```sh
   nix-shell --run 'yq "." mihomo/config.yaml >/dev/null && mihomo -t -d /tmp/mihomo -f mihomo/config.yaml'
   ```

4. Report warnings from `mihomo -t` instead of hiding them.

### `mihomo-docs`

Use for questions about Mihomo behavior or syntax: `url-test`, `fallback`, `proxy-providers`, `rule-providers`, DNS `fake-ip`, health checks, `expected-status`, `lazy`, `timeout`, `tolerance`, and related settings.

Expected workflow:

1. Query current Mihomo documentation first.
2. Read the relevant local config section.
3. Explain both the general Mihomo behavior and the concrete effect in this repo.

### `router-deploy`

Use for router-facing operations: SCP, SSH, copying config, replacing the Mihomo binary, restarting services, or checking router status/logs.

Safety rules:

- Validate locally before any deploy.
- Confirm live router writes/restarts unless the current user message explicitly includes the exact deploy action and target.
- Never use `/tmp/mihomo` as a temporary binary path; it is the runtime directory. Use `/tmp/mihomo.bin` for binary staging.

Useful commands:

```sh
nix-shell --run 'mihomo-yaml-check && mihomo-validate'
nix-shell --run 'mihomo-deploy-config router:/etc/mihomo/config.yaml'
nix-shell --run 'mihomo-fetch-router linux-arm64 /tmp'
```

## Current Routing Intent

- `RULE-SET,vpn` routes to `VPN-PREFERRED`.
- `VPN-PREFERRED` first uses `VPN-ALL-AUTO`, then falls back to `VPN` on `awg2`.
- `VPN-ALL-AUTO` is a `url-test` group over providers `aetris`, `mifa`, and `purple`.
- `RULE-SET,warp` routes to `WARP`, which falls back from `WARP-AWG0` (`awg0`) to `WARP-AWG1` (`awg1`). `awg0` is primary because Cloudflare WARP (`awg1`) cannot reach Telegram web/API frontends.
- Telegram web domains are pinned in mihomo `hosts` to `149.154.167.99`; this bypasses fake-IP and reaches `awg0` through the `warp_domains` set. Other Telegram domains stay on the `RULE-SET,warp` path.
- `MATCH,DIRECT` remains the final rule.

## Verification Expectations

For config changes, run:

```sh
nix-shell --run 'mihomo-validate'
```

For shell script changes, run ShellCheck when available:

```sh
nix-shell -p shellcheck --run 'shellcheck fetch-mihomo.sh'
```

For Nix changes, run:

```sh
nix-instantiate --parse shell.nix
```

If an LSP server is unavailable, explicitly report that limitation.

## Router Safety

Router commands may affect live networking. Prefer read-only checks unless deploy/restart is explicitly requested. Always report whether a command was local-only or touched the router.
