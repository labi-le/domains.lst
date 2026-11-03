# Architecture

## Overview

- `dnsmasq` remains the LAN-facing resolver on port `53` and keeps DHCP, `.lan` records, and explicit domain overrides.
- `murmur` owns external fake-IP handling, transparent proxy interception, proxy-provider selection, and outbound routing policy. It replaced `mihomo` on 2026-11-03.
- `stubby` remains the local upstream DNS resolver used by `murmur`.

## Traffic Flow

### DNS

1. LAN client sends DNS query to `dnsmasq` on `:53`.
2. Local `.lan` names and static dnsmasq rules are answered by `dnsmasq` itself.
3. Generic upstream DNS is forwarded by `dnsmasq` to `murmur` on `127.0.0.1:12344`.
4. `murmur` resolves upstream names through `stubby` on `127.0.0.1:5453`.
5. For external domains in fake-IP flow, `murmur` returns an address from `198.18.1.0/24`.

The DNS listener opens before the rule-providers finish loading, so the first queries
are answered by `MATCH,real-ip`. `dnsmasq` then pins that real address for the
whole upstream TTL, and for those minutes the domain never reaches the proxy at
all. The init script therefore flushes the `dnsmasq` cache twice after startup:
once as soon as the DNS port answers, and once more a few seconds later.

### Transparent Proxy

1. Client connects to a fake-IP address from `198.18.1.0/24`.
2. `nftables` marks and TPROXY-redirects that traffic to `murmur` on `:12342`.
3. `murmur` restores the original domain from its fake-IP mapping.
4. `murmur` applies routing rules and selects the outbound path.

### Interfaces

- `awg0`: Belarus VPN
- `awg1`: Cloudflare WARP
- `awg2`: Finland VPN

## Routing

### VPN Path

- `RULE-SET,vpn` routes to `VPN`.
- `VPN` is a `fallback` group: `VPN-ALL-AUTO` first, then the direct `awg2` path.
- `VPN-ALL-AUTO` is a `url-test` group over the proxy-provider `stable`.
- The `stable` provider is a pre-filtered list served by the sub-preprocessor on the
  LAN host. An empty provider must not degrade to `COMPATIBLE`, which would egress
  the VPN domains straight to the WAN, so `empty-fallback` is `REJECT`.
- The health probe is `https://platform.claude.com/`, not `cp.cloudflare.com`: a
  Cloudflare probe reports healthy while nothing else passes.

### WARP Path

- `RULE-SET,warp` routes to `WARP`.
- `WARP` is a `fallback` group over `WARP-AWG0` (awg0), `WARP-AWG1` (awg1) and `VPN`.
- The probe URL is `http://captive.apple.com/`, off-net on purpose.
- The timeout is 12000 ms: awg0 answers the probe in 5.9-7.3s and sometimes not at
  all inside 10s, while carrying Telegram traffic at 0.07s, so the implicit 5000 ms
  would retire the healthier rung.

### Telegram

- Telegram is routed through Belarus (`awg0`). `pbr` puts it in the `warp` rule set: `Services/telegram.lst` feeds `warp.txt` (domains) and `Subnets/IPv4/telegram.lst` feeds the `tproxy_ip4` IP set. So Telegram domains go fake-ip → `RULE-SET,warp` → `WARP` (primary `WARP-AWG0` = awg0), and native-app connections straight to DC IPs are matched by `tproxy_ip4` → TPROXY → awg0. It is not pinned in `hosts`.
- Direct WAN to Telegram's DC ranges is blocked by the ISP (verified: router-originated direct connect to every range times out), so a tunnel is required. `awg0` (Belarus) reaches Telegram; `awg1` (Cloudflare WARP) does not (verified per-tunnel), so `WARP-AWG0` stays primary.
- An on-router `tg-ws-proxy` (SOCKS5 `:17023`, MTProto↔WebSocket bridge, spatiumstas/tg-ws-proxy-go) also runs as an optional per-client path, but is not required now that Telegram routes via awg0.

### Direct Path

- `MATCH,DIRECT` handles everything not matched by `vpn` or `warp` rules.

## Storage

Two kinds of state, kept apart on purpose:

**On flash (survives a reboot, written rarely):**

- `/usr/bin/murmur`: the binary, a normal executable
- `/etc/murmur/config.yaml`, `/etc/init.d/murmur`, `/etc/config/murmur`
- `/etc/nftables.d/99-tproxy.nft`: the TPROXY rules, rendered by pbr

**In tmpfs (wiped on reboot, written often):**

- `/tmp/murmur.d/rules/*.txt`: the rule lists, refetched by pbr
- `/tmp/murmur.d/providers/*.yaml`: the proxy-provider cache
- `/tmp/murmur.d/cache.db`

The rule lists change weekly and grow to tens of kilobytes; writing them to flash
every week costs erase cycles for no benefit. They live in tmpfs and are refetched.

The binary has to be present before the network is up, so it lives on flash like any
other package. It only fits because it is built without `extra-protocols`: that
drops 17 transport crates and, with them, the hysteria/hysteria2, anytls, tuic,
mieru, openvpn, shadowquic and snell outbounds. The subscription's vless, ss and
vmess nodes are unaffected.

## Static Vs Runtime

### Static

- `/etc/murmur/config.yaml`
- `/etc/init.d/murmur`
- `/etc/config/murmur`
- `/etc/init.d/pbr`
- `/etc/config/dhcp`
- `/etc/config/firewall`
- `/etc/nftables.d/99-tproxy.nft`
- `/usr/bin/murmur`

### Runtime

- `/tmp/murmur.d/cache.db`
- `/tmp/murmur.d/rules/*.txt`
- `/tmp/murmur.d/providers/*.yaml`

## Important Files In This Repository

- `murmur/config.yaml` contains the static `murmur` configuration.
- `murmur/init.d` contains the procd init script for `murmur`.
- `murmur/config` contains the UCI service configuration for `murmur`.
- `pbr` regenerates the rule files under `/tmp/murmur.d/rules`, rewrites `/etc/nftables.d/99-tproxy.nft` for the current fake-IP subnet, and refreshes the TPROXY IP set.
- `proxy-ctl.sh` is the admin helper for status, health checks, restarts and rule refreshes.
- `fetch-murmur.sh` downloads the release binary, compresses it for flash and prints the checksum.
- `REFERENCE_MAP.md` maps repository files to router paths and lists external sources.

## Operational Notes

- `.lan` names must stay with `dnsmasq`; they must not be pushed into fake-IP flow.
- Old `/tmp/dnsmasq.d/00_vpn.conf` and `/tmp/dnsmasq.d/00_warp.conf` must not exist. If they reappear, they bypass `murmur` fake-IP ownership and break reverse mapping.
- Mutable `murmur` runtime data stays under `/tmp/murmur.d`, not `/etc/murmur`, to avoid unnecessary flash writes.
- After a reboot the rule files are empty until pbr has refetched them. pbr runs first (`START=97`) and the proxy second (`START=98`): a proxy started earlier would match nothing and send every proxied domain to `MATCH,DIRECT`. Measured on this router: the gap between the proxy starting and pbr finishing was about 25 seconds.
- murmur watches the rule files and reloads them by itself, so a later pbr run does not need a restart. The log line is `[Provider] <name>'s content update`.
- pbr reads `/etc/murmur/config.yaml` directly. It must not ask which process holds the tproxy port: it runs before the proxy does.
- The temporary binary staging path must not reuse `/tmp/murmur.d`, because that path is the runtime directory.
