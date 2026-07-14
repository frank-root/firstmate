#!/usr/bin/env bash
# Behavior tests for fm-spawn.sh's optional ECC capability-pack wiring
# (config/crew-capability-pack -> a Claude PreToolUse hook alongside the
# existing turn-end Stop hook). The pack itself is local/gitignored and
# often vendors third-party code, so these tests never depend on a real
# pack - they build a minimal synthetic one (a stub gateguard-run.js) the
# same way tests/fm-spawn-dispatch-profile.test.sh drives fm-spawn through
# meta writing and launch construction with a fake tmux and a real isolated
# git worktree, without starting any real harness.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-capability-pack)

make_spawn_fakebin() {
  local dir=$1 with_node=$2 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:-}"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows) exit 0 ;;
  has-session|new-session|new-window|kill-window) exit 0 ;;
  send-keys) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  fm_fake_exit0 "$fakebin" treehouse
  if [ "$with_node" = 1 ]; then
    fm_fake_exit0 "$fakebin" node
  fi
  printf '%s\n' "$fakebin"
}

# make_spawn_case <name> [with_node] [with_pack] [with_gateguard_file]
# Builds an isolated home+project+worktree, optionally seeding a fake `node`
# on PATH and/or a config/crew-capability-pack pointing at a synthetic pack
# directory. HOME is redirected to an empty per-case directory so the
# $HOME/.local/node/bin/node fallback never accidentally resolves to a real
# install on the machine running the suite.
make_spawn_case() {
  local name=$1 with_node=${2:-1} with_pack=${3:-0} with_gateguard=${4:-1}
  local case_dir home proj wt fakebin launchlog fakehome pack id=cap-$name-z1

  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakehome="$case_dir/fakehome"
  launchlog="$case_dir/launch.log"
  fakebin=$(make_spawn_fakebin "$case_dir/fake" "$with_node")
  mkdir -p "$home/data" "$home/projects" "$home/state" "$home/config" "$fakehome"
  printf '%s\n' claude > "$home/config/crew-harness"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  touch "$home/state/.last-watcher-beat"
  mkdir -p "$home/data/$id"
  printf 'brief for %s\n' "$id" > "$home/data/$id/brief.md"

  if [ "$with_pack" = 1 ]; then
    pack="$case_dir/pack"
    mkdir -p "$pack"
    if [ "$with_gateguard" = 1 ]; then
      printf '#!/usr/bin/env node\nprocess.exit(0);\n' > "$pack/gateguard-run.js"
    fi
    printf '%s\n' "$pack" > "$home/config/crew-capability-pack"
  fi

  printf '%s\n' "$id|$home|$proj|$wt|$fakebin|$launchlog|$fakehome"
}

run_spawn() {
  local home=$1 wt=$2 fakebin=$3 launchlog=$4 fakehome=$5
  shift 5
  : > "$launchlog"
  # A minimal, deterministic PATH (not the ambient real PATH): the machine
  # running this suite may have a real `node` on PATH via a user-specific
  # directory (e.g. ~/.local/node/bin), which would silently defeat the
  # no-node-resolvable test case if the real PATH were simply prepended to.
  FM_ROOT_OVERRIDE='' FM_HOME="$home" HOME="$fakehome" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$wt" TMUX="fake,1,0" \
    FM_FAKE_LAUNCH_LOG="$launchlog" PATH="$fakebin:/usr/bin:/bin:/usr/local/bin:/usr/sbin:/sbin" \
    "$SPAWN" "$@" 2>&1
}

read_case_record() {
  IFS='|' read -r ID HOME_DIR PROJ_DIR WT_DIR FAKEBIN_DIR LAUNCH_LOG FAKEHOME_DIR <<EOF
$1
EOF
}

settings_file() {
  printf '%s/.claude/settings.local.json' "$1"
}

test_no_capability_pack_keeps_settings_unchanged() {
  local rec out status settings
  rec=$(make_spawn_case no-pack 1 0)
  read_case_record "$rec"

  out=$(run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$FAKEHOME_DIR" "$ID" "$PROJ_DIR")
  status=$?
  expect_code 0 "$status" "spawn without a capability pack should succeed"
  settings=$(settings_file "$WT_DIR")
  assert_present "$settings" "settings.local.json was not written"
  assert_not_contains "$(cat "$settings")" "PreToolUse" \
    "unset config/crew-capability-pack must not add a PreToolUse hook"
  pass "fm-spawn.sh: no capability pack keeps settings.local.json unchanged"
}

test_capability_pack_wires_pretooluse_hook() {
  local rec out status settings content
  rec=$(make_spawn_case with-pack 1 1 1)
  read_case_record "$rec"

  out=$(run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$FAKEHOME_DIR" "$ID" "$PROJ_DIR")
  status=$?
  expect_code 0 "$status" "spawn with a populated capability pack should succeed"
  settings=$(settings_file "$WT_DIR")
  content=$(cat "$settings")
  assert_contains "$content" '"PreToolUse":[{"matcher":"Edit|Write|MultiEdit"' \
    "capability pack did not wire the Edit/Write/MultiEdit PreToolUse matcher"
  assert_contains "$content" '{"matcher":"Bash"' \
    "capability pack did not wire the Bash PreToolUse matcher"
  assert_contains "$content" "GATEGUARD_EXEMPT_GLOBS='node_modules/**,.git/**'" \
    "capability pack hook command missing the exempt-globs env var"
  assert_contains "$content" "gateguard-run.js" \
    "capability pack hook command missing the gateguard-run.js path"
  assert_contains "$content" '"Stop":[{"hooks":[{"type":"command","command":"touch' \
    "capability pack wiring must not remove the existing turn-end Stop hook"
  pass "fm-spawn.sh: a populated capability pack wires the PreToolUse fact-forcing hook"
}

test_capability_pack_without_gateguard_file_is_noop() {
  local rec out status settings
  rec=$(make_spawn_case pack-no-file 1 1 0)
  read_case_record "$rec"

  out=$(run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$FAKEHOME_DIR" "$ID" "$PROJ_DIR")
  status=$?
  expect_code 0 "$status" "spawn with a pack missing gateguard-run.js should still succeed"
  settings=$(settings_file "$WT_DIR")
  assert_not_contains "$(cat "$settings")" "PreToolUse" \
    "a pack directory without gateguard-run.js must not wire a PreToolUse hook"
  pass "fm-spawn.sh: a capability pack lacking gateguard-run.js is a no-op"
}

test_capability_pack_missing_node_warns_and_skips() {
  local rec out status settings
  rec=$(make_spawn_case no-node 0 1 1)
  read_case_record "$rec"

  out=$(run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$FAKEHOME_DIR" "$ID" "$PROJ_DIR")
  status=$?
  expect_code 0 "$status" "spawn with no resolvable node must still succeed (fail open, never wedge the spawn)"
  settings=$(settings_file "$WT_DIR")
  assert_not_contains "$(cat "$settings")" "PreToolUse" \
    "with no resolvable node binary, the hook must not be wired at all"
  assert_contains "$out" "no node binary was found" \
    "a missing node binary must warn visibly instead of silently embedding a broken command"
  pass "fm-spawn.sh: a missing node binary degrades visibly instead of wiring a broken hook command"
}

test_capability_pack_not_wired_for_secondmate() {
  local rec sm out status settings
  rec=$(make_spawn_case secondmate 1 1 1)
  read_case_record "$rec"
  sm="$HOME_DIR/../secondmate-home"
  mkdir -p "$sm/bin" "$sm/data"
  printf '# Firstmate\n' > "$sm/AGENTS.md"
  printf '%s\n' "$ID" > "$sm/.fm-secondmate-home"
  printf 'charter for %s\n' "$ID" > "$sm/data/charter.md"

  out=$(run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$FAKEHOME_DIR" "$ID" "$sm" --secondmate)
  status=$?
  expect_code 0 "$status" "secondmate spawn should succeed regardless of a configured capability pack"
  assert_grep "kind=secondmate" "$HOME_DIR/state/$ID.meta" "secondmate meta missing kind=secondmate"
  settings=$(settings_file "$WT_DIR")
  assert_absent "$settings" \
    "a secondmate spawn must never write a worktree .claude/settings.local.json (no ship/scout hook wiring path)"
  pass "fm-spawn.sh: capability pack wiring never applies to secondmate spawns"
}

test_no_capability_pack_keeps_settings_unchanged
test_capability_pack_wires_pretooluse_hook
test_capability_pack_without_gateguard_file_is_noop
test_capability_pack_missing_node_warns_and_skips
test_capability_pack_not_wired_for_secondmate

echo "# all fm-spawn-capability-pack tests passed"
