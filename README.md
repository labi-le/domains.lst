# network-tools

###### [spasibo](https://github.com/itdoginfo/domain-routing-openwrt)

#### murmur (the router's proxy)

murmur replaced mihomo as the router's proxy. It takes over the same ports
(DNS `12344`, tproxy `12342`), so nftables and dnsmasq are unchanged.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/labi-le/murmur/main/packaging/openwrt/install.sh)"

mkdir -p /etc/murmur /tmp/murmur.d/rules &&
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/murmur/config.yaml -O /etc/murmur/config.yaml &&
service murmur enable &&
service murmur restart
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
/usr/bin/murmur           -> the binary
/etc/murmur/config.yaml   -> static config, on flash
/tmp/murmur.d/cache.db    -> mutable cache
/tmp/murmur.d/rules/*     -> rule lists, refetched by pbr and reloaded on change
/tmp/murmur.d/providers/* -> downloaded proxy providers
```

The rule lists are deliberately kept in tmpfs: they are refetched weekly and would
otherwise cost a flash erase cycle every time. The binary lives on flash like any
other package because it has to exist before the network is up.

The overlay is a 37 MB UBI volume, so the binary is built without
`extra-protocols` (see `MURMUR_INSTALL.md`). That drops the hysteria2, anytls and
tuic outbounds; vless, ss and vmess are unaffected.

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
