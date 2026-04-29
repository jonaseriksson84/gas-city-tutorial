# Notes: Part 2, Building the bones

Raw notes from the test run of Part 2. Source material for `tutorials/02-building-bones.md` later.

## Tutorial-cleanup observations

### Adding a rig-scoped agent: `gc agent add` is necessary but not sufficient

`gc agent add --name backend --dir rss-reader` scaffolds `agents/backend/` with `agent.toml` (containing `dir = "rss-reader"`) and a placeholder `prompt.template.md`. The help text is explicit that the command "does not append `[[agent]]` blocks to `city.toml`." It also does not append to `pack.toml`. The agent is on disk but not registered.

To make the agent visible to the controller, the human must add an `[[agent]]` block to `pack.toml` manually:

```toml
[[agent]]
name = "backend"
dir = "rss-reader"
prompt_template = "agents/backend/prompt.template.md"
```

Notes about this:

- **`dir` belongs in the `[[agent]]` block in `pack.toml`**, not (only) in `agents/backend/agent.toml`. The `dir` field in `agent.toml` does not propagate into the resolved config in our setup. `pack.toml`'s `[[agent]]` is the source of truth for rig binding.
- **`[[agent]]` blocks in schema=2 `pack.toml` are the intended layout**, not legacy. `gc init` writes them deliberately, and the official tutorial documents them as the post-init shape. The doctor's `v2-agent-format` warning is a known false positive ([GH#1175](https://github.com/gastownhall/gascity/issues/1175) fixes it; [GH#1244](https://github.com/gastownhall/gascity/issues/1244) tracks the same false positive on `gc init`).
- **Without the `dir` field in `pack.toml`, `gc sling rss-reader/backend rr-lhv` fails** with "agent 'rss-reader/backend' not found in city.toml; did you mean 'rss-reader/claude'?" The hint suggests `rss-reader/claude`, which is the generic per-rig pool worker auto-provided by the core system pack.

For the chapter: use `gc agent add` (it correctly scaffolds the directory, `agent.toml`, and the prompt template placeholder; that work is real) and immediately follow up with a manual `[[agent]]` block edit in `pack.toml`. Two steps, both required, both belong in the chapter. Bypassing the tool throws away valuable scaffolding for no reason.

The two-step flow is consistent with what the help text and GH issue history imply: `gc agent add` is for filesystem scaffolding only; `pack.toml` is the human's source-of-truth declaration. The tool has not been flagged as a UX gap that should be auto-appending to `pack.toml`. If GC ever decides to make `gc agent add` write the registration block, the chapter shrinks to one step; until then, two.

### Polecats are invisible in `gc status` until they run

After registering `backend` in `pack.toml`, `gc status` shows only `dog` (the maintenance pool with declared min/max sizing) and `mayor` (the named session). `backend` is a polecat: configured but not running. It only appears in `gc session list` once work routes to it and a session materializes. Worth a one-line callout so readers do not panic when their newly-added agent does not show up in status.

### `gc reload` is usually a no-op (and that is correct behavior)

Both reloads in this run reported "No config changes detected" even though we had just edited `pack.toml`. That message is *not* a failure. It means: the new config is already in memory.

Why: the controller runs a recursive file watcher (fsnotify) over the city directory. Edits to `pack.toml`, `agent.toml`, prompt templates, etc. fire events within milliseconds. The reconciler tick that follows shortly after picks up the change and applies it. By the time the human types `gc reload`, the in-memory config already matches disk, so reload sees nothing to do.

Sources:
- [GH#926](https://github.com/gastownhall/gascity/issues/926) (closed): the watcher walks subdirs recursively so v2 convention edits trigger hot reload.
- [GH#1127](https://github.com/gastownhall/gascity/issues/1127) (open): tracks rebasing session config hashes after reload, also notes the "controller is busy" catch-22 fix and confirms `gc reload` is a *stabilization* tool, not a "restart on edit" trigger.

When `gc reload` actually matters:
- The watcher missed an edit (race conditions during bulk file moves, mostly)
- The agent is running in a sandboxed environment without fsnotify (CI, etc.)
- You changed something the watcher does not see: environment variables, remote pack contents, or a config file in a path not covered by the watch list

For the chapter: the reader does not need to run `gc reload` after editing `pack.toml`. They can. It will say "No config changes detected." That is fine. Frame it as "reload is the manual escape hatch; under normal conditions, the watcher has already done the work."

### `gc reload` may say "controller is busy" (intermittent)

Observed in an earlier attempt during Part 2 setup: `gc reload` once returned "Reload request could not be accepted because the controller is busy." A retry seconds later succeeded. This is a known race between reload requests and reconciler ticks, fixed by [GH#1127](https://github.com/gastownhall/gascity/issues/1127) (which buffers the reload channel). On a current build, less common; if it happens, give it a few seconds and try again.

### Polecat session naming: `<rig>/<agent>-<n>`

When the backend polecat materialized, its session showed up as `rss-reader/backend-1`. The `-1` suffix is the instance number for that rig+agent pair. Useful to mention in the chapter so readers know how to address the session in `gc session peek`, mail, etc.

### Backend agent commits inside the rig (not the parent)

The backend polecat ran `git add` and `git commit` inside `rss-reader/`, the rig's own git history. This is correct and intentional:

- The rig is its own repo (we ran `git init` inside it in chapter 0). The parent gitignores `rss-reader/`.
- Beads' auto-export uses `git add` inside the rig, so the rig must be a git repo.
- The agent prompt instructs it to commit completed work in the rig with the bead ID in the subject (`rr-lhv: scaffold rss-reader (Bun + Hono + bun:sqlite)`).
- The user-vs-agent split for git is *parent*-repo only. Inside a rig, the agent owns commits.

For the chapter: spell this out so readers do not get confused about who commits where. The rig is a fully separate git history that agents drive; the parent is the human's tutorial repo.

### What the scaffold turn looked like

The backend's first turn (slung `rr-lhv`):

1. Read the bead, asked one clarifying question via mail (or proceeded directly; depends on the run).
2. Wrote `package.json` (hono dep), `tsconfig.json` (strict + `noUncheckedIndexedAccess`), `src/index.ts` (Hono + bun:sqlite, `GET /health`).
3. Ran `bun install` to populate `bun.lock` and `node_modules/`.
4. Started the server in the background, hit `/health`, killed the server (exit 143 = SIGTERM, expected and noted).
5. Ran `bunx tsc --noEmit` to typecheck.
6. Staged specific files (not `git add .`), committed with bead ID in subject and HEREDOC body.
7. `bd close rr-lhv --reason="..."` with a real summary of what landed.

Worth a callout: this is what a well-configured polecat looks like end-to-end. The prompt template is doing real work here. Specifically:
- "commit when you finish" gives us the chapter-pacing artifact (one bead -> one commit).
- "include the bead ID in the subject" means `git log` reads as a project history of beads.
- "stage specific files" avoids accidentally committing junk.
- The HEREDOC pattern is from the agent's Claude Code defaults; we did not have to specify it.

### Bun specifics worth one line

- `bun.lock` lives at the rig root and is committed. We initially gitignored `bun.lock*` and the agent corrected that (kept it committed). The `*` glob was for `bun.lockb`-style binary artifacts that are no longer used.
- `bun:sqlite` is built in; no `better-sqlite3` install dance.
- Hono on Bun uses the `export default { port, fetch }` shape, not `serve()`. Worth showing.
- The agent set `port: Number(process.env.PORT ?? 3000)` so we can swap ports for tests later.

## Commands run

```bash
gc agent add --name backend --dir rss-reader
# Edit city/pack.toml to add the [[agent]] block with dir = "rss-reader"
gc reload
gc config show | grep -A 4 'name = "backend"'
gc mail send mayor -s "..." -m "..."
gc session submit mayor "Check your inbox."
gc session peek mayor
gc session peek rss-reader/backend-1
bd show rr-lhv     # confirm closed
```

## Observations and surprises

- The hand-off is striking: from the human's perspective, you write a couple of files and send one mail. The mayor reads the mail, calls `gc sling`, the polecat materializes inside its rig, and you get a working scaffold + commit + closed bead a couple of minutes later. The chapter should let the reader feel that compression.
- The mayor's strict-delegator prompt held up: it did not try to write code itself even though it would have been straightforward to do. This is the prompt-template payoff.

## Failure modes encountered

The `gc agent add` half-step (above) was the first friction point of Part 2. Mayor's first sling failed with "agent 'rss-reader/backend' not found"; we fixed it by adding `dir = "rss-reader"` to the `[[agent]]` block in `pack.toml` and reloading.
