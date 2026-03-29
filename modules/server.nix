{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.trusttunnel.server;

  vpnToml = (pkgs.formats.toml { }).generate "vpn.toml" (
    filterAttrs (_: v: v != null) {
      listen_address = cfg.listenAddress;
      ipv6_available = cfg.ipv6Available;
      allow_private_network_connections = cfg.allowPrivateNetworkConnections;
      tls_handshake_timeout_secs = cfg.tlsHandshakeTimeoutSecs;
      client_listener_timeout_secs = cfg.clientListenerTimeoutSecs;
      connection_establishment_timeout_secs = cfg.connectionEstablishmentTimeoutSecs;
      tcp_connections_timeout_secs = cfg.tcpConnectionsTimeoutSecs;
      udp_connections_timeout_secs = cfg.udpConnectionsTimeoutSecs;
      credentials_file = "/run/trusttunnel/credentials.toml";
      rules_file = cfg.rulesFile;
      speedtest_enable = cfg.speedtestEnable;
      ping_enable = cfg.pingEnable;
      auth_failure_status_code = cfg.authFailureStatusCode;
      # listen_protocols is required - at least one protocol must be enabled
      listen_protocols = {
        http1 = { };
        http2 = { };
        quic = { };
      };
    }
    // optionalAttrs (cfg.metrics.address != null) {
      metrics = {
        address = cfg.metrics.address;
      };
    }
  );

  hostsToml = (pkgs.formats.toml { }).generate "hosts.toml" {
    main_hosts = map (h: {
      hostname = h.hostname;
      cert_chain_path = h.certChainPath;
      private_key_path = h.privateKeyPath;
    }) cfg.hosts;
  };
in
{
  options.services.trusttunnel.server = {
    enable = mkEnableOption "TrustTunnel server";

    package = mkOption {
      type = types.package;
      default = pkgs.trusttunnel;
      defaultText = literalExpression "pkgs.trusttunnel";
      description = "TrustTunnel package to use";
    };

    user = mkOption {
      type = types.str;
      default = "trusttunnel";
      description = "User to run TrustTunnel server as";
    };

    group = mkOption {
      type = types.str;
      default = "trusttunnel";
      description = "Group to run TrustTunnel server as";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0:443";
      description = "Address to listen on";
    };

    ipv6Available = mkOption {
      type = types.bool;
      default = true;
      description = "Whether IPv6 is available";
    };

    allowPrivateNetworkConnections = mkOption {
      type = types.bool;
      default = false;
      description = "Allow connections to private networks";
    };

    tlsHandshakeTimeoutSecs = mkOption {
      type = types.int;
      default = 10;
      description = "TLS handshake timeout in seconds";
    };

    clientListenerTimeoutSecs = mkOption {
      type = types.int;
      default = 600;
      description = "Client listener timeout in seconds";
    };

    connectionEstablishmentTimeoutSecs = mkOption {
      type = types.int;
      default = 30;
      description = "Connection establishment timeout in seconds";
    };

    tcpConnectionsTimeoutSecs = mkOption {
      type = types.int;
      default = 604800;
      description = "TCP connections timeout in seconds";
    };

    udpConnectionsTimeoutSecs = mkOption {
      type = types.int;
      default = 300;
      description = "UDP connections timeout in seconds";
    };

    credentialsFile = mkOption {
      type = types.path;
      description = "Path to the credentials TOML file";
    };

    rulesFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional path to rules file";
    };

    speedtestEnable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable speedtest endpoint";
    };

    pingEnable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable ping endpoint";
    };

    authFailureStatusCode = mkOption {
      type = types.int;
      default = 407;
      description = "HTTP status code for authentication failures";
    };

    hosts = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            hostname = mkOption {
              type = types.str;
              description = "Hostname for this host";
            };
            certChainPath = mkOption {
              type = types.path;
              description = "Path to certificate chain file";
            };
            privateKeyPath = mkOption {
              type = types.path;
              description = "Path to private key file";
            };
          };
        }
      );
      default = [ ];
      description = "List of host configurations";
    };

    metrics = {
      address = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Metrics server address (null to disable)";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hosts != [ ];
        message = "services.trusttunnel.server.hosts must contain at least one host";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
    };

    users.groups.${cfg.group} = { };

    systemd.services.trusttunnel-server = {
      description = "TrustTunnel VPN Server";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        # The + prefix runs ExecStartPre as root, which is needed to copy the
        # credentials file into the runtime directory with correct ownership
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/install -m 0600 -o ${cfg.user} ${cfg.credentialsFile} /run/trusttunnel/credentials.toml"
        ];
        ExecStart = "${lib.getExe' cfg.package "trusttunnel_endpoint"} ${vpnToml} ${hostsToml}";
        RuntimeDirectory = "trusttunnel";
        RuntimeDirectoryMode = "0700";
        User = cfg.user;
        Group = cfg.group;
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
