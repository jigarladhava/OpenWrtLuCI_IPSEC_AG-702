--[[
LuCI - IPsec VPN Monitoring Configuration Page
]]--

local helper = require "ipsec.helper"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local fs = require "nixio.fs"

m = Map("ipsec", translate("IPsec VPN Monitoring"),
	translate("Configure active tunnel health monitoring with automatic recovery"))

-- Ping Monitoring Section
s = m:section(NamedSection, "health", "ping_monitor", translate("Special Ping Configuration"))
s.addremove = false
s.anonymous = true

-- Enable/Disable
o = s:option(Flag, "enabled", translate("Enable Special Ping"),
	translate("Enable active tunnel connectivity monitoring using ICMP ping"))
o.rmempty = false
o.default = "0"

-- Local IP (with auto-detection)
o = s:option(Value, "local_ip", translate("Local IP Address"),
	translate("Source IP address for ping packets (leave empty for auto-detection from Local Subnet)"))
o.datatype = "ipaddr"
o.placeholder = "Auto-detect"
o.rmempty = true
o:depends("enabled", "1")

-- Get auto-detected value for display
local local_subnet = uci:get("ipsec", "main", "local_subnet")
if local_subnet and local_subnet ~= "" then
	local auto_ip = local_subnet:match("^([^/]+)"):gsub("%.0$", ".1")
	o.description = translate("Auto-detected: ") .. auto_ip
end

-- Remote Primary IP
o = s:option(Value, "remote_primary", translate("Remote Primary IP"),
	translate("Primary target IP address in remote network for connectivity testing"))
o.datatype = "ipaddr"
o.placeholder = "10.0.0.1"
o.rmempty = false
o:depends("enabled", "1")

function o.validate(self, value, section)
	if not value or value == "" then
		return nil, translate("Primary IP is required when Special Ping is enabled")
	end
	if not helper.validate_ip(value) then
		return nil, translate("Invalid IP address format")
	end
	return value
end

-- Remote Secondary IP (optional)
o = s:option(Value, "remote_secondary", translate("Remote Secondary IP"),
	translate("Secondary/backup target IP (optional) - used if primary fails"))
o.datatype = "ipaddr"
o.placeholder = "10.0.0.1"
o.rmempty = true
o:depends("enabled", "1")

-- Initial Wait
o = s:option(Value, "initial_wait", translate("Initial Wait (seconds)"),
	translate("Time to wait after system boot before starting first ping test"))
o.datatype = "range(1,300)"
o.default = "10"
o.placeholder = "10"
o:depends("enabled", "1")

-- Normal Interval
o = s:option(Value, "interval", translate("Ping Interval (seconds)"),
	translate("Time between successful ping tests (1800 = 30 minutes)"))
o.datatype = "range(60,86400)"
o.default = "1800"
o.placeholder = "1800"
o:depends("enabled", "1")

-- Retry Interval
o = s:option(Value, "retry_interval", translate("Retry Interval (seconds)"),
	translate("Time to wait before retrying after a failed ping"))
o.datatype = "range(1,60)"
o.default = "5"
o.placeholder = "5"
o:depends("enabled", "1")

-- Timeout
o = s:option(Value, "timeout", translate("Ping Timeout (seconds)"),
	translate("Maximum time to wait for ping response"))
o.datatype = "range(1,30)"
o.default = "3"
o.placeholder = "3"
o:depends("enabled", "1")

-- Max Tries
o = s:option(Value, "max_tries", translate("Max Consecutive Failures"),
	translate("Number of consecutive ping failures before triggering IPsec restart"))
o.datatype = "range(1,10)"
o.default = "3"
o.placeholder = "3"
o:depends("enabled", "1")

-- Callback to restart daemon when config changes
function m.on_commit(self)
	local enabled = uci:get("ipsec", "health", "enabled")

	if enabled == "1" then
		-- Restart the monitoring daemon
		sys.call("/etc/init.d/ipsec-ping-monitor restart 2>/dev/null &")
		m.message = translate("Ping monitoring configuration saved and daemon restarted")
	else
		-- Stop the daemon
		sys.call("/etc/init.d/ipsec-ping-monitor stop 2>/dev/null &")
		m.message = translate("Ping monitoring disabled and daemon stopped")
	end
end

return m
