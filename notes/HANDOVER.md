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
| 5 Going live | not yet started | Plan: introduce `order` primitive (cooldown + cron) for periodic feed-fetch. Likely first custom formula authoring (deferred from Part 4 per design). |
| 6 Capstone | not yet started | |

## Immediate next step

Part 4 done and tagged. Mayor was killed and respawned to load the new Notification hook. Part 5 ("Going live") is next: introduce orders, schedule periodic feed-fetch, likely write the first custom formula. Reader-writes-one-config-from-scratch pedagogy level per the locked design.

Start by re-reading `project_tutorial_design.md` for the Part 5 concept payload (orders: cooldown + cron), then sketch a chapter plan for the user to confirm before running anything.

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

**Notification hook for stuck-polecat paging lives in `city/.gc/settings.json`.** Claude Code's `Notification` hook fires when a session is waiting for permission or has been idle 60s+; we wire it to `gc mail send human --notify` so the human gets paged. GC has no upstream equivalent ([GH#534](https://github.com/gastownhall/gascity/issues/534) closed `not_planned`), so this hook is the only path. The settings file applies to all managed Claude Code sessions in the city; new sessions read it on spawn, live sessions need a restart (`gc session kill <name>`) to reload.

**`.gc/settings.json` is gitignored by default in city.** The default `.gitignore` excludes the entire `.gc/` directory. To track config files like `settings.json`, use an allowlist pattern in `city/.gitignore`:
```
.gc/*
!.gc/settings.json
```
Same shape as the existing `.beads/*` + `!.beads/config.yaml` allowlist.

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
