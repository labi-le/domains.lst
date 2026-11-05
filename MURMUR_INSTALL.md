# Murmur Install Guide

## Purpose

This file documents the OpenWrt router installation flow for `murmur`, the router's
proxy. It replaced `mihomo` on 2026-11-03 and took over the same ports (DNS `12344`,
tproxy `12342`), so `nftables` and `dnsmasq` are unchanged.

## Static Vs Runtime Layout

Static files (on flash):

- `/etc/murmur/config.yaml`
- `/etc/init.d/murmur`
- `/etc/config/murmur`
- `/etc/init.d/pbr`
- `/usr/bin/murmur` (the binary)
- `/etc/nftables.d/99-tproxy.nft` (rendered by pbr)

Mutable runtime files (in tmpfs, wiped on reboot):

- `/tmp/murmur.d/cache.db`
- `/tmp/murmur.d/rules/*.txt`
- `/tmp/murmur.d/providers/*.yaml`

The rule lists live in tmpfs on purpose: they are refetched weekly, and writing them
to flash every week costs erase cycles for no benefit. The cost is a boot window
where the lists are empty, which is why pbr (`START=97`) runs before the proxy
(`START=98`). A proxy started earlier matches nothing and sends every proxied domain
to `MATCH,DIRECT`.

Do not use `/tmp/murmur.d` as a temporary binary filename. It is the runtime
directory.

## The Build

The binary must fit in a 37 MB overlay, so it is built without `extra-protocols`:

```sh
nix develop .#aarch64-musl --command bash -c '
  cargo build --locked --profile compact -p murmur --bin murmur \
    --no-default-features --features router-vvt \
    --target aarch64-unknown-linux-musl'
```

`router-vvt` is `with_low_memory`, `with_gvisor`, `no_easytier`, `no_tailscale`,
`no_zerotier` and, crucially, no `extra-protocols`. Dropping that feature removes 17
transport crates: hysteria, hysteria2, anytls, tuic, mieru, openvpn, shadowquic,
snell, ssr, sudoku, trusttunnel, kcptun, masque, simple-obfs and the quic and russh
dependencies. The subscription's vless, ss and vmess nodes are unaffected; its
hysteria2 and anytls nodes cannot be dialled by this build.

Installing it is then a plain file copy:

```sh
scp target/aarch64-unknown-linux-musl/compact/murmur router:/usr/bin/murmur
ssh router 'chmod 755 /usr/bin/murmur'
```

## Required Packages

```sh
opkg install dnsmasq-full stubby ca-bundle curl amneziawg-tools kmod-amneziawg
```

`xz` is not needed: the binary is a normal executable.

## Deploy the Binary and Service

Install `murmur` (`/usr/bin/murmur`, `/etc/init.d/murmur` with `--watch-config` and `nofile="4096 4096"`, and `/etc/config/murmur`) via the one-line OpenWrt installer:

```sh
ssh router 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/labi-le/murmur/main/packaging/openwrt/install.sh)"'
```

Or install the `.ipk` package directly from `https://github.com/labi-le/murmur/releases/tag/Prerelease-Alpha`:

```sh
ssh router '
  ver=$(curl -fsSL https://github.com/labi-le/murmur/releases/download/Prerelease-Alpha/version.txt) &&
  curl -fsSL "https://github.com/labi-le/murmur/releases/download/Prerelease-Alpha/murmur-vvt_${ver}_aarch64_generic.ipk" -o /tmp/murmur.ipk &&
  opkg install /tmp/murmur.ipk &&
  rm -f /tmp/murmur.ipk
'
```

When deploying a locally compiled binary directly:

```sh
scp target/aarch64-unknown-linux-musl/compact/murmur router:/usr/bin/murmur
ssh router 'chmod 755 /usr/bin/murmur'
```

Verify the build the same way the init script does:

```sh
ssh router '/usr/bin/murmur -v'
```

## Deploy the Configuration

```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/murmur/config.yaml -O /tmp/murmur.config.yaml &&
scp /tmp/murmur.config.yaml router:/etc/murmur/config.yaml

wget https://raw.githubusercontent.com/labi-le/domains.lst/main/pbr -O /tmp/pbr &&
scp /tmp/pbr router:/etc/init.d/pbr &&
ssh router 'chmod +x /etc/init.d/pbr'

wget https://raw.githubusercontent.com/labi-le/domains.lst/main/proxy-ctl.sh -O /tmp/proxy-ctl &&
scp /tmp/proxy-ctl router:/root/proxy-ctl.sh &&
ssh router 'chmod +x /root/proxy-ctl.sh'
```

## Validate Config

`murmur` supports these flags:

- `-d, --home-dir PATH`
- `-f, --config FILE`
- `-t, --test`
- `-v, --version`

Validate the active config against the tmpfs runtime directory:

```sh
ssh router '/usr/bin/murmur -t -d /tmp/murmur.d -f /etc/murmur/config.yaml'
```

## Local Dev Shell

Use the repository `shell.nix` before copying config changes to the router:

```sh
nix-shell
```

Useful commands inside the shell:

```sh
murmur-yaml-check
murmur-validate
murmur-deploy-config
murmur-fetch-router
murmur-deploy
```

Equivalent explicit commands:

```sh
yq '.' murmur/config.yaml >/dev/null
scp murmur/config.yaml router:/etc/murmur/config.yaml
```

## Start Services

```sh
ssh router '/etc/init.d/murmur enable && /etc/init.d/murmur restart'
ssh router '/etc/init.d/pbr enable && /etc/init.d/pbr start'
```

## Verification

### Router-Side Checks

The admin helper runs all of them:

```sh
ssh router '/root/proxy-ctl.sh check'
```

Expected output:

```
  OK   DNS is listening on 12344
  OK   tproxy is listening on 12342
  OK   murmur is running
  OK   <domain> resolves to the fake IP <ip>
  OK   <domain> resolves to the real IP <ip>
```

Manual equivalents:

```sh
ssh router 'netstat -lntp | grep -E "12342|12344"'
ssh router 'ls -lh /tmp/murmur.d/rules/ /tmp/murmur.d/cache.db'
ssh router 'dig +short rutracker.org @127.0.0.1 -p 12344'
ssh router 'nft list chain inet fw4 prerouting_tproxy'
```

The TPROXY counters must grow. If they stay at zero, the LAN traffic is not being
intercepted even though the DNS answers look correct.

### LAN Client Checks

```sh
curl -vk https://rutracker.org
curl -vk https://chatgpt.com
```

### Log Checks

```sh
ssh router 'logread | grep murmur | grep -E "RuleSet\(vpn\)|RuleSet\(warp\)|using VPN|using WARP|using DIRECT"'
```

Expected current routing behavior:

- `vpn` domains -> `VPN` (`VPN-ALL-AUTO` primary, direct `awg2` fallback)
- `warp` domains -> `WARP` (`WARP-AWG0`/`awg0` primary, `WARP-AWG1`/`awg1` then `VPN`)
- Telegram -> `WARP` (`awg0`)

## Firmware Upgrades

The configuration is listed in `/etc/sysupgrade.conf`, so a firmware upgrade keeps
it. The compressed binary is deliberately not in the list: 7.6 MB does not fit into
an upgrade image, and the init script can fetch it from the cache host instead.

```sh
ssh router 'cat /etc/sysupgrade.conf'
```

## References

- murmur releases: `https://github.com/labi-le/murmur/releases/tag/Prerelease-Alpha`
- The proxy's own documentation: `https://github.com/labi-le/murmur/tree/main/docs`
