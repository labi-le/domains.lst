# domains.lst

#### update /etc/init.d/getdomains for multiply list support
```sh
wget https://raw.githubusercontent.com/labi-le/domains.lst/main/getdomains -O /etc/init.d/getdomains && chmod +x /etc/init.d/getdomains
```

```sh
service getdomains restart
```
