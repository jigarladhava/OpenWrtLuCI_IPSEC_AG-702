--[[
LuCI - IPsec VPN Configuration Page
]]--

local helper = require "ipsec.helper"
local firewall = require "ipsec.firewall"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

-- Check for missing dependencies
local missing_pkgs = helper.get_missing()
local deps_ok = (#missing_pkgs == 0)

m = Map("ipsec", translate("IPsec VPN Configuration"),
	translate("Configure IPsec site-to-site VPN connection settings"))

-- Show dependency warning if packages are missing (using SimpleSection with rawhtml)
if not deps_ok then
	local install_cmd = "opkg update && opkg install " .. table.concat(missing_pkgs, " ")
	local install_url = luci.dispatcher.build_url("admin/vpn/ipsec/install_deps")

	local warn = m:section(SimpleSection)
	warn.template = "cbi/nullsection"
	warn.rawhtml = true

	function warn.render(self)
		luci.template.render_string([[
			<div class="alert-message warning" style="padding:15px;margin-bottom:20px;border-left:4px solid #f0ad4e;background:#fcf8e3;">
				<h4 style="margin:0 0 10px 0;color:#8a6d3b;">⚠️ <%:Missing Dependencies%></h4>
				<p style="margin:5px 0;"><%:The following packages are required but not installed%>:</p>
				<p><strong>]] .. table.concat(missing_pkgs, ", ") .. [[</strong></p>
				<p style="margin:10px 0 5px 0;"><%:Run this command via SSH to install%>:</p>
				<pre style="background:#f5f5f5;padding:10px;margin:10px 0;border-radius:4px;overflow-x:auto;border:1px solid #ddd;">]] .. install_cmd .. [[</pre>
				<p style="margin:10px 0 5px 0;"><%:Or click the button to install automatically%>:</p>
				<button type="button" class="cbi-button cbi-button-apply" id="install-deps-btn"
					onclick="installDeps()" style="margin-top:5px;">
					<%:Install Missing Packages%>
				</button>
				<span id="install-status" style="margin-left:10px;display:none;">
					<%:Installing, please wait...%>
				</span>
				<script type="text/javascript">
				function installDeps() {
					if (!confirm('Install missing packages now? This requires network access.')) return;
					var btn = document.getElementById('install-deps-btn');
					var status = document.getElementById('install-status');
					btn.disabled = true;
					status.style.display = 'inline';
					fetch(']] .. install_url .. [[')
						.then(function(r) { return r.json(); })
						.then(function(d) {
							alert(d.message);
							if (d.success) location.reload();
							else { btn.disabled = false; status.style.display = 'none'; }
						})
						.catch(function(e) {
							alert('Error: ' + e);
							btn.disabled = false;
							status.style.display = 'none';
						});
				}
				</script>
			</div>
		]])
	end
end

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

				m.message = translate("Configuration applied successfully. IPsec files generated and firewall configured.")
			else
				m.message = translate("IPsec configuration generated but firewall configuration failed: ") .. (fw_err or "unknown error")
			end
		else
			m.message = translate("Failed to generate IPsec configuration: ") .. (err or "unknown error")
		end
	end
end

-- Main VPN Configuration Section
s = m:section(NamedSection, "main", "vpn", translate("Basic Settings"))
s.addremove = false

-- Enable/Disable VPN
o = s:option(Flag, "enabled", translate("Enable VPN"),
	translate("Enable or disable the IPsec VPN connection"))
o.rmempty = false
o.default = "0"

-- Connection Name
o = s:option(Value, "name", translate("Connection Name"),
	translate("Name for this VPN connection"))
o.default = "site-to-site"
o.placeholder = "site-to-site"

function o.validate(self, value, section)
	if not value or value == "" then
		return nil, translate("Connection name is required")
	end
	-- disallow whitespace (spaces, tabs)
	if value:match("%s") then
		return nil, translate("Connection name must not contain spaces")
	end
	-- Allow only letters, digits, hyphen and underscore for safety
	if not value:match("^[%w%-]+$") then
		return nil, translate("Connection name may only contain letters, numbers, hyphen and underscore")
	end
	return value
end

-- Remote Gateway IP
o = s:option(Value, "remote_ip", translate("Remote Gateway IP"),
	translate("IP address of the remote VPN gateway"))
o.datatype = "ipaddr"
o.placeholder = "Your remote gateway IP"--117.10.10.17
o.rmempty = false

function o.validate(self, value, section)
	if not value or value == "" then
		return nil, translate("Remote gateway IP is required")
	end
	if not helper.validate_ip(value) then
		return nil, translate("Invalid IP address format")
	end
	return value
end

-- Remote Subnet
o = s:option(Value, "remote_subnet", translate("Remote Subnet"),
	translate("Remote network subnet in CIDR notation (e.g., 10.0.0.0/24)"))
o.datatype = "cidr4"
o.placeholder = "Remote Subnet(e.g., 10.0.0.0/24)"--10.0.0.0/24
o.rmempty = false

function o.validate(self, value, section)
	if not value or value == "" then
		return nil, translate("Remote subnet is required")
	end
	if not helper.validate_cidr(value) then
		return nil, translate("Invalid CIDR notation")
	end
	return value
end

-- Local Subnet
o = s:option(Value, "local_subnet", translate("Local Subnet"),
	translate("Local network subnet in CIDR notation (e.g., 192.168.1.0/24)"))
o.datatype = "cidr4"
o.placeholder = "Local Subnet (e.g., 192.168.1.0/24)"--192.168.1.0/24
--o.default = "192.168.1.0/24"
o.rmempty = false

function o.validate(self, value, section)
	if not value or value == "" then
		return nil, translate("Local subnet is required")
	end
	if not helper.validate_cidr(value) then
		return nil, translate("Invalid CIDR notation")
	end
	return value
end

-- Pre-Shared Key
o = s:option(Value, "psk", translate("Pre-Shared Key (PSK)"),
	translate("Pre-shared key for authentication (minimum 8 characters, 16+ recommended for SHA2-256)"))
o.password = true
o.placeholder = "Enter a strong pre-shared key"
o.rmempty = false

function o.validate(self, value, section)
	if not value or value == "" then
		return nil, translate("Pre-shared key is required")
	end
	if #value < 8 then
		return nil, translate("PSK must be at least 8 characters")
	end
	if #value < 16 then
		-- Warning but allow
		m.message = translate("Warning: PSK shorter than 16 characters is not recommended for SHA2-256")
	end
	return value
end

-- Auto-start on boot
o = s:option(Flag, "auto_start", translate("Auto-start on Boot"),
	translate("Automatically start the VPN connection when the router boots"))
o.rmempty = false
o.default = "1"

return m
