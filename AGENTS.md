# AGENTS.md

This repository manages OpenWrt router networking files, primarily the murmur proxy configuration, rule generation, and helper scripts.

## Project Map

murmur is the router's proxy. It replaced mihomo on 2026-11-03 and took over the
same ports (DNS `12344`, tproxy `12342`), so nftables and dnsmasq are unchanged.
The mihomo files are kept in this repository for reference only and are not deployed.

- `murmur/config.yaml` -> router `/etc/murmur/config.yaml`
- `murmur/init.d` -> router `/etc/init.d/murmur`
- `murmur/config` -> router `/etc/config/murmur`
- `pbr` -> router `/etc/init.d/pbr`
- `proxy-ctl.sh` -> router `/root/proxy-ctl.sh`
- `shell.nix` -> local dev shell for validation and config deploy helpers
- `fetch-murmur.sh` -> downloads the release binary, compresses it for flash with xz, and prints the checksum
- `fetch-mihomo.sh` -> legacy; mihomo is no longer deployed
- `MIHOMO_INSTALL.md` -> legacy install notes for mihomo
- `REFERENCE_MAP.md` -> repo-to-router mapping and external source URLs
- `ARCHITECTURE.md` -> DNS, fake-IP, TPROXY, routing, and binary storage design

## Project Skills

Use these project-local skills when their domain matches the task:

### `murmur-config-review`

Use for any work involving `murmur/config.yaml`, including proxy providers, proxy groups, rule providers, DNS fake-IP, health checks, and routing behavior.

Expected workflow:

1. Read the relevant config section.
2. Check references between providers, groups, rules, and fake-IP filters.
3. Validate locally with:

   ```sh
   nix-shell --run 'yq "." murmur/config.yaml >/dev/null'
   ```

4. Report any reference that points at a provider, group or rule file that does not exist.

### `murmur-docs`

Use for questions about murmur behavior or syntax: `url-test`, `fallback`, `proxy-providers`, `rule-providers`, DNS `fake-ip`, health checks, `expected-status`, `lazy`, `timeout`, `tolerance`, and related settings.

Expected workflow:

1. Query current murmur documentation first.
2. Read the relevant local config section.
3. Explain both the general behavior and the concrete effect in this repo.

### `router-deploy`

Use for router-facing operations: SCP, SSH, copying config, replacing the murmur binary, restarting services, or checking router status/logs.

Safety rules:

- Validate locally before any deploy.
- Confirm live router writes/restarts unless the current user message explicitly includes the exact deploy action and target.
- Never use `/tmp/murmur.d` as a temporary binary path; it is the runtime directory. Use `/tmp/murmur.bin` for binary staging.
- The rule lists live in `/tmp/murmur.d/rules` on purpose: they are refetched weekly and must not cost a flash erase cycle. The proxy watches them and reloads them on change, so a pbr run does not need a restart.
- The binary is 25 MB and the overlay has about 12 MB free: replace it as the compressed copy at `/etc/proxy/murmur.bin.xz`, never as a raw file in flash.
- Update the SHA-256 in `/etc/init.d/murmur` when the binary changes, or the init script will refuse to run it.

Useful commands:

```sh
nix-shell --run 'murmur-yaml-check'
nix-shell --run 'murmur-deploy-config router:/etc/murmur/config.yaml'
nix-shell --run 'murmur-fetch-router linux-arm64 /tmp --pack'
ssh router '/root/proxy-ctl.sh check'
```

## Current Routing Intent

- `RULE-SET,vpn` routes to `VPN`.
- `VPN` is a `fallback` group: `VPN-ALL-AUTO` first, then the direct `awg2` path.
- `VPN-ALL-AUTO` is a `url-test` group over the proxy-provider `stable`.
- `RULE-SET,warp` routes to `WARP`, which falls back from `WARP-AWG0` (`awg0`) to `WARP-AWG1` (`awg1`) and then `VPN`.
- Telegram is routed through Belarus (`awg0`): in the `warp` rule set (pbr `Services/telegram.lst` for domains, `Subnets/IPv4/telegram.lst` for the `tproxy_ip4` IP set) → `RULE-SET,warp` → `WARP` (primary `WARP-AWG0`), and direct-to-DC-IP traffic is matched by `tproxy_ip4` → TPROXY → awg0. Not pinned in `hosts`. Direct WAN to Telegram is ISP-blocked and `awg1` cannot reach Telegram, so `awg0` is primary/required. An optional on-router `tg-ws-proxy` (SOCKS5 `:17023`) also exists.
- `MATCH,DIRECT` remains the final rule.

## Verification Expectations

For config changes, run:

```sh
nix-shell --run 'murmur-yaml-check'
```

For shell script changes, run ShellCheck when available:

```sh
nix-shell -p shellcheck --run 'shellcheck fetch-murmur.sh proxy-ctl.sh pbr'
```

For Nix changes, run:

```sh
nix-instantiate --parse shell.nix
```

If an LSP server is unavailable, explicitly report that limitation.

## Router Safety

Router commands may affect live networking. Prefer read-only checks unless deploy/restart is explicitly requested. Always report whether a command was local-only or touched the router.
