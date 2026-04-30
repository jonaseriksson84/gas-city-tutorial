# Notes: Part 4, The review loop

Raw notes from the test run of Part 4. Source material for `tutorials/04-review-loop.md` later.

## Concept payload (from the locked design)

- Inter-agent communication beyond the mayor (reviewer mails specialists directly)
- Optional Codex provider swap on a single agent (provider pluggability)
- Review-as-part-of-feature-delivery, not as an afterthought

## What was set up

- `gc agent add --name reviewer --dir rss-reader` plus `[[agent]]` block in `pack.toml` with `dir = "rss-reader"` and `provider = "codex"`. The `provider = "codex"` override on a single agent is the entire mechanism for the provider swap; everything else inherits `workspace.provider = "claude"`.
- `agents/reviewer/prompt.template.md` written: hard rules (no code in the rig, fixes go through mayor, read everything before reviewing), the loop, an explicit "direct mail to specialists" section teaching the new pattern, what good review looks like, what is out of scope.
- `agents/mayor/prompt.template.md` updated: reviewer added to the four specialists list; multi-specialist chain example extended to include a `BEAD_REVIEW` bead depending on the last work bead and pre-routed to `rss-reader/reviewer`; new "Handling the reviewer's outcome" subsection covering both clean-approval (mail human) and findings (sling each fix bead, create a fresh review bead depending on the fixes, sling that to reviewer, loop until approved); brief note that reviewer↔specialist direct mail is normal traffic the mayor does not mediate.

## The feature run

Feature delivered: source domain label next to each item title.

Mayor decomposed cleanly into three work beads + one review bead, correctly skipping dba (no schema change needed; the URL was already in the `items` table):

- `rr-unj` Backend: derive domain from item URL for API and template
- `rr-tcw` Frontend: render item domain in parens on index
- `rr-dmw` Review: source domain label feature

Backend committed `30e9c31`, frontend committed `85d504d`. Reviewer (running on Codex) verified the feature against acceptance criteria: domains rendered correctly on the page, `domain` field populated on every API row, no obvious regressions. Reviewer also surfaced an entity-encoded titles defect that was leaking into the API and rendered output. Filed `rr-pyv` as a fix bead with concrete repro steps and a suggested lane (backend), mailed mayor with the finding, and added a note to `rr-unj` because no live backend session existed to mail directly.

Mayor was nudged manually after the reviewer's findings mail (see "Mail without --notify does not wake the recipient" below). Mayor read both unread mails, slung `rr-pyv` to backend, and pre-routed a fresh review bead `rr-9f3` depending on `rr-pyv` to reviewer. Backend committed `568ec40` (added `src/util/entities.ts`, decoded RSS feed titles before storing, plus a one-shot backfill of existing rows). Reviewer re-reviewed `rr-9f3` and approved.

Final shape:
- Five total commits in the rig for Part 4 (scaffold + Part 3's three + Part 4's three).
- Three feature beads + one review bead + one fix bead + one re-review bead, all closed.
- Page renders cleanly: titles like "Honey's", "IBM's", "Zig project's" all show real apostrophes; no `&#x27;` or `&amp;` artifacts.
- Domains show in grey parens beside each title.

## Tutorial-cleanup observations

### Mail without `--notify` does not wake the recipient

The reviewer's findings mail to the mayor ("Review of source domain label feature: 1 finding") was sent without `--notify`. The mail bead was written, but no recipient nudge was queued. The mayor was alive and idle (a `mode = "always"` named session), so it sat — not asleep, not stuck, just waiting for input it would never proactively go look for. Same shape as the GC#1139 idle-poll gap.

The fix is `--notify` on every `gc mail send` to a recipient that might be idle. Documentation in `gc mail send --help` is explicit about this. The chain of fixes was GH#619 → GH#1370 → GH#1404 (all closed) which made `--notify` actually queue the recipient nudge correctly. Earlier HANDOVER text said `--notify` was bad ("writes to stdin, sits in buffer, never processed"). That was true of an intermediate state and is now stale; HANDOVER corrected.

The reviewer prompt has been updated to use `--notify` on every send, both to mayor (findings) and to specialists (questions). The bead-note fallback (`bd note add`) is documented for the case where the specialist has no live session and the mail will sit until next spawn.

For the chapter: this gap is real and worth surfacing. The lesson is "mail does not push; nudges push." Default to `--notify` whenever the recipient might be idle.

### Permission prompts on Claude Code polecats are invisible to gc events — fixed in-chapter

Backend polecat sat on a `Bash(rm ...)` permission prompt for a stale `.git/index.lock` (left over from yesterday's `gc stop` interrupting an in-flight git operation). The polecat was healthy by every GC measure: session "active", tmux pane alive, last-active a few minutes back. But no event surfaced the stuck state. We confirmed via `gc events --since 10m | jq -r .type | sort | uniq -c | sort -rn`:

```
164 bead.updated
 89 bead.closed
 26 bead.created
  2 session.woke
  2 convoy.closed
  1 mail.sent
```

No permission/notification/input event. The pause is internal to the Claude Code subprocess and never bubbles up to the GC event bus.

Resolution path during the run: `gc session attach rss-reader/backend-1` to enter the polecat's tmux + Claude Code UI, approved the prompt, detached. Worked, but only because the human happened to be watching the overview script.

**Investigation:** [GH#534](https://github.com/gastownhall/gascity/issues/534) "feat: detect agents stuck on Claude Code modal dialogs" was closed `state_reason: not_planned`, so the GC-side detection feature did not ship. There is no GC primitive to lean on for this. The right hook lives one layer down: Claude Code's own `Notification` hook fires when Claude Code is waiting for user input.

**Fix wired in-chapter:** added a `Notification` hook to `city/.gc/settings.json` (the file that drives all managed Claude Code sessions in the city). The hook mails `human` with `--notify` and an attach command for the stuck session. Added a `HUMAN INBOX` tile to `bin/overview.sh` so the page is visible in the watch loop without grepping. Verified the hook command shape end-to-end by manually invoking it with `--from mayor` and watching the mail land in human's inbox. The Claude Code side (whether `Notification` actually fires on permission prompts) is upstream-documented behavior; we will see it fire naturally on the next polecat that hits a prompt.

For the chapter: this is the single biggest ergonomic improvement of Part 4. Without it, polecats stuck on permission prompts can sit indefinitely. With it, the human is paged within seconds.

Note for layering: per-provider overlays at `.gc/system/packs/core/overlay/per-provider/` exist for cursor, codex, copilot, gemini, omp, opencode, pi — but no `claude` directory. Claude Code's settings live at the city level (`city/.gc/settings.json`), which is also why this fix is one file at one path.

### `gc handoff --target mayor` did not restart the mayor

When we delivered the Part 4 feature request via `gc handoff --target mayor "<subject>" "<body>"`, the running mayor session (`rt-18e`) kept running (age stayed at "1d"). Per `gc handoff --help`, `mode = "always"` named sessions are "on-demand configured" targets, meaning handoff sends the mail without killing the session. The implication: prompt-template edits do not propagate via handoff for always-on crew agents. The new mayor never read the updated prompt.

The reason the mayor still followed the new review-bead pattern is that the handoff *body* explicitly explained the pattern in plain text ("Your prompt has been updated to teach the review-loop pattern: every feature chain now ends with a review bead..."). The mayor learned from the mail content rather than the template.

Workaround for forcing a real restart: `gc session kill mayor` (reconciler restarts with the new template loaded) or `gc restart` (whole-city restart).

For the chapter: when teaching prompt-template edits on a long-running named session, point readers to `gc session kill <name>` rather than `gc handoff` for the "load the new prompt" intent. `gc handoff` is the right tool for "deliver mail and continue conversation," which is a different thing.

### Stale `.git/index.lock` from prior `gc stop`

Yesterday's `gc stop` interrupted a polecat mid-`git add`. The git process was killed before it released `.git/index.lock`. Today's first polecat that touched the rig hit `fatal: Unable to create '.git/index.lock': File exists.` The polecat correctly diagnosed it (zero-byte lock dated yesterday, no holding process), then asked for permission to `rm` it and waited. After approval it removed the lock and committed.

For the chapter: pair this with a brief note on `gc stop` semantics. Hard kill of a polecat mid-git leaves the lock; the next polecat needs to clean it up. The agent's reasoning before deleting was the right pattern (verify stale, then act). Worth a sidebar.

### Reviewer's bead-note fallback worked exactly as designed

When the reviewer tried `gc mail send rss-reader/backend ... --notify` (would-be direct mail) but no live backend session existed (polecats drain after work), the prompt's documented fallback was `bd note add <bead-id> "<observation>"`. The reviewer correctly fell back. The note is now part of `rr-unj`'s history and rides with the bead permanently. This is better than the mail behavior anyway; mail decays, bead notes do not.

For the chapter: lead with the bead-note pattern for any "I want this thought attached to a specific work item" case. Direct mail is for live conversation; bead notes are for durable annotations.

### Codex provider swap is one line in `pack.toml`

`provider = "codex"` on the reviewer's `[[agent]]` block was the entire change. No new auth (Codex CLI's existing ChatGPT login carried). The reviewer session ran end-to-end on Codex, including filing a fix bead, mailing the mayor, and approving the re-review. No detectable behavioral difference at this scale.

For the chapter: the swap line is the headline; the rest is "and it just works." Mention the provider inheritance design ([GH#821](https://github.com/gastownhall/gascity/issues/821), closed) so readers know there is a clean override semantic.

## Commands run

```bash
gc start                                     # bring supervisor back after overnight shutdown
gc agent add --name reviewer --dir rss-reader
# Edit pack.toml to add [[agent]] block for reviewer with dir, prompt_template, provider = "codex"
gc reload                                    # no-op (fsnotify already picked up edits)
gc handoff --target mayor "Feature: source domain label next to each item" "$(cat <<'EOF' ... EOF)"
gc session attach rss-reader/backend-1       # to approve a permission prompt manually
gc events --since 10m | jq -r '.type' | sort | uniq -c | sort -rn   # event-type inventory
gc mail mark-unread rt-wisp-35g              # recovery after accidental mail read
gc session submit mayor "Check your inbox."  # manual nudge because mail was not sent with --notify
```

## Observations and surprises

- **Reviewer naturally surfaced the right bug.** No prompting required; the entity-encoded titles defect was visible the moment the reviewer rendered the page, and it filed a tight fix bead with repro steps. Pedagogy works: a competent specialist with read-everything-before-writing-a-review discipline finds the obvious things.
- **Mayor's "always on" is not "always polling."** Idle named sessions stay idle. Mail without `--notify` is mail in a void. Wake-on-routed-work (GC#1126) is the only auto-wake we get for free.
- **Provider swap was a non-event.** One line, no auth changes, no behavioral surprises. That is the right level of friction.
- **Permission-prompt invisibility is the worst gap left.** Bigger than the mail-wake gap because there is no `--notify` equivalent yet exposed in our setup. Real fix is the Notification hook + GH#534 detection wiring; that is the next task.

## Failure modes encountered

- **Mail without `--notify` left mayor idle indefinitely.** Manual nudge was required to recover. Reviewer prompt updated to use `--notify` everywhere; HANDOVER stale-note about `--notify` corrected.
- **Polecat stuck on a permission prompt was invisible to GC events.** Manual `gc session attach` to approve during the run. Fixed in-chapter by wiring a Claude Code `Notification` hook in `city/.gc/settings.json` that mails `human --notify` on every notification, plus a HUMAN INBOX tile in `bin/overview.sh` so pages are visible at a glance.
- **`gc mail read` (vs `gc mail peek`) marked an agent's mail as read** when the human was inspecting it. Recovery via `gc mail mark-unread <id>`. For human inspection of agent mail, default to `gc mail peek <id>`.
- **`gc handoff --target` does not restart `mode = "always"` named sessions.** Use `gc session kill <name>` when prompt-template changes need to be reloaded. The `handoff` body itself can carry the new pattern as plain text in a pinch.
- **Stale `.git/index.lock` from a prior `gc stop` that interrupted git.** Polecat diagnosed and resolved with permission. No code fix needed; it is a side-effect of hard-kill semantics on `gc stop`.
