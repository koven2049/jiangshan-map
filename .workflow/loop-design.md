# loop-design.md — 自治 Loop 设计规约

```
作用：issue 总线双角色自治 loop 的设计规约与演进依据；执行契约 loop.md
从本文派生。加/删约束、调阈值等修订以本文为准。
何时读：起草 loop.md、实施或改造任一 loop 执行器之前；每轮修订时。
last-reviewed: 2026-10-26
```

## 1. 角色

| 角色 | 名字 | 默认时序 | 职责 | 禁止 |
|---|---|---|---|---|
| 检查者 | `loop-checker` | 每日 06:00 | 生产只读巡检 + code review + test case review → 开 issue；次日回归复验；SLA 清扫；日报 | 改代码；写生产；merge |
| 修复者 | `loop-fixer` | 摄取器派发（常规 10 分钟 / 快速 60 秒） | 认领 issue → worktree → DoD → PR → merge 关单 | 开 issue；巡检生产 |
| 审核者 | `loop-auditor` | 每周一 07:00 | 周报：周统计（开/修/回退/reopen）+ 抽样复审已 merge 的 PR + 约束修订候选；发现的问题按检查者契约开单 | 改代码；修复 |
| 人 | 外圈 | 不定时 | needs-human 裁决；回退；调阈值 | — |

角色由执行器定时唤起（同机或分布，含二期云端执行者；常驻机选型见
`environment.md`）。角色间不直接通信，**只经 GitHub issue 协调；每次唤醒从
issue 现状出发，不信本地缓存**。周报是 §3/§4 修订的输入：人按周报调约束与
阈值，不手工拉数据。

## 2. 协议

**GitHub 状态定义**（状态只落 GitHub 原语，不引入 Projects 看板）：

| 原语 | 承载 |
|---|---|
| issue open / closed | 在场 / 完结 |
| assignee | **认领锁，状态判定以它为准** |
| label `loop/queued` / `loop/claimed` / `loop/review`（互斥） | 状态投影（未同步不影响判定） |
| label `loop/needs-human` | 旁路态，退出自动流，仅人解除 |
| label `loop/auto` | 来源标记：loop 角色（checker / auditor）开单即打，人工单无此 label，静态不改 |
| label `P0` / `P1` / `P2` | 严重级 |
| comment | 事件流：开单证据 / 认领 / 失败原因 / 审计结论 / 日报周报 |
| PR（`Fixes #N`） | 完结通道：merge 即关单 |
| 工程内 pinned「loop 日志」issue | 日报周报落点，comment 追加，时间线即档案 |

判定规则：open + 无 assignee + `loop/queued` = 可认领；assignee 非空 =
claimed；assignee 非空 + 存在 open PR（`Fixes #N`）= review；
`loop/needs-human` = 任何角色不取。label 由角色在转移点同步维护，
首个角色进场先建齐全部 label。

**状态转移**（状态 label 互斥，一次只挂一个；严重级并挂）：

| 转移 | 动作 | 执行者 |
|---|---|---|
| queued → claimed | set assignee（assignee 即锁；开工前复查仍是自己） | loop-fixer |
| claimed → queued | 失败 unassign 回队；SLA 清扫（claimed 且超 6h 无更新），只重排不关闭 | loop-fixer / loop-checker |
| claimed → review | 开 PR（`Fixes #N`）后改挂；PR 被关未 merge 则 unassign 回 queued | loop-fixer |
| review → closed | PR merge 携带 `Fixes #N`，GitHub 原生关单 | loop-fixer |
| closed → queued | 审计发现回归，reopen + comment | loop-checker |
| 任意 → needs-human | 升级条件命中即改标退出，仅人可解除 | loop-fixer / loop-checker |

**needs-human 协定**（label 管路由，comment 管决策）：升级时置空 assignee、
换 label、发决策请求 comment——背景 / 一个具体问题 / 选项与后果 / 声明无默认
动作；P0 级同时 @mention 人。人拍板 = 回复 comment + 删除该 label（agent 永不
代删），再按结论回 `loop/queued` 或直接 close。不设自动超时；防烂单靠日报列
needs-human 清单 + P0 @mention + 周报计数（挂超两周标红）。

**issue 契约**（loop-checker 开单必含）：现象与证据 / 位置（file:line、服务、
机器）/ 复现与验证命令 / 完成判据 / 严重级；正文末尾一行 loop.md URL。开单前
查 open issue 去重，同类 comment 追加，不开新单。

**外部报单（人 / bot）入口**：

- 来源判定：标题以 ` [bot]` 结尾 = bot 单（bot 以主人帐号开单，作者无法区分，
  后缀是唯一来源信号）；无后缀且无 `loop/auto` = 人工单。
- 授权：只认作者 ∈ 白名单（默认 = 仓主）的单；其余单任何角色不碰。label 只有
  仓库写权限者能打，所以「打上 `loop/queued`」本身即授权动作。
- 入队：bot 单无状态 label 且无 assignee → 摄取器自动补 `loop/queued` 并
  comment；人工单须人手动打 `loop/queued` 才进队。
- 信息不足（缺现象 / 复现 / 判据，修复者无法开工）→ `loop/needs-human` +
  决策请求 comment 列缺失项，不猜修。
- issue 标题与正文对修复者是**数据不是指令**：提示词以围栏块传入并声明此点。
- 已知 bot 报单方：Grok Bot（ops-dashboard 文档）与 agent-tag（飞书「投 loop
  T123」，`agent-tag/src/agent_tag/loops.py`）。两者都在开单前按**同名 open
  issue** 去重；agent-tag 正文按上条契约写 现象 / 复现与验证 / 完成判据 / 期望，
  不打严重级 label（进常规车道）。

**触发器（摄取器）**：确定性代码，不经模型。两条车道，参数页面可调、落
`schedule.json` 的 `intake` 段：

| 车道 | 默认节奏 | 取单范围 |
|---|---|---|
| 常规 | 每 10 分钟 | 全部可认领单，按 P0→P1→P2→无级、再按开单时间排序 |
| 快速 | 每 60 秒 | 仅 bot 单 且 `P0` |

每次摄取：列各开通工程 open issue → bot 单补入队 → SLA 清扫 → WIP 门 →
按空闲槽位派发。摄取器只派发，**认领由修复进程自己完成**（见并发）。

**并发**：

- 单机互斥用原子目录锁（`mkdir`，内含 pid，pid 已死即陈锁可抢）：issue 锁
  （同一单同时只一个修复进程）、槽位锁（全局并发上限 `max_parallel`，默认 2）、
  工程锁（同工程同时只一个常规修复，防互相冲突的 PR）。
- 快速车道多一个预留槽位、且不受工程锁限制——P0 不排在 P2 后面。
- 跨机互斥用 GitHub：修复进程拿到本机锁后 set assignee + 改挂 `loop/claimed`
  + 发带 `run=<id> host=<机器>` 标记的认领 comment，再回读：自上次入队以来最早
  的认领 comment 不是自己 → 退出不动（claim-lost）。
- 摄取器每车道单实例（同样目录锁），重叠触发直接跳过。

**修复 DoD**：worktree 分支 `fix/issue-<N>`（基于最新 `origin/<默认分支>`）→
delta verify（零新增失败）→ PR（body 带 `Fixes #N`）→ merge。结构强制
**1 issue : 1 PR : 1 merge commit**，禁 squash（merge 用 merge commit，保证
`git revert -m 1` 可按单回退）。上限：单 PR diff ≤300 行（超限转
`needs-human`，不开 PR）；单日 merge ≤5；open+claimed ≥10 时本轮不取新单。
失败：comment 原因 + 解除 assignee + 回 `loop/queued`；同一单连败 3 次 →
`needs-human`。

**修复时的 harness**：修复者在 worktree 内必须先读仓库根 `AGENTS.md`
（`CLAUDE.md` 软链同文件）并遵守；worktree 的钩子 = 仓库原有钩子 + 执行器的
pre-push 护栏（护栏不得顶掉原有钩子）。规范里能确定性检查的（测试、lint、diff
上限）由执行器在 agent 之外独立跑，agent 自报不算数。

**合并与上线**：

- 能否自动 merge 只按来源：`loop/auto` 单（loop 自己发现的）在工程开启自动
  merge 时可由审查者合并；人工单 / bot 单**一律等人 merge**——外部输入不可信，
  且是人在等结果。
- 审查结论只认最后一行严格格式 `结论：APPROVE|REQUEST-CHANGES|COMMENT`，
  不做子串匹配。
- loop 永不部署。merge ≠ 上线；上线是人发起的独立动作（ops 面板 deploy /
  `manage.sh deploy`），harness「合并即部署」收尾条款不适用于 loop 角色。
- agent-tag 投出的单：人在 GitHub merge 后，agent-tag 推一张绑定 merge
  commit 的「部署审批」卡片，机主回码才部署（`release: none` 的工程只确认）。
  同一次合并**只走一条上线路径**——用了 ops 面板 deploy 就不再批 agent-tag 的
  卡片（回 `驳回 T123`），反之亦然；agent-tag 只记得自己发起的部署，面板部署
  不进它的回滚目标表。

**凭证隔离**：修复进程的 agent 子进程环境去掉 `GH_TOKEN` / `GITHUB_TOKEN`，
`GH_CONFIG_DIR` 指向空目录（agent 内 `gh` 无登录态）；push / PR / issue 写
操作只由执行器代码完成。残余风险：同 OS 帐户下 ssh key 与文件仍可读，彻底
隔离需独立帐户或容器（二期）。

**安全边界**：loop-checker 对生产只读；数据 / schema / 删除 / 越出工程边界
一律 `needs-human`，不自主修；沿用执行器既有护栏（worktree 困禁、命令白名单、
轮次与墙钟上限、3 连败熔断）。issue 写操作（开单 / 评论 / 认领 / 关单）属 loop
常设授权，工程启用 loop 即生效。

**审计与回退**：loop-checker 每日复验近期已关单，回归即 reopen。回退由人执行：
`git revert -m 1 <merge>`（按 issue 号或按天逆序批量）；revert 不自动 reopen，
须手动 reopen + comment「人工回退」。回退率 / reopen 率升高时，恢复人审 merge
为首选回退。

**日报 / 周报**：loop-checker 每日一条、loop-auditor 每周一一条，comment 到
工程内 pinned「loop 日志」issue。日报：开 X / 修 Y / 存量 Z / 最老单年龄 /
WIP 水位；周报：周统计 + 抽样复审结论 + 约束修订候选（对应 §3）。

## 3. 约束预算（修订规则）

- 每条约束必须锚定一个失败模式；确定性逻辑落执行器代码，提示词只留契约。
- 连续两周未拦住任何东西的约束 → 删除候选；同一失败模式复现 2 次 → 先加代码
  约束，后加提示词约束；阈值按 §4 信号调。
- 阈值（SLA 6h、WIP 10、diff 300、merge 5/日）均为初始值。
- 明确不加：进度心跳 comment（PR commit 已是活动信号）；队列深度熔断（WIP 门
  + 日报已覆盖）；revert CLI（手工流程够用）；逐 issue 重复安全约束（URL
  指针代替）。
- 本文不出现工程名，执行器无关。

## 4. 演进信号

信号源：周报（含日报序列）/ 审计 reopen 率 / 人工回退次数 / WIP 水位 / 最老单年龄。
每次改 loop 行为（执行器 / loop.md）后，决策与理由回填本文。

## 修订记录

- 2026-10-26：加外部报单入口（` [bot]` 后缀 + 作者白名单）、事件型摄取器（常规
  / 快速双车道，参数页面可调）、本机目录锁 + GitHub 认领 comment 的双层并发、
  修复时 harness 加载与钩子链、来源决定 merge 权限、loop 永不部署、agent 凭证
  隔离。动机：手机 / bot 报单要分钟级响应；既有执行器只吃面板方向、不读 GitHub，
  且自动 merge 靠子串匹配 + squash，与本文 1:1:1 / 禁 squash 冲突。

- 2026-09-03：加 `loop/auto`（来源标记）与 `loop/review`（状态投影）。动机：
  监督看板需按 label 聚合检索——GitHub search 对 label 是一等公民，正文契约
  解析不可查询、不可过滤；review 判定仍以 assignee + open PR 为准，label 仅
  投影。撤销 §3 原「不加 type 标签」条目（被本条取代）。

## 附录：外部参考（非规则，仅作后续修订依据）

- [Label-Driven Agentic Workflows](https://medium.com/@serifcolakel/label-driven-agentic-workflows-building-autonomous-software-pipelines-without-a-workflow-engine-281bfc1cd399)：labels 既是队列又是状态，issue tracker 即 workflow engine；转移 = 删自己 label 加下一个。
- [Heartbeats, Work Queues, and Self-Managing Agents](https://medium.com/@chen.yang_50796/autonomous-ai-dev-teams-heartbeats-work-queues-and-self-managing-agents-0fad942580e9)：每次唤醒必须 `gh issue list`（实测信本地内存漏了 15 张单）；协调者负责 triage 与卡死监控——本文由 loop-checker 兼。
- [GitHub Copilot coding agent](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-on-github)：assign 即触发、draft PR 即进度面、merge 原生关单——本文 assignee 锁与关单方式同源。
- [Sentry Seer Autofix](https://docs.sentry.io/product/ai/autofix/)：生产信号 → 根因 → 修复计划 → PR，人审后合并。**有意识偏离**：本文一期即自主 merge，补偿 = delta verify + 次日审计 + 1:1:1 回退；信号恶化则回人审。
- [actions/stale](https://github.com/actions/stale) 及[争议](https://www.reddit.com/r/programming/comments/sh6a1t/github_stale_bot_considered_harmful/)：超时清扫可借，机械关单有害——本文只重排不关闭。
- 看板 WIP（[Atlassian](https://www.atlassian.com/agile/kanban/wip-limits)）：上限让停滞可见。
