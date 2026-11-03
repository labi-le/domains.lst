#!/bin/sh
# Download the murmur release binary for the router.
#
# The release asset for aarch64 is the `router-vvt` build: no extra-protocols, which
# is what makes it fit in the 37 MB overlay. A build with extra-protocols does not fit.
#
# Usage:
#   fetch-murmur.sh <arch> <tmpdir>

set -eu

ARCH="${1:-linux-arm64}"
TMPDIR="${2:-${TMPDIR:-/tmp}}"

REPO="labile-le/murmur"

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

printf '%s\n' "$sha"
