---
name: zapret-exclude
description: Use when a domain must be excluded from zapret's DPI desync, or when a client says a site is reachable but something (audio, video, an API call) silently fails. Covers editing zapret-exclude-ensure.lst, applying it on the router, and deciding whether an exclusion is the right lever at all.
---

# Zapret Exclude Entry

`zapret-hosts-user-exclude.txt` on the router holds the names zapret must **not**
desync. An entry is wrong in either direction and both failures are silent:

- A name that is in the list but needs the bypass: TLS handshake hangs to
  timeout, because the ISP's SNI filter has nothing to fight.
- A name that is not in the list but cannot survive desync: an instant
  `WRONG_VERSION_NUMBER` or `SSLV3_ALERT_HANDSHAKE_FAILURE`, because the
  mangled ClientHello hits a server that answers in plaintext or with a fatal
  alert.

## Decide the lever first

Before adding an entry, classify the failure on a client behind the router, not
on the router itself:

```sh
dig +short @192.168.1.1 <host>        # DNS answers, or the blocklist ate it
nc -z <ip> 443                        # TCP opens even when TLS will hang
openssl s_client -connect <ip>:443 -servername <host> </dev/null
```

- Hangs only for one SNI, from every address: ISP SNI filter. The name should
  **not** be excluded — it needs the bypass.
- Instant alert, plaintext reply, or a TLS **protocol** error such as
  `UNSOLICITED_EXTENSION`, `INVALID_SESSION_ID` or a connection reset, for every
  SNI including `example.com`: not a filter, a server that desync breaks. The
  name should be excluded.
- Alternating between addresses across repeated probes: edge flakiness, not a
  config defect. No list entry fixes it.
- Timeout **in both states** — with desync applied and with the name excluded:
  the entry buys nothing at all, because the address is unreachable rather than
  mangled. Drop it and use the routing lever (the foreign VPN list) instead;
  keeping it in the exclude list only denies the name the bypass if the filter
  ever becomes the cause.

Re-probe after the entry lands, and probe more than once: on these paths a
single result in either direction is noise. `CERTIFICATE_VERIFY_FAILED` after
the change is a **success** — the handshake completed and only the leaf does not
cover the probed hostname.

The Alipay measurement in `dpi-bypass.md` is the worked example of all four.

## Edit the entry

Entries live in `zapret-exclude-ensure.lst`, one per line:

- `+name` keep present and active in the router's list.
- `-name` comment out an active line (`cloudfront.net` is the current one, so
  the Duolingo web CDNs get the bypass the ISP denies them).

```sh
cd ~/PhpstormProjects/domains.lst
printf '+%s\n' 'example.com' >> zapret-exclude-ensure.lst
git commit -am 'zapret: skip desync for example.com'
git push
```

Check for an existing entry before adding: the shipped list already carries
names such as `stepfun.ai`, and a duplicate in the ensure list is a no-op that
reads like a fix.

## Apply

```sh
ssh router '/opt/zapret/exclude-ensure.sh'
```

The script downloads the list from
`raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/zapret-exclude-ensure.lst`,
edits `/opt/zapret/ipset/zapret-hosts-user-exclude.txt` only where it is out of
line, and restarts zapret only when something changed. It is idempotent: a
second run prints nothing.

There is no cron entry, so a change reaches the router only when the script is
run. A failed download is fatal: three retries, then exit 1 with the list left
untouched, because an ensure running on an empty list would delete the entries
it protects. `REPO_URL` overrides the source.

## Never do this

- Do not hand-edit `/opt/zapret/ipset/zapret-hosts-user-exclude.txt` as the fix.
  The zapret LuCI app rewrites the ipset files from its own copy on Save, which
  silently drops hand edits, and the repo copy then drifts from the live one.
  If a one-off manual edit is unavoidable, mirror it into
  `zapret-exclude-ensure.lst` and push in the same change.
- Do not edit the repo file without pushing, then run the script: it fetches the
  published URL, so the local commit alone changes nothing.

## Verify

```sh
ssh router '/opt/zapret/exclude-ensure.sh'      # prints what it changed
ssh router 'logread | grep zapret | tail'       # exclude hostlist verdict
```

Then re-run the three probes above from a client behind the router. The router's
own `openssl s_client` is not a usable probe; measure from the client.
