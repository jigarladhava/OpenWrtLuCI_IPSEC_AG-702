--[[
IPsec VPN Firewall Management Library
Handles firewall rules, NAT exceptions, and zone configuration
]]--

local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"

local firewall = {}

-- Remove old IPsec firewall rules
function firewall.remove_old_rules()
	local rules_to_delete = {}

	-- Find all IPsec-related rules
	uci:foreach("firewall", "rule", function(s)
		if s.name and (s.name:match("^Allow%-IPSec") or s.name:match("^Allow%-VPN")) then
			table.insert(rules_to_delete, s[".name"])
		end
	end)

	-- Delete rules
	for _, rule in ipairs(rules_to_delete) do
		uci:delete("firewall", rule)
	end

	uci:commit("firewall")
	return true
end

-- Add IPsec firewall rules
function firewall.add_ipsec_rules(remote_subnet)
	if not remote_subnet or remote_subnet == "" then
		return false, "Remote subnet is required"
	end

	-- IPSec protocol rules
	local rules = {
		{
			name = "Allow-IPSec-IKE",
			src = "wan",
			proto = "udp",
			dest_port = "500",
			target = "ACCEPT",
			family = "ipv4"
		},
		{
			name = "Allow-IPSec-NAT-T",
			src = "wan",
			proto = "udp",
			dest_port = "4500",
			target = "ACCEPT",
			family = "ipv4"
		},
		{
			name = "Allow-IPSec-ESP",
			src = "wan",
			proto = "esp",
			target = "ACCEPT",
			family = "ipv4"
		},
		{
			name = "Allow-IPSec-AH",
			src = "wan",
			proto = "ah",
			target = "ACCEPT",
			family = "ipv4"
		},
		{
			name = "Allow-VPN-Output",
			src = "*",
			dest = "*",
			dest_ip = remote_subnet,
			target = "ACCEPT",
			proto = "all"
		},
		{
			name = "Allow-VPN-Forward",
			src = "lan",
			dest = "*",
			dest_ip = remote_subnet,
			target = "ACCEPT",
			proto = "all"
		},
		{
			name = "Allow-VPN-Input",
			src = "*",
			dest = "*",
			src_ip = remote_subnet,
			target = "ACCEPT",
			proto = "all"
		}
	}

	-- Add each rule
	for _, rule in ipairs(rules) do
		local section = uci:add("firewall", "rule")
		for k, v in pairs(rule) do
			uci:set("firewall", section, k, v)
		end
	end

	uci:commit("firewall")
	return true
end

-- Disable all redirect rules
function firewall.disable_redirects()
	uci:foreach("firewall", "redirect", function(s)
		if s[".name"] then
			uci:set("firewall", s[".name"], "enabled", "0")
		end
	end)

	uci:commit("firewall")
	return true
end

-- Create NAT exception script
function firewall.create_nat_exception(local_subnet, remote_subnet)
	if not local_subnet or not remote_subnet then
		return false, "Both local and remote subnets are required"
	end

	local script = string.format([[#!/bin/sh
# IPsec NAT exception - Don't NAT VPN traffic
# This rule must be at position 0 to bypass other NAT rules

# Delete if exists (for idempotency)
nft delete rule inet fw4 srcnat ip saddr %s ip daddr %s counter accept 2>/dev/null

# Insert at the beginning (position 0) - CRITICAL!
nft insert rule inet fw4 srcnat position 0 ip saddr %s ip daddr %s counter accept 2>/dev/null

logger -t firewall "IPsec NAT exception added at position 0"
]], local_subnet, remote_subnet, local_subnet, remote_subnet)

	local f = io.open("/etc/firewall.ipsec", "w")
	if not f then
		return false, "Cannot write to /etc/firewall.ipsec"
	end

	f:write(script)
	f:close()

	sys.call("chmod +x /etc/firewall.ipsec")

	return true
end

-- Add firewall include for NAT exception
function firewall.add_firewall_include()
	local found = false

	-- Check if include already exists
	uci:foreach("firewall", "include", function(s)
		if s.path == "/etc/firewall.ipsec" then
			found = true
			return false
		end
	end)

	if not found then
		local section = uci:add("firewall", "include")
		uci:set("firewall", section, "path", "/etc/firewall.ipsec")
		uci:set("firewall", section, "fw4_compatible", "1")
		uci:commit("firewall")
	end

	return true
end

-- Configure firewall zones
function firewall.configure_zones()
	local changes = false

	-- Find and configure zones
	uci:foreach("firewall", "zone", function(s)
		local zone_name = s.name

		if zone_name == "LTE" then
			if s.masq ~= "0" then
				uci:set("firewall", s[".name"], "masq", "0")
				changes = true
			end
		elseif zone_name == "wan" then
			if s.masq ~= "1" then
				uci:set("firewall", s[".name"], "masq", "1")
				changes = true
			end
		end
	end)

	if changes then
		uci:commit("firewall")
	end

	return true
end

-- Apply all firewall configurations
function firewall.apply_firewall(local_subnet, remote_subnet)
	local ok, err

	-- Remove old rules
	firewall.remove_old_rules()

	-- Add new IPsec rules
	ok, err = firewall.add_ipsec_rules(remote_subnet)
	if not ok then return false, err end

	-- Disable redirects
	firewall.disable_redirects()

	-- Create NAT exception
	ok, err = firewall.create_nat_exception(local_subnet, remote_subnet)
	if not ok then return false, err end

	-- Add firewall include
	firewall.add_firewall_include()

	-- Configure zones
	firewall.configure_zones()

	-- Restart firewall
	sys.call("/etc/init.d/firewall restart")

	return true
end

-- Verify NAT exception is applied
function firewall.verify_nat_exception(remote_subnet)
	if not remote_subnet then
		return false
	end

	local result = sys.exec("nft list chain inet fw4 srcnat 2>/dev/null")
	return result:match(remote_subnet) ~= nil
end

return firewall
