# shellcheck shell=bash
# Shared in-flight-work and watcher-beacon-age status.
# Usage: . bin/fm-supervision-lib.sh
#
# Tracks whether a firstmate home has in-flight work and whether the watcher's
# liveness beacon (state/.last-watcher-beat, touched every poll cycle) is fresh.
# Guard scripts use these status fields for banner detail ONLY, then decide health
# with the live identity-matched watcher check (fm_watcher_healthy) in
# bin/fm-wake-lib.sh: a fresh beacon alone cannot prove a watcher is alive,
# because a dead watcher leaves its last beacon behind.

# Portable mtime; Linux stat lacks -f, macOS stat lacks -c.
fm_sup_stat_mtime() {
  if [ "$(uname)" = Darwin ]; then
    stat -f %m "$1" 2>/dev/null
  else
    stat -c %Y "$1" 2>/dev/null
  fi
}

# fm_supervision_status <state-dir> [grace-seconds]
# Populates, for the state dir at $1:
#   FM_SUP_IN_FLIGHT      count of state/*.meta (in-flight tasks)
#   FM_SUP_WATCHER_FRESH  true/false - a watcher beacon within the grace window
#   FM_SUP_BEACON_DESC    human-readable beacon age, for banners ("never" if absent)
#   FM_SUP_QUEUE_PENDING  true/false - state/.wake-queue has unread records
# grace-seconds defaults to $FM_GUARD_GRACE, then 300, matching fm-guard.sh.
# Always returns 0; callers read the vars. FM_SUP_WATCHER_FRESH is beacon age
# alone - it is banner forensics, never a liveness verdict (see below).
fm_supervision_status() {
  local state=$1 grace=${2:-${FM_GUARD_GRACE:-300}} meta beat m age
  FM_SUP_IN_FLIGHT=0
  FM_SUP_WATCHER_FRESH=false
  FM_SUP_BEACON_DESC=never
  FM_SUP_QUEUE_PENDING=false

  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    FM_SUP_IN_FLIGHT=$((FM_SUP_IN_FLIGHT + 1))
  done

  beat="$state/.last-watcher-beat"
  if [ -e "$beat" ]; then
    m=$(fm_sup_stat_mtime "$beat")
    if [ -n "$m" ]; then
      age=$(( $(date +%s) - m ))
      FM_SUP_BEACON_DESC="${age}s ago"
      [ "$age" -lt "$grace" ] && FM_SUP_WATCHER_FRESH=true
    else
      # shellcheck disable=SC2034 # Read by callers (fm-guard.sh) after sourcing.
      FM_SUP_BEACON_DESC=unknown
    fi
  fi

  # shellcheck disable=SC2034 # Read by callers (fm-guard.sh) after sourcing.
  [ -s "$state/.wake-queue" ] && FM_SUP_QUEUE_PENDING=true
  return 0
}

# fm_supervision_unhealthy <state-dir> [grace-seconds]
# Exit 0 (true) when in-flight work exists and no watcher has a fresh beacon.
# Exit 1 (false) otherwise, including zero in-flight.
#
# Retained deliberately, but NO production caller uses it and none should: it is
# beacon-age-only, so a dead watcher's leftover fresh beacon reads as healthy -
# exactly the masking bug fm_watcher_healthy exists to close. Guards must call
# fm_watcher_healthy instead. Kept as the covered definition of beacon-freshness
# semantics that fm_supervision_status's callers depend on (tests/fm-turnend-guard.test.sh).
fm_supervision_unhealthy() {
  fm_supervision_status "$@"
  [ "$FM_SUP_IN_FLIGHT" -gt 0 ] && [ "$FM_SUP_WATCHER_FRESH" = false ]
}
