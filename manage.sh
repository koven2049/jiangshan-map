#!/usr/bin/env bash
set -euo pipefail
# manage.sh (physical) for jiangshan-map — static atlas site, 双形态：
# 生产（mini ~/Services/jiangshan-map）= 系统 LaunchDaemon
# com.koven.jiangshan-map（KeepAlive，开机自启）；Test = 本目录 nohup + pidfile，
# 绝不托管给系统。
# Local serve: python3 server.py (repo root over HTTP, /health on port 8930).
# Deploy = zero-transfer, run entirely in this directory:
#   validate (node) → push origin (koven2049/jiangshan-map — the ONLY remote
#   this checkout touches; the upstream repo is never fetched or pushed).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── deploy-check.sh: conditional source, no-op fallback when no parent repo ──
_deploy_check="$(dirname "${BASH_SOURCE[0]}")/../coding/deploy-common/deploy-check.sh"
if [[ -f "$_deploy_check" ]]; then
    source "$_deploy_check"
else
    _check_deploy_target() { :; }
fi

# ── log helpers (§9.4 — keep these names) ───────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }

# ── config ──────────────────────────────────────────────────────────────────
SERVICE="jiangshan-map"
PORT=8930
PY=python3
PIDFILE="$SCRIPT_DIR/run/server.pid"
LOGFILE="$SCRIPT_DIR/run/server.log"
# 托管形态（铁律：见 .workflow/environment.md「Mac 开机自启」）：生产（mini）
# = 系统 LaunchDaemon（deploy/ 下的 plist 模板与线上一致，UserName=admin，
# 开机自启不依赖 GUI 登录；重启免 sudo=kill 后 KeepAlive 拉起，真正停用才需
# sudo bootout）；Test（开发机）= 本目录 nohup + pidfile，**绝不托管给系统**
# ——install-daemon 有 Test 防呆（无部署章即拒绝）。
LAUNCHD_LABEL="${LAUNCHD_LABEL:-com.koven.jiangshan-map}"

# ── START COMMAND ───────────────────────────────────────────────────────────
START_CMD=("$PY" "$SCRIPT_DIR/server.py")
# ────────────────────────────────────────────────────────────────────────────

# 实例身份判定特征：PROC_IDENT = 命令行里最特异的本目录路径片段（绝对路径的
# server.py，每个检出各有一份 → 天然目录级）；SERVICE_MARKER = 服务标记
# （线上 plist 用相对路径 server.py 启动，命令行无绝对路径时退化为
# 标记 + cwd 判定）。
PROC_IDENT="$SCRIPT_DIR/server.py"
SERVICE_MARKER="server.py"

is_running() {
  [[ -f "$PIDFILE" ]] || return 1
  local pid; pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
}

# ── 进程侦查助手 ────────────────────────────────────────────────────────────
# 监听 $PORT 的 PID（无监听/无 lsof → 空）。launchd 直接拉起的实例没有 pidfile，
# 只能靠端口判断是否已在运行。lsof 无匹配时退出码为 1，须归零以免 set -e 误杀。
port_listener_pid() {
  command -v lsof &>/dev/null || return 0
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
}

# 监听 $PORT 的全部 PID（可能有多个；无监听/无 lsof → 空）。
port_listener_pids() {
  command -v lsof &>/dev/null || return 0
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true
}

# 一个 PID 是否属于本目录实例：命令行含本目录特征路径；launchd 相对路径启动
# （命令行无绝对路径）时退化为 命令行含服务标记 且 进程 cwd 是本目录。
# 身份不确认绝不杀。
pid_is_ours() {
  local pid="$1" cmdline cwd
  cmdline="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ "${cmdline:-}" == *"$PROC_IDENT"* ]] && return 0
  [[ "${cmdline:-}" != *"$SERVICE_MARKER"* ]] && return 1
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  [[ "${cwd:-}" == "$SCRIPT_DIR" ]]
}

# 只保留确认是本目录实例的监听 PID：端口可能被无关进程或另一检出的同服务
# 占用——身份不确认绝不杀（launchd 与 nohup 实例都必须过身份判定）。
confirmed_server_pids() {
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    pid_is_ours "$pid" && printf '%s\n' "$pid"
  done < <(port_listener_pids)
  return 0
}

alive() { kill -0 "$1" 2>/dev/null; }

# 停一个 PID：先 TERM，等 ${JM_STOP_TERM_WAIT:-3}s 不退再 KILL，再等
# ${JM_STOP_KILL_WAIT:-2}s。仍活着（杀不动/权限不够）返回 1。
stop_pid() {
  local pid="$1" waits="${JM_STOP_TERM_WAIT:-3}" i
  kill -TERM "$pid" 2>/dev/null || true
  for ((i = 0; i < waits * 10; i++)); do alive "$pid" || return 0; sleep 0.1; done
  log_warn "pid $pid ignored SIGTERM — sending SIGKILL …"
  kill -KILL "$pid" 2>/dev/null || true
  waits="${JM_STOP_KILL_WAIT:-2}"
  for ((i = 0; i < waits * 10; i++)); do alive "$pid" || return 0; sleep 0.1; done
  alive "$pid" && return 1
  return 0
}

# 轮询 GET /health 直到 200，超时 ${JM_HEALTH_WAIT:-15}s 返回 1。
# 无 curl 的机器退化为「确认过的本服务监听存在」。
wait_health() {
  local timeout="${JM_HEALTH_WAIT:-15}" i
  if command -v curl &>/dev/null; then
    for ((i = 0; i < timeout * 2; i++)); do
      curl -sf --max-time 2 "http://127.0.0.1:$PORT/health" &>/dev/null && return 0
      sleep 0.5
    done
  else
    for ((i = 0; i < timeout * 2; i++)); do
      if [[ -n "$(confirmed_server_pids | head -n 1)" ]]; then return 0; fi
      sleep 0.5
    done
  fi
  return 1
}

# launchd 是否在本机加载了本服务（含 gui 域）；查不了（无 launchctl）返回 2。
launchd_managed() {
  command -v launchctl &>/dev/null || return 2
  launchctl print "system/$LAUNCHD_LABEL" &>/dev/null && return 0
  launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" &>/dev/null && return 0
  return 1
}

# ── 实例身份 = 部署盖章（2026-11-13 规约）──────────────────────────────────
# deploy-local 成功后在目标副本写 config/env=production（唯一写入点；deploy
# 走 git push 不落盘，不盖章）。两台机器的开发检出永远无章 → 都是 Test。
# manage.sh 只读章判身份；方向单向：源副本带章即拒绝部署（prod 不能当部署源，
# 见 cmd_deploy / cmd_deploy_local 的入口守卫）。禁止 hostname/IP/deploy.cfg
# 推断身份。
prod_stamp_file() { printf '%s/config/env' "$SCRIPT_DIR"; }
is_prod_instance() { [[ "$(cat "$(prod_stamp_file)" 2>/dev/null || true)" == production ]]; }
refuse_if_prod_source() {
  is_prod_instance || return 1
  log_error "本目录是生产副本（config/env=production，由 deploy-local 盖章）——不能作为部署源。"
  log_error "部署请在开发检出执行（本机或 mini 的 ~/Documents/... 检出，均无章=Test）。"
  return 0
}
system_managed() {
  command -v launchctl &>/dev/null || return 1
  launchctl print "system/$LAUNCHD_LABEL" &>/dev/null
}
# 目录级托管判定（2026-11-13 修订）：同机 Test 检出（~/Documents/...）与生产
# 副本（~/Services/...）共用同一个 label——只看 label 会把 Test 的 start/stop
# 误判成「生产托管中」。托管判定必须目录级：label 在 system 域 **且** 监听
# 进程属于本目录实例。
daemon_managed_here() {
  system_managed || return 1
  [[ -n "$(confirmed_server_pids | head -n 1)" ]]
}
# 端口被「别的目录」的本服务实例占用（典型：同机生产副本占着端口）。
port_held_elsewhere() {
  local listener; listener="$(port_listener_pid)"
  [[ -n "$listener" ]] || return 1
  [[ -z "$(confirmed_server_pids | head -n 1)" ]]
}
# 免密服务控制：root 所有的 svc-ctl 包装（白名单 label，只开放
# bootout/bootstrap/kickstart 三个动作）。缺失时（未安装）相关操作降级为
# 指引，不硬错。
SVC_CTL=/usr/local/bin/svc-ctl
svc_ctl() { sudo -n "$SVC_CTL" "$@"; }

# 系统域托管守卫（仅当本目录实例被 Daemon 托管时触发）：软停无意义——kill 后
# KeepAlive 立即拉起，面板会显示「成功」但服务根本没停。真停 = svc_ctl
# bootout；helper 未装时降级为准确指引（一次性安装命令见提示）。
# 返回码：0=已真停完成；1=非本目录托管（调用方走各自路径）；2=托管但 helper
# 未装、无法免密真停（调用方必须拒绝软停，exit 1）。
guard_prod_daemon_stop() {
  daemon_managed_here || return 1
  if svc_ctl bootout "system/$LAUNCHD_LABEL" 2>/dev/null; then
    sleep 1
    [[ -n "$(confirmed_server_pids | head -n 1)" ]] && stop_pid "$(confirmed_server_pids | head -n 1)" || true
    log_ok "已停用（svc_ctl bootout）。重新上线：./manage.sh start（走 bootstrap）。"
    return 0
  fi
  log_warn "本目录实例由系统 LaunchDaemon 托管（KeepAlive），软停会被立即拉起。"
  log_warn "免密真停需一次性安装 svc-ctl helper（root）："
  log_warn "  sudo bash ~/Services/install-svc-ctl.sh"
  log_warn "装好后本命令即可真停；或手动 ! sudo launchctl bootout system/$LAUNCHD_LABEL"
  return 2
}

# ── pretty box for status ───────────────────────────────────────────────────
box_line() { printf '│ %-9s : %s\n' "$1" "$2"; }

cmd_init() {
  log_step "Initializing $SERVICE …"
  command -v "$PY" &>/dev/null || { log_error "python3 not found."; exit 1; }
  mkdir -p "$SCRIPT_DIR/run" "$SCRIPT_DIR/config"
  if [[ ! -f "$SCRIPT_DIR/config/deploy.cfg.example" ]]; then
    cat > "$SCRIPT_DIR/config/deploy.cfg.example" <<'EOF'
env = production
ssh_target = admin@ts-macmini-m4
remote_path = Services/jiangshan-map
EOF
    log_info "Created config/deploy.cfg.example — copy to config/deploy.cfg and edit."
  fi
  log_ok "Init complete."
}

start_service() {
  if is_running; then log_ok "Already running (pid $(cat "$PIDFILE")) — idempotent, exit 0"; return 0; fi
  # 端口已被监听但 pidfile 缺失/失效（如 launchd 直接拉起的实例）：视为已在
  # 运行，直接返回(0)，不再启动第二个实例。
  local listener; listener="$(port_listener_pid)"
  if [[ -n "${listener:-}" ]]; then
    log_ok "Port $PORT already in use (pid $listener) — already running, skip second start, exit 0"
    return 0
  fi
  rm -f "$PIDFILE"
  mkdir -p "$SCRIPT_DIR/run"
  log_step "Starting $SERVICE on port $PORT …"
  PORT="$PORT" nohup "${START_CMD[@]}" >>"$LOGFILE" 2>&1 &
  echo $! >"$PIDFILE"; sleep 1
  if is_running; then
    log_ok "Started.  pid $(cat "$PIDFILE")  →  http://localhost:$PORT"
  else
    log_error "Failed to start. See $LOGFILE"; rm -f "$PIDFILE"; return 1
  fi
  return 0
}

cmd_start() {
  if daemon_managed_here; then
    # 本目录实例由 KeepAlive 保活，start 幂等。
    log_ok "Managed by system LaunchDaemon ($LAUNCHD_LABEL) — instance kept alive; start is a no-op."
    return 0
  fi
  if port_held_elsewhere; then
    # 同机另一副本（~/Services 生产实例）占着端口：Test 与生产同端口不能并存。
    log_error "端口 $PORT 已被本服务的生产实例占用（~/Services 副本，系统 Daemon 托管）。"
    log_error "Test 与生产同端口不能并存：要跑本目录实例，先停生产（去 ~/Services 副本执行 stop 会给出 sudo 命令）。"
    exit 1
  fi
  # 有章 = 生产副本（此前被 bootout 停用）：走 bootstrap 回托管，而非 nohup。
  if is_prod_instance; then
    if svc_ctl bootstrap "system/$LAUNCHD_LABEL" 2>/dev/null; then
      sleep 2
      if wait_health; then
        log_ok "Started via svc_ctl bootstrap.  pid $(port_listener_pid)  →  http://localhost:$PORT"
        return 0
      fi
      log_error "Bootstrap done but /health not passing."
      return 1
    fi
    log_error "免密启动失败：svc-ctl helper 未安装（root 一次性安装）："
    log_error "  sudo bash ~/Services/install-svc-ctl.sh"
    log_error "或手动 ! sudo launchctl bootstrap system /Library/LaunchDaemons/$LAUNCHD_LABEL.plist"
    exit 1
  fi
  start_service || exit 1
}

cmd_stop() {
  guard_prod_daemon_stop; local grc=$?
  [[ "$grc" -eq 0 ]] && return 0   # guard 已真停
  [[ "$grc" -eq 2 ]] && exit 1     # 托管但 helper 缺失：拒绝假成功（面板如实显示失败）
  if port_held_elsewhere; then
    log_error "端口 $PORT 上的实例属于生产副本（~/Services，系统 Daemon 托管），不属于本目录——本目录无可停。"
    log_error "要停生产：去 ~/Services 副本执行 ./manage.sh stop（同样会给 sudo 命令），或直接 sudo bootout。"
    exit 1
  fi
  # 停止目标 = pidfile 里的 PID + 监听 $PORT 的本目录实例。Test 模式（本目录
  # nohup）实例有 pidfile；launchd 直接拉起的实例没有——只认 pidfile 会
  # 「nothing to stop」，restart 就成了空转。身份不确认的进程绝不杀。
  local targets=() pid t dup
  if [[ -f "$PIDFILE" ]]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && alive "$pid"; then
      if pid_is_ours "$pid"; then
        targets+=("$pid")
      else
        log_warn "pidfile pid $pid is not this checkout's $SERVICE (stale pidfile?) — not killing it."
      fi
    else
      log_warn "Process not running."
    fi
  fi
  while IFS= read -r pid; do
    if [[ -n "$pid" ]]; then
      dup=0
      if [[ ${#targets[@]} -gt 0 ]]; then
        for t in "${targets[@]}"; do
          if [[ "$t" == "$pid" ]]; then dup=1; break; fi
        done
      fi
      if [[ "$dup" != 1 ]]; then targets+=("$pid"); fi
    fi
  done < <(confirmed_server_pids)

  if [[ ${#targets[@]} -eq 0 ]]; then
    log_warn "No pidfile and no confirmed $SERVICE instance on port $PORT — nothing to stop."
    rm -f "$PIDFILE"
    return 0
  fi

  log_step "Stopping $SERVICE (pid ${targets[*]}) …"
  local failed=0
  for pid in "${targets[@]}"; do
    stop_pid "$pid" || { log_error "Could not stop pid $pid."; failed=1; }
  done
  rm -f "$PIDFILE"
  if [[ "$failed" == 1 ]]; then return 1; fi
  # KeepAlive=true 的 launchd 会在老实例死掉的瞬间拉起新实例：老 PID 全死即视
  # 为停止成功（要真正停住 launchd 服务需 sudo bootout，不属于本脚本）。
  local respawned; respawned="$(confirmed_server_pids | head -n 1)"
  if [[ -n "${respawned:-}" ]]; then
    log_ok "Old instance stopped (launchd KeepAlive already respawned pid $respawned)."
  else
    log_ok "Stopped."
  fi
  return 0
}

cmd_restart() {
  log_step "Restarting $SERVICE …"
  # 本目录实例被系统 Daemon 托管：kill 后 KeepAlive 自动拉起新进程——重启免
  # sudo；绝不能 nohup 起第二实例（与 respawn 抢端口）。
  if daemon_managed_here; then
    log_info "system LaunchDaemon owns respawn — killing instance and letting KeepAlive restart it …"
    local pid killed=0
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      stop_pid "$pid" && killed=1 || log_warn "could not stop pid $pid"
    done < <(confirmed_server_pids)
    [[ "$killed" == 1 ]] || { log_error "No confirmed instance to restart."; return 1; }
  elif port_held_elsewhere; then
    log_error "端口 $PORT 被生产实例（~/Services 副本）占用——restart 不越目录杀生产进程。"
    log_error "要重启生产：去 ~/Services 副本执行 ./manage.sh restart。"
    exit 1
  else
    # 先记下旧实例，restart 结束时必须换成新进程。
    local old_pids=" " pid
    while IFS= read -r pid; do
      if [[ -n "$pid" ]]; then old_pids+="$pid "; fi
    done < <(confirmed_server_pids)
    cmd_stop || { log_error "Restart failed: old instance would not stop."; return 1; }

    # Test（非托管）：nohup 拉起本目录实例；查不到 launchctl → 退化为
    # ${JM_LAUNCHD_GRACE:-5}s 观察窗判断（非 mac 宿主）。
    local md=0
    launchd_managed || md=$?
    if [[ "$md" -eq 0 ]]; then
      log_info "launchd ($LAUNCHD_LABEL) KeepAlive owns respawn — waiting for it; never starting a second instance."
    elif [[ "$md" -eq 1 ]]; then
      log_info "Not launchd-managed (label $LAUNCHD_LABEL not loaded) — starting via nohup."
      start_service || { log_error "Restart failed: start failed."; return 1; }
    else
      local grace="${JM_LAUNCHD_GRACE:-5}" i respawned=""
      for ((i = 0; i < grace * 2; i++)); do
        while IFS= read -r pid; do
          if [[ -n "$pid" ]]; then
            if [[ "$old_pids" != *" $pid "* ]]; then respawned="$pid"; break 2; fi
          fi
        done < <(confirmed_server_pids)
        sleep 0.5
      done
      if [[ -n "$respawned" ]]; then
        log_info "Instance respawned externally (launchd KeepAlive, pid $respawned) — not starting a second one."
      else
        start_service || { log_error "Restart failed: start failed."; return 1; }
      fi
    fi
  fi

  # 健康检查不通过就不算重启完成——否则卡死的服务也会被报成「重启完成」。
  log_info "Waiting for health check (GET /health) …"
  if wait_health; then
    local now; now="$(confirmed_server_pids | head -n 1)"
    log_ok "Restarted.  pid ${now:-unknown}  →  http://localhost:$PORT"
    return 0
  fi
  log_error "Restart failed: /health not passing after ${JM_HEALTH_WAIT:-15}s."
  return 1
}

cmd_status() {
  local pid="" health="not responding"
  if is_running; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  fi
  if [[ -z "${pid:-}" ]]; then
    pid="$(confirmed_server_pids | head -n 1)"   # launchd 拉起的实例无 pidfile
  fi
  if [[ -n "${pid:-}" ]]; then
    if command -v curl &>/dev/null; then
      curl -sf --max-time 3 "http://127.0.0.1:$PORT/health" &>/dev/null && health="OK" || true
      [[ "$health" != "OK" ]] && health="FAILED"
    fi
  fi
  local state="not running"
  if [[ "$health" == "OK" ]]; then
    state="running"
    [[ -n "${pid:-}" ]] && state="running (PID $pid)"
  elif [[ -n "${pid:-}" ]]; then
    state="running (PID $pid)"
  fi
  echo -e "${CYAN}┌─ $SERVICE (physical) · port $PORT ─────────────────${NC}"
  box_line "Status"  "$state"
  box_line "URL"     "http://localhost:$PORT"
  box_line "Health"  "$health"
  box_line "Public"  "https://deanchen.me/jiangshan-map/ (GitHub Pages, upstream repo)"
  box_line "Log"     "${LOGFILE#$SCRIPT_DIR/}"
  # 托管形态只在托管时显示（Test 本目录跑不占行）。
  if system_managed; then box_line "托管" "LaunchDaemon (system)"; fi
  echo -e "${CYAN}└──────────────────────────────────────────────────${NC}"
  # 全绿才 exit 0：未运行或健康失败 → 非零（监控依赖）
  [[ -n "${pid:-}" && "$health" == "OK" ]] || return 1
}

cmd_logs() {
  [[ -f "$LOGFILE" ]] || { log_warn "No log yet: $LOGFILE"; exit 0; }
  log_info "Tailing $LOGFILE (Ctrl-C to exit) …"
  tail -f "$LOGFILE"
}

# ── install-daemon / uninstall-daemon：生产托管显式安装（需 root 执行打印的命令）──
# 防呆是本命令的核心：先判章——Test 机（无部署章）一律拒绝——Test 绝不托管
# 给系统（2026-11-13 规约）；有章才查 plist 模板并打印准确 sudo 指令。
cmd_install_daemon() {
  if is_prod_instance; then
    local src="$SCRIPT_DIR/deploy/$LAUNCHD_LABEL.plist"
    [[ -f "$src" ]] || { log_error "Missing plist template $src"; exit 1; }
    log_ok "生产实例（部署章在身）。安装命令（需 root，可用 ! 前缀执行）："
    echo "  sudo install -o root -g wheel -m 644 '$src' /Library/LaunchDaemons/$LAUNCHD_LABEL.plist"
    echo "  sudo launchctl bootstrap system /Library/LaunchDaemons/$LAUNCHD_LABEL.plist"
    log_info "托管后：restart 免 sudo（kill+KeepAlive）；真正停用用 sudo bootout 或 ./manage.sh stop。"
  else
    log_error "拒绝安装：本目录无部署章（config/env ≠ production）——这是 Test 检出，Test 不托管给系统。"
    log_error "生产副本由 deploy-local 盖章；盖章后在生产副本上执行本命令。"
    exit 1
  fi
}

cmd_uninstall_daemon() {
  if is_prod_instance; then
    log_ok "生产机卸载托管命令（需 root）："
    echo "  sudo launchctl bootout system/$LAUNCHD_LABEL 2>/dev/null"
    echo "  sudo rm /Library/LaunchDaemons/$LAUNCHD_LABEL.plist"
    log_info "卸载后本目录 ./manage.sh start 即回到 Test 形态（nohup）。"
  else
    log_error "本目录无部署章（Test 检出本就不该有托管），无需卸载。"
    exit 1
  fi
}

cmd_deploy() {
  local dry_run=false
  while [[ $# -gt 0 ]]; do case "$1" in -d|--dry-run) dry_run=true;; *) log_error "Unknown opt: $1"; exit 1;; esac; shift; done
  local cfg="$SCRIPT_DIR/config/deploy.cfg"
  [[ -f "$cfg" ]] || { log_error "config/deploy.cfg not found. Copy from .example."; exit 1; }
  local env_val
  env_val="$(grep '^env' "$cfg" | head -1 | cut -d '=' -f2 | xargs || true)"
  [[ "$env_val" == production || "$env_val" == test ]] || { log_error "deploy.cfg: env must be production or test"; exit 1; }
  refuse_if_prod_source && exit 1
  local branch; branch="$(git -C "$SCRIPT_DIR" branch --show-current)"
  [[ -n "$branch" ]] || { log_error "detached HEAD — checkout a branch first."; exit 1; }

  # 1. 只发布已提交内容
  if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
    log_error "工作区有未提交改动——先 commit 再 deploy（deploy 只发布已提交内容）"
    git -C "$SCRIPT_DIR" status --porcelain | head -5
    exit 1
  fi

  # 2. 发布闸：零依赖校验套件全绿才推
  local node_bin; node_bin="$(pick_node)"
  [[ -n "$node_bin" ]] || { log_error "node 不可用——发布前验证（scripts/validate_atlas.js）无法执行"; exit 1; }
  if [[ "$dry_run" == true ]]; then
    log_info "DRY RUN ($env_val): 验证 ✓ → git push origin $branch（koven2049/jiangshan-map）"
    return 0
  fi
  log_step "发布闸：node scripts/validate_atlas.js …"
  "$node_bin" scripts/validate_atlas.js \
    || { log_error "验证未通过——不发布"; exit 1; }

  # 3. 发布：唯一目标 = origin（koven2049 fork），不推任何其他仓
  log_step "推送 origin（koven2049/jiangshan-map）…"
  git -C "$SCRIPT_DIR" push origin "$branch" || { log_error "推 origin 失败"; exit 1; }
  log_ok "已发布 → origin（koven2049/jiangshan-map）。"
}

cmd_deploy_local() {
  # 同机部署正门：本机开发 = 本机生产（mini 常态）。不走 SSH、不查
  # deploy-check（它拦的就是"目标=本机"，那是给跨机 deploy 防配置错指的）。
  local dry_run=false target=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dry-run) dry_run=true ;;
      -*) log_error "Unknown opt: $1"; exit 1 ;;
      *) [[ -n "$target" ]] && { log_error "多余的参数: $1"; exit 1; }; target="$1" ;;
    esac; shift
  done
  target="${target:-$HOME/Services/$(basename "$SCRIPT_DIR")}"
  local excl="$SCRIPT_DIR/.rsync-exclude"
  [[ -f "$excl" ]] || { log_error ".rsync-exclude missing — refusing bare --delete deploy."; exit 1; }
  [[ -d "$target" ]] || { log_error "目标目录不存在: ${target}（不自动创建，防拼错路径静默部署；确认后 mkdir -p）"; exit 1; }
  [[ "$(cd "$target" && pwd)" == "$SCRIPT_DIR" ]] && { log_error "目标与源目录相同，拒绝执行"; exit 1; }
  refuse_if_prod_source && exit 1
  local args=(-avz --delete --exclude-from="$excl")
  [[ "$dry_run" == true ]] && args+=(--dry-run)
  log_info "Deploying (local) → ${target} …"
  rsync "${args[@]}" "$SCRIPT_DIR/" "$target/"
  if [[ "$dry_run" == true ]]; then
    log_warn "Dry-run only — 检查列表里不得出现 data/ logs/ config/*.cfg，确认后去掉 -d 正式部署"
  else
    # 部署盖章（唯一写入点，每次部署重盖）
    mkdir -p "$target/config"; echo production > "$target/config/env"
    log_ok "Deploy complete (code only). 本机执行: cd ${target} && ./manage.sh init && ./manage.sh restart"
  fi
}

pick_node() {
  local c
  for c in "$(command -v node 2>/dev/null)" "$HOME"/.nvm/versions/node/*/bin/node; do
    [[ -x "$c" ]] && { echo "$c"; return; }
  done
  echo ""
}

usage() {
  cat <<EOF
${SERVICE} (physical) — interactive historical atlas of China (static site)

Serves the repo root over HTTP from this directory (port $PORT). Deploy runs
entirely in this directory — validate, then push origin
(koven2049/jiangshan-map, the only publish target). Nothing is transferred
to any machine; no other remote is fetched or pushed.

Dual form: production (mini ~/Services copy, deploy-stamped) runs under a
system LaunchDaemon; a Test checkout (no stamp) runs under nohup in this
directory and is never installed into launchd.

Usage: ./manage.sh <command> [options]

Commands:
  init      Create run/ dir and config/deploy.cfg.example
  start     Start local static server on port $PORT (idempotent; managed:
            no-op; stamped: bootstrap back into launchd)
  stop      Stop server (managed: svc-ctl bootout real stop; test: SIGTERM
            → SIGKILL, confirmed-identity pids only)
  restart   stop + start (managed: kill + KeepAlive respawn; /health gates
            exit 0)
  status    Process + /health probe (exit 0 only when fully green)
  logs      Tail server.log
  deploy [-d]  Validate → push origin (koven2049/jiangshan-map); refuses a
            production-stamped source
  deploy-local [-d] [path]  Rsync code to local prod dir (same-machine dev);
            default $HOME/Services/<repo-name>; -d dry-run; stamps the target
  install-daemon  Print sudo commands to install the LaunchDaemon from
            deploy/<label>.plist (production-stamped dirs only; Test refused)
  uninstall-daemon  Print sudo commands to unload and remove the daemon
  help      Show this help

Examples:
  ./manage.sh start
  ./manage.sh deploy -d
EOF
}

main() {
  local cmd="${1:-}"; [[ $# -gt 0 ]] && shift || true
  case "$cmd" in
    init) cmd_init;; start) cmd_start;; stop) cmd_stop;; restart) cmd_restart;;
    status) cmd_status;; logs) cmd_logs "$@";; deploy) cmd_deploy "$@";; deploy-local) cmd_deploy_local "$@";;
    install-daemon) cmd_install_daemon;; uninstall-daemon) cmd_uninstall_daemon;;
    help|--help|-h) usage;;
    "") usage; exit 1;;
    *) log_error "Unknown command: $cmd"; usage; exit 1;;
  esac
}
main "$@"
