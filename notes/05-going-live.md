# Notes: Part 5, Going live

Raw notes from the test run of Part 5. Source material for `tutorials/05-going-live.md` later.

## Concept payload (from the locked design)

- The `order` primitive: cooldown and cron triggers.
- First custom formula authoring (deferred from Part 4).
- Pedagogy level: reader-writes-one-config-from-scratch.

## Pre-chapter recovery: macOS case-insensitive path collision

Part 5 began with the city refusing to start cleanly after an overnight laptop sleep. The cascade and the durable lesson both belong in the chapter as a sidebar.

### The symptom

After `gc stop` then `gc start`:

```
gc start: city failed to start: init: beads lifecycle: bead store: invalid managed dolt runtime state;
keeping registration for 'rss-tutorial' so the supervisor can retry automatically
```

Supervisor logs cycled forever:

```
gc supervisor: city 'rss-tutorial': init: beads lifecycle: bead store: invalid managed dolt runtime state (skipping)
gc supervisor: city 'rss-tutorial': init failure #4, next retry in 1m20s
```

### The root cause

The directory on disk is `/Users/jonaseriksson/Code/gas-city-tutorial/...` (capital `C`). The user's shell history has been typing `cd ~/code/...` (lowercase) for weeks. macOS's case-insensitive filesystem accepts both transparently.

Gas City's path identity is **string-canonical, not inode-canonical**. `internal/pathutil/pathutil.go:70` `SamePath` does:

1. `filepath.Abs`
2. `filepath.Clean`
3. `filepath.EvalSymlinks` (no-op when there is no symlink to resolve)
4. macOS `/private/{tmp,var}` collapse

It does **not** case-fold. On HFS+/APFS without case-sensitivity enabled, `/Users/.../Code/...` and `/Users/.../code/...` point to the same files but are treated as different paths by every comparison.

Sequence of damage:

1. An earlier session started the supervisor from the lowercase path. Dolt's runtime state files (`dolt-state.json`, `dolt-provider-state.json`, `dolt-config.yaml`) were written with `data_dir: /Users/.../code/...`.
2. Today's `gc start` ran from `~/Code/...` (capital). Registration in `~/.gc/cities.toml` was rewritten to capital `Code`.
3. The supervisor's bead-store init reads the dolt state file, then calls `validDoltRuntimeState(state, cityPath)` which does `samePath(state.DataDir, filepath.Join(cityPath, ".beads", "dolt"))`. Lowercase vs capital. Returns false.
4. The repair path (`repairedManagedDoltRuntimeState` at `cmd/gc/dolt_port_selection.go:80`) also uses `samePath` for the same comparison. Also fails.
5. Init fails. Supervisor retries. Each retry leaves the previous dolt sql-server running but unowned, holding the port and the dolt write lock.
6. Eventually we had two `dolt sql-server` processes for the same on-disk data directory plus the launchd-restarted supervisor's fresh attempts, with `database "__gc_probe" is locked by another dolt process` flooding `dolt.log`.

### The fix

Kill the orphan lowercase-path dolt. The supervisor's automatic retry loop then succeeds: a fresh dolt spawns reading the capital-path config, writes new state files with the capital `data_dir`, and `validDoltRuntimeState` passes. The reconciler wakes mayor + dog pool, city reports healthy.

Defensive cleanup of `dolt-state.json`, `dolt-provider-state.json`, `dolt.pid`, `dolt.lock` was performed but was probably not strictly needed; the supervisor's repair path would have rebuilt them once the lock fight ended.

### Going forward

Pick one casing and stick with it. The on-disk casing is what `ls -la ~/` shows for the `Code` directory. Type that exact case in shell, scripts, tmux windows, anything that ends up calling `gc`. A shell alias eliminates the footgun:

```bash
alias gctut='cd /Users/jonaseriksson/Code/gas-city-tutorial/city'
```

### Follow-up to consider, not file yet

No GH issue tracks this case-insensitive path collision. Closest neighbours:
- GH#1234 (closed) added the `repairedManagedDoltRuntimeState` recovery path for stale/missing state files. The fix is in our build but does not save us because it uses the same `samePath` for its own validation.
- GH#645 (closed) added symlink-aware normalization for rig context. Symlinks only, not case aliases.
- GH#1373 (open) is about `gc rig add` skipping canonicalization; adjacent but different.

Suggested fix shape if we file later: in `pathutil.NormalizePathForCompare`, on Darwin, query the volume's case-sensitivity (e.g. `pathconf(_PC_CASE_SENSITIVE)` or `getattrlist` with `ATTR_VOL_CAPABILITIES` checking `VOL_CAP_FMT_CASE_SENSITIVE`). If the volume is case-insensitive, lowercase the path before comparison. Linux ext4/btrfs are typically case-sensitive so the existing behaviour is correct there.

User's directive 2026-05-01: do not file the issue right now; keep this in notes and revisit after the test run completes.

### For the chapter sidebar

Title: "macOS will let you `cd` into the same place two ways. Gas City will not."

Beats:
- The on-disk `Code/` vs the lowercase `code/` you typed.
- What goes wrong (one paragraph: two dolt processes, write-lock contention, init refuses to clear).
- The check (`ls -la ~/` to see real casing) and the fix (kill orphan dolt, alias for the canonical path).
- The deeper lesson: dev-tool path identity is a string, not an inode. Be consistent.

## Chapter shape (planned, not yet executed)

1. Bare `exec` order for ingest, cooldown trigger. Reader writes `city/orders/rss-fetch.toml` from scratch. Verifies via `gc order list`, `gc order check`, watching items refresh on the page.
2. Cron variant: convert or add a second order on a wall-clock schedule. Teaches the difference between cooldown ("N since last completion") and cron ("at :00 every hour regardless").
3. A second order that genuinely needs an agent, dispatched via a custom formula. Candidate: daily digest (pick top 10 from last 24h, summarise into one paragraph, write to a file the page renders). This is where the deferred custom-formula authoring from Part 4 lives.

## Notification hook from Part 4 was the wrong primitive

The hook we wired in Part 4 (mail `human` with `--notify` on every Claude Code `Notification` event) fires on both permission prompts and plain idle (60s+ no input). In practice that flooded the human inbox with "needs attention" mails from the mayor (which is `mode = "always"` and idle by design), the dog pool (which idles between work), and any backend polecat that paused mid-turn. By the time the human looked, the inbox was a wall of `Permission prompt or idle on session X` mails most of which were just "X is breathing." The signal-to-noise was bad enough that the user wanted out.

A `matcher: "permission_prompt"` filter would have suppressed the idle case (the `Notification` event delivers `notification_type` of `"permission_prompt"` or `"idle_prompt"` and Claude Code routes by `matcher` value at config time). But the user's read was that mail is the wrong push channel even with the filter: "It'd be good if we are alerted somehow, but this is not it."

**What we did 2026-05-01:** removed the entire `Notification` block from `city/.gc/settings.json`. No hook now. Permission-prompt-stuck polecats are again invisible to gc events, same gap as before Part 4. The Part 4 chapter writeup will need to reflect this rethink rather than presenting the original mail-the-human hook as the answer.

**Open design question for the chapter.** What is the right alert primitive for "a polecat is blocked on a permission prompt"? Some shapes worth considering, none implemented yet:

- macOS native notification via `osascript -e 'display notification ...'`. System tray, no inbox pollution, visible regardless of which terminal window is foregrounded. Mac-only, but our audience is Mac-heavy.
- Terminal-bell flash plus colour-coded tile in `bin/overview.sh`. Passive, only useful if the watch loop is actually open. Free.
- A separate `human` inbox with stricter filtering: only the very first stuck-prompt mail in a given session, no repeats. Reduces noise but does not eliminate it.
- Webhook to whatever the user already gets paged on (Slack, Pushover, etc.). Heavy, but composable.

Per user directive 2026-05-01: pick a better design later. For now, no notification.

The HUMAN INBOX tile in `bin/overview.sh` will still surface anything mailed to `human` in the future, but with the hook removed nothing is currently writing to it from the Notification path. Existing junk mail from earlier hook fires can be dismissed with `gc mail mark-read <id>` or the inbox can be left alone (it is purely cosmetic).

**Lesson for the chapter narrative:** Part 4's hook was a real attempt at a real problem, but it shipped before we had stress-tested it on a long-running idle mayor and a busy dog pool. The honest version of Part 4 should walk the reader through the noisy outcome and end with "we removed the hook; this is still an open problem." Better than pretending the first design worked.

## Pre-chapter setup completed

Backend polecat added `rss-reader/src/cli/ingest.ts` (commit `a811c1e`) plus a follow-up DB-open error-handling fix (`ff4868c rr-269`). The CLI runs as `bun run src/cli/ingest.ts` from inside the rig and prints one line of `inserted=N ignored=M`. This is what the order's `exec` invokes.

## Beat 1: cooldown order, exec trigger

The order file the reader writes from scratch:

```toml
# city/orders/rss-fetch.toml
[order]
description = "Fetch HN RSS feed every two minutes and ingest new items"
trigger = "cooldown"
interval = "2m"
exec = "cd /Users/jonaseriksson/Code/gas-city-tutorial/rss-reader && bun run src/cli/ingest.ts"
timeout = "30s"
```

Verification commands:

```bash
gc order list                # should show rss-fetch at the bottom
gc order check               # rss-fetch shows "due: yes, never run" right after registration
gc order history rss-fetch   # populates after the first auto-fire
sqlite3 .../rss-reader.db "SELECT count(*), max(published_at) FROM items;"
```

After registration plus the first supervisor tick, `rss-fetch` fires immediately, then every ~2m + previous duration. Two consecutive history entries observed during the test run:

```
ORDER       BEAD     EXECUTED
rss-fetch   rt-dpr   2026-05-01T21:13:28Z
rss-fetch   rt-1af   2026-05-01T21:11:22Z
```

DB count grew from ~30 (after the first manual `gc order run rss-fetch`) to 127 over a few cycles. Page at http://localhost:3000/ updates on browser refresh.

### Path-casing recovery loop bit us through `bin/overview.sh`

`bin/overview.sh` (added in Part 3) hardcoded `CITY=/Users/jonaseriksson/code/...` (lowercase). Under `watch -n 3`, every 3 seconds it ran `gc --city <lowercase> session list`, which on this build's slow-path triggered an "ensure dolt" recovery via `gc dolt-state recover-managed --city <lowercase>`. The recover script tried to start a second dolt sql-server with a lowercase config, lost the database lock to the supervisor's correctly-cased dolt, exited, and reran 3 seconds later. Config reloads of the in-memory supervisor state failed with "invalid managed dolt runtime state (keeping old config)" because each retry rewrote `dolt-provider-state.json` with lowercase `data_dir` that did not match the registry's capital-cased `cityPath` under `samePath`. Net effect: built-in orders (loaded at startup before the storm) kept firing, but `rss-fetch` (added after startup, only visible via reload) never got dispatched.

Two compounding factors:
- Two `watch -n 3` processes were running because of an earlier session that did not cleanly exit. Storm doubled.
- `gc session list` is one of the documented v1.0.0 slow paths (HANDOVER, GH#1177).

Fix:
- Edited `bin/overview.sh` lines 8-9 to capital `Code`.
- Killed both watch processes; started a single one from the canonical-path shell.
- Recovery loop stopped within seconds; subsequent orders fired cleanly.

This is a real chapter sidebar in two places: Part 3 (where overview.sh was authored — show the right casing the first time) and Part 5 (where the consequence surfaced).

### What worked, structurally

- One TOML file in `city/orders/` was the entire delta from "no schedule" to "running every 2m." That is the right level of friction for a scheduled-job primitive.
- `gc order list` and `gc order check` were the only diagnostics needed to confirm registration and trigger eligibility.
- `gc order history <name>` is the audit log; one bead per fire, persistent.

### Chapter sidebars to write

1. "macOS will let you `cd` into the same place two ways. Gas City will not." (case-insensitive path footgun, full version in pre-chapter section above; Part 3 needs a reciprocal note when authoring `bin/overview.sh`.)
2. "`gc order check` is your dry-run." (Show the table, point at the DUE column and the elapsed/cooldown reasons.)
3. "Cooldown vs cron, in one sentence." (Set up beat 2.)

## Beat 2: cron trigger

A second order, distinct job. The reader writes `city/orders/rss-vacuum.toml` from scratch:

```toml
[order]
description = "Prune items older than 30 days and compact the rss-reader sqlite database nightly"
trigger = "cron"
schedule = "0 4 * * *"
exec = "sqlite3 /Users/jonaseriksson/Code/gas-city-tutorial/rss-reader/rss-reader.db \"DELETE FROM items WHERE published_at < datetime('now', '-30 days'); VACUUM;\""
timeout = "5m"
```

The motivation is the headline of the chapter sidebar: **two scheduling shapes for two job-shapes.**

- `rss-fetch` runs every 2 minutes regardless of when. Cooldown is correct.
- `rss-vacuum` runs at 4am. Cron is correct because cooldown drifts (a 24-hour cooldown started at 9pm fires at 9pm, then 9pm + last-vacuum-duration, etc).

### Why both DELETE and VACUUM, not just VACUUM

An earlier draft of this order ran only `VACUUM;`. That is a real SQLite maintenance command (rewrites the file, reclaims freelist pages from deleted rows), but in this app **nothing deletes rows**, so VACUUM had nothing to compact. The chapter motivation read as "we run a maintenance job" without explaining what was being maintained, which is the worst kind of demo job.

The order now does two things in one shot: delete items older than 30 days, then vacuum to reclaim the space. With cooldown ingest pulling new items every two minutes, the table grows monotonically, so prune-by-age is a real and necessary operation, not a contrived motivation. The DELETE will be a no-op for the first 30 days of the app's life and become non-trivial after that, which is exactly the right curve for "nightly maintenance."

A cleaner variant readers could try as a follow-up: add a "mark as read" feature (a `read_at` column on items, a route that toggles it, a tiny star or check on the index page), then change the order to delete read items older than 30 days. That turns the order into product cleanup, not just operational hygiene. Out of scope for this chapter; flagged as off-script for the curious.

### Reading `gc order check` for cron

Two reasons surface during this beat that read confusingly at first:

- `cron: schedule not matched` — current clock does not match the expression. Fully expected outside the matching window. Source: `internal/orders/triggers.go:117`.
- `cron: already run this minute` — fired during the current minute, dispatcher waiting for the next minute boundary. Source: same file, line 126. This is the per-minute deduplication guard that prevents the same minute from triggering twice if the supervisor ticks faster than 60 seconds.

The chapter should call out both reasons explicitly so readers do not misread "not matched" as a failure.

### Verification without waiting until 4am

Authoring a cron order means you do not get an immediate auto-fire to confirm correctness. Two fast paths:

1. **Manual fire.** `gc order run rss-vacuum`. Confirms the exec is correct. Manual runs do not write history (same gotcha as cooldown manual runs).
2. **Temporary every-minute swap.** Edit the schedule to `* * * * *`, save, wait ~60s, observe one auto-fire, revert to `0 4 * * *`. fsnotify picks up the edit without a restart. This is what we did during the test run. History after the swap:

   ```
   ORDER       BEAD     EXECUTED
   rss-vacuum  rt-h7v   2026-05-02T07:02:02Z
   rss-vacuum  rt-bk2   2026-05-02T07:01:56Z
   ```

   Two consecutive minutes, six seconds apart in wall-clock terms, exactly one fire per minute. Auto-fire confirmed end-to-end.

### Timezone footgun

`time.Now()` in `internal/orders/order_dispatch_loop` (and downstream) returns local time. So `0 4 * * *` is **4am local**, not UTC. On a CEST laptop in May, that is 4am CEST = 02:00 UTC. The chapter sidebar should say this in one sentence so readers do not assume UTC and end up surprised when their job fires at the "wrong" hour.

### What worked, structurally

- Two TOML files, one per scheduling shape, side-by-side in `city/orders/`. Crisp visual contrast.
- fsnotify-driven reload meant the every-minute experiment cost zero restarts.
- Beat 2 ran without any of the case-collision drama of beat 1 because we had already cleaned up `bin/overview.sh` and the recover loop.

## Beat 3: custom formula authoring

The pedagogical graduation moment. Beats 1 and 2 used `exec` orders, the same primitive a crontab gives you. Beat 3 introduces `formula` orders, which dispatch agent-shaped work to a polecat instead of running a shell script. Same trigger system, different action.

### The job

Daily RSS digest at 8am: query the last 24 hours of items, pick the 5 most interesting, write a one-sentence rationale per item, save to `digest.md` in the rig, commit. Real LLM judgment is needed for selection and rationale-writing; that is what justifies a formula over an exec.

### The two files (final shape)

`rss-reader/formulas/mol-rss-digest.toml`:

```toml
description = """
Generate a daily RSS digest. Select the most interesting items from the
last 24 hours and write a one-paragraph summary per item to digest.md
in the rig.
...
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
description = "..."

[[steps]]
id = "drain"
title = "Signal completion"
needs = ["generate-digest"]
description = "..."
```

`rss-reader/orders/rss-digest.toml`:

```toml
[order]
description = "Generate the daily RSS digest at 8am"
formula = "mol-rss-digest"
trigger = "cron"
schedule = "0 8 * * *"
pool = "backend"
```

Plus `formulas_dir = "../rss-reader/formulas"` added to the `[[rigs]]` block in `city/city.toml`.

### What happened during the test run, and why each step landed where it did

**Initial authoring** placed the formula in `city/formulas/mol-rss-digest.toml` and the order in `city/orders/rss-digest.toml`. `gc order list` showed it as a city-scoped order targeting the backend pool. The dispatcher fired correctly and created beads — but in the **city** bead store (`rt-` prefix), not the rig store. The backend agent is `dir = "rss-reader"`-bound, so it operates against the rig store. Beads sat unclaimed; no polecat spawned.

**Root cause**: order scope is determined by file location, not by the `pool` field. Source: `internal/orders/order.go:51`, `Rig` field is `toml:"-"` and "set by the scanning caller, not from TOML." Files under `city/orders/` are city-scoped regardless of where the target agent lives.

**Fix**: move the order to the rig.

```bash
mkdir -p rss-reader/orders
mv city/orders/rss-digest.toml rss-reader/orders/rss-digest.toml
```

After the move `gc order list` showed... nothing different. Still no rig column.

**Second blocker**: a rig only gets *exclusive* formula layers if it has either a pack include or a `formulas_dir` override on the rig in `city.toml`. Without one, every rig's layers are identical to the city's, and `rigExclusiveLayers(layers, cLayers)` returns empty in `scanAllOrders`. The rig orders directory is then never visited. Source: `internal/config/pack.go:820-847` (`ComputeFormulaLayers`) plus `cmd/gc/cmd_order.go:209-225` (`scanAllOrders`).

**Fix**: add to `city/city.toml`:

```toml
[[rigs]]
name = "rss-reader"
formulas_dir = "../rss-reader/formulas"
```

Plus `mkdir -p rss-reader/formulas/`. After this `gc order list` showed the RIG=rss-reader column.

**Third blocker**: order fired, but the formula resolver couldn't find `mol-rss-digest`. Event: `loading formula "mol-rss-digest": formula "mol-rss-digest" not found in search paths`. `gc order history` filled with `wisp-failed` tracking beads. The rig's formula layers (per `ComputeFormulaLayers`) include the city formulas as a base, so this *should* have worked, but the in-memory dispatcher kept its old layer cache.

**Fix**: move the formula from `city/formulas/` to `rss-reader/formulas/` AND `gc supervisor reload` to rebuild the in-memory config. After both, the next fire produced `Config reloaded: 7 agents, 1 rigs` and the order fired with `order.completed` instead of `order.failed`.

Final orientation:
- Formula at `rss-reader/formulas/mol-rss-digest.toml`.
- Order at `rss-reader/orders/rss-digest.toml`.
- `formulas_dir` registered on the rig in `city/city.toml`.
- City `formulas/` and `orders/` dirs hold the *city-scoped* artifacts (`rss-fetch.toml`, `rss-vacuum.toml` — neither references the rig agent).

### What the polecat actually did

Backend polecat spawned, ran the formula's `generate-digest` step: queried items from the last 24h, picked five (Fabien Sanglard SNES internals, a PostScript-in-WASM project, an OSS burnout report, a Noctua engineering blog post, Rancher's k3k), wrote rationale per item, committed `digest.md` (commit `3a05574`). Genuine selection judgment: it favoured technical depth and primary-source research over churn, exactly as the formula instructed.

### Cleanup loose ends from the every-minute swap

When the test-run schedule was set to `* * * * *` so we could see auto-fires inside a minute, the dispatcher created **a new molecule bead every minute**. One molecule got a backend polecat, did the work, committed. The others sat open — backend pool didn't pick them up because by the time it could, more had piled up and the desired-state machinery treated the pool as overloaded. End-state had ~3 orphan molecules (one in city store from the pre-rig-move phase, two in rig store from the rig-scoped phase) plus several leftover step beads.

Cleanup commands run during wrap-up:

```bash
(cd city && bd close rt-i34 rt-i34.1 rt-i34.2 rt-vry rt-vry.1 rt-vry.2)
(cd rss-reader && bd close rr-2j5 rr-2j5.1 rr-2j5.2 rr-1lw)
```

This is a real chapter sidebar: every formula-order fire creates a molecule + tracking bead. Setting an order to `* * * * *` for "let's see it fire fast" is **dangerous** because the storm leaves a litter of opens. For verification, prefer:
- `gc order run <name>` for a manual one-shot fire (no history written, but the exec/formula runs).
- A 5-minute cron (`*/5 * * * *`) for short-loop testing that gives the polecat time to finish before the next fire.

### `{{issue}}` resolves to the step bead, not the parent molecule

The formula's "close the bead when done" step used `bd update {{issue}} --status=closed`. The polecat correctly closed `rr-1lw.1` (the step bead, which is what `{{issue}}` resolves to in step context). The parent molecule `rr-1lw` was never closed. Both step children showed closed, the tracking wisp showed closed, but the molecule itself sat open, blocking pool drain logic.

For the chapter, the cleaner formula authoring is to either:
- Drop the explicit "close the bead" instruction (the runtime closes step beads on completion already), letting the parent molecule auto-close when all children close.
- Or close the parent explicitly via a lookup: `bd close $(bd show {{issue}} --json | jq -r .parent_id)` or similar.

Test run did not retry with a fixed formula. The cleanup ran by hand. Chapter draft will reflect the cleaner authoring.

### What worked, what to keep

- `formula = "..."` + `pool = "backend"` linkage in the order TOML works as soon as the rig-scoping requirements are met.
- Polecats correctly read formula step descriptions and execute them.
- Selection judgment (LLM picks 5 of 30+ items with reasonable rationales) was genuinely strong on the first try with the prompt written as plain markdown bullets in the step description.
- `gc events --since 5m | grep order\.` is the single best diagnostic for order failures; the `order.fired` / `order.failed` / `order.completed` events name the failure mode in plain text.

## Lessons by category, for the chapter narrative

### Path and config-layout traps

1. **macOS case-insensitive filesystem** — pick one casing, use it consistently in shell, scripts, and `gc --city` flags. `bin/overview.sh` hardcoded the wrong casing in Part 3 and that bit us hard during Part 5 setup. `notes/05-going-live.md` "Pre-chapter recovery" section has the full forensics.
2. **Order scope follows file location, not pool field.** City-scoped orders create city beads even if `pool = "backend"` and backend is rig-bound. Move the file to the rig.
3. **Rigs need a `formulas_dir` (or pack include) in `city.toml` to register exclusive formula layers.** Without one, the rig's `orders/` directory is never scanned even if it exists.
4. **Custom formulas referenced by rig-scoped orders must live in the rig's formula dir** in this build, despite `ComputeFormulaLayers` suggesting city formulas inherit. The dispatcher's in-memory layer cache was stricter than the source-code logic implied.
5. **`gc supervisor reload` is sometimes required after moving config files** even though fsnotify generally handles incremental edits. Move and rename operations seem to confuse the layer cache; explicit reload rebuilds it.

### Operational hygiene

6. **`* * * * *` is a dangerous testing schedule for formula orders.** Every minute = one new molecule + tracking bead + potential polecat. Storm leaves orphans. Use `gc order run <name>` for one-shot verification, or `*/5 * * * *` if you need to see auto-fire.
7. **Formula `{{issue}}` resolves to the step bead, not the parent molecule.** Author "close the bead" steps accordingly: prefer letting the runtime close step beads automatically and letting the molecule auto-close when children all close.
8. **Idle pool polecats may not drain immediately.** The reconciler reaps them on its own cadence. `gc session kill <name>` forces it.
9. **Rig and city are separate bead stores.** A bead in `rt-*` (city) is invisible to a rig-scoped agent and vice versa. Cleanup must run in both places.

### Notification-hook rethink

10. **Permission-prompt paging needs a smarter primitive than mail-to-human-on-every-Notification-event.** The Part 4 hook was removed in beat 0 of Part 5 because it flooded the inbox with idle pings. Open design question for the chapter epilogue: macOS native notification, terminal-bell + overview tile, or webhook.

## Beat 4: closing the loop with a `/digest` route

The cron formula was producing a real `digest.md` every morning, but nothing in the running app surfaced it. Closing this loop is what makes "Going live" feel finished. The reader can hit `/digest` in the browser and see what the 8am cron just produced.

This is also the second hands-off feature delivery in this chapter. The first was the formula chain inside the order. This one is a regular feature request to the mayor, run end to end with no manual nudging, on top of orders that are already running.

### The handoff

```bash
gc handoff --target mayor "Add /digest route" 'When digest.md exists at the rig root, expose a GET /digest route that renders the file as HTML. The digest is markdown, render it with a small markdown-to-HTML conversion. If digest.md is missing, show a friendly empty state pointing at the cron schedule. Match the existing index page styling; add a small "Daily digest" link in the header so it is discoverable from /. Decompose, pre-route the chain, and let it run hands-off.'
```

`gc handoff` does not take `--notify` (that flag is on `gc mail send` and `gc mail reply`). Handoff to an always-on mayor delivers mail to a session that is already running, so wake-up is automatic.

### What the mayor did

Decomposed the work into two beads, wired them together, slung both with `--on mol-do-work`:

- `rr-yxo` frontend: `src/views/digest.ts` with `digestPage(bodyHtml)` and `digestEmptyState(scheduleText)` sharing the index page shell, plus a small "Daily digest" link in the index header.
- `rr-3m0` backend: `marked` dependency added, `GET /digest` route in `src/index.ts` that reads `digest.md`, renders if present, returns the empty state otherwise.

Both polecats spawned from `gc.routed_to` metadata when their bead became ready. No mayor babysitting. Two clean commits in the rig:

- `f528dd4 rr-yxo: add digest page template + header link on index`
- `d01b914 rr-3m0: add GET /digest route with markdown rendering`

### Verifying

```bash
curl -s http://localhost:3000/digest | head -25
# returns the rendered digest with HN links, dates, summaries
```

The page is the same Verdana-on-white look as the index. The empty-state branch was visually checked separately by renaming `digest.md` and hitting the route again.

### Why this fit Part 5 and not Part 6

Part 6 was reserved for "ship-it autonomously" with a fresh feature prompt of the reader's choosing. Adding `/digest` there as a recommended path felt like a stretch, because it really belongs to the digest order: it is the visible artifact of "Going live." Pulling it forward into Part 5 makes the chapter feel complete and frees Part 6 to introduce a non-trivial feature (search, source filter, saved items) that exercises the dba and the reviewer in addition to backend and frontend.

### What worked, structurally

- Mayor's pre-route-the-chain prompt worked again on a non-formula request. Two beads, two `gc sling --on mol-do-work` calls, hands-off.
- Two reasonable specialist boundaries fell out naturally: views in frontend, route + dependency in backend.
- The agent picked a real markdown lib (`marked`) instead of writing a brittle inline parser, even though we left it open. That is the right call for a tutorial demo.
- The reviewer was not invoked. Mayor's prompt does not auto-route review for small additive changes; that is fine for the chapter and worth noting in the writeup.

### Chapter sidebar

A tiny one for "your second hands-off delivery feels different": the first time you watched the chain run (Part 3 feature), it was novel. By the end of Part 5, the chain running hands-off should feel routine. The chapter ending should call this out as the moment the system stops feeling magic and starts feeling like infrastructure.

## Sidebar: deploying the digest in production

The digest order works on the reader's laptop because Gas City is running there: the supervisor is up, dolt is serving, the backend polecat can spawn into a Claude Code session, the API key is in the environment. The natural next question is "if I deploy this app to a real host, how do I make the digest happen there?" This sidebar answers it honestly because the answer changes how the reader should think about Gas City's role in their stack.

There are three real options.

**Option A: run Gas City on the server.** Deploy the rig + city + supervisor + dolt + the coding-agent CLI (Claude Code or equivalent) + the API key onto the host. The cron order fires there, the supervisor spawns a backend polecat, the polecat calls the LLM, writes `digest.md` to disk in the rig directory, commits. The deployed app reads from disk. **Cost:** dolt running 24/7, supervisor process, the entire GC stack on a host whose purpose is to serve a Hono app. **Right when:** you actually have other multi-agent work happening on the server (review loops in CI, autonomous bug triage, ongoing feature delivery from production data). Wrong when "I just want the daily digest."

**Option B: run Gas City somewhere else with credentials. Commit the artifact. Deploy from git.** GC runs where the API keys live (your laptop, a worker box, a build server). The agent produces `digest.md`, commits to the rig repo, pushes. Your prod host auto-deploys on push, or pulls on cron. The digest in prod is whatever was last committed. **Cost:** you need GC running somewhere reliable. **Right when:** you want the agent's work to be reviewable, version-controlled, diffable, and "fresh every morning plus or minus a few hours" is good enough.

**Option C: skip Gas City in prod entirely. Call the LLM API directly.** A small script in the rig: `bun run scripts/digest.ts` queries the DB, builds a prompt, calls Anthropic via SDK, writes `digest.md`. Trigger it with whatever scheduler your platform offers: Vercel Cron, Fly machines schedule, GitHub Actions cron, k8s CronJob, systemd timer, plain cron. **Cost:** trivial, maybe 30 lines plus an API key. **Right when:** your "agent" is really just one LLM call, no multi-step lifecycle, no other agents to coordinate with.

The honest framing for the chapter: **Gas City's value lives during development.** Multi-agent feature delivery, review loops, hands-off chains, the experience of authoring custom formulas and watching them run. For a single daily LLM call in production, GC is the wrong tool, and that is a feature, not a flaw. Most production "AI feature" deploys are Option C in disguise, and that is fine.

For this app, the chapter recommends Option C as the default. Mention Option B as the version-control-friendly alternative for readers who like reviewing what the agent produced before it goes live. Note Option A only to acknowledge it exists; do not recommend it for a digest-shaped problem.

The custom formula the reader just wrote in this chapter is not wasted work for a deploy-Option-C reader. The prompt content (which items, in what shape, with what tone) ports directly into a 30-line script. The formula authoring exercise teaches the LLM-prompting muscle; the deploy decision is orthogonal.

## Status at end of Part 5

- Three orders registered: `rss-fetch` (cooldown 2m, exec, city), `rss-vacuum` (cron 0 4 * * *, exec, city), `rss-digest` (cron 0 8 * * *, formula, rig).
- One custom formula authored: `mol-rss-digest` in `rss-reader/formulas/`.
- Agent-generated `digest.md` artifact in the rig, refreshed daily.
- `/digest` route renders the digest at `http://localhost:3000/digest` with markdown-to-HTML, shipped via mayor handoff in two clean commits (`f528dd4`, `d01b914`).
- City `bin/overview.sh` corrected to canonical capital-`Code` paths.
- City `.gc/settings.json` `Notification` hook removed.
- City `city.toml` extended with `formulas_dir = "../rss-reader/formulas"`.
- Rig `formulas/` and `orders/` directories created and populated.
- All test-run orphan beads closed by hand at end-of-chapter.

## Pending after Part 5

- Decide and implement an alert primitive for stuck-on-permission polecats. Open since the Notification hook removal. Carries into Part 6 or beyond.
- Improve the formula's bead-close step to close the parent molecule rather than the step bead. Polish item; the loose-molecule cleanup is a one-liner in the meantime.

## Commands run during recovery

```bash
gc supervisor stop
pgrep -fl 'dolt sql-server'
kill <orphan-pids>
rm -f .gc/runtime/packs/dolt/{dolt.pid,dolt.lock,dolt-state.json,dolt-provider-state.json}
cd /Users/jonaseriksson/Code/gas-city-tutorial/city   # canonical casing
gc start
gc status
```
