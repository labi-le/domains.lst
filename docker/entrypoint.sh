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
