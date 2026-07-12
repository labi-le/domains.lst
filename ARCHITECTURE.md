# Architecture

## Overview

- `dnsmasq` remains the LAN-facing resolver on port `53` and keeps DHCP, `.lan` records, and explicit domain overrides.
- `mihomo` owns external fake-IP handling, transparent proxy interception, proxy-provider selection, and outbound routing policy.
- `stubby` remains the local upstream DNS resolver used by `mihomo`.

## Traffic Flow

### DNS

1. LAN client sends DNS query to `dnsmasq` on `:53`.
2. Local `.lan` names and static dnsmasq rules are answered by `dnsmasq` itself.
3. Generic upstream DNS is forwarded by `dnsmasq` to `mihomo` on `127.0.0.1:12344`.
4. `mihomo` resolves upstream names through `stubby` on `127.0.0.1:5453`.
5. For external domains in fake-IP flow, `mihomo` returns an address from `198.18.1.0/24`.

### Transparent Proxy

1. Client connects to a fake-IP address from `198.18.1.0/24`.
2. `nftables` marks and TPROXY-redirects that traffic to `mihomo` on `:12342`.
3. `mihomo` restores the original domain from its fake-IP mapping.
4. `mihomo` applies routing rules and selects the outbound path.

### Interfaces

- `awg0`: Belarus VPN
- `awg1`: Cloudflare WARP
- `awg2`: Finland VPN

## Routing

### VPN Path

- `RULE-SET,vpn` uses `VPN-PREFERRED`.
- `VPN-PREFERRED` is a `fallback` group.
- Primary path is `VPN-SUB-EU`.
- `VPN-SUB-EU` is a `url-test` group built from proxy-provider `mos-eu`.
- Country filter currently allows:
  `Estonia`, `Finland`, `Lithuania`, `Latvia`, `Poland`, `Germany`, `Netherlands`, `Czechia`, `Sweden`, `Norway`, `Denmark`.
- If subscription nodes fail health or dialing, fallback goes to `VPN`, which is the direct `awg2` path.

### WARP Path

- `RULE-SET,warp` uses `WARP`.
- `WARP` is a `fallback` group.
- Primary path is `WARP-AWG0` bound to interface `awg0`.
- If `WARP-AWG0` fails, fallback goes to `WARP-AWG1` bound to interface `awg1`.

### Telegram

- Telegram is routed through Belarus (`awg0`). `pbr` puts it in the `warp` rule set: `Services/telegram.lst` feeds `warp.txt` (domains) and `Subnets/IPv4/telegram.lst` feeds the `warp_domains` IP set. So Telegram domains go fake-ip → `RULE-SET,warp` → `WARP` (primary `WARP-AWG0` = awg0), and native-app connections straight to DC IPs are marked `0x3` via `warp_domains` → `table warp` → awg0. It is not pinned in mihomo `hosts`.
- Direct WAN to Telegram's DC ranges is blocked by the ISP (verified: router-originated direct connect to every range times out), so a tunnel is required. `awg0` (Belarus) reaches Telegram; `awg1` (Cloudflare WARP) does not (verified per-tunnel), so `WARP-AWG0` stays primary.
- An on-router `tg-ws-proxy` (SOCKS5 `:17023`, MTProto↔WebSocket bridge, spatiumstas/tg-ws-proxy-go) also runs as an optional per-client path, but is not required now that Telegram routes via awg0.

### Direct Path

- `MATCH,DIRECT` handles everything not matched by `vpn` or `warp` rules.

## Static Vs Runtime

### Static

- `/etc/mihomo/config.yaml`
- `/etc/init.d/mihomo`
- `/etc/config/mihomo`
- `/etc/init.d/pbr`
- `/etc/config/dhcp`
- `/etc/config/firewall`
- `/etc/nftables.d/99-tproxy.nft`

### Runtime

- `/tmp/mihomo/cache.db`
- `/tmp/mihomo/rules/vpn.txt`
- `/tmp/mihomo/rules/warp.txt`
- `/tmp/mihomo/providers/mos-eu.yaml`

## Important Files In This Repository

- `mihomo/config.yaml` contains the static `mihomo` configuration.
- `mihomo/init.d` contains the procd init script for `mihomo`.
- `mihomo/config` contains the UCI service configuration for `mihomo`.
- `pbr` regenerates rule-provider files under `/tmp/mihomo/rules`, rewrites `/etc/nftables.d/99-tproxy.nft` for the current fake-IP subnet, refreshes the WARP IP set, and restarts `mihomo`.
- `REFERENCE_MAP.md` maps repository files to router paths and lists external sources.

## Operational Notes

- `.lan` names must stay with `dnsmasq`; they must not be pushed into fake-IP flow.
- Old `/tmp/dnsmasq.d/00_vpn.conf` and `/tmp/dnsmasq.d/00_warp.conf` must not exist. If they reappear, they bypass `mihomo` fake-IP ownership and break reverse mapping.
- Mutable `mihomo` runtime data should stay under `/tmp/mihomo`, not `/etc/mihomo`, to avoid unnecessary flash writes.
- The temporary binary staging path for `mihomo` must not reuse `/tmp/mihomo`, because that path is now the runtime directory.
