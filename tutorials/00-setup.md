# Part 0: Setup

This is a seven-part tutorial about building a working web app while learning Gas City. Each part adds something new on top of the last. By the end you have an RSS reader of your own and a mental model for how Gas City fits into a project.

If you have used coding agents in your editor (Claude Code, Cursor, Codex), you already have most of the muscle this tutorial asks for. Gas City sits one level above that: instead of one agent helping you in your editor, you orchestrate several agents from the command line, each with its own role, and watch them deliver a feature together.

## What we are building

A minimalist Hacker-News-style RSS aggregator. It fetches the HN front-page feed, stores items in SQLite, renders them in a simple page, and ships small features along the way (per-source labels, search, a daily LLM-generated digest). The app is written by agents under your direction. The configs you write to direct them are the artifacts you keep.

By the end:

- A small Hono app on Bun, with `bun:sqlite`, `hono/html`, and HTMX.
- Five agents in your city: a mayor (always-on coordinator), a backend specialist, a DBA specialist, a frontend specialist, and a code reviewer.
- Three scheduled jobs: a periodic feed fetch, a nightly database prune, and a daily AI-written digest.

The stack is deliberately self-contained: no build step, no bundler, no JSX transpilation, no Tailwind toolchain. Bun runs `.ts` files directly, `bun:sqlite` is built in, `hono/html` is server-rendered, HTMX adds interactivity without leaving the server. Less to configure means less for the agents to get wrong.

## What you need installed

| Tool | Version used |
|---|---|
| Bun | 1.3.6 |
| Gas City `gc` | 1.0.0 |
| Beads `bd` | 1.0.3 |
| Claude Code | 2.1.121 |
| Codex (optional, used in Part 4) | 0.125.0 |
| tmux | 3.6a |

Install Gas City via Homebrew (pulls in `gc`, `bd`, `dolt`, `tmux`, `jq`, `flock`):

```bash
brew install gastownhall/gascity/gascity
```

Bun separately:

```bash
curl -fsSL https://bun.sh/install | bash
```

A Claude Code subscription covers the full run; the whole tutorial ran on my Anthropic subscription end to end without a separate API key. If you want to use API credit instead, $2 to $5 of Anthropic credit covers the run, plus maybe a dollar for Codex if you do the Part 4 provider swap. Codex on the reviewer ran on its free tier from my ChatGPT login. The simplest readiness check: type `claude` and `codex` at the shell, confirm both start. If they do, Gas City will use them.

## A note before we start: agents do not produce identical output

Every command output, file path, and config in this tutorial is what happened on my run. Your run will differ in details. Each chapter ends with a **shape check** that lists what should be true, not byte-identical: "the app renders an HN-style list at `/`," "this bead is closed." If your shape matches, you are on track.

When something goes off-script, each chapter has a "When your agent goes off-script" section with the failure modes I observed. The companion repo has a `chapter-N` tag for every chapter; if you ever want to skip ahead from a known-good state, `git checkout chapter-N` recovers it.

## Workspace layout

```
gas-city-tutorial/        parent repo
├── city/                 your Gas City workspace (configs, prompts)
├── rss-reader/           the rig (its own git repo, the app code)
├── notes/                your own notes if you keep any
└── tutorials/            these chapters
```

The parent is a git repo. `rss-reader/` is its own git repo (you `git init` it in Step 4) and is gitignored from the parent. They have independent histories on purpose: the rig is what the agents write to, the parent is what you write to.

<details>
<summary><strong>Sidebar:</strong> the rig does not have to live under the parent, and how to ship to GitHub</summary>

Nothing in Gas City requires the rig and city to be colocated. We do it for convenience: opening one editor at the parent gives you both the configs and the app side by side. You can keep them apart if you prefer (rig at `~/code/rss-reader`, city at `~/work/rss-reader-city`); `gc rig add` accepts an absolute path.

For GitHub: two repos is the natural shape. Push `rss-reader/` as the app repo (this is what you would deploy if you ever did). Push the parent repo as the tutorial-companion repo, or keep it private. Single-repo is friction for no gain because `bd`'s auto-export needs `git add` to work inside the rig directory. Submodules work if you want one URL.

</details>

## Step 1: Create the project layout

```bash
mkdir gas-city-tutorial && cd gas-city-tutorial
git init
mkdir notes tutorials
```

## Step 2: Initialize the city

```bash
gc init --provider claude --name rss-tutorial city
```

The flags make this non-interactive. To see what `gc init` is asking for, drop them and run `gc init city`; either path produces the same result.

The non-interactive form walks an eight-step setup ending with `[8/8] Waiting for supervisor to start city`, after which the prompt returns. A launchd agent is installed at `~/Library/LaunchAgents/com.gascity.supervisor.plist`. It manages every Gas City you create on the machine, runs in the background, restarts on login. Stop it with `gc supervisor stop` if you need to.

## Step 3: Make `gc` happy about your role

```bash
git config beads.role maintainer
```

`bd` (the bead store, which Gas City uses for tasks and mail) prints a warning on every write if `beads.role` is unset. One line silences it forever, scoped to this repo's `.git/config`.

## Step 4: Add the rig

A rig is a project directory inside your city that agents work on. Our rig is `rss-reader/`.

```bash
gc rig add rss-reader
mkdir rss-reader
cd rss-reader && git init && cd ..
```

`gc rig add` registers the rig with the city. The `git init` is necessary because `bd`'s auto-export uses `git add` inside the rig.

## Step 5: Tell the parent repo what to ignore

```bash
cat > .gitignore <<'EOF'
# Rig has its own git history
rss-reader/

# City runtime state (regenerated by gc init)
city/.gc/
city/.runtime/
city/.claude/skills/

# Editor cruft
.DS_Store
EOF
```

`city/.claude/skills/` contains absolute-path symlinks into a gitignored runtime directory; cleaner to ignore the link directory and let `gc init` regenerate it locally.

## Step 6: Verify

```bash
cd city
gc status
```

You should see something close to:

```
rss-tutorial  /Users/<you>/.../gas-city-tutorial/city
  Controller: supervisor-managed (PID ...)
  Authority:  supervisor process PID ...
  Suspended:  no

Agents:
  dog                     scaled (min=0, max=3)
    dog-1                 stopped
    dog-2                 stopped
    dog-3                 stopped

0/3 agents running

Named sessions:
  mayor                   reserved (always)

Rigs:
  rss-reader              /Users/<you>/.../gas-city-tutorial/rss-reader
```

A few things worth knowing:

- The **`dog`** pool is added by the maintenance system pack. It is a city-scoped utility worker for housekeeping (jsonl backup, shutdown dance). You will never address it directly.
- The **`mayor`** is `reserved (always)`: configured to run continuously, not yet materialized. We wake it in Part 1.
- **Polecats are invisible until they run.** The four specialists you will register in later chapters spawn on demand and only appear in `gc status` while they are active.

```bash
gc doctor
```

If it complains about the rig not being a git repository, you missed `cd rss-reader && git init` in Step 4. Otherwise everything should pass.

## Shape check

- A `city/` directory with a `pack.toml`, `city.toml`, `agents/mayor/prompt.template.md`.
- A `rss-reader/` directory that is a fresh git repo.
- `gc status` shows the city with a `dog` pool, a reserved `mayor` named session, and the `rss-reader` rig.
- `gc doctor` is clean.

## When your agent goes off-script

- **`gc init` hangs at step 8 or fails.** A stale launchd agent from a prior install. `gc supervisor stop`, `gc supervisor start`, then re-run `gc init` against a fresh city dir.
- **`bd create` (or `gc session wake`) fails later with `database not initialized: issue_prefix config is missing`.** [GH#1232](https://github.com/gastownhall/gascity/issues/1232), a v1.0.0 bd init bug. Surfaces twice in this tutorial: on first wake of the mayor (Part 1, against the city's `hq` database) and on first sling into the rig (Part 2, against the rig's `rr` database). Each chapter has the inline fix. By the time you read this the bug may be fixed and you skip both.

Now we wake the mayor and send our first piece of mail.
