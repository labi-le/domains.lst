# network-tools

###### [spasibo](https://github.com/itdoginfo/domain-routing-openwrt)

#### mihomo init script
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/init.d -O /etc/init.d/mihomo &&
chmod +x /etc/init.d/mihomo
```

#### mihomo uci config
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/config -O /etc/config/mihomo
```

#### mihomo static config
```sh
mkdir -p /etc/mihomo &&
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/config.yaml -O /etc/mihomo/config.yaml
```

#### disable the dnsmasq cache
Required. A caching `dnsmasq` pins a real address for its upstream TTL, while a
correct fake-IP answer carries TTL 1 — see `ARCHITECTURE.md`.
```sh
uci set dhcp.@dnsmasq[0].cachesize='0' &&
uci commit dhcp &&
service dnsmasq restart
```

#### pbr
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/pbr -O /etc/init.d/pbr &&
chmod +x /etc/init.d/pbr &&
service pbr enable &&
service pbr start
```

`pbr` takes the fake-IP subnet from `fake-ip-range` in `/etc/mihomo/config.yaml`, so install the
static config first; without that key it logs and exits 1 instead of writing TPROXY rules for a
guessed subnet. The subnet is `198.18.0.0/16`, which `lo` must carry — a separate UCI setting that
no file here derives or enforces:
```sh
uci -q delete network.loopback.ipaddr &&
uci add_list network.loopback.ipaddr='127.0.0.1' &&
uci add_list network.loopback.ipaddr='198.18.1.1/16' &&
uci commit network &&
service network reload
```
`pbr` warns at every start when no `lo` prefix covers the configured range; it does not change the
network config itself. Measured with `lo` left at `198.18.1.1/24`: `ip route get 198.18.0.5` on the
router answers `via 93.100.194.1 dev wan`, so the router's own traffic to fake IPs outside the old
`/24` leaves via the raw WAN. LAN clients still work, because they reach mihomo through the fwmark
lookup.

Its warnings go to syslog as well as stderr, so the weekly cron run is auditable:
```sh
logread -e pbr
```
A source that answers with a non-empty body yielding zero valid entries — a captive portal's HTML
`200` — counts as a failed source like one that never answered, and one failed source means that
list is not installed at all; the previous file stays.

#### runtime layout
```text
/etc/mihomo/config.yaml  -> static config
/tmp/mihomo/cache.db     -> mutable cache
/tmp/mihomo/rules/*      -> generated rule providers
/etc/mihomo/rules/*      -> persisted copy, seeded back into /tmp at boot
/tmp/mihomo/providers/*  -> downloaded proxy providers
```

#### external-dns
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/external-dns -O /etc/init.d/external-dns &&
chmod +x /etc/init.d/external-dns &&
service external-dns enable &&
service external-dns start
```

#### zapret exclusions
The 80/443 `nfqws` profile desyncs everything it is not told to skip, so a CDN that
breaks under desync needs its name here. `duolingo.cn` is on the list for exactly that
reason: without it the audio CDN answers nothing.
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/zapret-hosts-user-exclude.txt -O /opt/zapret/ipset/zapret-hosts-user-exclude.txt &&
/etc/init.d/zapret restart
```
Verify a name is skipped rather than desynced — `403` is the CDN answering, `000` is the
desync killing the handshake.
```sh
curl -s -o /dev/null -m 8 -w '%{http_code}\n' https://tts-static.duolingo.cn/
```

#### weekly refresh
`service pbr enable` only schedules `pbr` at boot — the crontab entry is a separate
step, easy to forget.
```sh
sh -c '(crontab -l 2>/dev/null; echo "0 6 * * 0 /etc/init.d/pbr start") | crontab -'
```
Freshness is the mtime of the generated files, nothing else. A date older than a week
means the refresh never ran, whatever `service pbr enabled` reports.
```sh
ls -l /etc/mihomo/rules/
```

#### packages
```sh
opkg install dnsmasq-full mihomo stubby ca-bundle curl amneziawg-tools kmod-amneziawg
```
