--[[
LuCI - IPsec VPN Controller
Copyright (C) 2024
Licensed under MIT License
]]--

module("luci.controller.ipsec", package.seeall)

function index()
	local sys = require "luci.sys"

	-- Only show if ipsec is installed
	if not sys.call("which ipsec >/dev/null 2>&1") == 0 then
		return
	end

	-- Create VPN menu entry
	entry({"admin", "vpn"}, firstchild(), _("VPN"), 60).dependent = false

	-- IPsec main entry
	entry({"admin", "vpn", "ipsec"}, alias("admin", "vpn", "ipsec", "overview"), _("IPsec VPN"), 10)

	-- Overview page
	entry({"admin", "vpn", "ipsec", "overview"}, template("ipsec/overview"), _("Overview"), 1)

	-- Configuration page
	entry({"admin", "vpn", "ipsec", "config"}, cbi("ipsec/config"), _("Configuration"), 2)

	-- Advanced settings page
	entry({"admin", "vpn", "ipsec", "advanced"}, cbi("ipsec/advanced"), _("Advanced"), 3)

	-- Status page
	entry({"admin", "vpn", "ipsec", "status"}, template("ipsec/status"), _("Status"), 4)

	-- Logs page
	entry({"admin", "vpn", "ipsec", "logs"}, template("ipsec/logs"), _("Logs"), 5)

	-- Monitoring tab
	entry({"admin", "vpn", "ipsec", "monitoring"}, cbi("ipsec/monitoring"), _("Monitoring"), 6)

	-- AJAX endpoints (no menu entries)
	entry({"admin", "vpn", "ipsec", "action_start"}, call("action_start"))
	entry({"admin", "vpn", "ipsec", "action_stop"}, call("action_stop"))
	entry({"admin", "vpn", "ipsec", "action_restart"}, call("action_restart"))
	entry({"admin", "vpn", "ipsec", "action_test"}, call("action_test"))
	entry({"admin", "vpn", "ipsec", "get_status"}, call("action_get_status"))
	entry({"admin", "vpn", "ipsec", "get_logs"}, call("action_get_logs"))
	entry({"admin", "vpn", "ipsec", "apply_config"}, call("action_apply_config"))
	entry({"admin", "vpn", "ipsec", "check_deps"}, call("action_check_deps"))
	entry({"admin", "vpn", "ipsec", "install_deps"}, call("action_install_deps"))
	entry({"admin", "vpn", "ipsec", "ping_status"}, call("action_ping_status"))
	entry({"admin", "vpn", "ipsec", "ping_logs"}, call("action_ping_logs"))
end

-- Start IPsec service
function action_start()
	local sys = require "luci.sys"
	local result = sys.call("/etc/init.d/ipsec start") == 0

	luci.http.prepare_content("application/json")
	luci.http.write_json({
		success = result,
		message = result and "IPsec service started" or "Failed to start IPsec service"
	})
end

-- Stop IPsec service
function action_stop()
	local sys = require "luci.sys"
	local result = sys.call("/etc/init.d/ipsec stop") == 0

	luci.http.prepare_content("application/json")
	luci.http.write_json({
		success = result,
		message = result and "IPsec service stopped" or "Failed to stop IPsec service"
	})
end

-- Restart IPsec service
function action_restart()
	local sys = require "luci.sys"
	local result = sys.call("/etc/init.d/ipsec restart") == 0

	luci.http.prepare_content("application/json")
	luci.http.write_json({
		success = result,
		message = result and "IPsec service restarted" or "Failed to restart IPsec service"
	})
end

-- Test connectivity
function action_test()
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()
	local http = require "luci.http"

	local target = http.formvalue("target") or ""
	local count = tonumber(http.formvalue("count")) or 4

	-- Validate target IP
	if not target:match("^%d+%.%d+%.%d+%.%d+$") then
		http.prepare_content("application/json")
		http.write_json({
			success = false,
			message = "Invalid IP address",
			output = ""
		})
		return
	end

	-- Get local subnet to determine source IP
	local local_subnet = uci:get("ipsec", "main", "local_subnet") or "192.168.1.0/24"
	local source_ip = local_subnet:match("^([^/]+)"):gsub("%.0$", ".1")

	-- Execute ping
	local cmd = string.format("ping -c %d -W 3 -I %s %s 2>&1", count, source_ip, target)
	local output = sys.exec(cmd)

	-- Check for "X packets received" pattern (works with BusyBox ping)
	local received = output:match("(%d+) packets received") or output:match("(%d+) received")
	local success = received and tonumber(received) > 0

	http.prepare_content("application/json")
	http.write_json({
		success = success,
		message = success and "Connection successful" or "Connection failed",
		output = output
	})
end

-- Get VPN status
function action_get_status()
	local sys = require "luci.sys"
	local helper = require "ipsec.helper"
	local http = require "luci.http"

	local status = helper.get_vpn_status()

	http.prepare_content("application/json")
	http.write_json(status)
end

-- Get logs
function action_get_logs()
	local sys = require "luci.sys"
	local http = require "luci.http"

	local lines = tonumber(http.formvalue("lines")) or 100
	local filter = http.formvalue("filter") or "pluto"

	local cmd = string.format("logread | grep '%s' | tail -%d", filter, lines)
	local output = sys.exec(cmd)

	http.prepare_content("application/json")
	http.write_json({
		success = true,
		logs = output
	})
end

-- Apply configuration
function action_apply_config()
	local helper = require "ipsec.helper"
	local firewall = require "ipsec.firewall"
	local http = require "luci.http"
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()

	-- Generate configuration files
	local ok, err = helper.apply_config()
	if not ok then
		http.prepare_content("application/json")
		http.write_json({
			success = false,
			message = "Configuration error: " .. tostring(err)
		})
		return
	end

	-- Apply firewall configuration
	local local_subnet = uci:get("ipsec", "main", "local_subnet")
	local remote_subnet = uci:get("ipsec", "main", "remote_subnet")

	ok, err = firewall.apply_firewall(local_subnet, remote_subnet)
	if not ok then
		http.prepare_content("application/json")
		http.write_json({
			success = false,
			message = "Firewall configuration error: " .. tostring(err)
		})
		return
	end

	-- Restart IPsec service
	sys.call("/etc/init.d/ipsec restart")

	-- Wait and add route
	sys.call("sleep 5 && /usr/sbin/ipsec-route.sh &")

	http.prepare_content("application/json")
	http.write_json({
		success = true,
		message = "Configuration applied successfully"
	})
end

-- Check missing dependencies (returns list of missing packages)
function action_check_deps()
	local helper = require "ipsec.helper"
	local http = require "luci.http"

	local missing = helper.get_missing()
	local all_ok = (#missing == 0)

	http.prepare_content("application/json")
	http.write_json({
		success = all_ok,
		missing = missing,
		message = all_ok and "All dependencies installed" or "Missing packages: " .. table.concat(missing, ", "),
		install_cmd = all_ok and "" or ("opkg update && opkg install " .. table.concat(missing, " "))
	})
end

-- Install missing dependencies (runs opkg update && opkg install ...)
function action_install_deps()
	local helper = require "ipsec.helper"
	local http = require "luci.http"

	local ok, logs, missing = helper.ensure_all(true)  -- auto_install = true

	http.prepare_content("application/json")
	http.write_json({
		success = ok,
		missing = missing or {},
		message = ok and "All packages installed successfully" or ("Installation failed: " .. (logs or "unknown error")),
		logs = logs or ""
	})
end

-- Get ping monitor status
function action_ping_status()
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()
	local fs = require "nixio.fs"
	local http = require "luci.http"

	local enabled = uci:get("ipsec", "health", "enabled") == "1"

	if not enabled then
		http.prepare_content("application/json")
		http.write_json({ enabled = false })
		return
	end

	-- Read state file
	local state_file = "/var/run/ipsec-ping-monitor.state"
	local state_data = fs.readfile(state_file) or ""

	local status = "UNKNOWN"
	local failures = 0
	local last_check = "Never"
	local target = "N/A"
	local last_timestamp = 0

	if state_data ~= "" then
		local parts = {}
		for part in state_data:gmatch("[^|]+") do
			table.insert(parts, part)
		end

		status = parts[1] or "UNKNOWN"
		if status == "OK" then
			target = parts[2] or ""
			last_timestamp = tonumber(parts[3]) or 0
		elseif status == "FAIL" then
			failures = tonumber(parts[2]) or 0
			last_timestamp = tonumber(parts[3]) or 0
		elseif status == "RECOVERY" then
			last_timestamp = tonumber(parts[2]) or 0
		end

		-- Calculate relative time
		if last_timestamp > 0 then
			local now = os.time()
			local diff = now - last_timestamp
			if diff < 60 then
				last_check = diff .. " seconds ago"
			elseif diff < 3600 then
				local mins = math.floor(diff / 60)
				local secs = diff % 60
				last_check = mins .. "m " .. secs .. "s ago"
			else
				local hours = math.floor(diff / 3600)
				local mins = math.floor((diff % 3600) / 60)
				last_check = hours .. "h " .. mins .. "m ago"
			end
		end
	end

	local local_ip = uci:get("ipsec", "health", "local_ip") or ""
	if local_ip == "" then
		local subnet = uci:get("ipsec", "main", "local_subnet") or ""
		local_ip = subnet:match("^([^/]+)"):gsub("%.0$", ".1")
	end

	http.prepare_content("application/json")
	http.write_json({
		enabled = true,
		status = status,
		local_ip = local_ip,
		primary = uci:get("ipsec", "health", "remote_primary") or "",
		secondary = uci:get("ipsec", "health", "remote_secondary") or "",
		failures = failures,
		max_tries = uci:get("ipsec", "health", "max_tries") or "3",
		last_check = last_check,
		next_check = uci:get("ipsec", "health", "interval") or "1800",
		target = target
	})
end

-- Get ping monitor logs
function action_ping_logs()
	local sys = require "luci.sys"
	local http = require "luci.http"

	local logs = sys.exec("logread | grep ipsec-ping | tail -50")

	http.prepare_content("application/json")
	http.write_json({ logs = logs })
end
