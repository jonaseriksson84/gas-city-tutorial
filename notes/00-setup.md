# Notes: Part 0, Setup

Raw notes from the test run of Part 0. Source material for `tutorials/00-setup.md` later.

## Environment captured at start

| Tool | Version |
|---|---|
| Bun | 1.3.6 |
| Gas City `gc` | 1.0.0 |
| Beads `bd` | 1.0.3 |
| Claude Code | 2.1.121 |
| Codex | 0.125.0 |
| tmux | 3.6a |

`ANTHROPIC_API_KEY` not set in shell. Claude Code is presumed authenticated via its own login flow.

## Commands run

### Step 1: Initialize the city

```
gc init --provider claude --name rss-tutorial city
```

Output (8-step sequence):

```
[1/8] Creating runtime scaffold
[2/8] Installing hooks (Claude Code)
[3/8] Writing default prompts
[4/8] Writing pack.toml
[5/8] Writing city configuration
Welcome to Gas City!
Initialized city "rss-tutorial" with default provider "claude".
[6/8] Checking provider readiness
[7/8] Registering city with supervisor
Registered city 'rss-tutorial' (/Users/jonaseriksson/code/gas-city-tutorial/city)
Installed launchd service: /Users/jonaseriksson/Library/LaunchAgents/com.gascity.supervisor.plist
[8/8] Waiting for supervisor to start city
```

Step 8 returns silently (prompt comes back) once the supervisor finishes starting the city.

## Observations and surprises

- `gc init --provider claude` is fully non-interactive. Useful for tutorial scripts.
- A launchd service `com.gascity.supervisor.plist` gets installed on first init. This is a per-user daemon that manages all cities. Fine, but worth calling out in the tutorial so readers are not surprised.
- The default minimal city already includes a `dog` agent pool (scaled 0 to 3, all stopped) defined by the `maintenance` system pack at `.gc/system/packs/maintenance/`. Dog is a city-scoped utility worker for housekeeping formulas (shutdown dance, jsonl backup). Tutorial readers will see it in `gc status`; explain briefly so they do not think they broke something.
- The default mayor's prompt is a generalist (plan + dispatch + manage). Our design calls for a strict-delegator mayor. Override happens in Part 1.
- A `mayor` named session is created with `mode = "always"` but starts in `reserved-unmaterialized` state. It does not actually spawn until a session is needed (via `gc session attach mayor` or similar).

## Failure modes encountered

### Rigs must be git repos for bd auto-export to work cleanly

`gc rig add` does not initialize a git repo inside the rig directory. `gc doctor` flags this as a warning (`rig:<name>:git — not a git repository`), and it surfaces later as a `auto-export: git add failed` warning from bd every time an agent runs `bd create` against the rig (bd writes `.beads/issues.jsonl` after each write and tries to `git add` it).

Fix is one line, run inside the rig dir right after `gc rig add`:

```bash
git init
```

For the chapter: this belongs in Part 0 setup, between `gc rig add` and the verification `gc status`. Otherwise readers will start tripping on the warning the moment work hits the rig in Part 2.

### Skills symlinks are absolute paths

`gc init` populates `city/.claude/skills/` with seven symlinks (`core.gc-agents`, `core.gc-city`, `core.gc-dashboard`, `core.gc-dispatch`, `core.gc-mail`, `core.gc-rigs`, `core.gc-work`). The auto-generated `city/.gitignore` does not exclude them, so they get tracked when you `git add`. The targets are absolute paths inside `city/.gc/system/packs/core/skills/`, which is gitignored. On any clone:

- The targets never exist (`.gc/` is not committed).
- If the clone path differs from the original, the absolute paths point nowhere on the new machine either way.

Fix for a tutorial reference repo: add `city/.claude/skills/` to the parent repo's `.gitignore`. A fresh `gc init` regenerates them locally.

Worth flagging upstream eventually: the GC team's auto-generated city `.gitignore` probably should exclude `.claude/skills/` itself, or `gc init` should write relative-target symlinks.
