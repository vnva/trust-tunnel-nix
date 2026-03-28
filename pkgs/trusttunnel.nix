{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "1.0.17";

  srcs = {
    x86_64-linux = fetchurl {
      url = "https://github.com/TrustTunnel/TrustTunnel/releases/download/v${version}/trusttunnel-v${version}-linux-x86_64.tar.gz";
      hash = "sha256-c7/BJ9htf1/vNYloaH4i7cDC/0QN2/qofdzPd+qtuSc=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/TrustTunnel/TrustTunnel/releases/download/v${version}/trusttunnel-v${version}-linux-aarch64.tar.gz";
      hash = "sha256-o5opgNqda7mkB7fGOZuLrQV5bbEZRgXN5Is7CpPZEXU=";
    };
  };
in
stdenv.mkDerivation {
  pname = "trusttunnel";
  inherit version;

  src =
    srcs.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
  ];

  dontConfigure = true;
  dontBuild = true;

  # TrustTunnel releases have files in a subdirectory named trusttunnel-v<version>-linux-<arch>
  # Use find to locate binaries regardless of the exact directory structure
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # Find and install endpoint binary
    ENDPOINT=$(find . -name "trusttunnel_endpoint" -type f | head -1)
    if [ -n "$ENDPOINT" ]; then
      install -m755 "$ENDPOINT" $out/bin/
    else
      echo "Error: trusttunnel_endpoint binary not found"
      exit 1
    fi

    # Client binary may not exist in all releases (optional)
    CLIENT=$(find . -name "trusttunnel_client" -type f | head -1)
    if [ -n "$CLIENT" ]; then
      install -m755 "$CLIENT" $out/bin/
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Stealth VPN that tunnels over HTTPS";
    homepage = "https://github.com/TrustTunnel/TrustTunnel";
    license = licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "trusttunnel_endpoint";
  };
}
