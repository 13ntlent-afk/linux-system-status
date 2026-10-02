#!/usr/bin/env bash
# sysstatus.sh - Short Linux system status report (read-only)
# Usage: ./sysstatus.sh          readable report
#        ./sysstatus.sh --json   JSON output

export LC_ALL=C                                   # same format on every system
export PATH="/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"   # cron has a tiny PATH

JSON=false
case "$1" in
  "") ;;
  --json) JSON=true ;;
  *) echo "Usage: $0 [--json]" >&2; exit 1 ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }          # does this command exist?
add()  { printf '%s=%s\n' "$1" "${2:-n/a}"; }        # print one key=value line

# Every check prints key=value lines. A missing tool just means no lines.
collect() {
  add time "$(date +%Y-%m-%dT%H:%M:%S%:z)"           # RFC 3339
  add host "$(hostname)"
  add user "$(id -un)"
  if [ "$(id -u)" -eq 0 ]; then add is_root true; add note "running as root, not needed"
  else add is_root false; fi
  if [ -f /.dockerenv ] || grep -qaE 'docker|kubepods' /proc/1/cgroup 2>/dev/null
  then add in_container true; else add in_container false; fi

  # CPU: compare /proc/stat twice, 1 second apart
  cores=$(nproc); add cpu_cores "$cores"
  if [ -r /proc/stat ]; then
    cpu() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat; }
    read -r t1 i1 <<< "$(cpu)"; sleep 1; read -r t2 i2 <<< "$(cpu)"
    [ $((t2 - t1)) -gt 0 ] && pct=$((100 * ((t2 - t1) - (i2 - i1)) / (t2 - t1)))
    add cpu_usage_percent "$pct"
  fi

  # Load average and uptime
  if [ -r /proc/loadavg ]; then
    read -r l1 l5 l15 _ < /proc/loadavg
    add load_1m "$l1"; add load_5m "$l5"; add load_15m "$l15"
  fi
  if [ -r /proc/uptime ]; then
    s=$(cut -d. -f1 /proc/uptime)
    add uptime "$((s / 86400))d $((s % 86400 / 3600))h $((s % 3600 / 60))m"
  fi

  # Memory and swap in MB
  if [ -r /proc/meminfo ]; then
    m() { awk -v k="$1:" '$1 == k {print int($2 / 1024)}' /proc/meminfo; }
    add mem_total_mb "$(m MemTotal)"; add mem_free_mb "$(m MemFree)"
    add mem_available_mb "$(m MemAvailable)"
    add mem_used_mb "$(( $(m MemTotal) - $(m MemAvailable) ))"
    add swap_total_mb "$(m SwapTotal)"
    add swap_used_mb "$(( $(m SwapTotal) - $(m SwapFree) ))"
  fi

  # Disk, top processes, network, users (each skipped if the tool is missing)
  have df && df -P -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null |
    awk 'NR>1 {print "disk_" $6 "=" $5 " used, " $4 " free"}'
  have ps && ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu --no-headers 2>/dev/null | head -5 |
    awk '{print "top_cpu_" NR "=" $5 " (pid " $1 ", " $3 "% cpu)"}'
  have ps && ps -eo pid,user,%cpu,%mem,comm --sort=-%mem --no-headers 2>/dev/null | head -5 |
    awk '{print "top_mem_" NR "=" $5 " (pid " $1 ", " $4 "% mem)"}'
  have ip && ip -o -4 addr show 2>/dev/null | awk '{print "ip_" $2 "=" $4}'
  have ss && ss -tuln 2>/dev/null | awk 'NR>1 {print "listening_" NR-1 "=" $1 " " $5}'
  have who && add logged_in_users "$(who | wc -l)"
  have who && who | awk '{print "login_" NR "=" $1 " on " $2}'

  # Extra: does Ubuntu want a reboot after updates?
  if [ -f /var/run/reboot-required ]; then add reboot_required true; else add reboot_required false; fi
}

# Turn the key=value lines into text or JSON
if [ "$JSON" = true ]; then
  collect | awk -F= '
    BEGIN { printf "{" }
    { k = $1; v = substr($0, length(k) + 2); gsub(/"/, "\\\"", v)
      if (v ~ /^-?[0-9.]+$/ || v == "true" || v == "false") out = v
      else if (v == "n/a") out = "null"
      else out = "\"" v "\""
      printf "%s\n  \"%s\": %s", (NR > 1 ? "," : ""), k, out }
    END { print "\n}" }'
else
  echo "=== System Status Report ==="
  collect | awk -F= '{ k = $1; printf "%-24s %s\n", k ":", substr($0, length(k) + 2) }'
fi
