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

# weak 06:00
```sh
0 6 * * 0 /etc/init.d/pbr start
```
