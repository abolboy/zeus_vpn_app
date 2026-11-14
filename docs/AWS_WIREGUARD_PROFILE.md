# Importing an AWS WireGuard client profile

ZEUS imports a **client** WireGuard configuration and passes it to the Xray WireGuard outbound. The app supports one `[Peer]` section per profile. It does not need a second Android VPN service for this path.

## Create a client profile on the server

Use a separate key pair for every client device. Do not put the server's private key in the phone profile.

A client profile has this general shape. Replace every placeholder with values from your own WireGuard setup; these example addresses are documentation placeholders, not working server details.

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = <CLIENT_TUNNEL_IPV4>/32
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <OPTIONAL_PRESHARED_KEY>
Endpoint = <AWS_PUBLIC_IP_OR_DNS>:<WIREGUARD_UDP_PORT>
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

For full-tunnel routing, use `0.0.0.0/0`; add `::/0` only when IPv6 is configured end-to-end on the client, server, and AWS network.

**Current ZEUS limitation:** the app routes the selected proxy traffic through the WireGuard outbound, but it does not yet generate complementary direct-route rules for destinations outside a restricted `AllowedIPs` list. Use full-tunnel `AllowedIPs` for the supported configuration. Do not rely on a narrow split-tunnel list to make all other traffic fall back to the normal internet path; unmatched traffic may fail instead. Split-tunnel routing needs a separate app-level routing feature and device tests before it can be called supported.

The `PublicKey` under `[Peer]` must be the server's WireGuard public key. The `PrivateKey` under `[Interface]` must be the phone/client's private key. The `Endpoint` must be the server's externally reachable public address and its actual WireGuard UDP listening port, not the EC2 instance's private VPC address.

## Import in ZEUS

1. Copy the complete client `.conf` text.
2. Open ZEUS → Settings → WireGuard / Cloudflare WARP → **Import WireGuard profile**.
3. Paste the profile and import it.
4. Enable the WireGuard tunnel.
5. Choose **WireGuard only** to route directly through the WireGuard server, or **Chain** to send the selected VLESS/VMess/Trojan server connection through WireGuard.
6. Connect and verify the public IP and real traffic. A displayed connected service state alone is not proof that traffic passes through the intended path.

## What the importer preserves

The profile parser validates and carries forward:

- Client private key and server public key (32-byte Base64 keys)
- Optional preshared key
- Client interface IPv4/IPv6 addresses
- Peer endpoint and UDP port
- Peer `AllowedIPs`
- `PersistentKeepalive`
- Numeric DNS servers
- MTU when it matches one of the app's supported presets
- Three-byte `Reserved` value used by profiles that provide it

The current app accepts one peer per profile. Multiple `[Peer]` sections are rejected rather than being merged incorrectly. If `AllowedIPs` is omitted, ZEUS supplies a full-tunnel default for the address families configured on the interface. Explicit full-tunnel routes are preferable so the intended traffic policy is clear.

## Server-side requirements

A successful import does not configure the AWS instance. Verify separately that:

- The EC2 security group and any host firewall allow inbound UDP on the WireGuard listening port.
- The client endpoint uses the correct public IP/EIP or DNS record and port.
- The client peer exists on the server with the correct public key and tunnel address.
- IP forwarding and the required routing/NAT rules are configured for the full-tunnel design currently supported by ZEUS.
- The server's return routes and any VPC route/security rules permit the traffic you expect.

The importer does not probe or modify the VPS, security group, firewall, forwarding, or NAT settings.

## Protect the profile

A WireGuard client file contains private key material and may also contain a preshared key. Never commit it to GitHub, paste it into public issues, or share it in screenshots. Keep the original client `.conf` in a separate encrypted password manager or secure offline location.

ZEUS stores the imported profile with the app's Android Keystore-backed encrypted credential storage. This storage is bound to the device/app installation; it is not cloud sync or a portable backup. Reinstalling the app or moving to another phone can require importing the profile again. See [Credential storage and migration](CREDENTIAL_STORAGE.md) for the migration and recovery behavior.
