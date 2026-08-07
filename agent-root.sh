#!/bin/zsh
# MacPulse Agent — root runner for password-free operations.
# launchd (WatchPaths on the spool dir) fires this when the app drops a
# request file. Only the fixed verbs below execute; requests carry no
# arguments, so user-writable spool content cannot inject paths/options.
DIR="/Library/Application Support/MacPulse"
SPOOL="$DIR/spool"
LOG="$DIR/macpulse.log"
REPORTS="$DIR/reports"

log() { echo "$(date '+%F %T') $1" >> "$LOG"; }
line() { printf '%s\n' "------------------------------------------------------------"; }

mkdir -p "$REPORTS"
chmod 755 "$REPORTS"
find "$SPOOL" -name 'done-*' -mmin +5 -delete 2>/dev/null

setopt NULL_GLOB
for req in "$SPOOL"/req-*; do
  id="${req##*/req-}"
  id="${id//[^a-zA-Z0-9]/}"
  verb=$(head -1 "$req" 2>/dev/null | tr -cd 'a-z')
  rm -f "$req"
  case "$verb" in
    tune)
      pmset -b powernap 0
      pmset -b displaysleep 5
      pmset -b disksleep 5
      pmset -b womp 0 2>/dev/null
      pmset -b proximitywake 0 2>/dev/null
      pmset -b standbydelaylow 900 2>/dev/null
      pmset -b standbydelayhigh 3600 2>/dev/null
      # Dual-GPU Intel MBP: integrated-only on battery is the biggest win
      pmset -b gpuswitch 0 2>/dev/null
      print -r -- "ok" > "$SPOOL/done-$id"
      chmod 644 "$SPOOL/done-$id"
      log "AGENT tune applied (battery profile)"
      ;;
    deep)
      OUT="$REPORTS/deepscan-$(date +%Y%m%d-%H%M%S).txt"
      {
        line; echo "MACPULSE DEEP SCAN — $(date)"; line
        echo; echo "== CPU =="
        sysctl -n machdep.cpu.brand_string 2>/dev/null
        sysctl hw.ncpu hw.memsize 2>/dev/null
        echo; echo "== GPU inventory =="
        system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|VRAM|Metal|Bus" | sed 's/^ *//'
        echo; echo "== Thermal state (CPU speed limits) =="
        pmset -g therm 2>/dev/null
        echo; echo "== Kernel power model: frequency, residency, package power =="
        powermetrics -n 1 -i 1000 2>/dev/null || echo "(default sample unavailable)"
        echo; echo "== SMC: die temperature & fans =="
        powermetrics --samplers smc -n 1 -i 500 2>/dev/null || echo "(smc sampler unavailable)"
        echo; echo "== Kernel per-process energy impact (top of table) =="
        powermetrics --samplers tasks -n 1 -i 1000 2>/dev/null | head -45 || echo "(tasks sampler unavailable)"
        echo; echo "== Kernel memory =="
        vm_stat
        sysctl vm.swapusage vm.loadavg 2>/dev/null
        sysctl kern.memorystatus_level 2>/dev/null
        line
      } > "$OUT" 2>&1
      chmod 644 "$OUT"
      print -r -- "$OUT" > "$SPOOL/done-$id"
      chmod 644 "$SPOOL/done-$id"
      log "AGENT deep scan -> $OUT"
      ;;
    *)
      log "AGENT ignored unknown request"
      ;;
  esac
done
