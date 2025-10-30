# pbr

###### [spasibo](https://github.com/itdoginfo/domain-routing-openwrt)

#### pbr
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/pbr -O /etc/init.d/pbr && chmod +x /etc/init.d/pbr
```

```sh
service pbr enable && service pbr start
```

#### block ipv6 youtube 
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/youtube-ipv6-block -O /etc/init.d/youtube-ipv6-block && chmod +x /etc/init.d/youtube-ipv6-block
```

```sh
service youtube-ipv6-block enable && service youtube-ipv6-block start 
```

#### every weak 06:00
```sh
sh -c '(crontab -l 2>/dev/null; echo "0 6 * * 0 /etc/init.d/pbr start") | crontab -'
```

#### hotplug.d
```sh
echo 'ip route add table vpn default dev awg0' > /etc/hotplug.d/iface/30-vpn
echo 'ip route add table youtube default dev awg1' > /etc/hotplug.d/iface/40-youtube
```

#### swap
```sh
ip route replace table vpn default dev tun0
```

#### iproute2
```sh
echo '99 vpn' >> /etc/iproute2/rt_tables
echo '98 youtube' >> /etc/iproute2/rt_tables
```
