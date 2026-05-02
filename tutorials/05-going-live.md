# Part 5: Going live

Up to now you have driven everything by hand. You sent a feature request, the mayor decomposed it, the chain ran. In this chapter we let the system run on its own schedule. By the end you have three jobs ticking in the background, and you have written your first formula from scratch.

By the end:

- A **cooldown** order that re-ingests the HN feed every two minutes.
- A **cron** order that prunes old items and compacts the database nightly.
- A **custom formula** (`mol-rss-digest`) that an LLM-backed agent runs on a cron, picks the day's top items, and commits a real `digest.md` to the rig.
- A `/digest` route on the app that renders that file in the browser.

The new concept here is **orders**: scheduled triggers that fire either after a cooldown elapses or on a cron expression. Orders can run an `exec` (a shell command) or a `formula` (a polecat's lifecycle). You will write all four shapes in this chapter.

## Order shapes at a glance

Two trigger types: `cooldown` (fire every N seconds/minutes), and `cron` (fire on a cron expression). Two execution shapes: `exec` (run a shell command), and `formula` (run a polecat through a formula's steps). All four combinations are valid, and Part 5 walks through three of them: cooldown+exec, cron+exec, cron+formula.

## Beat 1: a cooldown order that re-ingests the feed

`rss-fetch` is the first job. We want fresh items in the database every couple of minutes; cooldown is the right trigger because we just want "every 2 min, period," not "at minute 0 of every odd hour."

Create `city/orders/rss-fetch.toml` with this content:

```toml
[order]
description = "Fetch HN RSS feed every two minutes and ingest new items"
trigger = "cooldown"
interval = "2m"
exec = "cd /Users/<you>/.../gas-city-tutorial/rss-reader && bun run src/cli/ingest.ts"
timeout = "30s"
```

Replace the `<you>` path with your real path. Yes, the absolute path is ugly; we will talk about why in a moment.

Verify the order is registered:

```bash
gc order list
```

You should see `rss-fetch` listed with its trigger and schedule. Wait two minutes, then:

```bash
gc order history
```

You should see one or more `rss-fetch` rows, each with a timestamp. The exec ran. Confirm by checking the database:

```bash
sqlite3 ../rss-reader/rss-reader.db "SELECT COUNT(*) FROM items;"
```

The count should be larger than it was before, by however many new HN items appeared in the last interval.

If you would rather not wait, force-fire it:

```bash
gc order run rss-fetch
```

Manual `gc order run` does not write history (no `gc order history` row) but does run the exec. Useful for "is the exec line valid" verification.

### Why the absolute path

`rss-fetch` is at `city/orders/rss-fetch.toml`, which makes it a **city-scoped** order. The exec runs in whatever working directory the order dispatcher happens to be in; relative paths from inside `city/` would be brittle and wrong. The cleanest thing to do here is type out the absolute path. Less elegant than rig-scoped orders (covered in Beat 3) but it does the job.

### Sidebar: order scope follows file location, not the `pool` field

There is a subtle thing buried in the order primitive that costs an evening if you trip on it. **Where the order TOML file lives determines which bead store gets the work bead.** Files under `city/orders/` create city-scoped beads (prefixed `rt-`). Files under `<rig>/orders/` create rig-scoped beads (prefixed `rr-` for our `rss-reader` rig).

The `pool` field on a `formula`-shape order names the target agent, but it does **not** determine the bead store. So if you put a rig-scoped formula order at `city/orders/`, the dispatcher creates beads in the city's store and your rig-bound polecat (which reads from the rig's store) never sees them. The order fires forever, beads pile up, no work happens.

We will run into this in Beat 3 when we write the digest order. Move the file to the rig, the dispatcher does the right thing.

## Beat 2: a cron order that prunes and compacts

`rss-fetch` keeps adding rows. Without a counter-pressure the table grows forever. The reasonable answer is to delete items older than 30 days and reclaim the space. This is a "run at 4am" job, not a "run every X minutes" job, so cron is the right trigger.

Write `city/orders/rss-vacuum.toml`:

```toml
[order]
description = "Prune items older than 30 days and compact the rss-reader sqlite database nightly"
trigger = "cron"
schedule = "0 4 * * *"
exec = "sqlite3 /Users/<you>/.../gas-city-tutorial/rss-reader/rss-reader.db \"DELETE FROM items WHERE published_at < datetime('now', '-30 days'); VACUUM;\""
timeout = "5m"
```

Both statements run in one `sqlite3` call: delete rows older than 30 days, then VACUUM to actually reclaim the freed space. SQLite's VACUUM rewrites the file in-place; on its own it does nothing in a write-only database, which is why we pair it with the DELETE.

For the first 30 days of your app's life the DELETE is a no-op (nothing matches the WHERE), but VACUUM still runs and the order has a healthy history. After day 30 the DELETE starts removing items and VACUUM has real work.

### Verifying cron without waiting until 4am

Cron orders do not auto-fire until their schedule matches. Two ways to confirm yours is wired right:

1. **Force-fire once.** `gc order run rss-vacuum` runs the exec immediately. No history row written, but you confirm the SQL parses and runs.
2. **Temporarily switch to every minute.** Edit the schedule to `* * * * *`, save, wait 60 seconds, then revert. fsnotify picks the edit up without a restart. Useful when you want to see one auto-fire end to end.

```bash
gc order run rss-vacuum
gc order history rss-vacuum
```

You will see the manual run does not show in history (that is intended; manual runs are diagnostic). To see history, do the every-minute swap or wait until the cron schedule matches.

### Sidebar: reading `gc order check` for cron

Two reasons surface for cron orders that read confusingly the first time:

- `cron: schedule not matched`. The current minute does not match the expression. Fully expected outside the matching window.
- `cron: already run this minute`. The order fired in this current minute and the dispatcher is waiting for the next minute boundary. This is the per-minute deduplication guard; you can safely ignore it.

Neither is a failure. A cron order that says "schedule not matched" all afternoon is doing exactly what it should.

## Beat 3: a custom formula and a cron order that runs it

So far the orders run shell commands. The third one is different: it dispatches a formula to a polecat, and that polecat is an LLM session that picks today's top items, writes a markdown digest, and commits it.

Why this shape: anything that needs *judgment* (which items are interesting, what to write about them) cannot be a shell command. Anything that needs to commit on behalf of a specialist already has a polecat lane (backend) we can use. So the order's job is to spawn a backend polecat with a structured assignment, and the formula is what the polecat follows.

This is also the chapter's reader-writes-one-config-from-scratch moment. We are writing a formula by hand.

### Step 3a: extend `city.toml` to give the rig its own formula layer

The order will live in the rig (because the formula will live in the rig, and the work needs to land in the rig's bead store). For Gas City to scan a rig's `orders/` directory, the rig has to declare a formula layer. Open `city/city.toml` and add the `formulas_dir` field:

```toml
[workspace]
provider = "claude"

[[rigs]]
name = "rss-reader"
formulas_dir = "../rss-reader/formulas"
```

Then create the directory:

```bash
mkdir -p ../rss-reader/formulas ../rss-reader/orders
```

Why this is needed: the dispatcher only scans rig orders if the rig has at least one rig-exclusive formula layer registered. Without `formulas_dir`, the rig's formula layers are identical to the city's, the rig has no exclusive layer, the rig's `orders/` directory is never scanned, and your order is invisible. With the field set, even an empty `formulas/` directory is enough to flip the switch (and we are about to put a real formula in there).

### Step 3b: write the formula

Create `rss-reader/formulas/mol-rss-digest.toml`:

````toml
description = """
  Generate a daily RSS digest. Select the most interesting items from the
  last 24 hours and write a one-paragraph summary per item to digest.md
  in the rig.

  ## Variables

  | Variable | Source | Description |
  |----------|--------|-------------|
  | issue | caller | The work bead ID assigned to this agent |
  """
formula = "mol-rss-digest"
version = 1

[vars]
[vars.issue]
description = "The work bead ID for this digest run"
required = true

[[steps]]
id = "generate-digest"
title = "Pick top items, write digest, commit"
description = """
  Generate the daily digest from the last 24 hours of RSS items.

  1. Read your assignment:
  ```bash
  bd show {{issue}}
  ```

  2. Query the last 24 hours of items:
  ```bash
  sqlite3 rss-reader.db <<'SQL'
  .headers on
  .mode list
  SELECT id, title, source_domain, url, published_at
  FROM items
  WHERE published_at >= datetime('now', '-1 day')
  ORDER BY published_at DESC;
  SQL
  ```

  3. Pick the 5 most interesting items. Use your judgment. Look at
  title, source domain, recency. Favour technical depth, surprising
  findings, and items that read as substantive rather than churn.

  4. Write digest.md in the rig root:
  ```
  # Daily digest, <YYYY-MM-DD>

  1. **<title>** ([<domain>](<url>)) - <one-sentence rationale>
  2. ...
  ```

  5. Commit:
  ```bash
  git add digest.md
  git commit -m "digest: $(date +%Y-%m-%d) top items"
  ```

  6. Close the bead:
  ```bash
  bd update {{issue}} --status=closed --notes "Wrote digest with 5 items"
  ```

  Exit criteria: digest.md exists in the rig, committed, bead closed.
  """

[[steps]]
id = "drain"
title = "Signal completion"
needs = ["generate-digest"]
description = """
  Work is done. Signal the controller:

  gc runtime drain-ack
  """
````

Two things worth noting in the syntax:

- `formula = "mol-rss-digest"` is the formula's *name* (how orders refer to it), independent of the filename.
- `{{issue}}` in a step description gets resolved to the step's bead id when the polecat picks it up. Useful for "operate on your own assignment" patterns.

The formula has two steps. The first does the actual work. The second runs `gc runtime drain-ack`, which signals the controller that the work is done and the polecat can exit cleanly. Without an explicit drain step, the polecat's molecule does not close cleanly; you can think of `drain` as a tidy "work complete, recycle me" handshake.

A mild gotcha worth flagging: in step 6 above, the formula tells the polecat to `bd update {{issue}} --status=closed`. The `{{issue}}` resolves to the *step's* bead, not the parent molecule, so the molecule sometimes lingers as open even after the work has finished. That is cosmetic for our purposes (the work is done, the file is committed, the digest exists). If it bothers you in production, change the step to look up the parent molecule (`bd show {{issue}} --json | jq -r .parent_id`) and close that instead.

### Step 3c: write the order that dispatches it

Create `rss-reader/orders/rss-digest.toml`:

```toml
[order]
description = "Generate the daily RSS digest at 8am"
formula = "mol-rss-digest"
trigger = "cron"
schedule = "0 8 * * *"
pool = "backend"
```

Three differences from the cron order in Beat 2:

- `formula = "mol-rss-digest"` instead of `exec = "..."`. The order dispatches the formula.
- `pool = "backend"` names the target polecat lane. The work bead created by the dispatcher gets `gc.routed_to = "rss-reader/backend"` stamped on it; the reconciler spawns a backend polecat to handle it.
- The file lives at `rss-reader/orders/`, not `city/orders/`. This is the order-scope rule from Beat 1 in action: the rig is where the work needs to land.

### Step 3d: reload the formula layer cache

```bash
gc supervisor reload
```

fsnotify picks up file content edits reliably, but adding new files (especially formulas) sometimes does not rebuild the in-memory layer cache the dispatcher uses. An explicit `gc supervisor reload` forces a rebuild and is the safe move whenever you add a formula or move an order between scopes.

### Step 3e: verify and force-fire

```bash
gc order list
```

You should see `rss-digest` listed alongside `rss-fetch` and `rss-vacuum`. To force a run without waiting until 8am:

```bash
gc order run rss-digest
```

You will see a backend polecat spawn in `gc session list`, run the formula's steps, and after a couple of minutes the rig has a new commit:

```bash
cd ../rss-reader
git --no-pager log --oneline -3
ls digest.md
cat digest.md
```

The digest is real: five HN items from the last 24 hours with one-line rationales, committed by the polecat with a message like `digest: 2026-05-02 top items`.

## Beat 4: render the digest in the browser

The digest exists on disk. The natural next step is to surface it in the app, since that is what makes the loop visible. This is a short feature and the perfect closer for Part 5.

```bash
gc handoff --target mayor "Add /digest route" 'When digest.md exists at the rig root, expose a GET /digest route that renders the file as HTML. The digest is markdown; render it with a small markdown-to-HTML conversion (any minimal lib is fine). If digest.md is missing, show a friendly empty state pointing at the cron schedule. Match the existing index page styling; add a small "Daily digest" link in the header so it is discoverable from /. Decompose, pre-route the chain, and let it run hands-off.'
```

(Note: `gc handoff --target mayor` does not restart the always-on session, but it does deliver the mail. The mayor has not had its prompt changed, so no restart is needed.)

The mayor decomposes into two beads (frontend template + index header link, backend route), pre-routes both, and lets the chain run. A few minutes later the rig has two new commits and `/digest` works:

```bash
cd ../rss-reader
bun run src/index.ts &
sleep 1
curl -sI http://localhost:3000/digest | head -1
kill %1
```

You should see `HTTP/1.1 200 OK`. Open `http://localhost:3000/digest` in a browser. The digest renders. The header on `/` has a small "Daily digest" link.

You have closed the loop: cron fires, agent generates, app renders. Cooldown ingest still drips in fresh items every two minutes, the nightly prune is on its schedule, the daily digest at 8am will produce tomorrow's content while you sleep.

## How would this look in a deployed app?

Everything in this chapter ran on your laptop because Gas City is running there: the supervisor is up, dolt is serving, polecats can spawn into Claude Code sessions, your API keys are in the environment. We did it locally for two reasons. First, Part 5 is the chapter that teaches orders and custom formulas, and the easiest way to teach the primitives is to use them. Second, you end up with a working app you can poke at locally. Both wins.

If you ever wanted to actually deploy this RSS reader, the picture changes considerably. Gas City's value lives during construction (multi-agent feature delivery, review loops, hands-off chains, the experience you just had). For the four scheduled pieces in this chapter specifically, GC is overkill in production, and the right deployment shape is different for each. Walk through them one at a time.

### Cooldown order: re-ingest HN every 2 minutes

The job is "every 2 minutes, fetch the feed and upsert items." That is a classic scheduled task, well-served by primitives older than Gas City.

Three real options:

- **Platform cron.** `*/2 * * * *` in Vercel Cron, Fly machines schedule, k8s CronJob, systemd timer, or plain crontab calling your `bun run src/cli/ingest.ts` script. Minute-granularity is fine for "every 2 min."
- **In-process timer.** At app boot, run `setInterval(ingest, 120_000)`. The app does its own ingestion loop. No external scheduler needed. Simplest deployable shape: one process, one container.
- **Sidecar worker.** A separate Node/Bun process whose only job is the ingest loop. Useful when you want to scale or restart it independently of the web app, or when your platform recycles the web process between requests.

Gas City's order primitive does not buy you anything extra over these. The supervisor + history + dispatch machinery is dev-time tooling; in production an interval does the same work in fewer characters. For this app, in-process `setInterval` is what I would reach for.

### Cron order: nightly prune + VACUUM

Same shape as the cooldown one, different schedule. The SQL stays exactly the same. The runner is platform cron, or an in-process `setTimeout` aligned to 4am.

One production-only consideration: VACUUM rewrites the database file in place and briefly holds a write lock. At our scale (hundreds of items, maybe thousands after months) the lock is sub-second and nobody notices. At a different scale you would want either `PRAGMA auto_vacuum = INCREMENTAL` (so VACUUM gets cheaper) or a maintenance window. For this app, `0 4 * * *` with raw VACUUM is correct.

Same answer as the cooldown: platform cron with the same SQL. No GC.

### The digest: where the LLM call lives

This is the interesting one because the work itself is an LLM call. Three production options, all valid for different shapes of project:

**Option A: run Gas City on the server.** Deploy the rig, the city, the supervisor, dolt, the coding-agent CLI, and the API key onto the host. The cron order fires there, the supervisor spawns a backend polecat, the polecat calls the LLM, writes the digest, commits. Cost: dolt running 24/7, supervisor process, the entire GC stack on a host whose purpose is to serve a Hono app. Right when: you actually have other multi-agent work happening on the server. Wrong when "I just want the daily digest."

**Option B: run Gas City somewhere else with credentials. Commit the artifact. Deploy from git.** GC runs where the API keys live (your laptop, a worker box, a build server). The agent produces `digest.md`, commits to the rig repo, pushes. Your prod host auto-deploys on push, or pulls on cron. Cost: you need GC running somewhere reliable. Right when: you want the agent's output to be reviewable and version-controlled, and "fresh every morning plus or minus a few hours" is good enough.

**Option C: skip Gas City in prod entirely. Call the LLM API directly.** A small script in the rig: queries the DB, builds a prompt, calls Anthropic via SDK, stores the digest. Trigger it with whatever scheduler your platform offers. Cost: trivial, about 30 lines plus an API key.

For this app, Option C is the right default, and the production version is small enough to write out:

```ts
// scripts/digest.ts
import Anthropic from "@anthropic-ai/sdk";
import { Database } from "bun:sqlite";

const db = new Database("rss-reader.db");
const items = db.prepare(`
  SELECT title, url, source_domain
  FROM items
  WHERE published_at >= datetime('now','-1 day')
  ORDER BY published_at DESC
`).all();

const client = new Anthropic();
const msg = await client.messages.create({
  model: "claude-sonnet-4-6",
  max_tokens: 2048,
  messages: [{
    role: "user",
    content: `Pick the 5 most interesting items from this list.
Use your judgment: technical depth, surprising findings, substantive
posts over churn. Return markdown with a numbered list, each item
'**title** ([domain](url)) - one-sentence rationale'.

Items:
${JSON.stringify(items)}`,
  }],
});

const today = new Date().toISOString().slice(0, 10);
db.prepare("INSERT OR REPLACE INTO digests (date, body_md) VALUES (?, ?)")
  .run(today, msg.content[0].text);
```

Triggered by `0 8 * * *` in your platform's cron config. No Gas City. No file system. No git push.

Notice that the digest is now stored as a row in a `digests` table, not as a file in the rig:

```sql
CREATE TABLE digests (
  id INTEGER PRIMARY KEY,
  date TEXT NOT NULL UNIQUE,
  body_md TEXT NOT NULL,
  created_at INTEGER DEFAULT (unixepoch())
);
```

DB-as-storage makes more sense than file-as-storage in production. The digest is content, not configuration. Storing it next to the items it summarizes keeps everything queryable, deletable, and swappable without a deploy. No git pushes from prod.

The custom formula you wrote earlier in this chapter is not wasted: the prompt content (which items, in what shape, with what tone) ports directly into the prompt string above. The formula authoring exercise teaches the LLM-prompting muscle; the deploy decision is orthogonal.

### `/digest` route

Currently the route reads `digest.md` from disk and parses markdown. In production, with the digest stored in the DB, the route reads from there:

```ts
app.get("/digest", (c) => {
  const row = db.prepare(
    "SELECT date, body_md FROM digests ORDER BY date DESC LIMIT 1"
  ).get() as { date: string; body_md: string } | null;
  if (!row) return c.html(digestEmptyState());
  return c.html(digestPage(marked.parse(row.body_md), row.date));
});
```

You can also expose `/digest/:date` for old digests if you want to keep them. DB-as-storage gives you that for free.

If you keep digest.md as a file (because you really do want git-as-audit-log), the route stays the way you have it now, but you have coupled deploys to digest generation. Every digest is a commit, every commit is a deploy on most platforms. Some teams want this; most do not.

### The pattern that emerges

Imagine actually shipping this app. Gas City disappears from the production picture entirely. The four primitives you just learned map to:

| Tutorial primitive | Production replacement |
|---|---|
| cooldown order (`rss-fetch`) | platform cron, or in-process `setInterval` |
| cron order (`rss-vacuum`) | platform cron with the same SQL |
| custom formula (`mol-rss-digest`) | platform cron + 30-line script + Anthropic API |
| `/digest` route reading file | route reading from `digests` table |

That is a feature, not a flaw. None of GC's value shows up in `kubectl get pods` after deploy, and that is correct. GC earned its keep during construction: the mayor's decompose-and-route, the multi-specialist chain, the review loop in Part 4, the way you described features once and watched them ship. None of that is the daily digest. The daily digest is one LLM call.

A useful mental test: when you imagine a feature, ask whether the work is **one LLM call with deterministic surrounding code**, or **a coordination problem across multiple capabilities with judgment at each step**. The first wants a script and a scheduler. The second wants Gas City. The RSS digest is the first. Building the RSS reader was the second.

## Shape check

- Three orders registered (`gc order list`): `rss-fetch` (cooldown 2m, exec, city scope), `rss-vacuum` (cron 0 4 * * *, exec, city scope), `rss-digest` (cron 0 8 * * *, formula, rig scope).
- One custom formula `mol-rss-digest` at `rss-reader/formulas/mol-rss-digest.toml`.
- `city.toml` has `formulas_dir = "../rss-reader/formulas"` on the rss-reader rig block.
- `rss-reader/digest.md` exists and is committed.
- `GET /digest` returns the rendered digest. `GET /` has a "Daily digest" link.

## When your order goes off-script

- **`gc order list` does not show your rig-scoped order.** The rig probably does not have `formulas_dir` set. Add it to `city/city.toml`, create `rss-reader/formulas/`, run `gc supervisor reload`.
- **Order fires but no polecat picks it up.** Check the bead store. If you slung from `city/orders/` with `pool = "rss-reader/backend"`, the bead is in the city store and the backend polecat reads from the rig store; they will never meet. Move the order TOML to `rss-reader/orders/`.
- **Formula-shape order fires but `formula "<name>" not found in search paths`.** Move the formula file to the rig (`rss-reader/formulas/`) and run `gc supervisor reload`. fsnotify alone does not always rebuild the layer cache for new files.
- **Cron schedule reads "schedule not matched" all day.** That is normal. The schedule only matches at the configured minute. Force-fire to verify the exec runs.
- **Cron schedule fires at the wrong hour.** Local time, not UTC. Adjust accordingly.
- **Every-minute test (`* * * * *`) creates a flood of beads.** Each fire spawns a fresh molecule, tracking bead, and potentially a polecat. Use `gc order run <name>` for one-shot verification (no history row, but exec/formula runs cleanly). Save `*/5 * * * *` for "show me an auto-fire on a short loop and let the polecat finish before the next."

In Part 6 we wrap up: one feature request, one mayor handoff, all four specialists running together hands-off. The capstone.
