# Handover: Gas City RSS Tutorial Test Run

**Read this first** if you are picking up this project after a compaction or fresh session. It captures live test-run state. The behavioral rules and design context live in memory files; this file captures what we are *doing right now*.

## What we are doing

A test run of a 7-part blog post tutorial that teaches Gas City (multi-agent orchestration SDK) by building a minimalist Hacker-News-style RSS aggregator. The user runs the GC commands and edits configs; I keep these notes; the notes become the source material for the eventual blog post.

The test run goes end to end first; the markdown chapters get written *from the notes* afterward, not in parallel. We are mid test run.

Stack: Bun + Hono + `bun:sqlite` + `hono/html` + HTMX + TypeScript. Five agents in the design (mayor + backend + frontend + dba + reviewer); we are introducing them incrementally, one chapter at a time.

## Where we are

| Chapter | Tag | State |
|---|---|---|
| 0 Setup | `chapter-0` | Done. City + rig registered. |
| 1 First contact | `chapter-1` | Done. Strict-delegator mayor, first mail+reply round-trip. Mayor created scaffold bead `rr-lhv`. |
| 2 Building the bones | `chapter-2` | Done. Backend polecat materialized, built scaffold, committed in rig (`6f9d267`), closed `rr-lhv`. |
| 3 Specialists at work | `chapter-3` | Done. dba and frontend registered, mayor's prompt updated to pre-route chains, feature delivered (HN-style index from hardcoded RSS feed). Three feature beads closed; four chapter commits in rig (scaffold, schema, ingest, render). |
| 4 The review loop | `chapter-4` | Done (commit `8bd4e43`). Reviewer polecat registered with `provider = "codex"`. Domain-label feature delivered + reviewed + entity-encoded-titles defect filed and fixed end-to-end via the review loop. Reviewer ran on Codex; no auth surprises. Notification hook for stuck-polecat paging wired in `city/.gc/settings.json`. |
| 5 Going live | `chapter-5` | Done. Three orders registered: cooldown ingest (`rss-fetch`), nightly cron VACUUM (`rss-vacuum`), 8am cron formula `rss-digest` dispatching a custom `mol-rss-digest` formula on a backend polecat that produces a real `digest.md`. `/digest` route shipped via mayor handoff to close the visible loop (rig commits `f528dd4` frontend + `d01b914` backend, `marked` dep). Notification hook removed (wrong primitive). Three structural gotchas surfaced: order scope follows file location, rigs need `formulas_dir`, formulas referenced by rig-scoped orders must live in the rig. |
| 6 Capstone | `chapter-6` | Done. Single mayor handoff produced full FTS5 search across all four lanes. Mayor decomposed into four predicted beads, then inserted a fifth (`rr-gq4`) mid-flight when an ingest gap surfaced. Reviewer ran isolated end-to-end testing on port 3001, filed two fix beads (`rr-etw` UX, `rr-brg` doc). Seven beads total, all closed. Wall clock 27 min. Two new gotchas: mail to polecats with no live session fails (use bead descriptions for context), and predicted four-bead decompositions can grow during execution without breaking. |

## Immediate next step

**Test run complete.** All seven chapters tagged (`chapter-0` through `chapter-6`). Source notes in `notes/` cover Parts 0 through 6. Search works end to end, three orders ticking, agent-generated digest rendering at `/digest`.

What is left to do:

1. **Write the seven markdown chapters in `tutorials/`** from the source notes. Production workflow per `project_tutorial_design.md` is test-then-write, and we are now in the write phase. The notes are the input; CommonMark markdown chapters per chapter are the output. Voice rules from `feedback_writing_style.md` apply (no em dashes, no LLM tells).
2. **Reflect Part 5 honestly in the Part 4 chapter writeup.** The Notification hook was introduced in Part 4 and removed in Part 5 because it was the wrong primitive (idle pings flooded the human inbox). Part 4's chapter cannot present the hook as the answer. It either gets honest about the rethink or removes the hook section entirely; my lean is honest-about-the-rethink, because the failure mode is itself instructive.
3. **Decide what to do about the alert-primitive gap.** Notification hook gone, no replacement. Options for the chapter writeups: (a) leave it as an honest open question in Part 5's "still open" section, (b) propose a candidate (osascript native notification, terminal bell, webhook) and call it future work, (c) build one before publishing. My lean is (a) for the blog series and (b) as a follow-up post if the reaction wants it.
4. **Cosmetic: improve `mol-rss-digest` to close the parent molecule, not just the step bead.** One-line follow-up; not blocking publish.
5. **Re-check the dashboard if `brew upgrade` lands a v1.0.x newer than 2026-04-27.** Could change the recommended overview tooling for the chapter.

## What just happened (Part 3 outcome)

- User registered `dba` and `frontend` polecats via `gc agent add` + manual `[[agent]]` block edits in pack.toml. Same two-step pattern as Part 2's backend.
- I wrote three prompt templates (dba, frontend, mayor update) under one-off authorization. Mayor's prompt now teaches pre-routing entire chains via `gc sling --on mol-do-work` rather than the manual nudge loop.
- User restarted the mayor with `gc handoff --target mayor "<feature subject>" "<feature body>"` so the new prompt loaded and the feature mail was waiting.
- Mayor decomposed the feature into three beads (`rr-iv6` schema, `rr-i9v` ingest, `rr-96c` render), wired deps with `bd dep add`, slung the first with `--on mol-do-work`.
- After user pushback on the manual-nudge framing, two recovery slings (`gc sling rss-reader/backend rr-i9v --on mol-do-work` and the same for frontend) stamped `gc.routed_to` on the remaining beads. The chain then ran hands-off: backend polecat spawned automatically when rr-iv6 closed and rr-i9v became ready; frontend polecat spawned when rr-i9v closed and rr-96c became ready.
- Final state in `rss-reader/`: four commits (`6f9d267` scaffold, `fd8274f` schema, `0ea0f57` ingest, `3daafff` render). Three feature beads closed. Server boots, `/api/items` returns N HN items, `/` renders the HN-style index.
- Major mid-chapter learning: GC auto-dispatches on `gc.routed_to` metadata via PR#1126 (merged 2026-04-23). Sling stamps the metadata; reconciler spawns/wakes the right agent when the bead becomes ready. Pre-route the whole chain upfront, then hands-off. Memory saved at `project_routed_to_auto_dispatch.md`.
- Tutorial helper added at `bin/overview.sh` because the v1.0.0 dashboard is broken (request-flood, GH#1168, fix on main but no release yet).
- Mid-chapter notes correction: my Part 2 writeup of `gc reload` was wrong about why "no config changes" appears. The fsnotify watcher (GH#926) picks edits up automatically; `gc reload` is a stabilization tool, not a "kick". Notes corrected.

## Workspace layout

```
/Users/jonaseriksson/code/gas-city-tutorial/   parent repo
├── city/                                       Gas City workspace
│   ├── pack.toml                               (mayor + backend [[agent]] blocks; backend has dir = "rss-reader")
│   ├── city.toml
│   └── agents/
│       ├── mayor/prompt.template.md            strict-delegator version
│       └── backend/prompt.template.md          rss-reader specialist
├── rss-reader/                                 the rig (its own git repo, gitignored from parent)
├── design/tutorial-design.md
├── notes/                                      source material for the blog
│   ├── 00-setup.md
│   ├── 01-first-contact.md
│   ├── 02-building-bones.md
│   └── HANDOVER.md (this file)
└── tutorials/                                  empty until test run completes
```

`rss-reader/` is its own git repo (required because bd auto-export needs `git add` to work). The parent gitignores `rss-reader/`. Treat them as independent histories.

## Hard-won gotchas (read these before doing anything)

**Workflow split (memorized):**
- User: all `gc` commands, all config file edits (`pack.toml`, `agent.toml`, `prompt.template.md`, `formula.toml`, `order.toml`).
- Me: git operations (init, add, commit, tag, rm --cached, amend), notes files, memory, read-only Bash inspection.
- Default to handing the keyboard to the user; one-off "you do it" authorizations do not become standing permission.

**v1.0.0-specific issues to keep in mind:** User is on `gc 1.0.0` (Homebrew, built-from-source on 2026-04-27 12:30:47, latest released tag is `v1.0.0` from 2026-04-21). Several relevant fixes landed on `main` after this build but no new release tag has been cut, so `brew upgrade` does not help.
- **Dashboard is unusable** (request flood, [GH#1168](https://github.com/gastownhall/gascity/issues/1168), closed 2026-04-28). Fixes: [PR#1339](https://github.com/gastownhall/gascity/pull/1339) and [PR#1376](https://github.com/gastownhall/gascity/pull/1376) merged 2026-04-27 evening. Workaround: `bash bin/overview.sh` (committed in repo); use it standalone or under `watch -n 3`.
- **GC#1209** (open) — beads layer `ApplyEvent("bead.updated")` writes unconditionally on every event. Cosmetic noise in our small city; not blocking.
- **GH#1293 / GH#1177** (both open) — `gc status` and `gc session list` slow paths. Not yet bitten us hard at this scale.
- **Re-check the dashboard after any `brew upgrade` once a v1.0.x newer than 2026-04-27 lands.** If usable, switch the chapter to recommend it.

**Bug GH#1232: `bd create` fails on every write path** with `database not initialized: issue_prefix config is missing`. Already worked around for the city `hq` DB and the rig `rr` DB. If we hit it again on a new database (e.g. when adding a new rig), apply the same direct dolt SQL fix:

```bash
cd <city>/.beads/dolt
dolt --use-db <db-name> sql -q "
  INSERT INTO config (\`key\`, value) VALUES ('issue_prefix', '<prefix>')
    ON DUPLICATE KEY UPDATE value='<prefix>';
  CALL dolt_commit('-Am', 'set issue_prefix');
"
```

**Bug GH#1139: idle Claude Code sessions do not auto-poll** for new mail or routed work. Hooks fire on `SessionStart`, `UserPromptSubmit`, `Stop`, `PreCompact`, none of which trigger on a fully-idle session. The canonical pattern for "send mail and wake the recipient" is **`--notify`** on the send:

```bash
gc mail send <agent> -s "<subject>" -m "<body>" --notify
gc mail reply <id> -s "<subject>" -m "<body>" --notify
```

`--notify` queues a recipient nudge after the mail bead is written ([GH#1370](https://github.com/gastownhall/gascity/issues/1370), [GH#1404](https://github.com/gastownhall/gascity/pull/1404), both closed). The recipient wakes automatically.

If you forgot `--notify` on an already-sent mail and the recipient is idle, the manual two-step still works as a recovery:

```bash
gc mail send <agent> -s "..." -m "..."             # without --notify
gc session submit <agent> "Check your inbox."      # manual nudge afterward
```

Do **not** use `gc session submit ... --intent interrupt_now` (interrupts mid-turn work; bad pattern for everyday flow). Default intent on submit is correct: it wakes idle sessions and queues for in-turn sessions.

**Earlier note that `--notify` "writes to stdin and sits in buffer" was stale** — it was true at one point ([GH#619](https://github.com/gastownhall/gascity/issues/619), closed) and the chain of fixes through GH#1404 made it work properly. Treat `--notify` as the canonical send-and-wake primitive.

**Doctor's `v2-agent-format` warning is a known false positive** ([GH#1175](https://github.com/gastownhall/gascity/issues/1175), [GH#1244](https://github.com/gastownhall/gascity/issues/1244)). Schema=2 pack.toml `[[agent]]` blocks ARE the intended layout. Ignore the warning, do not try to "fix" it.

**`beads.role not configured` warning** clears with `git config beads.role maintainer` from inside the parent git repo. Already done in this test run.

**`gc agent add --dir <rig>` does NOT update pack.toml.** It scaffolds `agents/<name>/{agent.toml,prompt.template.md}` only. The human must add the `[[agent]]` block with `dir = "rss-reader"` to `pack.toml` manually. The dir field in `agent.toml` does NOT propagate into the resolved config in our setup. Per chapter design, the chapter teaches both steps; do not bypass `gc agent add`.

**Pre-route entire bead chains; do not orchestrate manual nudges.** `gc sling <agent> <bead-id>` stamps `gc.routed_to=<agent>` on the bead. The reconciler auto-spawns/wakes the matching polecat when the bead becomes ready (GC#1126 merged 2026-04-23). For multi-step chains: create all beads, wire deps with `bd dep add`, sling all of them upfront with `--on mol-do-work` (slinging blocked beads is fine; the metadata is set, the bead waits). After that the orchestrator (mayor) is hands-off. Detailed memory at `project_routed_to_auto_dispatch.md`. **Do not** propose "wait and watch" mayor loops.

**Slinging with `--on <formula>` creates a convoy + a molecule wrapper around the work bead.** When inspecting `bd list`, you will see auto-convoys (`sling-<bead-id>`) and `mol-do-work` molecules with sub-task beads, alongside the actual feature task bead. This is bookkeeping noise, not bugs. Worth a sidebar in the chapter.

**`gc mail inbox` syntax: positional, not `--to`.** `gc mail inbox mayor` is right; `gc mail inbox --to mayor` errors with "unknown flag." Same for other mail subcommands; check `--help` rather than guessing.

**`watch` + `git log` needs `--no-pager`.** Otherwise git seizes the TTY and `watch` becomes unusable. The `bin/overview.sh` helper uses `git --no-pager log`.

**`gc reload` is mostly a no-op (and that is correct).** The controller's fsnotify watcher (GH#926) picks up edits to `pack.toml`, `agent.toml`, and prompt templates within milliseconds and applies them at the next reconciler tick. By the time you call `gc reload`, the in-memory config matches disk and reload reports "No config changes detected." That is a positive signal, not a failure. Reload matters only when the watcher missed something (CI, sandbox, environment vars).

**`gc handoff --target mayor` does NOT restart `mode = "always"` named sessions.** Per `gc handoff --help`, always-on named sessions are "on-demand configured" and handoff just sends mail without killing. The new prompt template will not load. For a real restart that picks up prompt or settings.json edits, use `gc session kill mayor` — the reconciler respawns the session with the latest config. `gc handoff` is for "deliver mail and continue conversation," which is different from "load new prompt."

**`gc reload` may say "controller is busy"** during a reconcile tick. Retry in a few seconds. Buffered-channel fix in [GH#1127](https://github.com/gastownhall/gascity/issues/1127), still open as of build cutoff.

**`gc mail reply` requires `-s` subject** (does not auto-Re from parent). The mayor learned this the hard way; the strict-delegator prompt now lists the exact reply syntax.

**`gc mail check` exits 1 when there is no mail** (intentional, useful for shell scripts; not an error).

**Use `gc mail peek <id>` not `gc mail read <id>` when a human inspects an agent's mail.** `read` marks the message as read and removes it from the recipient's `gc mail check` (unread-only) result, which can starve the agent of work it needs to act on. `peek` shows the body without mutating state. If you accidentally use `read`, recover with `gc mail mark-unread <id>`.

**Notification hook from Part 4 has been REMOVED 2026-05-01.** Claude Code's `Notification` event fires on both permission prompts and plain idle (60s+); our mail-to-`human --notify` design flooded the human inbox with "X needs attention" from idle mayor + idle dog pool. A `matcher: "permission_prompt"` filter would suppress idle, but the user's call was that mail is the wrong push channel regardless. The hook block was deleted from `city/.gc/settings.json`. Permission-prompt-stuck polecats are invisible to gc events again (same gap as pre-Part-4). Open design question: what is the right alert primitive (osascript native notification, terminal bell + overview tile, webhook)? Full writeup in `notes/05-going-live.md`. The Part 4 chapter writeup will need to be honest about the rethink rather than presenting the original hook as the answer. Live sessions still hold the old hook in memory; `gc session kill mayor` reloads the cleaner settings.

**`.gc/settings.json` is gitignored by default in city.** The default `.gitignore` excludes the entire `.gc/` directory. To track config files like `settings.json`, use an allowlist pattern in `city/.gitignore`:
```
.gc/*
!.gc/settings.json
```
Same shape as the existing `.beads/*` + `!.beads/config.yaml` allowlist.

**macOS case-insensitive filesystem aliases break `gc start`.** Real on-disk casing is `/Users/jonaseriksson/Code/gas-city-tutorial/city`. If you ever invoke `gc start` from `~/code/...` (lowercase), dolt's runtime state files get written with the lowercase `data_dir`, and the next `gc start` from the canonical capital path sees `invalid managed dolt runtime state` because `internal/pathutil/pathutil.go:70` `SamePath` does not case-fold. Two dolt sql-servers fight over the same data dir; everything jams. **Fix:** kill the orphan lowercase-path dolt (`kill <pid>` from `pgrep -fl 'dolt sql-server'`); the supervisor's auto-retry then succeeds. **Prevention:** always `cd /Users/jonaseriksson/Code/...` (capital `C`); a shell alias makes this automatic. The same casing trap also bit `bin/overview.sh` during Part 5: a hardcoded lowercase `CITY=` made the watch loop hammer dolt with a recovery storm every 3 seconds, which broke config reloads and stalled the order dispatcher. The script was patched (Part 5) and a single canonical-path watch loop is the only correct way to run it. Full writeup in `notes/05-going-live.md` under "Pre-chapter recovery". No GH issue tracks this; do not file yet per user directive 2026-05-01.

**Order scope is file-location, not pool-field.** Files under `city/orders/` create city-scope beads (`rt-` prefix). Files under `<rig>/orders/` create rig-scope beads (`rr-` prefix). The `pool = "<agent>"` field in the order TOML names the target agent but does NOT determine which bead store the work bead lands in. Source: `internal/orders/order.go:51` (`Rig` is `toml:"-"`, set by the scanning caller). **Consequence:** if you put an order at city level with `pool = "<rig-bound-agent>"`, the dispatcher creates beads in the wrong store and the agent never picks them up. The order will fire forever, beads pile up, no work happens. **Fix:** move the order file to `<rig>/orders/`. Full writeup in `notes/05-going-live.md` under "What happened during the test run."

**Rigs need `formulas_dir` (or pack include) in `city.toml` to register exclusive formula layers.** Without one, every rig's formula layers are identical to the city's, and `rigExclusiveLayers(layers, cLayers)` returns empty in `scanAllOrders`. Result: the rig's `orders/` directory is never scanned even if it exists, and `gc order list` never shows rig-scoped orders even after you put files in `<rig>/orders/`. Source: `internal/config/pack.go:820-847` (`ComputeFormulaLayers`) plus `cmd/gc/cmd_order.go:209-225`. **Fix:** add `formulas_dir = "../<rig>/formulas"` to the `[[rigs]]` block in `city/city.toml` and create that directory (can be empty). The rig's `orders/` directory becomes scannable as soon as the rig has at least one rig-exclusive formula layer registered.

**In this build, custom formulas referenced by rig-scoped orders must live in the rig's formula dir.** Despite `ComputeFormulaLayers` producing rig layers that include city formulas as a base, the in-memory dispatcher's formula resolver fails with `formula "<name>" not found in search paths` if the formula file is at `city/formulas/` and the order is at `<rig>/orders/`. **Fix:** put the formula in `<rig>/formulas/` AND run `gc supervisor reload` after the move. fsnotify alone does not rebuild the layer cache reliably for moves; explicit reload is needed.

**`* * * * *` is a dangerous testing schedule for formula orders.** Every minute fires creates a new molecule + tracking bead + potential polecat spawn. The pool can't keep up; orphan molecules pile up; cleanup is manual. **Use `gc order run <name>` for one-shot verification** (no history written but exec/formula runs), or `*/5 * * * *` if you really need to see auto-fire on a short loop and let the polecat finish before the next.

**Formula `{{issue}}` resolves to the step bead, not the parent molecule.** If a formula step says `bd update {{issue}} --status=closed`, the polecat closes the step it was given (e.g. `rr-1lw.1`), not the parent molecule (`rr-1lw`). The molecule sits open, blocking pool drain. **Fix in formula authoring:** drop the explicit "close the bead" instruction in the step description (the runtime closes step beads on completion; the molecule auto-closes when all children close), or close the parent explicitly via a `bd show {{issue}} --json | jq -r .parent_id` lookup.

**Polecats invisible in `gc session list`** until they run. `gc status` only shows named sessions and scaled pools. A newly-registered polecat agent is still configured correctly even if invisible.

**Rigs must be git repos** (run `git init` inside the rig dir). `gc rig add` does not init one. `gc doctor` flags `rig:<name>:git — not a git repository`. Otherwise bd's auto-export prints a warning on every write.

**Symlinks in `city/.claude/skills/`** are absolute paths into `.gc/system/packs/.../skills/` which is itself gitignored. Would dangle on any clone. Already gitignored at the parent level. Recreated locally on every `gc init`.

## Investigation discipline

Two specific failures of mine the user called out:

1. Don't assume "this is a bug, here's the workaround." Investigate first: did we do something wrong? Are we misled by a false-positive warning? Check the actual command's help, the docs, `city/.gc/system/packs/` for canonical examples, then GH issues. Most of the time the problem is user error, half-completed step, or false-positive warning. Reserve "bug + workaround" framing for things tied to a real GH issue.

2. Use `gh api repos/gastownhall/gascity/issues/<number>` for fetching specific issues — `gh issue view` errors out on this repo because of a GraphQL projects-classic deprecation issue. For listing/searching, `gh api "repos/gastownhall/gascity/issues?state=all&per_page=100" --paginate -q '.[]| ...'` works.

## Voice rules (also memorized)

- No em dashes anywhere. Use commas, parentheses, periods, or restructured sentences.
- No common LLM-tell phrases (delve, leverage, robust, seamless, "imagine if", "in summary", "furthermore"). Read drafts aloud; if it sounds like a corporate blog post, rewrite.
- These rules apply to tutorial markdown, blog content, conversational replies, and notes files.

## Memory files to read

In `/Users/jonaseriksson/.claude/projects/-Users-jonaseriksson-Code-gas-city-tutorial/memory/`:

- `MEMORY.md` (index)
- `feedback_writing_style.md`
- `user_gc_knowledge.md`
- `project_tutorial_design.md` (the full design with chapter outline, agent roster, audience, etc.)
- `feedback_test_run_workflow.md` (the user/agent split)
- `feedback_git_amend.md`
- `project_bd_issue_prefix_bug.md`
- `feedback_investigate_before_patching.md`

The fresh agent should read these on startup if they are not already in context.
