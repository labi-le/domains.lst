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

1. `RULE-SET,vpn` routes to `VPN-PREFERRED`.
2. `VPN-PREFERRED` is a `fallback` group.
3. `VPN-PREFERRED` first tries `VPN-ALL-AUTO`.
4. `VPN-ALL-AUTO` is a `url-test` group using providers `aetris`, `mifa`, and `purple`.
5. If subscription nodes are unusable, `VPN-PREFERRED` falls back to `VPN`, the direct `awg2` path.

Current intended WARP flow:

1. `RULE-SET,warp` routes to `WARP`.
2. `WARP` falls back from `WARP-AWG1` to `WARP-AWG0`.

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

## Required Validation

After any config edit, run local validation through the Nix shell:

```sh
nix-shell --run 'yq "." mihomo/config.yaml >/dev/null && mihomo -t -d /tmp/mihomo -f mihomo/config.yaml'
```

Also run diagnostics for changed files when an LSP is available. If an LSP is not installed, report that limitation explicitly.

## Safety Rules

- Do not deploy to the router from this skill. Use the `router-deploy` skill for SCP, SSH, service restart, and router-side checks.
- Do not change rule lists, generated runtime files, or router state unless the user explicitly asks.
- Do not use `/tmp/mihomo` as a temporary binary path; it is the Mihomo runtime directory.
