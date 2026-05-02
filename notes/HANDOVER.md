# Handover: Gas City RSS Tutorial

**Read this first** if you are picking up this project after a fresh session. The behavioral rules and design context live in memory files; this file captures live project state and the hard-won gotchas worth carrying forward.

## What this project is

A seven-part tutorial that teaches Gas City (multi-agent orchestration SDK) by building a minimalist Hacker-News-style RSS aggregator. The user is publishing it as a blog series on their personal site, with a possible contribution back to the Gas City community.

Stack: Bun + Hono + `bun:sqlite` + `hono/html` + HTMX + TypeScript. Five agents (mayor + backend + dba + frontend + reviewer); introduced incrementally one chapter at a time.

## Where we are: drafts complete, blog adaptation deferred

Two phases finished:

1. **End-to-end test run.** All seven chapters captured by tag `chapter-0` through `chapter-6` on the parent repo. The run produced the source notes in `notes/00-setup.md` through `notes/06-capstone.md`.

2. **Tutorial markdown chapters drafted.** All seven live in `tutorials/`. Three commits on `main`:
   - `e9ba6c8` initial drafts from notes
   - `d07ffb2` cleanup pass (sidebars marked with `<details><summary>`, prose tightened, duplications collapsed, unlikely-error entries removed)
   - `58991eb` source-code audit fixes (bead-prefix derivation explained, sling error format, `mol-do-work` step name)

The chapters are CommonMark, ~190-410 lines each, total ~1900 lines. Ready for adaptation to a blog platform.

**What is next:** the user has a personal site they will publish on. Decisions deferred until they pick it up:

- Whether to use `<details>` blocks as-is (they collapse on most platforms) or transform into the platform's native sidebar/aside syntax.
- Whether to add platform-specific frontmatter (Astro, Hugo, Jekyll, Mintlify all have their own).
- Whether to add screenshots or transcript blocks (currently neither; design said markdown is the primary artifact).
- Whether to contribute upstream to docs.gascityhall.com after the personal-site publish lands.

## Workspace layout

```
/Users/jonaseriksson/code/gas-city-tutorial/   parent repo (city configs + tutorial source)
├── city/                                      Gas City workspace
│   ├── pack.toml                              5 [[agent]] blocks: mayor, backend, dba, frontend, reviewer
│   ├── city.toml                              has formulas_dir on the rss-reader rig
│   ├── agents/                                5 prompt templates, all final
│   └── orders/                                rss-fetch + rss-vacuum (city-scoped)
├── rss-reader/                                rig (its own git repo, gitignored from parent)
│   ├── formulas/mol-rss-digest.toml
│   └── orders/rss-digest.toml                 rig-scoped, dispatches the formula
├── notes/                                     test-run source notes (input to chapters)
│   ├── 00-setup.md ... 06-capstone.md
│   └── HANDOVER.md (this file)
├── tutorials/                                 the polished chapters, ready to adapt
│   └── 00-setup.md ... 06-capstone.md
├── design/tutorial-design.md
└── bin/overview.sh                            CLI overview helper used by the chapters
```

`rss-reader/` is its own git repo (required because `bd`'s auto-export needs `git add`). The parent gitignores `rss-reader/`. Treat them as independent histories. Latest rig commits are search + digest work; fully working app at `bun run src/index.ts` (port 3000).

## Open follow-ups (not blocking publish)

1. **Alert primitive for stuck-on-permission polecats.** The Part 4 Notification hook was removed in Part 5 because it flooded the human inbox with idle pings. Ch 4's "permission-prompt-stuck gap" sidebar is honest about this. Right shape is probably a small osascript wrapper or terminal bell tied to the same Claude Code `Notification` event; we did not build it.

2. **`mol-rss-digest` parent-molecule close.** The formula's bead-close step uses `bd update {{issue}} --status=closed`, which closes the step bead, not the parent molecule. Cosmetic; the work completes and the digest commits cleanly. Fix would be `bd show {{issue}} --json | jq -r .parent_id` then close that. Tutorial Ch 5 flags it.

3. **`brew upgrade` re-check.** v1.0.0 has the dashboard fetch-flood bug ([GH#1168](https://github.com/gastownhall/gascity/issues/1168), fix on main not yet released). If a newer release lands, re-test the dashboard and consider switching the chapter's recommended overview tool from `bin/overview.sh` to `gc dashboard serve`.

## Hard-won gotchas (reference for any future GC work in this project)

These are durable observations worth carrying forward, not all in the tutorial. If you do new GC work in this repo, scan this list before touching things.

**v1.0.0 specifics (build cutoff 2026-04-27).** Several relevant fixes are on `main` but not in any released tag:
- Dashboard fetch flood ([GH#1168](https://github.com/gastownhall/gascity/issues/1168), fix in PR#1339 + PR#1376 merged 2026-04-27 evening, no release yet).
- `gc status` slow path ([GH#1293](https://github.com/gastownhall/gascity/issues/1293), [GH#1177](https://github.com/gastownhall/gascity/issues/1177), open).
- Beads layer cosmetic noise ([GC#1209](https://github.com/gastownhall/gascity/issues/1209), open).

**Bug GH#1232** (`bd create` fails on first write to a fresh database with `database not initialized: issue_prefix config is missing`). Surfaces twice in the test run: city store on first `gc session wake`, rig store on first sling. Workaround applied to both stores during the test run; tutorial chapters 1 and 2 carry the inline fix:

```bash
cd <city>/.beads/dolt
dolt --use-db <hq|rr> sql -q "
  INSERT INTO config (\`key\`, value) VALUES ('issue_prefix', '<rt|rr>')
    ON DUPLICATE KEY UPDATE value='<rt|rr>';
  CALL dolt_commit('-Am', 'set issue_prefix');"
```

**`gc handoff --target mayor` does NOT restart `mode = "always"` named sessions.** Confirmed in `gc handoff --help`: "for on-demand configured named targets, sends mail and returns without killing the session." So handoff delivers mail but does not load a new prompt. For prompt changes, use `gc session kill mayor`; the reconciler respawns with the new template. Tutorial Ch 2/3/4 use this pattern.

**`gc agent add --dir <rig>` scaffolds files; it does not register the agent.** `gc agent add --help` is explicit: "These files live in the city directory and do not append `[[agent]]` blocks to `city.toml`." `pack.toml` is the source of truth for registration; you must add the `[[agent]]` block by hand. Verified in source at `cmd/gc/cmd_agent.go:406-407`.

**Bead prefixes are derived from city/rig name, not hardcoded.** `DeriveBeadsPrefix(name)` at `internal/config/config.go:738`: split on `-`/`_`, take first letter of each part. So `rss-tutorial` → `rt`, `rss-reader` → `rr`. If a future rig is named differently, the prefix changes.

**`gc reload` is mostly a no-op** because the controller's fsnotify watcher (recursive after [GH#926](https://github.com/gastownhall/gascity/issues/926), closed) picks up edits to `pack.toml`, `agent.toml`, and prompt templates within milliseconds. By the time you call `gc reload`, the in-memory config matches disk and reload reports "No config changes detected." That is a positive signal. Reload matters only when the watcher missed something or you are in a sandbox without fsnotify.

**`gc supervisor reload` IS necessary when adding new formula files or moving orders between scopes.** fsnotify alone does not always rebuild the layer cache for new files. Tutorial Ch 5 step 3d uses this.

**`--notify` is the canonical send-and-wake primitive.** Earlier states of `gc` had unreliable `--notify`; the chain of fixes through [GH#1370](https://github.com/gastownhall/gascity/issues/1370) and [GH#1404](https://github.com/gastownhall/gascity/pull/1404) (both closed) made it work. Default to `--notify` whenever mailing an agent that might be sitting idle.

**Order scope follows file location, not the `pool` field.** Files under `city/orders/` create city-scoped beads (`rt-` prefix); files under `<rig>/orders/` create rig-scoped beads (`rr-`). The `pool = "<agent>"` field names the target, but does NOT determine which bead store the work bead lands in. Source: `internal/orders/order.go`. Consequence: putting a rig-pool order at city level fails silently (beads in city store, polecat reads from rig store, nothing connects). Fix: move the order TOML to the rig.

**Rigs need `formulas_dir` (or pack include) in `city.toml` for their `orders/` directory to be scanned.** Source: `internal/config/pack.go` (`ComputeFormulaLayers` filters via `rigExclusiveLayers`) and `cmd/gc/cmd_order.go`. Without it, `gc order list` ignores the rig. The field is at `internal/config/config.go:421` (not deprecated despite some confusion in the audit).

**Custom formulas referenced by rig-scoped orders must live in the rig's formula dir** in this build (v1.0.0). Even though `ComputeFormulaLayers` produces rig layers that include city formulas as a base, the in-memory dispatcher's resolver fails with `formula "<name>" not found in search paths` if the formula is at `city/formulas/` and the order is at `<rig>/orders/`. Move the formula to the rig and run `gc supervisor reload`.

**Cron evaluator uses local time, not UTC.** Source: `internal/orders/triggers.go:104-130` uses `time.Now()` methods directly with no `.UTC()`. So `0 4 * * *` is 4am wherever the laptop is configured.

**Slinging with `--on <formula>` creates extra beads** (sling convoy + molecule + step beads + the actual work bead). Bookkeeping noise, not bugs. Tutorial Ch 2 hand-waves this; Ch 3 explains the wisp/molecule/convoy vocabulary fully.

**`gc handoff --help`, `gc agent add --help`, `gc order check`** are reliable references; the source's user-facing strings match what the tutorial quotes. When in doubt, run `gc <cmd> --help`.

**macOS case-insensitive filesystem trap.** Real on-disk casing is `/Users/jonaseriksson/Code/gas-city-tutorial`. Invoking `gc start` from `~/code/...` (lowercase) makes dolt write runtime state with the lowercase path; subsequent capital-path invocations see "invalid managed dolt runtime state" because `internal/pathutil/pathutil.go:70 SamePath` does not case-fold. The tutorial does not surface this gotcha (it bit us during the test run because `bin/overview.sh` had hardcoded lowercase paths under `watch -n 3`). For any future work in this repo: always `cd /Users/jonaseriksson/Code/...` (capital `C`). No GH issue tracks this.

**`.gc/settings.json` is gitignored by default.** To track it (we do, for the hooks), the city's `.gitignore` uses an allowlist:
```
.gc/*
!.gc/settings.json
```
Same shape as the existing `.beads/*` + `!.beads/config.yaml` allowlist.

**`gc mail peek <id>` not `gc mail read <id>`** when a human inspects an agent's mail. `read` marks the message as read and removes it from the recipient's `gc mail check` (unread-only) result. Recovery: `gc mail mark-unread <id>`.

**`gc mail inbox` syntax is positional, not `--to`.** `gc mail inbox mayor` works; `gc mail inbox --to mayor` errors.

**Polecats are invisible in `gc status` and `gc session list` until they actively run.** A newly-registered polecat is configured correctly even if invisible. Only crew (named sessions) and scaled pools show up at rest.

## Workflow rules (memorized)

- User: all `gc` commands, all config file edits (`pack.toml`, `agent.toml`, `prompt.template.md`, `formula.toml`, `order.toml`).
- Me: git operations, notes files, memory, read-only Bash inspection. One-off "you do it" authorizations do not become standing permission.
- Voice rules apply to tutorial markdown, blog content, conversational replies, notes files: no em dashes, no LLM-tell phrases (delve, leverage, robust, seamless, "imagine if", "in summary", "furthermore").

## Investigation discipline

If something looks broken, investigate before patching. Did we do something wrong? Are we misled by a false-positive warning? Check `--help`, the source at `/Users/jonaseriksson/code/gascity/`, then GH issues. Reserve "bug + workaround" framing for things tied to a real GH issue. For listing GH issues use `gh api repos/gastownhall/gascity/issues?...` (the repo's GraphQL has a deprecated-projects-classic issue that breaks `gh issue view`).

## Memory files to read

In `/Users/jonaseriksson/.claude/projects/-Users-jonaseriksson-Code-gas-city-tutorial/memory/`:

- `MEMORY.md` (index)
- `feedback_writing_style.md` (voice rules)
- `user_gc_knowledge.md` (user is new to GC; ground claims in research)
- `project_tutorial_design.md` (the locked design with chapter outline, agent roster, audience)
- `feedback_test_run_workflow.md` (user/agent split)
- `feedback_git_amend.md` (prefer amend for fix-ups of just-made commits)
- `project_bd_issue_prefix_bug.md` (the GH#1232 workaround)
- `feedback_investigate_before_patching.md` (investigate first, do not assume bug)
- `project_routed_to_auto_dispatch.md` (sling stamps `gc.routed_to`; reconciler auto-dispatches)
- `feedback_fix_in_chapter.md` (when the test run surfaces a problem, fix lands in the same chapter tag)
- `feedback_no_internal_ids.md` (do not reference internal task IDs to the user)

The fresh agent should read these on startup if not already in context.
