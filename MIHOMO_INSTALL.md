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

`web.telegram.org` must resolve to a `198.18.1.x` fake IP, not a real `104.18.x` address: a real
one means the `telegram` entry is missing from `dns.fake-ip-filter`. The raw DC IP exercises the
`tproxy_ip4` -> `RULE-SET,telegram_ip` path that native Telegram apps use.

### Log Checks

```sh
ssh router 'logread | grep mihomo | grep -E "RuleSet\(vpn\)|RuleSet\(telegram\)|RuleSet\(telegram_ip\)|RuleSet\(warp\)|RuleSet\(warp_ip\)|using VPN-ALL-AUTO|using WARP-AWG0|using WARP\[|using DIRECT"'
```

Expected current routing behavior:

- `vpn` domains -> `VPN-ALL-AUTO`
- `VPN-ALL-AUTO` selects the lowest-latency node across proxy-provider `stable`
- no awg fallback: an empty provider yields `REJECT` via `empty-fallback`, so `vpn` domains fail
  instead of leaking to the WAN
- `warp` domains -> `WARP` (primary `WARP-AWG0`/`awg0`, fallback `WARP-AWG1`/`awg1`)
- Telegram domains -> `WARP-AWG0` directly (pinned to `awg0`, no fallback)
- Telegram raw DC IPs -> TPROXY via nft set `tproxy_ip4` -> `RULE-SET,telegram_ip,WARP-AWG0,no-resolve`
- Viber IPs -> TPROXY via `tproxy_ip4` -> `RULE-SET,warp_ip,WARP,no-resolve`

## References

- Mihomo releases: `https://github.com/MetaCubeX/mihomo/releases`
- Mihomo CLI flags: `https://github.com/mzdluo123/mihomo/blob/Meta/_autodocs/configuration.md`
