# Part 6: Capstone, ship-it autonomously

You have all seven primitives live. The mayor is awake, four specialists sit dormant ready to spawn, three orders tick on schedule, one custom formula produces a real artifact every morning. There is nothing left for this tutorial to teach about Gas City as a primitive set.

What is left is the experience of using it. This chapter is a single feature delivery, end to end, with one handoff and no nudges. You watch the system work. The exact lesson is, "this is what 'ship it autonomously' actually feels like."

The test-run transcript is embedded in this chapter. Your run will differ in details: bead ids, exact wall-clock timing, whether the reviewer files one finding or three. The shape should match.

## The feature: full-text search with SQLite FTS5

Three reasons this is the right capstone over the alternatives:

- **DBA stretch.** A real schema migration: an FTS5 virtual table, three sync triggers, a backfill from existing rows. Bigger lift than the simple `domain` column from Part 4.
- **Visible payoff.** You type in a box and results filter. Feels nothing like clicking refresh.
- **Reviewer surface.** FTS5's `MATCH` operator has its own quoting rules, and naive injection of user input throws on `(`, `)`, `OR`, `NOT`. A careful reviewer catches it.

You only run one command in this chapter.

## The handoff

```bash
gc handoff --target mayor "Add search to rss-reader" 'I want full-text search over the indexed items. The index page should grow a small search input in the header. Typing in it should query item titles (and descriptions if cheap) and show matches in the same HN-style list. Live results via HTMX with sensible debounce are nice but not required; a plain GET form is fine if the agents prefer simpler. Use SQLite FTS5 for the search index, populate it from the existing items table, and keep it in sync as new items get ingested. Empty query should show the recent items as today. The reviewer should pay attention to user input handling around the FTS MATCH operator and to whether the index stays in sync after the next cooldown ingest. Decompose, pre-route the chain, and let it run hands-off.'
```

That is the entire chapter, mechanically. Everything below is what happens after.

## What to expect

The mayor's prompt covers multi-specialist chains and mandatory review beads. The natural decomposition for search is four beads:

- DBA (bead 1): an FTS5 virtual table over `items(title, description)`, content-table mode pointing back at `items`, three triggers (insert/update/delete) to keep the index in sync, plus a backfill from existing rows.
- Backend (bead 2, depends on bead 1): `GET /search?q=...` route running an FTS5 `MATCH` query, returning the same item list shape as the index. Empty `q` falls through to recent items.
- Frontend (bead 3, depends on bead 2): a search input in the header, HTMX `hx-get="/search"` with a debounce, target an items div. Plain GET form fallback if HTMX is unavailable.
- Reviewer (bead 4, depends on bead 3): runs the app, reviews the lanes, pays attention to FTS quoting and trigger correctness. Approves or files fix beads.

Wall-clock estimate: five to ten minutes if no rework is needed, up to fifteen with one round of fix beads.

## What to watch

- **The decomposition mail.** First mail back from the mayor is "here is what I created." If the lanes look wrong, fix it via mail before specialists start. Cheap to redo.
- **Whether DBA lands a real FTS5 setup or fakes it with `LIKE`.** Both will look correct on small data. The reviewer should catch the cheat.
- **Reviewer's posture on input handling.** Either notices the FTS5 quoting issue and files a fix bead, or flags it and lets it ship.
- **Whether the cooldown ingest keeps populating the FTS index.** This is the trigger-correctness question. After the first ship, wait one cooldown cycle, search for a brand-new item, see if it appears.

Open the overview in another terminal:

```bash
watch -n 3 bash bin/overview.sh
```

## What actually happened in the test run

The mayor decomposed into the four predicted beads at 19:38 to 19:39 UTC, single batch, pre-routed in one shot.

- `rr-utf` `[rss-reader/dba]` "DBA: items_fts FTS5 virtual table + sync triggers"
- `rr-1be` `[rss-reader/backend]` "Backend: /search route with FTS5 MATCH + safe input handling"
- `rr-vk8` `[rss-reader/frontend]` "Frontend: search input in index header + results rendering"
- `rr-vox` `[rss-reader/reviewer]` "Review: FTS5 search end-to-end"

DBA spawned first. While building the FTS5 table over `items(title, description)`, the agent noticed the `description` column did not exist on `items`. The bead description had asked for FTS over title and description, so the column was implied but not written into the schema migration plan. The DBA agent added the column itself with an idempotent `ALTER` ("Also added items.description column ... since the bead's SQL referenced it but the column did not exist"). Closed the bead with a clean note.

Backend spawned next, shipped the `/search` route with safe input handling (try the query as raw FTS5 first, fall back to a sanitized phrase if `MATCH` throws). Closed the bead.

Frontend spawned, added the search input to the header, picked a plain GET form over HTMX live search (the prompt left it open, the agents went with simpler), and made sure the reflected query in the input was HTML-escaped. Closed the bead.

Then something interesting happened. At 19:54, fifteen minutes into the chain, **the mayor created a fifth bead unprompted**:

- `rr-gq4` `[rss-reader/backend]` "Backend: populate items.description from feed during ingest"

The DBA had added the `description` column, but the existing ingest code was not populating it. So new rows would have NULL descriptions and FTS5 over `description` would index empty strings. The mayor noticed the gap (or the backend surfaced it during the `/search` work) and inserted a backend bead to fix ingest. No human in the loop. The orchestrator caught and patched a chain hole during execution.

Backend spawned again, extended the ingest to extract `<description>` from the feed (with HTML-strip and entity-decode passes), capped at 2000 chars, verified that a fresh ingest produced 30/30 non-empty descriptions and that searching for description-only tokens worked. Closed the bead.

Then the reviewer spawned. Read everything in scope. Booted an isolated test instance on port 3001 with its own fresh ingest cycle to verify the schema and triggers cleanly, separate from the live :3000 app. Ran the hostile-input set: `"`, `*`, `(`, `)`, `AND/OR/NOT/NEAR`, a 1KB string, unicode. All returned 200. Verified items=30 / items_fts=30 with 30 non-empty descriptions, that description-only searches worked, that triggers kept counts aligned across insert/update/delete. Approved the lanes.

Found two things and filed fix beads:

- `rr-etw` `[rss-reader/backend]` "Preserve non-empty syntax-only search queries". A UX bug where typing `(broken` cleared the input on fallback, so the user lost their typing.
- `rr-brg` `[rss-reader/backend]` "Document /search sanitization in route file". A doc-only finding, asking for an explanatory comment at the route call site.

The reviewer also tried to mail the backend specialist directly with the findings. There was no live backend session at that point (the previous polecat had drained), so the mail send returned an error. The reviewer's prompt has a fallback for exactly this case: **when no live session exists, write the observation as a bead note instead of a mail.** The note rides with the bead permanently. The reviewer did exactly that, then mailed the mayor with the list of fix beads.

Mayor read the findings mail, slung both fix beads to backend, spawned a fresh review bead `rr-9f3` depending on the fixes, slung it to the reviewer. Backend respawned, shipped both fixes (`b1babaa` for `rr-etw`, `7410d6e` for `rr-brg`). Reviewer respawned, verified, approved.

Final tally:

- **7 work beads**: 4 predicted + 1 mid-flight insertion + 2 reviewer findings.
- **All 4 specialist lanes** engaged: dba, backend (three times), frontend, reviewer (twice).
- **27 minutes wall clock** from handoff to last commit.
- **The 8am `rss-digest` cron fired during the search work and produced its commit cleanly.** Orders kept ticking in the background.

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

All three should return 200. The first returns matching items. The empty query falls through to the recent-items list. The hostile `(broken` query is sanitized and returns matching items (or none if nothing matches the token), without 500.

Browser eyeball: type into the input on `/`, hit return, results swap.

## Sidebar: mail to polecats does not queue

This is worth surfacing because it caught us during the test run. If you mail a polecat lane that has no live session, the send fails (no inbox to deliver to until a session spawns). The reviewer's correct workaround is to put the observation on the bead description as a note: `bd note add <bead-id> "<text>"`. The note rides with the bead; the next session that picks it up sees the context.

Pattern, in two lines:

- **Mail named/always-on agents** (mayor, human). They have inboxes that hold messages.
- **Put context on beads for polecats** (backend, dba, frontend, reviewer). Bead notes outlast mail and carry the context to whoever spawns next.

## Shape check

- One feature shipped: full-text search with FTS5, working `/search` route, search input on `/`.
- All four specialists engaged in this single feature.
- Seven closed work beads from the chain, plus the bookkeeping convoys and molecules.
- Hostile input curls all return 200, not 500.
- The cooldown ingest still adds rows, and they are searchable shortly after.

## When your agent goes off-script

- **The agents pick `LIKE` instead of FTS5.** That is the scenario the reviewer is supposed to catch. If it does not, send a follow-up to the mayor: "FTS5 was specified; the current implementation uses `LIKE`. Please refile and re-route." Mayor will sling a fresh DBA bead.
- **Backend's `/search` 500s on parentheses or `OR`.** The reviewer is supposed to catch this too. If you find it after the chain settled, file a fix bead by hand: `cd rss-reader && bd create -t "Backend: sanitize /search input" -d "..." --json` and ask the mayor to sling it.
- **The mayor decomposes into fewer than four beads (e.g. skips reviewer).** The Part 4 prompt makes the review bead mandatory. If the mayor forgets, reply pointing at the prompt's review-bead requirement.
- **Cooldown ingest stops mid-chain.** The trigger-correctness question. Wait one cycle (~2 min) after the chain settles, ingest a couple of new items, search for them. If they do not appear, the FTS5 triggers are wrong; file a fix bead.
- **The chain stalls before the review bead.** Most often the last work bead's polecat drained but the review bead's `gc.routed_to` did not stick. Re-sling: `gc sling rss-reader/reviewer <review-bead-id> --on mol-do-work`.

## Go off-script: alternative capstone features

If you would rather build something else, two one-paragraph prompts you can swap into the handoff above. Either one is a valid Part 6.

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
3. **Communication.** Mayor's reply to your handoff. Reviewer's mail to the mayor with findings. The reviewer's reach for direct mail to backend, finding no live session, falling back to a bead note.
4. **Beads.** Seven created (four predicted plus one mid-flight insertion plus two reviewer findings), three dependency edges in the original chain, all closed.
5. **Sling.** Six `--on mol-do-work` calls (four upfront plus two for the fix beads). Reconciler did the rest.
6. **Formulas.** `mol-do-work` driving each polecat's lifecycle. Your custom `mol-rss-digest` from Part 5 firing in the background while the search work shipped.
7. **Orders.** Three of them ticking through the run: `rss-fetch` every two minutes refreshing items into the FTS index (triggers kept it in sync), `rss-vacuum` at 4am, `rss-digest` at 8am which fired and committed during the search work.

## Where to go next

Practical follow-ups, ordered roughly smallest to largest. Pick whatever matches your itch.

- **Pagination on the index.** `/` currently shows 30 items hardcoded. Add a "show more" button (HTMX-shaped: `hx-get="/?page=2"` swapping in the next batch) or a permalink-friendly `?page=N`.
- **Show only items from a particular domain.** Either the `/source/:domain` page from earlier in this chapter, or a query param filter on `/`.
- **Mark/unmark read.** A `read_at` column on items, a small star or check toggle on each row, a "show only unread" filter. The Part 5 `rss-vacuum` cron can be retargeted to prune **read** items older than N days, which makes the cleanup user-driven instead of operational.
- **Favorite/unfavorite articles with a `/favorites` page.** Same shape as mark-read but kept indefinitely. Saved state survives the vacuum cron.
- **Replace the hardcoded HN feed with multiple feeds.** A `feeds` table, an admin route to add and remove feeds, and an ingest loop that iterates. A real four-lane chain: DBA migration, backend ingest update, frontend admin page, reviewer pass.
- **Move the digest out of Gas City and into a small script that calls Anthropic directly.** Per Part 5's "How would this look in a deployed app?" section. Drops GC out of production for this app entirely, which is the right shape if you ever ship it.
- **Auth and user-specific feeds.** Each user has their own feeds, their own read state, their own favorites. The biggest single jump in scope: a user model, sessions, permission checks on every route. A meaty multi-chapter-shaped chain on its own.
- **Tags or categories.** Either user-applied or auto-classified by an LLM at ingest time. The latter is a small "AI feature in production" use case: one cheap API call per item during the cooldown ingest, store the labels, filter by them.
- **Saved-search-as-feed.** Take any FTS5 query you care about (`rust`, `k8s`, `webgpu`) and turn it into a permalinked view. `/q/rust` shows the latest items matching the query. Trivial backend, free reuse of Part 6's search work.
- **Email or Slack digest delivery.** The daily digest lands in your inbox or a channel, not just the website. A small webhook script triggered after the digest row is written.
- **A weekly or monthly digest** alongside the daily one, with a different prompt ("look at the last 7 days, find the themes that recurred"). Same custom-formula shape as the daily.
- **Stats page.** Top sources by week, items per day, your read-rate, your favorite-rate by source. SQL aggregations rendered in HTML.
- **Dark mode and a responsive layout.** Frontend lane only, but it makes the app feel like something you would actually use.
- **Export your digests as their own RSS feed.** `/digest.rss` serves the last N days of digest rows in RSS 2.0 format. Consume your own AI summaries from another reader. Pleasingly recursive.

And the bigger swings, the ones that go beyond this app:

- **Build a second app with the same crew.** The mayor + backend + dba + frontend + reviewer roster ports to anything: a personal kanban, a habit tracker, a side-project journal. The configs you wrote here are the durable artifacts; the rss-reader code was a demonstration.
- **Replace one specialist with a Codex agent and watch the styles diverge.** Or add a sixth specialist (a tester, a docs-writer, a PR-reviewer) and see how the chain reshapes itself.
- **Use Gas City for non-coding work.** A weekly research roundup, a financial reconciliation, an ops runbook executor. The orchestration shape generalizes; "agent in your editor" was just the on-ramp.

The world is your oyster. The point of these seven chapters was not to build an RSS reader. It was to give you a working mental model for "describe a feature, watch the system ship it." You have that now. The next thing you build with Gas City does not need a tutorial.
