#!/bin/sh
#
# IPsec Connection Monitor
# Automatically detects and fixes "cannot identify ourselves" error
# that occurs when network interfaces change and Libreswan fails to rebind
#

# Skip if IPsec is not enabled
ENABLED=$(uci get ipsec.main.enabled 2>/dev/null)
[ "$ENABLED" = "1" ] || exit 0

# Get connection name from UCI
CONN_NAME=$(uci get ipsec.main.name 2>/dev/null)
[ -z "$CONN_NAME" ] && exit 0

# Check if pluto is running
if [ ! -S /var/run/pluto/pluto.ctl ]; then
	logger -t ipsec-monitor "Pluto not running, skipping check"
	exit 0
fi

# Get IPsec status
STATUS=$(ipsec whack --status 2>&1)

# Check for error conditions
HAS_ERROR=0

# Check 1: my_ip = unset
if echo "$STATUS" | grep -q "my_ip = unset"; then
	logger -t ipsec-monitor "ERROR DETECTED: my_ip = unset"
	HAS_ERROR=1
fi

# Check 2: our idtype = %none
if echo "$STATUS" | grep -q "our idtype.*%none"; then
	logger -t ipsec-monitor "ERROR DETECTED: our idtype = %none"
	HAS_ERROR=1
fi

# Check 3: connection unrouted
if echo "$STATUS" | grep -q "unrouted"; then
	logger -t ipsec-monitor "ERROR DETECTED: connection unrouted"
	HAS_ERROR=1
fi

# Check 4: Try to get full status with connection name
CONN_STATUS=$(ipsec whack --status | grep -A10 "\"$CONN_NAME\"" 2>&1)

# Check for "cannot identify" error
if echo "$CONN_STATUS" | grep -q "cannot identify\|0\.0\.0\.0.*not usable"; then
	logger -t ipsec-monitor "ERROR DETECTED: cannot identify ourselves"
	HAS_ERROR=1
fi

# If error detected, restart network service
if [ "$HAS_ERROR" = "1" ]; then
	logger -t ipsec-monitor "Interface binding issue detected - restarting network service"

	# Restart network service (this reinitializes interfaces and allows Libreswan to rebind)
	service network restart 2>&1 | logger -t ipsec-monitor

	# Wait for network and IPsec to stabilize (IPsec will auto-reconnect)
	sleep 15

	# Refresh routes
	/usr/sbin/ipsec-route.sh 2>&1 | logger -t ipsec-monitor

	logger -t ipsec-monitor "Network restart completed - IPsec should auto-reconnect"
else
	# No error, connection is healthy
	exit 0
fi

exit 0
