# Subs Updater Docker Service Design

Date: 2026-07-06
Status: approved

## Purpose

Automate the subscription filtering pipeline: a Docker Compose stack re-runs
`filter-subs.sh` every 30 minutes and serves the resulting `stable.txt` over
local HTTP, so the router always fetches a fresh pre-filtered node list
without manual runs or git pushes.

## Data Flow

```
subs/sources.txt (mounted ro)
        |
        v
updater container: filter-subs.sh (MIHOMO_BIN mode, in-container test instance)
        |
        v  atomic replace
subs-data volume: /data/stable.txt
        |
        v  read-only mount
web container: nginx:alpine  ->  http://192.168.1.2:7009/stable.txt
        |
        v
router mihomo proxy-provider `stable` (direct URL, no converter)
```

## Components

### updater service

- Image built from `Dockerfile` in repo root, multi-stage:
  - stage 1: `metacubex/mihomo:latest` (source of the static `mihomo` binary)
  - stage 2: `alpine` + `bash curl jq coreutils grep gawk` +
    `COPY --from=mihomo` binary to `/usr/local/bin/mihomo`
- `docker/entrypoint.sh`: infinite loop — run `filter-subs.sh`, log outcome,
  `sleep "$INTERVAL_SEC"` (default 1800). First run starts immediately.
  A failed run never aborts the loop.
- Mounts:
  - `./filter-subs.sh` -> `/app/filter-subs.sh` (ro; script edits need no rebuild)
  - `./subs/sources.txt` -> `/config/sources.txt` (ro)
  - `subs-data` named volume -> `/data`
- Environment: `MIHOMO_BIN=/usr/local/bin/mihomo`,
  `SOURCES_FILE=/config/sources.txt`, `OUTPUT_FILE=/data/stable.txt`,
  `INTERVAL_SEC=1800`, plus optional pass-through of the existing tunables
  (`ROUNDS`, `MAX_FAIL`, `MAX_AVG_MS`, `TIMEOUT_MS`, ...).
- No docker socket, no published ports. The test mihomo instance runs as a
  background process inside the container, controller on `127.0.0.1:19090`.

### web service

- `nginx:alpine`, mounts `subs-data` volume read-only at
  `/usr/share/nginx/html`, publishes port `7009:80`.
- Independent lifecycle: keeps serving the last good `stable.txt` while the
  updater restarts, rebuilds, or crashes.
- Healthcheck: `wget -q -O /dev/null http://127.0.0.1/stable.txt` (starts
  passing after the first successful updater cycle).

### filter-subs.sh changes

1. **`MIHOMO_BIN` mode**: when the env var is set, start
   `"$MIHOMO_BIN" -d "$WORKDIR"` as a background process instead of
   `docker run metacubex/mihomo`, and kill that PID in the cleanup trap.
   Docker mode stays the default for manual nix-shell runs. The readiness
   poll (`/providers/proxies/merged`) is shared by both modes.
2. **Atomic output**: current `mv "$WORKDIR/..." "$OUTPUT_FILE"` crosses
   filesystems (mktemp dir -> volume), which is copy+unlink, not atomic.
   New behavior: `cp` to `<output dir>/.stable.txt.tmp`, then `mv` within
   the same directory.
3. Dependency check: `docker` is required only when `MIHOMO_BIN` is unset.

### Router config change (one-time, follow-up)

`mihomo/config.yaml` provider `stable` URL becomes
`http://192.168.1.2:7009/stable.txt` — direct, dropping the converter hop:
the payload is already a clean URI list that mihomo parses natively, and
`exclude_groups` is a no-op after relabeling.

## Failure Handling

- Sources unreachable or zero survivors: `filter-subs.sh` dies without
  touching `stable.txt`; entrypoint logs the failure and sleeps until the
  next cycle. nginx keeps serving the previous list.
- Empty volume on first deploy: nginx returns 404 until the first successful
  cycle; the router keeps using its cached `providers/stable.yaml` copy.
- Updater crash loop: `restart: unless-stopped`; web service unaffected.

## Tunables

| Variable | Default | Meaning |
| --- | --- | --- |
| `INTERVAL_SEC` | `1800` | Pause between filter runs |
| `MIHOMO_BIN` | unset | Path to mihomo binary; enables in-container mode |
| (existing) | see `filter-subs.sh` | `ROUNDS`, `MAX_FAIL`, `MAX_AVG_MS`, `TIMEOUT_MS`, `ROUND_PAUSE`, `TEST_URL`, `CONTROLLER` |

## Verification

- `shellcheck filter-subs.sh docker/entrypoint.sh` clean.
- Fixture test re-run unchanged (DRY_RUN path, mode-independent).
- `MIHOMO_BIN` mode smoke-tested locally before any docker build:
  `MIHOMO_BIN=$(command -v mihomo) OUTPUT_FILE=/tmp/... ./filter-subs.sh`
  inside nix-shell produces a survivor list end-to-end.
- `docker compose up -d --build`; wait for first cycle;
  `curl -fsS http://127.0.0.1:7009/stable.txt` returns a URI list.
- Kill updater mid-cycle: `stable.txt` still served, unchanged.
- `nix-shell --run 'mihomo-yaml-check && mihomo-validate'` after the config
  URL change.

## Out of Scope

- Pushing `stable.txt` to GitHub (superseded by local HTTP delivery).
- Router deploy of the new config (separate explicit action).
- Bandwidth testing, node dedup across runs, metrics/alerting.
