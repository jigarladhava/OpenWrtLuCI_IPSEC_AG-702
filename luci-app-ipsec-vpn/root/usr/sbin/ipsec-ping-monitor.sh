#!/bin/sh
#
# IPsec Ping Monitor Daemon
# Actively monitors tunnel connectivity via ping with automatic recovery
#

# LED control
LED_PATH="/sys/class/gpio/led_rs232/value"

led_on() {
	echo "1" > "$LED_PATH" 2>/dev/null
}

led_off() {
	echo "0" > "$LED_PATH" 2>/dev/null
}

# Exit if IPsec VPN is not enabled
IPSEC_ENABLED=$(uci get ipsec.main.enabled 2>/dev/null)
if [ "$IPSEC_ENABLED" != "1" ]; then
	led_off
	exit 0
fi

# Read configuration from UCI
ENABLED=$(uci get ipsec.health.enabled 2>/dev/null)
LOCAL_IP=$(uci get ipsec.health.local_ip 2>/dev/null)
PRIMARY=$(uci get ipsec.health.remote_primary 2>/dev/null)
SECONDARY=$(uci get ipsec.health.remote_secondary 2>/dev/null)
INITIAL_WAIT=$(uci get ipsec.health.initial_wait 2>/dev/null || echo 10)
INTERVAL=$(uci get ipsec.health.interval 2>/dev/null || echo 1800)
RETRY_INTERVAL=$(uci get ipsec.health.retry_interval 2>/dev/null || echo 5)
TIMEOUT=$(uci get ipsec.health.timeout 2>/dev/null || echo 3)
MAX_TRIES=$(uci get ipsec.health.max_tries 2>/dev/null || echo 3)

# State file for tracking
STATE_FILE="/var/run/ipsec-ping-monitor.state"
FAILURE_COUNT=0

# Auto-detect local IP if not manually set
if [ -z "$LOCAL_IP" ]; then
	LOCAL_SUBNET=$(uci get ipsec.main.local_subnet 2>/dev/null)
	if [ -n "$LOCAL_SUBNET" ]; then
		# Extract IP from CIDR and convert .0 to .1
		LOCAL_IP=$(echo "$LOCAL_SUBNET" | cut -d'/' -f1 | sed 's/\.0$/.1/')
	fi
fi

# Validate configuration
if [ -z "$PRIMARY" ] || [ -z "$LOCAL_IP" ]; then
	logger -t ipsec-ping "ERROR: Missing configuration (primary IP or local IP)"
	exit 1
fi

logger -t ipsec-ping "Starting ping monitor daemon"
logger -t ipsec-ping "Config: Local=$LOCAL_IP, Primary=$PRIMARY, Secondary=$SECONDARY"
logger -t ipsec-ping "Timings: Interval=${INTERVAL}s, Retry=${RETRY_INTERVAL}s, Timeout=${TIMEOUT}s, MaxTries=$MAX_TRIES"

# Initial wait after boot
sleep $INITIAL_WAIT

# Main monitoring loop
while true; do
	# Re-read enabled status (allow runtime disable)
	ENABLED=$(uci get ipsec.health.enabled 2>/dev/null)

	if [ "$ENABLED" != "1" ]; then
		# Disabled - turn off LED and check again in 60 seconds
		led_off
		sleep 60
		continue
	fi

	# Try ping to primary target
	PING_SUCCESS=0
	TARGET_USED=""

	if ping -c 1 -W $TIMEOUT -I $LOCAL_IP $PRIMARY >/dev/null 2>&1; then
		PING_SUCCESS=1
		TARGET_USED="$PRIMARY (primary)"
	else
		# Primary failed, try secondary if configured
		if [ -n "$SECONDARY" ]; then
			if ping -c 1 -W $TIMEOUT -I $LOCAL_IP $SECONDARY >/dev/null 2>&1; then
				PING_SUCCESS=1
				TARGET_USED="$SECONDARY (secondary)"
			fi
		fi
	fi

	if [ $PING_SUCCESS -eq 1 ]; then
		# Success - LED ON
		led_on
		if [ $FAILURE_COUNT -gt 0 ]; then
			logger -t ipsec-ping "Tunnel recovered - $TARGET_USED reachable"
		fi
		FAILURE_COUNT=0
		echo "OK|$TARGET_USED|$(date +%s)" > $STATE_FILE
		sleep $INTERVAL
	else
		# Failure - LED OFF
		led_off
		FAILURE_COUNT=$((FAILURE_COUNT + 1))
		logger -t ipsec-ping "Ping failed - attempt $FAILURE_COUNT/$MAX_TRIES"
		echo "FAIL|$FAILURE_COUNT|$(date +%s)" > $STATE_FILE

		if [ $FAILURE_COUNT -ge $MAX_TRIES ]; then
			# Max tries reached - trigger recovery
			logger -t ipsec-ping "Max ping failures reached - restarting IPsec"

			# Restart IPsec service
			/etc/init.d/ipsec restart 2>&1 | logger -t ipsec-ping

			# Wait for IPsec to come up
			sleep 15

			# Refresh routes
			/usr/sbin/ipsec-route.sh 2>&1 | logger -t ipsec-ping

			logger -t ipsec-ping "IPsec restart completed"

			# Reset counter and wait before next check
			FAILURE_COUNT=0
			echo "RECOVERY|$(date +%s)" > $STATE_FILE
			sleep 30
		else
			# Retry after short interval
			sleep $RETRY_INTERVAL
		fi
	fi
done
