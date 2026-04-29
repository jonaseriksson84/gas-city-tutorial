# Notes: Part 3, Specialists at work

Raw notes from the test run of Part 3. Source material for `tutorials/03-specialists.md` later.

## Concept payload (from the locked design)

- Polecats vs crew (sharpened by watching multiple polecats materialize and drain)
- Formulas (TOML lifecycle recipes; Part 3 uses built-in `mol-do-work` via `--on`)
- Molecules (the bead DAG cooked from a formula; here we hand-build the DAG)
- Wisps (a formula attached to a bead via `--on`)
- Dependencies between work beads (`bd dep add`, `bd ready`)
- DAG = Directed Acyclic Graph; define inline at the moment we wire the first dep

## Tutorial-cleanup observations

### Major correction: pre-route the entire chain, do not nudge the mayor manually

I planned this chapter assuming the mayor would orchestrate the dispatch loop manually: sling bead 1, wait for it to close, sling bead 2, etc. That was wrong, and the user (rightly) pushed back during the test run. The actual GC mechanism:

- `gc sling <agent> <bead-id>` sets metadata `gc.routed_to=<agent>` on the bead as a side effect.
- A polecat's `work_query` is `bd ready --metadata-field gc.routed_to=$GC_TEMPLATE --unassigned`. That is how polecats find their work.
- The reconciler's auto-nudge (GH#1126, merged 2026-04-23) detects unprocessed `gc.routed_to` beads and either spawns a new session of the target template (if no session exists) or nudges an alive idle one.

The correct multi-step pattern: pre-route every bead in the chain at creation time. Slinging a blocked bead is fine and intended; it just stamps the metadata, and the bead waits there with `bd ready` returning false until its blockers close. No orchestrator polling, no human nudging.

The mayor's prompt template was updated to teach this pattern after the user's pushback. The chapter should present pre-routing as the default from the start; only mention the manual-nudge anti-pattern as a brief "do not do this" callout if at all.

GH#1139 (open) describes a narrow gap (alive-idle session whose template just received routed work and scaling is satisfied), but for our setup most polecats are spawned-on-demand by scale_check, so the gap rarely bites. The pattern is sound.

### Rig beads vs city beads

`bd list` from `city/` shows city-level beads only (session beads, mail-trigger beads). The feature beads we create live in the rig's bd database, so they only appear if you `cd rss-reader/` first or pass `--rig rss-reader`. Worth a one-line callout when the reader does their first `bd list` and sees nothing they expect.

The mayor's prompt template handles this implicitly by `cd`ing into the rig before running bd commands. Readers will trip on it the first time they run bd themselves to inspect state.

### Dashboard is broken in v1.0.0 (request-flood, fixed on main)

`gc dashboard serve` opens a static SPA at localhost:8080. On v1.0.0 it floods the supervisor API with concurrent panel refreshes, exhausts Chrome's per-origin socket pool, and the tab dies with cascading `net::ERR_INSUFFICIENT_RESOURCES` errors plus "Panel refresh failed" toasts.

Tracked as [GH#1168](https://github.com/gastownhall/gascity/issues/1168) ("bug: dashboard failed to fetch"), closed 2026-04-28.

The fixes:

- [PR#1339](https://github.com/gastownhall/gascity/pull/1339) (`perf(api): serve read models from cached session state`) merged 2026-04-27 18:51 UTC. Replaces expensive per-session provider calls with cached session-bead lookups for `/v0/city/{city}/sessions`, `/rigs`, `/status` etc.
- [PR#1376](https://github.com/gastownhall/gascity/pull/1376) (`fix(status): use cached session state with liveness overlay`) merged 2026-04-27 20:30 UTC. Completes the cached-state work for `/status`.

**These landed on main but are not in any released tag.** Latest release is v1.0.0 (2026-04-21). The brew formula points at the v1.0.0 tarball. `brew upgrade` does not help; you are already on the latest released bottle.

For the chapter: do **not** recommend the dashboard for v1.0.0. State the situation plainly: "v1.0.0 has a known dashboard fetch-storm bug. The fix is on main and will land in the next release. Until then, the dashboard is unusable; use the CLI overview." If we want to embed a screenshot, take it on a build that has the fix (build from main, take screenshot, downgrade for the rest of the test run if needed).

When v1.0.1 (or whatever ships next) lands, revisit and rerun on a clean install to confirm the fix.

### `gc status` perf is also slated to improve

[GH#1177](https://github.com/gastownhall/gascity/issues/1177) (open DRAFT, blocked on #1147 + #1149) documents a 74s `gc status` hang on a 37-agent city. Fix is gated on read-path-routing PRs. We do not hit this in the tutorial because the city is tiny, but worth knowing.

[GH#1293](https://github.com/gastownhall/gascity/issues/1293) (open) is a similar "gc status / gc session list hangs indefinitely" report. Same code path.

### Useful CLI overview for the reader

```bash
watch -n 2 'echo "=== sessions ===" && gc session list && echo "" && echo "=== rig beads ===" && (cd rss-reader && bd list --status=open) && echo "" && echo "=== mayor inbox ===" && gc mail inbox 2>/dev/null | head -10'
```

Refreshes every 2s. Tile shows: who is running, what is still open in the rig, what mail is waiting. Good "leave it open in another terminal" answer.

### `gc events --follow` is the activity stream

```bash
gc events --follow --since 5m
```

JSON Lines, one event per line. Good for "what just happened?" debugging. Less good as a static overview because it scrolls.

### Configuration hot-reload is invisible (and that is correct)

Both reloads in the chapter reported "No config changes detected" because the controller's fsnotify watcher had already picked up the edit ([GH#926](https://github.com/gastownhall/gascity/issues/926) made the watcher recursive and reliable). `gc reload` is a stabilization tool, not a "restart on edit" trigger; in normal use it is a no-op. See chapter 2 notes for the full writeup.

### Long-lived crew session needs explicit restart to pick up prompt changes

The mayor is a `mode = "always"` crew session — it runs continuously. Editing `agents/mayor/prompt.template.md` on disk does not change the prompt loaded into the running mayor's context. Restart it with:

```bash
gc handoff --target mayor "<subject>" "<message-body-becomes-the-new-mayor's-first-task>"
```

`gc handoff --target` mails the target, kills the running session, and the reconciler restarts it (with the new prompt) and the mail queued. Useful pattern: deliver the next chapter's feature request as the handoff body. The new mayor reads its inbox on boot and immediately starts the new work with the new prompt.

For the chapter: introduce `gc handoff` here as the natural "kick the mayor with new instructions" command. It is more elegant than `gc restart` (which restarts the whole city).

## Commands run

```bash
gc agent add --name dba --dir rss-reader
gc agent add --name frontend --dir rss-reader
# Edit pack.toml to add [[agent]] blocks for dba and frontend with dir = "rss-reader"
gc reload
gc config show | grep -E '^\[\[agent\]\]|^name|^dir'
gc handoff --target mayor "First feature: HN-style index from a hardcoded RSS feed" "<feature description>"
gc session list
gc session peek mayor
gc sling rss-reader/backend rr-i9v --on mol-do-work
gc sling rss-reader/frontend rr-96c --on mol-do-work
bash bin/overview.sh
```

## Observations and surprises

- **The mayor's restart-via-handoff pattern is elegant.** `gc handoff --target mayor` mails the new feature request, kills the running mayor, the reconciler restarts it with the new prompt, and the new mayor reads the mail on boot. Tighter than `gc restart` (which restarts the whole city) and natural for chapter pacing.

- **Slinging with `--on mol-do-work` creates extra bead infrastructure** that shows up in `bd list`. Each sling created:
  - An auto-convoy (e.g. `rr-55h sling-rr-i9v`) wrapping the work bead.
  - A molecule (e.g. `rr-588 mol-do-work`) for the wisp's lifecycle, with two task children (`Read assignment, implement, and close`; `Signal completion`).
  - The actual feature task bead (e.g. `rr-i9v`).

  Worth a sidebar so readers do not freak when their bead list shows triple the beads they expected. The convoy and molecule wrappers are bookkeeping; the task bead is the work.

- **Pre-routing the chain worked exactly as documented.** Mayor created three beads, wired deps with `bd dep add`, and slung the first with `--on mol-do-work`. After the user's pushback on manual nudging, two slings (`gc sling rss-reader/backend rr-i9v --on mol-do-work` and the same for frontend) stamped routed_to on the remaining beads. Backend polecat spawned automatically when rr-iv6 closed and rr-i9v became ready. Frontend polecat spawned when rr-i9v closed and rr-96c became ready. No human in the loop after the two recovery slings.

- **The agents work end-to-end.** Final shape: four commits in the rig (scaffold, schema, ingest, frontend), three closed feature beads, server boots, GET /api/items returns N entries, GET / renders an HN-style list.

- **Backend flagged a real defect in its completion mail:** "observed entity-encoded titles in ingest data." The HN RSS feed includes HTML entities (`&amp;`, etc.) in titles, and the ingest stored them verbatim. Frontend renders them as-is, so users see literal `&amp;`. **Save this for Part 4** — it is a perfect target for the review-loop chapter (reviewer flags the bug, mayor opens a fix bead, backend or frontend addresses it).

## Failure modes encountered

- **The "wait and watch" mayor-as-orchestrator pattern was wrong.** Manual nudging was my misread. The mayor's prompt now teaches pre-routing the entire chain at sling time. Chapter should teach pre-routing from the start; mention the manual-nudge anti-pattern only if at all.
- **Dashboard request flood in v1.0.0** ([GH#1168](https://github.com/gastownhall/gascity/issues/1168), fixed on main but not in any release tag yet). Documented above. The chapter cannot recommend the dashboard for v1.0.0 readers.
- **`--to mayor` is wrong syntax for `gc mail inbox`.** The right form is `gc mail inbox mayor`. My initial overview script had the bad form; corrected.
- **`watch` + `git log` requires `--no-pager`,** otherwise git seizes the TTY with a pager and `watch` becomes unusable. Tutorial helper script uses `git --no-pager log` accordingly.
