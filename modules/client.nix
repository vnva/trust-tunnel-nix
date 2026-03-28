{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.trusttunnel.client;

  hasPassword = cfg.endpoint.password != null;
  hasPasswordFile = cfg.endpoint.passwordFile != null;

  needsPasswordSubstitution = hasPasswordFile;

  endpointConfig = filterAttrs (_: v: v != null) {
    hostname = cfg.endpoint.hostname;
    addresses = cfg.endpoint.addresses;
    has_ipv6 = cfg.endpoint.hasIpv6;
    username = cfg.endpoint.username;
    password = if hasPasswordFile then "PLACEHOLDER" else cfg.endpoint.password;
    upstream_protocol = cfg.endpoint.upstreamProtocol;
    skip_verification = cfg.endpoint.skipVerification;
    anti_dpi = cfg.endpoint.antiDpi;
    client_random = cfg.endpoint.clientRandom;
    certificate = cfg.endpoint.certificate;
  };

  listenerConfig = filterAttrs (_: v: v != { }) {
    tun =
      if cfg.listener.tun.enable then
        {
          included_routes = cfg.listener.tun.includedRoutes;
          excluded_routes = cfg.listener.tun.excludedRoutes;
          mtu_size = cfg.listener.tun.mtuSize;
          change_system_dns = cfg.listener.tun.changeSystemDns;
        }
      else
        { };
    socks =
      if cfg.listener.socks.enable then
        {
          address = cfg.listener.socks.address;
        }
      else
        { };
  };

  configTomlBase = (pkgs.formats.toml { }).generate "trusttunnel_client.toml" (
    filterAttrs (_: v: v != null && v != { }) {
      loglevel = cfg.loglevel;
      vpn_mode = cfg.vpnMode;
      killswitch_enabled = cfg.killswitchEnabled;
      killswitch_allow_ports = cfg.killswitchAllowPorts;
      post_quantum_group_enabled = cfg.postQuantumGroupEnabled;
      exclusions = cfg.exclusions;
      dns_upstreams = cfg.dnsUpstreams;
      endpoint = endpointConfig;
      listener = listenerConfig;
    }
  );

  passwordSubstitutionScript = pkgs.writeShellScript "trusttunnel-client-prep-with-password" ''
        set -e
        ${pkgs.coreutils}/bin/cp ${configTomlBase} /run/trusttunnel-client/trusttunnel_client.toml
        # Read password from file and substitute safely using Python
        # to avoid shell injection issues with special characters
        ${pkgs.python3}/bin/python3 -c "
    import re
    import sys
    with open('${cfg.endpoint.passwordFile}', 'r') as pf:
        password = pf.read().rstrip('\n')
    with open('/run/trusttunnel-client/trusttunnel_client.toml', 'r') as f:
        content = f.read()
    # Escape the password for TOML string
    escaped = password.replace('\\\\', '\\\\\\\\').replace('\"', '\\\\\"').replace('\n', '\\\\n')
    content = re.sub(r'^password = \"PLACEHOLDER\"$', f'password = \"{escaped}\"', content, flags=re.MULTILINE)
    with open('/run/trusttunnel-client/trusttunnel_client.toml', 'w') as f:
        f.write(content)
    "
        ${pkgs.coreutils}/bin/chmod 0600 /run/trusttunnel-client/trusttunnel_client.toml
  '';

  copyScript = pkgs.writeShellScript "trusttunnel-client-prep-simple" ''
    set -e
    ${pkgs.coreutils}/bin/cp ${configTomlBase} /run/trusttunnel-client/trusttunnel_client.toml
    ${pkgs.coreutils}/bin/chmod 0600 /run/trusttunnel-client/trusttunnel_client.toml
  '';

  prepScript = if needsPasswordSubstitution then passwordSubstitutionScript else copyScript;
in
{
  options.services.trusttunnel.client = {
    enable = mkEnableOption "TrustTunnel client";

    package = mkOption {
      type = types.package;
      default = pkgs.trusttunnel;
      defaultText = literalExpression "pkgs.trusttunnel";
      description = "TrustTunnel package to use";
    };

    user = mkOption {
      type = types.str;
      default = "trusttunnel-client";
      description = "User to run TrustTunnel client as";
    };

    group = mkOption {
      type = types.str;
      default = "trusttunnel-client";
      description = "Group to run TrustTunnel client as";
    };

    loglevel = mkOption {
      type = types.enum [
        "info"
        "debug"
        "trace"
      ];
      default = "info";
      description = "Log level";
    };

    vpnMode = mkOption {
      type = types.enum [
        "general"
        "selective"
      ];
      default = "general";
      description = "VPN mode";
    };

    killswitchEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable killswitch";
    };

    killswitchAllowPorts = mkOption {
      type = types.listOf types.int;
      default = [ ];
      description = "Ports to allow when killswitch is active";
    };

    postQuantumGroupEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable post-quantum groups";
    };

    exclusions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Exclusions for VPN routing";
    };

    dnsUpstreams = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "DNS upstream servers";
    };

    endpoint = {
      hostname = mkOption {
        type = types.str;
        description = "Endpoint hostname";
      };

      addresses = mkOption {
        type = types.listOf types.str;
        description = "Endpoint addresses";
      };

      hasIpv6 = mkOption {
        type = types.bool;
        default = true;
        description = "Whether endpoint has IPv6";
      };

      username = mkOption {
        type = types.str;
        description = "Username for authentication";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Password for authentication (inline - will be world-readable in /nix/store)";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing password";
      };

      upstreamProtocol = mkOption {
        type = types.enum [
          "http2"
          "http3"
        ];
        default = "http2";
        description = "Upstream protocol";
      };

      skipVerification = mkOption {
        type = types.bool;
        default = false;
        description = "Skip TLS certificate verification";
      };

      antiDpi = mkOption {
        type = types.bool;
        default = false;
        description = "Enable anti-DPI measures";
      };

      clientRandom = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Client random value";
      };

      certificate = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "PEM certificate (inline)";
      };
    };

    listener = {
      tun = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable TUN interface listener";
        };

        includedRoutes = mkOption {
          type = types.listOf types.str;
          default = [
            "0.0.0.0/0"
            "2000::/3"
          ];
          description = "Routes to include in VPN";
        };

        excludedRoutes = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Routes to exclude from VPN";
        };

        mtuSize = mkOption {
          type = types.int;
          default = 1280;
          description = "MTU size for TUN interface";
        };

        changeSystemDns = mkOption {
          type = types.bool;
          default = true;
          description = "Change system DNS settings";
        };
      };

      socks = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable SOCKS proxy listener";
        };

        address = mkOption {
          type = types.str;
          default = "127.0.0.1:1080";
          description = "SOCKS proxy address";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    warnings =
      optional (hasPassword && !hasPasswordFile)
        "services.trusttunnel.client.endpoint.password is set and will be stored world-readable in /nix/store. Consider using endpoint.passwordFile instead.";

    assertions = [
      {
        assertion = hasPassword != hasPasswordFile;
        message = "Exactly one of services.trusttunnel.client.endpoint.password or services.trusttunnel.client.endpoint.passwordFile must be set (neither can be null)";
      }
      {
        assertion = cfg.endpoint.addresses != [ ];
        message = "services.trusttunnel.client.endpoint.addresses must contain at least one address";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
    };

    users.groups.${cfg.group} = { };

    systemd.services.trusttunnel-client = {
      description = "TrustTunnel VPN Client";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        # The + prefix runs ExecStartPre as root, which is needed to write to
        # /run/trusttunnel-client/ before the service user can access it
        ExecStartPre = [ "+${prepScript}" ];
        ExecStart = "${lib.getExe' cfg.package "trusttunnel_client"} -c /run/trusttunnel-client/trusttunnel_client.toml";
        RuntimeDirectory = "trusttunnel-client";
        RuntimeDirectoryMode = "0700";
        User = cfg.user;
        Group = cfg.group;
        AmbientCapabilities = mkIf cfg.listener.tun.enable [ "CAP_NET_ADMIN" ];
        DeviceAllow = mkIf cfg.listener.tun.enable [ "/dev/net/tun rw" ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
