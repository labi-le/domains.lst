# network-tools

###### [spasibo](https://github.com/itdoginfo/domain-routing-openwrt)

#### murmur (the router's proxy)

murmur replaced mihomo as the router's proxy. It takes over the same ports
(DNS `12344`, tproxy `12342`), so nftables and dnsmasq are unchanged.

```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/murmur/init.d -O /etc/init.d/murmur &&
chmod +x /etc/init.d/murmur

wget https://raw.githubusercontent.com/labi-le/domains.lst/main/murmur/config -O /etc/config/murmur

mkdir -p /etc/murmur /etc/proxy /tmp/murmur.d/rules &&
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/murmur/config.yaml -O /etc/murmur/config.yaml
```

#### pbr

Fetches the rule lists, writes the nft rules, restarts the proxy.

```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/pbr -O /etc/init.d/pbr &&
chmod +x /etc/init.d/pbr &&
service pbr enable &&
service pbr start
```

#### runtime layout

```text
/etc/proxy/murmur.bin.xz  -> compressed binary, on flash
/etc/murmur/config.yaml   -> static config, on flash
/tmp/murmur.bin           -> the binary, unpacked from the compressed copy
/tmp/murmur.d/cache.db    -> mutable cache
/tmp/murmur.d/rules/*     -> rule lists, refetched by pbr and reloaded on change
/tmp/murmur.d/providers/* -> downloaded proxy providers
```

The rule lists are deliberately kept in tmpfs: they are refetched weekly and would
otherwise cost a flash erase cycle every time. The binary cannot follow that rule
because it has to exist before the network is up.

The binary is 25 MB and the overlay has about 12 MB free, so it cannot live in
flash uncompressed. The init script keeps an `xz` copy on flash and unpacks it
into tmpfs on every boot. If the compressed copy is missing, it downloads the
binary from the cache host and verifies the SHA-256 before running it.

#### proxy-ctl

```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/proxy-ctl.sh -O /root/proxy-ctl.sh &&
chmod +x /root/proxy-ctl.sh

/root/proxy-ctl.sh status   # show the state
/root/proxy-ctl.sh check    # verify DNS, tproxy and the fake-IP routing
/root/proxy-ctl.sh restart  # restart the proxy and flush the DNS cache
/root/proxy-ctl.sh refresh  # refetch the rule lists and rewrite the nft rules
```

#### weekly refresh

```sh
sh -c '(crontab -l 2>/dev/null; echo "0 6 * * 0 /etc/init.d/pbr start") | crontab -'
```

#### firmware upgrades

The proxy files are listed in `/etc/sysupgrade.conf`, so a firmware upgrade keeps
the configuration. The binary is not in the backup list: 7.6 MB of compressed
binary does not fit into the upgrade image, and the init script can fetch it
from the cache host instead.

#### packages

The router needs `xz` to unpack the binary:

```sh
opkg update && opkg install xz
```

#### mihomo (removed)

mihomo was removed from the router on 2026-11-03. The files below are kept in
this repository for reference only and are no longer deployed.

```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/init.d -O /etc/init.d/mihomo &&
chmod +x /etc/init.d/mihomo

wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/config -O /etc/config/mihomo

mkdir -p /etc/mihomo &&
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/mihomo/config.yaml -O /etc/mihomo/config.yaml
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
