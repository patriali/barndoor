#!/bin/bash
# Barn Door Protocol - Emergency network isolation for Linux OS
# Supports most distros (Debian/Ubuntu, Fedora/RHEL, Arch, etc.)
# Run as root: sudo ./barndoor.sh
# Isolates machine: drops all external traffic, keeps only loopback.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root."
  exit 1
fi

echo "Activating Barn Door Protocol..."

# Stop higher-level firewall managers first
systemctl stop firewalld 2>/dev/null || true
systemctl stop ufw 2>/dev/null || true
ufw disable 2>/dev/null || true

# Prefer nftables (modern standard, IPv4+IPv6)
if command -v nft >/dev/null 2>&1; then
  echo "Applying nftables isolation..."
  nft flush ruleset
  nft -f - <<EOF
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority filter; policy drop;
    iif lo accept
  }
  chain forward {
    type filter hook forward priority filter; policy drop;
  }
  chain output {
    type filter hook output priority filter; policy drop;
    oif lo accept
  }
}
EOF
elif command -v iptables >/dev/null 2>&1; then
  echo "Falling back to iptables..."
  iptables -F; iptables -X; iptables -t nat -F; iptables -t nat -X; iptables -t mangle -F; iptables -t mangle -X || true
  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT DROP
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A OUTPUT -o lo -j ACCEPT
  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -F; ip6tables -X || true
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
  fi
else
  echo "Warning: No nftables or iptables found. Proceeding with interface/service isolation only."
fi

# Bring down all non-loopback interfaces
echo "Disabling network interfaces..."
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$'); do
  ip link set "$iface" down 2>/dev/null || true
done

# Stop networking and remote services
echo "Stopping network services..."
systemctl stop NetworkManager 2>/dev/null || true
systemctl stop systemd-networkd 2>/dev/null || true
systemctl stop networking 2>/dev/null || true
systemctl stop sshd 2>/dev/null || true
systemctl stop ssh 2>/dev/null || true
systemctl stop vsftpd 2>/dev/null || true
systemctl stop httpd 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

# Optional: disable IPv6 if possible
sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 2>/dev/null || true

echo ""
echo "Barn Door closed."
echo "Machine isolated from external networks. Local (loopback) access only."
echo "To reverse: reboot (recommended) or manually restore interfaces/services/firewall."
