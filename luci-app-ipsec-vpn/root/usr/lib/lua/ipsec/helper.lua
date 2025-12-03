-- Helper: dependency checks and optional opkg installer for ipsec package
-- WARNING: installing packages requires network access and may take time.
-- This module performs idempotent checks and invokes `opkg` when requested.

local sys  = require "luci.sys"
local util = require "luci.util"

local _M = {}

-- Canonical list of packages the LuCI app expects. Adjust to target image.
local REQUIRED_PACKAGES = {
  "libreswan",
  "ip-full",
  "kmod-ipsec",
  "kmod-ipsec4",
  "kmod-crypto-cbc",
  "kmod-crypto-hmac",
  "kmod-crypto-sha256",
}

-- Return table of missing packages (may be empty)
function _M.get_missing()
  local miss = {}
  for _, pkg in ipairs(REQUIRED_PACKAGES) do
    -- opkg list-installed prints a line for installed packages; check for presence
    local out = sys.exec("opkg list-installed " .. pkg .. " 2>/dev/null | head -n1") or ""
    if out == "" then
      table.insert(miss, pkg)
    end
  end
  return miss
end

-- Install a list (array) of packages. Returns boolean success, and combined logs.
-- This runs `opkg update` first, then `opkg install` for the list.
-- Note: this call may block for several seconds/minutes depending on network.
function _M.install_packages(pkgs)
  if not pkgs or #pkgs == 0 then
    return true, "no packages to install"
  end

  local pkgstr = table.concat(pkgs, " ")
  -- Run update and install, capture exit code and logs in temp files.
  local update_log = "/tmp/ipsec_opkg_update.log"
  local install_log = "/tmp/ipsec_opkg_install.log"

  -- update
  sys.call("opkg update >" .. update_log .. " 2>&1")

  -- install (idempotent for already-installed packages)
  local rc = sys.call("opkg install " .. pkgstr .. " >" .. install_log .. " 2>&1")

  local out_update = sys.exec("cat " .. update_log .. " 2>/dev/null") or ""
  local out_install = sys.exec("cat " .. install_log .. " 2>/dev/null") or ""
  local combined = out_update .. "\n" .. out_install

  return (rc == 0), combined
end

-- Convenience: ensure all REQUIRED_PACKAGES are present; install if missing when `auto_install` is true.
-- Returns: success(bool), message(string), missing_table(table)
function _M.ensure_all(auto_install)
  local miss = _M.get_missing()
  if #miss == 0 then
    return true, "all packages present", {}
  end
  if not auto_install then
    return false, "missing packages: " .. table.concat(miss, ", "), miss
  end

  local ok, logs = _M.install_packages(miss)
  if ok then
    -- re-check
    local miss2 = _M.get_missing()
    if #miss2 == 0 then
      return true, "installed missing packages", {}
    else
      return false, "installed but still missing: " .. table.concat(miss2, ", "), miss2
    end
  else
    return false, logs, miss
  end
end

-- Validate IP address
function _M.validate_ip(ip)
  if not ip then return false end
  local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
  if #chunks ~= 4 then return false end
  for _, v in pairs(chunks) do
    local num = tonumber(v)
    if not num or num < 0 or num > 255 then return false end
  end
  return true
end

-- Validate CIDR notation
function _M.validate_cidr(cidr)
  if not cidr then return false end
  local ip, prefix = cidr:match("^([^/]+)/(%d+)$")
  if not ip or not prefix then return false end
  if not _M.validate_ip(ip) then return false end
  local prefix_num = tonumber(prefix)
  if not prefix_num or prefix_num < 0 or prefix_num > 32 then return false end
  return true
end

-- Generate /etc/ipsec.conf from UCI config
function _M.generate_ipsec_conf()
  local uci = require "luci.model.uci".cursor()
  local vpn = uci:get_all("ipsec", "main")
  local ike = uci:get_all("ipsec", "phase1")
  local esp = uci:get_all("ipsec", "phase2")
  local dpd = uci:get_all("ipsec", "deadpeer")
  local opts = uci:get_all("ipsec", "settings")

  if not vpn or not vpn.remote_ip or vpn.remote_ip == "" then
    return nil, "Missing required configuration: remote_ip"
  end
  if not vpn.remote_subnet or vpn.remote_subnet == "" then
    return nil, "Missing required configuration: remote_subnet"
  end
  if not vpn.psk or vpn.psk == "" then
    return nil, "Missing required configuration: psk"
  end

  local config = string.format([[config setup
    uniqueids=%s

conn %s
    type=tunnel
    auto=%s
    authby=secret
    left=%%defaultroute
    leftsubnet=%s
    right=%s
    rightsubnet=%s
    ikev2=%s
    ike=%s-%s-%s
    ikelifetime=%ss
    rekeyfuzz=%s%%
    esp=%s-%s-%s
    salifetime=%ss
    dpddelay=%s
    dpdtimeout=%s
    dpdaction=%s
    keyingtries=%s
]],
    (opts and opts.uniqueids == "1") and "yes" or "no",
    vpn.name or "site-to-site",
    vpn.auto_start == "1" and "start" or "add",
    vpn.local_subnet,
    vpn.remote_ip,
    vpn.remote_subnet,
    (ike and ike.version == "1") and "never" or "insist",
    ike and ike.encryption or "aes256",
    ike and ike.hash or "sha2_256",
    ike and ike.dh_group or "modp2048",
    ike and ike.lifetime or "5400",
    ike and ike.rekey_fuzz or "50",
    esp and esp.encryption or "aes256",
    esp and esp.hash or "sha2_256",
    esp and esp.dh_group or "modp2048",
    esp and esp.lifetime or "3600",
    dpd and dpd.delay or "30",
    dpd and dpd.timeout or "120",
    dpd and dpd.action or "restart",
    (opts and opts.keyingtries) or "%forever"
  )
  return config
end

-- Write ipsec.conf file
function _M.write_ipsec_conf()
  local config, err = _M.generate_ipsec_conf()
  if not config then return false, err end
  local f = io.open("/etc/ipsec.conf", "w")
  if not f then return false, "Cannot write to /etc/ipsec.conf" end
  f:write(config)
  f:close()
  return true
end

-- Generate /etc/ipsec.secrets from UCI config
function _M.generate_ipsec_secrets()
  local uci = require "luci.model.uci".cursor()
  local vpn = uci:get_all("ipsec", "main")
  if not vpn or not vpn.psk or vpn.psk == "" then
    return nil, "Missing PSK"
  end
  return string.format('%%any %%any : PSK "%s"\n', vpn.psk)
end

-- Write ipsec.secrets file
function _M.write_ipsec_secrets()
  local secrets, err = _M.generate_ipsec_secrets()
  if not secrets then return false, err end
  local f = io.open("/etc/ipsec.secrets", "w")
  if not f then return false, "Cannot write to /etc/ipsec.secrets" end
  f:write(secrets)
  f:close()
  sys.call("chmod 600 /etc/ipsec.secrets")
  return true
end

-- Apply configuration (generate files and verify syntax)
function _M.apply_config()
  local ok, err
  ok, err = _M.write_ipsec_conf()
  if not ok then return false, err end
  ok, err = _M.write_ipsec_secrets()
  if not ok then return false, err end
  local result = sys.exec("ipsec addconn --checkconfig 2>&1")
  if result:match("syntax error") or result:match("ERROR") then
    return false, "Configuration syntax error: " .. result
  end
  return true
end

-- Get VPN status
function _M.get_vpn_status()
  local uci = require "luci.model.uci".cursor()
  local status = {
    running = false, connected = false, uptime = 0,
    traffic_in = 0, traffic_out = 0,
    local_ip = "", remote_ip = "", last_dpd = "",
    local_subnet = "", remote_subnet = ""
  }
  local result = sys.exec("/etc/init.d/ipsec status 2>&1")
  status.running = not result:match("not running") and not result:match("inactive")
  if not status.running then return status end
  status.local_subnet = uci:get("ipsec", "main", "local_subnet") or ""
  status.remote_subnet = uci:get("ipsec", "main", "remote_subnet") or ""
  status.remote_ip = uci:get("ipsec", "main", "remote_ip") or ""
  result = sys.exec("ipsec status 2>&1")
  status.connected = result:match("IPsec SA established") ~= nil
  result = sys.exec("ipsec whack --trafficstatus 2>&1")
  local inBytes = result:match("inBytes=(%d+)")
  local outBytes = result:match("outBytes=(%d+)")
  if inBytes then status.traffic_in = tonumber(inBytes) or 0 end
  if outBytes then status.traffic_out = tonumber(outBytes) or 0 end
  return status
end

-- Service management
function _M.start_service()   return sys.call("/etc/init.d/ipsec start") == 0 end
function _M.stop_service()    return sys.call("/etc/init.d/ipsec stop") == 0 end
function _M.restart_service() return sys.call("/etc/init.d/ipsec restart") == 0 end
function _M.enable_service()  return sys.call("/etc/init.d/ipsec enable") == 0 end
function _M.disable_service() return sys.call("/etc/init.d/ipsec disable") == 0 end

-- Format bytes to human readable
function _M.format_bytes(bytes)
  local units = {"B", "KB", "MB", "GB"}
  local size = tonumber(bytes) or 0
  local unit_index = 1
  while size >= 1024 and unit_index < #units do
    size = size / 1024
    unit_index = unit_index + 1
  end
  return string.format("%.2f %s", size, units[unit_index])
end

-- Get recent logs
function _M.get_logs(lines, filter)
  lines = lines or 100
  filter = filter or "pluto"
  local cmd = string.format("logread | grep '%s' | tail -%d", filter, lines)
  return sys.exec(cmd)
end

-- Get auto-detected local IP from local_subnet
function _M.get_auto_local_ip()
  local uci = require "luci.model.uci".cursor()
  local subnet = uci:get("ipsec", "main", "local_subnet")

  if not subnet or subnet == "" then
    return nil
  end

  -- Extract IP from CIDR (e.g., 192.168.1.0/24 -> 192.168.1.1)
  local ip = subnet:match("^([^/]+)")
  if ip then
    return ip:gsub("%.0$", ".1")
  end

  return nil
end

return _M
