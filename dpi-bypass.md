# DPI bypass on the router

The OpenWrt box at `192.168.1.1` runs zapret (`nfqws`) and mihomo. Neither is
nix-managed; both are edited in place, so this file is the record.

zapret runs a single `nfqws` with six profiles, matched in order. The one that
carries ordinary web traffic is

```
--filter-tcp=80,443
--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
--dpi-desync=fake multisplit --dpi-desync-split-seqovl=664 ...
```

It desyncs **everything except** the names in that exclude list. A name in the
list gets no bypass at all — which is the whole failure mode below.

## The ISP filters TLS by exact SNI

Not by IP, and not by suffix. Measured 2026-09-26 from `pc`:

| Target | SNI sent | Result |
|---|---|---|
| `18.165.140.41` | `simg-ssl.duolingo.com` | TLS ok, 0.02 s |
| `18.165.140.41` | `d1vq87e9lcf771.cloudfront.net` | handshake timeout, 6 s |
| `18.165.140.41` | `example.cloudfront.net` | TLS alert in 0.02 s — reached the server |
| `52.85.222.97` | `simg-ssl.duolingo.com` | TLS ok, 0.03 s |

The same address answers or hangs depending only on the name in the
ClientHello, and a nonexistent `*.cloudfront.net` name passes, so this is a
list of specific distribution names rather than a block of the CDN.

TCP is never the signal: `connect()` to every one of these addresses succeeds
in 0.01 s. A tool that only checks the port will report the host healthy.

## Two opposite failures, both silent audio

The exclude list can break an app by holding a name **or** by missing one.
Duolingo produced one of each on 2026-09-26.

### Excluded when it needed the bypass — the browser

The web app serves assets from `d1vq87e9lcf771`, `d2pur3iezf4d1j` and
`d1btvuu4dwu627` under `cloudfront.net`, and the ISP filters exactly those SNIs.
`cloudfront.net` sat in the exclude list, so they got no desync and their
handshakes hung. Removing the line and restarting zapret:

```sh
sed -i 's/^cloudfront\.net$/#cloudfront.net/' \
  /opt/zapret/ipset/zapret-hosts-user-exclude.txt
/etc/init.d/zapret restart
```

Measured immediately after, same three names, same addresses: TLS ok in 0.02 to
0.03 s, all three. Revert by deleting the `#`; `/tmp/exclude.bak` holds the
pre-change file until the router reboots.

Collateral was checked, not assumed: `d3js.org`, `www.imdb.com`, `slack.com`,
`www.reddit.com`, `cdn.jsdelivr.net`, `assets.nflxext.com` and `www.amazon.com`
all still complete TLS with the desync now applied to CloudFront.

### Not excluded when desync breaks it — the Android app

This is what actually silenced the phone, and the CloudFront fix did nothing
for it. The app does not use the `.com` CDNs at all. It fetches audio from
`tts-static.duolingo.cn` and images from `simg-ssl.duolingo.cn`, both served by
Alibaba (`Server: Tengine`, `Via: ens-cache*`) out of `43.109.100.0/24`.
`duolingo.com` was in the exclude list; `duolingo.cn` was not, so the generic
profile split their ClientHello — and that CDN answers a mangled handshake with
**plaintext HTTP**:

```
HTTP/1.1 400 Bad Request
Server: Tengine
```

which OpenSSL reports as `WRONG_VERSION_NUMBER`, not as a timeout. Fixed by
adding `duolingo.cn` next to `duolingo.com` in the exclude list. Measured after
the restart: TLSv1.3 in 0.10 s to `43.109.100.186` and `.187`, `curl` 403 from
the CDN root, and the router log flipped to
`exclude hostlist check for duolingo.cn : positive`.

Nothing regenerates the exclude list — no cron entry and no update hook
references it — so both edits survive until someone rewrites the file by hand.

### Telling the two apart

The error shape names the cause, and they are opposites:

| Symptom on 443 | Cause | Fix |
|---|---|---|
| handshake hangs to timeout | ISP SNI filter, no bypass applied | remove from exclude |
| instant `WRONG_VERSION_NUMBER`, plaintext reply | desync applied to a server that cannot take it | add to exclude |

The router's own log settles it without guessing —
`/tmp/zapret+nfqws+3+main.log` prints `exclude hostlist check for <host>` with
its verdict, and
`grep -oE "hostname='[^']*'"` over that file lists the names real clients are
actually asking for. That is how the `.cn` endpoints were found: nothing on the
PC ever requests them.

## The edits get reverted, and by what

Both fixes above were live and verified, and on 2026-10-08 they were gone:
`duolingo.cn` deleted, `cloudfront.net` uncommented, file mtime 17:57. The
failure looked new for a while — the `.cn` hosts then answered with
`SSLV3_ALERT_HANDSHAKE_FAILURE` instead of the earlier plaintext 400 — but the
alert was a symptom of the same cause: desync applied again to a host that
cannot take it. Proving that was cheap: the host rejected **every** SNI,
including `example.com`, which no ISP filter bothers to block.

What reverts it: `/opt/zapret/ipset/zapret-hosts-user-exclude.txt` is
hand-maintained. Nothing cron-like writes it, `/etc/config/zapret` only names
its path, and `/etc/init.d/zapret` never regenerates it — but the **LuCI zapret
app is installed** at `/www/luci-static/resources/view/zapret`, and pressing
Save in it rewrites the ipset files from its own copy. Saving there undoes
every hand edit, and the symptom returns as "Duolingo broke again" with nothing
in the log explaining why.

So: to change the exclude list, either edit the file and restart zapret, or
make the same change in LuCI and restart. Never both — LuCI will clobber the
file one and not warn. Reapply is the same two `sed` lines plus
`/etc/init.d/zapret restart`; the pre-drift copies are kept in `/tmp` on the
router until reboot.

## The script that keeps it applied

The list lives here: `zapret-hosts-user-exclude.txt` maps to
`/opt/zapret/ipset/zapret-hosts-user-exclude.txt` per `AGENTS.md`. Three files:

- `zapret-hosts-user-exclude.txt` — the list itself. The repo copy had drifted
  by 84 lines, including the per-app sections maintained on the router, so it
  was replaced with the live file rather than hand-patched; the two now carry
  the same md5.
- `zapret-exclude-ensure.lst` — the entries the script asserts, one per line
  with a `+`/`-` prefix: `+duolingo.com`, `+duolingo.cn`, `-cloudfront.net`.
- `zapret-exclude-ensure.sh` — installed as `/opt/zapret/exclude-ensure.sh`.
  Idempotent "ensure", not an append: it adds the `+` names and comments out an
  active `-` name, then restarts zapret only if something changed, so a quiet
  cron run costs no bypass outage. It exits 1 when either file is missing, so a
  botched install shows up in the log instead of passing silently.

Cron runs it every five minutes, so a LuCI save is repaired within one interval
without anyone noticing, and its path is in `/etc/sysupgrade.conf`. Note that
the rest of `/opt/zapret` is **not** backed up, so a firmware upgrade still
loses zapret itself and its shipped lists; only the script survives, and it
will then re-apply the entries to whatever fresh list appears.

Verified by reproducing the clobber: with `duolingo.cn` deleted and
`cloudfront.net` reactivated, all three hosts failed TLS; after one run of the
script they handshaked again, and a second run was silent. The router's own
`openssl s_client` is not a usable probe for this — measure from a client
behind the router instead.

One unresolved question, raised by an earlier version of this file's list: it
carried a comment claiming the **active** `cloudfront.net` line is load-bearing,
because a trailing `--hostlist-domains` profile names the three Duolingo hosts
explicitly. That profile is not in `/etc/config/zapret` any more — the only
`--hostlist-domains` left is `discord.media` — so the commented catch-all is
what carries those three hosts now. If that trailing profile is restored, the
`-cloudfront.net` entry should be dropped and the catch-all left alone.

## Still broken, same mechanism

`aws.amazon.com` times out in TLS exactly like the audio CDNs did. It matches
`amazon.com`, which is a separate entry in the same exclude list, so it is
excluded from the bypass for the same reason. It was broken before this change
and is untouched by it. Removing that entry would fix it the same way; it was
left alone because nobody asked for it.

## Diagnosing the next one

The symptom to recognise is an application that works while one class of its
content is silently missing. Three commands separate the causes:

```sh
dig +short @192.168.1.1 <host>            # DNS answers, or the blocklist ate it
nc -z <ip> 443                            # TCP opens even when TLS will hang
openssl s_client -connect <ip>:443 -servername <host> </dev/null
```

If the third hangs while the second succeeds, it is SNI filtering. Then check
whether the name, or any suffix of it, is in
`/opt/zapret/ipset/zapret-hosts-user-exclude.txt`.
