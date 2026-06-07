#!/usr/bin/env bash
set -e

ARCH="linux-arm64" # arm64 = aarch64 (ARMv8, cortex-a53)
REPO="MetaCubeX/mihomo"
TMPDIR="${TMPDIR:-/tmp}"
UPX_PROVIDER="${UPX_PROVIDER:-nix run nixpkgs#upx --}" # empty = skip UPX

die() {
  echo "ERROR: $1" >&2
  exit 1
}
for dep in curl jq gunzip; do
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
URL=$(curl -sL "$ASSETS_API" | jq -r --arg a "$ARCH" '
    .assets[]
    | select(.name | test("^mihomo-\($a)-.*\\.gz$"))
    | select(.name | test("-go\\d") | not)
    | .browser_download_url
' | head -1)

if [ -z "$URL" ]; then
  die "no $ARCH .gz asset found for $TAG"
fi

FILE="mihomo-${ARCH}-${TAG}.gz"
cd "$TMPDIR"
curl -fsSL --progress-bar -o "$FILE" "$URL"

gunzip -f "$FILE"
BIN="${FILE%.gz}"

if [ -n "$UPX_PROVIDER" ]; then
  chmod +x "$BIN"
  $UPX_PROVIDER --lzma "$BIN" > /dev/null 2>&1
fi

echo "${TMPDIR}/${BIN}"
