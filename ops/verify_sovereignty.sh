#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '[CONFIRMED] nftables ruleset'
sudo nft list ruleset

printf '%s\n' '[CONFIRMED] listening/connectivity snapshot'
sudo ss -tunp

printf '%s\n' '[VERIFICATION] egress denial probe'
if command -v curl >/dev/null 2>&1; then
  if curl --connect-timeout 3 --max-time 5 https://example.com >/tmp/khz-egress.out 2>/tmp/khz-egress.err; then
    printf '%s\n' 'EGRESS_RESULT=UNVERIFIED_ASSERTION: outbound HTTPS succeeded on this host'
    exit 2
  else
    printf '%s\n' 'EGRESS_RESULT=ENFORCED_OR_UNAVAILABLE: outbound HTTPS probe failed'
  fi
fi

printf '%s\n' '[VERIFICATION] systemd sandbox properties'
systemctl show khz-sovereign-graph.service \
  -p User -p NoNewPrivileges -p PrivateTmp -p PrivateDevices \
  -p ProtectSystem -p ProtectHome -p RestrictNamespaces \
  -p RestrictAddressFamilies

printf '%s\n' '[VERIFICATION] optional eBPF TCP connect probe'
if command -v bpftrace >/dev/null 2>&1; then
  timeout 5s sudo bpftrace -e 'tracepoint:syscalls:sys_enter_connect { printf("pid=%d comm=%s fd=%d\\n", pid, comm, args->fd); }' || true
else
  printf '%s\n' 'EBPF_RESULT=UNVERIFIED ASSERTION: bpftrace not installed'
fi
