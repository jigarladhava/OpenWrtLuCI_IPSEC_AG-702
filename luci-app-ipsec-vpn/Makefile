include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Support for IPsec Site-to-Site VPN
LUCI_DEPENDS:=+libreswan +ip-full +iptables +kmod-ipt-ipsec +kmod-ipsec +kmod-ipsec4 +kmod-ipsec6 \
	+kmod-crypto-cbc +kmod-crypto-hmac +kmod-crypto-sha256

PKG_NAME:=luci-app-ipsec-vpn
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Your Name <your.email@example.com>
PKG_LICENSE:=MIT

include $(TOPDIR)/feeds/luci/luci.mk

# vim: set tabstop=4 shiftwidth=4 noexpandtab:
