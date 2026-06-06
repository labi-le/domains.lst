# Reference Map

## Repo -> Router

| repo path | router path | role | state |
| --- | --- | --- | --- |
| `mihomo/config.yaml` | `/etc/mihomo/config.yaml` | Main Mihomo static config (awg0=BY, awg1=WARP, awg2=FI) | static |
| `mihomo/init.d` | `/etc/init.d/mihomo` | Procd service script for Mihomo | static |
| `mihomo/config` | `/etc/config/mihomo` | UCI service settings for Mihomo | static |
| `pbr` | `/etc/init.d/pbr` | Regenerates rule-provider files and WARP IP set, then restarts Mihomo | static |
| `external-dns` | `/etc/init.d/external-dns` | Updates external router DNS record in UCI/dnsmasq | static |
| `youtube-ipv6-block` | `/etc/init.d/youtube-ipv6-block` | IPv6 blocking helper for YouTube | static |
| `(not tracked)` | `/tmp/mihomo/cache.db` | Mihomo mutable cache database | runtime |
| `(not tracked)` | `/tmp/mihomo/rules/vpn.txt` | Generated VPN rule-provider file | runtime |
| `(not tracked)` | `/tmp/mihomo/rules/warp.txt` | Generated WARP rule-provider file | runtime |
| `(not tracked)` | `/tmp/mihomo/providers/mos-eu.yaml` | Downloaded proxy-provider cache | runtime |

## Sources

| consumer | kind | url | purpose |
| --- | --- | --- | --- |
| `pbr` | VPN rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/geoblock.lst` | Base geoblock VPN domains |
| `pbr` | VPN rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/google_ai.lst` | AI service VPN domains |
| `pbr` | VPN rule set | `https://raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/custom-set.txt` | Local custom VPN domains |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/block.lst` | Base blocked domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/porn.lst` | Porn domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/anime.lst` | Anime domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/news.lst` | News domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/twitter.lst` | Twitter/X domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/telegram.lst` | Telegram domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/meta.lst` | Meta domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/custom-set_cis.txt` | Local custom CIS domains for WARP |
| `pbr` | WARP IP set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/telegram.lst` | Telegram IPv4 ranges |
| `pbr` | WARP IP set | `https://raw.githubusercontent.com/routir/unblock/refs/heads/main/services/viber-ip-de.lst` | Viber IPv4 ranges |
| `mihomo` | proxy-provider | `https://hub.mos.ru/zieng2/wl/raw/main/list_universal.txt` | Subscription feed for preferred EU VPN nodes |
| `mihomo` | URL test | `https://ifconfig.io/` | Probe URL for `VPN-SUB-EU` |
| `mihomo` | fallback health | `https://ifconfig.io/` | Probe URL for `VPN-PREFERRED` |
