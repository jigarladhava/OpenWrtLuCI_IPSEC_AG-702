#!/bin/sh
#
# Check why ping monitor daemon is not updating status
#

echo "=== Ping Monitor Daemon Diagnostic ==="
echo ""

echo "1. Checking if monitoring is enabled in config..."
ENABLED=$(uci get ipsec.health.enabled 2>/dev/null)
echo "   Enabled: $ENABLED"
if [ "$ENABLED" != "1" ]; then
    echo "   ⚠ Monitoring is DISABLED. Enable it in the UI first."
    echo ""
    echo "To enable manually:"
    echo "   uci set ipsec.health.enabled='1'"
    echo "   uci commit ipsec"
    echo "   /etc/init.d/ipsec-ping-monitor restart"
    exit 0
fi
echo ""

echo "2. Checking if daemon process is running..."
if ps | grep -v grep | grep ipsec-ping-monitor.sh >/dev/null 2>&1; then
    echo "   ✓ Daemon is running"
    ps | grep -v grep | grep ipsec-ping-monitor
else
    echo "   ✗ Daemon is NOT running"
    echo ""
    echo "   Checking init script..."
    if [ -f /etc/init.d/ipsec-ping-monitor ]; then
        echo "   ✓ Init script exists"
        echo ""
        echo "   Starting daemon..."
        /etc/init.d/ipsec-ping-monitor start
        sleep 2
        if ps | grep -v grep | grep ipsec-ping-monitor.sh >/dev/null 2>&1; then
            echo "   ✓ Daemon started successfully"
        else
            echo "   ✗ Failed to start daemon"
            echo ""
            echo "   Checking logs..."
            logread | grep ipsec-ping | tail -20
        fi
    else
        echo "   ✗ Init script NOT found at /etc/init.d/ipsec-ping-monitor"
    fi
fi
echo ""

echo "3. Checking daemon script..."
if [ -f /usr/sbin/ipsec-ping-monitor.sh ]; then
    echo "   ✓ Script exists"
    ls -lh /usr/sbin/ipsec-ping-monitor.sh
    if [ -x /usr/sbin/ipsec-ping-monitor.sh ]; then
        echo "   ✓ Script is executable"
    else
        echo "   ✗ Script is NOT executable"
        echo "   Fixing permissions..."
        chmod +x /usr/sbin/ipsec-ping-monitor.sh
    fi
else
    echo "   ✗ Script NOT found at /usr/sbin/ipsec-ping-monitor.sh"
fi
echo ""

echo "4. Checking state file..."
if [ -f /var/run/ipsec-ping-monitor.state ]; then
    echo "   ✓ State file exists"
    echo "   Content:"
    cat /var/run/ipsec-ping-monitor.state
    echo ""
else
    echo "   ⚠ State file does NOT exist yet"
    echo "   This is normal if daemon just started (wait up to initial_wait seconds)"
fi
echo ""

echo "5. Checking configuration values..."
echo "   Local IP: $(uci get ipsec.health.local_ip 2>/dev/null || echo 'auto-detect')"
echo "   Primary: $(uci get ipsec.health.remote_primary 2>/dev/null)"
echo "   Secondary: $(uci get ipsec.health.remote_secondary 2>/dev/null)"
echo "   Initial Wait: $(uci get ipsec.health.initial_wait 2>/dev/null)s"
echo "   Interval: $(uci get ipsec.health.interval 2>/dev/null)s"
echo "   Max Tries: $(uci get ipsec.health.max_tries 2>/dev/null)"
echo ""

echo "6. Checking recent logs..."
echo "   Last 20 lines from ipsec-ping:"
logread | grep ipsec-ping | tail -20
echo ""

echo "7. Testing manual ping (if daemon is configured)..."
PRIMARY=$(uci get ipsec.health.remote_primary 2>/dev/null)
LOCAL_IP=$(uci get ipsec.health.local_ip 2>/dev/null)
if [ -z "$LOCAL_IP" ]; then
    LOCAL_SUBNET=$(uci get ipsec.main.local_subnet 2>/dev/null)
    if [ -n "$LOCAL_SUBNET" ]; then
        LOCAL_IP=$(echo "$LOCAL_SUBNET" | sed 's|/.*||' | sed 's/\.0$/.1/')
    fi
fi

if [ -n "$PRIMARY" ] && [ -n "$LOCAL_IP" ]; then
    echo "   Testing: ping -c 1 -W 3 -I $LOCAL_IP $PRIMARY"
    if ping -c 1 -W 3 -I "$LOCAL_IP" "$PRIMARY" >/dev/null 2>&1; then
        echo "   ✓ Ping SUCCESS - tunnel appears to be working"
    else
        echo "   ✗ Ping FAILED - check if tunnel is up and routes are configured"
        echo ""
        echo "   Checking if route exists..."
        ip route | grep "$PRIMARY"
    fi
else
    echo "   ⚠ Cannot test - missing configuration"
fi
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "Next steps:"
echo "1. If daemon is not running, check logs above for errors"
echo "2. If ping fails, ensure IPsec tunnel is connected first"
echo "3. Wait $(uci get ipsec.health.initial_wait 2>/dev/null || echo 10)s after daemon start for first update"
echo "4. Check state file again: cat /var/run/ipsec-ping-monitor.state"
