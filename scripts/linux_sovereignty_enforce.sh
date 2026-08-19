#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-apply}"
STATE_DIR="/var/lib/khz-sovereign"
NFT_FILE="/etc/nftables.d/khz-sovereign.nft"
UNIT_DROPIN_DIR="/etc/systemd/system/khz-sovereign.service.d"

require_root() {
  [[ "$(id -u)" -eq 0 ]] || { echo "root required" >&2; exit 1; }
}

apply() {
  install -d -m 0750 "$STATE_DIR" "$UNIT_DROPIN_DIR" "$(dirname "$NFT_FILE")"
  cat > "$NFT_FILE" <<'NFT'
flush table inet khz_sovereign
 table inet khz_sovereign {
   chain output {
     type filter hook output priority filter; policy drop;
     oifname "lo" accept
     ip daddr 127.0.0.0/8 accept
     ip6 daddr ::1 accept
     ip daddr 169.254.169.254 drop
     ip6 daddr fe80::/10 drop
     ct state established,related accept
   }
   chain input {
     type filter hook input priority filter; policy drop;
     iifname "lo" accept
     ip saddr 127.0.0.0/8 accept
     ip6 saddr ::1 accept
     ct state established,related accept
   }
   chain forward {
     type filter hook forward priority filter; policy drop;
   }
 }
NFT
  nft -f "$NFT_FILE"
  systemctl enable nftables
  systemctl restart nftables

  cat > "$UNIT_DROPIN_DIR/10-isolation.conf" <<'UNIT'
[Service]
PrivateNetwork=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
NoNewPrivileges=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
IPAddressDeny=any
LockPersonality=true
RestrictRealtime=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
SystemCallArchitectures=native
UNIT

  systemctl daemon-reload
  printf '%s\n' applied > "$STATE_DIR/linux-enforcement.state"
}

verify() {
  nft list table inet khz_sovereign >/dev/null
  systemctl cat khz-sovereign.service >/dev/null 2>&1 || true
  [[ -f "$STATE_DIR/linux-enforcement.state" ]]
  printf '%s\n' VERIFIED
}

require_root
case "$MODE" in
  apply) apply; verify ;;
  verify) verify ;;
  remove) nft delete table inet khz_sovereign 2>/dev/null || true; rm -f "$NFT_FILE"; rm -rf "$UNIT_DROPIN_DIR"; systemctl daemon-reload; rm -f "$STATE_DIR/linux-enforcement.state" ;;
  *) echo "usage: $0 {apply|verify|remove}" >&2; exit 2 ;;
esac
