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
- `/tmp/mihomo/providers/mos-eu.yaml`

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

Example using the currently deployed version:

```sh
VER="1.19.25"
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

## Start Services

```sh
ssh router '/etc/init.d/mihomo enable && /etc/init.d/mihomo restart'
ssh router '/etc/init.d/pbr enable && /etc/init.d/pbr start'
```

## Verification

### Router-Side Checks

```sh
ssh router 'ss -ltnup 2>/dev/null | grep -E "12342|12344"'
ssh router 'ls -lh /tmp/mihomo/cache.db /tmp/mihomo/rules/vpn.txt /tmp/mihomo/rules/warp.txt /tmp/mihomo/providers/mos-eu.yaml'
ssh router 'dig +short chatgpt.com @127.0.0.1 -p 53'
ssh router 'dig +short rutracker.org @127.0.0.1 -p 53'
```

### LAN Client Checks

```sh
curl -vk https://chatgpt.com
curl -vk https://rutracker.org
```

### Log Checks

```sh
ssh router 'logread | grep mihomo | grep -E "RuleSet\(vpn\)|RuleSet\(warp\)|using VPN-PREFERRED|using WARP|using DIRECT"'
```

Expected current routing behavior:

- `vpn` domains -> `VPN-PREFERRED`
- `VPN-PREFERRED` -> `VPN-SUB-EU` primary -> `VPN` (`awg2`) fallback
- `warp` domains -> `WARP` (`awg1`)

## References

- Mihomo releases: `https://github.com/MetaCubeX/mihomo/releases`
- Mihomo CLI flags: `https://github.com/mzdluo123/mihomo/blob/Meta/_autodocs/configuration.md`
