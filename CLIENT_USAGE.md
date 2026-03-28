# TrustTunnel Client — NixOS Module Usage

## Quick Start

Add the flake to your `flake.nix`:

```nix
inputs.trust-tunnel-nix.url = "github:youruser/trust-tunnel-nix";
```

Import the module and configure:

```nix
{ inputs, ... }:
{
  imports = [ inputs.trust-tunnel-nix.nixosModules.client ];

  services.trusttunnel.client = {
    enable = true;

    endpoint = {
      hostname = "vpn.example.com";
      addresses = [ "203.0.113.10:443" ];
      username = "myuser";
      passwordFile = "/run/secrets/trusttunnel-password";
    };
  };
}
```

## Options Reference

### Top-level

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the TrustTunnel client service |
| `package` | package | `pkgs.trusttunnel` | Package to use |
| `user` | string | `"trusttunnel-client"` | System user to run the service as |
| `group` | string | `"trusttunnel-client"` | System group |
| `loglevel` | enum | `"info"` | Log level: `info`, `debug`, `trace` |
| `vpnMode` | enum | `"general"` | VPN mode: `general` (all traffic) or `selective` |
| `killswitchEnabled` | bool | `true` | Block all traffic if VPN connection drops |
| `killswitchAllowPorts` | list of int | `[]` | Ports to allow through killswitch (e.g. SSH) |
| `postQuantumGroupEnabled` | bool | `true` | Enable post-quantum cryptography |
| `exclusions` | list of string | `[]` | CIDRs or hosts to exclude from VPN routing |
| `dnsUpstreams` | list of string | `[]` | Custom DNS servers to use over the VPN |

### `endpoint`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hostname` | string | — | **Required.** Server hostname |
| `addresses` | list of string | — | **Required.** Server addresses (host:port) |
| `username` | string | — | **Required.** Authentication username |
| `password` | string or null | `null` | Inline password (world-readable in /nix/store — avoid in production) |
| `passwordFile` | path or null | `null` | **Preferred.** Path to file containing the password |
| `hasIpv6` | bool | `true` | Whether the endpoint has IPv6 |
| `upstreamProtocol` | enum | `"http2"` | Transport protocol: `http2` or `http3` |
| `skipVerification` | bool | `false` | Skip TLS certificate verification |
| `antiDpi` | bool | `false` | Enable anti-DPI obfuscation |
| `clientRandom` | string or null | `null` | Client random value |
| `certificate` | string or null | `null` | Custom PEM certificate (inline) |

> **Note:** Exactly one of `password` or `passwordFile` must be set.

### `listener.tun`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `true` | Enable TUN interface (system-wide VPN) |
| `includedRoutes` | list of string | `["0.0.0.0/0", "2000::/3"]` | Routes to tunnel through VPN |
| `excludedRoutes` | list of string | `[]` | Routes to exclude from tunneling |
| `mtuSize` | int | `1280` | TUN interface MTU |
| `changeSystemDns` | bool | `true` | Redirect system DNS through VPN |

### `listener.socks`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable SOCKS5 proxy listener |
| `address` | string | `"127.0.0.1:1080"` | Bind address for the SOCKS proxy |

## Examples

### Minimal configuration with password file

```nix
services.trusttunnel.client = {
  enable = true;
  endpoint = {
    hostname = "vpn.example.com";
    addresses = [ "203.0.113.10:443" ];
    username = "alice";
    passwordFile = "/run/secrets/trusttunnel-password";
  };
};
```

### Keep SSH accessible through killswitch

```nix
services.trusttunnel.client = {
  enable = true;
  killswitchEnabled = true;
  killswitchAllowPorts = [ 22 ];
  endpoint = {
    hostname = "vpn.example.com";
    addresses = [ "203.0.113.10:443" ];
    username = "alice";
    passwordFile = "/run/secrets/trusttunnel-password";
  };
};
```

### Selective routing (only tunnel specific CIDRs)

```nix
services.trusttunnel.client = {
  enable = true;
  vpnMode = "selective";
  endpoint = {
    hostname = "vpn.example.com";
    addresses = [ "203.0.113.10:443" ];
    username = "alice";
    passwordFile = "/run/secrets/trusttunnel-password";
  };
  listener.tun = {
    includedRoutes = [ "10.0.0.0/8" ];
    changeSystemDns = false;
  };
};
```

### SOCKS proxy only (no TUN)

```nix
services.trusttunnel.client = {
  enable = true;
  endpoint = {
    hostname = "vpn.example.com";
    addresses = [ "203.0.113.10:443" ];
    username = "alice";
    passwordFile = "/run/secrets/trusttunnel-password";
  };
  listener = {
    tun.enable = false;
    socks = {
      enable = true;
      address = "127.0.0.1:1080";
    };
  };
};
```

### HTTP/3 with anti-DPI

```nix
services.trusttunnel.client = {
  enable = true;
  endpoint = {
    hostname = "vpn.example.com";
    addresses = [ "203.0.113.10:443" ];
    username = "alice";
    passwordFile = "/run/secrets/trusttunnel-password";
    upstreamProtocol = "http3";
    antiDpi = true;
  };
};
```

## Secrets Management

Use a secrets manager such as [agenix](https://github.com/ryantm/agenix) or [sops-nix](https://github.com/Mic92/sops-nix) to provide the password file:

```nix
# sops-nix example
sops.secrets."trusttunnel-password" = {};

services.trusttunnel.client = {
  enable = true;
  endpoint = {
    hostname = "vpn.example.com";
    addresses = [ "203.0.113.10:443" ];
    username = "alice";
    passwordFile = config.sops.secrets."trusttunnel-password".path;
  };
};
```

## Systemd Service

The module creates a systemd service named `trusttunnel-client`. Common commands:

```bash
# Check status
systemctl status trusttunnel-client

# View logs
journalctl -u trusttunnel-client -f

# Restart
systemctl restart trusttunnel-client
```
