#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 006IDC contributors.
# Bootstrap for the community-tool integration; original notices are in the bundle.

set -euo pipefail

main() (
    local version=0.1.0
    local digest=1179fffeea6190922a0047acb59ce18e3480eaf04c56a417fbccd51e57f10a79
    local url="https://github.com/006IDC/linux-toolbox/releases/download/v${version}/006idc-linux-toolbox-${version}.tar.gz"
    local work actual command_name

    [[ $(uname -s) == Linux ]] || { echo '此启动入口需要 Linux。' >&2; return 1; }
    for command_name in curl tar gzip; do
        command -v "$command_name" >/dev/null 2>&1 || { printf '缺少 %s，请安装后重试。\n' "$command_name" >&2; return 1; }
    done
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        echo '缺少 SHA256 工具（sha256sum 或 shasum）。' >&2
        return 1
    fi

    # Independent per invocation; do not trust a caller-supplied root TMPDIR/cache.
    work=$(umask 077; mktemp -d /tmp/006box-start.XXXXXXXX) || return
    trap 'rm -rf -- "$work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '006IDC Linux 工具箱：获取固定发行版 %s…\n' "$version" >&2
    if ! curl --proto '=https' --proto-redir '=https' -fSL --connect-timeout 15 --max-time 180 --retry 2 "$url" -o "$work/toolbox.tar.gz"; then
        echo '发行包下载失败，未启动。' >&2
        return 1
    fi
    [[ -s $work/toolbox.tar.gz ]] || { echo '发行包为空，未启动。' >&2; return 1; }
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$work/toolbox.tar.gz" | awk '{print $1}')
    else
        actual=$(shasum -a 256 "$work/toolbox.tar.gz" | awk '{print $1}')
    fi
    [[ $actual == "$digest" ]] || { echo '发行包 SHA256 不匹配，未解压、未启动。' >&2; return 1; }
    # This exact release archive contains regular source files and directories only.
    tar -xzf "$work/toolbox.tar.gz" -C "$work"
    local entry="$work/006idc-linux-toolbox-${version}/toolbox.sh"
    [[ -f $entry && ! -L $entry ]] || { echo '发行包缺少正确的工具箱入口。' >&2; return 1; }
    bash -n "$entry"
    bash "$entry" "$@"
)

# The enclosing parse completes before main is called; stdin remains the terminal
# when invoked with bash <(curl ...), allowing the interactive menu to read input.
main "$@"
