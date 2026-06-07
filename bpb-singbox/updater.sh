#!/bin/sh
# Fetches BPB sing-box config, pathes it for mixed SOCKS5, writes to shared volume

SUB_URL="${SUB_URL:?SUB_URL not set}"
CONF="/etc/sing-box/config.json"
CONF_TMP="${CONF}.tmp"

fetch_and_patch() {
  echo "[$(date)] Fetching BPB..."
  wget -q -O "${CONF_TMP}.raw" "$SUB_URL" || { echo "Failed to fetch"; return 1; }

  python3 -c "
import json
with open('${CONF_TMP}.raw') as f:
    bpbsb = json.load(f)
obs = [o for o in bpbsb.get('outbounds',[]) if o.get('type') == 'vless']
if not obs:
    raise SystemExit('No VLESS outbounds found')
config = {
    'log': {'level': 'warn'},
    'inbounds': [{'type': 'mixed', 'tag': 'mixed-in', 'listen': '0.0.0.0', 'listen_port': 10808}],
    'outbounds': obs + [{'type': 'direct', 'tag': 'direct'}, {'type': 'block', 'tag': 'block'}],
    'route': {'rules': [{'inbound': ['mixed-in'], 'outbound': obs[0]['tag']}], 'auto_detect_interface': True}
}
with open('${CONF_TMP}', 'w') as f:
    json.dump(config, f, indent=2)
print(f'Updated: {len(obs)} VLESS outbounds')
" && mv "$CONF_TMP" "$CONF" && echo "[$(date)] Config updated" && curl -s --unix-socket /var/run/docker.sock -X POST http://localhost/containers/bpb-singbox/restart > /dev/null && return 0
  return 1
}

# Initial fetch
fetch_and_patch

# Loop every hour
while true; do
  sleep 3600
  fetch_and_patch
done
