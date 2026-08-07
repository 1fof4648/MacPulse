#!/bin/zsh
# MacPulse Guard v5 — Kalman chance-constrained governor + memory forecaster.
# Runs as root every 60 s.
#
# POWER: adaptive Kalman filter (local linear trend: state [level, trend],
# covariance P, measurement noise R adapted from innovations). Forecast
# P~ = L + 5T with properly propagated variance; policy derives from:
#   "Engage Low Power Mode when P(runtime < H) > 5%."
#   engage  when 60*E/(P~ + 1.645*sigma) <= 120 min
#   release when >= 180 min (time-domain hysteresis) and batt>=50%, mem>=40%
# Floors: batt <= 40% or free-mem <= 25% engage regardless of forecast.
#
# MEMORY: least-squares trend over the last 15 samples; if free% is falling
# fast enough to hit pressure (25%) within 20 min, log an early warning
# naming the top consumer BEFORE the squeeze happens. Runs on AC too.
DIR="/Library/Application Support/MacPulse"
LOG="$DIR/macpulse.log"
STATE_FILE="$DIR/state"
KALMAN_FILE="$DIR/kalman"
MEMHIST="$DIR/memhist"

PCT=$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%'); PCT=${PCT:-100}
FREE=$(memory_pressure 2>/dev/null | grep -Eo '[0-9]+%' | tail -1 | tr -d '%'); FREE=${FREE:-100}
SRC="ac"; pmset -g batt | grep -q "'Battery Power'" && SRC="batt"
PREV=$(cat "$STATE_FILE" 2>/dev/null || echo "none")

log() { echo "$(date '+%F %T') $1" >> "$LOG"; }
engage()  { pmset -a lowpowermode 1 2>/dev/null; echo "lpm"    > "$STATE_FILE"; log "ENGAGE low-power ($1)"; }
release() { pmset -a lowpowermode 0 2>/dev/null; echo "normal" > "$STATE_FILE"; log "RESTORE normal power ($1)"; }

# ---------- memory trend forecast (power-source independent) ----------
print -r -- "$FREE" >> "$MEMHIST"
tail -15 "$MEMHIST" > "$MEMHIST.tmp" 2>/dev/null && mv "$MEMHIST.tmp" "$MEMHIST"
MEMTREND=$(awk '{n++; y=$1; sx+=n; sy+=y; sxy+=n*y; sx2+=n*n} END{
  if (n < 6) { print "na"; exit }
  d = n*sx2 - sx*sx; if (d == 0) { print "na"; exit }
  printf "%.2f", (n*sxy - sx*sy)/d
}' "$MEMHIST")
if [[ "$MEMTREND" != "na" ]] && awk -v s="$MEMTREND" 'BEGIN{exit !(s <= -0.3)}' && (( FREE > 25 )); then
  MMEM=$(awk -v f="$FREE" -v s="$MEMTREND" 'BEGIN{printf "%.0f", (f - 25)/(-s)}')
  if (( MMEM <= 20 )); then
    if [[ ! -f "$DIR/memwarn" ]]; then
      touch "$DIR/memwarn"
      log "MEMORY TREND free=${FREE}% falling ${MEMTREND}%/min — pressure in ~${MMEM} min; top: $(ps axo rss,comm | sort -rn | head -1)"
    fi
  else
    rm -f "$DIR/memwarn"
  fi
else
  rm -f "$DIR/memwarn"
fi
if (( FREE <= 12 )); then
  log "CRITICAL memory (free=${FREE}%) — top hog: $(ps axo rss,comm | sort -rn | head -1)"
fi

# ---------- power control ----------
if [[ "$SRC" != "batt" ]]; then
  # Filter state is only meaningful for discharge; reset it on AC
  rm -f "$KALMAN_FILE"
  [[ "$PREV" == "lpm" ]] && release "on AC"
  exit 0
fi

# Battery gauge (top-level keys only — nested dicts repeat these names)
GAUGE=$(ioreg -rn AppleSmartBattery | awk '
  $1 == "\"InstantAmperage\"" {a=$3}
  $1 == "\"Voltage\""         {v=$3}
  $1 == "\"CurrentCapacity\"" {c=$3}
  END {
    if (a > 9.2e18) a -= 18446744073709551616;
    if (a < 0) a = -a;
    printf "%.1f %.2f", a*v/1000000, c*v/1000000
  }')
W=${GAUGE%% *}; EWH=${GAUGE##* }
W=${W:-0}; EWH=${EWH:-50}

if [[ -f "$KALMAN_FILE" ]]; then
  read -r L T P11 P12 P22 R < "$KALMAN_FILE"
else
  L="$W"; T=0; P11=25; P12=0; P22=1; R=4
fi

RES=$(awk -v w="$W" -v l="$L" -v t="$T" -v p11="$P11" -v p12="$P12" -v p22="$P22" -v r="$R" -v e="$EWH" 'BEGIN{
  q1=0.5; q2=0.05; z=1.645;
  lp = l + t; tp = t;
  a11 = p11 + 2*p12 + p22 + q1; a12 = p12 + p22; a22 = p22 + q2;
  y = w - lp; s = a11 + r; k1 = a11/s; k2 = a12/s;
  nl = lp + k1*y; nt = tp + k2*y;
  n11 = (1-k1)*a11; n12 = (1-k1)*a12; n22 = a22 - k2*a12;
  nr = 0.9*r + 0.1*(y*y - a11); if (nr < 0.25) nr = 0.25;
  pf = nl + 5*nt; if (pf < nl) pf = nl; if (pf < 3) pf = 3;
  vf = n11 + 10*n12 + 25*n22 + nr; if (vf < 0.01) vf = 0.01;
  sg = sqrt(vf);
  m = 60*e/(pf + z*sg);
  printf "%.2f %.3f %.3f %.3f %.3f %.3f %.0f %.1f %.1f", nl, nt, n11, n12, n22, nr, m, pf, sg
}')
read -r L T P11 P12 P22 R M P S <<< "$RES"
echo "$L $T $P11 $P12 $P22 $R" > "$KALMAN_FILE"

if [[ "$PREV" != "lpm" ]]; then
  if (( M <= 120 )); then
    engage "95%-confidence runtime ${M} min @ ${P}W ±${S}, batt=${PCT}%"
  elif (( PCT <= 40 )); then
    engage "batt=${PCT}%"
  elif (( FREE <= 25 )); then
    engage "free-mem=${FREE}%"
  fi
else
  if (( M >= 180 )) && (( PCT >= 50 )) && (( FREE >= 40 )); then
    release "95%-confidence runtime ${M} min @ ${P}W ±${S}, batt=${PCT}%"
  fi
fi
