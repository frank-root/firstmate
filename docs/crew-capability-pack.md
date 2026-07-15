# Crew capability packs

A capability pack is a local, gitignored directory of crewmate-facing add-ons: brief text, PreToolUse hooks, or both.
It is **opt-in and ships empty for every user of this shared template**, the same framing as X-mode (section 14): nothing in this file changes any behavior until a captain points `config/crew-capability-pack` at a real directory.

## Activation

`config/crew-capability-pack` (local, gitignored) holds one line: the absolute path to the pack directory.
Absent, empty, or pointing at a directory missing the expected files means every consuming script no-ops - this is the default state for every installation.
The pack directory itself is expected to be gitignored too (add its own entry, e.g. `/ecc-pack/`, next to `config/crew-capability-pack` in `.gitignore`) since it typically vendors third-party code and embeds absolute local paths.

Inherited into every secondmate home as the literal file, same as `config/crew-harness`: a secondmate spawns its own ship/scout crewmates through the identical `bin/fm-spawn.sh` path, so it needs the same pointer to stay consistent with the primary's posture.
Because the value is an absolute filesystem path, a secondmate's copy of the config file can point at the exact same on-disk pack directory as the primary - the pack itself does not need to be duplicated per home.

## Expected shape

Both files below are individually optional; a pack may ship either, both, or neither (an empty pack is just a no-op directory).

- `defense-preamble.md` - plain Markdown, prepended into every scaffolded ship and scout brief (`bin/fm-brief.sh`) under a "# Prompt Defense Baseline" heading. Static content only: it is brief text the crewmate reads, not something that executes.
- `gateguard-run.js` - a Node script wired as a Claude PreToolUse hook (`bin/fm-spawn.sh`), for `Edit|Write|MultiEdit` and `Bash` tool calls, on Claude ship and scout crewmate spawns only (never secondmates - see "Scope" below). Must speak Claude Code's PreToolUse hook protocol: read the hook JSON on stdin, and on stdout either emit nothing (allow) or a `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",...}}` JSON body (deny).
- `PROVENANCE.txt` - required whenever a pack vendors code from elsewhere (which is the expected case, not a special one). States the source repository, the exact commit, and the specific file(s) vendored, plus the pack's own kill switch if it has one. This is an explicit requirement so a pack can be re-diffed against its upstream on demand, the same evidentiary bar this repo holds itself to elsewhere (`firstmate-coding-guidelines`).
- Any supporting files `gateguard-run.js` itself `require()`s (e.g. a `hooks/` or `lib/` subdirectory). Firstmate's own scripts never read these directly; they exist purely for the pack's own script to load.

Firstmate's scripts check only for the *presence* of `defense-preamble.md` and `gateguard-run.js` (a plain `-f` test).
They do not parse, lint, or validate either file's contents - a pack's content is trusted, local, captain-supplied configuration, not something firstmate verifies.

## What runs, when, and its blast radius

`defense-preamble.md` never executes. It is read once per brief scaffold and concatenated into that brief's text.

`gateguard-run.js`, when wired, runs as an ordinary local Node process, once per matching tool call, with the same OS-user privileges as the crewmate's own shell.
This is **not a sandbox boundary** - it is automation convenience for a captain who trusts what they vendored, not a defense against an adversarial pack author.
The only party who can populate `config/crew-capability-pack` is whoever controls this local, gitignored config, so the real trust boundary is "does the captain trust what they put in the pack directory," not "is this safe against a hostile pack."

A hook wired this way sits directly in the crewmate's tool-call path, so its own failure modes matter:

- **Fail-open is a contract the pack itself must uphold, not something firstmate enforces.** The reference implementation (see `PROVENANCE.txt` in a populated pack) demonstrates the pattern worth copying: wrap the hook's core logic in a try/catch and exit 0 (allow) on any internal error, so a bug in the hook can produce unwanted friction but never wedge a crewmate outright. A pack author who skips this can genuinely block tool calls on error.
- **Missing dependency degrades safely and visibly.** `bin/fm-spawn.sh` resolves a `node` binary (`PATH`, then `$HOME/.local/node/bin/node`) and verifies it is actually executable before wiring the hook. If neither resolves, the hook is not wired - the spawned crewmate's settings are byte-identical to the no-pack case - and a warning is printed to spawn output rather than the wiring silently degrading to a broken command string with no signal anywhere.
- **Kill switch is the pack's own, not firstmate's.** The reference implementation honors an env var (documented in the pack's own `PROVENANCE.txt` and defense preamble) that disables it outright. Firstmate does not provide a generic kill switch beyond removing `config/crew-capability-pack` itself, which stops new spawns from wiring the hook but does not retroactively affect already-spawned crewmates.

## Scope: Claude ship/scout crewmates only, never secondmates or the primary

The PreToolUse wiring applies only to Claude-harness ship and scout crewmate spawns.
It is intentionally exempt for `kind=secondmate` spawns (a secondmate is a long-running supervisory peer, not a task executor, and pays the same friction cost the primary firstmate session itself never pays) and for every non-Claude harness (the hook protocol used here is Claude-specific; other harnesses would need their own wiring under their own hook mechanism).
The brief-text half (`defense-preamble.md`) is scope-independent - it renders into both ship and scout briefs, but is inert prose with no enforcement mechanism of its own.

## Scope decision: vendor faithfully, do not reimplement a smaller parser

A capability pack that vendors a destructive-command detector faces a real choice: keep the upstream implementation (often hardened against non-obvious bypasses - quoted command words, `sh -c` wrapping, nested subshells, and similar) or write a smaller, easier-to-audit check scoped to a single captain's own trusted crewmates.

The recommendation for this template is to **keep a faithfully vendored implementation** rather than reimplement a leaner one, for reasons specific to how firstmate crewmates actually operate, not just "more coverage is better":

- Crewmates routinely ingest untrusted external content as part of normal work - PR descriptions, issue text, fetched web pages - and act on it autonomously. A prompt-injection payload embedded in that content is a more realistic adversary here than "a stranger installs a shared plugin," and it is exactly the class of adversary a hardened, bypass-resistant detector is built to resist.
- A from-scratch, smaller detector reintroduces the same class of risk it is meant to avoid: it trades a maintained implementation with cited, advisory-driven hardening for new code with its own untested bypass surface.
- The failure mode of a parser bug here is soft in both directions (see "Fail-open" above): a false positive is friction, a false negative is a missed detection, and neither crashes or silently corrupts anything. That significantly lowers the cost of carrying more vendored code than a "keep it minimal" instinct would otherwise suggest.

Re-evaluate this if the specific pack in use diverges from that shape (for example, a pack whose hook does not fail open, or one with no `PROVENANCE.txt` to re-diff against upstream) - the recommendation is for a faithfully vendored, evidenced pack, not vendoring in general.

## Verified

2026-07-14, this repo: `bin/fm-brief.sh` and `bin/fm-spawn.sh`'s capability-pack wiring was exercised against a real populated pack (a `defense-preamble.md` and a stub `gateguard-run.js`) and against an unset `config/crew-capability-pack`.
Confirmed: the unset case renders brief output and `.claude/settings.local.json` byte-identical to the pre-pack baseline (no stray blank sections, no altered JSON), and the set case renders the preamble cleanly into both ship and scout briefs with correct single-blank-line spacing.
