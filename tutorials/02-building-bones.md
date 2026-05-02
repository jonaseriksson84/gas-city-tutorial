# Part 2: Building the bones

In Part 1 you woke a mayor with no specialists. In this chapter we register a **backend** specialist, hand the mayor a feature, watch it route the work, and end up with a working app skeleton committed to the rig.

By the end:

- `pack.toml` has a backend agent registered, bound to the `rss-reader` rig.
- The mayor's prompt covers single-specialist routing via `gc sling`.
- The backend polecat has materialized, scaffolded the rig, committed, and closed its bead.

Three concepts surface here: **sling** (the routing primitive), **beads** (the unit of work), and **hooks** (how Claude Code sessions get nudged automatically).

## Crew vs polecat

Crew agents run continuously. The mayor is crew because `pack.toml` declares it as a `[[named_session]]` with `mode = "always"`.

Polecats run on demand. They have no `[[named_session]]` block. They spawn when work is routed to them, do that work, commit, close the bead, and exit. Polecats stay invisible in `gc status` until they are actively running.

For this tutorial, the mayor is the only crew agent. Backend, DBA, frontend, and reviewer (the four specialists you register over the next chapters) are all polecats.

## Step 1: Scaffold the backend agent

```bash
gc agent add --name backend --dir rss-reader
```

This creates `agents/backend/` with:

- `agent.toml`, a small stub (containing `dir = "rss-reader"` because of the flag)
- `prompt.template.md`, a placeholder you will replace

The `--dir` flag writes the dir into `agent.toml`. **It does not register the agent.** Per `gc agent add --help`: "These files live in the city directory and do not append `[[agent]]` blocks to `city.toml`." Registration is a separate manual step. The tool stays out of `pack.toml` on purpose so you can review the registration block before it goes live.

You will see this two-step shape every time you add an agent: `gc agent add` for the scaffolding, then a manual `[[agent]]` block in `pack.toml` for the registration.

## Step 2: Register the agent in `pack.toml`

Open `city/pack.toml`. After the existing `[[agent]]` block for `mayor`, add:

```toml
[[agent]]
name = "backend"
dir = "rss-reader"
prompt_template = "agents/backend/prompt.template.md"
```

The `dir = "rss-reader"` makes this a rig-scoped specialist. When you sling work to `rss-reader/backend`, the spawned session's working directory will be `rss-reader/`, and `bd` calls will operate on the rig's bead store.

Yes, `dir` is now in both `agent.toml` (written by `--dir`) and `pack.toml` (added here). The `pack.toml` one is the source of truth; `agent.toml`'s `dir` does not propagate into the resolved config in this build. Without the `dir` line in `pack.toml`, `gc sling rss-reader/backend <bead>` errors with `agent 'rss-reader/backend' not found in city.toml`.

`gc doctor` may also warn about `v2-agent-format`. That is [GH#1175](https://github.com/gastownhall/gascity/issues/1175), a known false positive. Schema=2 `pack.toml` with `[[agent]]` blocks is the intended layout. Ignore it.

## Step 3: Write the backend prompt

Open `agents/backend/prompt.template.md` and replace it with:

```markdown
# Backend (rss-reader specialist)

You are the backend agent for the `rss-reader` rig. You work on server-side code: Hono routes, database access via `bun:sqlite`, RSS fetching and parsing, scheduled refresh logic, anything that runs on the server.

## Hard rules

- **You only write code inside the `rss-reader/` rig directory.** No edits outside the rig.
- **You only write backend-shaped code.** Server routes, db queries, fetch/parse logic, types and helpers that live behind the API. You do not write HTML templates, CSS, HTMX attributes, or anything frontend-shaped. If a task needs frontend work, close your bead with a comment and let the mayor route it to a frontend agent.
- **You do not modify `pack.toml`, agent configs, or anything inside `city/`.** That is the mayor's and human's domain.
- **You keep changes scoped to the bead.** If you discover unrelated cleanup that would help, mention it in your closing comment. Do not silently expand scope.

## Your loop

1. Find your assigned work with `bd ready` (or `bd show <id>` if you already know it).
2. Read the bead description and acceptance criteria carefully.
3. Do the work in `rss-reader/`. Run `bun install` if dependencies changed, run any tests, and verify by hand that acceptance criteria are met.
4. Commit changes inside the rig with a message that references the bead id.
5. Close the bead: `bd close <id>` with a concise summary of what changed and how to verify.
6. Mail the mayor a brief status update if anything notable happened.
7. Exit. The controller recycles your slot.

## Stack and conventions

- Runtime: Bun. Use `bun install`, `bun run`, `bun test`. No npm.
- Framework: Hono. Routes live in `rss-reader/src/`.
- Database: `bun:sqlite` (Bun built-in). Schema is owned by the `dba` agent (added later); for now just create the file.
- Language: TypeScript with strict settings.
- No build step. Bun runs `.ts` files directly.

## Commands you actually use

- bd: `bd ready`, `bd show <id>`, `bd close <id>`, `bd label add <id> <label>`
- Mail: `gc mail send mayor -s "<subject>" -m "<body>"` for status updates
- Shell: `bun install`, `bun run dev`, `bun test`, `git`

## When in doubt

Run `gc <cmd> --help` rather than guessing flags. If a task is genuinely ambiguous, mail the mayor, label the bead `blocked:awaiting-clarification`, and pause.

## Environment

Your agent name is `$GC_AGENT`. Your assigned bead id appears in the work query output.
```

## Step 4: Update the mayor's prompt for single-specialist routing

The mayor needs to know how to sling work. Open `agents/mayor/prompt.template.md` and replace it with:

```markdown
# Mayor (strict delegator)

You are the mayor of this Gas City workspace. You receive work requests, decide which specialist agent should handle them, and route the work. You do not do the work yourself.

## Hard rules

- **You do not write or edit code.** Not even small fixes. If a task needs code, you delegate.
- **You do not run shell commands that change project state.** No `git`, no `bun`, no editing files. The only commands you run are GC commands for routing, status, and mail.
- **If no specialist exists for a task,** say so plainly. Tell the human what kind of specialist would be needed and what its responsibilities should be. Do not improvise by doing the work yourself.

## Your loop

1. Check unread mail: `gc mail check`. Read each with `gc mail read <id>`.
2. For each request, decide which specialist should handle it.
3. Dispatch (see below).
4. Reply to the human via `gc mail reply <id>` summarizing what you decomposed the request into, which beads you created, and who got each one.
5. Monitor with `bd list` and `gc session peek <name>`.

## Available specialists

- `rss-reader/backend`: server-side TypeScript inside the rig. Hono routes, ingest, parsing, anything that runs on the server.

## Dispatch (single specialist)

If a request maps cleanly to one lane, sling with inline text and the built-in `mol-do-work` lifecycle:

    gc sling rss-reader/backend "<concise bead title and description>" --on mol-do-work

`--on mol-do-work` attaches the built-in `mol-do-work` formula as a wisp on the bead. The polecat will follow that lifecycle (read assignment, do work, commit, close, drain) instead of behaving ad-hoc. Use this for every polecat sling unless you have a specific reason not to.

When you create a bead, make the description concrete enough that the specialist can act without asking for clarification. Include: what the bead must produce, where files should live (relative to the rig), and what acceptance looks like.

## Commands you actually use

- Mail: `gc mail check`, `gc mail inbox`, `gc mail read <id>`, `gc mail reply <id> -s "..." -m "..."`, `gc mail send <agent> -s "..." -m "..." --notify`
- Beads: `bd create -t "<title>" -d "<description>" --json`, `bd list`, `bd show <id>`
- Dispatch: `gc sling rss-reader/<agent> "<inline description>" --on mol-do-work`, or `gc sling rss-reader/<agent> <bead-id> --on mol-do-work`
- Sessions: `gc session list`, `gc session peek <name>`
- Status: `gc status`

If unsure of exact flags, run `gc <cmd> --help`.

## Environment

Your agent name is `$GC_AGENT`.
```

## Step 5: Restart the mayor with the new prompt loaded

The mayor's session is still running from Part 1, with the Part 1 prompt loaded. The prompt file is read fresh at session start, so saving a new file does not change a running session. Restart it:

```bash
gc session kill mayor
```

The reconciler respawns the named session within seconds with the new prompt loaded. This is the standard tool for prompt-template changes on always-on named sessions. We will do this every time we change the mayor's prompt in later chapters.

A note on `gc handoff --target mayor`: it is the right tool for delivering a new feature request to the mayor when the prompt is unchanged. For prompt changes on `mode = "always"` sessions, handoff sends mail without killing, so the new prompt does not load. Use `gc session kill` for prompt changes; `gc handoff --target` for feature delivery.

## Step 6: Verify the registration

```bash
gc config show | grep -A 4 'name = "backend"'
```

You should see your `[[agent]]` block printed back, including `dir = "rss-reader"` and `prompt_template = "agents/backend/prompt.template.md"`.

<details>
<summary><strong>Sidebar:</strong> what <code>gc reload</code> does (and why you do not need it)</summary>

`gc reload` forces the controller to reread `pack.toml` and friends. You can run it now and it will report:

```
No config changes detected.
```

That is not a failure. The controller runs an fsnotify watcher ([GH#926](https://github.com/gastownhall/gascity/issues/926), closed) that picks up edits to `pack.toml` and prompt templates within milliseconds. By the time you run `gc reload`, the in-memory config already matches disk.

When `gc reload` actually matters: the watcher missed an edit, you are running in a sandbox without fsnotify, or you changed something the watcher does not see (env vars, remote pack contents). For the rest of this tutorial, treat it as a manual escape hatch. You should not need it.

`gc reload` does **not** restart running named sessions. It rebuilds the in-memory config; sessions keep their current prompt loaded. That is what `gc session kill` is for.

</details>

## Step 7: Hand the mayor the first feature

```bash
gc handoff --target mayor "Feature: scaffold the rss-reader rig" "Please get the rss-reader rig set up. Initialize a Bun + Hono + bun:sqlite project at the rig root: package.json, tsconfig.json (strict + noUncheckedIndexedAccess), src/index.ts with a tiny Hono app exposing GET /health -> 'ok'. Open the bun:sqlite db at rss-reader/rss-reader.db (file does not need to exist yet; bun:sqlite will create it). bun install. Verify by booting the server briefly and curling /health. Commit inside the rig with the bead id in the subject. Close the bead."
```

`gc handoff --target mayor` delivers the message and wakes the session if it has gone idle. For an always-on session it is equivalent to `gc mail send mayor --notify -s "..." -m "..."`. We use `gc handoff` throughout the rest of the tutorial as the idiomatic command for "deliver new feature context to a session."

Watch the mayor work:

```bash
gc session peek mayor
```

You should see it run `gc mail check`, read the message, decide that this is a backend task, then sling something like:

```
gc sling rss-reader/backend "Scaffold rss-reader: package.json, tsconfig.json, src/index.ts with Hono GET /health, bun install, verify and commit" --on mol-do-work
```

`gc sling` does three things at once:

1. Creates a new bead in the rig store (you will see something like `rr-lhv` in the output).
2. Stamps `gc.routed_to = "rss-reader/backend"` on the bead as metadata.
3. With `--on mol-do-work`, attaches the formula so the spawned polecat follows a structured lifecycle.

The reconciler notices a routed bead with no live session for that template and spawns one. You will see `rss-reader/backend-1` appear in `gc session list` shortly after. The `-1` is the instance number for that rig+agent pair.

## Step 8: Watch the polecat work

```bash
gc session peek rss-reader/backend-1
```

In another terminal, set up the overview helper that the rest of the tutorial uses:

```bash
mkdir -p ../bin
cat > ../bin/overview.sh <<'EOF'
#!/usr/bin/env bash
set -u
CITY=$(pwd)
RIG=$(realpath ../rss-reader)

hr() { printf '%s\n' "------------------------------------------------------------"; }

hr; echo "SESSIONS"; hr
gc --city "$CITY" session list 2>&1 | grep -v '^warning:' || true
echo
hr; echo "RIG BEADS - OPEN"; hr
(cd "$RIG" && bd list --status=open 2>&1 | grep -v '^warning:') || true
echo
hr; echo "RIG COMMITS (last 5)"; hr
git -C "$RIG" --no-pager log --oneline -5 2>&1 || true
echo
hr; echo "MAYOR INBOX"; hr
gc --city "$CITY" mail inbox mayor 2>&1 | grep -v '^warning:' | head -8 || true
EOF
chmod +x ../bin/overview.sh
```

```bash
watch -n 3 bash ../bin/overview.sh
```

You will see the bead appear in "RIG BEADS - OPEN" the moment the mayor slings it, then the polecat session show up in "SESSIONS" within seconds. A few minutes later, the bead disappears from open (closed by the polecat), a new commit shows up under "RIG COMMITS," and the session goes away as the polecat exits.

The dashboard at `gc dashboard serve` would normally show all of this in a tidier UI. On my v1.0.0 run the dashboard was entirely unresponsive ([GH#1168](https://github.com/gastownhall/gascity/issues/1168), fix on main but not in any released tag yet). YMMV: try `gc dashboard serve` first; if the panels populate cleanly, use it. If not, the overview script is the fallback used throughout the rest of the tutorial.

## Step 9: Read the result

```bash
cd ../rss-reader
bd show rr-lhv
git --no-pager log --oneline
```

You should see one commit with a message like `rr-lhv: scaffold rss-reader (Bun + Hono + bun:sqlite)`. The rig now has `package.json`, `tsconfig.json`, `src/index.ts` with a tiny Hono app exposing `GET /health`, plus `bun.lock` (committed) and `node_modules/` (locally present, not committed).

Boot it briefly:

```bash
bun run src/index.ts &
sleep 1
curl -s http://localhost:3000/health
echo
kill %1
```

You should see `ok`.

## What you saw extra in `bd list`

Slinging with `--on mol-do-work` creates extra bookkeeping beads alongside the work bead:

- A "sling" wrapper bead (e.g. `sling-rr-lhv`).
- A `mol-do-work` parent bead with two child step beads.
- The actual work bead (`rr-lhv`).

This is the formula's expansion at runtime. The vocabulary (convoys, molecules, wisps) lands properly in Part 3, where formulas are introduced as a primary concept. For now, treat the wrappers and the parent as runtime scaffolding. The bead you care about is the one whose title matches your sling description.

## Shape check

- `pack.toml` has `[[agent]] name = "backend" dir = "rss-reader"`.
- The mayor's prompt has a Dispatch section that mentions `gc sling`.
- One commit in the rig with the bead id in the subject.
- `bd show rr-lhv` shows status `closed` (your bead id will differ).
- `curl http://localhost:3000/health` returns `ok`.

## When your agent goes off-script

- **First sling fails with `database not initialized: issue_prefix config is missing`.** Same v1.0.0 [GH#1232](https://github.com/gastownhall/gascity/issues/1232) bug from Part 1, but this time the rig's bd database (`rr`) is the one missing its config row. Fix from the city directory:

   ```bash
   cd .beads/dolt
   dolt --use-db rr sql -q "
     INSERT INTO config (\`key\`, value) VALUES ('issue_prefix', 'rr')
       ON DUPLICATE KEY UPDATE value='rr';
     CALL dolt_commit('-Am', 'set issue_prefix');"
   cd ../..
   ```

   Ask the mayor to retry the sling (`gc session submit mayor "Retry the previous sling"`).

- **`gc sling rss-reader/backend ...` errors with "agent not found".** Missing `dir = "rss-reader"` in `pack.toml`.
- **Backend polecat asks a clarifying question via mail and pauses.** This is the prompt working: when the bead description is ambiguous, the prompt instructs the agent to label and stop rather than guess. Reply to the mayor with a clarification and let it relay.

<details>
<summary><strong>Sidebar:</strong> hooks (how Claude Code finds work without polling)</summary>

`gc init` installed a `.gc/settings.json` in the city that wires Claude Code lifecycle events to GC commands. The four hooks you have are:

| Event | Hook |
|---|---|
| `SessionStart` | `gc prime --hook` (loads the prompt) |
| `UserPromptSubmit` | `gc nudge drain --inject` and `gc mail check --inject` |
| `Stop` | `gc hook --inject` |
| `PreCompact` | `gc handoff "context cycle"` (preserves state when context fills) |

The two `UserPromptSubmit` hooks are the heart of "how the agent finds work without polling." On every turn boundary, Claude Code asks GC two questions: "is anything queued for me?" (the nudge drain) and "is there mail?" (the check). The answers flow into the agent's context as system messages, and the agent acts on them.

This is why a session that never has a turn cannot pick up mail (nothing fires the hooks) and why the standard pattern is mail with `--notify`, which forces a wake.

</details>

In Part 3 we register two more specialists and let the mayor decompose a real feature into a small dependency chain.
