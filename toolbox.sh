#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 006IDC contributors.
# Integration launcher derived from Netflixxp/jcnf-box (Apache-2.0).
# Reworked: registry, source display, digest verification, isolation and CLI.

set -o pipefail
BOX_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
BOX_VERSION=0.1.0

fail() { printf '错误：%s\n' "$*" >&2; return 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "缺少 $1，请通过系统软件包管理器安装后重试。"; }
linux_only() { [[ $(uname -s) == Linux ]] || fail '执行工具需要 Linux；当前系统可查看菜单、来源和使用说明。'; }
architecture() {
    case $(uname -m) in
        x86_64|amd64) printf 'amd64\n' ;;
        aarch64|arm64) printf 'arm64\n' ;;
        *) printf 'unsupported\n' ;;
    esac
}

banner() {
    printf '\n006IDC Linux 工具箱  v%s\n' "$BOX_VERSION"
    printf '开源整合项目 · 基于 jcnf-box，集成 LinuxMirrors 等社区工具\n'
    printf '原作者保留署名；各组件继续采用原许可证。\n\n'
}

list_tools() {
    printf '%-14s %s\n' 'info' '系统信息（本地只读）'
    awk -F '\t' '!/^#/ && !seen[$1]++ {printf "%-14s %s\n", $1, $2}' "$BOX_DIR/tools.lock.tsv"
    printf '%-14s %s\n' 'docker-registry' '仅更换 Docker 镜像加速器（LinuxMirrors）'
    printf '%-14s %s\n' 'bbr' '启用当前内核 BBR（改编自 jcnf-box）'
}

load_tool() {
    local requested=$1 row arch
    [[ $requested =~ ^[a-z][a-z0-9-]*$ ]] || { fail '工具名称不合法。'; return 1; }
    [[ $requested == docker-registry ]] && requested=docker
    arch=$(architecture)
    row=$(awk -F '\t' -v id="$requested" -v arch="$arch" '!/^#/ && $1==id && ($4=="any" || $4==arch) {print; exit}' "$BOX_DIR/tools.lock.tsv")
    [[ -n $row ]] || { fail "未知工具或当前架构不支持：$1"; return 1; }
    IFS=$'\t' read -r TOOL_ID TOOL_TITLE TOOL_KIND TOOL_ARCH TOOL_UPSTREAM TOOL_REF TOOL_SOURCE TOOL_SHA TOOL_ENTRY TOOL_ROOT TOOL_EFFECTS <<< "$row"
    [[ $TOOL_SHA =~ ^[a-f0-9]{64}$ ]] || { fail '锁定清单中的 SHA256 不合法。'; return 1; }
    case $TOOL_KIND in
        bundled) [[ $TOOL_SOURCE == vendor/jcnf/swap.sh ]] || return 1 ;;
        bash|binary|tar-bash|zip-bin) [[ $TOOL_SOURCE == https://* ]] || return 1 ;;
        *) fail '不支持的组件类型。'; return 1 ;;
    esac
}

show_tool() {
    case $1 in
        info) printf '系统信息：只读本机发行版、CPU、内存、磁盘、服务与端口；不联网。\n'; return ;;
        bbr)
            printf 'BBR：改编自 Netflixxp/jcnf-box，Apache-2.0。\n'
            printf '来源与固定提交见 upstreams.json。\n'
            printf '检查当前内核支持后写入独立 sysctl 配置；提供恢复入口，不更换内核。\n'
            return ;;
    esac
    load_tool "$1" || return
    printf '\n工具：%s (%s)\n' "$TOOL_TITLE" "$1"
    printf '上游：%s\n' "$TOOL_UPSTREAM"
    printf '版本：%s\n' "$TOOL_REF"
    printf '入口：%s\n' "$TOOL_SOURCE"
    printf 'SHA256：%s\n' "$TOOL_SHA"
    printf '许可证：licenses/%s.txt（详见 THIRD_PARTY_NOTICES.md）\n' "$TOOL_UPSTREAM"
    printf '系统 root 权限：%s\n' "$TOOL_ROOT"
    printf '影响：%s\n' "$TOOL_EFFECTS"
    printf '该校验覆盖入口文件/发布包；上游运行后联网下载的内容不在此摘要范围内。\n'
}

confirm_run() {
    local id=$1 yes=$2 answer
    [[ $yes == yes ]] && return 0
    [[ -t 0 ]] || { fail '非交互运行必须明确添加 --yes；请先使用 show 查看来源与影响。'; return 1; }
    printf '\n输入 RUN %s 确认运行，其他输入取消：' "$id"
    IFS= read -r answer || return 1
    [[ $answer == "RUN $id" ]] || { printf '已取消。\n'; return 1; }
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        fail '缺少 SHA256 校验工具（sha256sum 或 shasum）。'
    fi
}

prepare_tool() {
    local work=$1 actual
    if [[ $TOOL_KIND == bundled ]]; then
        cp -- "$BOX_DIR/$TOOL_SOURCE" "$work/payload" || return
    else
        need curl || return
        printf '正在获取固定版本并校验…\n' >&2
        curl --proto '=https' --proto-redir '=https' -fSL --connect-timeout 15 --max-time 300 --retry 2 \
            "$TOOL_SOURCE" -o "$work/payload" || { fail '下载失败，未执行。'; return 1; }
    fi
    [[ -s $work/payload ]] || { fail '下载为空，未执行。'; return 1; }
    actual=$(sha256_file "$work/payload") || return
    [[ $actual == "$TOOL_SHA" ]] || { fail 'SHA256 不匹配，未执行。'; return 1; }
    TOOL_EXEC="$work/payload"
    case $TOOL_KIND in
        bundled|bash) bash -n "$TOOL_EXEC" || return ;;
        binary) chmod 700 "$TOOL_EXEC" || return ;;
        zip-bin)
            need unzip || return
            # Only stream the exact known member; no archive paths are extracted.
            unzip -p "$work/payload" "$TOOL_ENTRY" > "$work/program" || return
            [[ -s $work/program ]] || return 1
            chmod 700 "$work/program" || return
            TOOL_EXEC="$work/program"
            ;;
        tar-bash)
            need tar || return
            # This pinned source archive was checked for links/path traversal at import.
            tar -xzf "$work/payload" -C "$work" || return
            TOOL_EXEC="$work/$TOOL_ENTRY"
            [[ -f $TOOL_EXEC && ! -L $TOOL_EXEC ]] || return 1
            bash -n "$TOOL_EXEC" || return
            ;;
    esac
}

execute_tool() (
    local id=$1 mode=$2 yes=$3 work status
    shift 3
    linux_only || return
    load_tool "$id" || return
    if [[ $mode == run ]]; then
        show_tool "$id" || return
        [[ $TOOL_ROOT != 1 || $EUID == 0 ]] || { fail '该项需要 root，请明确使用 sudo 运行这一项。'; return 1; }
        confirm_run "$id" "$yes" || return
    fi
    # No shared executable cache, no inherited root TMPDIR, and no stale fallback.
    work=$(umask 077; mktemp -d /tmp/006box.XXXXXXXX) || return
    trap 'rm -rf -- "$work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    prepare_tool "$work" || return
    if [[ $mode == verify ]]; then
        printf '已获取并验证：%s，未执行上游程序。\n' "$id"
        return 0
    fi
    case $id in
        docker-registry) set -- --only-registry "$@" ;;
        ipquality) set -- -p "$@" ;; # Upstream privacy option disables online report generation.
    esac
    case $TOOL_KIND in
        binary|zip-bin) "$TOOL_EXEC" "$@" ;;
        tar-bash) (cd -- "$(dirname -- "$TOOL_EXEC")" && bash "$TOOL_EXEC" "$@") ;;
        *) bash "$TOOL_EXEC" "$@" ;;
    esac
    status=$?
    printf '\n[%s] 结束，退出码：%s\n' "$id" "$status" >&2
    return "$status"
)

system_info() {
    linux_only || return
    printf '\n系统信息（只读，不联网）\n'
    if [[ -r /etc/os-release ]]; then
        # Read data rather than sourcing a system file as code.
        awk -F= '$1=="PRETTY_NAME" {gsub(/"/,"",$2); print "发行版：" $2}' /etc/os-release
    fi
    printf '内核：%s\n架构：%s\n' "$(uname -r)" "$(uname -m)"
    if command -v lscpu >/dev/null 2>&1; then lscpu | head -n 18; fi
    if command -v free >/dev/null 2>&1; then free -h; fi
    df -h / || return
    if command -v ss >/dev/null 2>&1; then printf '\n监听端口\n'; ss -lntu; fi
}

run_bbr() {
    local yes=$1
    shift
    linux_only || return
    show_tool bbr
    [[ $EUID == 0 ]] || { fail 'BBR 修改需要 root。'; return 1; }
    confirm_run bbr "$yes" || return
    bash "$BOX_DIR/modules/bbr.sh" "$@"
}

help_text() {
    banner
    cat <<'HELP'
用法：
  bash toolbox.sh                         中文交互菜单
  bash toolbox.sh list                    列出工具
  bash toolbox.sh show <工具>             显示来源、版本与影响
  bash toolbox.sh verify <工具>           获取并校验，不执行
  bash toolbox.sh run <工具> [--yes] [-- 上游参数...]
  bash toolbox.sh info                    本地系统信息，不联网
  bash toolbox.sh about                   整合说明与许可证
  bash toolbox.sh --version

示例：
  sudo bash toolbox.sh run mirrors
  sudo bash toolbox.sh run docker-registry
  bash toolbox.sh run nexttrace -- --help
  bash toolbox.sh run yabs -- -h
  sudo bash toolbox.sh run bbr -- --restore

--yes 只跳过本工具箱的运行确认，上游仍保留自身交互。
HELP
}

about() {
    banner
    printf '维护：006IDC · https://github.com/006IDC/linux-toolbox\n\n'
    cat "$BOX_DIR/NOTICE"
    printf '\n'
    cat "$BOX_DIR/THIRD_PARTY_NOTICES.md"
}

menu() {
    local choice id status target
    local ids=(info mirrors docker docker-registry swap bbr nexttrace ipquality yabs ecs acme kejilion)
    [[ -t 0 ]] || { fail '交互菜单需要终端；使用 list、show 或 run 命令。'; return 1; }
    while true; do
        banner
        printf ' 系统与容器\n  1  系统信息\n  2  软件源切换 · LinuxMirrors\n  3  Docker 安装与换源 · LinuxMirrors\n  4  Docker 镜像加速器 · LinuxMirrors\n  5  SWAP 管理 · jcnf\n  6  当前内核 BBR · jcnf 改编\n\n'
        printf ' 检测与测评\n  7  路由追踪 · NextTrace\n  8  IP 质量体检 · IPQuality\n  9  性能测评 · YABS\n 10  综合测评 · 融合怪 ECS\n\n'
        printf ' 更多工具\n 11  SSL 证书 · acme.sh\n 12  完整管理工具箱 · 科技 lion\n\n  a  关于整合与开源许可\n  0  退出\n\n'
        read -r -p '选择：' choice || return 0
        case $choice in
            0|q|Q) return 0 ;;
            a|A) about ;;
            1|2|3|4|5|6|7|8|9|10|11|12)
                id=${ids[$((choice-1))]}
                case $id in
                    info) system_info ;;
                    bbr) run_bbr no ;;
                    nexttrace)
                        read -r -p '目标 IP / 域名（留空查看帮助）：' target || return 0
                        if [[ -z $target ]]; then execute_tool "$id" run no --help
                        elif [[ $target =~ ^[a-zA-Z0-9:][a-zA-Z0-9.:-]*$ ]]; then execute_tool "$id" run no "$target"
                        else fail '目标地址格式不合法。'; fi
                        ;;
                    acme)
                        printf '通过命令行管理证书，例如：\n  bash toolbox.sh run acme -- --install\n  bash toolbox.sh run acme -- --issue -d example.com --webroot /var/www/html\n'
                        execute_tool "$id" run no --help
                        ;;
                    *) execute_tool "$id" run no ;;
                esac
                status=$?
                [[ $status == 0 ]] || printf '本次未成功（退出码 %s），请查看上方具体原因。\n' "$status" >&2
                ;;
            *) printf '请输入菜单中的编号。\n' ;;
        esac
        read -r -p '按回车返回菜单…' choice || return 0
    done
}

main() {
    local cmd=${1:-menu} id yes=no
    [[ $# == 0 ]] || shift
    case $cmd in
        menu) menu ;;
        --version|-v) printf '%s\n' "$BOX_VERSION" ;;
        --help|-h|help) help_text ;;
        list) list_tools ;;
        show) [[ $# == 1 ]] || { help_text; return 2; }; show_tool "$1" ;;
        about) about ;;
        info) system_info ;;
        verify) [[ $# == 1 ]] || return 2; execute_tool "$1" verify no ;;
        run)
            [[ $# -gt 0 ]] || { help_text; return 2; }
            id=$1; shift
            if [[ ${1:-} == --yes ]]; then yes=yes; shift; fi
            if [[ $# -gt 0 ]]; then
                [[ $1 == -- ]] || { fail '上游参数前必须使用 -- 分隔。'; return 2; }
                shift
            fi
            case $id in
                info) system_info ;;
                bbr) run_bbr "$yes" "$@" ;;
                *) execute_tool "$id" run "$yes" "$@" ;;
            esac
            ;;
        *) fail "未知命令：$cmd"; return 2 ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
