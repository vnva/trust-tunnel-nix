# TrustTunnel Server — NixOS Module Usage

## Quick Start

Add the flake to your `flake.nix`:

```nix
inputs.trust-tunnel-nix.url = "github:youruser/trust-tunnel-nix";
```

Import the module and configure:

```nix
{ inputs, ... }:
{
  imports = [ inputs.trust-tunnel-nix.nixosModules.server ];

  services.trusttunnel.server = {
    enable = true;

    credentialsFile = "/run/secrets/trusttunnel-credentials.toml";

    hosts = [
      {
        hostname = "vpn.example.com";
        certChainPath = "/var/lib/acme/vpn.example.com/fullchain.pem";
        privateKeyPath = "/var/lib/acme/vpn.example.com/key.pem";
      }
    ];
  };
}
```

## Options Reference

### Top-level

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the TrustTunnel server service |
| `package` | package | `pkgs.trusttunnel` | Package to use |
| `user` | string | `"trusttunnel"` | System user to run the service as |
| `group` | string | `"trusttunnel"` | System group |
| `listenAddress` | string | `"0.0.0.0:443"` | Address and port to listen on |
| `ipv6Available` | bool | `true` | Advertise IPv6 support to clients |
| `allowPrivateNetworkConnections` | bool | `false` | Allow clients to reach private/RFC1918 networks |
| `credentialsFile` | path | — | **Required.** Path to credentials TOML file |
| `rulesFile` | path or null | `null` | Optional path to access rules file |
| `speedtestEnable` | bool | `false` | Enable built-in speedtest endpoint |
| `pingEnable` | bool | `false` | Enable ping diagnostic endpoint |
| `authFailureStatusCode` | int | `407` | HTTP status code returned on authentication failure |

### Timeout Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tlsHandshakeTimeoutSecs` | int | `10` | TLS handshake timeout (seconds) |
| `clientListenerTimeoutSecs` | int | `600` | Client idle timeout (seconds) |
| `connectionEstablishmentTimeoutSecs` | int | `30` | Connection setup timeout (seconds) |
| `tcpConnectionsTimeoutSecs` | int | `604800` | TCP session timeout (seconds, default 7 days) |
| `udpConnectionsTimeoutSecs` | int | `300` | UDP session timeout (seconds) |

### `hosts` (list)

At least one host is required. Each entry supports:

| Option | Type | Description |
|--------|------|-------------|
| `hostname` | string | **Required.** Hostname this certificate covers |
| `certChainPath` | path | **Required.** Path to PEM certificate chain file |
| `privateKeyPath` | path | **Required.** Path to PEM private key file |

### `metrics`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `metrics.address` | string or null | `null` | Address for the metrics HTTP server (e.g. `"127.0.0.1:9100"`). Disabled when null. |

## Credentials File Format

The credentials file is a TOML file listing authorized users:

```toml
[[client]]
username = "alice"
password = "s3cr3t"

[[client]]
username = "bob"
password = "an0th3rp4ss"
```

> The credentials file is copied to `/run/trusttunnel/credentials.toml` at service start with permissions `0600`. Use a secrets manager to provide the source file.

## Examples

### Basic single-host server

```nix
services.trusttunnel.server = {
  enable = true;
  credentialsFile = "/run/secrets/trusttunnel-credentials.toml";
  hosts = [
    {
      hostname = "vpn.example.com";
      certChainPath = "/var/lib/acme/vpn.example.com/fullchain.pem";
      privateKeyPath = "/var/lib/acme/vpn.example.com/key.pem";
    }
  ];
};
```

### Multi-host server (SNI routing)

```nix
services.trusttunnel.server = {
  enable = true;
  credentialsFile = "/run/secrets/trusttunnel-credentials.toml";
  hosts = [
    {
      hostname = "vpn1.example.com";
      certChainPath = "/var/lib/acme/vpn1.example.com/fullchain.pem";
      privateKeyPath = "/var/lib/acme/vpn1.example.com/key.pem";
    }
    {
      hostname = "vpn2.example.com";
      certChainPath = "/var/lib/acme/vpn2.example.com/fullchain.pem";
      privateKeyPath = "/var/lib/acme/vpn2.example.com/key.pem";
    }
  ];
};
```

### With metrics and custom timeouts

```nix
services.trusttunnel.server = {
  enable = true;
  credentialsFile = "/run/secrets/trusttunnel-credentials.toml";

  tlsHandshakeTimeoutSecs = 15;
  udpConnectionsTimeoutSecs = 120;

  metrics.address = "127.0.0.1:9100";

  hosts = [
    {
      hostname = "vpn.example.com";
      certChainPath = "/var/lib/acme/vpn.example.com/fullchain.pem";
      privateKeyPath = "/var/lib/acme/vpn.example.com/key.pem";
    }
  ];
};
```

### With ACME (Let's Encrypt) certificates

NixOS can automatically obtain and renew TLS certificates via Let's Encrypt.

**Prerequisites:**
- A domain pointing to your server's IP (DNS A record)
- Port 80 open for the ACME HTTP-01 challenge

```nix
# Enable ACME and request a certificate for your domain
security.acme = {
  acceptTerms = true;
  defaults.email = "admin@example.com";
  certs."vpn.example.com" = {};
};

# Open port 80 for ACME HTTP-01 challenge (certificate renewal)
networking.firewall.allowedTCPPorts = [ 80 443 ];
networking.firewall.allowedUDPPorts = [ 443 ]; # if using HTTP/3

# Allow the trusttunnel user to read ACME certificates
users.users.trusttunnel.extraGroups = [ "acme" ];

services.trusttunnel.server = {
  enable = true;
  credentialsFile = "/run/secrets/trusttunnel-credentials.toml";
  hosts = [
    {
      hostname = "vpn.example.com";
      # NixOS places ACME certs here automatically
      certChainPath = "/var/lib/acme/vpn.example.com/fullchain.pem";
      privateKeyPath = "/var/lib/acme/vpn.example.com/key.pem";
    }
  ];
};
```

> **Note:** On first deploy NixOS will run `nixos-rebuild switch`, which triggers
> certificate issuance. The service starts automatically once the cert is ready.
> Renewals happen automatically via a systemd timer — no action needed.

**DNS challenge (if port 80 is not available):**

If your server cannot expose port 80, use a DNS challenge instead. This requires
API credentials for your DNS provider. See the
[NixOS ACME options](https://search.nixos.org/options?query=security.acme) for
supported providers (`security.acme.certs.<name>.dnsProvider`).

## Secrets Management

Use [agenix](https://github.com/ryantm/agenix) or [sops-nix](https://github.com/Mic92/sops-nix) to provide the credentials file:

```nix
# sops-nix example
sops.secrets."trusttunnel-credentials.toml" = {
  owner = "root"; # copied by root at service start
};

services.trusttunnel.server = {
  enable = true;
  credentialsFile = config.sops.secrets."trusttunnel-credentials.toml".path;
  hosts = [ ... ];
};
```

## Firewall

Open port 443 in the NixOS firewall:

```nix
networking.firewall.allowedTCPPorts = [ 443 ];
networking.firewall.allowedUDPPorts = [ 443 ]; # if using HTTP/3
```

## Systemd Service

The module creates a systemd service named `trusttunnel-server`. Common commands:

```bash
# Check status
systemctl status trusttunnel-server

# View logs
journalctl -u trusttunnel-server -f

# Restart
systemctl restart trusttunnel-server
```
