#!/usr/bin/env bash
set -euo pipefail

# Monitor EC2 host + target R process utilization.
# Works on Linux/EC2; writes CSV for post-run analysis.
#
# Usage:
#   bash monitor_ec2_resources.sh [interval_seconds] [output_csv] [r_pid]
# Example:
#   bash monitor_ec2_resources.sh 10 step2_monitor.csv
#   bash monitor_ec2_resources.sh 5 step2_monitor.csv 12345

INTERVAL="${1:-10}"
OUT="${2:-step2_monitor.csv}"
TARGET_PID="${3:-}"

if [[ -z "${TARGET_PID}" ]]; then
  TARGET_PID="$(pgrep -f 'Rscript.*(master_analysis\\.R|run_step2_full_ec2\\.R)' | head -n1 || true)"
fi

echo "timestamp,load1,load5,load15,cpu_user_pct,cpu_sys_pct,cpu_idle_pct,mem_total_mb,mem_avail_mb,mem_used_mb,swap_total_mb,swap_free_mb,root_used_pct,r_pid,r_cpu_pct,r_mem_pct,r_rss_mb,r_vsz_mb,r_threads" > "${OUT}"

# Prime CPU counters
read -r _ user nice system idle iowait irq softirq steal _ _ < /proc/stat
PREV_TOTAL=$((user+nice+system+idle+iowait+irq+softirq+steal))
PREV_IDLE=$((idle+iowait))
PREV_USER=$((user+nice))
PREV_SYS=$((system+irq+softirq))

while true; do
  TS="$(date '+%Y-%m-%d %H:%M:%S')"

  # Load averages
  read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg

  # CPU utilization from /proc/stat deltas
  read -r _ user nice system idle iowait irq softirq steal _ _ < /proc/stat
  TOTAL=$((user+nice+system+idle+iowait+irq+softirq+steal))
  IDLE=$((idle+iowait))
  USER=$((user+nice))
  SYS=$((system+irq+softirq))

  DT=$((TOTAL-PREV_TOTAL))
  DIDLE=$((IDLE-PREV_IDLE))
  DUSER=$((USER-PREV_USER))
  DSYS=$((SYS-PREV_SYS))

  if [[ "${DT}" -gt 0 ]]; then
    CPU_IDLE_PCT="$(awk -v a="${DIDLE}" -v b="${DT}" 'BEGIN {printf "%.2f", (a/b)*100}')"
    CPU_USER_PCT="$(awk -v a="${DUSER}" -v b="${DT}" 'BEGIN {printf "%.2f", (a/b)*100}')"
    CPU_SYS_PCT="$(awk -v a="${DSYS}" -v b="${DT}" 'BEGIN {printf "%.2f", (a/b)*100}')"
  else
    CPU_IDLE_PCT="0.00"; CPU_USER_PCT="0.00"; CPU_SYS_PCT="0.00"
  fi

  PREV_TOTAL=${TOTAL}; PREV_IDLE=${IDLE}; PREV_USER=${USER}; PREV_SYS=${SYS}

  # Memory
  MEM_TOTAL_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  MEM_AVAIL_KB="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
  SWAP_TOTAL_KB="$(awk '/SwapTotal/ {print $2}' /proc/meminfo)"
  SWAP_FREE_KB="$(awk '/SwapFree/ {print $2}' /proc/meminfo)"

  MEM_TOTAL_MB=$((MEM_TOTAL_KB/1024))
  MEM_AVAIL_MB=$((MEM_AVAIL_KB/1024))
  MEM_USED_MB=$(((MEM_TOTAL_KB-MEM_AVAIL_KB)/1024))
  SWAP_TOTAL_MB=$((SWAP_TOTAL_KB/1024))
  SWAP_FREE_MB=$((SWAP_FREE_KB/1024))

  # Root disk usage
  ROOT_USED_PCT="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"

  # Process metrics
  R_PID_OUT=""
  R_CPU_PCT=""
  R_MEM_PCT=""
  R_RSS_MB=""
  R_VSZ_MB=""
  R_THREADS=""

  if [[ -n "${TARGET_PID}" ]] && ps -p "${TARGET_PID}" > /dev/null 2>&1; then
    R_PID_OUT="${TARGET_PID}"
    read -r R_CPU_PCT R_MEM_PCT R_RSS_KB R_VSZ_KB R_THREADS <<< "$(ps -p "${TARGET_PID}" -o %cpu,%mem,rss,vsz,nlwp --no-headers | awk '{$1=$1; print}')"
    R_RSS_MB="$(awk -v x="${R_RSS_KB}" 'BEGIN {printf "%.1f", x/1024}')"
    R_VSZ_MB="$(awk -v x="${R_VSZ_KB}" 'BEGIN {printf "%.1f", x/1024}')"
  fi

  echo "${TS},${LOAD1},${LOAD5},${LOAD15},${CPU_USER_PCT},${CPU_SYS_PCT},${CPU_IDLE_PCT},${MEM_TOTAL_MB},${MEM_AVAIL_MB},${MEM_USED_MB},${SWAP_TOTAL_MB},${SWAP_FREE_MB},${ROOT_USED_PCT},${R_PID_OUT},${R_CPU_PCT},${R_MEM_PCT},${R_RSS_MB},${R_VSZ_MB},${R_THREADS}" >> "${OUT}"

  sleep "${INTERVAL}"
done
