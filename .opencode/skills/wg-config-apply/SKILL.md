---
name: wg-config-apply
description: Use when an AmneziaWG or WARP client `.conf` (from AmneziaWG, AyuGram Desktop, or a WARP provider) must become router state on an `awg*` interface — converting it to OpenWrt UCI with wg2uci.sh, or applying it to the router with apply-wg.sh.
---

# WG Config Apply

Use this skill when a WireGuard-family client configuration has to reach an
`awg*` interface on the OpenWrt router. The typical source is a `.conf` exported
by AmneziaWG, AyuGram Desktop, or a WARP provider; the destination is
`/etc/config/network` on the router.

## The two scripts

| file | role |
| --- | --- |
| `wg2uci.sh` | the converter. Reads an AmneziaWG `.conf` and prints an OpenWrt UCI fragment. This is the only place the `.conf` format is parsed. |
| `apply-wg.sh` | the applier. Pipes the `.conf` through `wg2uci.sh`, translates the fragment into `uci` statements, and runs them on the router over SSH. |

`apply-wg.sh` deliberately reuses `wg2uci.sh` as its only parser. Do not
re-implement `.conf` parsing anywhere else: if the format needs new handling,
change `wg2uci.sh` and let `apply-wg.sh` consume the result.

## Usage

```sh
./apply-wg.sh <awg.conf> [iface] [host]   # iface defaults to awg1, host to router
./apply-wg.sh < awg.conf
cat awg.conf | ./apply-wg.sh
```

To inspect the conversion without touching the router, run the converter alone:

```sh
./wg2uci.sh awg.conf awg1
```

## What apply-wg.sh does

1. Backs up `/etc/config/network` to `/root/uci-backups/network.bak.<iface>.<timestamp>`.
2. `ifdown <iface>`.
3. Deletes the old `config interface '<iface>'` and its `amneziawg_<iface>` peer, then recreates both from the parsed config.
4. `uci commit network`, `ifup <iface>`.
5. Polls `awg show` for a `latest handshake`, then prints the interface state and the first three routing lines.

Anything the config does not carry is dropped rather than left stale: the
interface is rebuilt from scratch, so a removed option does not survive from the
previous config.

## Deliberate deviations from the `.conf`

These are required, not oversights. Do not "fix" them.

- **`DNS = ...` is discarded.** On a client that line picks a resolver. On the
  router it would outrank the deliberately split DNS (stubby on
  `127.0.0.1:5453`, the LAN resolver on `192.168.1.2#5353`, and mihomo on
  `127.0.0.1:12344`) documented in `AGENTS.md`.
- **`defaultroute` stays `0`.** The configs carry `AllowedIPs = 0.0.0.0/0, ::/0`.
  If that were allowed to install routes it would hijack the router's default
  route and take the whole LAN down. Verify `default via ... dev wan` is still
  present after an apply.
- **The peer section is anonymous**, created with `uci add` and addressed as
  `network.@amneziawg_<iface>[0]`, because that is the shape `awg0` and `awg2`
  already use in `/etc/config/network`. A named peer section would leave two
  different shapes in one file.

## Guards

`apply-wg.sh` refuses to contact the router unless the parse produced a
non-empty `private_key`, `public_key`, and `endpoint_host`. This matters because
`wg2uci.sh` emits `option private_key ''` when it parsed nothing — an empty, a
malformed, or a CRLF-converted config would otherwise delete the working
interface and recreate it with no key material. A rejected config exits before
any SSH connection is made.

## Safety

This changes live networking on a router that carries a household LAN.

- Prefer validating locally first: run `./wg2uci.sh <conf> <iface>` and read the
  fragment before applying.
- The apply is the explicit request. Do not run it to "check" something.
- After applying, confirm three things: `awg show <iface>` reports a recent
  `latest handshake`, the `allowed ips` are as expected, and the default route
  is unchanged.

## Verification

```sh
shellcheck apply-wg.sh
./wg2uci.sh sample.conf awg1          # fragment looks right
./apply-wg.sh sample.conf awg1 router # handshake + routes reported at the end
```
