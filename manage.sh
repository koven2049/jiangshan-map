#!/usr/bin/env bash
set -euo pipefail
# manage.sh (physical) for jiangshan-map — static atlas site, pidfile + nohup.
# Local serve: python3 server.py (repo root over HTTP, /health on port 8930).
# Deploy = zero-transfer, run entirely in this directory:
#   validate (node) → sync koven2049 fork (origin) → publish upstream
#   (DeanChensj/jiangshan-map is the GitHub Pages source of deanchen.me).

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

cmd_start() {
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

cmd_restart() { log_step "Restarting $SERVICE …"; cmd_stop || true; cmd_start; }

cmd_status() {
  local pid="" health="not responding"
  if is_running; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
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

  # 2. 同步上游：本地只发布包含 upstream/main 最新提交的内容
  git -C "$SCRIPT_DIR" fetch origin -q
  git -C "$SCRIPT_DIR" fetch upstream -q
  local behind
  behind="$(git -C "$SCRIPT_DIR" rev-list --count "$branch..upstream/main")"
  if (( behind > 0 )); then
    if [[ "$dry_run" == true ]]; then
      log_info "DRY RUN: upstream 有 $behind 个新提交，将先 merge upstream/main 再发布"
    else
      log_step "上游有 $behind 个新提交，先 merge upstream/main …"
      git -C "$SCRIPT_DIR" merge upstream/main --no-edit \
        || { log_error "合并冲突——解决后 commit，再重跑 ./manage.sh deploy"; exit 1; }
    fi
  fi

  # 3. 发布闸：零依赖校验套件全绿才推
  local node_bin; node_bin="$(pick_node)"
  [[ -n "$node_bin" ]] || { log_error "node 不可用——发布前验证（scripts/validate_atlas.js）无法执行"; exit 1; }
  if [[ "$dry_run" == true ]]; then
    log_info "DRY RUN ($env_val): 验证 ✓ → git push origin $branch（koven2049 同步）→ git push upstream $branch（发布 deanchen.me）"
    return 0
  fi
  log_step "发布闸：node scripts/validate_atlas.js …"
  "$node_bin" scripts/validate_atlas.js \
    || { log_error "验证未通过——不发布"; exit 1; }

  # 4. 双推：origin 同步 + upstream 发布
  log_step "推送 origin（koven2049 同步）…"
  git -C "$SCRIPT_DIR" push origin "$branch" || { log_error "推 origin 失败"; exit 1; }
  log_step "推送 upstream（发布 deanchen.me）…"
  local push_err=/tmp/jiangshan-map-push.err
  if ! git -C "$SCRIPT_DIR" push upstream "$branch" 2>"$push_err"; then
    if grep -q "Permission to\|publickey\|denied" "$push_err"; then
      log_error "推 upstream 被拒：DeanChensj 的推送公钥还没配置（一次性设置）。"
      log_error "把下面这把公钥加到 GitHub → DeanChensj/jiangshan-map → Settings → Deploy keys，勾选 Allow write access："
      echo "    $(cat "$HOME/.ssh/jiangshan_map_deploy.pub" 2>/dev/null || echo '<~/.ssh/jiangshan_map_deploy.pub 不存在>')"
    else
      log_error "推 upstream 失败：$(tail -2 "$push_err")"
    fi
    rm -f "$push_err"
    exit 1
  fi
  rm -f "$push_err"
  log_ok "已发布 → https://deanchen.me/jiangshan-map/（Pages 构建约 1 分钟后生效）；origin 已同步。"
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

Serves the repo root over HTTP from this directory (port $PORT). Publishes
to https://deanchen.me/jiangshan-map/ via GitHub Pages: deploy runs entirely
in this directory — validate, sync the koven2049 fork (origin), push the
upstream repo DeanChensj/jiangshan-map (the Pages source). Nothing is
transferred to any machine.

Usage: ./manage.sh <command> [options]

Commands:
  init      Create run/ dir and config/deploy.cfg.example
  start     Start local static server on port $PORT (idempotent)
  stop      Stop server (SIGTERM → SIGKILL)
  restart   stop + start
  status    Process + /health probe (exit 0 only when fully green)
  logs      Tail server.log
  deploy [-d]  Validate → merge upstream → push origin (sync) + upstream (publish)
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
    status) cmd_status;; logs) cmd_logs "$@";; deploy) cmd_deploy "$@";;
    help|--help|-h) usage;;
    "") usage; exit 1;;
    *) log_error "Unknown command: $cmd"; usage; exit 1;;
  esac
}
main "$@"
