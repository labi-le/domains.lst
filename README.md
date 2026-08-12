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

#### runtime layout
```text
/etc/mihomo/config.yaml  -> static config
/tmp/mihomo/cache.db     -> mutable cache
/tmp/mihomo/rules/*      -> generated rule providers
/etc/mihomo/rules/*      -> persisted copy, seeded back into /tmp at boot
/tmp/mihomo/providers/*  -> downloaded proxy providers
```

#### block ipv6 youtube
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/youtube-ipv6-block -O /etc/init.d/youtube-ipv6-block &&
chmod +x /etc/init.d/youtube-ipv6-block &&
service youtube-ipv6-block enable &&
service youtube-ipv6-block start
```

#### external-dns
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/external-dns -O /etc/init.d/external-dns &&
chmod +x /etc/init.d/external-dns &&
service external-dns enable &&
service external-dns start
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
