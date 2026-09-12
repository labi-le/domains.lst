# AGENTS.md

This repository manages OpenWrt router networking files, primarily Mihomo configuration, rule generation, and helper scripts.

## Project Map

- `mihomo/config.yaml` -> router `/etc/mihomo/config.yaml`
- `mihomo/init.d` -> router `/etc/init.d/mihomo`
- `mihomo/config` -> router `/etc/config/mihomo`
- `pbr` -> router `/etc/init.d/pbr`
- `shell.nix` -> local dev shell for validation, config deploy helpers, and router Mihomo binary fetching
- `fetch-mihomo.sh` -> downloads latest upstream Mihomo binary for the router architecture and optionally compresses it with UPX
- `zapret-hosts-user-exclude.txt` -> router `/opt/zapret/ipset/zapret-hosts-user-exclude.txt`
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

- `RULE-SET,vpn` routes to `VPN`, a `fallback` group of two rungs: `VPN-ALL-AUTO`, the `url-test` group over proxy-provider `stable`, then `WARP-AWG2` (`awg2`, Cloudflare WARP through a Finland relay).
- `WARP-AWG2` backs the subscription rather than the `WARP` group because it is the only rung the subscription's targets accept, not because of where it exits: measured 2026-09-10, `platform.claude.com` answers `200` over `awg2` and `403` over both `awg0` and `awg1`. Geography is not the reason — `awg0` does not exit in Russia either. Supporting readings from `https://www.cloudflare.com/cdn-cgi/trace` that day: `awg0` is `ip=178.120.2.178 loc=BY warp=off`, `awg1` is `loc=RU warp=on` (WARP geolocates the client's source address, and that is the router's own WAN address `93.100.194.40`; the endpoint `8.39.214.16` belongs to Cloudflare, not to any Russian network), `awg2` is `loc=FI warp=on`. The cover is partial: `chatgpt.com` answers `403` over all three exits, `awg2` included, so the rung degrades `vpn` rather than restoring it. The cause is not established — `awg0` is `warp=off` on a Belarusian address and still draws `403` — so record the observation and do not attribute it to WARP-range blocking.
- `empty-fallback: REJECT` on `VPN-ALL-AUTO` must stay, but it is now the last line rather than the first. An empty `stable` provider makes `VPN-ALL-AUTO` return `REJECT`, whose probe fails with `io.EOF`, so the outer `VPN` group reads that rung as dead and moves to `WARP-AWG2`; the killswitch only fires when `awg2` is dead as well, since a `fallback` group with no live member returns `proxies[0]`. Without `REJECT` the empty provider would degrade to `COMPATIBLE`, a direct outbound with no interface bind, and send `vpn` domains out the raw WAN.
- `RULE-SET,warp` routes to `WARP`, a `fallback` group of three rungs: `WARP-AWG0` (`awg0`, Belarus), `WARP-AWG1` (`awg1`, Cloudflare WARP on a direct endpoint), then `DIRECT`. `awg2` is deliberately not a rung, and not because it carries Telegram badly: measured 2026-09-10 on DC connects (:443, three attempts each) it managed 3/3 to `194.221.250.50` and 2/3 to `91.108.56.130` against 0/3 to `149.154.166.121` and `149.154.175.100`, while the raw WAN never completes a connect to `91.108.56.130:443` or `149.154.167.99:443` at all — `DIRECT` hangs on strictly more DCs than `awg2` would. The removal is the owner's instruction: `awg2` is reserved for the `vpn` path, where it is the only rung `platform.claude.com` accepts, and for the `warp` set a fast visible ISP block is preferred to a partial relay. Do not propose putting it back. The price is accepted, not zero: with both tunnels down Telegram hangs on more DCs than it would over `awg2`, and Discord takes the ISP 403 instead of riding the Finnish relay (`discord.com/api/v9/gateway` answers 200 over `awg0`, `awg1` and `awg2` alike), so `WARP` gives up its one path independent of both `awg0`'s server and `awg1`'s endpoint. `DIRECT` is last at the owner's explicit call — Telegram and Discord must go direct when neither tunnel can carry them, so the ISP block itself surfaces instead of a hang on a dead tunnel. What "direct" looks like differs by service, measured 2026-09-10 from the router's WAN: Discord's `162.159.128.233:443` answers `403` in 0.008 s, while Telegram's `149.154.167.99:443` and `91.108.56.130:443` never complete a TCP connect at all — a silent drop that ends in a timeout, not a refusal. This is a deliberate loosening of the killswitch stance, and only for the `warp` set; the `vpn` path is untouched and still ends in `REJECT`.
- `DIRECT` passes the `WARP` group's probe as long as the WAN is up: the raw WAN answers `captive.apple.com` in 0.03 s (measured 2026-09-10), so under any tunnel failure the group still has a live member and degrades to a raw egress. A WAN outage is the exception — the `DIRECT` probe fails with the tunnels, `findAliveProxy` finds nothing alive, and the group returns `proxies[0]` = `WARP-AWG0`. Read the log accordingly: a `using WARP[WARP-AWG0]` line during a WAN outage is the every-member-dead case, not a healthy `awg0`.
- The `WARP` group probes `http://captive.apple.com/` with `expected-status: 200`, not `cp.cloudflare.com`. WARP still reaches Cloudflare when its egress is broken everywhere else, so a Cloudflare probe reports a healthy tunnel that carries nothing — measured through a degraded `awg1` on 2026-08-20: `cp.cloudflare.com` 3/3 while `8.8.8.8:443` managed 1/3. `captive.apple.com` and `www.msftconnecttest.com/connecttest.txt` were 3/3 over both `awg1` and `awg2` and 0/3 over dead `awg0`; `connectivitycheck.gstatic.com/generate_204` was 2/3 and was rejected as too flaky to gate a fallback on. Do not probe a raw Telegram DC address instead: `ARCHITECTURE.md` records why those readings are not reproducible.
- The `WARP` group carries `timeout: 12000`, `interval: 300` and `lazy: false` — `lazy` defaults to `true`, which lets `HealthCheck.process` skip a tick while the group is undialled, so a startup probe taken before `awg0`/`awg1` handshake could freeze a both-tunnels-dead verdict and pin the raw `DIRECT` egress until traffic arrives. The omitted `timeout` default is 5000 ms, and on 2026-09-10 `awg0` answered the apple probe in 5.9 s, 7.3 s and once not at all inside a 10 s ceiling, while connecting to Telegram DCs in 0.07 s, so the default retired the rung that actually worked and pinned everything on `awg1`, which was failing `149.154.166.121:443` 0/3. A single failed probe keeps a rung demoted for the whole `interval`, and `max-failed-times` cannot rescue it — `GroupBase.onDialFailed` discards dial errors from `direct` members, so only the interval recheck moves a rung. `tolerance` is not set here: `FallbackOption` never decodes it, so the old `tolerance: 150` was inert. The `VPN` group has no `timeout` key at all and runs on that 5000 ms default, with `interval: 60` and `lazy: false`.
- Telegram rides the `WARP` group like the rest of the `warp` set: `RULE-SET,telegram,WARP` and `RULE-SET,telegram_ip,WARP,no-resolve`. `pbr` still fetches `Services/telegram.lst` into `telegram.txt` instead of feeding it to the `warp` set, and `Subnets/IPv4/telegram.lst` into `telegram_ip.txt`, and the two rules still sit above the `warp` rules — that ordering no longer protects a pin, it only keeps the sets distinct. Native-app connections to raw DC IPs reach mihomo because `pbr` TPROXYs the nft set `tproxy_ip4` (Telegram + Viber ranges) to `:12342`. The `telegram` rule-provider must also appear in `dns.fake-ip-filter` as `RULE-SET,telegram,fake-ip`, otherwise Telegram domains fall to `MATCH,real-ip` and resolve to Cloudflare IPs that are absent from `tproxy_ip4`, going straight to the ISP-blocked WAN.
- The `awg0` pin was dropped on 2026-08-20 at the owner's explicit call, reversing the earlier "loud failure beats silent hang" rule: Telegram now degrades with the rest of the `warp` set instead of dying outright when `awg0` is down. Measured through mihomo right after the change, `awg1` carried it — 10 of 10 TCP connects from the LAN to `149.154.175.50:443` and `91.108.56.130:443`, all logged as `RuleSet(telegram_ip) using WARP[WARP-AWG1]`, and `web.telegram.org` answered 200 over `RuleSet(telegram)`. It is not uniform: the same log shows `dial tcp 149.154.167.99:443: i/o timeout`, so some DCs still hang on `awg1` rather than fail.
- Discord, voice included, goes to the `WARP` group through the `warp` rule set: it is blocked *by* Russia like Twitter and Meta, which is what that set means, while `vpn` means services that geo-block Russia. `vpn` is also wrong operationally: it now leads with a `url-test` ranked by HTTP latency, which says nothing about UDP, and it falls back to a relayed WARP hop instead of degrading in place. Voice is a separate UDP/RTP connection to a hostname the gateway hands out at runtime under `discord.media`, so fake-IP applies and the existing `198.18.1.0/24` TPROXY rule already matches `udp`: no firewall or `config.yaml` change is needed. Discord and Telegram share one path: the `WARP` group's `awg0` → `awg1` → `DIRECT` fallback. Measured 2026-09-10 by real IP, `discord.com/api/v9/gateway` answered 200 over `awg0`, `awg1` and `awg2` alike, so dropping `awg2` costs Discord nothing.
- The old split path is gone: firewall rule `mark_warp_domains` (mark `0x3`), ipset `warp_domains`, ip rule `fwmark 0x3 lookup warp`, `table warp` and hotplug `/etc/hotplug.d/iface/40-warp` were all removed. An optional on-router `tg-ws-proxy` (SOCKS5 `:17023`) still exists.
- `awg0`'s peer is addressed as `192.168.1.2` directly (UCI `network.@amneziawg_awg0[0].endpoint_host`). Do not set it back to `labile.cc`: that name resolves to `192.168.1.2` via the dnsmasq override but to the router's own WAN IP publicly, so if the ifup-time resolver ever answers with the public record the tunnel points at the router itself and receives nothing. This setting lives only in router UCI and is not tracked in this repository, so nothing here enforces it.
- `awg0` lost its peer between 2026-08-20 and 2026-09-10 and got it back: on 2026-09-10 it was rehandshaking every ~34 s with 27.64 GiB received. The Belarus server was recreated, not repointed — treat the earlier note about `amnezia-wg-easy` on `192.168.1.2:51820` (`10.8.0.0/24`, its own key, no `s3`/`s4`/`i1`) as the wrong container to aim at if the peer disappears again.
- Rule files are mirrored to `/etc/mihomo/rules` by `pbr` and seeded back into `/tmp/mihomo/rules` by `mihomo/init.d` before mihomo starts. Without that, a reboot leaves every rule-provider empty and all of `vpn`, `warp` and `telegram` fall through to `MATCH,DIRECT` until `pbr` has refetched. The seed never overwrites a workdir file that already has content.
- The router's `dnsmasq` runs with `cache-size=0` (UCI `dhcp.@dnsmasq[0].cachesize`). Keep it there. mihomo answers DNS before its rule-providers load, so an early query for a `vpn` domain gets a real address; a caching `dnsmasq` then pins it for the upstream TTL while a correct fake-IP answer only carries TTL 1, so wrong answers outlive right ones by two orders of magnitude. While pinned, the domain resolves outside `198.18.1.0/24`, never enters mihomo, and bypasses every rule including the killswitch. Nothing is lost by disabling it: mihomo caches DNS itself, and the `stubby` and `192.168.1.2#5353` forwards sit in front of their own caches. Like the `awg0` endpoint this lives only in router UCI, so nothing here enforces it.
- `mihomo/init.d` still sends `dnsmasq` a `SIGHUP` a few seconds after mihomo starts. With the cache off it is a no-op; it stays so that an install which has not disabled the cache still narrows the window instead of leaving it open for the whole TTL.
- Router DNS is deliberately split three ways in UCI `dhcp.@dnsmasq[0]`, and the work domains bypass mihomo on purpose. The eight named hosts (`cloud.dit.mos.ru`, `mapp2fasak-m.mos.ru`, `vpn-ke.mos.ru`, `vpn-dc.mos.ru`, `gate-n.mos.ru`, `gate-k.mos.ru`, `sudir.mos.ru`, `hub.mos.ru`) plus `passport.mos.ru` go to `stubby` on `127.0.0.1#5453`; the catch-all `mos.ru`, `passport.local` and `elocont.ru` go to the LAN resolver `192.168.1.2#5353`; everything else goes to mihomo on `127.0.0.1#12344`. Do not fold these into mihomo's fake-IP flow. They resolve independently of mihomo, so work DNS keeps answering when the proxy stack is down — measured `sudir.mos.ru` → `212.11.155.165-167` via stubby and `*.mos.ru`/`passport.local` → `10.207.221.2` / `10.206.185.x` via the LAN resolver, all in 0 ms. And with `MATCH,real-ip` as the only `fake-ip-filter` default, one stray line in the `vpn` list would put a `198.18.1.0/24` address in front of an internal name and silently break a working domain; a domain-scoped dnsmasq forward makes that structurally impossible. Like the `awg0` endpoint this lives only in router UCI and is not tracked here.
- `MATCH,DIRECT` remains the final rule.

## Verification Expectations

For config changes, run:

```sh
nix-shell --run 'mihomo-validate'
```

`mihomo -t` passing does not prove a key name is real: an invented top-level key (`totally-invented-key-xyz: 42`) still yields `test is successful`, while an invalid value for a recognised key (`enhanced-mode: NOT-A-REAL-MODE`) fails. The validator checks values of keys it knows and silently discards names it does not, so a misspelled key passes and then does nothing at runtime. When a change adds or relies on a config key, prove the key is parsed by temporarily giving it a deliberately invalid value and confirming the test fails.

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
