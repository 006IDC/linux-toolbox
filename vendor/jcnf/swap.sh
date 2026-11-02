#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Based on Netflixxp/jcnf-box sh/swap.sh, author jcnf.
# Modified by 006IDC (2026): Chinese prompts, ownership, lock, capacity checks,
# fstab backup and failure rollback. Never remove an unowned /var/lib/006idc-linux-toolbox/swapfile.
set -euo pipefail
[[ $(uname -s) == Linux && $EUID == 0 ]] || { echo '需要 Linux root。' >&2; exit 1; }
[[ ! -d /proc/vz ]] || { echo '不支持 OpenVZ。'; exit 1; }
for tool in flock dd mkswap swapon swapoff stat df awk; do command -v "$tool" >/dev/null || { echo "缺少 $tool。" >&2; exit 1; }; done
STATE=/var/lib/006idc-linux-toolbox/swap
[[ ! -L /var/lib/006idc-linux-toolbox && ! -L $STATE && ! -L /etc/fstab ]] || { echo '状态或 fstab 路径异常。' >&2; exit 1; }
umask 077
mkdir -p "$STATE"
chmod 700 "$STATE"
exec 9>"$STATE/lock"
flock -n 9 || { echo '另一个 SWAP 操作正在运行。' >&2; exit 1; }
read -r -p '1：创建本工具箱 /var/lib/006idc-linux-toolbox/swapfile；2：移除本工具箱 /var/lib/006idc-linux-toolbox/swapfile：' action
case $action in
    1)
        [[ ! -e /var/lib/006idc-linux-toolbox/swapfile && ! -L /var/lib/006idc-linux-toolbox/swapfile && ! -e $STATE/identity ]] || { echo '已有 swap 文件或未完成状态，停止。'; exit 1; }
        ! grep -qE '^[[:space:]]*/var/lib/006idc-linux-toolbox/swapfile[[:space:]]' /etc/fstab || exit 1
        read -r -p '大小（MiB，例如 1024）：' size
        [[ $size =~ ^[1-9][0-9]{0,6}$ ]] || { echo '大小无效。'; exit 1; }
        free_kib=$(df -Pk "$STATE" | awk 'END {print $4}')
        [[ $free_kib =~ ^[0-9]+$ ]] && (( size * 1024 + 524288 < free_kib )) || { echo '空间不足；创建后至少保留 512 MiB。'; exit 1; }
        cp -p /etc/fstab "$STATE/fstab.before-add"
        (set -o noclobber; : > /var/lib/006idc-linux-toolbox/swapfile) || exit 1
        rollback() {
            local status=$?
            trap - EXIT
            if awk 'NR>1 {print $1}' /proc/swaps | grep -qx /var/lib/006idc-linux-toolbox/swapfile; then
                swapoff /var/lib/006idc-linux-toolbox/swapfile || { echo '停用失败，保留文件和状态，请人工检查。' >&2; exit "$status"; }
            fi
            # Remove our exact line only; do not overwrite concurrent fstab edits.
            sed -i '\|^/var/lib/006idc-linux-toolbox/swapfile none swap sw 0 0 # 006IDC-swap$|d' /etc/fstab || { echo 'fstab 恢复失败，保留文件和状态。' >&2; exit "$status"; }
            rm -f -- /var/lib/006idc-linux-toolbox/swapfile "$STATE/identity"
            exit "$status"
        }
        trap rollback EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        stat -c '%d:%i' /var/lib/006idc-linux-toolbox/swapfile > "$STATE/identity"
        dd if=/dev/zero of=/var/lib/006idc-linux-toolbox/swapfile bs=1M count="$size" status=progress
        chmod 600 /var/lib/006idc-linux-toolbox/swapfile
        mkswap /var/lib/006idc-linux-toolbox/swapfile
        swapon /var/lib/006idc-linux-toolbox/swapfile
        printf '%s\n' '/var/lib/006idc-linux-toolbox/swapfile none swap sw 0 0 # 006IDC-swap' >> /etc/fstab
        trap - EXIT INT TERM
        echo '已创建；fstab 前像保存在本工具箱状态目录。'
        ;;
    2)
        [[ -f /var/lib/006idc-linux-toolbox/swapfile && ! -L /var/lib/006idc-linux-toolbox/swapfile && -f $STATE/identity && ! -L $STATE/identity ]] || { echo '未找到本工具箱管理的 swap 文件，拒绝移除。'; exit 1; }
        [[ $(stat -c '%d:%i' /var/lib/006idc-linux-toolbox/swapfile) == "$(cat "$STATE/identity")" ]] || { echo '文件身份已改变，拒绝移除。'; exit 1; }
        # Reject unrelated references before disabling swap or changing fstab.
        if grep -E '^[[:space:]]*/var/lib/006idc-linux-toolbox/swapfile[[:space:]]' /etc/fstab | grep -vx '/var/lib/006idc-linux-toolbox/swapfile none swap sw 0 0 # 006IDC-swap' >/dev/null; then
            echo '存在其他 fstab 引用，保留文件与运行状态，请检查。' >&2; exit 1
        fi
        cp -p /etc/fstab "$STATE/fstab.before-remove"
        was_active=no
        config_changed=no
        rollback_remove() {
            local status=$?
            trap - EXIT
            if [[ $config_changed == yes ]] && ! grep -qx '/var/lib/006idc-linux-toolbox/swapfile none swap sw 0 0 # 006IDC-swap' /etc/fstab; then
                printf '%s\n' '/var/lib/006idc-linux-toolbox/swapfile none swap sw 0 0 # 006IDC-swap' >> /etc/fstab || echo '恢复 fstab 失败，保留前像与状态。' >&2
            fi
            if [[ $was_active == yes ]]; then
                swapon /var/lib/006idc-linux-toolbox/swapfile || echo '重新启用失败，保留文件和状态，请人工检查。' >&2
            fi
            exit "$status"
        }
        trap rollback_remove EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        if awk 'NR>1 {print $1}' /proc/swaps | grep -qx /var/lib/006idc-linux-toolbox/swapfile; then
            was_active=yes
            swapoff /var/lib/006idc-linux-toolbox/swapfile
        fi
        config_changed=yes
        sed -i '\|^/var/lib/006idc-linux-toolbox/swapfile none swap sw 0 0 # 006IDC-swap$|d' /etc/fstab
        # A separate user-added fstab reference must not be left pointing at a deleted file.
        ! grep -qE '^[[:space:]]*/var/lib/006idc-linux-toolbox/swapfile[[:space:]]' /etc/fstab || { echo '存在其他 fstab 引用，保留文件，请检查。' >&2; exit 1; }
        rm -- /var/lib/006idc-linux-toolbox/swapfile
        trap - EXIT INT TERM
        rm -- "$STATE/identity"
        echo '已移除本工具箱 swap；其他 swap 未改动。'
        ;;
    *) echo '选项无效。'; exit 1 ;;
esac
cat /proc/swaps
