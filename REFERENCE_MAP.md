# Reference Map

## Repo -> Router

| repo path | router path | role | state |
| --- | --- | --- | --- |
| `murmur/config.yaml` | `/etc/murmur/config.yaml` | Main murmur static config (awg0=BY, awg1/awg2=WARP/FI) | static |
| `murmur/init.d` | `/etc/init.d/murmur` | Procd service script; unpacks the binary and seeds the workdir | static |
| `murmur/config` | `/etc/config/murmur` | UCI service settings for murmur | static |
| `pbr` | `/etc/init.d/pbr` | Regenerates the rule files and the TPROXY IP set, then restarts the proxy | static |
| `proxy-ctl.sh` | `/root/proxy-ctl.sh` | Admin helper: status, check, restart, refresh | static |
| `external-dns` | `/etc/init.d/external-dns` | Updates external router DNS record in UCI/dnsmasq | static |
| `youtube-ipv6-block` | `/etc/init.d/youtube-ipv6-block` | IPv6 blocking helper for YouTube | static |
| `(not tracked)` | `/etc/proxy/murmur.bin.xz` | Compressed murmur binary (xz -6, about 7.6 MB) | binary |
| `(not tracked)` | `/tmp/murmur.bin` | The unpacked binary, unpacked from the compressed copy on boot | runtime |
| `(not tracked)` | `/tmp/murmur.d/cache.db` | murmur mutable cache database | runtime |
| `(not tracked)` | `/tmp/murmur.d/rules/*.txt` | Rule lists, written by pbr, reloaded by murmur on change | runtime |
| `(not tracked)` | `/tmp/murmur.d/providers/*.yaml` | Downloaded proxy-provider cache | runtime |
| `(not tracked)` | `/etc/nftables.d/99-tproxy.nft` | TPROXY rules, rendered by pbr | generated |

### Removed

mihomo was removed from the router and from this repository on 2026-11-03. Its
files remain in git history (`git log --all -- mihomo/`).

## Sources

| consumer | kind | url | purpose |
| --- | --- | --- | --- |
| `pbr` | realip rule set | `https://raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/realip.txt` | Domains that must bypass the proxy |
| `pbr` | VPN rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/geoblock.lst` | Base geoblock VPN domains |
| `pbr` | VPN rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/google_ai.lst` | AI service VPN domains |
| `pbr` | VPN rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/tiktok.lst` | TikTok VPN domains |
| `pbr` | VPN rule set | `https://raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/custom-set.txt` | Local custom VPN domains |
| `pbr` | Telegram rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/telegram.lst` | Telegram domains |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/block.lst` | Base blocked domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/porn.lst` | Porn domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/anime.lst` | Anime domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/news.lst` | News domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/twitter.lst` | Twitter/X domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/meta.lst` | Meta domains for WARP |
| `pbr` | WARP rule set | `https://raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/custom-set_cis.txt` | Local custom CIS domains for WARP |
| `pbr` | TPROXY IP set | `https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/telegram.lst` | Telegram IPv4 ranges |
| `pbr` | TPROXY IP set | `https://raw.githubusercontent.com/routir/unblock/refs/heads/main/services/viber-ip-de.lst` | Viber IPv4 ranges |
| `murmur` | proxy-provider | `http://192.168.1.2:7008/stable.txt` | Pre-filtered node list from the sub-preprocessor |
| `murmur` | URL test | `https://platform.claude.com/` | Probe URL for `VPN-ALL-AUTO` and `VPN` |
| `murmur` | fallback health | `http://captive.apple.com/` | Off-net probe URL for the `WARP` group |
| `fetch-murmur.sh` | release | `https://api.github.com/repos/labile-le/murmur/releases/latest` | Release metadata |
| `murmur/init.d` | binary fallback | `https://cache.labile.cc/serve/5sfjlphiywgmn76k76q1wzv87xdzaqdf/` | Binary download when the flash copy is missing |
