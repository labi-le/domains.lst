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

- `awg0`: Belarus VPN, own server, address `10.8.1.3/32`, peer endpoint `192.168.1.2:27748`. Not WARP (`cdn-cgi/trace` reports `warp=off`, egress `178.120.56.133`, `loc=BY`).
- `awg1`: Cloudflare WARP, peer `bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=`, direct endpoint `8.39.214.16:2408`, address `172.16.0.2/32`. Egress `104.28.196.105`, `colo=HEL`, `loc=RU`. This is `WARP-AWG1`, the only WARP path mihomo uses.
- `awg2`: also Cloudflare WARP with the same peer key, but reached through a Finland relay (`fi.tribukvy.ltd`, `45.128.235.30:1002`), so its egress is `104.28.222.16`, `loc=FI`. Nothing in mihomo references it since the VPN path became subscription-only.
- `awg2` was moved off `172.16.0.2/32` to `172.16.0.3/32`. Every Cloudflare WARP profile ships that same IPv4, so `awg1` and `awg2` used to hold one address on two live interfaces. The relay behind `awg2` accepts a different client address — verified, the tunnel handshakes and passes traffic on `172.16.0.3`. A direct Cloudflare endpoint may not be as forgiving, so do not assume this transfers to `awg1`. The per-client IPv6 was already unique and is unchanged.
- The WARP egress geolocation follows the client's source address, not the endpoint. The router's own WAN, `93.100.194.40`, geolocates as `loc=RU`, which is why `awg1` gets an `RU` egress; swapping it onto a different Cloudflare endpoint moved the colo `LED` to `HEL` and changed nothing else. `awg2` gets an `FI` egress only because it reaches Cloudflare from a Finnish relay. `BY` appears solely on `awg0`, which does not use WARP at all.
- `awg1`, `awg2` and `awg0` keys and endpoints live only in router UCI (`/etc/config/network`). Nothing in this repository tracks or enforces them. A UCI snapshot is kept on the router at `/root/uci-backups/`.

## Routing

### VPN Path

- `RULE-SET,vpn` uses `VPN-ALL-AUTO`.
- `VPN-ALL-AUTO` is a `url-test` group built from proxy-provider `stable`, a pre-filtered raw URI list served by sub-preprocessor at `http://192.168.1.2:7008/stable.txt`.
- There is no fallback outside the subscription. If the provider yields no nodes, `empty-fallback: REJECT` resolves the group to `REJECT`; if every node fails its health check, the dial to the selected node fails. Either way `vpn` domains never reach the WAN directly.

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
- Direct WAN to Telegram's DC ranges is blocked by the ISP, so a tunnel is required. `awg0` carries Telegram; `awg1` does not — verified by A/B through mihomo's own dialer (the same requests forced out `WARP-AWG0` vs `WARP-AWG1`): `web.telegram.org`, `t.me` and a raw DC IP return 200/302 via `awg0` and time out after 20s via `awg1`. That dialer A/B is the only measurement this claim rests on. An attempt to re-verify it after `awg1` moved to `8.39.214.16:2408` produced contradictory results and was discarded, so the pin stays on the conservative side rather than on fresh evidence.
- `curl -k https://<telegram-dc-ip>/` is not a usable probe and its results must not be written down as fact. Back-to-back passes disagree on every interface at once, including `awg0`, which demonstrably carries Telegram: one pass reported all three DCs reachable through `awg0`, the next reported two of three dead. Unique per-tunnel addresses did not make it reproducible, so the cause is the probe, not the binding — those addresses do not serve ordinary HTTPS and the result depends on state the probe does not control. ICMP is not valid either; Telegram DCs drop it on paths that carry TCP fine. Use mihomo's own dialer, or real client traffic and the `logread` routing decision.
- Two probe traps that are real and reproducible: names resolve to fake-IP through the local resolver, so `curl --interface if!awgN https://<name>/` times out on *every* interface unless the real address is pinned with `--resolve`; and `curl --interface awgN` binds by source address rather than by device, so it only selects a tunnel when that address is unique. Since `awg2` moved to `172.16.0.3/32` the addresses are distinct and `--interface if!awgN` gives stable, per-tunnel egress readings across repeated passes.
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
- `/etc/mihomo/rules/*.txt` (persisted mirror of the five rule files, seeded back into the workdir at boot)

## Important Files In This Repository

- `mihomo/config.yaml` contains the static `mihomo` configuration.
- `mihomo/init.d` contains the procd init script for `mihomo`.
- `mihomo/config` contains the UCI service configuration for `mihomo`.
- `pbr` regenerates the rule-provider files under `/tmp/mihomo/rules` (`vpn`, `warp`, `telegram`, `telegram_ip`, `warp_ip`), mirrors each installed file to `/etc/mihomo/rules`, rewrites `/etc/nftables.d/99-tproxy.nft` for the current fake-IP subnet, declares and populates the nft set `tproxy_ip4` that TPROXYs Telegram/Viber IPv4 ranges into mihomo, and restarts `mihomo`. It `touch`es every rule-provider file first, which makes the degraded state deterministic. Verified on v1.19.27: a missing `type: file` path does **not** stop mihomo — it starts and serves, logs `initial rule provider <name> error: ... no such file or directory`, and that provider matches nothing, so traffic falls through to `MATCH,DIRECT` instead of the intended tunnel. Also verified: a rule file created *after* mihomo started is picked up without a restart, so recovery does not depend on the `touch`.
- `mihomo/init.d` seeds `$workdir/rules` from `/etc/mihomo/rules` before launching mihomo, copying only persisted files that are non-empty and only over workdir files that are missing or empty, so a fresh `pbr` write is never clobbered.
- `REFERENCE_MAP.md` maps repository files to router paths and lists external sources.

## Operational Notes

- `.lan` names must stay with `dnsmasq`; they must not be pushed into fake-IP flow.
- Old `/tmp/dnsmasq.d/00_vpn.conf` and `/tmp/dnsmasq.d/00_warp.conf` must not exist. If they reappear, they bypass `mihomo` fake-IP ownership and break reverse mapping.
- Rule-provider format is a contract between `pbr` and `mihomo/config.yaml`. `pbr` emits `+.<domain>` lines for `vpn.txt`, `warp.txt` and `telegram.txt`, and all three providers must stay `behavior: domain`. Do not switch back to `behavior: classical` with `DOMAIN-SUFFIX,` lines: mihomo's `DOMAIN-SUFFIX` matcher is case-sensitive on the query side (`rules/common/domain_suffix.go`) and `withFakeIP` does not lowercase the query name, so a mixed-case lookup like `ChatGPT.com` misses the rule set, falls through `fake-ip-filter` to `MATCH,real-ip`, and returns the real IP. `dnsmasq` caches case-insensitively, so one such query poisons the entry for every case variant until its upstream TTL expires. `behavior: domain` is immune because its matcher lowercases internally. The IP providers `telegram_ip`/`warp_ip` are a separate contract: `pbr` emits bare IPv4 CIDR lines (no `+.` prefix, IPv6 filtered out) and both must stay `behavior: ipcidr`. Format and behaviour must always change together, and `pbr` must be deployed and run before (or with) the config, never the config alone.
- `pbr` writes every generated file atomically (`.tmp` then `mv`): `_process_rule_set` for `vpn`/`warp`/`telegram`, `_install_ip_file` for `telegram_ip`/`warp_ip`, and `_write_tproxy_rules` for the nft include. Keep it that way: `mihomo` hot-reloads the rule files via fsnotify, so an in-place truncating redirect exposes a window where the rule set is empty — `vpn`/`warp`/`telegram` domains then resolve to their real IPs, and an empty IP file additionally propagates into the `tproxy_ip4` nft set.
- The nft include carries its set elements inline, so a bare `fw4 reload` (LuCI edit, port forward, `/etc/init.d/firewall reload`) restores `tproxy_ip4` without rerunning `pbr` — verified: 31 elements before and after a reload with no `pbr` run. Because the file is included into `table inet fw4`, one overlapping CIDR from upstream would otherwise break the whole ruleset at boot, so `pbr` validates the rendered file inside a throwaway table (`nft -c`) and falls back to writing it without inline elements if validation fails. This nft build rejects `flags interval,auto-merge`, so overlaps cannot be merged away — the validation fallback is the only guard.
- Mutable `mihomo` runtime data should stay under `/tmp/mihomo`, not `/etc/mihomo`, to avoid unnecessary flash writes. `/etc/mihomo/rules` is the deliberate exception: five small text files rewritten per `pbr` run (weekly by cron) buy a boot that starts with the last known good rule sets instead of a guaranteed `MATCH,DIRECT` window.
- The temporary binary staging path for `mihomo` must not reuse `/tmp/mihomo`, because that path is now the runtime directory.
- `/tmp` is tmpfs, so every reboot wipes `/tmp/mihomo/rules`, and the "keeping existing" fallbacks in `pbr` protect a re-run rather than a cold boot — on a fresh boot they would keep the empty file `touch` just created. The `/etc/mihomo/rules` mirror plus the init-script seed is what closes that window. Without it, a boot whose fetches fail breaks **all** Telegram, not just some domains: `telegram.txt` is empty so its domains fall through `fake-ip-filter` to `MATCH,real-ip` and get Cloudflare addresses no set covers, and `telegram_ip.txt` is empty too, so raw DC IPs are still TPROXY'd into mihomo (the nft set is restored from the persisted `/etc` file) but then match no rule and land on `MATCH,DIRECT`. Membership in `tproxy_ip4` only delivers a packet *into* mihomo; the routing decision still needs a non-empty rule set. The seed only helps after one successful `pbr` run: a first install still boots with empty rule sets.
- `mihomo` opens its DNS listener before its rule-providers finish loading. Measured by busy-polling `:12344` across a restart: the first answer for `chatgpt.com` is the real address `172.64.155.209`, the very next poll is already `198.18.1.4`. During that window `RULE-SET,vpn,fake-ip` matches nothing and `MATCH,real-ip` wins.
- That window is dangerous only because `dnsmasq` caches it, and the retention is wildly asymmetric: `mihomo` hands out a fake IP with a TTL of 1s, while a real answer carries the upstream's own TTL — measured 96s for `example.com` and 300s for `chatgpt.com`. A correct answer is forgotten almost immediately and a wrong one is pinned for minutes, and for those minutes the domain resolves to its real address, is not in `198.18.1.0/24` and not in `tproxy_ip4`, and therefore never enters `mihomo` at all — no rule set, no killswitch, straight out the ISP WAN. Nothing appears in `mihomo`'s log, because the traffic never reaches it.
- The durable fix is `cache-size=0` on the router's `dnsmasq` (UCI `dhcp.@dnsmasq[0].cachesize`), which removes the asymmetry by removing the cache. `mihomo` caches DNS itself, and the domain-scoped forwards to `stubby` and to the LAN resolver at `192.168.1.2#5353` each sit in front of their own cache, so nothing measurable is lost — all three paths answered in 0ms afterwards. Verified additively: `example.org` resolves to its real address through both resolvers, and within 3s of appending `+.example.org` to `vpn.txt` both return `198.18.1.236`; before the change `dnsmasq` kept serving the real address for the rest of its TTL. Like the `awg0` endpoint, this lives only in router UCI and nothing in this repository enforces it. `flush_dns_cache` in `mihomo/init.d` stays for installs that still cache: it waits for the `listen:` port from the config to appear in `netstat -lnu`, then sends `dnsmasq` a `SIGHUP` at +3s and again at +15s.
- Diagnosing this class of bug: compare `dig +short <name> @127.0.0.1 -p 53` with `dig +short <name> @127.0.0.1 -p 12344`. With the cache off the two must agree on every query, so a lasting disagreement is no longer the cache and points at the forward itself. Where a cache is still in play, the poisoned entry's TTL visibly counts down between two `dig` runs and `killall -HUP dnsmasq` clears it immediately.
- The syslog ring buffer has to outlive an incident to be worth anything, and at `log-level: debug` it cannot. Measured: 2463 of 2542 lines were `level=debug`, dominated by per-connection `use specified fingerprint` and `REALITY Authentication` chatter, leaving 17 seconds of history in the stock 64 KiB buffer — not enough to diagnose anything intermittent. `match RuleSet(...) using ...`, the only line that records a routing decision, is `level=info`, so `log-level: info` drops 96% of the volume and keeps every useful record. The buffer is also raised to 512 KiB (UCI `system.@system[0].log_size`). The failed-dial warnings a LAN torrent client generates through `RULE-SET,warp_ip` look noisy in a tail but were only 20 of those lines.
- `tracepath`/`traceroute` cannot work here and their silence is not evidence of a leak. Probes to a fake IP are TPROXY'd in `prerouting` before any TTL processing, so no hop ever answers and every line reads `no reply`. The probes do reach `mihomo` — `[UDP] 192.168.1.3 --> chatgpt.com:44444 match RuleSet(vpn) using VPN-ALL-AUTO` — they just cannot produce a path. To check for a leak, compare the exit address instead: `curl --resolve <name>:443:<fake-ip> https://<name>/cdn-cgi/trace`.
