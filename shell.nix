{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShellNoCC {
  packages = with pkgs; [
    mihomo
    yq-go
    openssh
    curl
    jq
    gzip
    upx
  ];

  shellHook = ''
    mihomo_config_default="mihomo/config.yaml"
    mihomo_home_default="''${MIHOMO_HOME:-/tmp/mihomo}"

    mihomo-yaml-check() {
      local config="''${1:-$mihomo_config_default}"
      yq '.' "$config" >/dev/null
    }

    mihomo-validate() {
      local config="''${1:-$mihomo_config_default}"
      local home_dir="''${2:-$mihomo_home_default}"
      mihomo -t -d "$home_dir" -f "$config"
    }

    mihomo-deploy-config() {
      local target="''${1:-router:/etc/mihomo/config.yaml}"
      mihomo-yaml-check "$mihomo_config_default" && \
        mihomo-validate "$mihomo_config_default" && \
        scp "$mihomo_config_default" "$target"
    }

    mihomo-fetch-router() {
      local arch="''${1:-''${MIHOMO_ROUTER_ARCH:-linux-arm64}}"
      local tmpdir="''${2:-''${TMPDIR:-/tmp}}"
      local bin

      mkdir -p "$tmpdir"
      bin="$(MIHOMO_ARCH="$arch" TMPDIR="$tmpdir" UPX_PROVIDER="upx --best" bash ./fetch-mihomo.sh)"
      chmod +x "$bin"

      echo "Router binary: $bin" >&2
      echo "Deploy: scp \"$bin\" router:/tmp/mihomo.bin && ssh router 'cp /tmp/mihomo.bin /usr/bin/mihomo && chmod 755 /usr/bin/mihomo'" >&2
      printf '%s\n' "$bin"
    }

    mihomo-filter-subs() {
      bash ./filter-subs.sh "$@"
    }

    echo "mihomo dev shell"
    echo "  mihomo-yaml-check [config]"
    echo "  mihomo-validate [config] [home-dir]"
    echo "  mihomo-deploy-config [router:/etc/mihomo/config.yaml]"
    echo "  mihomo-fetch-router [linux-arm64] [tmpdir]"
    echo "  mihomo-filter-subs   (env: ROUNDS MAX_FAIL MAX_AVG_MS ... see filter-subs.sh)"
  '';
}
