#!/usr/bin/env bash
set -euo pipefail
# manage.sh (physical) for jiangshan-map — static atlas site, pidfile + nohup.
# Local serve: python3 server.py (repo root over HTTP, /health on port 8930).
# Publish: the public site is GitHub Pages on DeanChensj/jiangshan-map
# (deanchen.me/jiangshan-map); deploy here syncs the mini mirror + pushes
# the koven2049 fork — the Pages release itself happens on the upstream side.

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
  local env_val ssh_target remote_path
  env_val="$(grep '^env' "$cfg" | head -1 | cut -d '=' -f2 | xargs || true)"
  ssh_target="$(grep '^ssh_target' "$cfg" | head -1 | cut -d '=' -f2 | xargs || true)"
  remote_path="$(grep '^remote_path' "$cfg" | head -1 | cut -d '=' -f2 | xargs || true)"
  [[ "$env_val" == production || "$env_val" == test ]] || { log_error "deploy.cfg: env must be production or test"; exit 1; }
  [[ -n "${ssh_target:-}" && -n "${remote_path:-}" ]] || { log_error "ssh_target/remote_path missing in deploy.cfg"; exit 1; }
  _check_deploy_target "$ssh_target" || exit 1
  local branch; branch="$(git -C "$SCRIPT_DIR" branch --show-current)"
  [[ -n "$branch" ]] || { log_error "detached HEAD — checkout a branch first."; exit 1; }
  if [[ "$dry_run" == true ]]; then
    log_info "DRY RUN ($env_val):"
    log_info "  1. git push origin $branch  (koven2049 fork — Pages release is on the upstream side)"
    log_info "  2. ssh $ssh_target 'cd $remote_path && git pull --ff-only'"
    return 0
  fi
  log_step "Deploying ($env_val): push $branch → origin, sync mirror …"
  git -C "$SCRIPT_DIR" push origin "$branch"
  ssh "$ssh_target" "cd '$remote_path' && git pull --ff-only" \
    || { log_error "Mirror sync failed on $ssh_target."; exit 1; }
  log_ok "Deploy complete. (Public site https://deanchen.me/jiangshan-map/ is published from the upstream repo, not this push.)"
}

usage() {
  cat <<EOF
${SERVICE} (physical) — interactive historical atlas of China (static site)

Serves the repo root over HTTP for local use and ops-dashboard probing; the
public deployment is GitHub Pages (deanchen.me/jiangshan-map) from the
upstream repo DeanChensj/jiangshan-map — this checkout tracks it as 'upstream'
and pushes to the koven2049 fork ('origin').

Usage: ./manage.sh <command> [options]

Commands:
  init      Create run/ dir and config/deploy.cfg.example
  start     Start local static server on port $PORT (idempotent)
  stop      Stop server (SIGTERM → SIGKILL)
  restart   stop + start
  status    Process + /health probe (exit 0 only when fully green)
  logs      Tail server.log
  deploy [-d]  Push branch to origin + git pull the mini mirror (per config/deploy.cfg)
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
