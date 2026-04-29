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
| 2 Building the bones | not yet tagged | **Test run done, awaiting commit + tag.** Backend polecat materialized (`rss-reader/backend-1`), built scaffold (Bun + Hono + bun:sqlite + `/health`), committed in rig (`6f9d267`), closed `rr-lhv`. |
| 3 Specialists at work | not yet started | Next chapter introduces `frontend` and `dba` agents and the first "real" feature work. |
| 4-6 | not yet started | |

## Immediate next step

Test run for Part 2 finished cleanly. Two open items before moving to Part 3:

1. **Commit + tag the parent repo for chapter-2.** My responsibility. Files changed in parent: `city/pack.toml` (backend `[[agent]]` block), `city/agents/backend/` (scaffolded by `gc agent add`), `notes/02-building-bones.md` (filled in), `notes/HANDOVER.md` (this update). Tag `chapter-2`. Confirm with the user before tagging.
2. **Decide on Part 3 scoping.** The locked design says Part 3 introduces frontend + dba agents and the first feature beyond `/health`. Likely first feature: read RSS feeds from a hardcoded list, store items in sqlite, render the front page (HTMX-backed) listing them. Need to decide which agent does what work order before we start so the chapter has a clean shape.

## What just happened (Part 2 outcome)

- User ran `gc reload` then `gc config show | grep -A 4 'name = "backend"'`. Resolved config showed `dir = "rss-reader"` on the backend block. Reload was a no-op because an earlier reload had already picked it up; harmless.
- User ran `gc mail send mayor ...` + `gc session submit mayor "Check your inbox."`. Mayor woke, processed the mail, called `gc sling rss-reader/backend rr-lhv`.
- Backend polecat session `rss-reader/backend-1` materialized and ran the scaffold turn: wrote `package.json`, `tsconfig.json`, `src/index.ts` (Hono + bun:sqlite, GET /health). Ran `bun install`, sanity-tested the server, killed it (exit 143 SIGTERM, expected), `bunx tsc --noEmit` clean, staged specific files, committed with bead ID in subject, closed `rr-lhv` with a real reason.
- On disk in `rss-reader/`: scaffold present (`package.json`, `tsconfig.json`, `src/index.ts`, `.gitignore`, `bun.lock`, empty `rss-reader.db`). Two commits in rig history: `e3c70c6` (initial bd config + gitignore) and `6f9d267` (scaffold).

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

**Bug GH#1232: `bd create` fails on every write path** with `database not initialized: issue_prefix config is missing`. Already worked around for the city `hq` DB and the rig `rr` DB. If we hit it again on a new database (e.g. when adding a new rig), apply the same direct dolt SQL fix:

```bash
cd <city>/.beads/dolt
dolt --use-db <db-name> sql -q "
  INSERT INTO config (\`key\`, value) VALUES ('issue_prefix', '<prefix>')
    ON DUPLICATE KEY UPDATE value='<prefix>';
  CALL dolt_commit('-Am', 'set issue_prefix');
"
```

**Bug GH#1139: idle Claude Code sessions do not auto-poll** for new mail or routed work. Hooks fire on `SessionStart`, `UserPromptSubmit`, `Stop`, `PreCompact`, none of which trigger on a fully-idle session. The canonical pattern for "send mail, have it picked up at earliest convenience" is:

```bash
gc mail send <agent> -s "<subject>" -m "<body>"
gc session submit <agent> "Check your inbox."
```

Do **not** use `gc mail send --notify` (writes to stdin, sits in buffer when idle, never processed). Do **not** use `gc session submit ... --intent interrupt_now` (interrupts mid-turn work; bad pattern for everyday flow). Default intent on submit is correct: it wakes idle sessions and queues for in-turn sessions.

**Doctor's `v2-agent-format` warning is a known false positive** ([GH#1175](https://github.com/gastownhall/gascity/issues/1175), [GH#1244](https://github.com/gastownhall/gascity/issues/1244)). Schema=2 pack.toml `[[agent]]` blocks ARE the intended layout. Ignore the warning, do not try to "fix" it.

**`beads.role not configured` warning** clears with `git config beads.role maintainer` from inside the parent git repo. Already done in this test run.

**`gc agent add --dir <rig>` does NOT update pack.toml.** It scaffolds `agents/<name>/{agent.toml,prompt.template.md}` only. The human must add the `[[agent]]` block with `dir = "rss-reader"` to `pack.toml` manually. The dir field in `agent.toml` does NOT propagate into the resolved config in our setup. Per chapter design, the chapter teaches both steps; do not bypass `gc agent add`.

**`gc reload` is a no-op for prompt template changes.** Only re-reads TOML configs. Prompt files re-read on session materialization. Do not tell the user to reload after editing a prompt.

**`gc reload` may say "controller is busy"** during a reconcile tick. Retry in a few seconds.

**`gc mail reply` requires `-s` subject** (does not auto-Re from parent). The mayor learned this the hard way; the strict-delegator prompt now lists the exact reply syntax.

**`gc mail check` exits 1 when there is no mail** (intentional, useful for shell scripts; not an error).

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
