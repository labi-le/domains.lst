# Mihomo Install Guide

## Purpose

This file documents the current OpenWrt router installation flow for `mihomo`, the static config files copied from this repository, and the verification commands used after deployment.

## Static Vs Runtime Layout

Static files:

- `/etc/mihomo/config.yaml`
- `/etc/init.d/mihomo`
- `/etc/config/mihomo`
- `/etc/init.d/pbr`

Mutable runtime files:

- `/tmp/mihomo/cache.db`
- `/tmp/mihomo/rules/vpn.txt`
- `/tmp/mihomo/rules/warp.txt`
- `/tmp/mihomo/rules/telegram.txt`
- `/tmp/mihomo/rules/telegram_ip.txt`
- `/tmp/mihomo/rules/warp_ip.txt`
- `/tmp/mihomo/providers/stable.yaml`
- `/etc/mihomo/rules/*.txt` (persisted mirror, seeded back into `/tmp/mihomo/rules` at boot)

Do not use `/tmp/mihomo` as a temporary binary filename. It is the runtime directory.

## Required Packages

```sh
opkg install dnsmasq-full stubby ca-bundle curl amneziawg-tools kmod-amneziawg
```

## Mihomo Binary

Official release page:

- `https://github.com/MetaCubeX/mihomo/releases`

Current router build pattern:

- `mihomo-linux-arm64-v<version>.gz`

Example (substitute the current release; the router runs `mihomo -v` to report its own):

```sh
VER="1.19.27"
curl -L -o "/tmp/mihomo-${VER}.gz" \
  "https://github.com/MetaCubeX/mihomo/releases/download/v${VER}/mihomo-linux-arm64-v${VER}.gz"

gzip -dc "/tmp/mihomo-${VER}.gz" > "/tmp/mihomo-${VER}"
upx --best --lzma "/tmp/mihomo-${VER}"
```

`fetch-mihomo.sh` does the same three steps with the integrity check the manual `curl` above
lacks: it verifies the downloaded `.gz` against the `sha256` digest the GitHub release API
publishes for that asset and, on mismatch, deletes the download, prints both hashes and exits
non-zero before `gunzip`. A release that carries no digest fails closed unless
`MIHOMO_SKIP_DIGEST=1` is set. UPX runs after verification, so the compressed binary derives
from verified bytes. It needs `sha256sum` alongside `curl`, `jq` and `gunzip`.

Copy to the router from the workstation:

```sh
scp "/tmp/mihomo-${VER}" router:/tmp/mihomo.bin
ssh router 'cp /tmp/mihomo.bin /usr/bin/mihomo && chmod 755 /usr/bin/mihomo'
```

## Install Static Config Files

```sh
ssh router 'mkdir -p /etc/mihomo'

wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/init.d -O /tmp/mihomo.init &&
scp /tmp/mihomo.init router:/etc/init.d/mihomo &&
ssh router 'chmod +x /etc/init.d/mihomo'

wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/config -O /tmp/mihomo.uci &&
scp /tmp/mihomo.uci router:/etc/config/mihomo

wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/config.yaml -O /tmp/mihomo.config.yaml &&
scp /tmp/mihomo.config.yaml router:/etc/mihomo/config.yaml

wget https://raw.githubusercontent.com/labi-le/domains.lst/main/pbr -O /tmp/pbr &&
scp /tmp/pbr router:/etc/init.d/pbr &&
ssh router 'chmod +x /etc/init.d/pbr'
```

## Validate Config

`mihomo` supports these flags:

- `-d, --home-dir PATH`
- `-f, --config FILE`
- `-t, --test`
- `-v, --version`

Validate the active config against the tmpfs runtime directory:

```sh
ssh router '/usr/bin/mihomo -t -d /tmp/mihomo -f /etc/mihomo/config.yaml'
```

## Local Dev Shell

Use the repository `shell.nix` before copying config changes to the router:

```sh
nix-shell
```

Useful commands inside the shell:

```sh
mihomo-yaml-check
mihomo-validate
mihomo-deploy-config
mihomo-fetch-router
```

Equivalent explicit commands:

```sh
yq '.' mihomo/config.yaml >/dev/null
mihomo -t -d /tmp/mihomo -f mihomo/config.yaml
scp mihomo/config.yaml router:/etc/mihomo/config.yaml
```

A successful `mihomo -t` does not prove a key name exists: unrecognised keys are accepted silently and
then ignored at runtime. To prove a key is parsed, temporarily give it an invalid value and confirm the
test fails.

`mihomo-deploy-config` runs the local YAML parse and `mihomo -t` checks first, then copies `mihomo/config.yaml` to `router:/etc/mihomo/config.yaml`.

To fetch the latest router `mihomo` binary for ARM64 and compress it with UPX:

```sh
mihomo-fetch-router
```

The helper defaults to `linux-arm64` and prints the compressed binary path. Override the architecture or temporary output directory when needed:

```sh
mihomo-fetch-router linux-arm64 /tmp
MIHOMO_ROUTER_ARCH=linux-arm64 mihomo-fetch-router
```

Copy the resulting binary to the router:

```sh
bin="$(mihomo-fetch-router)"
scp "$bin" router:/tmp/mihomo.bin
ssh router 'cp /tmp/mihomo.bin /usr/bin/mihomo && chmod 755 /usr/bin/mihomo'
```

## Start Services

```sh
ssh router '/etc/init.d/mihomo enable && /etc/init.d/mihomo restart'
ssh router '/etc/init.d/pbr enable && /etc/init.d/pbr start'
ssh router 'fw4 reload'
```

`pbr` rewrites `/etc/nftables.d/99-tproxy.nft` but does not reload `fw4`, so chain changes take
effect only on the next `fw4 reload` or boot. Set *elements* are inlined into that file and are
also applied live by `pbr`, so an existing install survives a reload untouched; a first install,
or any edit to the rule text itself, needs the reload above.

`pbr` reads `fake-ip-range` out of `/etc/mihomo/config.yaml` at start, so `/etc/mihomo/config.yaml`
must be installed before the first `pbr start`; with the key absent `pbr` logs and exits 1 rather
than guessing a subnet. Changing the range takes edits in **two** places, not one: `fake-ip-range`
in `config.yaml`, followed by `pbr start` and `fw4 reload`, and separately the `lo` address in UCI
`network.loopback.ipaddr`, which is not derived from `fake-ip-range` and is not tracked in this
repository. The range is now `198.18.0.0/16`, so `lo` must carry a prefix covering it:

```sh
ssh router "uci -q delete network.loopback.ipaddr; uci add_list network.loopback.ipaddr='127.0.0.1'; uci add_list network.loopback.ipaddr='198.18.1.1/16'; uci commit network; service network reload"
```

`pbr` checks this at every start and warns when no `lo` prefix covers the configured range
(`WARNING: no address on lo covers 198.18.0.0/16`, with the `uci` command above in the message).
It only warns; it never edits the network config. Skipping the step is not cosmetic: with `lo` at
`198.18.1.1/24`, `ip route get 198.18.0.5` on the router answers
`via 93.100.194.1 dev wan`, so router-originated traffic to a fake IP outside the old `/24` leaves
out the raw WAN. LAN clients are unaffected, since their packets reach mihomo through the fwmark
lookup.

## Verification

### Router-Side Checks

```sh
ssh router 'ss -ltnup 2>/dev/null | grep -E "12342|12344"'
ssh router 'ls -lh /tmp/mihomo/cache.db /tmp/mihomo/rules/*.txt /etc/mihomo/rules/*.txt /tmp/mihomo/providers/stable.yaml'
ssh router 'dig +short chatgpt.com @127.0.0.1 -p 53'
ssh router 'dig +short rutracker.org @127.0.0.1 -p 53'
ssh router 'dig +short web.telegram.org @127.0.0.1 -p 53'
ssh router 'nft list set inet fw4 tproxy_ip4'
ssh router 'nft list chain inet fw4 prerouting_tproxy'
```

### LAN Client Checks

```sh
curl -vk https://chatgpt.com
curl -vk https://rutracker.org
curl -sS -o /dev/null -w '%{http_code}\n' https://web.telegram.org/
curl -sS -k -o /dev/null -w '%{http_code}\n' https://149.154.167.99/
```

`web.telegram.org` must resolve to a `198.18.x.x` fake IP, not a real `104.18.x` address: a real
one means the `telegram` entry is missing from `dns.fake-ip-filter`. The raw DC IP exercises the
`tproxy_ip4` -> `RULE-SET,telegram_ip` path that native Telegram apps use.

### Log Checks

```sh
ssh router 'logread | grep mihomo | grep -E "RuleSet\(vpn\)|RuleSet\(telegram\)|RuleSet\(telegram_ip\)|RuleSet\(warp\)|RuleSet\(warp_ip\)|using VPN|using WARP|using DIRECT"'
```

`pbr`'s own warnings go to syslog through `logger -t pbr` as well as stderr, which is what makes
the weekly cron run auditable — a failed fetch or a rejected list is visible after the fact:

```sh
ssh router 'logread -e pbr'
```

A run that logs a refused list left the previous rule files in place on purpose. Each source is
judged on its own: a source whose body is non-empty but yields zero valid entries — a captive
portal's HTML `200`, which `curl -sSLf` accepts — counts as failed exactly like one that failed
all five retries, and one failed source blocks the whole list from being installed. A rejected
CIDR is narrower: `nft rejected element <cidr>` means that element was dropped, while the rest of
`tproxy_ip4` was still filled.

Expected current routing behavior:

- `vpn` domains -> `VPN`, a fallback group: `VPN-ALL-AUTO` first, then `WARP-AWG2`
- `VPN-ALL-AUTO` still selects the lowest-latency node across proxy-provider `stable`
- the killswitch is conditional: an empty provider makes `VPN-ALL-AUTO` resolve to `REJECT`,
  whose health probe fails, so `VPN` falls through to `WARP-AWG2`; only when `awg2` is dead too
  does `VPN` return its first member and reject the traffic instead of leaking it to the WAN
- `warp` domains -> `WARP`, a fallback group: `WARP-AWG0`/`awg0` first, then `WARP-AWG1`/`awg1`,
  then `DIRECT` — with both tunnels down the traffic goes straight out the WAN and meets the ISP
  block itself (Discord answers `403` at once, Telegram DC connects just time out) instead of
  hanging on a dead tunnel
- Telegram domains -> `WARP`, the same group as the rest of the `warp` set; the old `awg0` pin was
  dropped on 2026-08-20
- Telegram raw DC IPs -> TPROXY via nft set `tproxy_ip4` -> `RULE-SET,telegram_ip,WARP,no-resolve`
- Viber IPs -> TPROXY via `tproxy_ip4` -> `RULE-SET,warp_ip,WARP,no-resolve`

Reading the `DIRECT` hits in that grep: a `warp`, `telegram` or `telegram_ip` match whose outbound
is the `WARP` group's `DIRECT` rung is the expected last-rung outcome, not a fault — it means both
tunnels failed their `captive.apple.com` probe, and the traffic is deliberately allowed to hit the
ISP block instead of hanging. Chase the tunnels, not the routing. A `vpn` domain leaving over
`DIRECT` is still a fault in every case: the `vpn` path ends in `REJECT` and must never egress raw.
A plain `using DIRECT` on a domain in none of the rule sets is just `MATCH,DIRECT` doing its job.

## References

- Mihomo releases: `https://github.com/MetaCubeX/mihomo/releases`
- Mihomo CLI flags: `https://github.com/mzdluo123/mihomo/blob/Meta/_autodocs/configuration.md`
