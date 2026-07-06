# Subs Updater Docker Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Docker Compose stack that re-runs `filter-subs.sh` every 30 minutes and serves `stable.txt` over local HTTP on port 7009.

**Architecture:** Two services — `updater` (alpine + mihomo binary, loops filter-subs.sh in `MIHOMO_BIN` mode, no docker socket) and `web` (nginx:alpine serving a shared `subs-data` volume). Router later fetches `http://192.168.1.2:7009/stable.txt` directly, no converter.

**Tech Stack:** bash, Docker multi-stage build, docker compose, nginx:alpine, metacubex/mihomo binary.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-06-subs-updater-docker-design.md`.
- Commit messages: short lowercase subjects, no footers, no Conventional Commits.
- Never use `/tmp/mihomo` as a scratch path (router runtime dir convention).
- `filter-subs.sh` must keep working unchanged in docker mode via `nix-shell --run mihomo-filter-subs`.
- A failed filter run must never truncate or remove the existing output file.

---

### Task 1: `MIHOMO_BIN` mode + atomic output in filter-subs.sh

**Files:**
- Modify: `filter-subs.sh`

**Interfaces:**
- Consumes: existing env tunables.
- Produces: env knob `MIHOMO_BIN` (path to mihomo binary; empty = docker mode). Atomic output replace within the output directory. Task 2's entrypoint relies on `MIHOMO_BIN=/usr/local/bin/mihomo`, `SOURCES_FILE`, `OUTPUT_FILE` env overrides.

- [ ] **Step 1: run existing fixture to establish green baseline**

Run: `bash /tmp/filter-subs-test/check.sh` — if the fixture was cleaned up, recreate it per the Task 2 fixture description in `docs/superpowers/plans/2026-07-06-filter-subs.md` first.
Expected: PASS (relabel/dedupe assertions).

- [ ] **Step 2: add `MIHOMO_BIN` tunable and PID tracking**

In the tunables block (after `MIHOMO_IMAGE=` line) add:

```bash
MIHOMO_BIN="${MIHOMO_BIN:-}"
```

After `WORKDIR="$(mktemp -d)"` add:

```bash
MIHOMO_PID=""
```

Update the header comment tunables list (line 9-10) to include `MIHOMO_BIN`.

- [ ] **Step 3: mode-aware cleanup and dependency check**

Replace `cleanup()`:

```bash
cleanup() {
  if [ -n "$MIHOMO_PID" ]; then
    kill "$MIHOMO_PID" >/dev/null 2>&1 || true
    wait "$MIHOMO_PID" 2>/dev/null || true
  else
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORKDIR"
}
```

Replace the docker dependency check:

```bash
if [ "$DRY_RUN" != "1" ]; then
  if [ -n "$MIHOMO_BIN" ]; then
    [ -x "$MIHOMO_BIN" ] || die "MIHOMO_BIN is not executable: $MIHOMO_BIN"
  else
    command -v docker >/dev/null 2>&1 || die "docker not found, please install"
    docker info >/dev/null 2>&1 || die "docker daemon unavailable"
  fi
fi
```

- [ ] **Step 4: mode-aware test instance launch and failure log path**

Replace the `docker run` block:

```bash
if [ -n "$MIHOMO_BIN" ]; then
  "$MIHOMO_BIN" -d "$WORKDIR" > "$WORKDIR/mihomo.log" 2>&1 &
  MIHOMO_PID=$!
else
  docker run --rm -d --name "$CONTAINER" --network host \
    -v "$WORKDIR:/root/.config/mihomo" "$MIHOMO_IMAGE" >/dev/null
fi
```

In the not-ready branch replace `docker logs "$CONTAINER" >&2 || true` with:

```bash
  if [ -n "$MIHOMO_PID" ]; then
    cat "$WORKDIR/mihomo.log" >&2 || true
  else
    docker logs "$CONTAINER" >&2 || true
  fi
```

- [ ] **Step 5: atomic output replace**

Replace the final emit lines:

```bash
mkdir -p "$(dirname "$OUTPUT_FILE")"
OUT_TMP="$(dirname "$OUTPUT_FILE")/.stable.txt.tmp"
cp "$WORKDIR/stable.txt" "$OUT_TMP"
mv "$OUT_TMP" "$OUTPUT_FILE"
```

- [ ] **Step 6: verify — shellcheck, fixture, binary-mode smoke**

Run: `nix-shell -p shellcheck --run 'shellcheck filter-subs.sh'` — expect clean.
Run: `bash /tmp/filter-subs-test/check.sh` — expect PASS (DRY_RUN path unaffected).
Run binary-mode e2e inside nix-shell (mihomo package provides the binary):

```sh
nix-shell --run 'MIHOMO_BIN="$(command -v mihomo)" OUTPUT_FILE=/tmp/filter-subs-test/stable-bin.txt ROUNDS=2 ./filter-subs.sh'
```

Expected: "mihomo loaded N nodes", rounds run, survivor list written to `/tmp/filter-subs-test/stable-bin.txt`, exit 0. Verify docker mode still selected by default: `DRY_RUN=1 ./filter-subs.sh | head -3` works without `MIHOMO_BIN`.

- [ ] **Step 7: commit**

```bash
GIT_MASTER=1 git add filter-subs.sh
GIT_MASTER=1 git commit -m "add mihomo binary mode and atomic output"
```

### Task 2: updater image — Dockerfile + entrypoint

**Files:**
- Create: `docker/entrypoint.sh`
- Create: `Dockerfile`

**Interfaces:**
- Consumes: `filter-subs.sh` mounted at `/app/filter-subs.sh` (Task 3 compose), `MIHOMO_BIN` mode from Task 1.
- Produces: image with `mihomo` at `/usr/local/bin/mihomo`, entrypoint loop honoring `INTERVAL_SEC` (default 1800).

- [ ] **Step 1: confirm mihomo binary path in upstream image**

Run: `docker image inspect metacubex/mihomo:latest --format '{{json .Config.Entrypoint}}'` (pull first if needed).
Expected: `["/mihomo"]` — if different, adjust the `COPY --from` path below.

- [ ] **Step 2: write `docker/entrypoint.sh`**

```bash
#!/usr/bin/env bash
# entrypoint for the subs updater: run filter-subs.sh forever, one cycle per INTERVAL_SEC.
set -u

INTERVAL_SEC="${INTERVAL_SEC:-1800}"

while true; do
  echo "cycle start: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if bash /app/filter-subs.sh; then
    echo "cycle ok"
  else
    echo "cycle failed; previous output kept" >&2
  fi
  sleep "$INTERVAL_SEC"
done
```

- [ ] **Step 3: write `Dockerfile`**

```dockerfile
FROM metacubex/mihomo:latest AS mihomo

FROM alpine:3.22
RUN apk add --no-cache bash curl jq coreutils grep gawk
COPY --from=mihomo /mihomo /usr/local/bin/mihomo
COPY docker/entrypoint.sh /app/entrypoint.sh
ENTRYPOINT ["bash", "/app/entrypoint.sh"]
```

- [ ] **Step 4: verify — shellcheck + build**

Run: `nix-shell -p shellcheck --run 'shellcheck docker/entrypoint.sh'` — expect clean.
Run: `docker build -t subs-updater:test .` — expect successful build.
Run: `docker run --rm --entrypoint /usr/local/bin/mihomo subs-updater:test -v` — expect mihomo version banner.

- [ ] **Step 5: commit**

```bash
GIT_MASTER=1 git add Dockerfile docker/entrypoint.sh
GIT_MASTER=1 git commit -m "add subs updater image"
```

### Task 3: docker-compose.yml + live verification

**Files:**
- Create: `docker-compose.yml`

**Interfaces:**
- Consumes: image from Task 2, script mode from Task 1.
- Produces: `subs-data` volume with `/data/stable.txt`; HTTP endpoint `:7009/stable.txt` for Task 4.

- [ ] **Step 1: write `docker-compose.yml`**

```yaml
services:
  updater:
    build: .
    restart: unless-stopped
    environment:
      MIHOMO_BIN: /usr/local/bin/mihomo
      SOURCES_FILE: /config/sources.txt
      OUTPUT_FILE: /data/stable.txt
      INTERVAL_SEC: ${INTERVAL_SEC:-1800}
    volumes:
      - ./filter-subs.sh:/app/filter-subs.sh:ro
      - ./subs/sources.txt:/config/sources.txt:ro
      - subs-data:/data

  web:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "7009:80"
    volumes:
      - subs-data:/usr/share/nginx/html:ro
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1/stable.txt"]
      interval: 60s
      timeout: 5s

volumes:
  subs-data:
```

- [ ] **Step 2: validate compose file**

Run: `docker compose config --quiet`
Expected: exit 0, no output.

- [ ] **Step 3: bring the stack up and watch the first cycle**

Run: `docker compose up -d --build`, then `docker compose logs -f updater` until "cycle ok" (first cycle takes ~1-2 min: fetch + 5 delay rounds).
Expected: "merged: ... unique nodes", "wrote N/M nodes to /data/stable.txt", "cycle ok".

- [ ] **Step 4: verify HTTP delivery**

Run: `curl -fsS http://127.0.0.1:7009/stable.txt | head -3` and `curl -fsS http://127.0.0.1:7009/stable.txt | wc -l`
Expected: vless/trojan/ss URI lines with `#<src>-NNN` fragments; count equals the "wrote N" from the log.

- [ ] **Step 5: resilience check — web survives updater death**

Run: `docker compose stop updater && curl -fsS http://127.0.0.1:7009/stable.txt | wc -l && docker compose start updater`
Expected: same line count while updater is stopped.

- [ ] **Step 6: commit**

```bash
GIT_MASTER=1 git add docker-compose.yml
GIT_MASTER=1 git commit -m "add subs updater compose stack"
```

### Task 4: point router config at local HTTP

**Files:**
- Modify: `mihomo/config.yaml` (proxy-providers `stable` url + comment)

**Interfaces:**
- Consumes: `http://192.168.1.2:7009/stable.txt` from Task 3.
- Produces: validated config; router deploy stays a separate explicit action.

- [ ] **Step 1: change the provider URL**

In `mihomo/config.yaml` provider `stable`: replace the converter URL with `http://192.168.1.2:7009/stable.txt` and update the comment to say the list is served by the local subs-updater compose stack (raw URI list, parsed natively; converter dropped — exclude_groups was a no-op after relabeling).

- [ ] **Step 2: validate**

Run: `nix-shell --run 'mihomo-yaml-check && mihomo-validate'`
Expected: "test is successful"; only the pre-existing Classical-rule-provider warnings.

- [ ] **Step 3: commit**

```bash
GIT_MASTER=1 git add mihomo/config.yaml
GIT_MASTER=1 git commit -m "fetch stable list from local updater"
```
