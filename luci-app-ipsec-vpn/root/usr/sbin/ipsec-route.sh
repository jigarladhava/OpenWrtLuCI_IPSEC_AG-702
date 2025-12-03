#!/bin/sh
#
# IPsec VPN Route Management Script
# Automatically detects WAN interface and adds appropriate route
#

# Get configuration from UCI
REMOTE_SUBNET=$(uci get ipsec.main.remote_subnet 2>/dev/null)
REMOTE_GW=$(uci get ipsec.main.remote_ip 2>/dev/null)

# Validate configuration
if [ -z "$REMOTE_SUBNET" ] || [ -z "$REMOTE_GW" ]; then
	echo "Error: IPsec configuration not found"
	logger -t ipsec-route "ERROR: IPsec configuration not found in UCI"
	exit 1
fi

# Find the interface used to reach the VPN gateway
DEFAULT_IF=$(ip route get ${REMOTE_GW} 2>/dev/null | grep -oP 'dev \K\S+' | head -n1)

if [ -z "$DEFAULT_IF" ]; then
	# Fallback: check default route
	DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
fi

if [ -z "$DEFAULT_IF" ]; then
	echo "Error: Could not determine active WAN interface"
	logger -t ipsec-route "ERROR: Could not determine active WAN interface"
	exit 1
fi

echo "Active WAN interface: $DEFAULT_IF"
logger -t ipsec-route "Active WAN interface: $DEFAULT_IF"

# Remove old route if exists
ip route del ${REMOTE_SUBNET} 2>/dev/null

# Add route based on interface type
if echo "$DEFAULT_IF" | grep -qE '^(3g-lte|pppoe|wwan|wlan)'; then
	# For PPP/wireless interfaces, route directly through the interface
	ip route add ${REMOTE_SUBNET} dev ${DEFAULT_IF}
	echo "Route added: ${REMOTE_SUBNET} dev ${DEFAULT_IF}"
	logger -t ipsec-route "Route added: ${REMOTE_SUBNET} dev ${DEFAULT_IF}"
else
	# For ethernet interfaces, use gateway
	ip route add ${REMOTE_SUBNET} via ${REMOTE_GW} dev ${DEFAULT_IF}
	echo "Route added: ${REMOTE_SUBNET} via ${REMOTE_GW} dev ${DEFAULT_IF}"
	logger -t ipsec-route "Route added: ${REMOTE_SUBNET} via ${REMOTE_GW} dev ${DEFAULT_IF}"
fi

# Verify route
if ip route | grep -q ${REMOTE_SUBNET}; then
	echo "Route verification successful"
	logger -t ipsec-route "Route verification successful"
	ip route | grep ${REMOTE_SUBNET}
	exit 0
else
	echo "Warning: Route may not be active"
	logger -t ipsec-route "WARNING: Route may not be active"
	exit 1
fi
