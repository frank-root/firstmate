#!/usr/bin/env bash
# fm-hook-flags.sh - enable/disable gate for OPTIONAL, non-safety-critical hooks.
#
# Ported from ECC's (affaan-m/ECC) ECC_HOOK_PROFILE / ECC_DISABLED_HOOKS pattern
# (scripts/lib/hook-flags.js, scripts/hooks/run-with-flags.js): a hook declares
# which profiles it belongs to, and a session-wide env var picks the active
# profile or force-disables specific hooks by id, without touching hook
# registration in settings.json.
#
# Usage:
#   fm-hook-flags.sh <hook-id> <profiles-csv> -- <command> [args...]
#
#   <hook-id>       stable id for this hook, e.g. "pre:write:example-warning"
#   <profiles-csv>  comma-separated profile membership, e.g. "standard,strict"
#   <command...>    the real hook command; runs only if the hook is enabled
#
# Enablement:
#   FM_DISABLED_HOOKS   comma-separated hook ids, force-disabled regardless of profile
#   FM_HOOK_PROFILE     active profile (default: standard); hook runs iff this
#                       value appears in <profiles-csv>
#
# A suppressed hook always exits 0 - a skipped optional hook must never look
# like a failing one to the harness. The wrapped command's own exit status is
# preserved when it runs.
#
# ponytail: this repo currently registers zero hooks that belong behind this
# gate. Firstmate's three existing hooks (fm-arm-pretool-check.sh,
# fm-cd-pretool-check.sh, fm-turnend-guard.sh) are safety invariants that
# AGENTS.md documents as unconditional guarantees, so they do not route
# through here - wiring them in would quietly create a bypass for exactly
# what they exist to prevent. Wire a future hook through this gate only once
# it is genuinely optional (a style nag, a suggestion, a nice-to-have), giving
# it its own <hook-id>.

set -euo pipefail

usage() {
  echo "usage: fm-hook-flags.sh <hook-id> <profiles-csv> -- <command> [args...]" >&2
  exit 64
}

[ "$#" -ge 3 ] || usage
hook_id="$1"
profiles_csv="$2"
shift 2
[ "$1" = "--" ] || usage
shift
[ "$#" -ge 1 ] || usage

# _fm_csv_has <needle> <csv>: true if <needle> is one of the comma-separated
# items in <csv>. Avoids bash arrays: macOS's stock bash (3.2) leaves a `read
# -ra` target completely unset (not just empty) when the source is empty,
# which trips `set -u` on the very next "${arr[@]}" expansion.
_fm_csv_has() {
  case ",$2," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

fm_hook_enabled() {
  local id="$1" plist="$2" active
  _fm_csv_has "$id" "${FM_DISABLED_HOOKS:-}" && return 1
  active="${FM_HOOK_PROFILE:-standard}"
  _fm_csv_has "$active" "$plist"
}

if fm_hook_enabled "$hook_id" "$profiles_csv"; then
  exec "$@"
fi
exit 0
