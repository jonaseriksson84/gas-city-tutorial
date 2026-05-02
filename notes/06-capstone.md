# Part 6: Capstone, ship-it autonomously

Source notes for the capstone chapter. The chapter is the synthesis chapter: all seven primitives are live, the reader hands the system one feature prompt and watches the chain run.

## Concept payload (from the locked design)

Synthesis. No new primitive introduced. Hybrid recommended-prompt + go-off-script. The chapter embeds the actual transcript captured during this test run.

## The feature: search with SQLite FTS5

Why search and not the other candidates:

- **DBA stretch.** FTS5 virtual table plus content-sync triggers is a real schema migration. Bigger lift than the simple `domain` column from Part 4.
- **Visible payoff.** Reader types into a box, results filter live. Feels nothing like "I clicked refresh."
- **Reviewer surface.** FTS5 `MATCH` has its own quoting rules; raw user input can throw on parentheses, `OR`, `NOT`. A careful reviewer catches this.
- **Whole-chain exercise.** dba → backend → frontend → reviewer. All four polecats engaged in one delivery.

## The handoff (verbatim)

```bash
gc handoff --target mayor "Add search to rss-reader" 'I want full-text search over the indexed items. The index page should grow a small search input in the header. Typing in it should query item titles (and descriptions if cheap) and show matches in the same HN-style list. Live results via HTMX with sensible debounce are nice but not required; a plain GET form is fine if the agents prefer simpler. Use SQLite FTS5 for the search index, populate it from the existing items table, and keep it in sync as new items get ingested. Empty query should show the recent items as today. The reviewer should pay attention to user input handling around the FTS MATCH operator and to whether the index stays in sync after the next cooldown ingest. Decompose, pre-route the chain, and let it run hands-off.'
```

One paragraph, one prompt, no nudges. Same shape as the `/digest` handoff in Part 5 with a real DBA migration on the front.

## Predicted decomposition (going in)

Based on the mayor's strict-delegator prompt and what we saw on the `/digest` chain:

- `rss-reader/dba` bead 1: FTS5 virtual table over `items(title, description)`, content-table mode pointing at `items`, three triggers (insert/update/delete), backfill via `INSERT INTO items_fts(items_fts) VALUES('rebuild')` or equivalent.
- `rss-reader/backend` bead 2 (depends on bead 1): `GET /search?q=...` route running an FTS5 `MATCH` query, returning the same item list shape the index uses. Empty `q` falls through to recent items.
- `rss-reader/frontend` bead 3 (depends on bead 2): search input in the header, HTMX `hx-get="/search"` with debounce, target an items div. Plain GET form fallback if HTMX is off.
- `rss-reader/reviewer` bead 4 (depends on bead 3): runs the app, reviews lanes, pays special attention to FTS quoting and trigger correctness. Approves or files fix beads.

Wall clock estimate: 5 to 10 minutes if no rework, up to 15 with one fix-bead round.

## What to watch during the run

- **The decomposition mail.** First mail the mayor sends after handoff is the "here's what I created" reply. If the lanes look wrong, fix via mail before specialists start. Cheap to redo.
- **Whether dba lands a real FTS5 setup or fakes it with `LIKE`.** Both will look correct on a small dataset. Reviewer should catch the cheat.
- **Reviewer posture on input handling.** Either notices the FTS5 quoting issue and files a fix bead, or flags it and lets it ship.
- **Whether cooldown ingest keeps populating the FTS index.** Trigger correctness. Wait one cooldown cycle after first ship, search for a brand-new item, see if it appears.
- **Permission prompts.** Notification hook is gone (Part 5). If a polecat blocks on a permission prompt, nothing alerts. Watch the overview tile.

## What actually happened

### Decomposition the mayor chose

Four beads upfront, exactly as predicted. Mayor created them at 19:38 to 19:39Z, single batch:

- `rr-utf` `[rss-reader/dba]` "DBA: items_fts FTS5 virtual table + sync triggers"
- `rr-1be` `[rss-reader/backend]` "Backend: /search route with FTS5 MATCH + safe input handling" (depends on rr-utf)
- `rr-vk8` `[rss-reader/frontend]` "Frontend: search input in index header + results rendering" (depends on rr-1be)
- `rr-vox` `[rss-reader/reviewer]` "Review: FTS5 search end-to-end" (depends on rr-vk8)

Pre-routed in one shot with `--on mol-do-work`. The reconciler walked the chain hands-off. Strong signal that the strict-delegator prompt and the `gc.routed_to` auto-dispatch behavior compose well at this scale.

### The chain grew mid-flight, the system handled it

At 19:54 (~15 minutes in, after dba shipped) the mayor created a fifth bead unprompted:

- `rr-gq4` `[rss-reader/backend]` "Backend: populate items.description from feed during ingest"

Origin: the dba bead's close_reason flagged that "Also added items.description column (idempotent ALTER) since the bead's SQL referenced it but the column did not exist." The new column existed but ingest was not populating it, so FTS5 over `description` would index empty strings. Mayor noticed the gap (or backend told it during /search work) and slung an additional bead to fix ingest. No human input.

This is a chapter-worthy moment: the orchestrator caught and patched a chain hole during execution. The "predicted four" became "actual five" on its own.

### Reviewer pass

`rr-vox` close_reason is unusually thorough; worth quoting in the chapter:

> Reviewed end-to-end. Passed: recent-list fallback for empty q matches / exactly; hostile queries (`"`, `*`, `(`, `)`, `AND/OR/NOT/NEAR`, 1KB string, unicode) returned 200 with no SQL/500 failures; reflected q is HTML-escaped; fresh isolated ingest on port 3001 produced items=30/items_fts=30 with 30 non-empty descriptions; description-only search for `Comments` worked; repeat ingest kept counts aligned; trigger lifecycle check on a copied db kept insert/update/delete counts in sync.

Findings:

- `rr-etw` "Preserve non-empty syntax-only search queries" (UX: a query like `(broken` was being cleared from the input on fallback, so the user lost their typing).
- `rr-brg` "Document /search sanitization in route file" (doc-only: explanatory comment requested at the route call site).

The reviewer ran an isolated test instance on port 3001 with its own ingest cycle to verify the schema and triggers cleanly, then ran the hostile-input set against the live `:3000`. That isolation move (don't trust the running app's data, build your own) is a real review pattern worth highlighting in the chapter.

### A small workflow scar to note in the chapter

Reviewer close_reason ends with: "Mailed mayor via rt-wisp-4wi. Direct mail to rss-reader/backend failed because no live session existed, so reviewer notes were added to rr-etw and rr-brg instead."

Mail to a polecat with no live session does not queue (no inbox to deliver to until a session spawns); it errors. The reviewer fell back to writing the notes into the bead descriptions where the next backend session would see them on `mol-do-work` pickup. This is a real pattern: when the recipient is a polecat (ephemeral, on-demand), put the context on the bead, not in mail. Mail is for named/always-on like the mayor or the human. Worth a chapter sidebar.

### Fix-bead round

Both fixes shipped at 20:05Z and the route still returns 200 on the hostile-input set. The reviewer did not need a second pass; the original review's acceptance criteria covered the fixes by construction.

### Wall-clock timing

Handoff at 19:38, last fix commit at 20:05. About 27 minutes wall clock for a feature that involved a real schema migration, a working FTS5 setup with content-table triggers, a route with safe input handling, an HTMX-able search form, an end-to-end review, and three fix beads.

### Final bead inventory

- 4 predicted + 1 mid-chain insertion + 2 reviewer findings = **7 work beads**, all closed.
- All four polecat lanes engaged (dba, backend, frontend, reviewer).
- Plus the usual `sling-*` convoy beads and `mol-do-work` molecule scaffolding the runtime spawns automatically. Bookkeeping noise, not bugs (Part 5 sidebar already covered this).

## Verification

```bash
curl -s 'http://localhost:3000/search?q=kubernetes' | head -40
curl -s 'http://localhost:3000/search?q='            # empty -> recent items
curl -s 'http://localhost:3000/search?q=(broken'     # quoting torture; should not 500
```

All three returned `200`. The `kubernetes` query returned two real items (`K3k: Kubernetes in Kubernetes` and `Kubereboot/Kured`); empty `q` matched the index page; the `(broken` query returned 200 with the original input preserved in the search box (the rr-etw fix).

Search HTML shape (excerpt):

```html
<h1>rss-reader <a href="/digest" class="meta">Daily digest</a>
  <form class="search" action="/search" method="get" role="search">
    <input type="text" name="q" value="kubernetes" placeholder="search…" aria-label="Search">
  </form>
</h1>
<ol>
  <li><a href="https://github.com/rancher/k3k">K3k: Kubernetes in Kubernetes</a> ...</li>
  <li><a href="https://github.com/kubereboot/kured">Kubereboot/Kured: Kubernetes Reboot Daemon</a> ...</li>
</ol>
```

Plain GET form (the agent went with this rather than HTMX live search; defensible call given the prompt left it open). Submitting the form reloads `/search?q=...`. The HTMX route is open as a future enhancement, not a regression.

## Sidebar: go off-script alternatives

Two one-paragraph prompts the reader can swap in if they want a different capstone:

**Per-source filter.**

```
gc handoff --target mayor "Per-source filter" 'Add a /source/:domain page that lists items from one host. Link the source label in each row of / to its filter page. Add a small "top sources" list somewhere on / showing the five most-linked domains. No schema change should be needed; the domain column was added in Part 4.'
```

Backend and frontend lanes, dba untouched, reviewer pass.

**Saved items.**

```
gc handoff --target mayor "Saved items" 'Let me save items. Each row on / gets a small star toggle that flips saved on or off, persisted in SQLite. Add a /saved page that lists saved items in the same HN-style format. Saved state must survive the nightly rss-vacuum cron.'
```

All four lanes including dba (smaller migration than search).

Either is a valid Part 6. The chapter recommends search; these are listed because the reader's instinct may differ.

## Synthesis recap (chapter close, draft)

The seven primitives in the order they surfaced in this single delivery:

1. **City and rigs.** The workspace and the rss-reader rig where the search work landed.
2. **Agents and sessions.** Four polecats spawning into existence on demand off the bead chain. None pre-running; each one materialized when its bead became ready.
3. **Communication.** Mayor's reply to your handoff. The reviewer's mail to the mayor with findings. The reviewer's reach for direct mail to backend, finding no live session, and writing notes onto the bead instead.
4. **Beads.** Seven created (four predicted + one mid-flight + two reviewer findings), three dependency edges in the original chain, all closed.
5. **Sling.** Four `--on mol-do-work` calls upfront, two more for the fix beads. Reconciler did the rest.
6. **Formulas.** `mol-do-work` driving each polecat's lifecycle. `mol-rss-digest` firing in the background while the search work shipped.
7. **Orders.** Three of them still ticking through the run: `rss-fetch` every two minutes refreshing items into the FTS index (triggers kept it in sync), `rss-vacuum` at 4am, `rss-digest` at 8am which fired and committed during the search work.

Close beat: this is what "ship it autonomously" actually looks like. One prompt. The orchestrator decomposed, dispatched, caught a chain hole mid-flight and patched it, ran a substantive review, accepted findings, shipped fixes. No human nudges. The system did the rest.

## Status at end of Part 6

- Search shipped end to end. FTS5 virtual table over `items(title, description)` with content-table triggers, `/search` route with safe input handling, header search form rendered on `/`, all driven by one `gc handoff` to the mayor.
- All four polecat lanes engaged in a single delivery for the first time in the tutorial.
- Reviewer ran a substantive end-to-end pass with isolated test ingest. Two fix beads filed and shipped.
- Mid-chain bead insertion (`rr-gq4`) by the mayor surfaced a real ingest gap and patched it without human input.
- Three orders still ticking through the run: `rss-fetch` (cooldown 2m), `rss-vacuum` (cron 0 4 * * *), `rss-digest` (cron 0 8 * * *). The 8am `rss-digest` cron fired during the search-feature work and produced its commit cleanly.
- Total: 7 search beads + 1 background digest molecule, all the search ones closed.

## Pending after Part 6

- Alert primitive for stuck-on-permission polecats (still open from Part 5). Not blocking publish; a side note for an "open issues" appendix.
- One open background bead (`rr-9r2` mol-rss-digest molecule) from the morning's 8am digest, same `{{issue}}` step-vs-molecule gotcha noted in Part 5. Cosmetic.
- HTMX live-search not built; the agents picked plain GET form. Real off-script extension for a reader who wants more.
- Older items still have NULL descriptions (`rr-gq4` scoped backfill out per its close_reason). FTS title-only matches still work for old rows; description matches only work for items ingested after `rr-gq4` shipped. Worth a chapter footnote.

## Lessons by category

### What the synthesis chapter actually shows

- A single prompt produces a multi-specialist chain that ships a real feature with a real schema migration, a working FTS5 index, safe input handling, and a meaningful review pass.
- The chain can grow during execution (mid-flight bead insertion) without losing coherence. The orchestrator's prompt (strict-delegator + mandatory review bead) plus `gc.routed_to` auto-dispatch is enough.
- "Hands-off after handoff" is the right framing for the chapter; the reader should not feel any need to nudge.

### Mail to polecats does not queue

If you mail a polecat lane that has no live session, the send fails (no inbox until a session spawns). The reviewer's workaround was to put the notes on the bead description instead. **Pattern:** mail named/always-on agents (mayor, human); put context on beads for polecats. Worth a Part 6 sidebar.

### Reviewer self-isolation is a real practice to call out

Reviewer ran an isolated test instance on port 3001 with its own fresh ingest to verify schema + triggers, before testing the live :3000 app. Don't-trust-the-running-data is exactly the kind of practice that makes a reviewer worth its provider tokens.

### When the prediction is mostly right, that itself is the point

The mayor's decomposition matched my four-bead prediction. That is not because I'm clever; it is because the strict-delegator prompt teaches the canonical multi-specialist shape and the reviewer-bead requirement. By Part 6 the reader should be able to predict their own decomposition for similar features. The chapter should make this skill explicit.
