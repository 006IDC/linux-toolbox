#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Derived from Netflixxp/jcnf-box jcnfbox.sh bbr(), author jcnf.
# 006IDC changes: backups, safe failure recovery, exclusive config and restore.
set -euo pipefail
[[ $(uname -s) == Linux && $EUID == 0 ]] || { echo '需要 Linux root。' >&2; exit 1; }
CONF=/etc/sysctl.d/90-006idc-bbr.conf
STATE=/var/lib/006idc-linux-toolbox/bbr
MODE=${1:---enable}
[[ $# -le 1 && ( $MODE == --enable || $MODE == --restore ) ]] || { echo '用法：bbr.sh [--enable|--restore]' >&2; exit 2; }
umask 077
for tool in flock sysctl grep; do command -v "$tool" >/dev/null || { echo "缺少 $tool。" >&2; exit 1; }; done
[[ ! -L /var/lib/006idc-linux-toolbox && ! -L $STATE && ! -L $CONF ]] || { echo '配置/状态路径是符号链接，停止。' >&2; exit 1; }
mkdir -p "$STATE"
chmod 700 "$STATE"
exec 9>"$STATE/lock"
flock -n 9 || { echo '另一个 BBR 操作正在运行。' >&2; exit 1; }

restore_values() {
    local qdisc algo
    [[ -f $STATE/original ]] || { echo '没有本工具箱的 BBR 恢复点。' >&2; return 1; }
    read -r qdisc algo < "$STATE/original"
    [[ $qdisc =~ ^[a-zA-Z0-9_]+$ && $algo =~ ^[a-zA-Z0-9_]+$ ]] || return 1
    sysctl -w "net.core.default_qdisc=$qdisc" "net.ipv4.tcp_congestion_control=$algo"
}

if [[ $MODE == --restore ]]; then
    [[ -f $CONF ]] || { echo '没有本工具箱的 BBR 配置。' >&2; exit 1; }
    grep -qx '# Managed by 006IDC Linux Toolbox' "$CONF" || { echo '配置归属不匹配。' >&2; exit 1; }
    restore_values
    rm -- "$CONF"
    rm -- "$STATE/original"
    echo '已恢复启用前的运行参数并移除本工具箱配置。'
    exit 0
fi

command -v modprobe >/dev/null && modprobe tcp_bbr 2>/dev/null || true
grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control || { echo '当前内核不支持 BBR，未更换内核。' >&2; exit 1; }
if [[ -e $CONF ]]; then
    grep -qx '# Managed by 006IDC Linux Toolbox' "$CONF" && [[ -f $STATE/original ]] || { echo '已有配置归属未知，停止。' >&2; exit 1; }
else
    [[ ! -e $STATE/original ]] || { echo '检测到未完成恢复，请检查已有 BBR 状态。' >&2; exit 1; }
    old_qdisc=$(sysctl -n net.core.default_qdisc)
    old_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    [[ $old_qdisc =~ ^[a-zA-Z0-9_]+$ && $old_algo =~ ^[a-zA-Z0-9_]+$ ]] || { echo '无法读取有效的原始参数。' >&2; exit 1; }
    printf '%s %s\n' "$old_qdisc" "$old_algo" > "$STATE/original"
    mkdir -p /etc/sysctl.d
    printf '%s\n' '# Managed by 006IDC Linux Toolbox' 'net.core.default_qdisc = fq' 'net.ipv4.tcp_congestion_control = bbr' > "$CONF"
fi
if ! sysctl -p "$CONF"; then
    echo '应用失败，尝试恢复原参数。' >&2
    if restore_values; then rm -- "$CONF" "$STATE/original"; else echo '恢复未完成，保留状态供处理。' >&2; fi
    exit 1
fi
echo 'BBR 已启用；已有连接不保证立即使用新算法。'
