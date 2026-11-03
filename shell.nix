{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShellNoCC {
  packages = with pkgs; [
    yq-go
    openssh
    curl
    jq
    gzip
    upx
    xz
  ];

  shellHook = ''
    murmur_config_default="murmur/config.yaml"
    murmur_home_default="''${MURMUR_HOME:-/tmp/murmur-work}"

    murmur-yaml-check() {
      local config="''${1:-$murmur_config_default}"
      yq '.' "$config" >/dev/null
    }

    murmur-validate() {
      local config="''${1:-$murmur_config_default}"
      local home_dir="''${2:-$murmur_home_default}"
      mkdir -p "$home_dir/rules" "$home_dir/providers"
      # murmur checks its own config: -t validates, -d is the workdir.
      murmur -t -d "$home_dir" -f "$config"
    }

    murmur-deploy-config() {
      local target="''${1:-router:/etc/murmur/config.yaml}"
      murmur-yaml-check "$murmur_config_default" && \
        scp "$murmur_config_default" "$target"
    }

    # Downloads the release binary and packs it for the router's flash.
    # The router's overlay has about 12 MB free, so the binary must travel
    # compressed; xz -6 is the highest level that fits in the router's RAM.
    murmur-fetch-router() {
      local arch="''${1:-''${MURMUR_ROUTER_ARCH:-linux-arm64}}"
      local tmpdir="''${2:-''${TMPDIR:-/tmp}}"

      mkdir -p "$tmpdir"
      bash ./fetch-murmur.sh "$arch" "$tmpdir" --pack
    }

    # Syncs the repository files to the router and restarts the proxy.
    murmur-deploy() {
      local host="''${1:-router}"
      scp murmur/init.d "$host":/etc/init.d/murmur
      scp murmur/config "$host":/etc/config/murmur
      scp murmur/config.yaml "$host":/etc/murmur/config.yaml
      scp pbr "$host":/etc/init.d/pbr
      scp proxy-ctl.sh "$host":/root/proxy-ctl.sh
      ssh "$host" 'chmod +x /etc/init.d/murmur /etc/init.d/pbr /root/proxy-ctl.sh'
    }

    echo "murmur dev shell"
    echo "  murmur-yaml-check [config]"
    echo "  murmur-validate [config] [home-dir]"
    echo "  murmur-deploy-config [router:/etc/murmur/config.yaml]"
    echo "  murmur-fetch-router [linux-arm64] [tmpdir]"
    echo "  murmur-deploy [router]"
  '';
}
