#!/bin/sh
# Download the murmur binary for the router, compress it for flash, and verify it.
#
# The router's overlay has roughly 12 MB free, and the uncompressed murmur binary is
# 25 MB. The binary therefore cannot live in flash uncompressed: the init script
# keeps an xz-compressed copy on flash and unpacks it into tmpfs on every boot.
#
# Usage:
#   fetch-murmur.sh <arch> <tmpdir>       download and stage the binary
#   fetch-murmur.sh <arch> <tmpdir> --pack  also write the xz copy for the router
#
# The xz step must run where there is enough RAM: xz -9 needs about 300 MB and
# fails with "Out of memory" on a router with 256 MB, where xz -6 needs about 60 MB
# and produces a copy 4 MB larger.

set -eu

ARCH="${1:-linux-arm64}"
TMPDIR="${2:-${TMPDIR:-/tmp}}"
PACK=0
[ "${3:-}" = "--pack" ] && PACK=1

REPO="labile-le/murmur"
CACHE_HOST="192.168.1.2"
CACHE_URL="https://cache.labile.cc/serve/5sfjlphiywgmn76k76q1wzv87xdzaqdf/"

mkdir -p "$TMPDIR"

# The latest release tag.
tag=$(curl -sSLf "https://api.github.com/repos/${REPO}/releases/latest" \
	| jq -r '.tag_name') || {
	echo "could not read the latest release tag" >&2
	exit 1
}
echo "latest release: $tag" >&2

# The release asset name carries the target triple, e.g. murmur-linux-arm64.tar.gz.
asset=$(curl -sSLf "https://api.github.com/repos/${REPO}/releases/tags/${tag}" \
	| jq -r --arg arch "$ARCH" '.assets[] | select(.name | test("'"$ARCH"'")) | .browser_download_url' \
	| head -1) || {
	echo "no release asset for $ARCH" >&2
	exit 1
}
[ -n "$asset" ] || {
	echo "no release asset for $ARCH" >&2
	exit 1
}
echo "asset: $asset" >&2

curl -sSLf "$asset" -o "$TMPDIR/murmur.tar.gz"
tar -xzf "$TMPDIR/murmur.tar.gz" -C "$TMPDIR" || {
	echo "could not unpack the archive" >&2
	exit 1
}

# The archive holds the binary under an unknown name; find the ELF.
bin=$(find "$TMPDIR" -maxdepth 2 -type f -name 'murmur*' ! -name '*.tar.gz' \
	| while read -r f; do
		if head -c 4 "$f" | grep -q ELF; then echo "$f"; break; fi
	done)
[ -n "$bin" ] || {
	echo "no ELF binary in the archive" >&2
	exit 1
}
chmod +x "$bin"
mv "$bin" "$TMPDIR/murmur.bin"

sha=$(sha256sum "$TMPDIR/murmur.bin" | cut -d' ' -f1)
size=$(wc -c < "$TMPDIR/murmur.bin")
echo "binary: $TMPDIR/murmur.bin ($size bytes)" >&2
echo "sha256: $sha" >&2

if [ "$PACK" -eq 1 ]; then
	# xz -6 is the highest level that fits in the router's RAM.
	xz -6 -c "$TMPDIR/murmur.bin" > "$TMPDIR/murmur.bin.xz"
	echo "packed: $TMPDIR/murmur.bin.xz ($(wc -c < "$TMPDIR/murmur.bin.xz") bytes)" >&2
	echo >&2
	echo "Deploy:" >&2
	echo "  scp '$TMPDIR/murmur.bin.xz' router:/etc/proxy/murmur.bin.xz" >&2
	echo "  ssh router 'sed -i \"s/^SHA256=.*/SHA256=\\\"$sha\\\"/\" /etc/init.d/murmur'" >&2
	echo >&2
	echo "The cache host copy is at $CACHE_URL" >&2
fi

printf '%s\n' "$sha"
