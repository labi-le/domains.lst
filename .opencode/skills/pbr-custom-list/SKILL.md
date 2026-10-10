---
name: pbr-custom-list
description: Use when adding or removing a domain in custom-set.txt or custom-set_cis.txt, i.e. deciding which traffic pbr and mihomo route through the foreign VPN, WARP, or direct. Covers the push-to-GitHub requirement, applying on the router, and verification.
---

# Pbr Custom Lists

Two hand-maintained lists feed pbr's rule sets. Each is downloaded by URL from
this repository, so a local edit is inert until it is pushed and applied.

- `custom-set.txt` — concatenated with `geoblock.lst` and `google_ai.lst` into
  the `vpn` rule set: domains that must leave via the **foreign VPN**. Think
  services that are SNI-filtered by the ISP, or simply want a foreign egress.
- `custom-set_cis.txt` — concatenated into the `warp` set together with
  `block.lst`, `porn.lst`, `news.lst`, `discord.lst` and others: domains routed
  via WARP, which is where blocked or CIS-region traffic ends up.

Pick the list from the desired route, not from the name: "custom" is not
"foreign", and `cis` is not "domestic".

## Add or remove a domain

```sh
cd ~/PhpstormProjects/domains.lst
printf '%s\n' 'example.com' >> custom-set.txt      # or custom-set_cis.txt
git commit -am 'pbr: add example.com to the vpn list'
git push
```

The push is required. `pbr` fetches

```
https://raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/custom-set.txt
```

so without a push the router keeps reading the published copy. Verify the
published file before touching the router:

```sh
curl -s https://raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/custom-set.txt | tail
```

## Apply

```sh
ssh router '/etc/init.d/pbr start'
```

Cron also runs it daily at 06:00, so an unapplied change lands the next morning
on its own. Running it by hand is the way to make it effective now.

The fetch is fail-safe: if any source in a set returns nothing, the whole set
keeps its previous contents rather than installing a shrunken list. A warning in
the output that names a source is therefore informative, not fatal.

## Verify

```sh
ssh router 'grep -n "example" /tmp/mihomo/rules/vpn.txt'
```

Entries are rewritten as `+.example.com`, so match with the plus-dot form. Then
confirm the routing decision from the log:

```sh
ssh router 'logread | grep -E "vpn rule_set|Wrote .* entries" | tail'
```

## Reporting

Always report: which list the domain went to and why, the commit, whether
`pbr start` was run on the router (it rewrites the rule sets and restarts
mihomo), and the entry count of the affected set before and after.
