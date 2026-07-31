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
- Primary path is `VPN-ALL-AUTO`.
- `VPN-ALL-AUTO` is a `url-test` group built from proxy-provider `stable`, a pre-filtered raw URI list served by sub-preprocessor at `http://192.168.1.2:7008/stable.txt`.
- If subscription nodes fail health or dialing, fallback goes to `VPN`, which is the direct `awg2` path.

### WARP Path

- `RULE-SET,warp` uses `WARP`.
- `WARP` is a `fallback` group.
- Primary path is `WARP-AWG0` bound to interface `awg0`.
- If `WARP-AWG0` fails, fallback goes to `WARP-AWG1` bound to interface `awg1`.

### Telegram

- Telegram is pinned to Belarus (`awg0`) through a single path inside mihomo, with no fallback. `pbr` no longer feeds `Services/telegram.lst` into the `warp` rule set; it fetches it into `telegram.txt` instead, so Telegram domains are absent from `warp.txt` as long as no other warp source carries them. `Subnets/IPv4/telegram.lst` goes to `telegram_ip.txt`. Domains go fake-ip → `RULE-SET,telegram,WARP-AWG0`; native-app connections straight to DC IPs are TPROXY'd into mihomo by `iifname "br-lan" ip daddr @tproxy_ip4 ... tproxy ip to :12342` and matched by `RULE-SET,telegram_ip,WARP-AWG0,no-resolve`. Both target the proxy `WARP-AWG0` directly rather than the `WARP` group. Telegram is not pinned in mihomo `hosts`.
- Order matters: the two `telegram` rules must stay above `RULE-SET,warp`/`RULE-SET,warp_ip`. Nothing in `pbr` subtracts Telegram entries from the warp sources; only rule order keeps a Telegram domain or DC range that one day appears in a warp list from putting Telegram back on the `WARP` group with its unusable `awg1` fallback.
- The `telegram` rule-provider is also listed in `dns.fake-ip-filter` as `RULE-SET,telegram,fake-ip`. This is required, not cosmetic: without it Telegram domains fall through to `MATCH,real-ip` and resolve to Cloudflare addresses (`104.18.x`) that are not members of `tproxy_ip4`, so they would bypass mihomo entirely and hit the ISP-blocked WAN.
- Pinning instead of falling back is deliberate. `awg1` answers the `WARP` group's `cp.cloudflare.com` probe with 204 but cannot carry Telegram TCP, so including it in Telegram's path would turn an `awg0` outage into a silent hang. With the pin, Telegram fails loudly when `awg0` is down, while the other `warp` domains keep the `awg0` → `awg1` fallback and Viber ranges stay on the group via `RULE-SET,warp_ip,WARP,no-resolve`.
- The previous split design is gone: firewall rule `mark_warp_domains` (mark `0x3`), ipset `warp_domains`, ip rule `fwmark 0x3 lookup warp`, `table warp` and hotplug script `/etc/hotplug.d/iface/40-warp` were all removed. Telegram routing is now decided only by mihomo rules, never by kernel policy routing. `no-resolve` on both IP rules keeps mihomo from resolving every unmatched domain just to test an IP set.
- Direct WAN to Telegram's DC ranges is blocked by the ISP, so a tunnel is required. `awg0` carries Telegram; `awg1` does not — verified by A/B through mihomo's own dialer (the same requests forced out `WARP-AWG0` vs `WARP-AWG1`): `web.telegram.org`, `t.me` and a raw DC IP return 200/302 via `awg0` and time out after 20s via `awg1`. Do not re-verify with `curl --interface awg1`: `awg1` and `awg2` both carry `172.16.0.2/32`, so source-address binding does not reliably select the tunnel. ICMP is also not a valid probe — Telegram DCs drop it even on a path that carries TCP fine.
- `awg0`'s peer endpoint is configured as the literal LAN address `192.168.1.2`, not `labile.cc`. That hostname resolves to `192.168.1.2` through the dnsmasq override but to the router's own WAN address publicly, so if the ifup-time resolver ever answers with the public record the tunnel would point at the router itself and receive nothing. This lives only in router UCI (`network.@amneziawg_awg0[0].endpoint_host`) and is not tracked in this repository, so nothing here enforces it.
- An on-router `tg-ws-proxy` (SOCKS5 `:17023`, MTProto↔WebSocket bridge, spatiumstas/tg-ws-proxy-go) also runs as an optional per-client path, but is not required now that Telegram routes via awg0.

### Direct Path

- `MATCH,DIRECT` handles everything not matched by the `vpn`, `telegram`, `telegram_ip`, `warp` or `warp_ip` rule sets.

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
- `/tmp/mihomo/rules/telegram.txt`
- `/tmp/mihomo/rules/telegram_ip.txt`
- `/tmp/mihomo/rules/warp_ip.txt`
- `/tmp/mihomo/providers/stable.yaml`

## Important Files In This Repository

- `mihomo/config.yaml` contains the static `mihomo` configuration.
- `mihomo/init.d` contains the procd init script for `mihomo`.
- `mihomo/config` contains the UCI service configuration for `mihomo`.
- `pbr` regenerates the rule-provider files under `/tmp/mihomo/rules` (`vpn`, `warp`, `telegram`, `telegram_ip`, `warp_ip`), rewrites `/etc/nftables.d/99-tproxy.nft` for the current fake-IP subnet, declares and populates the nft set `tproxy_ip4` that TPROXYs Telegram/Viber IPv4 ranges into mihomo, and restarts `mihomo`. It `touch`es every rule-provider file first, which makes the degraded state deterministic. Verified on v1.19.27: a missing `type: file` path does **not** stop mihomo — it starts and serves, logs `initial rule provider <name> error: ... no such file or directory`, and that provider matches nothing, so traffic falls through to `MATCH,DIRECT` instead of the intended tunnel. Also verified: a rule file created *after* mihomo started is picked up without a restart, so recovery does not depend on the `touch`.
- `REFERENCE_MAP.md` maps repository files to router paths and lists external sources.

## Operational Notes

- `.lan` names must stay with `dnsmasq`; they must not be pushed into fake-IP flow.
- Old `/tmp/dnsmasq.d/00_vpn.conf` and `/tmp/dnsmasq.d/00_warp.conf` must not exist. If they reappear, they bypass `mihomo` fake-IP ownership and break reverse mapping.
- Rule-provider format is a contract between `pbr` and `mihomo/config.yaml`. `pbr` emits `+.<domain>` lines for `vpn.txt`, `warp.txt` and `telegram.txt`, and all three providers must stay `behavior: domain`. Do not switch back to `behavior: classical` with `DOMAIN-SUFFIX,` lines: mihomo's `DOMAIN-SUFFIX` matcher is case-sensitive on the query side (`rules/common/domain_suffix.go`) and `withFakeIP` does not lowercase the query name, so a mixed-case lookup like `ChatGPT.com` misses the rule set, falls through `fake-ip-filter` to `MATCH,real-ip`, and returns the real IP. `dnsmasq` caches case-insensitively, so one such query poisons the entry for every case variant until its upstream TTL expires. `behavior: domain` is immune because its matcher lowercases internally. The IP providers `telegram_ip`/`warp_ip` are a separate contract: `pbr` emits bare IPv4 CIDR lines (no `+.` prefix, IPv6 filtered out) and both must stay `behavior: ipcidr`. Format and behaviour must always change together, and `pbr` must be deployed and run before (or with) the config, never the config alone.
- `pbr` writes every generated file atomically (`.tmp` then `mv`): `_process_rule_set` for `vpn`/`warp`/`telegram`, `_install_ip_file` for `telegram_ip`/`warp_ip`, and `_write_tproxy_rules` for the nft include. Keep it that way: `mihomo` hot-reloads the rule files via fsnotify, so an in-place truncating redirect exposes a window where the rule set is empty — `vpn`/`warp`/`telegram` domains then resolve to their real IPs, and an empty IP file additionally propagates into the `tproxy_ip4` nft set.
- The nft include carries its set elements inline, so a bare `fw4 reload` (LuCI edit, port forward, `/etc/init.d/firewall reload`) restores `tproxy_ip4` without rerunning `pbr` — verified: 31 elements before and after a reload with no `pbr` run. Because the file is included into `table inet fw4`, one overlapping CIDR from upstream would otherwise break the whole ruleset at boot, so `pbr` validates the rendered file inside a throwaway table (`nft -c`) and falls back to writing it without inline elements if validation fails. This nft build rejects `flags interval,auto-merge`, so overlaps cannot be merged away — the validation fallback is the only guard.
- Mutable `mihomo` runtime data should stay under `/tmp/mihomo`, not `/etc/mihomo`, to avoid unnecessary flash writes.
- The temporary binary staging path for `mihomo` must not reuse `/tmp/mihomo`, because that path is now the runtime directory.
- Known limitation: `/tmp` is tmpfs, so every reboot wipes `/tmp/mihomo/rules`. The "keeping existing" fallbacks in `pbr` therefore protect a re-run, not a cold boot — on a fresh boot they keep the empty file `touch` just created. If the fetches fail at boot, **all** Telegram breaks, not just some domains: `telegram.txt` is empty so its domains fall through `fake-ip-filter` to `MATCH,real-ip` and get Cloudflare addresses no set covers, and `telegram_ip.txt` is empty too, so raw DC IPs are still TPROXY'd into mihomo (the nft set is restored from the persisted `/etc` file) but then match no rule and land on `MATCH,DIRECT`. Membership in `tproxy_ip4` only delivers a packet *into* mihomo; the routing decision still needs a non-empty rule set. `pbr` deliberately does not overwrite the persisted nft file on a no-data run, so the ranges themselves survive. Shipping a checked-in seed copy of the rule files, or persisting them outside tmpfs, is the fix if this ever bites.
