# 006IDC Linux 工具箱

**社区开源工具整合与适配项目。基于 jcnf-box，集成 LinuxMirrors、NextTrace、YABS、融合怪 ECS、IPQuality、acme.sh 和科技 lion。**

我们提供统一中文入口、版本锁定、下载摘要校验、权限提示、失败处理和适配测试；各项核心工具归原作者及贡献者所有。本项目不是这些工具的官方发行版，不代表上游作者背书。[整合来源与许可证](THIRD_PARTY_NOTICES.md) · [改动署名](NOTICE)

## 产品介绍

适用于通过 SSH 管理 Linux 服务器的用户：从一个终端菜单进入换源、Docker 安装、系统维护、网络诊断和服务器测评。工具按需下载运行，无常驻后台服务，无额外 Web 管理端口。

## 版本概览

- 当前版本：`0.1.0`，首个开源整合版本。
- 工具箱要求：Linux、Bash 4+、curl、CA 证书、`sha256sum`；压缩包组件另需 tar/gzip 或 unzip。
- 主要目标：Debian / Ubuntu，AMD64 / ARM64。其他发行版按各上游自身支持范围工作，尚未作为本项目整体验收目标。
- 首版已通过 AMD64 / ARM64 入口集成、Debian / Ubuntu 实际换源，以及临时 Ubuntu VM 中的 SWAP / BBR 修改与恢复验证。
- macOS 可以查看清单、来源和文档，系统工具执行会被拒绝。
- NextTrace / ECS 的临时可执行文件需要 `/tmp` 允许执行；`/tmp` 挂载为 `noexec` 的加固主机暂不适用这两项。
- [验证范围与限制](docs/VALIDATION.md)，不将上游声称支持等同于本项目已验证。

## 主要功能

| 功能 | 命令中的工具名 | 提供者 |
| --- | --- | --- |
| 本机系统、内存、磁盘、监听端口 | `info` | 本项目只读汇总 |
| 软件源切换 | `mirrors` | LinuxMirrors |
| Docker 安装与软件源配置 | `docker` | LinuxMirrors |
| 仅配置 Docker 镜像加速器 | `docker-registry` | LinuxMirrors |
| SWAP 创建与移除 | `swap` | jcnf-box，006IDC 适配 |
| 当前内核 BBR 启用与恢复 | `bbr` | jcnf-box，006IDC 适配 |
| 路由追踪 | `nexttrace` | NextTrace |
| IP 风险、黑名单及连通性 | `ipquality` | IPQuality |
| CPU、磁盘、网络性能 | `yabs` | YABS |
| 综合服务器测评 | `ecs` | 融合怪 ECS |
| SSL 证书申请、安装与续期 | `acme` | acme.sh |
| 上游完整系统管理菜单 | `kejilion` | 科技 lion |

菜单中的 NextTrace 可输入目标地址；acme.sh 先展示帮助，复杂证书参数通过命令行原样传递。上游安装器保留自己的交互与确认。

## 使用与升级

一条命令启动（不需要 Git）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/006IDC/linux-toolbox/main/start.sh)
```

启动入口自动获取固定的 `0.1.0` 发行包，校验内置 SHA256 后打开中文菜单。退出后清理临时源码，不安装常驻服务或全局命令；上游工具自身产生的配置仍按原行为保存。需要修改系统时，请在 root 终端执行同一条命令。

也可以直接带工具箱参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/006IDC/linux-toolbox/main/start.sh) list
bash <(curl -fsSL https://raw.githubusercontent.com/006IDC/linux-toolbox/main/start.sh) show mirrors
```

支持的依赖为 Bash 4+、curl、CA 证书、tar/gzip，以及 `sha256sum` 或 `shasum`。远程入口地址会随维护更新，所启动的发行版和摘要在 `start.sh` 中明确固定。

需要保留源码时，仍可使用 Git 安装。

先准备依赖，例如 Debian / Ubuntu：

```bash
sudo apt-get update
sudo apt-get install -y bash curl ca-certificates coreutils tar gzip unzip git
git clone --depth 1 https://github.com/006IDC/linux-toolbox.git
cd linux-toolbox
bash toolbox.sh
```

使用源码包时，解压后进入目录运行 `bash toolbox.sh`，不需要 Git。请保留整个目录；单独下载 `toolbox.sh` 缺少依赖清单和模块，无法工作。

```bash
# 查看来源与影响，不下载、不执行
bash toolbox.sh show mirrors
bash toolbox.sh list

# 下载并检查固定版本，不执行上游程序
bash toolbox.sh verify nexttrace

# 仅在需要 root 的操作上使用 sudo
sudo bash toolbox.sh run mirrors
sudo bash toolbox.sh run docker-registry
bash toolbox.sh run nexttrace -- --help
sudo bash toolbox.sh run nexttrace -- example.com
bash toolbox.sh run yabs -- -h

# 自动化：明确接受该工具的影响；--yes 不会自动同意上游协议
bash toolbox.sh run nexttrace --yes -- --help

# 使用 acme.sh 自身能力；账户、域名及部署路径由操作者指定
bash toolbox.sh run acme -- --help
bash toolbox.sh run acme -- --install
bash toolbox.sh run acme -- --issue -d example.com --webroot /var/www/html

# 恢复本工具箱启用 BBR 前的参数
sudo bash toolbox.sh run bbr -- --restore
```

所有上游参数放在 `--` 后，通过 Bash 参数数组传递，不使用 `eval`。交互运行需输入 `RUN 工具名` 确认；非交互运行必须明确传入 `--yes`。

Git 安装可用 `git pull --ff-only` 升级工具箱，升级不会自动运行任何上游工具。压缩包安装使用新目录解压新版。上游入口版本由 `tools.lock.tsv` 锁定，**不会每次启动自动切换至上游最新版**。

## 执行与恢复说明

- 每次执行使用新的私有临时目录，下载完成后校验 SHA256。下载失败、空文件、摘要不符或 Bash 语法错误时停止，退出后清理临时入口；不回退执行旧缓存。
- 摘要覆盖锁定的入口脚本或官方发布包。**上游在运行过程中下载的依赖、子脚本及软件包仍由上游管理，不能据此认为整条下载链均已固定或审计。**
- 换源、Docker 和科技 lion 会改变系统，应先查看 `show` 的影响并自行保有系统恢复点。Docker 镜像加速器的可用性取决于具体服务，并非本项目承诺。
- SWAP 仅管理本工具箱创建且文件身份匹配的 `/var/lib/006idc-linux-toolbox/swapfile`；不删除已有的未知 swap。fstab 前像位于 `/var/lib/006idc-linux-toolbox/swap/`。文件系统或容器不允许 swapon 时返回失败。
- BBR 只使用当前内核已有能力，写入独立配置并保存旧参数。`--restore` 恢复旧运行参数；不安装、更换内核，也不保证现有连接立即切换算法。
- IPQuality 默认追加上游 `-p` 隐私选项，禁用在线报告生成；查询本身仍访问外部数据库。测评工具可能占用较多资源，Geekbench 可上传成绩。科技 lion 保留上游行为，包括许可提示与统计联网；仅在明确进入该项后运行。
- 工具箱本身不上传报告或保存命令参数。上游产生的文件与持久配置依照上游行为保存；卸载工具箱目录不会自动撤销它们。

## 版本演进

见 [CHANGELOG.md](CHANGELOG.md)。首版聚焦可用的终端整合入口，不包含 Web 面板、多主机控制或批量远程执行。

## 许可证和维护

整合层及 jcnf 改编部分采用 [Apache-2.0](LICENSE)。独立调用的第三方组件保持各自的 MIT、Apache-2.0、GPL-3.0、AGPL-3.0 或 WTFPL 许可，**仓库根许可证不覆盖全部上游组件**。固定源码链接、作者、许可原文与改动范围见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、[NOTICE](NOTICE) 和 [upstreams.json](upstreams.json)。

维护者：[006IDC](https://github.com/006IDC)。缺陷反馈请使用本仓库 Issues；上游内部问题会注明对应来源。提交反馈前移除密码、Token、证书私钥与客户资料。

开发验证：

```bash
python3 -m unittest discover -s tests -v
python3 scripts/check_upstreams.py
# 可选网络检查，只下载校验，不运行工具
python3 scripts/check_upstreams.py --network
```
