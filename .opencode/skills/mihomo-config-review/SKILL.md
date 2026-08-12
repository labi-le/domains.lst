---
name: mihomo-config-review
description: Use when reviewing, explaining, or changing this repo's Mihomo configuration, especially mihomo/config.yaml, proxy-providers, proxy-groups, DNS fake-ip settings, rule-providers, health checks, and routing behavior.
---

# Mihomo Config Review

Use this skill for any task that touches or evaluates `mihomo/config.yaml`.

## Scope

Important repo files:

- `mihomo/config.yaml` - static Mihomo config copied to `/etc/mihomo/config.yaml`.
- `shell.nix` - local validation/deploy helper environment.
- `MIHOMO_INSTALL.md` - operational install, validation, deploy, and verification notes.
- `REFERENCE_MAP.md` - repo path to router path mapping.
- `ARCHITECTURE.md` - network flow and routing design.

Current intended VPN flow:

1. `RULE-SET,vpn` routes to `VPN-ALL-AUTO`.
2. `VPN-ALL-AUTO` is a `url-test` group using proxy-provider `stable`. The path is subscription-only; there is no AmneziaWG fallback.
3. `empty-fallback: REJECT` must stay: the default `COMPATIBLE` is a direct outbound with no interface bind, so an empty provider would leak `vpn` domains to the raw WAN.

Current intended WARP flow:

1. `RULE-SET,warp` routes to `WARP`.
2. `WARP` is primary `WARP-AWG0` (`awg0`, Belarus) with fallback to `WARP-AWG1` (`awg1`, Cloudflare WARP).

Current intended Telegram flow:

1. `RULE-SET,telegram,WARP-AWG0` and `RULE-SET,telegram_ip,WARP-AWG0,no-resolve` target the *proxy* `WARP-AWG0`, never the `WARP` group: `awg1` passes the group's `cp.cloudflare.com` probe but cannot carry Telegram TCP, so a group fallback would turn an `awg0` outage into a silent hang.
2. Both rules must stay above `RULE-SET,warp` and `RULE-SET,warp_ip`.
3. `RULE-SET,telegram,fake-ip` must stay in `dns.fake-ip-filter`; without it Telegram domains resolve to real Cloudflare IPs that no set covers and egress to the ISP-blocked WAN.
4. Native-app traffic to raw DC IPs enters mihomo only via the nft set `tproxy_ip4` that `pbr` writes into `/etc/nftables.d/99-tproxy.nft`.

## Review Checklist

When reviewing or editing config, check all of these:

- `proxy-groups[].use` entries reference existing `proxy-providers`.
- `proxy-groups[].proxies` entries reference existing proxies, existing proxy groups, or known built-ins such as `DIRECT`/`REJECT`.
- `rules` and `dns.fake-ip-filter` `RULE-SET` entries reference existing `rule-providers`.
- `rule-providers` paths match the runtime layout under `/tmp/mihomo/rules` when Mihomo runs with `-d /tmp/mihomo`.
- `proxy-providers` paths match the runtime layout under `/tmp/mihomo/providers` when Mihomo runs with `-d /tmp/mihomo`.
- Health checks have intentional `url`, `interval`, `timeout`, `lazy`, `expected-status`, and `max-failed-times` values.
- `url-test` `tolerance` is intentional: lower values switch more eagerly; higher values are stickier.
- `.lan` and `.local` names stay `real-ip` in `fake-ip-filter`.
- `MATCH,DIRECT` remains the final fallback rule unless the user explicitly asks otherwise.
- Telegram rules still target `WARP-AWG0` directly, still precede the `warp` rules, and `telegram` is still listed in `dns.fake-ip-filter`.
- `empty-fallback: REJECT` on `VPN-ALL-AUTO` is not removed.
- Domain rule-providers (`vpn`, `warp`, `telegram`) stay `behavior: domain` with `+.<domain>` lines; IP rule-providers (`telegram_ip`, `warp_ip`) stay `behavior: ipcidr` with bare CIDR lines.

## Required Validation

After any config edit, run local validation through the Nix shell:

```sh
nix-shell --run 'yq "." mihomo/config.yaml >/dev/null && mihomo -t -d /tmp/mihomo -f mihomo/config.yaml'
```

Also run diagnostics for changed files when an LSP is available. If an LSP is not installed, report that limitation explicitly.

### What `mihomo -t` Does Not Prove

`mihomo -t` validates the *values* of keys it recognises and silently discards key names it does not
recognise. Measured against this repo's `mihomo/config.yaml` with Mihomo Meta v1.19.29:

- unchanged config: `test is successful`
- plus an invented top-level key `totally-invented-key-xyz: 42`: `test is successful`
- a real key given an invalid value (`enhanced-mode: NOT-A-REAL-MODE`): `test failed`

So a misspelled or non-existent key passes validation cleanly and then does nothing at runtime: the
config looks correct while the behaviour it was supposed to produce is simply absent.

Therefore, when a change adds or depends on a config key:

- Temporarily set that key to a deliberately invalid value and re-run the validation command.
- Require `test failed`. That failure is the only evidence the key name is actually parsed.
- Restore the intended value and confirm the test passes again before reporting the change as valid.

Worked case, `empty-fallback` on a proxy-group: `empty-fallback: REJECT` passes, and the bogus
`empty-fallback: NOPE-DOES-NOT-EXIST` fails. Together those two results prove the key is understood
rather than ignored.

Note the version gap: local validation runs Mihomo v1.19.29 while the router binary is v1.19.27, so
key support can in principle differ between the machine that validates and the machine that runs.

## Safety Rules

- Do not deploy to the router from this skill. Use the `router-deploy` skill for SCP, SSH, service restart, and router-side checks.
- Do not change rule lists, generated runtime files, or router state unless the user explicitly asks.
- Do not use `/tmp/mihomo` as a temporary binary path; it is the Mihomo runtime directory.
