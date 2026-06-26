---
name: mihomo-docs
description: Use for questions about Mihomo/Clash.Meta behavior, including proxy-groups, url-test, fallback, proxy-providers, DNS fake-ip, rule-providers, health checks, expected-status, lazy, tolerance, and config syntax.
---

# Mihomo Docs

Use this skill when the user asks how Mihomo works or what a Mihomo config setting means.

## Required Documentation Flow

1. Query current Mihomo documentation before answering library-specific behavior. Prefer Context7 documentation for Mihomo/MetaCubeX wiki.
2. Read the relevant local config section from `mihomo/config.yaml`.
3. Answer in two layers:
   - What Mihomo documentation says generally.
   - What that means in this repository's current config.

## Common Topics

Use this skill for these topics:

- `url-test` selection and `tolerance` behavior.
- `fallback` selection order and health checks.
- `proxy-providers` and provider `health-check` behavior.
- `rule-providers` and `RULE-SET` routing.
- `fake-ip`, `fake-ip-filter`, `real-ip`, and domain restoration.
- `expected-status`, `timeout`, `lazy`, and `max-failed-times`.
- The interaction between provider health checks and proxy-group health checks.

## Answer Style

- Speak in the user's language.
- Link local files when mentioning them, for example `mihomo/config.yaml`.
- Prefer concrete examples using this repo's groups: `VPN-ALL-AUTO`, `VPN-PREFERRED`, `WARP`, `aetris`, `mifa`, and `purple`.
- If documentation and observed config could be interpreted differently, say so and identify what would need runtime verification.

## Boundaries

- Do not edit files unless the current user message explicitly asks to implement/change/fix something.
- Do not deploy or restart router services. Use the `router-deploy` skill for that.
