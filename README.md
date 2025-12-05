# LuCI IPsec VPN Application for OpenWrt
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fjigarladhava%2FOpenWrtLuCI_IPSEC_AG-702.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fjigarladhava%2FOpenWrtLuCI_IPSEC_AG-702?ref=badge_shield)


A LuCI web interface application for configuring IPsec site-to-site VPN connections using Libreswan on OpenWrt routers.

**Tested on:** Atreyo AG-702 Modem

## Features

- **Easy Configuration** - Web-based UI for IPsec site-to-site VPN setup
- **Phase 1 & 2 Settings** - Full control over IKE and ESP parameters
- **Dead Peer Detection** - Automatic detection and recovery from connection failures
- **Health Monitoring** - Active ping-based tunnel monitoring with automatic restart
- **Firewall Integration** - Automatic firewall rules and NAT exception management
- **Status Dashboard** - Real-time connection status, traffic statistics, and logs

## Requirements

### Hardware
- OpenWrt-compatible router (tested on Atreyo AG-702)

### Software Dependencies
These packages are required on the router:
```
libreswan ip-full kmod-ipsec kmod-ipsec4 kmod-crypto-cbc kmod-crypto-hmac kmod-crypto-sha256
```

The application will detect and prompt to install missing packages automatically.

## Installation

### From Windows (PowerShell)

#### Step 1: Build Package

```powershell
cd D:\Development\AG-702Release
New-Item -ItemType Directory -Force -Path build\luci-app-ipsec-vpn
Copy-Item -Recurse -Force luci-app-ipsec-vpn\* build\luci-app-ipsec-vpn\
cd build
tar -czf luci-app-ipsec-vpn.tar.gz luci-app-ipsec-vpn
cd ..
```

#### Step 2: Transfer to Router

```powershell
scp build\luci-app-ipsec-vpn.tar.gz root@192.168.1.1:/tmp/
```

#### Step 3: Deploy on Router

SSH into router and run:

```bash
cd /tmp
tar xzf luci-app-ipsec-vpn.tar.gz

# Create directories
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/model/cbi/ipsec
mkdir -p /usr/lib/lua/luci/view/ipsec
mkdir -p /usr/lib/lua/ipsec
mkdir -p /etc/config
mkdir -p /usr/sbin

# Copy files
cp -f luci-app-ipsec-vpn/luasrc/controller/ipsec.lua /usr/lib/lua/luci/controller/
cp -f luci-app-ipsec-vpn/luasrc/model/cbi/ipsec/*.lua /usr/lib/lua/luci/model/cbi/ipsec/
cp -f luci-app-ipsec-vpn/luasrc/view/ipsec/*.htm /usr/lib/lua/luci/view/ipsec/
cp -f luci-app-ipsec-vpn/root/usr/lib/lua/ipsec/*.lua /usr/lib/lua/ipsec/

# Copy config (only if doesn't exist)
[ ! -f /etc/config/ipsec ] && cp -f luci-app-ipsec-vpn/root/etc/config/ipsec /etc/config/

# Copy and enable scripts
cp -f luci-app-ipsec-vpn/root/usr/sbin/*.sh /usr/sbin/
chmod +x /usr/sbin/ipsec-*.sh
cp -f luci-app-ipsec-vpn/root/etc/init.d/ipsec-ping-monitor /etc/init.d/
chmod +x /etc/init.d/ipsec-ping-monitor

# Run setup and clear cache
cp -f luci-app-ipsec-vpn/root/etc/uci-defaults/50-ipsec-vpn /etc/uci-defaults/
chmod +x /etc/uci-defaults/50-ipsec-vpn
/etc/uci-defaults/50-ipsec-vpn
rm -rf /tmp/luci-*

# Cleanup
rm -rf /tmp/luci-app-ipsec-vpn*
```

#### Step 4: Access Web Interface

1. Open browser: `http://192.168.1.1`
2. Login to LuCI
3. Navigate to: **VPN → IPsec VPN**

## Usage

### Basic Configuration

1. Go to **VPN → IPsec VPN → Configuration**
2. Fill in:
   - **Remote Gateway IP** - Public IP of the remote VPN endpoint
   - **Remote Subnet** - Network behind remote gateway (e.g., `10.0.0.0/24`)
   - **Local Subnet** - Your local network (e.g., `192.168.1.0/24`)
   - **Pre-Shared Key** - Shared secret (minimum 16 characters recommended)
3. Enable the VPN and click **Save & Apply**

### Advanced Settings

Go to **VPN → IPsec VPN → Advanced** to configure:
- IKE version (IKEv1/IKEv2)
- Encryption algorithms (AES-128/192/256, 3DES)
- Hash algorithms (SHA1, SHA2-256/384/512)
- DH Groups for key exchange
- Lifetime settings
- Dead Peer Detection parameters

### Health Monitoring

Go to **VPN → IPsec VPN → Monitoring** to enable active tunnel monitoring:
- Configurable ping targets in remote network
- Automatic IPsec restart on connectivity loss
- LED status indication (device-specific)

## File Structure

```
luci-app-ipsec-vpn/
├── luasrc/
│   ├── controller/ipsec.lua      # Routes and AJAX endpoints
│   ├── model/cbi/ipsec/          # Configuration forms
│   │   ├── config.lua            # Basic settings
│   │   ├── advanced.lua          # Phase 1/2 settings
│   │   └── monitoring.lua        # Health monitoring
│   └── view/ipsec/               # HTML templates
├── root/
│   ├── etc/
│   │   ├── config/ipsec          # UCI configuration schema
│   │   └── init.d/               # procd service scripts
│   └── usr/
│       ├── lib/lua/ipsec/        # Helper libraries
│       │   ├── helper.lua        # Core functions
│       │   └── firewall.lua      # Firewall management
│       └── sbin/                 # Runtime scripts
│           ├── ipsec-route.sh    # Route management
│           └── ipsec-ping-monitor.sh  # Health monitor daemon
```

## Troubleshooting

### VPN Not Connecting

```bash
# Check IPsec status
ipsec status

# View logs
logread | grep pluto

# Verify configuration
cat /etc/ipsec.conf
```

### Web Interface Not Appearing

```bash
# Clear LuCI cache
rm -rf /tmp/luci-*

# Restart web server
/etc/init.d/uhttpd restart
```

### Route Issues

```bash
# Check routes
ip route | grep <remote_subnet>

# Manually refresh routes
/usr/sbin/ipsec-route.sh
```

### Firewall Issues

```bash
# Check NAT exception rule
nft list chain inet fw4 srcnat | head -10

# Verify firewall rules
uci show firewall | grep -i ipsec
```

## Verification

After setup, verify connectivity:

```bash
# On router
ipsec status                    # Should show "established"
ip route | grep <remote_subnet> # Should show route

# From LAN client
ping <ip_in_remote_subnet>      # Should get replies
```

## License

MIT License


[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fjigarladhava%2FOpenWrtLuCI_IPSEC_AG-702.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fjigarladhava%2FOpenWrtLuCI_IPSEC_AG-702?ref=badge_large)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes on actual hardware
4. Submit a pull request