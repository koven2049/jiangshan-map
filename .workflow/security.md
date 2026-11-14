# security.md — 安全红线细则与审计登记

```
last-reviewed: 2026-09-05 ｜ 按需加载，不自动注入。锚点见 AGENTS.md「安全红线」。
本文件是安全规则族的唯一细则来源：新安全主题在此加一节（有配套 skill 则互链），
AGENTS.md 锚点不再增长，控制常驻 token 开销。
```

## 密钥安全（skill: `llm-key-protection`）

**触发**（任一命中即本节全部适用）：改动涉及密钥/凭证类资产——api key、token、
secret、密码、整份凭证文件（service account JSON 等）、URL 内嵌凭证——的：
新接入、经手端点（保存/测试连接/删除）、落盘（配置文件/DB）、可能进响应或日志。
spawn 子 agent 执行此类改动时，提示词必须带上 skill 名与本文件路径
（子 agent 不必然继承本文件上下文）。

**审计**：按 skill 威胁模型五面逐项过（提交通道抓包 / 读取回显 / 静态存储 /
文件权限 / 出站 https），结果登记下方表格。存量欠账处理同 Lint 存量纪律：
如实报告登记；普通任务不顺手大改，安全加固任务一次修完。

**实战补丁模式**（源自 trade-system 2026-08 修复；参考实现
`trade-system/src/trade_system/secure.py`，方案文档
`key-security-hardening.md`）：

- 密钥字段集中枚举（如 `SECRET_FIELDS` frozenset），save/load 两侧挂信封加密；
  非密钥字段（provider/base_url/model 等）保持明文便于人读与 diff
- 启动自愈：加载配置时明文自动重存升级密文 + 含密文件收权 0600
  （每次加载顺手自愈，不止创建时一次）
- 密钥文件与 KEK **双排除**：`.gitignore` 与 `.rsync-exclude`（或部署排除清单）都要加。
  排除即部署语义变化——交付说明必须写清服务器侧如何获得凭证
  （rsync `--delete` 不会误删已排除的远端存量；新机需重新录入；KEK 不跨机复制）
- 通道闸门逃生口：TestClient host 视为回环（测试免配置）；env flag 仅限特殊拓扑显式豁免
- 删除密钥走独立 DELETE 端点（PUT 留空 = 保持不变，防误清）

**验证（固化为仓库测试，手工 curl 不算完成）**：

- 通道闸门三分支：明文 HTTP + 外部 IP → 403；`x-forwarded-proto: https` → 放行；回环 → 放行
- 加解密 roundtrip + 同明文两次密文不同（nonce 生效）+ 篡改返回空
- 保存后直查存储原始值为 `enc:v1:` 前缀且不含明文；旧明文启动自动升级
- 响应体 grep 不到密钥串；密钥文件权限 0600
- 修完在下方登记表更新状态与修复 commit

## 审计登记表

五列 = 威胁模型五面（提交通道 / 读取回显 / 静态存储 / 文件权限 / 出站 https）。
`—` = 无密钥面，不适用。

| 工程 | 提交 | 回显 | 存储 | 权限 | 出站 | 状态 / 备注 |
|---|---|---|---|---|---|---|
| trade-system | ✅闸门 | ✅零回显 | ✅enc:v1（面板口令除外） | ✅0600+自愈 | ✅改址须重填 key+非回环强制 https+拒私网/元数据 IP | 2026-10-28 审计复核（fa79cf2）：登录/Basic 按 IP 失败限流、会话 HMAC 改服务端 runtime/session.key、/docs 关闭、500 不回显异常；**面板口令按用户拍板保留明文**（已支持 scrypt 哈希 + 启动 WARNING），属已知例外 |
| stock-watch | —无接收面 | ✅仅回布尔 | ✅本地零 key 落盘（真实 key 在远端 env） | ✅远端 .env 0600（2026-08-29 收紧） | ✅https | 2026-08-29 远端 aliyun-hk .env 644→600，服务健康；本地零改动 |
| vedio-split-view | ✅自产 key 端点已合规（哈希入库、一次性返回）；飞书凭证无 HTTP 写入面；2026-10-02 增 vfav_token（转发 X 到 vedio-favorate 的令牌）随飞书凭证 enc:v1 加密，只读挂载容错 | ✅仅 key_prefix；hook 响应零回显 | ⚠app.yaml 明文 LLM key 仍欠账；飞书 secret 在 `config/feishu.yaml` 为 enc:v1（KEK=`config/secret.key`） | ✅0600 本地+远端 ts-macmini-m4；feishu.yaml/secret.key 加载自愈 | ✅https（飞书 open-apis） | 2026-08-31 飞书 hook：凭证不进 app.yaml/git/rsync；欠账：0.0.0.0 裸 HTTP（TLS/反代属部署层决策） |
| movie-share | —无接收面 | —无回显 | ⚠明文 cfg；硬编码 key 已清（0794943） | ✅0600 本地+远端 | ✅全 https | 2026-08-29 修复：a71bca9 泄露的 GLM key+豆瓣 cookie 已从源码清除，key 现被智谱拒(401)，待用户确认轮换；欠账：无 at-rest 加密、Dockerfile COPY credentials.cfg 烘焙进镜像层、filter-repo 待用户决策 |
| ops-dashboard | ✅闸门+bind回环 | ✅掩码/has_secret | ✅（远端明文，见欠账） | ✅远端0600 | ✅https强制 | 2026-08-29 修复 1aa2e9c；欠账：API 整体无鉴权（已限 127.0.0.1 兜底）；worker 侧 config.json 无 at-rest 加密（0600） |
| ops-dashboard（执行面控制令牌，2026-09-04） | ✅闸门（PUT worker/_test 均 _require_safe_key_channel） | ✅掩码，PUT 令牌留空=保持已存 | ✅config/local.worker.json 明文 JSON（0600 原子写，gitignore；欠账：无 at-rest 加密，与存量口径一致） | ✅执行面 agent.json 0600（install 脚本） | ⚠http 内网/Tailscale 明文 + Bearer（HTTPS 列为后续，dashboard 控制面仅此通道） | 2026-09-04 HTTP 控制面上线（exec_agent）；GitHub 凭据不经此通道（执行面 checks.ini bot 自管）；欠账：dashboard API 无鉴权（127.0.0.1 兜底，与上行同） |
| show-site | —无接收面 | ✅ | ⚠deploy.cfg 明文（vercel/blob token，git 未追踪） | ✅0600（2026-08-29） | ✅https | 零代码改动，仅收权 |
| show-site-private | ⚠自认证接收面（边缘有 CF Tunnel TLS） | ✅ | ⚠app.cfg/sessions.json 明文（git 未追踪） | ✅0600（2026-08-29） | —纯静态 | 用户行动项：admin_123 弱密码；欠账：cookie 补 Secure 属性 |
| assets-view | 登录接收密码（经 CF 隧道 TLS）；2026-10-29 加 IP+用户名双维度失败限流（5/10 次每 15 分钟） | ✅零回显；2026-10-29 修复登录密码明文写入 app.log（脱敏中间件 + 测试固化），线上历史 60 条已清洗 | ⚠credentials.cfg 明文（kronos key，git 未追踪）；2026-10-29 修复 auth.secret_key 仓库默认值可伪造会话→runtime/db/auth_secret.key 随机密钥（0600，git/rsync 排除） | ✅0600（app.cfg 含密码曾 644→已修，2026-10-29） | ✅https（CF 隧道） | 用户行动项：轮换登录密码（现密码曾在日志明文滞留且泄露进会话记录）；欠账：credentials.cfg at-rest 加密、token_value 明文与 hash 同存 DB |
| cc_switch | ✅key 运维手改 env，无 HTTP 写面 | ⚠GET /api/config 回明文 key（设计如此，Bearer 鉴权） | ⚠env 明文（10 vendor token，git 未追踪） | ✅0600 本地 + 双实例（2026-08-29：primary env/tokens.yaml/client remote.yaml、backup env/tokens.yaml 均 644→600，root 拉取同步不受影响） | ✅https base_url | TLS 终止已确认 = Cloudflare Tunnel 双实例在跑；primary 8787 已收窄 127.0.0.1（隧道域名 200 验证）；欠账清零 |
| glm-follower | —无接收面 | ✅ | ⚠credentials.cfg 明文（本地占位、远端真实，git 未追踪） | ✅0600 本地+远端 aliyun-sz2（2026-08-29） | ✅https | 附带欠账：bind 0.0.0.0 裸 Flask 无鉴权（非密钥项） |
| ipo_check | — | — | — | — | ✅（公开源 http 但无 key 传输） | 不适用（无密钥面），零改动 |
| shengteng | — | — | — | — | ✅ | 不适用（无密钥面），零改动 |
| ai-learning | ✅闸门 | ✅零回显 | ⚠️Setting 表明文（DB 侧） | ✅无密钥文件（库内 kv） | ✅https强制 | 2026-08-29 修复 a47dfe3：GET/PUT 掩码+has_value、PUT 空/掩码=保持、闸门三分支测试固化、llm/vsv base_url 强制 https（回环 http 豁免）、compose DB_PASSWORD 必填、live 测试硬编码 vsk key 改 env（key 已进过 git 历史，待用户轮换）；欠账：Setting at-rest 加密、auth bootstrap 放行、全面鉴权 |
| coding | —无 HTTP 接收面 | ✅（仅 Langfuse public key 前 12 位，非敏感） | ⚠vendor/.env 明文（9 个 LLM token，git 未追踪） | ✅0600（2026-08-29） | ✅https | 附带欠账：agent-dash.conf bind 0.0.0.0（非密钥项） |
| house-info | 暂缓 | | | | | 用户豁免（2026-08-29） |
| loop-control（2026-09-10 面板迁 mini，ADR-008） | —无密钥接收面（PUT 端点只收配置值，JOB_ENV_KEYS 白名单+值字符集校验） | ✅响应中间件全文替换三把令牌（含 v1 对比值），测试锁死 | ✅token/PAT 均为本地 0600 json（gitignore；欠账：无 at-rest 加密，与 ops-dashboard 同口径）；mini agent.json/jobs env 0600；git 历史扫描零泄漏 | ✅local.* 0600 + agent 加载自愈收权；crontab-sync 回执 root 直写→已改 mktemp+chown+rename 落位 0600（2026-09-05）；面板迁 mini 后看板 PAT 落 mini `~/Services/loop-control-panel/config/local.github.json`（0600，经 stdin 直传不经 rsync） | ⚠agent :17900 HTTP+Bearer 走 Tailscale(WireGuard 加密)，LAN 直连 IP 备援为明文；面板→GitHub ✅https；面板 :19100 绑 0.0.0.0 但应用层 TailnetGuard 只放行回环+Tailscale 私网（`100.64.0.0/10`），局域网实测 403（2026-09-10，ADR-008）| 2026-09-05 全面审计：53→57 测试固化权限面；欠账：面板 API 无鉴权——边界已从"仅回环"改为"回环+Tailscale 私网"（tailnet 内设备无鉴权可写配置，与笔记本本地同级信任；再收紧需加写接口认证）；agent 无限流（43 字符 token 下可接受）；v1 同病 TCC 故障未修（非本仓） |
| newzealand | 暂缓 | | | | | 用户豁免（2026-08-29） |
| agent-tag（2026-10-28，P0 前审计；P1a 复审） | ✅P1a 起有 HTTP 接收面：`POST /api/message`、`GET /api/manifest` 收 `Authorization: Bearer OPS_TOKEN`（hmac 恒时比较；经隧道来的请求要求 `X-Forwarded-Proto: https`，否则 401；进程只绑 127.0.0.1）。OPS_TOKEN 与飞书凭证同存 enc:v1。此前 P0 无 HTTP 接收面（只有 127.0.0.1 `GET /health`；凭证只经 SSH 管道 `manage.sh set-secret` 从 stdin 写入，复制自 feishu-bots 总机器人 .env，全程不落屏） | ✅零回显：`/health` 只回状态，`doctor` 只显示 ok/MISSING，飞书错误只记 code/msg | ✅config/secrets.json 逐值 enc:v1 + config/secret.key（KEK）分离；git 与 .rsync-exclude 双排除，测试锁死 | ✅0600（原子写 + chmod，测试锁死） | ✅https（open.feishu.cn） | 凭证面：飞书总机器人 app_id/app_secret（与 feishu-bots 同一应用，复制一份到 mini）；P1b（2026-10-29）复审：DeepSeek key（复用 feishu-bots 的 LLM_API_KEY，经 SSH 管道写入 enc:v1）只在 agent-tag 主进程内用于 `/llm` 回环代理；Agent 子进程（Claude Code CLI）只拿每会话随机令牌（库里只存 sha256，会话结束吊销），代理拒绝带 cf-connecting-ip 的请求，测试锁死响应与日志不含 key/令牌；P2b（2026-10-29）复审：改码会话 Agent 获得 worktree 内的读写与 Bash——Bash 走 Claude Code 沙箱（只写 worktree、网络白名单、Read 拒绝规则覆盖 ~/.ssh ~/.config ~/.cloudflared ~/.claude 与各服务 config/ runtime/），Runner 执行 Agent 产物（`manage.sh check`）一律套 Seatbelt（home 整体不可读、钥匙串/launchd 不可达、屏蔽本机代理端口），Runner 侧 git 不信 worktree 的 `.git` 指针、关 hooks/fsmonitor；push/PR/合并/部署只由 Runner 用 mini 上 admin 的 gh/SSH 凭证执行，Agent 不持有；部署把机主 config/ 复制成真目录且先 dry-run，传输清单含 config/ runtime/ logs/ data/ .venv/ 即停；均有红绿测试；卡片回调（2026-10-29）：新增公网 `POST /api/hooks/feishu`，无 Bearer，要求飞书加密（Encrypt Key）+ 签名 + Verification Token + 5 分钟时间窗，点击人须为机主，只执行固定指令；Encrypt Key 与 Verification Token 经 `set-secret`（stdin，enc:v1）写入，响应与日志不回显，测试锁死伪造签名/错 token/重放/明文请求均 401；控制台登录（2026-10-29）：飞书「运维 控制台」签发一次性登录链接（`secrets.token_urlsafe(32)`，10 分钟，单次，库存 sha256），兑换为会话 Cookie（随机，库存 sha256，HttpOnly+Secure+SameSite=Lax，30 天，「退出控制台」全部吊销）；时间线与审计对审批码打码；控制台密码登录：只存 scrypt 哈希（n=2^15，`console_password_hash` enc:v1，`set-console-password` 交互/stdin 写入，`set-secret` 拒绝该槽位），按 IP 与全局限次锁定并飞书告警，表单要求同源；GLM（2026-10-30）：新增 `glm_api_key`（智谱开放平台，stdin `set-secret` 写入 enc:v1），同 DeepSeek key 一样只在 `/llm` 回环代理内换上，仅 `glm-*` 会话转发到 https://open.bigmodel.cn/api/anthropic；测试锁死 GLM 会话不会带 DeepSeek key、缺 key 时 503 不回退；专用「运维」应用（C2，2026-11-09）：新增 `feishu_ops_app_id` / `feishu_ops_app_secret`，只经 `set-secret`（stdin，enc:v1）写入，无 HTTP 接收面；只在主进程内交给 lark-oapi 长连接（出站 wss，不需要公网入口），日志级别 WARNING（lark 的连接地址带短期票据，INFO 会打出来）；`doctor` 只显示设了没有；切换完成后公网 `/api/message`、`/api/hooks/feishu` 可关，暴露面变小；2026-11-09 收口：公网 `/api/message`、`/api/manifest`、`/api/hooks/feishu` 已从程序删除（消息与卡片点击只走专用应用的出站长连接），`ops_token`、`feishu_encrypt_key`、`feishu_verification_token` 停用并在启动时从 secrets.json 删除（测试锁死 `set-secret` 不再接受）；`agent-tag.koven2049.xyz` 只剩 `/health`；日报与诊断云文档改由专用应用写（日报文件夹的可编辑协作者）；同日停用总机器人应用凭证 `feishu_app_id/secret`（启动时删除，不再接受），agent-tag 只持有「运维机器人」一套飞书凭证；feishu-bots 侧 `OPS_TOKEN` 已从 aliyun 的 bots/main/config/.env 删除 |
| feishu-assistant | —无 HTTP 接收面（WS 机器人；key 仅本机/SSH 写入 enc:v1） | ✅不回显；sanitize 剥路径 | ✅credentials.cfg enc:v1 + secret.key 双排除 | ✅0600 自愈 | ✅https（飞书 / DeepSeek） | 2026-09-08 看图改 deepseek-v4-flash-vision-exp，与问答共用 DeepSeek key |
| feishu-bots | —无 HTTP 接收面（WS 多机器人；key 仅本机 .env/SSH push-secrets 写入） | ✅不回显；sanitize 剥路径 | ✅bots/*/config/.env 明文 0600（gitignore+rsync 双排除）；bot.cfg ${VAR} 引用零密钥；deploy.cfg 出库改 .example | ✅0600 自愈 | ✅https（飞书/DeepSeek） | 2026-09-24 审计+修复：load_settings 曾在插值 parser 上跑明文升级，把 .env 密钥用本机 KEK 物化进 bot.cfg、跨机不可解（changbaishan 线上启动事故）——改为原始文本升级+${VAR} 跳过，回归测试锁死；8a806c9 误提交的 enc:v1 密文与 deploy.cfg 经 git-filter-repo 清出全部历史并强推，仓库更名 feishu_travel_bot→feishu-bots；对象库全量扫描零残留 |
| vedio-favorate | ✅闸门：带代理头（X-Forwarded-*/CF-*）时只认访客协议，明文页面 308、接口 403，HTTPS 带 HSTS；无代理头仅回环+Tailscale 私网（100.64/10）放行；服务本体只绑 127.0.0.1，跨设备经 ts-forward（只绑 Tailscale IP 的转发器，2026-10-07 起；LAN/公网无监听）；登录限流先占位后校验；密码与智谱 key 只经本机编辑 config/app.cfg 进入，无 HTTP 写入面 | ✅零回显：令牌明文仅创建时出现一次且只能调 /api/share，令牌调分享不回显库内容；/api/system 只回 llm.configured 布尔；key 报错日志先脱敏 | ✅密码读到明文即就地换 scrypt 哈希；智谱 key 读到明文即就地加密 enc:v1（KEK config/secret.key）；会话/令牌只存 sha256；改写配置的临时文件 config/.app.cfg.* 已 git 与 rsync 双排除 | ✅app.cfg / secret.key / library.db 0600，data/ 与 logs/ 0700，加载自愈 | ✅智谱强制 https（base_url 非 https 拒绝启动）、禁用代理、拒绝重定向（防 urllib 跟随时带出 Bearer）；下载经本机回环代理 | 2026-09-26 v0.2.0 审计：修复 LLM 重定向带出 key、令牌分享回显、临时文件未排除（b15db52，测试 tests/test_security.py）；用户行动项：初始密码 admin_123 待改；/tmp/{pre,post}-strip-{dsh,codex}.json 四个 0644 文件含同一把智谱 key 明文（非本工程产生），建议删除并轮换 key；2026-11-10 建 GitHub 私有仓（koven2049/vedio-favorate）前历史审计：全历史文件名扫描（.env/.cfg/.key/.db）零命中、全历史内容模式（key/token/password 真实值形态）零命中、源码无硬编码、真实配置 config/*.cfg/*.key 与 data/ run/ logs/ runtime/ 全程被 .gitignore——完整 93 提交历史原样推送（f226ee1） |
| personal-data-collection（凭据域 KeyHub，2026-11-09） | ✅闸门：手工登记 `POST /api/v1/keyhub/assets`、转托管 `/assets/{id}/hosting`、泄露反向验证（粘贴旧 Key 时）三处只收 HTTPS/`x-forwarded-proto: https`/回环，外部明文 403；三分支测试固化；服务只绑 127.0.0.1 经 CF Tunnel | ✅零回显：资产只回指纹与布尔 `hosted`，无掩码/尾号；收 Key 端点手动解析请求体，`/api/v1/keyhub/*` 的 422 去掉 `input` 字段；检查只存结果分类（不存响应正文/URL/请求头）；金丝雀测试锁死 DB、日志、全部 GET 响应 | ✅扫描值不出机：远端 `python3 -` 现场注入胡椒（stdin，不进 argv/远端磁盘），只上报 HMAC-SHA256 指纹；托管密文 enc:v1 存 DB（KEK 复用 config/secret.key，不进 DB/备份）；胡椒 `config/keyhub-pepper.key` 独立文件；base_url 入库前剥 userinfo/query/fragment 与 Key 形路径段 | ✅胡椒/KEK 0600 自动生成，git 与 .rsync-exclude（`*.key`、`/config/`）双排除，测试断言 0600 | ✅检查只发官方域名白名单或用户逐个确认的中转，仅 https、禁重定向、禁代理、明文 HTTP 端点（如 Tushare）拒绝检查；值在检查进程内存中用后即弃 | 设计：docs/keyhub-integration-design.md §7；接口：docs/keyhub-api.md。已知边界：指纹+路径拓扑对已认证客户端可见并进每日备份（决策 D3，单用户同认证域）；托管 Key 无取回明文接口 |
