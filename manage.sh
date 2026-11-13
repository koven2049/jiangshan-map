#!/usr/bin/env bash
set -euo pipefail
# manage.sh (physical) for jiangshan-map — static atlas site, pidfile + nohup;
# mini 上由 system LaunchDaemon com.koven.jiangshan-map 托管时自动切到 launchd 分支。
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

START_CMD=("$PY" server.py)
# ────────────────────────────────────────────────────────────────────────────

is_running() {
  [[ -f "$PIDFILE" ]] || return 1
  local pid; pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
}

box_line() { printf '│ %-9s : %s\n' "$1" "$2"; }

cmd_init() {
  log_step "Initializing $SERVICE …"
  command -v "$PY" &>/dev/null || { log_error "python3 not found."; exit 1; }
  mkdir -p "$SCRIPT_DIR/run"
  if [[ ! -f "$SCRIPT_DIR/config/deploy.cfg.example" ]]; then
    mkdir -p "$SCRIPT_DIR/config"
    cat > "$SCRIPT_DIR/config/deploy.cfg.example" <<'EOF'
env = production
ssh_target = admin@ts-macmini-m4
remote_path = /Users/admin/Documents/workspace/ai/ai-projects/jiangshan-map
EOF
    log_info "Created config/deploy.cfg.example — copy to config/deploy.cfg and edit."
  fi
  log_ok "Init complete."
}

# ── system LaunchDaemon 托管（mini 生产，见 ~/Services/README）：不 nohup，start/stop/restart 走 launchd ──
LAUNCHD_LABEL="com.koven.jiangshan-map"
under_launchd() { [[ -f "/Library/LaunchDaemons/${LAUNCHD_LABEL}.plist" ]]; }
launchd_pid() { launchctl print "system/$LAUNCHD_LABEL" 2>/dev/null | sed -n 's/^[[:space:]]*pid = \([0-9]*\)$/\1/p' | head -1; }
launchd_cmd() {
  local pid n i; pid="$(launchd_pid)"
  case "$1" in
    start)
      [[ -n "$pid" ]] && { log_ok "launchd 托管中 (pid $pid)"; return 0; }
      log_error "launchd 托管但未运行: ! sudo launchctl kickstart -k system/$LAUNCHD_LABEL"; return 1 ;;
    stop)
      log_warn "launchd KeepAlive 托管, kill 会被拉起。真正停用: ! sudo launchctl bootout system/$LAUNCHD_LABEL"; return 0 ;;
    restart)
      [[ -n "$pid" ]] || { launchd_cmd start; return; }
      kill -TERM "$pid" 2>/dev/null || true
      for i in $(seq 1 25); do
        sleep 1; n="$(launchd_pid)"
        [[ -n "$n" && "$n" != "$pid" ]] && { log_ok "launchd 已重启 (pid $n)"; return 0; }
      done
      log_error "launchd 25s 内未拉起, 查 launchctl print system/$LAUNCHD_LABEL"; return 1 ;;
  esac
}

cmd_start() {
  if under_launchd; then launchd_cmd start; return; fi
  if is_running; then log_ok "Already running (pid $(cat "$PIDFILE")) — idempotent, exit 0"; exit 0; fi
  mkdir -p "$SCRIPT_DIR/run"
  rm -f "$PIDFILE"
  log_step "Starting $SERVICE on port $PORT …"
  nohup "${START_CMD[@]}" >>"$LOGFILE" 2>&1 &
  echo $! >"$PIDFILE"; sleep 1
  if is_running; then
    log_ok "Started.  pid $(cat "$PIDFILE")  →  http://localhost:$PORT"
  else
    log_error "Failed to start. See $LOGFILE"; rm -f "$PIDFILE"; exit 1
  fi
}

cmd_stop() {
  if under_launchd; then launchd_cmd stop; return; fi
  [[ -f "$PIDFILE" ]] || { log_warn "No pidfile; nothing to stop."; return 0; }
  local pid; pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    log_step "Stopping (pid $pid) …"; kill -TERM "$pid" || true; sleep 2
    kill -0 "$pid" 2>/dev/null && { log_warn "SIGKILL …"; kill -KILL "$pid" || true; }
    log_ok "Stopped."
  else
    log_warn "Process not running."
  fi
  rm -f "$PIDFILE"
}

cmd_restart() {
  log_step "Restarting $SERVICE …"
  if under_launchd; then launchd_cmd restart; return; fi
  cmd_stop || true; cmd_start
}

cmd_status() {
  local pid="" health="not responding"
  if under_launchd; then pid="$(launchd_pid)"; elif is_running; then pid="$(cat "$PIDFILE" 2>/dev/null || true)"; fi
  if [[ -n "${pid:-}" ]]; then
    if command -v curl &>/dev/null; then
      curl -s --max-time 3 "http://127.0.0.1:$PORT/health" &>/dev/null && health="OK" || health="FAILED"
    fi
  fi
  local state; [[ -n "${pid:-}" ]] && state="running (PID $pid)" || state="not running"
  echo -e "${CYAN}┌─ $SERVICE (physical) · port $PORT ─────────────────${NC}"
  box_line "Status"  "$state"
  box_line "URL"     "http://localhost:$PORT"
  box_line "Health"  "$health"
  box_line "Public"  "https://deanchen.me/jiangshan-map/ (GitHub Pages, upstream repo)"
  box_line "Log"     "${LOGFILE#$SCRIPT_DIR/}"
  echo -e "${CYAN}└──────────────────────────────────────────────────${NC}"
  [[ -n "${pid:-}" && "$health" == "OK" ]] || return 1
}

cmd_logs() {
  [[ -f "$LOGFILE" ]] || { log_warn "No log yet: $LOGFILE"; exit 0; }
  log_info "Tailing $LOGFILE (Ctrl-C to exit) …"
  tail -f "$LOGFILE"
}

cmd_deploy() {
  local dry_run=false
  while [[ $# -gt 0 ]]; do case "$1" in -d|--dry-run) dry_run=true;; *) log_error "Unknown opt: $1"; exit 1;; esac; shift; done
  local cfg="$SCRIPT_DIR/config/deploy.cfg"
  [[ -f "$cfg" ]] || { log_error "config/deploy.cfg not found. Copy from .example."; exit 1; }
  local env_val
  env_val="$(grep '^env' "$cfg" | head -1 | cut -d '=' -f2 | xargs || true)"
  [[ "$env_val" == production || "$env_val" == test ]] || { log_error "deploy.cfg: env must be production or test"; exit 1; }
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
  local args=(-avz --delete --exclude-from="$excl")
  [[ "$dry_run" == true ]] && args+=(--dry-run)
  log_info "Deploying (local) → ${target} …"
  rsync "${args[@]}" "$SCRIPT_DIR/" "$target/"
  if [[ "$dry_run" == true ]]; then
    log_warn "Dry-run only — 检查列表里不得出现 data/ logs/ config/*.cfg，确认后去掉 -d 正式部署"
  else
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

Usage: ./manage.sh <command> [options]

Commands:
  init      Create run/ dir and config/deploy.cfg.example
  start     Start local static server on port $PORT (idempotent)
  stop      Stop server (SIGTERM → SIGKILL)
  restart   stop + start
  status    Process + /health probe (exit 0 only when fully green)
  logs      Tail server.log
  deploy [-d]  Validate → push origin (koven2049/jiangshan-map)
  deploy-local [-d] [path]  Rsync code to local prod dir (same-machine dev);
              default $HOME/Services/<repo-name>; -d dry-run
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
    help|--help|-h) usage;;
    "") usage; exit 1;;
    *) log_error "Unknown command: $cmd"; usage; exit 1;;
  esac
}
main "$@"
