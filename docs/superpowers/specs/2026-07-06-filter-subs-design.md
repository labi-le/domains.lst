# Subscription Filter Script Design

Date: 2026-07-06
Status: approved (design discussed and accepted in chat)

## Purpose

The proxy subscriptions used by the router (`aetris`, `purple`, `mifa`) contain many dead or slow nodes. This project adds a workstation-side script that tests every node through a disposable Mihomo instance and publishes only stable, fast nodes as a single filtered subscription file served from this repository.

## Data Flow

```
subs/sources.txt            original subscription URLs (name + url per line)
        |
        v
filter-subs.sh              fetch -> merge -> label -> test -> filter
        |
        v  (docker: metacubex/mihomo, N delay rounds via REST API)
subs/stable.txt             surviving share links, sorted by mean delay
        |
        v  git commit + push (manual)
router provider `stable`:
http://192.168.1.2:7008/?subscription_url=https://raw.githubusercontent.com/labi-le/domains.lst/main/subs/stable.txt
```

The router keeps fetching through the existing converter at `192.168.1.2:7008`, which already proxies GitHub raw URLs today. No new reachability assumptions on the router side.

## Components

### 1. `subs/sources.txt`

- Format: `name url` per line, `#` starts a comment, blank lines ignored.
- `name` must match `[a-z0-9-]+`; it becomes the node label prefix.
- Initial content: the three sources currently embedded in `mihomo/config.yaml` provider URLs:
  - `mifa https://mifa.world/vless`
  - `aetris https://raw.githubusercontent.com/flaafix/AetrisVPN-black-list/refs/heads/main/configs.txt`
  - `purple https://raw.githubusercontent.com/Animeblin1/sukasubs/refs/heads/main/purple.txt`

### 2. `filter-subs.sh` (repo root, bash, style matches `fetch-mihomo.sh`)

Stages:

1. **Deps check**: `curl`, `jq`, `docker` must exist; die with a clear message otherwise.
2. **Fetch**: download each source with `curl`. If the payload has no `://` scheme lines, try base64-decoding it (standard v2ray subscription encoding). A failed source prints a warning and is skipped; if all sources fail, abort.
3. **Merge + dedupe**: concatenate all share links, drop duplicates by `host:port` (first occurrence wins).
4. **Label rewrite**: rewrite each link's display name to `<source>-<NNN>` (e.g. `aetris-001`):
   - `vless://`, `trojan://`, `ss://`: replace the URI fragment (`#name`).
   - `vmess://`: base64-decode the JSON payload, rewrite `ps` with `jq`, re-encode.
   - Unknown schemes: keep the line untouched, append a fragment only if absent.
   - Mihomo derives node names from these labels, so API results map back to source links with zero ambiguity.
5. **Test instance**: write the merged list as a `type: file` proxy-provider payload plus a minimal Mihomo config into a temp dir; run `docker run --rm -d --network host -v <tmpdir>:/root/.config/mihomo metacubex/mihomo:latest`; poll `GET /version` on the controller until ready (30 s budget).
6. **Delay rounds**: `ROUNDS` times call `GET /group/TEST/delay?url=<TEST_URL>&timeout=<TIMEOUT_MS>&expected=204`, sleeping `ROUND_PAUSE` seconds between rounds. Each response maps node name -> delay ms; a node missing from a response counts as a failure for that round.
7. **Aggregate + filter** (`jq`): per node compute success count and mean delay. Keep nodes with `failures <= MAX_FAIL` and `mean <= MAX_AVG_MS`.
8. **Emit**: write survivors' share links to `subs/stable.txt`, sorted by mean delay ascending. Print a report table (name, mean ms, failures, verdict) to stdout. If zero nodes survive, abort without touching `subs/stable.txt`.
9. **Cleanup**: `trap` stops the container and removes the temp dir on any exit path.

### 3. Test Mihomo config (generated into the temp dir)

- `external-controller: 127.0.0.1:19090` (non-default port to avoid collisions).
- DNS server and TUN disabled; no tproxy; `log-level: warning`; `mode: rule` with `rules: [MATCH,DIRECT]`.
- Proxy-provider `merged`: `type: file`, pointing at the merged URI list; `health-check.enable: false` so nothing tests nodes except our explicit API calls.
- Proxy-group `TEST`: `type: select`, `include-all: true`.

### 4. Tunables (environment variables with defaults)

| Variable | Default | Meaning |
| --- | --- | --- |
| `ROUNDS` | `5` | delay test rounds |
| `TIMEOUT_MS` | `2000` | per-node delay timeout |
| `MAX_FAIL` | `0` | max failed rounds a surviving node may have |
| `MAX_AVG_MS` | `1000` | max mean delay |
| `ROUND_PAUSE` | `3` | seconds between rounds |
| `TEST_URL` | `https://www.gstatic.com/generate_204` | probe URL |
| `CONTROLLER` | `127.0.0.1:19090` | external controller address |
| `MIHOMO_IMAGE` | `metacubex/mihomo:latest` | docker image |
| `SOURCES_FILE` | `subs/sources.txt` | input list |
| `OUTPUT_FILE` | `subs/stable.txt` | output list |

### 5. `shell.nix`

- Add helper `mihomo-filter-subs() { bash ./filter-subs.sh "$@"; }` and a menu line in the shell hook. Docker is expected from the host system (daemon required anyway); the script checks for it.

### 6. `mihomo/config.yaml` (one-time follow-up change)

After the first `subs/stable.txt` is committed and pushed to `main`:

- Replace the three `proxy-providers` entries with a single `stable` provider using the converter URL wrapping the raw `stable.txt` link (keep `exclude_groups=geo_blocked` and current health-check block, `path: ./providers/stable.yaml`).
- Change `VPN-ALL-AUTO` to `use: [stable]`.
- Validate with `nix-shell --run 'mihomo-yaml-check && mihomo-validate'`.
- Router deploy stays a separate, explicitly requested action (`router-deploy` skill).

## Edge Cases

- Source unreachable -> warning, continue; all sources unreachable -> abort, output untouched.
- Zero survivors -> abort with report, output untouched (router keeps the last good list).
- Docker missing or API not ready within 30 s -> die with message, cleanup runs.
- Duplicate node labels are impossible by construction (unique `<source>-<NNN>` labels).
- Measurement vantage: tests run from the workstation behind the router; traffic to proxy endpoints leaves via `MATCH,DIRECT`, matching the router's own path to those nodes, so results are representative.

## Verification

- `nix-shell -p shellcheck --run 'shellcheck filter-subs.sh'`
- `nix-instantiate --parse shell.nix`
- Real end-to-end run: `nix-shell --run 'mihomo-filter-subs'` must produce a non-empty `subs/stable.txt` and a sane report.
- After the config change: `nix-shell --run 'mihomo-yaml-check && mihomo-validate'`.

## Out of Scope

- Bandwidth/download speed testing.
- Cron/CI automation of the filtering run.
- Router deployment (separate explicit action).
