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

1. `RULE-SET,vpn` routes to the `VPN` group, a `fallback` with two rungs: `VPN-ALL-AUTO` then
   `WARP-AWG2`. The path is no longer subscription-only.
2. `VPN-ALL-AUTO` is a `url-test` group using proxy-provider `stable`.
3. `WARP-AWG2` (`awg2`, Cloudflare WARP through a Finland relay) is rung 2 on acceptance, not
   geography: `platform.claude.com` answers 200 over awg2 and 403 over awg0 and awg1. It is not
   "the only rung outside Russia" - awg0 exits in Belarus (`loc=BY`). Separately, `chatgpt.com`
   answers 403 over all three exits including awg2; that is an observation with no established
   cause, and it is not attributable to OpenAI blocking Cloudflare WARP ranges, since awg0 is
   `warp=off` on a Belarusian address and still gets 403.
4. The `VPN` group probes `https://platform.claude.com/` every 60 s with `lazy: false` and
   `expected-status: 200-399`. It carries no `timeout`, so the omitted default of 5000 ms applies -
   measured 2026-09-10, that probe answers 200 over awg2 in ~0.67 s, so an explicit `timeout` would
   be inert.
5. `empty-fallback: REJECT` must stay: the default `COMPATIBLE` is a direct outbound with no
   interface bind, so an empty provider would leak `vpn` domains to the raw WAN.
6. `REJECT` no longer rejects on the spot. An empty provider resolves `VPN-ALL-AUTO` to `REJECT`,
   whose probe fails with `io.EOF`, so the outer `VPN` group reads that rung as dead and routes to
   `WARP-AWG2`. Only when awg2 is dead too does the group fall back to returning `proxies[0]` and
   kill the traffic.

Current intended WARP flow:

1. `RULE-SET,warp`, `RULE-SET,warp_ip`, `RULE-SET,telegram`, and `RULE-SET,telegram_ip` all route
   to `WARP`.
2. `WARP` is a `fallback` over `WARP-AWG0` (`awg0`, Belarus), `WARP-AWG1` (`awg1`, Cloudflare
   WARP), then `DIRECT`.
3. `DIRECT` is a deliberate last rung: with both tunnels dead, Telegram and Discord meet the ISP
   block itself instead of hanging on a tunnel that carries nothing. Measured 2026-09-10 from the
   router's WAN, that block surfaces immediately for Discord - `162.159.128.233:443` answers `403`
   in 0.008 s - and as a timeout for Telegram, whose DC addresses `149.154.167.99:443` and
   `91.108.56.130:443` never complete a TCP connect at all (silent drop). Telegram gets no
   refusal, only silence.
4. `DIRECT` passes the group probe while the WAN is up: the raw WAN answers `captive.apple.com` in
   0.03 s (measured 2026-09-10), so any tunnel failure leaves the group a live member. With the WAN
   itself down the `DIRECT` probe fails alongside the tunnels, `findAliveProxy` finds nothing alive
   and the group returns `proxies[0]` = `WARP-AWG0` — so a `using WARP[WARP-AWG0]` line during a
   WAN outage is the every-member-dead case, not a healthy awg0.
5. This is a deliberate loosening of the old killswitch stance, and only for the `warp` set. The
   `vpn` path is untouched and still ends in `REJECT`.
6. `WARP` probes `http://captive.apple.com/` rather than `cp.cloudflare.com`: Cloudflare is the one
   destination WARP still reaches when its egress is broken, so a Cloudflare probe reports a rung
   healthy while nothing else passes. Probing off-net is what lets the Telegram rules target the
   group instead of the proxy `WARP-AWG0`.
7. `WARP` `timeout` is `12000`, not `8000` and not the implicit 5000: awg0's apple probe measured
   5.9 s and 7.3 s, and once produced no answer inside a 10 s ceiling, while its Telegram DC
   connects took 0.07 s. A rung demoted by one failed probe stays demoted for the whole `interval`,
   and `max-failed-times` cannot rescue it, because `GroupBase.onDialFailed` discards dial failures
   from `direct` members. Anything near 5000 ms retires the healthier rung. `lazy: false` is set
   here too: the default `true` skips probes while the group is undialled, which can freeze a
   both-tunnels-dead verdict and pin the raw `DIRECT` egress until traffic arrives.
8. The Telegram rules must stay above `RULE-SET,warp` and `RULE-SET,warp_ip`.
9. `RULE-SET,telegram,fake-ip` must stay in `dns.fake-ip-filter`; without it Telegram domains
   resolve to real Cloudflare IPs that no set covers and egress to the ISP-blocked WAN.
10. Native-app traffic to raw DC IPs enters mihomo only via the nft set `tproxy_ip4` that `pbr`
    writes into `/etc/nftables.d/99-tproxy.nft`.

## Review Checklist

When reviewing or editing config, check all of these:

- `proxy-groups[].use` entries reference existing `proxy-providers`.
- `proxy-groups[].proxies` entries reference existing proxies, existing proxy groups, or known built-ins such as `DIRECT`/`REJECT`.
- `rules` and `dns.fake-ip-filter` `RULE-SET` entries reference existing `rule-providers`.
- `rule-providers` paths match the runtime layout under `/tmp/mihomo/rules` when Mihomo runs with `-d /tmp/mihomo`.
- `proxy-providers` paths match the runtime layout under `/tmp/mihomo/providers` when Mihomo runs with `-d /tmp/mihomo`.
- Health checks have intentional `url`, `interval`, `timeout`, `lazy`, `expected-status`, and `max-failed-times` values.
- A proxy-group `timeout` defaults to 5000 ms, so an explicit `timeout: 5000` is inert; only a value that differs from 5000 changes behaviour.
- `url-test` `tolerance` is intentional: lower values switch more eagerly; higher values are stickier. On `fallback` groups it is inert - `FallbackOption` never decodes it - so a `tolerance` on `WARP` or `VPN` would do nothing.
- `max-failed-times` cannot demote a `direct` member: `GroupBase.onDialFailed` discards dial failures from `direct` proxies, so `WARP-AWG0`, `WARP-AWG1`, `WARP-AWG2`, and `DIRECT` are demoted only by a failed probe.
- The `VPN` group keeps `url: https://platform.claude.com/`, `interval: 60`, `lazy: false`, `expected-status: 200-399`, and its rung order `VPN-ALL-AUTO` before `WARP-AWG2`.
- `RULE-SET,vpn` targets the `VPN` group, and no rule targets `VPN-ALL-AUTO` directly. A rule pointed back at `VPN-ALL-AUTO` validates cleanly and silently disables the `awg2` fallback, since the outer group is then never consulted.
- `WARP` keeps its rung order `WARP-AWG0`, `WARP-AWG1`, `DIRECT`, its `http://captive.apple.com/` probe, `lazy: false`, and a `timeout` well above awg0's measured 5.9-7.3 s probe latency.
- `.lan` and `.local` names stay `real-ip` in `fake-ip-filter`.
- `MATCH,DIRECT` remains the final fallback rule unless the user explicitly asks otherwise.
- Telegram rules still route to `WARP`, still precede the `warp` rules, and `telegram` is still listed in `dns.fake-ip-filter`.
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
