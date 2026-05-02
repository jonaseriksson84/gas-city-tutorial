# Part 6: Capstone, ship-it autonomously

You have all seven primitives live. The mayor is awake, four specialists sit dormant ready to spawn, three orders tick on schedule, one custom formula produces a real artifact every morning. There is nothing left for this tutorial to teach about Gas City as a primitive set.

What is left is the experience of using it. This chapter is a single feature delivery, end to end, with one handoff and no nudges. You watch the system work.

The test-run transcript is embedded in this chapter. Your run will differ in details: bead ids, exact wall-clock timing, whether the reviewer files one finding or three. The shape should match.

## The feature: full-text search with SQLite FTS5

Three reasons this is the right capstone:

- **DBA stretch.** A real schema migration: an FTS5 virtual table, three sync triggers, a backfill from existing rows.
- **Visible payoff.** You type in a box and results filter. Feels nothing like clicking refresh.
- **Reviewer surface.** FTS5's `MATCH` operator has its own quoting rules; naive injection of user input throws on `(`, `)`, `OR`, `NOT`. A careful reviewer catches it.

You only run one command in this chapter.

## The handoff

```bash
gc handoff --target mayor "Add search to rss-reader" 'I want full-text search over the indexed items. The index page should grow a small search input in the header. Typing in it should query item titles (and descriptions if cheap) and show matches in the same HN-style list. Live results via HTMX with sensible debounce are nice but not required; a plain GET form is fine if the agents prefer simpler. Use SQLite FTS5 for the search index, populate it from the existing items table, and keep it in sync as new items get ingested. Empty query should show the recent items as today. The reviewer should pay attention to user input handling around the FTS MATCH operator and to whether the index stays in sync after the next cooldown ingest. Decompose, pre-route the chain, and let it run hands-off.'
```

That is the entire chapter, mechanically. Everything below is what happens after.

## What to expect

The natural decomposition for search is four beads:

- **DBA**: an FTS5 virtual table over `items(title, description)`, content-table mode pointing back at `items`, three triggers (insert/update/delete), backfill from existing rows.
- **Backend** (depends on DBA): `GET /search?q=...` route running an FTS5 `MATCH` query. Empty `q` falls through to recent items.
- **Frontend** (depends on backend): a search input in the header, HTMX `hx-get="/search"` with a debounce, target an items div. Plain GET form fallback if HTMX is unavailable.
- **Reviewer** (depends on frontend): runs the app, reviews the lanes, pays attention to FTS quoting and trigger correctness.

Wall clock: five to ten minutes if no rework, up to fifteen with one round of fix beads.

What to watch:

- **The decomposition mail.** First mail back from the mayor. If lanes look wrong, fix via mail before specialists start.
- **Whether DBA lands a real FTS5 setup or fakes it with `LIKE`.** Both will look correct on small data; the reviewer should catch the cheat.
- **Reviewer's posture on input handling.** Either notices the FTS5 quoting issue or flags it.
- **Whether cooldown ingest keeps populating the FTS index.** Trigger correctness. After the chain ships, wait one cycle, search for a brand-new item, see if it appears.

Open the overview:

```bash
watch -n 3 bash bin/overview.sh
```

## What actually happened in the test run

The mayor decomposed into the four predicted beads in one batch, pre-routed in one shot.

DBA spawned first. While building the FTS5 table over `items(title, description)`, the agent noticed the `description` column did not exist on `items`. The bead description had asked for FTS over title and description, so the column was implied but not in the schema migration plan. The DBA agent added the column itself with an idempotent `ALTER`, closed the bead with a clean note.

Backend spawned next, shipped `/search` with safe input handling (try the query as raw FTS5 first, fall back to a sanitized phrase if `MATCH` throws). Frontend spawned, added the search input, picked a plain GET form over HTMX live search (the prompt left it open, the agents went with simpler), HTML-escaped the reflected query.

Then something interesting happened. **Fifteen minutes in, the mayor created a fifth bead unprompted**: backend ingest needed to populate the new `description` column from the feed. Otherwise new rows would have NULL descriptions and FTS5 over `description` would index empty strings. The mayor noticed the gap (or backend surfaced it during the `/search` work) and inserted a backend bead to fix it. No human in the loop. The orchestrator caught and patched a chain hole during execution.

Backend respawned, extended ingest to extract `<description>` from the feed (with HTML-strip and entity-decode), capped at 2000 chars, verified 30/30 non-empty descriptions on a fresh ingest. Closed.

Then the reviewer spawned. Read everything in scope. Booted an isolated test instance on port 3001 with its own fresh ingest cycle to verify the schema and triggers cleanly. Ran the hostile-input set: `"`, `*`, `(`, `)`, `AND/OR/NOT/NEAR`, a 1KB string, unicode. All returned 200. Approved the lanes.

Found two things and filed fix beads:

- A UX bug where typing `(broken` cleared the input on fallback so the user lost their typing.
- A doc-only finding asking for an explanatory comment at the route call site.

The reviewer also tried to mail the backend specialist directly with the findings. There was no live backend session at that point (the previous polecat had drained), so the mail send returned an error. The reviewer's prompt has a fallback for exactly this case: when no live session exists, attach the observation as a bead note. The note rides with the bead permanently. The reviewer did exactly that, then mailed the mayor with the list of fix beads.

Mayor read the findings mail, slung both fix beads, spawned a fresh review bead depending on the fixes, slung that to the reviewer. Backend respawned, shipped both fixes. Reviewer respawned, verified, approved.

Final tally:

- **7 work beads**: 4 predicted + 1 mid-flight insertion + 2 reviewer findings.
- **All 4 specialist lanes engaged**: dba, backend (three times), frontend, reviewer (twice).
- **27 minutes wall clock** from handoff to last commit.
- The 8am `rss-digest` cron fired during the search work and produced its commit cleanly. Orders kept ticking in the background.

## Verification

```bash
cd ../rss-reader
bun run src/index.ts &
sleep 1

curl -s -o /dev/null -w "kubernetes: %{http_code}\n" 'http://localhost:3000/search?q=kubernetes'
curl -s -o /dev/null -w "empty:      %{http_code}\n" 'http://localhost:3000/search?q='
curl -s -o /dev/null -w "broken:     %{http_code}\n" 'http://localhost:3000/search?q=(broken'

kill %1
```

All three should return 200. Browser eyeball: type into the input on `/`, hit return, results swap.

<details>
<summary><strong>Sidebar:</strong> mail to polecats does not queue</summary>

If you mail a polecat lane that has no live session, the send fails (no inbox until a session spawns). The reviewer's fallback is to put the observation on the bead description as a note: `bd note add <bead-id> "<text>"`. The note rides with the bead; the next session that picks it up sees the context.

Pattern, in two lines:

- **Mail named/always-on agents** (mayor, human). They have inboxes that hold messages.
- **Put context on beads for polecats** (backend, dba, frontend, reviewer). Bead notes outlast mail and carry context to whoever spawns next.

</details>

## Shape check

- One feature shipped: full-text search with FTS5, working `/search` route, search input on `/`.
- All four specialists engaged in this single feature.
- Closed work beads from the chain (yours may number 4 to 7+ depending on how the chain unfolded).
- Hostile input curls all return 200, not 500.
- The cooldown ingest still adds rows, and they are searchable shortly after.

## When your agent goes off-script

- **The agents pick `LIKE` instead of FTS5.** The reviewer should catch this. If it does not, follow up to the mayor: "FTS5 was specified; the current implementation uses `LIKE`. Please refile and re-route."
- **Backend's `/search` 500s on parentheses or `OR`.** The reviewer should catch this too. If you find it after the chain settled, file a fix bead by hand and ask the mayor to sling it.
- **Cooldown ingest stops mid-chain.** After the chain settles, wait one cycle (~2 min), ingest a couple of new items, search for them. If they do not appear, the FTS5 triggers are wrong; file a fix bead.
- **The chain stalls before the review bead.** The last work bead's polecat drained but the review bead's `gc.routed_to` did not stick. Re-sling: `gc sling rss-reader/reviewer <review-bead-id> --on mol-do-work`.

## Go off-script: alternative capstone features

If you would rather build something else, two one-paragraph prompts you can swap into the handoff above.

**Per-source filter page.**

```
gc handoff --target mayor "Per-source filter" 'Add a /source/:domain page that lists items from one host. Link the source label in each row of / to its filter page. Add a small "top sources" list somewhere on / showing the five most-linked domains. No schema change should be needed; the domain column was added in Part 4. Decompose, pre-route, run hands-off.'
```

Backend and frontend lanes, DBA untouched, reviewer pass. Smaller than search.

**Saved items.**

```
gc handoff --target mayor "Saved items" 'Let me save items. Each row on / gets a small star toggle that flips saved on or off, persisted in SQLite. Add a /saved page that lists saved items in the same HN-style format. Saved state must survive the nightly rss-vacuum cron. Decompose, pre-route, run hands-off.'
```

All four lanes including DBA (smaller migration than search), reviewer pass. Persistence-shaped feature.

## The seven primitives, in the order they surfaced in this single delivery

1. **City and rigs.** The workspace and the rss-reader rig where the search work landed.
2. **Agents and sessions.** Four polecats spawning into existence on demand off the bead chain. None pre-running; each one materialized when its bead became ready.
3. **Communication.** Mayor's reply to your handoff. Reviewer's mail to the mayor with findings. Reviewer's reach for direct mail to backend, finding no live session, falling back to a bead note.
4. **Beads.** Created, wired with deps, all closed by chain end.
5. **Sling.** `--on mol-do-work` calls upfront and for fix beads. Reconciler did the rest.
6. **Formulas.** `mol-do-work` driving each polecat's lifecycle. Your custom `mol-rss-digest` from Part 5 firing in the background.
7. **Orders.** Three ticking through the run: `rss-fetch` every two minutes, `rss-vacuum` at 4am, `rss-digest` at 8am.

## Where to go next

Practical follow-ups, ordered roughly smallest to largest. Pick whatever matches your itch.

- **Pagination on the index.** `/` currently shows 30 items hardcoded. Add a "show more" button (HTMX-shaped: `hx-get="/?page=2"` swapping in the next batch) or a permalink-friendly `?page=N`.
- **Show only items from a particular domain.** Either the `/source/:domain` page from above, or a query param filter on `/`.
- **Mark/unmark read.** A `read_at` column on items, a small star or check toggle on each row, a "show only unread" filter. The Part 5 `rss-vacuum` cron can be retargeted to prune **read** items older than N days, making the cleanup user-driven instead of operational.
- **Favorite/unfavorite articles with a `/favorites` page.** Same shape as mark-read but kept indefinitely.
- **Replace the hardcoded HN feed with multiple feeds.** A `feeds` table, an admin route to add and remove feeds, an ingest loop that iterates. A real four-lane chain.
- **Move the digest out of Gas City and into a small script that calls Anthropic directly.** Per Part 5's deployed-app section. Drops GC out of production for this app entirely, which is the right shape if you ever ship it.
- **Auth and user-specific feeds.** Each user has their own feeds, read state, favorites. The biggest single jump in scope: a user model, sessions, permission checks on every route.
- **Tags or categories.** Either user-applied or auto-classified by an LLM at ingest time. The latter is a small "AI feature in production" use case.
- **Saved-search-as-feed.** Take any FTS5 query and turn it into a permalinked view. `/q/rust` shows the latest items matching. Trivial backend, free reuse of Part 6's search work.
- **Email or Slack digest delivery.** A small webhook script triggered after the digest row is written.
- **A weekly or monthly digest** alongside the daily one, with a different prompt. Same custom-formula shape.
- **Stats page.** Top sources by week, items per day, your read-rate. SQL aggregations rendered in HTML.
- **Dark mode and a responsive layout.** Frontend lane only.
- **Export your digests as their own RSS feed.** `/digest.rss`. Pleasingly recursive: consume your AI summaries from another reader.

And the bigger swings:

- **Build a second app with the same crew.** The mayor + backend + dba + frontend + reviewer roster ports to anything: a personal kanban, a habit tracker, a side-project journal. The configs you wrote here are the durable artifacts; the rss-reader code was a demonstration.
- **Replace one specialist with a Codex agent.** Or add a sixth specialist (a tester, a docs-writer, a PR-reviewer) and see how the chain reshapes itself.
- **Use Gas City for non-coding work.** A weekly research roundup, a financial reconciliation, an ops runbook executor. The orchestration shape generalizes.

The world is your oyster. The point of these seven chapters was not to build an RSS reader. It was to give you a working mental model for "describe a feature, watch the system ship it." You have that now. The next thing you build with Gas City does not need a tutorial.
