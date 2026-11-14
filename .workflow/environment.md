# environment.md — 开发 / 部署环境拓扑

```
唯一来源；tools/multica/.workflow/environment.md 软链到此，改动只改本文件。
作用：跨机器开发时的环境事实来源。SSH 去哪、代理怎么走、进程怎么托管、
公网域名怎么挂、Multica 团队怎么接。
何时读：开工不在本机、要部署、要挂域名、要访问外网、或需要派活给其它机器上的 agent。
凭证 / 密码 / token 不写本文件；代理具体命令以各机 root 下 README 为准。
last-reviewed: 2026-11-10
```

开发目录（两台 Mac 相同）：`~/Documents/workspace/ai`

---

## 1. 机器总览

| 称呼（hosts 别名） | 角色 | OS | 登录帐户 | 备注 |
|---|---|---|---|---|
| `ts-macbook-air` | 主力开发机 | macOS（M3 Air） | 仅 `mingjian` | 单用户；`hostname` 与 Tailscale 主机名都是 `macbook-air` |
| `ts-macmini-m4` | 开发机 + 家用中心节点 | macOS（M4 mini） | `admin` / `shiyun` | 双用户 |
| `aliyun-sz1` | 生产 | AliyunOS（CentOS 系） | `root` / `dev` | 深圳；无稳定外网 |
| `aliyun-sz2` | 生产（主力） | AliyunOS（CentOS 系） | `root` / `dev` | 深圳；进了 Tailscale；无稳定外网 |
| `aliyun-hk` | 生产 + 出网跳板 | AliyunOS（CentOS 系） | `root` / `dev` | 香港，可访问外网 |
| `ts-grok-cursor` | Grok Bot 云电脑（box） | Linux 容器（Debian） | bot 内 `box`（有 sudo） | Tailscale 主机名 `grok-bot`；**无 systemd**；公网出口常为 Cloudflare，外网 UDP 通常进不来 |

`/etc/hosts` 是别名与 IP 的唯一清单（公网 IP + Tailscale `100.x`）。不要在文档里维护第二份 IP 表。`ts-grok-cursor` 只写 Tailscale `100.x`（当前 hosts：`ts-grok-cursor`），不另写公网 IP。

---

## 2. 帐户与目录约定

### 2.1 两台 Mac

| 机器 | 帐户 | 约定 |
|---|---|---|
| ts-macbook-air | `mingjian` | 日常开发帐号；与 `admin@`、`shiyun@ts-macmini-m4` 均无密钥 SSH 打通 |
| ts-macmini-m4 | `admin` | **主要开发 / 部署帐号**。公共东西放 `~/Services`、`~/Public`；共享软件放 `/opt/`（如 `public-skills`、`public-tools`、`cc_switch`）。`~/Services` 自带运维索引：`README`（目录结构唯一说明）、`check_services.sh`（一键巡检，新服务登记进它的 `PROJECTS`）——服务清单看那里，不在本文维护第二份 |
| ts-macmini-m4 | `shiyun` | 第二登录帐户 |


在 macmini 上部署：优先公共目录（`~/Services`、`~/Public`、`/opt`），不要把「两用户都要用」的东西塞进某个家目录的隐匿路径。

**全局 git ignore 兜底（2026-11-11 起，两机 + mini 的 `admin`）。** `core.excludesFile` 指向各自的 `~/.config/git/ignore`（git 默认路径，所以 config 丢了也照样生效），里面登记了必然是本机产物的 agent 工具目录：`.code-review-graph/`、`.video_agent/`、`.v2c/`、`.zcode/`、`.claudian/`、`.codex/`、`.agents/`、`.worktree/`、`.worktrees/`、`.claude/worktrees/`。

- **它是兜底，不是替代。** 全局文件不随仓库走，别人 clone 或新机器拉下来都没有——所以仓内 `.gitignore` 仍是主线，新工程照样要自己写。全局那层只覆盖「新仓刚建、新工具刚冒出来、还没人补仓内规则」的空窗期。
- **三个模式故意没加**，别顺手补上：`.claude/`（仓库可能合法提交工程级 Claude 配置，只兜它的 `worktrees/`）、`.playwright-cli/`（vedio-split-view 有已跟踪文件）、`.obsidian/`（obsidian-backup 的用途可能就包含提交 vault 配置）。
- 全局模式是**任意层级**匹配，不像仓内规则有路径上下文；加之前必须按任意层级查一遍有没有哪个仓在跟踪同名目录（只查顶层会漏）。已跟踪的文件不受 ignore 影响，但之后在那个目录里新增的文件会被静默挡掉，这是真正的代价。
- mini 的 `shiyun` 没设（改不了，需密码）；agent 活都在 `admin` 下。
- **动某仓时的自查**：全局有、本仓没有的条目，判断本仓会不会产出——会就补进仓内 `.gitignore` 并提交（补前按任意层级确认没在跟踪同名目录）；刻意不加的，把结论和理由写进本工程 `AGENTS.md` 专属段，否则下一个 agent 会当遗漏再补。

**全局守卫 guardrails（2026-11-12 起，macbook-air、mini 的 `admin` 与 `shiyun`；对所有 agent 生效）。** 两件都挂在 git 与 shell 层，不依赖任何 agent 的 hook 机制：
- **git hook**：`core.hooksPath` 指向 `guardrails/git-hooks/`——commit-msg 校验 Conventional Commits、subject ≤50 字符、>10 行改动须有正文；pre-commit 拦凭证形文件名 + gitleaks 扫暂存区；之后链式执行各仓自己的 `.git/hooks/<name>`。仓内设了本地 `core.hooksPath` 的仓（如自带 `.githooks/`）不经过它。
- **rsync 包装器**：各 shell profile 末尾的受管块把 `guardrails/bin` 放到 PATH 最前，`rsync` 先过包装器——拦 `--delete-excluded` 与无排除清单的 `--delete`，再 exec 真 rsync；`--server`（远端接收侧）直接放行。不经过它：`sudo`（secure_path）、cron/launchd（不读 profile）、绝对路径调用。核实过的本地镜像用 `GUARDRAILS_ALLOW_RSYNC_DELETE=1` 放行。
- 装/查/卸：`guardrails/install.sh [--check|--uninstall]`，各机在自己的 harness 根下跑。mini 的 `shiyun` 读不到 admin 家目录，用共享副本 `/opt/public-tools/guardrails`：guardrails 改动拉到 mini 后，以 admin 跑 `guardrails/install.sh --publish /opt/public-tools/guardrails`，再以 shiyun 跑 `/opt/public-tools/guardrails/install.sh`。

### 2.2 三台云主机

| 帐户 | 用途 |
|---|---|
| `dev` | **默认生产部署帐户**。笔记本和 macmini 都已打通 `dev@` 与 `root@` |
| `root` | 系统级改动、隧道、少数高敏感服务。目前只有 `cc_switch` / `cc_switch_codex` 跑在 `root@aliyun-sz2`（高敏感，勿当普通服务对待） |

### 2.3 Grok Bot 云电脑（`ts-grok-cursor`）

- 这是 Cursor / Grok Bot 的 **agent 云电脑（box）**，不是阿里云生产机；不要往上面当普通 `dev@` 部署站用。
- 持久自愈套件在 bot 内：`~/.local/share/box-bootstrap/`（`tailscale/`、`hysteria2/`）。点「Update Grok Bot's Computer」后 `/usr/local` 会丢，home 里的 kit 通常还在，靠 `ensure-*.sh` + 桌面自启重装/拉起。
- 登录态：Tailscale 在 `~/.local/share/tailscale/`（`--accept-dns=false`，避免改写 bot DNS）。

---

## 3. SSH 拓扑

```
ts-macbook-air  ←──keyless──→  admin@ts-macmini-m4
        │                              │
        └──────────┬───────────────────┘
                   ▼
         root@ / dev@  {aliyun-sz1, aliyun-sz2, aliyun-hk}
                   │
                   └── 三台云主机彼此可 SSH
```

- 两台开发机可互 SSH，也可 SSH 到全部云主机。
- 云主机**不能** SSH 回开发机。
- `~/.ssh/config` 几乎没有 Host 别名，靠 `/etc/hosts` 解析。
- 连 macmini：Tailscale 主机名 `ts-macmini-m4` 可用；若 clash TUN 干扰 `100.x`，改走 LAN IP（见 `/etc/hosts` 旁的局域网习惯，当前是 `192.168.31.231`）。

---

## 4. Tailscale

官方 Tailscale（非自建 Headscale），tailnet 帐户 `koven2049@`，协调服务器 `https://controlplane.tailscale.com`。

开发相关：`aliyun-sz2` / `aliyun-hk`（2026-09-26 加入） / `ts-macbook-air` / `ts-macmini-m4` / **`ts-grok-cursor`（2026-10-01 加入）**。`100.x` 别称一律看 `/etc/hosts` 里 `ts-*`。hosts 里还有 iPhone、NAS 等个人设备，**不是**开发/部署拓扑的一部分。

| 机器 | 怎么跑 | 节点间端口 |
|---|---|---|
| 两台 Mac | 官方 `Tailscale.app`（随 App 拉起） | UDP **41641**（本机 `*.41641`） |
| aliyun-sz2 | systemd `tailscaled`（enabled）；配置 `/etc/default/tailscaled`（`PORT=41641`） | 同上 |
| aliyun-hk | systemd `tailscaled`（enabled，active）；`/etc/default/tailscaled` 未设 PORT（默认 41641） | 同上 |
| ts-grok-cursor | 无 systemd：`ensure-tailscale.sh` + XFCE 自启；状态在 bot `~/.local/share/tailscale/`；kit `~/.local/share/box-bootstrap/tailscale/` | 同上（Tailscale 自协商） |

查状态：`tailscale status`。SSH / 连 bot 用 hosts 别名 `ts-grok-cursor` 即可，不必记 `100.x`。bot 侧 MagicDNS 名是 `grok-bot.tail87d2.ts.net`（本机 hosts 仍以 `ts-grok-cursor` 为准）。

---

## 5. 出网代理

原则：**直连优先**。确认被拦（超时 / reset / Failed to connect）再挂代理；国内站、内网、localhost 不要走代理。详见 skill `my-proxy`。

### 5.1 两台 Mac

本地代理 `127.0.0.1:7897`（HTTP 与 SOCKS5 同端口）。

```bash
# 单条命令临时走代理（agent 默认用这种，用完即弃）
https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 <cmd>

# 交互式会话（bashrc 已有 alias）
open_proxy
close_proxy
```

启用前先确认端口在听：`nc -z -w 2 127.0.0.1 7897`。

### 5.2 三台云主机（互为隧道）

```
aliyun-sz1 / aliyun-sz2  --访问外网被拦-->  经隧道走 aliyun-hk
aliyun-hk                --访问中国大陆网站受阻时才走-->  经隧道走 aliyun-sz2
```

香港默认可上外网；只有打不开大陆站点时才需要回连深圳。不要一上 hk 就挂 sz 隧道。

**怎么用：读该机 `root` 家目录下的 README，不要把命令/密码抄进其它文档。**

| 机器 | 目录（当前实际） | 说明 |
|---|---|---|
| aliyun-sz1 / sz2 | `/root/hk-proxy/`、`/root/sz-proxy/` | 出网走香港。`sz-proxy` 是本机 mihomo（常见本地端口 `7890`）；`hk-proxy` 是直连香港 SOCKS 的说明与开关脚本 |
| aliyun-hk | `/root/sing-box/` | 给深圳做 SOCKS 入口。另有 `/root/cloudflare/` 讲 Tunnel。这台**没有** `hk-proxy` / `sz-proxy` 目录 |

云主机出网端口与 Mac 的 `7897` **不是一回事**，以该机 README 为准。

### 5.3 Grok Bot 上的 Hysteria2（个人拨入，走 Tailscale）

用途：给 Mac / iPhone（Shadowrocket）一条经 `ts-grok-cursor` 出网的节点；**和 aliyun-hk 的出网跳板不是同一套**——hk 服务深圳云生产出网，这台服务个人客户端。

| 项 | 约定 |
|---|---|
| 监听 | UDP **8443**（Hysteria2） |
| 可达性 | 客户端连 **`ts-grok-cursor:8443`（Tailscale）**。bot 公网出口常是 Cloudflare，**外网 UDP 一般进不来**；iPhone 先开 Tailscale 再拨 |
| 自愈 kit | bot 内 `~/.local/share/box-bootstrap/hysteria2/`（`README.md` / `install.sh` / `server.yaml` / certs）；启动：`ensure-hy2-stack.sh` + 桌面自启 |
| 订阅（勿把口令抄进其它文档） | Shadowrocket：`http://ts-grok-cursor:18787/sub`；Clash Meta YAML：`http://ts-grok-cursor:18787/clash.yaml`（订阅 HTTP 只绑 Tailscale） |
| Mac Clash | Mini 上 Clash Verge 实际跑在 **shiyun** 会话；公共备份可放 `admin@ts-macmini-m4:~/Services/grok-bot-hy2/clash.yaml` |

口令与证书只在 bot kit 的 `state/`、`certs/`；需要轮换时改 bot 上配置并重跑 `gen-sub.sh`，再更新订阅。

---

## 6. 公网域名（cloudflared）

生产服务经常需要一个公网地址：用 Cloudflare Tunnel，后缀一律 `*.koven2049.xyz`。

| 项 | 约定 |
|---|---|
| 映射配置（唯一事实来源） | `/etc/cloudflared/config.yml` |
| 加/删域名 | 改这份 yaml + `cloudflared tunnel route dns …`；macmini 细则见该机 `~/Services/docs/cloudflared.md` |
| 凭证 | 不要动 `cert.pem` / tunnel json |
| 每台机器 | 自己一条 tunnel（macmini 上是 `mac-mini-tunnel`） |

ingress 典型形态：`hostname` → `http://localhost:<port>`，最后一条 `http_status:404`。需要 WebSocket 直通后端时，用 `path:` 把 `/ws` 等路径单独指到 API 端口（Multica 就是这样）。

---

## 7. 进程托管与 Shell

| 机器 | 后台进程 | Shell |
|---|---|---|
| 三台云主机（AliyunOS / CentOS 系） | **systemd** unit | bash |
| 两台 Mac | **系统 LaunchDaemon + `UserName=admin`**（2026-11-10 定稿） | **bash，不是 zsh**。alias 写 `~/.bashrc` |

**Mac 开机自启铁律（**仅 Mac 部署目标**——两台 Mac，主战场 mini；云主机是 AliyunOS 走 systemd，不适用本节任何内容；2026-11-10 定稿、11-11 细化；曾短暂试过用户 LaunchAgent，因重启后不自启而废弃；事实源=mini `~/Services/README` §2）**：常驻服务一律 `/Library/LaunchDaemons/<label>.plist` 并写 **`UserName=admin`**——开机即起（无需 GUI 登录）、进程以 admin 身份运行非 root（cloudflared 以 root 运行是唯一例外）。plist 要点：`UserName=admin`；`EnvironmentVariables` 显式 `HOME=/Users/admin` 与 `PATH`（含 `/opt/homebrew/bin` 与 `/usr/sbin`）；删 `LimitLoadToSessionType`；`install -o root -g wheel -m 644` 安装；前台跑服务 + `KeepAlive=true`（plist 里不得调 `manage.sh start`/nohup）。manage.sh 要点：查状态 `launchctl print system/<label>`（无需 sudo）；**重启无需 sudo**——进程是 admin 的，kill 后 KeepAlive 自动拉起（`./manage.sh restart` 即此法）；`kickstart -k|bootstrap|bootout` 才需 sudo，**由用户以 `!` 前缀自行执行**；**托管识别**——判定 `/Library/LaunchDaemons/<label>.plist` 存在后 start/restart 不得再 nohup 起第二份；**禁止手动 nohup 常驻进程**（不归 launchd 管、挂了不拉起、还占端口挡 Daemon，2026-11-11 job-collection 事故）。验收 `~/Services/check_services.sh`（服务清单由 README §3 表驱动）开机自启段全绿；重启后先不登 admin 桌面直接跑巡检验证无人值守自启。保留用户 Agent 的只有 GUI 应用类（Clash Verge、BrowserOS、Grok Bot、Google 更新器等 `open -a` 类；清单以 README 为准）。

工程生命周期入口统一 `./manage.sh`（`init/start/stop/restart/status/rebuild/deploy`）。

---

## 8. Multica

自托管团队看板：人和本机 AI agent 当队友派 issue。数据只在 macmini postgres。**不要用** `multica.ai` 云（那边的 token 在这里会 `invalid PAT: no rows`）。

| | |
|---|---|
| 入口 | `https://multica.koven2049.xyz` |
| 服务端 | 仅 `ts-macmini-m4`：`~/Services/multica`（podman + compose，只绑 127.0.0.1，公网走 cloudflared） |
| 运维 | 该目录 `./manage.sh status/logs/restart/rebuild`；细节看同目录 `OPS.md` |
| 客户端 | 两台 Mac 的 `~/.multica/config.json`（及桌面 App 的 `desktop.json`）都指向上面这个 URL |
| 登录码 | 没配邮件。本机跑 `multica-code` |

**派活：** 网页 / App / `multica` CLI 建 issue，指派给下表里的 agent。任务在 **daemon 所在那台机器本机** 跑（不是容器里），用该机器已装 CLI 的凭证。

| 机器 | 谁在跑 |
|---|---|
| ts-macmini-m4 | claude, kimi |
| ts-macbook-air | claude, codex, grok, kimi, qoderclicn |

先 `multica runtime list` 看谁在线。云主机 SSH 不回开发机时，用这条路让对面机器上的 agent 干活。

**改端口 / 域名：** 宿主端口看 `.env` + compose，**不要写进别的文档**。frontend 不能代理 WebSocket，所以 `/ws` 必须在 `/etc/cloudflared/config.yml` 里单独指到 backend；改端口要 `.env` 和 ingress 一起改。

**别踩：** `compose logs --since` 在这套 podman 上会挂死；改 `.env` 必须 `up -d`（`restart` 不重读）；本机自加文件（`manage.sh` / `OPS.md` / `start.sh`）不要放进 git 跟踪路径——`rebuild` 会 `checkout --force`。

---

## 9. Agent 行为速查

1. 先判断自己在哪台机器（`hostname` / `whoami`），再选 SSH 目标与代理。  
2. 部署默认 `dev@` 云主机；只有用户点名或高敏感服务才动 `root@aliyun-sz2`。  
3. macmini 上放公共产物；开机自启用系统 LaunchDaemon + UserName=admin（见上「Mac 开机自启铁律」）。  
4. 挂公网域名：改那台机器的 `/etc/cloudflared/config.yml`，不要另造一份域名清单。  
5. 出网失败先直连再代理；云主机代理命令只从该机 `root` 下 README 读。  
6. 需要其它机器上的 agent 干活：走 Multica 派 issue，不要假设云主机能量产 SSH 回笔记本。
