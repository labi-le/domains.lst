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

- `RULE-SET,vpn` routes to `VPN-ALL-AUTO`, a `url-test` group over proxy-provider `stable`.
- The VPN path is subscription-only: there is no AmneziaWG fallback behind it and no interface-bound VPN proxy.
- `empty-fallback: REJECT` on `VPN-ALL-AUTO` must stay. The default `COMPATIBLE` is a direct outbound with no interface bind, so an empty `stable` provider (host down, `/tmp` cache lost on reboot) would send `vpn` domains out the raw WAN. `REJECT` makes that an explicit killswitch.
- `RULE-SET,warp` routes to `WARP`, which falls back from `WARP-AWG0` (`awg0`) to `WARP-AWG1` (`awg1`).
- Telegram is pinned to Belarus (`awg0`) via a **single path inside mihomo, with no fallback**. `pbr` fetches `Services/telegram.lst` into `telegram.txt` instead of feeding it to the `warp` set (nothing subtracts Telegram entries from the other warp sources, so rule order is what protects the pin), and `Subnets/IPv4/telegram.lst` into `telegram_ip.txt`. Both route to the proxy `WARP-AWG0` directly, not to the `WARP` group: `RULE-SET,telegram,WARP-AWG0` and `RULE-SET,telegram_ip,WARP-AWG0,no-resolve`, which MUST stay ordered above the `warp` rules. Native-app connections to raw DC IPs reach mihomo because `pbr` TPROXYs the nft set `tproxy_ip4` (Telegram + Viber ranges) to `:12342`. The `telegram` rule-provider must also appear in `dns.fake-ip-filter` as `RULE-SET,telegram,fake-ip`, otherwise Telegram domains fall to `MATCH,real-ip` and resolve to Cloudflare IPs that are absent from `tproxy_ip4`, going straight to the ISP-blocked WAN.
- Pinning is deliberate: `awg1` passes the `WARP` group's `cp.cloudflare.com` probe but cannot carry Telegram TCP, so a fallback there would convert a loud `awg0` failure into a silent hang. Telegram now fails explicitly if `awg0` is down, while the remaining `warp` domains keep the honest `awg0` → `awg1` fallback. Viber IPs stay on the group via `RULE-SET,warp_ip,WARP,no-resolve`.
- The old split path is gone: firewall rule `mark_warp_domains` (mark `0x3`), ipset `warp_domains`, ip rule `fwmark 0x3 lookup warp`, `table warp` and hotplug `/etc/hotplug.d/iface/40-warp` were all removed. An optional on-router `tg-ws-proxy` (SOCKS5 `:17023`) still exists.
- `awg0`'s peer is addressed as `192.168.1.2` directly (UCI `network.@amneziawg_awg0[0].endpoint_host`). Do not set it back to `labile.cc`: that name resolves to `192.168.1.2` via the dnsmasq override but to the router's own WAN IP publicly, so if the ifup-time resolver ever answers with the public record the tunnel points at the router itself and receives nothing. This setting lives only in router UCI and is not tracked in this repository, so nothing here enforces it.
- Rule files are mirrored to `/etc/mihomo/rules` by `pbr` and seeded back into `/tmp/mihomo/rules` by `mihomo/init.d` before mihomo starts. Without that, a reboot leaves every rule-provider empty and all of `vpn`, `warp` and `telegram` fall through to `MATCH,DIRECT` until `pbr` has refetched. The seed never overwrites a workdir file that already has content.
- `mihomo/init.d` sends `dnsmasq` a `SIGHUP` a few seconds after mihomo starts. This is load-bearing, not hygiene: mihomo answers DNS before its rule-providers load, so the first query for a `vpn` domain gets a real address, and `dnsmasq` would pin it for the upstream TTL. While pinned, that domain resolves outside `198.18.1.0/24`, never enters mihomo, and bypasses every rule including the killswitch.
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

## Commit Convention

Hand-written commits in this repo are short, lowercase, imperative, with no trailing period
(0 of 272 subjects end in one) and a median subject of ~16 characters:

```
fix fakeip algo
increase tolerance
route telegram via warp (awg0), drop hosts pin
```

- Keep the subject to one short line. Only 2 of 272 subjects exceed 72 characters.
- A `scope:` prefix (`mihomo:`, `warp:`, `pbr:`) is rare — 5 of 272 — so use it only when the
  change really is confined to one area. Never use Conventional Commits prefixes (`feat:`,
  `chore:`).
- A body is the exception, not the rule: 17 of 272 commits have one, and only 3 use `-` bullets.
  Add one only when the diff cannot show *why*, and keep it to a few lines. Never restate the
  diff or list touched files.
- Ignore the `Update <file>` / `Create <file>` subjects when copying style: those are GitHub
  web-editor defaults, not a convention.

Code comments follow the same rule: explain a non-obvious constraint or consequence, never what
the next line already says.

## Router Safety

Router commands may affect live networking. Prefer read-only checks unless deploy/restart is explicitly requested. Always report whether a command was local-only or touched the router.
