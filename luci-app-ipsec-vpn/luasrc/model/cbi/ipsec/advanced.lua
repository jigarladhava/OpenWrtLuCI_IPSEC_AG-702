--[[
LuCI - IPsec VPN Advanced Settings Page
]]--

local helper = require "ipsec.helper"
local firewall = require "ipsec.firewall"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

m = Map("ipsec", translate("IPsec VPN Advanced Settings"),
	translate("Configure Phase 1 (IKE), Phase 2 (ESP), and Dead Peer Detection settings"))

-- Callback function that runs after configuration is saved
function m.on_commit(self)
	-- Get the configuration values
	local remote_ip = uci:get("ipsec", "main", "remote_ip")
	local remote_subnet = uci:get("ipsec", "main", "remote_subnet")
	local local_subnet = uci:get("ipsec", "main", "local_subnet")
	local psk = uci:get("ipsec", "main", "psk")
	local enabled = uci:get("ipsec", "main", "enabled")

	-- Only generate config if we have the required fields
	if remote_ip and remote_subnet and local_subnet and psk and
	   remote_ip ~= "" and remote_subnet ~= "" and local_subnet ~= "" and psk ~= "" then

		-- Generate IPsec configuration files
		local ok, err = helper.apply_config()
		if ok then
			-- Apply firewall configuration
			local fw_ok, fw_err = firewall.apply_firewall(local_subnet, remote_subnet)
			if fw_ok then
				-- Add route script
				sys.call("/usr/sbin/ipsec-route.sh 2>/dev/null &")

				-- Restart IPsec service if enabled
				if enabled == "1" then
					sys.call("sleep 2 && /etc/init.d/ipsec restart 2>/dev/null &")
				end

				m.message = translate("Advanced configuration applied successfully. IPsec service will restart.")
			else
				m.message = translate("IPsec configuration generated but firewall configuration failed: ") .. (fw_err or "unknown error")
			end
		else
			m.message = translate("Failed to generate IPsec configuration: ") .. (err or "unknown error")
		end
	end
end

-- Phase 1 (IKE) Settings
s = m:section(NamedSection, "phase1", "ike", translate("Phase 1 (IKE) Settings"))
s.addremove = false

-- IKE Version
o = s:option(ListValue, "version", translate("IKE Version"),
	translate("Select IKE protocol version (IKEv1 for compatibility with older systems)"))
o:value("1", "IKEv1")
o:value("2", "IKEv2")
o.default = "1"
o.rmempty = false

-- IKE Mode (only for IKEv1)
o = s:option(ListValue, "mode", translate("Mode (IKEv1 only)"),
	translate("Main Mode is more secure, Aggressive Mode is faster"))
o:value("main", "Main Mode")
o:value("aggressive", "Aggressive Mode")
o.default = "main"
o.rmempty = false

-- Encryption Algorithm
o = s:option(ListValue, "encryption", translate("Encryption Algorithm"),
	translate("Encryption algorithm for Phase 1"))
o:value("aes128", "AES-128")
o:value("aes192", "AES-192")
o:value("aes256", "AES-256")
o:value("3des", "3DES")
o.default = "aes256"
o.rmempty = false

-- Hash Algorithm
o = s:option(ListValue, "hash", translate("Hash Algorithm"),
	translate("Hash/integrity algorithm for Phase 1"))
o:value("md5", "MD5")
o:value("sha1", "SHA1")
o:value("sha2_256", "SHA2-256")
o:value("sha2_384", "SHA2-384")
o:value("sha2_512", "SHA2-512")
o.default = "sha2_256"
o.rmempty = false

-- DH Group
o = s:option(ListValue, "dh_group", translate("DH Group"),
	translate("Diffie-Hellman group for key exchange"))
o:value("modp1024", "14 (modp1024)")
o:value("modp1536", "5 (modp1536)")
o:value("modp2048", "14 (modp2048)")
o:value("modp3072", "15 (modp3072)")
o:value("modp4096", "16 (modp4096)")
o.default = "modp2048"
o.rmempty = false

-- IKE Lifetime
o = s:option(Value, "lifetime", translate("Lifetime (seconds)"),
	translate("How long the IKE SA is valid (300-86400 seconds)"))
o.datatype = "range(300,86400)"
o.default = "5400"
o.placeholder = "5400"
o.rmempty = false

-- Rekey Fuzz
o = s:option(Value, "rekey_fuzz", translate("Rekey Fuzz (%)"),
	translate("Randomization percentage for rekeying (0-100)"))
o.datatype = "range(0,100)"
o.default = "50"
o.placeholder = "50"
o.rmempty = false

-- Phase 2 (ESP) Settings
s = m:section(NamedSection, "phase2", "esp", translate("Phase 2 (ESP) Settings"))
s.addremove = false

-- ESP Encryption
o = s:option(ListValue, "encryption", translate("Encryption Algorithm"),
	translate("Encryption algorithm for Phase 2"))
o:value("aes128", "AES-128")
o:value("aes192", "AES-192")
o:value("aes256", "AES-256")
o:value("3des", "3DES")
o.default = "aes256"
o.rmempty = false

-- ESP Hash
o = s:option(ListValue, "hash", translate("Hash Algorithm"),
	translate("Hash/integrity algorithm for Phase 2"))
o:value("md5", "MD5")
o:value("sha1", "SHA1")
o:value("sha2_256", "SHA2-256")
o:value("sha2_384", "SHA2-384")
o:value("sha2_512", "SHA2-512")
o.default = "sha2_256"
o.rmempty = false

-- PFS Group
o = s:option(ListValue, "dh_group", translate("PFS Group"),
	translate("Perfect Forward Secrecy Diffie-Hellman group"))
o:value("modp1024", "2 (modp1024)")
o:value("modp1536", "5 (modp1536)")
o:value("modp2048", "14 (modp2048)")
o:value("modp3072", "15 (modp3072)")
o:value("modp4096", "16 (modp4096)")
o.default = "modp2048"
o.rmempty = false

-- ESP Lifetime
o = s:option(Value, "lifetime", translate("Lifetime (seconds)"),
	translate("How long the IPsec SA is valid (300-86400 seconds)"))
o.datatype = "range(300,86400)"
o.default = "3600"
o.placeholder = "3600"
o.rmempty = false

-- Dead Peer Detection Settings
s = m:section(NamedSection, "deadpeer", "dpd", translate("Dead Peer Detection (DPD)"))
s.addremove = false

-- DPD Delay
o = s:option(Value, "delay", translate("DPD Delay (seconds)"),
	translate("Interval between DPD checks (10-300 seconds)"))
o.datatype = "range(10,300)"
o.default = "30"
o.placeholder = "30"
o.rmempty = false

-- DPD Timeout
o = s:option(Value, "timeout", translate("DPD Timeout (seconds)"),
	translate("Time to wait for DPD response before considering peer dead (30-600 seconds)"))
o.datatype = "range(30,600)"
o.default = "120"
o.placeholder = "120"
o.rmempty = false

-- DPD Action
o = s:option(ListValue, "action", translate("DPD Action"),
	translate("Action to take when peer is detected as dead"))
o:value("restart", "Restart - Reconnect immediately")
o:value("clear", "Clear - Remove connection")
o:value("hold", "Hold - Wait for peer")
o.default = "restart"
o.rmempty = false

-- Additional Options
s = m:section(NamedSection, "settings", "options", translate("Additional Options"))
s.addremove = false

-- Keying Tries
o = s:option(Value, "keyingtries", translate("Keying Tries"),
	translate("Number of attempts to establish connection (use 'forever' for unlimited)"))
o.default = "forever"
o.placeholder = "forever or number"
o.rmempty = false

-- Unique IDs
o = s:option(Flag, "uniqueids", translate("Unique IDs"),
	translate("Enforce unique connection IDs (recommended)"))
o.rmempty = false
o.default = "1"

-- Debug Mode
o = s:option(Flag, "debug", translate("Debug Mode"),
	translate("Enable debug logging (use for troubleshooting only)"))
o.rmempty = false
o.default = "0"

return m
