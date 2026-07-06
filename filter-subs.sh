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
  # some subscription servers 403 the default curl UA
  payload="$(curl -fsSL -A "mihomo" --max-time 30 "$url")" || return 1
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
  if [ -z "${raw//[[:space:]]/}" ]; then
    continue
  fi
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
