# domains.lst

###### [spasibo](https://github.com/itdoginfo/domain-routing-openwrt)

#### pbr
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/pbr -O /etc/init.d/pbr && chmod +x /etc/init.d/pbr
```

#### pbr-noyt
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/pbr-noyt -O /etc/init.d/pbr-noyt && chmod +x /etc/init.d/pbr-noyt
```

#### pbr-yt
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/pbr-yt -O /etc/init.d/pbr-yt && chmod +x /etc/init.d/pbr-yt
```

```sh
service [name] restart
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
