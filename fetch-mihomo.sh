#!/usr/bin/env bash
set -e

ARCH="${MIHOMO_ARCH:-${ARCH:-linux-arm64}}" # arm64 = aarch64 (ARMv8, cortex-a53)
REPO="MetaCubeX/mihomo"
TMPDIR="${TMPDIR:-/tmp}"
UPX_PROVIDER="${UPX_PROVIDER:-nix run nixpkgs#upx --}" # empty = skip UPX

die() {
  echo "ERROR: $1" >&2
  exit 1
}
for dep in curl jq gunzip sha256sum; do
  command -v "$dep" > /dev/null 2>&1 || die "$dep not found, please install"
done
if [ -n "$UPX_PROVIDER" ]; then
  _upx_cmd="${UPX_PROVIDER%% *}"
  command -v "$_upx_cmd" > /dev/null 2>&1 || die "$_upx_cmd not found (UPX_PROVIDER=$UPX_PROVIDER)"
fi

TAG=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name')
if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
  die "cannot resolve latest release tag"
fi

ASSETS_API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
ASSET=$(curl -sL "$ASSETS_API" | jq -r --arg a "$ARCH" '
    .assets[]
    | select(.name | test("^mihomo-\($a)-.*\\.gz$"))
    | select(.name | test("-go\\d") | not)
    | "\(.browser_download_url)\t\(.digest // "")"
' | head -1)

URL=${ASSET%%	*}
DIGEST=${ASSET#*	}

if [ -z "$URL" ]; then
  die "no $ARCH .gz asset found for $TAG"
fi

case "$DIGEST" in
  sha256:*) EXPECTED=${DIGEST#sha256:} ;;
  *)
    [ "${MIHOMO_SKIP_DIGEST:-0}" = "1" ] \
      || die "release $TAG carries no sha256 digest for $(basename "$URL"); set MIHOMO_SKIP_DIGEST=1 to install unverified"
    EXPECTED=""
    ;;
esac

FILE="mihomo-${ARCH}-${TAG}.gz"
cd "$TMPDIR"
curl -fsSL --progress-bar -o "$FILE" "$URL"

if [ -n "$EXPECTED" ]; then
  ACTUAL=$(sha256sum "$FILE" | cut -d' ' -f1)
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    rm -f "$FILE"
    echo "ERROR: sha256 mismatch for $FILE" >&2
    echo "  expected: $EXPECTED" >&2
    echo "  actual:   $ACTUAL" >&2
    exit 1
  fi
else
  echo "WARNING: installing $FILE unverified (MIHOMO_SKIP_DIGEST=1)" >&2
fi

gunzip -f "$FILE"
BIN="${FILE%.gz}"

if [ -n "$UPX_PROVIDER" ]; then
  chmod +x "$BIN"
  # a silent UPX failure ships a 46 MB binary at a router with a 37 MB overlay
  $UPX_PROVIDER --lzma "$BIN" > /dev/null || die "UPX failed on $BIN"
fi

echo "${TMPDIR}/${BIN}"
