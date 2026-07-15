#!/usr/bin/env bash
# Behavior tests for bin/fm-hook-flags.sh, the optional-hook enable/disable gate.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GATE="$ROOT/bin/fm-hook-flags.sh"

test_default_profile_runs_matching_hook() {
  local out
  out=$(env -u FM_HOOK_PROFILE -u FM_DISABLED_HOOKS "$GATE" pre:test:example standard,strict -- echo ran)
  assert_contains "$out" "ran" "default (standard) profile runs a standard,strict hook"
}

test_default_profile_skips_strict_only_hook() {
  local out code
  out=$(env -u FM_HOOK_PROFILE -u FM_DISABLED_HOOKS "$GATE" pre:test:strict-only strict -- echo ran)
  code=$?
  assert_not_contains "$out" "ran" "default (standard) profile must not run a strict-only hook"
  expect_code 0 "$code" "a suppressed hook still exits 0"
}

test_strict_profile_enables_strict_only_hook() {
  local out
  out=$(FM_HOOK_PROFILE=strict "$GATE" pre:test:strict-only strict -- echo ran)
  assert_contains "$out" "ran" "FM_HOOK_PROFILE=strict runs a strict-only hook"
}

test_disabled_hooks_wins_over_matching_profile() {
  local out code
  out=$(FM_DISABLED_HOOKS=pre:test:example,other:id "$GATE" pre:test:example standard,strict -- echo ran)
  code=$?
  assert_not_contains "$out" "ran" "FM_DISABLED_HOOKS suppresses a hook even in-profile"
  expect_code 0 "$code" "a disabled hook still exits 0"
}

test_wrapped_command_exit_code_is_preserved() {
  local code
  env -u FM_HOOK_PROFILE -u FM_DISABLED_HOOKS "$GATE" pre:test:example standard,strict -- sh -c 'exit 7'
  code=$?
  expect_code 7 "$code" "an enabled hook's own exit code passes through"
}

test_default_profile_runs_matching_hook
test_default_profile_skips_strict_only_hook
test_strict_profile_enables_strict_only_hook
test_disabled_hooks_wins_over_matching_profile
test_wrapped_command_exit_code_is_preserved
pass "fm-hook-flags gate: profile membership, disable-list precedence, exit-code passthrough"
