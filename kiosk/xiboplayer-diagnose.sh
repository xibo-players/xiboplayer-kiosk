#!/bin/bash
# Xiboplayer Diagnostic Monitor
# ==============================
# Launches a player and monitors memory, CPU, GPU, and processes.
# Collects all data into a tarball for sending to support.
#
# Usage:
#   ./xiboplayer-diagnose.sh                    # monitor running player (auto-detect)
#   ./xiboplayer-diagnose.sh --player electron  # monitor electron specifically
#   ./xiboplayer-diagnose.sh --player chromium  # monitor chromium specifically
#   ./xiboplayer-diagnose.sh --pid 12345        # monitor a specific PID
#   ./xiboplayer-diagnose.sh --duration 60      # collect for 60 minutes (default: 30)
#   ./xiboplayer-diagnose.sh --interval 30      # sample every 30s (default: 60)
#
# Output: ~/xiboplayer-diag-YYYY-MM-DD-HHMMSS.tar.gz

set -uo pipefail

# ── Defaults ──────────────────────────────────────────────────
PLAYER=""
PID=""
DURATION=30       # minutes
INTERVAL=60       # seconds
OUTDIR=""
HZ=$(getconf CLK_TCK)

# ── Parse arguments ───────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --player) PLAYER="$2"; shift 2 ;;
    --pid)    PID="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/s/^# //p' "$0"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

TOTAL_SAMPLES=$(( DURATION * 60 / INTERVAL ))

# ── Detect player PID ─────────────────────────────────────────
detect_pid() {
  local player="${1:-}"

  # By player name
  if [[ "$player" == "electron" ]]; then
    for p in /proc/[0-9]*/exe; do
      target=$(readlink "$p" 2>/dev/null) || continue
      case "$target" in */electron|*/xiboplayer)
        ppid=${p#/proc/}; ppid=${ppid%/exe}
        cmd=$(tr '\0' ' ' < "/proc/$ppid/cmdline" 2>/dev/null)
        case "$cmd" in *--type=*) ;; *) echo "$ppid"; return ;; esac
      ;; esac
    done
  elif [[ "$player" == "chromium" ]]; then
    for p in /proc/[0-9]*/exe; do
      target=$(readlink "$p" 2>/dev/null) || continue
      case "$target" in */chromium-browser*)
        ppid=${p#/proc/}; ppid=${ppid%/exe}
        cmd=$(tr '\0' ' ' < "/proc/$ppid/cmdline" 2>/dev/null)
        case "$cmd" in *--type=*) ;; *) echo "$ppid"; return ;; esac
      ;; esac
    done
  fi

  # Auto-detect: try systemd services first
  for svc in xiboplayer-electron xiboplayer-chromium; do
    spid=$(systemctl --user show "${svc}.service" -p MainPID --value 2>/dev/null || echo 0)
    if [[ "$spid" != "0" ]] && kill -0 "$spid" 2>/dev/null; then
      echo "$spid"; return
    fi
  done

  # Fallback: any electron or chromium main process
  for p in /proc/[0-9]*/exe; do
    target=$(readlink "$p" 2>/dev/null) || continue
    case "$target" in */electron|*/xiboplayer|*/chromium-browser*)
      ppid=${p#/proc/}; ppid=${ppid%/exe}
      cmd=$(tr '\0' ' ' < "/proc/$ppid/cmdline" 2>/dev/null)
      case "$cmd" in *--type=*) ;; *) echo "$ppid"; return ;; esac
    ;; esac
  done
}

if [[ -z "$PID" ]]; then
  PID=$(detect_pid "$PLAYER")
fi

if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
  echo "ERROR: No player process found."
  echo "  Start a player first, or use --pid to specify the main process PID."
  exit 1
fi

# Identify player from binary
PLAYER_BIN=$(readlink "/proc/$PID/exe" 2>/dev/null || echo "unknown")
case "$PLAYER_BIN" in
  *chromium*) PLAYER_NAME="chromium" ;;
  *electron*|*xiboplayer*) PLAYER_NAME="electron" ;;
  *) PLAYER_NAME="player" ;;
esac

# ── Setup output directory ────────────────────────────────────
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
OUTDIR="/tmp/xiboplayer-diag-${TIMESTAMP}"
mkdir -p "$OUTDIR"

MEM_FILE="$OUTDIR/memory.csv"
PROC_FILE="$OUTDIR/processes.csv"
FD_FILE="$OUTDIR/fd-detail.log"
CPU_PREV="$OUTDIR/.cpu-prev"
SYSINFO="$OUTDIR/system-info.txt"
PLAYER_LOG="$OUTDIR/player.log"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Xiboplayer Diagnostic Monitor                      ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Player:   $PLAYER_NAME (PID $PID)"
echo "║  Duration: ${DURATION} minutes ($TOTAL_SAMPLES samples)"
echo "║  Interval: ${INTERVAL}s"
echo "║  Output:   $OUTDIR/"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Collect system info ───────────────────────────────────────
{
  echo "=== System Info ==="
  echo "Date: $(date -Iseconds)"
  echo "Hostname: $(hostname)"
  echo "Kernel: $(uname -r)"
  echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
  echo "CPU: $(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)"
  echo "Cores: $(nproc)"
  echo "RAM: $(awk '/^MemTotal:/{printf "%.1f GB", $2/1048576}' /proc/meminfo)"
  echo ""
  echo "=== GPU ==="
  for card in /sys/class/drm/card[0-9]*; do
    [[ -f "$card/device/vendor" ]] || continue
    vendor=$(cat "$card/device/vendor" 2>/dev/null)
    device=$(cat "$card/device/device" 2>/dev/null)
    driver=$(basename "$(readlink "$card/device/driver" 2>/dev/null)" 2>/dev/null)
    echo "  $card: vendor=$vendor device=$device driver=$driver"
  done
  echo ""
  echo "=== Player ==="
  echo "Binary: $PLAYER_BIN"
  echo "PID: $PID"
  echo "Cmdline: $(tr '\0' ' ' < /proc/$PID/cmdline 2>/dev/null)"
  echo ""
  echo "=== Display ==="
  gdctl show 2>/dev/null || echo "gdctl not available"
  echo ""
  echo "=== Player version ==="
  rpm -q xiboplayer-electron xiboplayer-chromium xiboplayer-kiosk 2>/dev/null || echo "not RPM-installed"
} > "$SYSINFO" 2>&1

# ── Copy recent player log ────────────────────────────────────
for logpath in /tmp/electron-pwa.log /tmp/chromium-pwa.log \
               "$HOME/.local/share/xiboplayer/electron/log.txt" \
               "$HOME/.local/share/xiboplayer/chromium/log.txt"; do
  if [[ -f "$logpath" ]]; then
    tail -500 "$logpath" > "$PLAYER_LOG" 2>/dev/null
    echo "# Source: $logpath" >> "$PLAYER_LOG"
    break
  fi
done

# ── CSV headers ───────────────────────────────────────────────
echo "# Diagnostic monitor started: $(date -Iseconds), PID=$PID, player=$PLAYER_NAME" > "$MEM_FILE"
echo "timestamp,main_rss,children_rss,gpu_rss,renderer_rss,pids,log_lines,main_fds,total_fds,fd_socket,fd_pipe,fd_anon,fd_file,total_cpu,nvidia_gpu,nvidia_mem,sys_cpu,intel_gpu_pct,main_pss,children_pss,gpu_pss,renderer_pss,cpu_main,cpu_gpu,cpu_renderer,cpu_network,cpu_other" >> "$MEM_FILE"

echo "# Per-process monitor started: $(date -Iseconds)" > "$PROC_FILE"
echo "timestamp,pid,type,rss_mb,cpu_pct,threads,fds,pss_mb" >> "$PROC_FILE"

# ── Process type detection ────────────────────────────────────
detect_type() {
  local p=$1
  local cmd=$(cat /proc/$p/cmdline 2>/dev/null | tr '\0' ' ')
  local exe=$(readlink /proc/$p/exe 2>/dev/null)

  [[ "$p" == "$PID" ]] && { echo "main"; return; }

  if echo "$cmd" | grep -q 'utility-sub-type=network'; then echo "network"; return; fi
  if echo "$cmd" | grep -q 'utility-sub-type=audio'; then echo "audio"; return; fi
  if echo "$cmd" | grep -q 'utility-sub-type='; then echo "utility"; return; fi
  if echo "$cmd" | grep -q 'type=gpu-process\|type=gpu'; then echo "gpu"; return; fi
  if echo "$cmd" | grep -q 'type=renderer'; then echo "renderer"; return; fi
  if echo "$cmd" | grep -q 'type=zygote'; then
    local threads=$(awk '/^Threads:/{print $2}' "/proc/$p/status" 2>/dev/null || echo 1)
    if echo "$cmd" | grep -q -- '--no-zygote-sandbox'; then
      [[ "$threads" -gt 2 ]] && { echo "renderer"; return; }
    else
      [[ "$threads" -gt 2 ]] && { echo "gpu"; return; }
    fi
    echo "zygote"; return
  fi

  case "$exe" in
    */node|*/node[0-9]*) echo "server"; return ;;
    */chromium-browser*|*/chrome)
      echo "$cmd" | grep -q -- '--type=' && { echo "other"; return; }
      echo "browser"; return ;;
    */xiboplayer|*/electron)
      local drm_count=$(readlink /proc/$p/fd/* 2>/dev/null | grep -c 'renderD' || echo 0)
      local threads=$(awk '/^Threads:/{print $2}' "/proc/$p/status" 2>/dev/null || echo 1)
      [[ "$drm_count" -gt 2 ]] && { echo "renderer"; return; }
      [[ "$threads" -gt 25 ]] && { echo "main"; return; }
      [[ "$threads" -gt 10 ]] && { echo "gpu"; return; }
      echo "other"; return ;;
    */cat|*/bash|*/sh) echo "pipe"; return ;;
  esac
  echo "other"
}

read_gpu_render_ns() {
  local p=$1
  for fd in /proc/$p/fdinfo/*; do
    if grep -q 'drm-engine-render' "$fd" 2>/dev/null; then
      awk '/^drm-engine-render:/{print $2+0}' "$fd" 2>/dev/null
      return
    fi
  done
  echo 0
}

# ── Main collection loop ─────────────────────────────────────
echo "Collecting... Press Ctrl+C to stop early and package results."
trap 'echo ""; echo "Interrupted after $sample samples."; break' INT

sample=0
while [[ $sample -lt $TOTAL_SAMPLES ]]; do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "$(date -Iseconds) PROCESS_DIED" >> "$MEM_FILE"
    echo "Player process $PID died after $sample samples."
    break
  fi

  ts=$(date -Iseconds)
  progress=$(( (sample + 1) * 100 / TOTAL_SAMPLES ))
  printf "\r  Sample %d/%d (%d%%) — %s" "$((sample + 1))" "$TOTAL_SAMPLES" "$progress" "$ts"

  # Walk process tree
  all_pids="$PID"
  walk_children() {
    local parent=$1 depth=$2
    [[ "$depth" -gt 8 ]] && return
    for child in $(pgrep -P "$parent" 2>/dev/null); do
      all_pids="$all_pids $child"
      walk_children "$child" $((depth + 1))
    done
  }
  walk_children "$PID" 1

  main_rss=0; children_total=0; gpu_rss=0; renderer_rss=0
  main_pss=0; children_pss=0; gpu_pss=0; renderer_pss=0
  pids_count=0; total_cpu=0
  cpu_main=0; cpu_gpu=0; cpu_renderer=0; cpu_network=0; cpu_other=0
  cpu_prev_new=""
  gpu_render_ns=0

  for p in $all_pids; do
    [[ -f "/proc/${p}/status" ]] || continue
    pids_count=$((pids_count + 1))
    ptype=$(detect_type "$p")

    prss=$(awk '/^VmRSS:/{printf "%.1f", $2/1024}' "/proc/${p}/status" 2>/dev/null || echo 0)
    ppss=$(awk '/^Pss:/{printf "%.1f", $2/1024}' "/proc/${p}/smaps_rollup" 2>/dev/null || echo 0)

    ticks=$(awk '{print $14+$15}' "/proc/${p}/stat" 2>/dev/null || echo 0)
    prev_ticks=$(grep "^${p} " "$CPU_PREV" 2>/dev/null | awk '{print $2}')
    if [[ -n "$prev_ticks" ]] && [[ "$prev_ticks" -gt 0 ]] 2>/dev/null; then
      delta_ticks=$((ticks - prev_ticks))
      pcpu=$(awk "BEGIN{printf \"%.1f\", $delta_ticks * 100 / ($INTERVAL * $HZ)}")
    else
      pcpu="0.0"
    fi
    cpu_prev_new="${cpu_prev_new}${p} ${ticks}\n"
    total_cpu=$(awk "BEGIN{printf \"%.1f\", $total_cpu + $pcpu}")
    case "$ptype" in
      main)     cpu_main=$(awk "BEGIN{printf \"%.1f\", $cpu_main + $pcpu}") ;;
      gpu)      cpu_gpu=$(awk "BEGIN{printf \"%.1f\", $cpu_gpu + $pcpu}") ;;
      renderer) cpu_renderer=$(awk "BEGIN{printf \"%.1f\", $cpu_renderer + $pcpu}") ;;
      network)  cpu_network=$(awk "BEGIN{printf \"%.1f\", $cpu_network + $pcpu}") ;;
      *)        cpu_other=$(awk "BEGIN{printf \"%.1f\", $cpu_other + $pcpu}") ;;
    esac

    pthreads=$(awk '/^Threads:/{print $2}' "/proc/${p}/status" 2>/dev/null || echo 0)
    pfds=$(ls /proc/${p}/fd 2>/dev/null | wc -l || echo 0)

    case "$ptype" in gpu|renderer|browser|main)
      ns=$(read_gpu_render_ns "$p")
      [[ "${ns:-0}" -gt "${gpu_render_ns:-0}" ]] 2>/dev/null && gpu_render_ns=$ns
    ;; esac

    if [[ "$ptype" == "main" ]]; then
      main_rss=$prss; main_pss=$ppss
    elif [[ "$ptype" != "pipe" ]]; then
      children_total=$(awk "BEGIN{printf \"%.1f\", $children_total + $prss}")
      children_pss=$(awk "BEGIN{printf \"%.1f\", $children_pss + $ppss}")
      case "$ptype" in
        gpu) gpu_rss=$(awk "BEGIN{printf \"%.1f\", $gpu_rss + $prss}"); gpu_pss=$(awk "BEGIN{printf \"%.1f\", $gpu_pss + $ppss}") ;;
        renderer) renderer_rss=$(awk "BEGIN{printf \"%.1f\", $renderer_rss + $prss}"); renderer_pss=$(awk "BEGIN{printf \"%.1f\", $renderer_pss + $ppss}") ;;
      esac
    fi

    echo "${ts},${p},${ptype},${prss},${pcpu},${pthreads},${pfds},${ppss}" >> "$PROC_FILE"
  done

  printf "%b" "$cpu_prev_new" > "$CPU_PREV"

  # GPU% from DRM render engine
  gpu_prev_file="$OUTDIR/.gpu-prev"
  prev_gpu_ns=$(cat "$gpu_prev_file" 2>/dev/null || echo 0)
  intel_gpu_pct="0.0"
  if [[ "${gpu_render_ns:-0}" -gt 0 ]] 2>/dev/null && [[ "${prev_gpu_ns:-0}" -gt 0 ]] 2>/dev/null; then
    gpu_delta_ns=$((gpu_render_ns - prev_gpu_ns))
    interval_ns=$((INTERVAL * 1000000000))
    intel_gpu_pct=$(awk "BEGIN{printf \"%.1f\", $gpu_delta_ns * 100 / $interval_ns}")
  fi
  echo "${gpu_render_ns:-0}" > "$gpu_prev_file"

  log_lines=0
  open_fds=$(ls /proc/${PID}/fd 2>/dev/null | wc -l || echo 0)
  total_fds=0; fd_socket=0; fd_pipe=0; fd_anon=0; fd_file=0
  for fpid in $all_pids; do
    [[ -d "/proc/${fpid}/fd" ]] || continue
    for link in $(readlink /proc/${fpid}/fd/* 2>/dev/null); do
      total_fds=$((total_fds + 1))
      case "$link" in
        socket:*)     fd_socket=$((fd_socket + 1)) ;;
        pipe:*)       fd_pipe=$((fd_pipe + 1)) ;;
        anon_inode:*) fd_anon=$((fd_anon + 1)) ;;
        /*)           fd_file=$((fd_file + 1)) ;;
      esac
    done
  done

  # FD snapshot every 10 samples
  if [[ $((sample % 10)) -eq 0 ]]; then
    echo "=== Snapshot at ${ts} (sample ${sample}) ===" >> "$FD_FILE"
    for fpid in $all_pids; do
      [[ -d "/proc/${fpid}/fd" ]] || continue
      pname=$(cat /proc/${fpid}/cmdline 2>/dev/null | tr '\0' ' ' | cut -c1-60)
      pfd_count=$(ls /proc/${fpid}/fd 2>/dev/null | wc -l)
      echo "  PID ${fpid} (${pfd_count} fds): ${pname}" >> "$FD_FILE"
      readlink /proc/${fpid}/fd/* 2>/dev/null | sort | uniq -c | sort -rn | head -10 >> "$FD_FILE"
    done
    echo "" >> "$FD_FILE"
  fi

  nvidia_gpu=0; nvidia_mem=0
  if nvidia_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null); then
    nvidia_gpu=$(echo "$nvidia_info" | head -1 | awk -F', ' '{print $1+0}')
    nvidia_mem=$(echo "$nvidia_info" | head -1 | awk -F', ' '{print $2+0}')
  fi

  sys_cpu=$(top -bn1 2>/dev/null | awk '/^%Cpu/ {printf "%.1f", 100 - $8}' || echo 0)

  echo "${ts},${main_rss},${children_total},${gpu_rss},${renderer_rss},${pids_count},${log_lines},${open_fds},${total_fds},${fd_socket},${fd_pipe},${fd_anon},${fd_file},${total_cpu},${nvidia_gpu},${nvidia_mem},${sys_cpu},${intel_gpu_pct},${main_pss},${children_pss},${gpu_pss},${renderer_pss},${cpu_main},${cpu_gpu},${cpu_renderer},${cpu_network},${cpu_other}" >> "$MEM_FILE"

  sample=$((sample + 1))
  sleep "$INTERVAL"
done

# ── Package results ───────────────────────────────────────────
echo ""
echo ""

# Remove temp files
rm -f "$OUTDIR/.cpu-prev" "$OUTDIR/.gpu-prev"

# Create tarball
TARBALL="$HOME/xiboplayer-diag-${TIMESTAMP}.tar.gz"
tar czf "$TARBALL" -C /tmp "xiboplayer-diag-${TIMESTAMP}"

SAMPLES=$(grep -c '^20' "$MEM_FILE" 2>/dev/null || echo 0)
SIZE=$(du -sh "$TARBALL" | awk '{print $1}')

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Collection complete                                ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Samples:  $SAMPLES"
echo "║  Files:    $OUTDIR/"
echo "║  Tarball:  $TARBALL ($SIZE)"
echo "║                                                     ║"
echo "║  Send $TARBALL to support.  ║"
echo "╚══════════════════════════════════════════════════════╝"
