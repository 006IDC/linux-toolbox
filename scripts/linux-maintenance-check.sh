#!/usr/bin/env bash
# Only for a clean, disposable GitHub-hosted Linux runner. Never a business host.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $EUID == 0 ]] || { echo '仅允许在临时 GitHub runner 中以 root 验证。' >&2; exit 1; }
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ ! -e /var/lib/006idc-linux-toolbox && ! -L /var/lib/006idc-linux-toolbox && ! -e /etc/sysctl.d/90-006idc-bbr.conf ]] || { echo '环境不干净，拒绝修改。' >&2; exit 1; }
before_fstab=$(sha256sum /etc/fstab | awk '{print $1}')
printf '1\n64\n' | bash "$ROOT/toolbox.sh" run swap --yes
grep -qx '/var/lib/006idc-linux-toolbox/swapfile none swap sw 0 0 # 006IDC-swap' /etc/fstab
awk 'NR>1 {print $1}' /proc/swaps | grep -qx /var/lib/006idc-linux-toolbox/swapfile
# Simulate fstab edit failure after swapoff; the active swap must be restored.
fake_bin=$(mktemp -d /tmp/006box-failure.XXXXXXXX)
printf '#!/bin/sh\nexit 73\n' > "$fake_bin/sed"
chmod 700 "$fake_bin/sed"
if printf '2\n' | PATH="$fake_bin:$PATH" bash "$ROOT/toolbox.sh" run swap --yes; then echo '错误：未传播 fstab 编辑失败。'; exit 1; fi
awk 'NR>1 {print $1}' /proc/swaps | grep -qx /var/lib/006idc-linux-toolbox/swapfile
grep -qx '/var/lib/006idc-linux-toolbox/swapfile none swap sw 0 0 # 006IDC-swap' /etc/fstab
rm -rf -- "$fake_bin"
printf '2\n' | bash "$ROOT/toolbox.sh" run swap --yes
[[ ! -e /var/lib/006idc-linux-toolbox/swapfile ]]
[[ $(sha256sum /etc/fstab | awk '{print $1}') == "$before_fstab" ]]

# Unknown swap files must survive the remove option unchanged.
printf 'synthetic-unowned-file\n' > /var/lib/006idc-linux-toolbox/swapfile
if printf '2\n' | bash "$ROOT/toolbox.sh" run swap --yes; then echo '错误：接受了未知文件。'; exit 1; fi
grep -qx 'synthetic-unowned-file' /var/lib/006idc-linux-toolbox/swapfile
rm /var/lib/006idc-linux-toolbox/swapfile

# Simulate creation failure before swapon; no file or fstab entry may remain.
fake_bin=$(mktemp -d /tmp/006box-failure.XXXXXXXX)
printf '#!/bin/sh\nexit 74\n' > "$fake_bin/mkswap"
chmod 700 "$fake_bin/mkswap"
if printf '1\n64\n' | PATH="$fake_bin:$PATH" bash "$ROOT/toolbox.sh" run swap --yes; then echo '错误：未传播创建失败。'; exit 1; fi
[[ ! -e /var/lib/006idc-linux-toolbox/swapfile && ! -e /var/lib/006idc-linux-toolbox/swap/identity ]]
[[ $(sha256sum /etc/fstab | awk '{print $1}') == "$before_fstab" ]]
rm -rf -- "$fake_bin"

before_qdisc=$(sysctl -n net.core.default_qdisc)
before_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
bash "$ROOT/toolbox.sh" run bbr --yes
[[ $(sysctl -n net.ipv4.tcp_congestion_control) == bbr ]]
bash "$ROOT/toolbox.sh" run bbr --yes -- --restore
[[ $(sysctl -n net.core.default_qdisc) == "$before_qdisc" ]]
[[ $(sysctl -n net.ipv4.tcp_congestion_control) == "$before_algo" ]]
[[ ! -e /etc/sysctl.d/90-006idc-bbr.conf ]]
echo 'PASS: actual SWAP create/remove/ownership and BBR enable/restore in disposable runner'
