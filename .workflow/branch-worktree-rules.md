# 分支与 Worktree 规则（多 agent 并行开发）

> 适用范围：**会动源代码或测试文件的任务**，按两档判定（判据都可自检，不依赖
> 「有没有别人在跑」这种查不到的前提）：
> - **直做档**（在主分支上做）：开工 `git status --short` 主目录干净，且改动一次
>   commit 收尾（小修 / 单点功能）。纪律：只 `git add <自己的文件>`（禁 `-A` / `.`），
>   commit 前再看一眼 `git status`，出现不是自己的改动不碰；做完立即 commit + push，
>   不留未提交改动过夜。
> - **worktree 档**（走下文全流程）：主目录有他人未提交改动；预计多个 commit 的长任务；
>   派子 agent 并行写代码；要从干净目录部署。拿不准按 worktree 档。
> - 只读分析、只改文档 / 配置 / 纯资源文件的任务始终直做。
> 2026-11-12 修订：2026-10-08 起「一律 worktree」对单人小仓开销过大，改为两档；
> 事故防线从「隔离目录」换成「开工干净 + 只 add 自己的文件 + 即时提交」，
> 并行写代码与长任务仍走 worktree。
> 本仓库（harness 根）自身改动走「即改即推」：直接 commit 到 main 并
> push，无需开分支。
> 事故背景：2026-08-21 实测——多 agent 共用同一工作目录，未提交改动随
> `git checkout` 被并行提交裹走。**分支只隔离提交历史，不隔离工作目录**；
> worktree 才隔离工作目录。
> 复盘 2026-08-26：「收尾清理」屡被跳过（一次巡检出 5 个已合并未删分支 +
> 空壳 worktree；PR 常在会话结束后由用户合并，届时无人清理；本地 main
> 未更新时 `branch -d` 也会失败被跳过）。对策 = 开工巡检自愈 + 收尾硬判定。
> 隔离单位 = 任务 / 主会话。session 内子 agent 共享主会话的 worktree
> （见 implement.md「子 agent 使用」），不另开，也**不因此豁免本规则**；
> 子工程的提交纪律（如直推 main）同样不豁免——在 worktree 分支上干，
> 合并回主分支再推，两者兼容。

## 规则

### 1. 开工（worktree 档）：新任务 = 新 worktree + 新分支

```bash
git -C <仓库> fetch --prune
git -C <仓库> status --short            # 主目录有别人的在途改动：先问清归属（见下），确认后再 pull
git -C <仓库> pull origin main          # 从最新 main 起步
git branch --merged origin/main | grep -v main$   # 有输出 = 清理候选，按 §3 核实验收
git worktree prune && git worktree list  # 先清失效登记；看现有 worktree 避免撞车，已合并残留先核对 §3 的交付证据再清理
git worktree add ../.worktree/<仓库>-wt-<简述> -b feat/<简述>
cd ../.worktree/<仓库>-wt-<简述>        # 在这里开发
```

- **开工巡检（自愈）**：这里只清**已验收且已合并**的残留——上个 agent 忘了清，你来清；
  `-d` 天然不会误删未合并分支，放心用。分支未合并、或 worktree 里有未提交改动的
  一律不动，报告用户。已合并的分支和 worktree 也要先核对 §3 的交付证据，验收待定时保留。
- 发现 main 上有未提交改动：不是你的就不要动，先问清归属，绝不能顺手提交。
- 命名：分支用 `feat/<简述>` / `fix/<简述>` / `task/<简述>`（任务/实验）；worktree
  目录统一建在**仓库同级的 `.worktree/` 目录下**（不直接散在同级），子目录名
  `<仓库>-wt-<简述>`。**目录名必须以
  仓库标识开头**——同级多仓库并存，裸 `wt-`/`task-` 开头看不出归属。类型只放
  分支名，目录名不重复。简述 kebab-case ≤20 字符。
- **建后即补运行配置**：worktree 天生缺被 .gitignore 的部署/运行配置
  （`config/deploy.cfg`、`config/env`、`.env` 等）。本工程有 deploy 流程或需要
  本地起服务验证的，`worktree add` 后**立即**从主目录复制过来——不要拖到部署时
  才发现缺配置（rsync `--delete` 危险侧见 §3「从自己的 worktree 部署」）。
- **`.worktree/` 必须被本仓 `.gitignore` 覆盖**（防嵌套仓被 `git add -A` 当 gitlink
  提交进 main，2026-10-28 事故）。建 worktree 前自检：`git check-ignore .worktree
  >/dev/null && echo ok || echo "需先补 .gitignore"`；目录约定再改名时同步全家族
  各仓 .gitignore。校验只用 `git check-ignore`——`grep '^\.worktree'` 会误命中
  `.worktrees/` 旧条目。

### 2. 并行互不干扰：每个 agent 一个 worktree

每个 agent 一个 worktree，不在同一目录里切分支。worktree 共享仓库对象（不重复
占空间），但工作目录、未提交改动、运行时产物完全隔离。走哪一档只看文件头的
可自检判据，不看「有没有别人在跑」。

### 3. 收尾：提交 → 合并与推送 → 部署与线上验证 → 清理

以下示例从任务 worktree 开始，按保留提交 SHA 的 PR 合并演示。先将占位符替换为本仓实际值；任一步失败即停在该步。直做档沿用相同的提交、远端和生产验收，省略 PR 与 worktree 清理。

```bash
set -eu
wt=$(git rev-parse --show-toplevel)
branch=$(git branch --show-current)
primary='<主检出绝对路径>'
base=main
git status --short --untracked-files=all
git add -- '<本次文件>'                 # 逐项列出任务文件，包含新增和删除
git diff --cached --check
git diff --cached                      # 核对范围、内容及敏感信息
git commit -m '<类型>: <摘要>'           # 按工程要求填写提交正文
task_sha=$(git rev-parse HEAD)
git show --stat "$task_sha"             # 对照交付清单，确认改动确实在提交里
test -z "$(git status --porcelain --untracked-files=all)"

git push -u origin "$branch"
gh pr create --base "$base" --head "$branch" --fill
gh pr merge "$branch" --merge           # 等待实际合并；保留 worktree 直到验收完毕
cd "$primary"
test "$(git branch --show-current)" = "$base"
git pull --ff-only origin "$base"
release_sha=$(git rev-parse HEAD)       # 本次准备部署的主分支版本
git merge-base --is-ancestor "$task_sha" "$release_sha"
git push origin "$base"
git fetch origin "refs/heads/$base:refs/remotes/origin/$base"
git merge-base --is-ancestor "$release_sha" "refs/remotes/origin/$base"

# 有生产变更时，在 HEAD 等于 release_sha 的干净部署源执行（目录选择见下文）
cd '<本次发布的部署源>'
test "$(git rev-parse HEAD)" = "$release_sha"
test -z "$(git status --porcelain --untracked-files=all)"
./manage.sh deploy                      # 同机改用 ./manage.sh deploy-local
# 下列三项替换为本工程真实探针；任一失败，保留现场
actual_sha=$(read_running_production_revision)
test "$actual_sha" = "$release_sha"
curl -fsS '<生产 health URL>'
verify_production_readonly_response     # 请求关键只读接口，核对预期业务字段或值

cd "$primary"
git worktree remove "$wt"
git branch -d "$branch"
```

**收尾硬判定**

1. **任务已提交。** 对照任务文件、差异和验收清单，记录实际承载改动的完整 SHA。已分步提交时复核整段任务差异并记录末次提交，省略重复提交。检查任务范围内已暂存、未暂存及未跟踪文件，防止漏交；别人的改动保留。仅凭工作区干净或 ahead 计数为零不能证明本次改动已交付。
2. **主分支已收到。** 推送后重新获取远端主分支，验证本次提交已进入发布提交，且远端包含发布提交，如上两条祖先检查。采用 squash/rebase 时，从已合并 PR 取得实际落入主分支的提交，核对其差异覆盖任务后，用该 SHA 验证归属并保留原任务 SHA。无发布远程的仓库核对本地主分支包含任务提交，注明仅本地提交。
3. **生产已验证。** 核对运行实例返回的完整版本，或将运行中的镜像摘要、构建标识与发布提交对应；rsync 工程可核对本次变更的产物哈希，并确认运行进程加载该产物。HTTP 服务还要验证健康探针和一个关键只读接口的业务结果；非 HTTP 工程核对实际运行版本并执行项目既有只读状态或功能检查。无法证明版本时报告“生产版本未验证”。纯文档、本地改动、无部署目标或用户明确暂缓部署时，略过示例的整个生产段并写明原因。
4. **最后清理。** 以上适用项通过后，仅移除本任务的 worktree 和已合并分支，再用 `git worktree list` 与 `git branch --list` 核对。PR 待合并、部署失败或线上验收未通过时，保留现场并报告停在哪一步；不强删分支。

- **从自己的 worktree 部署（主目录有别的 agent 在途改动时必选）**：deploy 是
  rsync 按源目录原样同步，脏主目录 = 把别人的半成品推上生产（2026-08-25 险情
  实录）。全新 worktree 天生缺被 gitignore 的部署配置，部署前从主 worktree
  复制本工程的部署配置；注意其中不在 rsync 排除表、属正常同步项的文件——
  源目录缺失会被 `--delete` 从远端**删掉**（危险侧失败），缺失即中止 deploy
  的属安全侧，事先分清。
- 危险文件：凭证形文件名与密钥内容由全局 pre-commit hook 拦截（见
  environment.md）；hook 不认识的 `config/*.json` 等 push 前过一眼
  `git diff origin/main..HEAD --name-only`；日志/缓存确认 `.gitignore` 覆盖。
- 每个 worktree 只做一件事；遵守范围限定，不因同一 worktree 混改多个子工程。

### 4. 切分支的铁律

任何 `git checkout` 切换之前工作区必须干净（commit 或 stash）。带着未提交改动
切分支 = 把半成品送到别人的分支上。

### 5. 子工程差异

- **主分支名**：示例命令里的 `main` 按该仓实际主分支替换（个别仓库用
  `master`）；巡检/清理用 `git branch --merged origin/<主分支>`。
- **本地合并**：将示例中推送任务分支及创建、合并 PR 的步骤替换为在主检出更新主分支并执行 `git merge <任务分支>`。随后按 §3 推送并核对远端、按需部署并验证运行版本与功能，最后清理；`branch -d` 失败时保留分支排查。

### 6. 共享 venv 工程（trade-system）的 worktree 纪律

- worktree 里 `.venv` **软链到主 checkout**（`ln -s <主worktree>/.venv .venv`），
  不装独立环境；测试用 `PYTHONPATH=src .venv/bin/pytest`（PYTHONPATH 让 src
  解析到 worktree 自己的代码，venv 只出解释器和依赖）。
- **禁止在 worktree 里跑 `uv run` / `uv sync` / `manage.sh init|rebuild|start|deploy`**：
  uv 会把共享 venv 的 editable pth 改写到 worktree，删 worktree 后主环境
  import 断、金丝雀假绿。manage.sh 已加软链守卫（deploy 直拒、check/status
  安全）；pth 被改写时 deploy 前置自愈会修回主 src。
