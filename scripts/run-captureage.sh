#!/usr/bin/env bash
#
# run-captureage.sh — launch the CaptureAge spectator app under CrossOver/Wine
# on Apple Silicon Macs, working around the Electron/Chromium GPU-surface
# crash-loop, and keep the fix in place across CaptureAge's auto-updates.
#
# Why this exists
# ---------------
# CaptureAge is an Electron app. Its demanding *native* game-world renderer
# (D3D11 -> DXVK -> Vulkan -> Metal) runs fine under CrossOver, but Chromium's
# separate GPU process cannot create an on-screen surface for a window that
# belongs to another Wine process. The GPU process dies with:
#
#     ERROR:skia_output_device_gl.cc ... Couldn't create surface
#
# and the window crash-loops before the UI ever appears. The fix is a Chromium
# launch flag that keeps Chromium's UI compositor off that path. Nothing is
# installed or patched — this is a pure launch-flag fix.
#
# CaptureAge updates itself on start. After an update it relaunches itself
# WITHOUT our flag (you get a blank white window). This script therefore keeps
# watching for a while after launch: if a CaptureAge instance without the flag
# shows up, it closes only CaptureAge's processes and starts it again with the
# flag.
#
# This script does NOT modify, repackage, or redistribute CaptureAge. It only
# launches the copy you installed, with the right flags. Install CaptureAge
# yourself from https://captureage.com/ first.
#
# Usage
# -----
#   ./run-captureage.sh                        # launch + watchdog (--in-process-gpu)
#   CA_MODE=disable-gpu ./run-captureage.sh    # fallback mode (see README)
#   CA_DEBUG=1 ./run-captureage.sh             # verbose Electron logging
#   CA_BOTTLE="My Bottle" ./run-captureage.sh  # other CrossOver bottle
#   CA_DRY_RUN=1 ./run-captureage.sh           # print the command, run nothing
#   CA_WATCH=0 ./run-captureage.sh             # launch only, no watchdog
#
# Environment overrides
# ---------------------
#   CA_BOTTLE     CrossOver bottle that contains CaptureAge
#                 (default: "Age of Empires II Definitive Edition")
#   CA_EXE        Windows path to CaptureAge.exe inside the bottle
#   CA_CROSSOVER  Path to CrossOver.app (default: /Applications/CrossOver.app)
#   CA_MODE       in-process-gpu (default) | disable-gpu | swiftshader |
#                 disable-gpu-compositing
#   CA_DEBUG      1 = pass --enable-logging and ELECTRON_ENABLE_LOGGING=1
#   CA_DRY_RUN    1 = print the resolved command and exit
#   CA_WATCH      1 (default) = run the updater watchdog; 0 = launch and exit
#   CA_WATCH_SECS how long the watchdog runs after the last (re)launch (default 900)
#   CA_MAX_RELAUNCH  max. watchdog relaunches per run (default 3)
#   CA_LOG        file for launcher + wine output (default ~/Library/Logs/CaptureAge-fixed.log)
#
set -euo pipefail

# --- Configuration (override via environment) -------------------------------
CA_BOTTLE="${CA_BOTTLE:-Age of Empires II Definitive Edition}"
CA_CROSSOVER="${CA_CROSSOVER:-/Applications/CrossOver.app}"
CA_MODE="${CA_MODE:-in-process-gpu}"
CA_EXE_DEFAULT='C:/users/crossover/AppData/Local/Programs/CaptureAge/CaptureAge.exe'
CA_EXE="${CA_EXE:-$CA_EXE_DEFAULT}"
CA_WATCH="${CA_WATCH:-1}"
CA_WATCH_SECS="${CA_WATCH_SECS:-900}"
CA_MAX_RELAUNCH="${CA_MAX_RELAUNCH:-3}"
CA_LOG="${CA_LOG:-$HOME/Library/Logs/CaptureAge-fixed.log}"
# Trebuchet prototype (dxmt-label 2026-11-23): CA_URL = argument passed to CaptureAge (captureage://spectate/...),
# CA_WATCH_ONLY=1 = do not launch, only fix flagless instances (in-game "Spectate with CA" button) while CA_WATCH_PID lives,
# CA_RUNTIME = path part that must appear in CaptureAge's mapped files (e.g. SoftFault-CrossOver.app); others are restarted.
CA_URL="${CA_URL:-}"; CA_WATCH_ONLY="${CA_WATCH_ONLY:-0}"; CA_WATCH_PID="${CA_WATCH_PID:-}"; CA_RUNTIME="${CA_RUNTIME:-}"
# Trebuchet (CA_TREBUCHET=1): watch until CaptureAge quits (no 15-min limit; the launcher shows "running" meanwhile);
# CA_RESTART=1 closes a running CaptureAge first; CA_REPORT = file for one line per button restart.
CA_TREBUCHET="${CA_TREBUCHET:-0}"; CA_RESTART="${CA_RESTART:-0}"; CA_REPORT="${CA_REPORT:-}"
(( CA_TREBUCHET )) && CA_WATCH_SECS=31536000
POLL=3            # seconds between watchdog checks
CONFIRM=2         # an unflagged instance must be seen this many polls in a row

# Process pattern. ANCHORED on purpose: Wine shows Windows processes with their
# Windows path as argv[0] ("C:\users\crossover\...\CaptureAge\CaptureAge.exe").
# An unanchored pattern would also match any shell or tool whose command line
# merely mentions CaptureAge (including this script) and kill it. "." matches
# both "\" and "/". It matches CaptureAge.exe in its install folder and nothing
# else: never wineserver, AoE2, Steam, CaptureAge's updater (runs from Temp) or
# "Uninstall CaptureAge.exe" (the updater runs it while it installs).
CA_PATTERN="${CA_PATTERN:-^$(printf '%s' "$CA_EXE" | sed 's/[][(){}+*?|^$.]/./g; s/[\/\\]/./g')( |\$)}"

die() {
  printf '%s\n' "$@" >&2
  if [[ ! -t 2 && "${CA_NO_DIALOG:-0}" != "1" ]]; then
    /usr/bin/osascript -e 'on run argv' -e 'display alert "CaptureAge (fixed)" message (item 1 of argv) as critical' -e 'end run' "$(printf '%s\n' "$@")" >/dev/null 2>&1 || true
  fi
  exit 1
}
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# --- Pick the compositor-workaround flags -----------------------------------
# All modes keep CaptureAge's native game-world renderer hardware-accelerated
# (it uses its own D3D11 device, not Chromium's GPU process); they only change
# how Chromium composites the lightweight HTML/React UI.
case "$CA_MODE" in
  in-process-gpu)
    # Default. Verified on 1.26.0: Chromium runs its GPU work as a thread of
    # the main process, which owns the window, so the Metal surface can be
    # attached. UI renders with GPU compositing.
    GPU_FLAGS=(--in-process-gpu) ;;
  disable-gpu)
    # Fallback. Chromium drops its GPU process and composites in software.
    # Verified on 1.13.0; on 1.26.0 the window stays blank white.
    GPU_FLAGS=(--disable-gpu) ;;
  swiftshader)
    GPU_FLAGS=(--use-angle=swiftshader) ;;
  disable-gpu-compositing)
    GPU_FLAGS=(--disable-gpu-compositing) ;;
  *)
    die "error: unknown CA_MODE '$CA_MODE' (use in-process-gpu | disable-gpu | swiftshader | disable-gpu-compositing)" ;;
esac
FIX_FLAG="${GPU_FLAGS[0]}"   # the watchdog looks for this flag

EXTRA_FLAGS=()
if [[ "${CA_DEBUG:-0}" == "1" ]]; then
  export ELECTRON_ENABLE_LOGGING=1
  EXTRA_FLAGS+=(--enable-logging)
fi
export CX_GRAPHICS_BACKEND="${CX_GRAPHICS_BACKEND:-dxvk}"

WINE="$CA_CROSSOVER/Contents/SharedSupport/CrossOver/bin/wine"
build_cmd() { CMD=("$WINE" --no-update --bottle "$CA_BOTTLE" "$CA_EXE" "${GPU_FLAGS[@]}" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}); [[ -n "$CA_URL" ]] && CMD+=("$CA_URL"); return 0; }
build_cmd

if [[ "${CA_DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY RUN — would execute:\n  CX_GRAPHICS_BACKEND=%s' "$CX_GRAPHICS_BACKEND"
  [[ "${CA_DEBUG:-0}" == "1" ]] && printf ' ELECTRON_ENABLE_LOGGING=1'
  printf ' \\\n  '; printf '%q ' "${CMD[@]}"; printf '\n'
  printf '  watchdog: %s (pattern %s, flag %s, %ss, max %s relaunches)\n' \
    "$([[ $CA_WATCH == 1 ]] && echo on || echo off)" "$CA_PATTERN" "$FIX_FLAG" "$CA_WATCH_SECS" "$CA_MAX_RELAUNCH"
  exit 0
fi

# --- Sanity checks ----------------------------------------------------------
if [[ ! -x "$WINE" ]]; then
  die "error: CrossOver 'wine' not found at: $WINE" \
      "Install CrossOver or set CA_CROSSOVER to your CrossOver.app."
fi
BOTTLE_DIR="$HOME/Library/Application Support/CrossOver/Bottles/$CA_BOTTLE"
if [[ ! -d "$BOTTLE_DIR" ]]; then
  die "error: CrossOver bottle not found: $BOTTLE_DIR" \
      "Set CA_BOTTLE to the bottle where you installed CaptureAge."
fi
EXE_HOST="$BOTTLE_DIR/drive_c/${CA_EXE#C:/}"
if [[ ! -f "$EXE_HOST" ]]; then
  echo "warning: CaptureAge.exe not found at $EXE_HOST — trying anyway." >&2
fi

# --- Process helpers (anchored pattern only) --------------------------------
ca_lines() { pgrep -fl "$CA_PATTERN" 2>/dev/null || true; }   # "pid command..."
ca_count() { ca_lines | grep -c . || true; }
ca_has_flag() { ca_lines | grep -Eq -- " ${FIX_FLAG}( |\$)"; }
# 0 = every CaptureAge.exe maps files from CA_RUNTIME (or no CA_RUNTIME given)
ca_in_runtime() {
  [[ -z "$CA_RUNTIME" ]] && return 0
  local p
  for p in $(pgrep -f "$CA_PATTERN" 2>/dev/null); do
    /usr/sbin/lsof -Fn -p "$p" 2>/dev/null | grep -qF "$CA_RUNTIME" || return 1
  done
  return 0
}
ca_url_seen() { ca_lines | grep -oE 'captureage://[^ ]+' | head -1; }

# Close CaptureAge's processes only: TERM, wait, then KILL what is left.
ca_kill() {
  local pids; pids="$(pgrep -f "$CA_PATTERN" || true)"
  [[ -z "$pids" ]] && return 0
  log "closing CaptureAge processes: $(echo $pids)"
  pkill -TERM -f "$CA_PATTERN" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ "$(ca_count)" == 0 ]] && return 0
    sleep 1
  done
  pkill -KILL -f "$CA_PATTERN" || true
  sleep 1
}

launch() {
  log "launching CaptureAge (mode $CA_MODE, flags: ${GPU_FLAGS[*]} ${EXTRA_FLAGS[*]-})"
  # Detached from this script: the watchdog may exit while CaptureAge runs on.
  # Run from the log folder: DXVK writes CaptureAge_d3d11.log into the cwd.
  ( cd "$(dirname "$CA_LOG")" && nohup "${CMD[@]}" >>"$CA_LOG" 2>&1 </dev/null & )
}

mkdir -p "$(dirname "$CA_LOG")"
# When run from a terminal, show output there and keep a copy in the log.
if [[ -t 1 ]]; then
  exec > >(tee -a "$CA_LOG") 2>&1
else
  exec >>"$CA_LOG" 2>&1
fi
log "---- run-captureage.sh (bottle: $CA_BOTTLE) ----"

# --- Already running? -------------------------------------------------------
if [[ "$CA_WATCH_ONLY" != "1" && "$CA_RESTART" == "1" && "$(ca_count)" -gt 0 ]]; then
  u="$(ca_url_seen)"; [[ -z "$CA_URL" && -n "$u" ]] && { CA_URL="$u"; build_cmd; }
  log "restart requested: closing the running CaptureAge"; ca_kill
fi
if [[ "$CA_WATCH_ONLY" != "1" && "$(ca_count)" -gt 0 ]]; then
  if ca_has_flag && ca_in_runtime; then
    log "CaptureAge is already running with $FIX_FLAG — nothing to do."
    exit 0
  fi
  ca_in_runtime || log "CaptureAge runs outside the fixed runtime ($CA_RUNTIME) — restarting it."
  u="$(ca_url_seen)"; [[ -z "$CA_URL" && -n "$u" ]] && { CA_URL="$u"; build_cmd; }
  log "CaptureAge is running WITHOUT $FIX_FLAG (blank/crashing window) — restarting it."
  ca_kill
fi

if [[ "$CA_WATCH_ONLY" == "1" ]]; then
  log "watch-only: fixing flagless CaptureAge instances while pid ${CA_WATCH_PID:-?} lives"
  bad=0; relaunches=0
  while [[ -z "$CA_WATCH_PID" ]] || kill -0 "$CA_WATCH_PID" 2>/dev/null; do
    sleep "$POLL"
    if [[ "$(ca_count)" -gt 0 ]] && ! ca_has_flag; then bad=$((bad+1)); else bad=0; fi
    (( bad < CONFIRM )) && continue
    (( relaunches >= CA_MAX_RELAUNCH )) && { log "watch-only: $relaunches restarts — giving up"; exit 1; }
    u="$(ca_url_seen)"; CA_URL="${u:-}"; build_cmd
    log "watch-only: CaptureAge without $FIX_FLAG (${CA_URL:-no url}) — restarting with it"
    ca_kill; relaunches=$((relaunches+1)); launch; bad=0
    [[ -n "$CA_REPORT" ]] && echo "captureage: restarted with $FIX_FLAG (from the game's button${CA_URL:+, same captureage:// link})" >> "$CA_REPORT"
  done
  log "watch-only: game ended — stopping"; exit 0
fi

launch

if [[ "$CA_WATCH" != "1" ]]; then
  log "watchdog off (CA_WATCH=$CA_WATCH); done."
  exit 0
fi

# --- Updater watchdog -------------------------------------------------------
# States per poll:
#   no CaptureAge process      -> updater may be running, or the user quit
#   flagged process present    -> healthy
#   only unflagged processes   -> the updater relaunched it without the flag
log "watchdog: watching for ${CA_WATCH_SECS}s (pattern '$CA_PATTERN')"
relaunches=0
deadline=$(( $(date +%s) + CA_WATCH_SECS ))
seen=0          # we have seen CaptureAge running at least once
bad=0           # consecutive polls with only unflagged instances
gone=0          # consecutive polls with no instance at all
GONE_LIMIT=$(( 120 / POLL ))   # 2 min with nothing running (after seen) -> user quit
# Trebuchet: quit is seen after ~9 s, unless CaptureAge's updater/installer is busy (then the 2-min limit applies)
updater_busy() { pgrep -if '^C:.users.crossover.AppData.Local.(Temp.*captureage|Programs.CaptureAge.Uninstall CaptureAge)' >/dev/null 2>&1; }

while (( $(date +%s) < deadline )); do
  sleep "$POLL"
  n="$(ca_count)"
  if [[ "$n" == 0 ]]; then
    bad=0
    if (( seen )); then
      gone=$((gone + 1))
      if (( gone >= GONE_LIMIT )) || { (( CA_TREBUCHET && gone >= 3 )) && ! updater_busy; }; then
        log "watchdog: CaptureAge closed — stopping."
        exit 0
      fi
    fi
    continue
  fi
  seen=1; gone=0
  # Healthy = some CaptureAge.exe carries the flag and none is a fresh
  # unflagged relaunch by the updater ("--updated").
  if ca_has_flag && ! ca_lines | grep -Ev -- " ${FIX_FLAG}( |\$)" | grep -Eq -- ' --updated( |$)'; then
    bad=0
    continue
  fi
  bad=$((bad + 1))
  (( bad < CONFIRM )) && continue
  log "watchdog: CaptureAge running without $FIX_FLAG (likely relaunched by its updater):"
  # Log pids and the updater markers only (a full command line can be long).
  ca_lines | awk '{ m=""; for (i=2;i<=NF;i++) if ($i=="--installer"||$i=="--updated") m=m" "$i; print "    pid " $1 m }'
  if (( relaunches >= CA_MAX_RELAUNCH )); then
    log "watchdog: already relaunched $relaunches times — giving up. Quit CaptureAge and start it again."
    exit 1
  fi
  u="$(ca_url_seen)"; [[ -n "$u" ]] && { CA_URL="$u"; build_cmd; }
  ca_kill
  relaunches=$((relaunches + 1))
  launch
  bad=0
  deadline=$(( $(date +%s) + CA_WATCH_SECS ))
done
log "watchdog: time is up — stopping (CaptureAge keeps running)."
