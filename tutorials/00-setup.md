# Part 0: Setup

This is a seven-part tutorial about building a working web app while learning Gas City. Each part adds something new on top of the last. By the end you have an RSS reader of your own and a mental model for how Gas City fits into a project.

If you have used coding agents in your editor (Claude Code, Cursor, Codex), you already have most of the muscle this tutorial asks for. Gas City sits one level above that: instead of one agent helping you in your editor, you orchestrate several agents from the command line, each with its own role, and watch them deliver a feature together. The fancy word for this is multi-agent orchestration. The unfancy word is "you describe a feature once, the agents handle the rest."

## What we are building

A minimalist Hacker-News-style RSS aggregator. It fetches the HN front-page feed, stores items in SQLite, renders them in a simple page, and ships small features along the way (per-source labels, search, a daily LLM-generated digest). The app is written by agents under your direction. The configs you write to direct them are the artifacts you keep.

By the end:

- A small Hono app on Bun, with `bun:sqlite`, `hono/html`, and HTMX.
- Five agents in your city: a mayor (always-on coordinator), a backend specialist, a DBA specialist, a frontend specialist, and a code reviewer.
- Three scheduled jobs: a periodic feed fetch, a nightly database prune, and a daily AI-written digest.

The stack is deliberately self-contained. No build step, no bundler, no `node-gyp`, no JSX transpilation, no Tailwind toolchain. Bun runs `.ts` files directly. `bun:sqlite` is built in. `hono/html` is server-rendered HTML with a small template-tag literal API. HTMX adds interactivity without leaving the server side. Less to configure means less for the agents to get wrong, which keeps the chapters short and the failures legible.

## What you need installed

| Tool | Version used |
|---|---|
| Bun | 1.3.6 |
| Gas City `gc` | 1.0.0 |
| Beads `bd` | 1.0.3 |
| Claude Code | 2.1.121 |
| Codex (optional, used in Part 4) | 0.125.0 |
| tmux | 3.6a |

Tap and install Gas City via Homebrew:

```bash
brew install gastownhall/gascity/gascity
```

That pulls in `gc`, `bd`, `dolt`, `tmux`, `jq`, and `flock` automatically. Install Bun separately:

```bash
curl -fsSL https://bun.sh/install | bash
```

Make sure Claude Code is set up and signed in. The mayor and most specialists run on Claude. In Part 4 you can optionally swap one agent over to Codex; if you skip that, you do not need Codex installed.

For credits: a Claude Code subscription covers the full run with no extra setup. The whole tutorial ran on my Anthropic subscription end to end without a separate API key. Codex on the reviewer in Part 4 ran on its free tier from my ChatGPT login and used roughly nothing. If you do not have a subscription and want to use API credit instead, $2 to $5 of Anthropic credit covers the full run, plus maybe a dollar for Codex if you do the provider swap. The simplest readiness check: type `claude` and `codex` at the shell, confirm both start and respond. If they do, Gas City will use them.

## A note before we start: agents do not produce identical output

Every command output, file path, and config in this tutorial is what happened on my run. Your run will differ in details. The agents will pick slightly different file names, slightly different code shapes, slightly different commit messages. That is fine. Each chapter ends with a **shape check** that lists what should be true, not what should be byte-identical: "the app renders an HN-style list at `/`," "this bead is closed," "this commit exists in the rig." If your shape matches, you are on track.

When something goes off-script, each chapter has a "When your agent goes off-script" section with the failure modes I observed and recovery moves. The companion repo has a `chapter-N` tag for every chapter; if you ever want to skip ahead from a known-good state, `git checkout chapter-N` recovers it.

## Workspace layout

```
gas-city-tutorial/        parent repo
├── city/                 your Gas City workspace (configs, prompts)
├── rss-reader/           the rig (its own git repo, the app code)
├── notes/                your own notes if you keep any
└── tutorials/            these chapters
```

The parent is a git repo. `rss-reader/` is its own git repo (initialized in step 4 below) and is gitignored from the parent. They have independent histories on purpose: the rig is what the agents write to, the parent is what you write to.

Two notes about this layout. First, the rig does not have to live under the same parent directory as the city. We do it for convenience: opening one editor at the parent gives you both the configs and the app side by side. If you would rather keep them apart (rig at `~/code/rss-reader`, city at `~/work/rss-reader-city`), nothing in Gas City requires colocation. `gc rig add` accepts an absolute path, and the city's `city.toml` records whatever path you give.

Second, on shipping to GitHub: the rig and the city are two independent git histories, so the natural answer is two GitHub repos. Push `rss-reader/` as the app repo (this is what you would deploy if you ever did). Push the parent repo (containing the city configs, your notes, this tutorial) as the tutorial-companion repo, or keep it private. Trying to ship them as a single repo is friction for no gain: `bd`'s auto-export needs `git add` to work inside the rig directory, which means the rig has to be its own git history. Submodules are an option if you want one URL, but the simpler answer is two repos.

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

The `--provider` and `--name` flags make this non-interactive, which is convenient for tutorial scripts. If you would rather see what `gc init` is asking for, drop the flags:

```bash
gc init city
```

It will prompt for the provider, the city name, and a few other defaults. Either path produces the same result.

The non-interactive form walks an eight-step setup:

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
Registered city 'rss-tutorial' (...gas-city-tutorial/city)
Installed launchd service: ~/Library/LaunchAgents/com.gascity.supervisor.plist
[8/8] Waiting for supervisor to start city
```

Step 8 returns silently when the supervisor finishes booting. A launchd agent is installed at `~/Library/LaunchAgents/com.gascity.supervisor.plist`. This is a per-user daemon that manages every Gas City you create on the machine, not just this one. It runs in the background, will restart on login, and uses very little memory while idle. If you ever want to stop everything: `gc supervisor stop`.

## Step 3: Make `gc` happy about your role

```bash
git config beads.role maintainer
```

`bd` (the bead store, which Gas City uses for tasks and mail) prints a warning on every write if `beads.role` is unset. Setting it once silences the warning forever. It writes to the parent repo's `.git/config`, so it is local to this project.

## Step 4: Add the rig

A rig is a project directory inside your city that agents work on. Our rig is `rss-reader/`.

```bash
gc rig add rss-reader
mkdir rss-reader
cd rss-reader && git init && cd ..
```

`gc rig add` registers the rig with the city. Then we create the directory and `git init` it. Without the `git init`, `gc doctor` will warn about the rig not being a git repo, and `bd`'s auto-export will fail every time an agent writes a bead. One line, saves a lot of noise.

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

Why `city/.claude/skills/` is in there: `gc init` populates that directory with seven absolute-path symlinks pointing into `city/.gc/system/packs/.../skills/`. The targets are themselves gitignored, and the absolute paths would dangle on any clone. Easier to ignore the link directory and let `gc init` regenerate it locally.

## Step 6: Verify

```bash
cd city
gc status
```

You should see something close to this:

```
rss-tutorial  /Users/<you>/.../gas-city-tutorial/city
  Controller: supervisor-managed (PID ...)
  Authority: supervisor process PID ...
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

- The **`dog`** agent pool was added automatically by the maintenance system pack. It is a city-scoped utility worker for housekeeping (jsonl backup, shutdown dance, etc). You will never address it directly. If you see it in `gc status`, you did not break anything.
- The **`mayor`** named session is `reserved (always)`, which means "configured to run continuously, but the actual session is not yet materialized." It will materialize the first time you wake it. We do that in Part 1.
- **Polecats are invisible until they run.** Through this tutorial you will register four more agents (backend, dba, frontend, reviewer) that are not "always on." They are polecats: they spawn on-demand when work is routed to them. So `gc status` will not list them until you are actively running work. That is expected.

```bash
gc doctor
```

If it complains about the rig not being a git repository, you forgot the `cd rss-reader && git init` step from Step 4. Otherwise everything should pass.

## Shape check

- A `city/` directory with a `pack.toml`, `city.toml`, `agents/mayor/prompt.template.md`.
- A `rss-reader/` directory that is a fresh git repo.
- `gc status` shows the city with a `dog` pool, a reserved `mayor` named session, and the `rss-reader` rig.
- `gc doctor` is clean (or only flags warnings you understand and have noted).

## When your agent goes off-script

Nothing executes during Part 0 except `gc init`, so the mainline failure mode is not agent-related. Two things you might hit:

- **`gc init` says "supervisor failed to start" or hangs at step 8.** Your launchd agent might already exist from a prior install. `gc supervisor stop`, then `gc supervisor start`, then re-run `gc init` against a fresh city dir.
- **`bd create` (or `gc session wake`) fails later with `database not initialized: issue_prefix config is missing`.** This is [GH#1232](https://github.com/gastownhall/gascity/issues/1232), a v1.0.0 bug where bd silently fails to write its `issue_prefix` config row during init. The bug surfaces twice in the tutorial: once on first wake of the mayor (Part 1, against the city's bd database `hq` with prefix `rt`), and once on first sling into the rig (Part 2, against the rig's bd database `rr` with prefix `rr`). Both are fixed the same way, by inserting the row directly via dolt. From the city directory:

   ```bash
   cd .beads/dolt
   dolt --use-db hq sql -q "
     INSERT INTO config (\`key\`, value) VALUES ('issue_prefix', 'rt')
       ON DUPLICATE KEY UPDATE value='rt';
     CALL dolt_commit('-Am', 'set issue_prefix');"
   ```

   For the rig version (Part 2), substitute `--use-db rr` and the prefix `'rr'`. Both fixes are repeated inline at the points where each error first surfaces, so you do not need to flip back here. By the time you read this the fix may have shipped, in which case the error never appears and the workaround is unnecessary.

Now we wake the mayor and send our first piece of mail.
