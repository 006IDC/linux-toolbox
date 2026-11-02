# 第三方来源与许可声明

本项目是开源整合与适配项目。各上游核心能力属于原作者及贡献者；006IDC 的工作主要是统一入口、运行调度、版本清单、失败处理及适配测试。上游名称仅用于准确标识来源，不表示官方合作或背书。

检查日期：2026-11-02。入口与发布文件见 [tools.lock.tsv](tools.lock.tsv)，准确来源身份见 [upstreams.json](upstreams.json)。

| 上游 | 作者 / 维护者 | 许可证原文 | 固定源码 | 整合方式 |
| --- | --- | --- | --- | --- |
| [Netflixxp/jcnf-box](https://github.com/Netflixxp/jcnf-box) | jcnf 与贡献者 | [Apache-2.0](licenses/jcnf.txt) | [`40e9013eda2e`](https://github.com/Netflixxp/jcnf-box/tree/40e9013eda2ef7bbbfddcf0b07d7a24f12894fb6) | 直接改编 |
| [SuperManito/LinuxMirrors](https://github.com/SuperManito/LinuxMirrors) | SuperManito 与贡献者 | [MIT](licenses/linuxmirrors.txt) | [`b52707f38e58`](https://github.com/SuperManito/LinuxMirrors/tree/b52707f38e5800d48ac7cc3f390eafec9e948faf) | 固定入口调用 |
| [kejilion/sh](https://github.com/kejilion/sh) | kejilion 与贡献者 | [Apache-2.0](licenses/kejilion.txt) | [`c2993d56760a`](https://github.com/kejilion/sh/tree/c2993d56760a29d3e0cdda33757cc0b9a47935ad) | 固定入口调用 |
| [xykt/IPQuality](https://github.com/xykt/IPQuality) | xykt 与贡献者 | [AGPL-3.0](licenses/ipquality.txt) | [`87397e2c3196`](https://github.com/xykt/IPQuality/tree/87397e2c3196ec796f5477c83343c2354df601ea) | 独立进程调用 |
| [masonr/yet-another-bench-script](https://github.com/masonr/yet-another-bench-script) | Mason Rowe 与贡献者 | [WTFPL](licenses/yabs.txt) | [`21f62408ecde`](https://github.com/masonr/yet-another-bench-script/tree/21f62408ecde9b23d4eec878f46a8292f1944aa0) | 固定入口调用 |
| [acmesh-official/acme.sh](https://github.com/acmesh-official/acme.sh) | acmesh-official / Neil Pang 与贡献者 | [GPL-3.0](licenses/acme.txt) | [`37d064f7b580`](https://github.com/acmesh-official/acme.sh/tree/37d064f7b580055d3f2ddf9a9c960f754f3694d6) | 独立进程调用 |
| [nxtrace/NTrace-core](https://github.com/nxtrace/NTrace-core) | nxtrace 与贡献者 | [GPL-3.0](licenses/nexttrace.txt) | [`7ff73b2c51f9`](https://github.com/nxtrace/NTrace-core/tree/7ff73b2c51f9f37a9bc1d6139b7053948f0250db) | 独立可执行文件调用 |
| [oneclickvirt/ecs](https://github.com/oneclickvirt/ecs) | oneclickvirt 与贡献者 | [GPL-3.0](licenses/ecs.txt) | [`01a8003f8402`](https://github.com/oneclickvirt/ecs/tree/01a8003f840292396d1364a1dfef82a9a8f8b597) | 独立可执行文件调用 |

## 各项整合与修改

- **Netflixxp/jcnf-box**：toolbox.sh 的菜单/调度思路与基础代码；vendor/jcnf/swap.sh；modules/bbr.sh。006IDC 修改：调度重构、中文提示、下载确认及校验；SWAP 归属/备份/恢复；BBR 独立配置与恢复。
- **SuperManito/LinuxMirrors**：使用自包含 Lite 脚本；未改写核心换源/安装逻辑。docker-registry 模式追加上游 --only-registry。
- **kejilion/sh**：保留上游完整菜单及其许可/统计提示；不将该项目的全部功能列为本项目已验收。
- **xykt/IPQuality**：保留原脚本，默认追加上游 -p，禁用在线报告生成；不取消外部数据库查询。
- **masonr/yet-another-bench-script**：保留原脚本。fio、iperf3、Geekbench 等依赖另有各自许可，脚本许可不覆盖这些依赖。
- **acmesh-official/acme.sh**：固定源码包并保留 DNS/部署插件目录；未修改上游源代码。
- **nxtrace/NTrace-core**：按 AMD64 / ARM64 获取官方 v1.7.5 发布文件并校验 GitHub 发布摘要；对应源码固定于下表提交。
- **oneclickvirt/ecs**：按 AMD64 / ARM64 获取官方 v0.2.17 发布包，只读取 goecs 成员；对应源码固定于下表提交。

## 许可边界

根 [LICENSE](LICENSE) 的 Apache-2.0 适用于整合层及 jcnf 改编部分。独立执行的第三方程序并未统一改标为 Apache-2.0。GPL / AGPL 组件保留原许可、版权及准确源码链接；如修改或再分发这些组件，应履行其适用的源码提供等义务。进程调用不是免除第三方义务的理由。

仓库仅直接捆绑 jcnf 改编脚本与许可原文，其余上游按需从锁定的官方来源下载；下载不等同于上游安装或全功能验收。后续子脚本、软件包、数据库与外部服务继续适用各自许可和条款。

本仓库未复制 BlueSkyXN/SKY-BOX 源码；不把其 README 的个人非商用说明与 LICENSE 冲突当成已解决的许可问题。

如来源或署名有误，请通过本仓库 Issues 提供证据，我们会核对更正。
