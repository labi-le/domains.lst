# Subscription Filter Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `filter-subs.sh`, which tests every node of the GitHub-hosted proxy subscriptions through a disposable Dockerized Mihomo and publishes only stable, fast nodes to `subs/stable.txt`, then switch the router config to that single filtered provider.

**Architecture:** Sources listed in `subs/sources.txt` are fetched, merged, deduplicated by endpoint, and relabeled to unique `<source>-<NNN>` names. The merged URI list is mounted into a `metacubex/mihomo` container as a `type: file` proxy-provider; the script runs N delay rounds via `GET /group/TEST/delay`, aggregates results with `jq`, and writes survivors (sorted by mean delay) back into the repo. The router keeps consuming the result through the existing converter at `192.168.1.2:7008`.

**Tech Stack:** bash, curl, jq, awk, Docker (`metacubex/mihomo:latest`), Mihomo REST API, nix-shell helpers.

Spec: `docs/superpowers/specs/2026-07-06-filter-subs-design.md`

## Global Constraints

- Bash scripts follow `fetch-mihomo.sh` style: `#!/usr/bin/env bash`, strict mode, `die()`/`warn()` to stderr, env-tunable defaults.
- Never use `/tmp/mihomo` as a temp/staging path — it is the Mihomo runtime directory (AGENTS.md rule).
- Tunable defaults (exact values): `ROUNDS=5`, `TIMEOUT_MS=2000`, `MAX_FAIL=0`, `MAX_AVG_MS=1000`, `ROUND_PAUSE=3`, `TEST_URL=https://www.gstatic.com/generate_204`, `CONTROLLER=127.0.0.1:19090`, `MIHOMO_IMAGE=metacubex/mihomo:latest`, `SOURCES_FILE=subs/sources.txt`, `OUTPUT_FILE=subs/stable.txt`, `DRY_RUN=0`.
- Commit style: short lowercase imperative subject (matches `git log`), body footer `Ultraworked with [Sisyphus](https://github.com/code-yeongyu/oh-my-openagent)`, every git command prefixed `GIT_MASTER=1`.
- Verification commands: `nix-shell -p shellcheck --run 'shellcheck filter-subs.sh'`, `nix-instantiate --parse shell.nix`, `nix-shell --run 'mihomo-yaml-check && mihomo-validate'`.
- No router deploy in this plan. Pushing to `origin/main` requires explicit user confirmation.

---

### Task 1: `subs/sources.txt`

**Files:**
- Create: `subs/sources.txt`

**Interfaces:**
- Produces: `subs/sources.txt` in the format `name url` (one per line, `#` comments, blank lines allowed); `name` matches `[a-z0-9-]+`. Task 2's script reads this path by default.

- [ ] **Step 1: Write the file**

```
# proxy subscription sources: <name> <url>
# name: [a-z0-9-]+, becomes the node label prefix in subs/stable.txt
mifa https://mifa.world/vless
aetris https://raw.githubusercontent.com/flaafix/AetrisVPN-black-list/refs/heads/main/configs.txt
purple https://raw.githubusercontent.com/Animeblin1/sukasubs/refs/heads/main/purple.txt
```

- [ ] **Step 2: Commit**

```bash
GIT_MASTER=1 git add subs/sources.txt
GIT_MASTER=1 git commit -m "add subscription sources list" -m "Ultraworked with [Sisyphus](https://github.com/code-yeongyu/oh-my-openagent)"
```

---

### Task 2: `filter-subs.sh`

**Files:**
- Create: `filter-subs.sh` (repo root, mode 755)
- Test fixture (temporary, not committed): `/tmp/filter-subs-test/`

**Interfaces:**
- Consumes: `subs/sources.txt` from Task 1.
- Produces: executable `filter-subs.sh`; env contract per Global Constraints; `DRY_RUN=1` prints `label\tlink` TSV to stdout and exits before Docker; full run writes `subs/stable.txt` (one share link per line, sorted by mean delay ascending) and prints a report table to stderr.

- [ ] **Step 1: Write the failing test (fixture + assertions)**

Create `/tmp/filter-subs-test/check.sh`:

```bash
#!/usr/bin/env bash
# offline dry-run test for filter-subs.sh label/merge/dedupe logic
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

FIX=/tmp/filter-subs-test
mkdir -p "$FIX"

VMESS_JSON='{"add":"10.9.9.9","port":"443","ps":"old name","id":"abc","v":"2"}'
VMESS_B64="$(printf '%s' "$VMESS_JSON" | base64 -w0)"

cat > "$FIX/src.txt" <<EOF
vless://uuid-1@10.0.0.1:443?security=tls#Original%20Name
vless://uuid-2@10.0.0.1:443?security=tls#Duplicate%20Endpoint
trojan://pw@example.com:8443#Some
ss://YWVzLTEyOC1nY206dGVzdA@192.168.100.1:8888#legacy
vmess://$VMESS_B64
not a link line
EOF

cat > "$FIX/sources.txt" <<EOF
# comment line
demo file://$FIX/src.txt
EOF

out="$(DRY_RUN=1 SOURCES_FILE="$FIX/sources.txt" bash ./filter-subs.sh)"

[ "$(printf '%s\n' "$out" | wc -l)" -eq 4 ] || { echo "FAIL: expected 4 unique nodes, got:"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -qF 'demo-001	vless://uuid-1@10.0.0.1:443?security=tls#demo-001' || { echo "FAIL: vless relabel"; exit 1; }
[ "$(printf '%s\n' "$out" | grep -c '10.0.0.1:443')" -eq 1 ] || { echo "FAIL: duplicate endpoint not deduped"; exit 1; }
if printf '%s\n' "$out" | grep -q 'demo-002'; then echo "FAIL: duplicate got its own label instead of being dropped"; exit 1; fi
printf '%s\n' "$out" | grep -qF 'demo-003	trojan://pw@example.com:8443#demo-003' || { echo "FAIL: trojan relabel"; exit 1; }
printf '%s\n' "$out" | grep -qF 'demo-004	ss://YWVzLTEyOC1nY206dGVzdA@192.168.100.1:8888#demo-004' || { echo "FAIL: ss relabel"; exit 1; }
printf '%s\n' "$out" | awk -F'\t' '$1=="demo-005"{print $2}' | sed 's#^vmess://##' | base64 -d | jq -e '.ps == "demo-005"' >/dev/null || { echo "FAIL: vmess ps rewrite"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/filter-subs-test/check.sh`
Expected: FAIL — `filter-subs.sh: No such file or directory` (script does not exist yet).

- [ ] **Step 3: Write `filter-subs.sh`**

```bash
#!/usr/bin/env bash
# filter-subs.sh - keep only stable, fast nodes from proxy subscriptions.
#
# Reads sources from subs/sources.txt (name url per line), merges and
# relabels all share links to <source>-<NNN>, tests every node through a
# disposable Mihomo container via GET /group/TEST/delay, and writes the
# survivors to subs/stable.txt sorted by mean delay.
#
# Tunables (env): ROUNDS TIMEOUT_MS MAX_FAIL MAX_AVG_MS ROUND_PAUSE TEST_URL
#                 CONTROLLER MIHOMO_IMAGE SOURCES_FILE OUTPUT_FILE DRY_RUN
set -euo pipefail

ROUNDS="${ROUNDS:-5}"
TIMEOUT_MS="${TIMEOUT_MS:-2000}"
MAX_FAIL="${MAX_FAIL:-0}"
MAX_AVG_MS="${MAX_AVG_MS:-1000}"
ROUND_PAUSE="${ROUND_PAUSE:-3}"
TEST_URL="${TEST_URL:-https://www.gstatic.com/generate_204}"
CONTROLLER="${CONTROLLER:-127.0.0.1:19090}"
MIHOMO_IMAGE="${MIHOMO_IMAGE:-metacubex/mihomo:latest}"
SOURCES_FILE="${SOURCES_FILE:-subs/sources.txt}"
OUTPUT_FILE="${OUTPUT_FILE:-subs/stable.txt}"
DRY_RUN="${DRY_RUN:-0}"

API="http://$CONTROLLER"
CONTAINER="mihomo-subtest-$$"
WORKDIR="$(mktemp -d)"

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warn: $*" >&2; }

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

for dep in curl jq awk base64 grep; do
  command -v "$dep" >/dev/null 2>&1 || die "$dep not found, please install"
done
if [ "$DRY_RUN" != "1" ]; then
  command -v docker >/dev/null 2>&1 || die "docker not found, please install"
  docker info >/dev/null 2>&1 || die "docker daemon unavailable"
fi
[ -f "$SOURCES_FILE" ] || die "sources file not found: $SOURCES_FILE"

# --- fetch + merge + relabel -------------------------------------------------

MERGED="$WORKDIR/provider.txt"
INDEX="$WORKDIR/index.tsv" # <label>\t<relabeled link>
: > "$MERGED"
: > "$INDEX"

declare -A SEEN # host:port dedupe

b64_decode() { # stdin -> stdout; tolerates whitespace, url-safe alphabet, missing padding
  local s
  s="$(tr -d ' \t\r\n' | tr '_-' '/+')"
  while [ $((${#s} % 4)) -ne 0 ]; do s="${s}="; done
  printf '%s' "$s" | base64 -d 2>/dev/null
}

fetch_source() { # $1=url -> share links on stdout
  local url="$1" payload decoded
  payload="$(curl -fsSL --max-time 30 "$url")" || return 1
  if ! grep -aq '://' <<< "$payload"; then
    decoded="$(printf '%s' "$payload" | b64_decode || true)"
    if grep -aq '://' <<< "${decoded:-}"; then
      payload="$decoded"
    fi
  fi
  printf '%s\n' "$payload"
}

total_in=0
sources_ok=0

process_source() { # $1=name $2=url
  local name="$1" url="$2" links line label json hostport base newline n=0
  links="$(fetch_source "$url")" || { warn "source $name unreachable, skipping"; return 0; }
  sources_ok=$((sources_ok + 1))
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      vless://* | vmess://* | trojan://* | ss://* | ssr://* | hysteria://* | hysteria2://* | hy2://* | tuic://*) ;;
      *) continue ;;
    esac
    total_in=$((total_in + 1))
    n=$((n + 1))
    label="$(printf '%s-%03d' "$name" "$n")"
    case "$line" in
      vmess://*)
        json="$(printf '%s' "${line#vmess://}" | b64_decode)" || { warn "$label: bad vmess base64, dropped"; continue; }
        hostport="$(jq -r '"\(.add):\(.port)"' <<< "$json" 2>/dev/null)" || { warn "$label: bad vmess json, dropped"; continue; }
        newline="vmess://$(jq -c --arg ps "$label" '.ps = $ps' <<< "$json" | base64 -w0)"
        ;;
      *://*@*)
        base="${line%%#*}"
        hostport="${base##*@}"
        hostport="${hostport%%\?*}"
        hostport="${hostport%%/*}"
        newline="${base}#${label}"
        ;;
      *)
        base="${line%%#*}"
        hostport="$base"
        newline="${base}#${label}"
        ;;
    esac
    if [ -n "${SEEN[$hostport]:-}" ]; then
      continue
    fi
    SEEN[$hostport]=1
    printf '%s\n' "$newline" >> "$MERGED"
    printf '%s\t%s\n' "$label" "$newline" >> "$INDEX"
  done <<< "$links"
}

while IFS= read -r raw; do
  raw="${raw%%#*}"
  [ -z "${raw//[[:space:]]/}" ] && continue
  src_name="$(awk '{print $1}' <<< "$raw")"
  src_url="$(awk '{print $2}' <<< "$raw")"
  [[ "$src_name" =~ ^[a-z0-9-]+$ ]] || die "bad source name in $SOURCES_FILE: $src_name"
  [ -n "$src_url" ] || die "missing url for source: $src_name"
  process_source "$src_name" "$src_url"
done < "$SOURCES_FILE"

[ "$sources_ok" -gt 0 ] || die "all sources unreachable"
node_count="$(wc -l < "$INDEX")"
[ "$node_count" -gt 0 ] || die "no share links found in any source"
echo "merged: $total_in links from $sources_ok source(s), $node_count unique nodes" >&2

if [ "$DRY_RUN" = "1" ]; then
  cat "$INDEX"
  exit 0
fi

# --- disposable mihomo -------------------------------------------------------

cat > "$WORKDIR/config.yaml" <<EOF
log-level: warning
mode: rule
external-controller: $CONTROLLER
proxy-providers:
  merged:
    type: file
    path: ./provider.txt
    health-check:
      enable: false
      url: $TEST_URL
      interval: 3600
proxy-groups:
  - name: TEST
    type: select
    include-all: true
rules:
  - MATCH,DIRECT
EOF

docker run --rm -d --name "$CONTAINER" --network host \
  -v "$WORKDIR:/root/.config/mihomo" "$MIHOMO_IMAGE" >/dev/null

ready=0
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 "$API/version" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" != "1" ]; then
  docker logs "$CONTAINER" >&2 || true
  die "mihomo API not ready on $CONTROLLER"
fi

loaded="$(curl -fsS "$API/providers/proxies/merged" | jq '.proxies | length')"
[ "$loaded" -gt 0 ] || die "provider loaded 0 proxies (parse failure?)"
echo "mihomo loaded $loaded nodes; testing: $ROUNDS rounds x ${TIMEOUT_MS}ms timeout" >&2

# --- delay rounds ------------------------------------------------------------

url_enc="$(jq -rn --arg v "$TEST_URL" '$v|@uri')"

for r in $(seq 1 "$ROUNDS"); do
  echo "round $r/$ROUNDS..." >&2
  curl -fsS --max-time $((TIMEOUT_MS / 1000 + 60)) \
    "$API/group/TEST/delay?url=${url_enc}&timeout=${TIMEOUT_MS}&expected=204" \
    > "$WORKDIR/round$r.json" || echo '{}' > "$WORKDIR/round$r.json"
  if [ "$r" -lt "$ROUNDS" ]; then
    sleep "$ROUND_PAUSE"
  fi
done

# --- aggregate + filter ------------------------------------------------------

jq -s '
  map(to_entries | map(select(.value > 0))) | add
  | group_by(.key)
  | map({name: .[0].key, succ: length, mean: (map(.value) | add / length)})
' "$WORKDIR"/round*.json > "$WORKDIR/agg.json"

jq -r '.[] | [.name, (.mean | floor), .succ] | @tsv' "$WORKDIR/agg.json" > "$WORKDIR/agg.tsv"

SURVIVORS="$WORKDIR/survivors.tsv"
jq -r --argjson rounds "$ROUNDS" --argjson maxfail "$MAX_FAIL" --argjson maxavg "$MAX_AVG_MS" '
  map(select((($rounds - .succ) <= $maxfail) and (.mean <= $maxavg)))
  | sort_by(.mean)
  | .[] | [.name, (.mean | floor), .succ] | @tsv
' "$WORKDIR/agg.json" > "$SURVIVORS"

# --- report ------------------------------------------------------------------

echo >&2
awk -F'\t' -v rounds="$ROUNDS" -v aggf="$WORKDIR/agg.tsv" -v survf="$SURVIVORS" '
  BEGIN { printf "%-16s %9s %6s %8s\n", "NODE", "MEAN_MS", "FAILS", "VERDICT" }
  FILENAME == aggf  { mean[$1] = $2; fails[$1] = rounds - $3; next }
  FILENAME == survf { keep[$1] = 1; next }
  {
    m = ($1 in mean) ? mean[$1] : "-"
    f = ($1 in fails) ? fails[$1] : rounds
    v = ($1 in keep) ? "keep" : "drop"
    printf "%-16s %9s %6s %8s\n", $1, m, f, v
  }
' "$WORKDIR/agg.tsv" "$SURVIVORS" "$INDEX" >&2
echo >&2

# --- emit --------------------------------------------------------------------

surv_count="$(wc -l < "$SURVIVORS")"
[ "$surv_count" -gt 0 ] || die "no nodes survived filtering ($node_count tested); $OUTPUT_FILE left untouched"

awk -F'\t' -v survf="$SURVIVORS" '
  FILENAME == survf { order[++cnt] = $1; next }
  { link[$1] = $2 }
  END { for (i = 1; i <= cnt; i++) if (order[i] in link) print link[order[i]] }
' "$SURVIVORS" "$INDEX" > "$WORKDIR/stable.txt"

mkdir -p "$(dirname "$OUTPUT_FILE")"
mv "$WORKDIR/stable.txt" "$OUTPUT_FILE"
echo "wrote $surv_count/$node_count nodes to $OUTPUT_FILE" >&2
```

Then: `chmod 755 filter-subs.sh`

- [ ] **Step 4: Run the fixture test to verify it passes**

Run: `bash /tmp/filter-subs-test/check.sh`
Expected: `PASS` (stderr shows `merged: 5 links from 1 source(s), 4 unique nodes`)

- [ ] **Step 5: ShellCheck**

Run: `nix-shell -p shellcheck --run 'shellcheck filter-subs.sh'`
Expected: no output, exit 0. Fix any findings without weakening quoting/strict mode.

- [ ] **Step 6: Real dry-run against live sources**

Run: `DRY_RUN=1 bash filter-subs.sh | head -20` (workstation network required)
Expected: stderr `merged: N links from 3 source(s), M unique nodes` with M > 0; stdout lines like `aetris-001<TAB>vless://...#aetris-001`. If a source is down, a `warn:` line appears and the rest proceed.

- [ ] **Step 7: Commit**

```bash
GIT_MASTER=1 git add filter-subs.sh
GIT_MASTER=1 git commit -m "add subscription filter script" -m "Ultraworked with [Sisyphus](https://github.com/code-yeongyu/oh-my-openagent)"
```

---

### Task 3: `shell.nix` helper

**Files:**
- Modify: `shell.nix` (shellHook: add function + menu line)

**Interfaces:**
- Consumes: `filter-subs.sh` from Task 2.
- Produces: `mihomo-filter-subs` shell function available inside `nix-shell`, forwarding env tunables untouched.

- [ ] **Step 1: Add helper to shellHook**

Insert after the `mihomo-fetch-router()` function definition, before the `echo "mihomo dev shell"` block:

```nix
    mihomo-filter-subs() {
      bash ./filter-subs.sh "$@"
    }
```

And add a menu line after `echo "  mihomo-fetch-router [linux-arm64] [tmpdir]"`:

```nix
    echo "  mihomo-filter-subs   (env: ROUNDS MAX_FAIL MAX_AVG_MS ... see filter-subs.sh)"
```

- [ ] **Step 2: Validate nix syntax**

Run: `nix-instantiate --parse shell.nix >/dev/null`
Expected: exit 0, no error output.

- [ ] **Step 3: Verify helper exists in the shell**

Run: `nix-shell --run 'type mihomo-filter-subs'`
Expected: output states `mihomo-filter-subs is a function`.

- [ ] **Step 4: Commit**

```bash
GIT_MASTER=1 git add shell.nix
GIT_MASTER=1 git commit -m "add mihomo-filter-subs helper" -m "Ultraworked with [Sisyphus](https://github.com/code-yeongyu/oh-my-openagent)"
```

---

### Task 4: Real end-to-end run (QA) producing `subs/stable.txt`

**Files:**
- Create (generated): `subs/stable.txt`

**Interfaces:**
- Consumes: `filter-subs.sh`, `subs/sources.txt`, Docker daemon, live network.
- Produces: committed `subs/stable.txt` — one share link per line, labels `<source>-<NNN>`, sorted by mean delay ascending. Task 5's provider URL serves exactly this file.

- [ ] **Step 1: Full run**

Run: `nix-shell --run 'mihomo-filter-subs'`
Expected: first run may pull the Docker image (delay is normal); then `mihomo loaded L nodes`, 5 round lines, a report table with keep/drop verdicts, and `wrote S/M nodes to subs/stable.txt` with S > 0.
If S is 0 (all nodes bad or thresholds too strict): re-run once with `MAX_AVG_MS=2000 nix-shell --run 'mihomo-filter-subs'` and note the relaxation in the commit body.

- [ ] **Step 2: Sanity-check the output**

Run: `wc -l subs/stable.txt && head -5 subs/stable.txt`
Expected: S lines; every line starts with a known scheme and ends with `#<source>-<NNN>` (vmess lines excepted — label lives in the base64 `ps` field).

- [ ] **Step 3: Verify Mihomo accepts the output as a provider payload**

Run:
```bash
tmp="$(mktemp -d /tmp/filter-subs-verify.XXXXXX)"
cp subs/stable.txt "$tmp/provider.txt"
cat > "$tmp/config.yaml" <<'EOF'
log-level: warning
mode: rule
proxy-providers:
  merged:
    type: file
    path: ./provider.txt
    health-check:
      enable: false
      url: https://www.gstatic.com/generate_204
      interval: 3600
proxy-groups:
  - name: TEST
    type: select
    include-all: true
rules:
  - MATCH,DIRECT
EOF
nix-shell --run "mihomo -t -d $tmp -f $tmp/config.yaml" && rm -rf "$tmp"
```
Expected: `configuration file ... test is successful`.

- [ ] **Step 4: Commit**

```bash
GIT_MASTER=1 git add subs/stable.txt
GIT_MASTER=1 git commit -m "add filtered stable subscription" -m "Ultraworked with [Sisyphus](https://github.com/code-yeongyu/oh-my-openagent)"
```

---

### Task 5: Switch `mihomo/config.yaml` to the single `stable` provider

**Files:**
- Modify: `mihomo/config.yaml:44-100` (proxy-providers block and `VPN-ALL-AUTO.use`)

**Interfaces:**
- Consumes: `subs/stable.txt` published at `https://raw.githubusercontent.com/labi-le/domains.lst/main/subs/stable.txt` (requires push — see Step 3 note).
- Produces: router config with one provider `stable`; `VPN-ALL-AUTO` unchanged in behavior, sourced from the filtered list.

**Pre-condition:** `subs/stable.txt` must be pushed to `origin/main` before Step 2 — `mihomo -t` may fetch the http provider when no cached payload exists, and the converter URL 404s until the raw file is live. Ask the user to confirm the push first.

- [ ] **Step 1: Replace the three providers with one**

Replace the entire `proxy-providers:` block (`mifa`, `aetris`, `purple` entries) with:

```yaml
proxy-providers:
  stable:
    type: http
    url: "http://192.168.1.2:7008/?subscription_url=https://raw.githubusercontent.com/labi-le/domains.lst/main/subs/stable.txt&exclude_groups=geo_blocked"
    path: ./providers/stable.yaml
    interval: 3600
    health-check:
      enable: true
      url: "https://gstatic.com/generate_204"
      interval: 120
      timeout: 2000
      lazy: false
      expected-status: 204
```

And change `VPN-ALL-AUTO`:

```yaml
  - name: VPN-ALL-AUTO
    type: url-test
    use:
      - stable
```

(keep the group's existing url/interval/timeout/tolerance/lazy/expected-status/max-failed-times lines unchanged).

Note: after relabeling, converter group tags are gone, so `exclude_groups=geo_blocked` becomes a no-op kept only for URL-shape consistency; the delay filter replaces its function.

- [ ] **Step 2: Validate**

Run: `nix-shell --run 'mihomo-yaml-check && mihomo-validate'`
Expected: `test is successful`. Report any warnings verbatim.

- [ ] **Step 3: Commit**

```bash
GIT_MASTER=1 git add mihomo/config.yaml
GIT_MASTER=1 git commit -m "switch providers to filtered stable list" -m "Ultraworked with [Sisyphus](https://github.com/code-yeongyu/oh-my-openagent)"
```

Note: the new provider URL only resolves after `main` is pushed. Ask the user before pushing; router deploy (`mihomo-deploy-config`) happens only on explicit request.
