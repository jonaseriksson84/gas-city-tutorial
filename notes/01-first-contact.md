# Notes: Part 1, First contact

Raw notes from the test run of Part 1. Source material for `tutorials/01-first-contact.md` later.

## Tutorial-cleanup observations

These are things the tutorial should NOT do, even though I did them during the test run. List them here so the chapter ends up shorter than my transcript.

### `--city ./city` is redundant when running from inside the city directory

The global `--city` flag defaults to "walk up from cwd". When the reader's shell is inside `city/`, GC auto-discovers it. We should instruct readers to `cd city` once at the start and drop the flag entirely. Save the explanation of `--city` for the rare case where it is genuinely needed (running scripts from outside the city dir, multi-city setups).

### `gc reload` is not needed after editing a prompt template

`gc reload` rereads TOML config (`city.toml`, `pack.toml`). Prompt template files are read when a session materializes, not at reload time. So the loop is:

1. Edit `agents/<name>/prompt.template.md`.
2. Either start a new session, or wait for the next session restart.

We can verify the new prompt with `gc prime <name>` without any reload step.

The chapter should not introduce `gc reload` at all in the prompt-editing flow. Save it for later when we change `pack.toml`.

### `gc prime <name>` returns the prompt verbatim if no template directives

Our mayor prompt has no `{{ template "..." }}` expansions, so `gc prime mayor` returns exactly what we wrote. Worth a one-line callout in the tutorial: "what you write is what the agent sees, except where `{{ ... }}` template directives expand."

## Commands run

(Captured chronologically; will be tightened when writing the chapter.)

1. Edit `city/agents/mayor/prompt.template.md` to the strict-delegator version.
2. `gc prime mayor` to verify the compiled prompt matches what we wrote.
3. `gc session wake mayor` (failed initially due to GH#1232; see Failure modes).
4. After applying the dolt-SQL workaround, `gc session wake mayor` succeeded with `Session rt-18e: wake requested.`
5. `gc session peek mayor` to confirm the mayor came alive and ran its self-onboarding loop.
6. `gc mail send mayor -s "..." -m "..." --notify` to send the first project kickoff message.
7. Mayor read mail, replied via `gc mail reply rt-wisp-kv4 -s "Re: ..." -m "..."`.
8. `gc mail inbox` confirmed the reply appeared in the human's inbox.

## Observations and surprises

### Mayor self-onboards on wake

When the mayor session first comes alive, it executes the loop in our prompt without prompting: runs `gc mail check`, `gc status`, `gc mail inbox`, then posts a "Mayor ready, standing by" summary. This is desired behavior. Worth calling out in the chapter so readers see the mayor "do something" the moment it wakes, not the tmux equivalent of staring at a blank screen.

### `gc mail check` exits 1 when there is no mail

Mayor hit this on first run, recovered by switching to `gc mail inbox`. Could be intentional (nonzero is useful in shell scripts to detect "no new mail") or a UX papercut. One-line note in the chapter so readers do not panic when they see it.

### `gc mail reply` requires `-s` subject; does not auto-Re

Mayor's reply path: tried `--body` (wrong flag) → tried `-m "..."` only (failed with `title is required`) → tried `-s "Re: <original>" -m "..."` (succeeded). The reply command does not derive a subject from the parent message, so subject is required just like a fresh send. Bake this into the next iteration of the strict-delegator prompt so future mayors do not have to discover it through three failures.

### Claude Code's Bash tool truncates help output

When the mayor first ran `gc mail reply --help`, the Bash tool collapsed the tail with "+5 lines", hiding `-s/--subject` from view. The prompt's "if unsure of exact flags, run `gc <cmd> --help`" rule is not always sufficient because of this. The chapter and the prompt should spell the exact reply syntax inline so the agent does not have to consult truncated help.

### Mayor showed restraint without being told the project plan

Despite our prompt not mentioning a "locked tutorial roster," the mayor's reply included the phrase "Deferred to their locked tutorial roster if they already have one specced." That is the agent making a sensible inference (the human probably has a plan, do not preempt it). Good behavior. Not something to engineer into the prompt explicitly, but worth noting that the strict-delegator stance produces this naturally.

### Mail and idle agents: `gc session submit` with default intent is the right tool

This took several iterations to land on. The full mental model:

**Hooks only fire on Claude Code lifecycle events.** The hooks GC installs in the city are:

| Event | Hook |
|---|---|
| `SessionStart` | `gc prime --hook` |
| `UserPromptSubmit` | `gc nudge drain --inject` and `gc mail check --inject` |
| `Stop` | `gc hook --inject` |
| `PreCompact` | `gc handoff "context cycle"` |

None of these fire when the agent is sitting fully idle at its prompt with no turn in progress. So mail addressed to an idle agent does not get auto-picked-up unless something starts a turn.

**Why `gc mail send --notify` is unreliable for idle agents.** `--notify` calls nudge with `--delivery wait-idle` under the hood. Nudge delivers text into the session's tmux input as if typed. If the agent is mid-turn, the text gets processed at end-of-turn (we saw this on first contact: deferred reminder fires after Stop). If the agent is already idle at its prompt, the text sits in the input buffer. No Enter, no UserPromptSubmit, no mail check. The text just sits there.

We confirmed this empirically: `gc nudge status mayor` showed 0 pending / 0 in-flight after two `--notify` messages, so the nudges were not queued, they were sent to stdin and ignored by the idle agent.

**Periodic ticks exist, but not for "always" sessions.** Pool / patrol agents in the `gastown` pack (boot, deacon, witness) declare `wake_mode = "fresh"` and the supervisor wakes them on a reconcile tick interval. Our minimal pack does not include them, and our mayor is a named "always" session, not a pool worker. So no auto-poll for our setup.

**Known issue, not us doing anything wrong.** Confirmed via GH search:

| Issue | State | What it covers |
|---|---|---|
| [GC#1139](https://github.com/gastownhall/gascity/issues/1139) | open | `feat(reconciler): auto-nudge live sessions when gc.routed_to work arrives`. Describes our exact scenario verbatim: idle session sitting at hook waiting for poll, newly arrived routed work stalls. Proposed fix is a reconciler-side per-tick auto-nudge for any alive session whose template has pending routed work. **Not yet merged.** |
| [GC#1404](https://github.com/gastownhall/gascity/issues/1404) | closed | `fix(mail): nudge reply recipients from human`. Fixed `gc mail reply --notify` so nudges actually get queued for recipients. Closed and merged, but not in gc 1.0.0 (which is what we are on). Likely explains why `gc nudge status mayor` showed 0 pending after our `--notify` calls. |

Two distinct gaps. #1404 is the queueing path (fixed). #1139 is the idle-session-doesn't-poll path (still open). Even with #1404, an "always" session that hits idle still does not auto-pick-up.

Before publishing the tutorial: re-check both issues. If #1139 is closed and shipped in the gc version readers will be on, drop the workaround from the chapter body. Until then, the canonical pattern in the chapter is `mail send` + `session submit` with default intent.

**The canonical pattern for "send mail, have it processed at the earliest sensible moment":**

```bash
gc mail send <agent> -s "<subject>" -m "<body>"
gc session submit <agent> "<short pointer text>"
```

`gc session submit` with default intent lets the runtime decide: wake an idle session, queue if mid-turn, never interrupt. That is the "earliest convenience" semantic. The pointer text is brief because the real content is in the mail.

`--intent interrupt_now` is for "stop what you are doing and handle this now." Bad pattern for everyday human-to-mayor mail; it interrupts mid-turn work. We used it once during the test run to recover from a stuck idle mayor; that was a one-off, not the model we teach.

`--notify` on `gc mail send` is fine for "deliver politely, processing happens at next safe idle." But for an "always" session that may genuinely sit idle for hours, that means "maybe never." Avoid it for the human-to-mayor flow in the chapter.

**Tutorial implications:**

- Replace `--notify` in the Part 1 send-and-wait flow with the two-step `mail send` + `session submit` pattern.
- Add a short sidebar in the chapter explaining: idle Claude Code has no auto-poll, hooks only fire on lifecycle events, so the canonical wake-and-deliver tool is `session submit` with default intent.
- Mention `gc nudge status <agent>` as the diagnostic command for "did my notify even queue?" It saved us once already.
- Acknowledge the `gastown` pack provides patrol agents that can prod the mayor periodically; for readers who want auto-poll, that is the upgrade path. Out of scope for this chapter.

### `beads.role not configured` warning on every `bd create`

Bd reads `git config beads.role` on every write to attribute changes (maintainer vs contributor). Unset = a warning prints on every `bd create`. Tracked upstream as GH#2950. The warning is informational; it does not block anything. But it clutters every mayor command and tutorial transcript.

Fix:

```bash
git config beads.role maintainer
```

Run from inside the git repo containing the city. Writes to that repo's local `.git/config`. After setting, subsequent bd writes are silent.

For the chapter: fold this into Part 0 setup as a one-line "configure your beads role" step right after `gc init`. Smaller papercut to fix proactively than to leave readers seeing a warning they cannot decode. Drop the line entirely if GH#2950 lands a default before publish.

## Failure modes encountered

### `gc session wake mayor` fails with `database not initialized: issue_prefix config is missing`

Tracked upstream as [GH#1232](https://github.com/gastownhall/gascity/issues/1232) (kind/bug, priority/p1, open). The `gc-beads-bd.sh` script tries to write `issue_prefix` into the bd config table during init via `bd config set issue_prefix <p>`, but bd 1.0.3 rejects this with `Error: issue_prefix is reserved for setup`. The script call site swallows the error with `2>/dev/null || true`, so init returns success while the row is missing. Every `bd create` write path then fails: `gc session wake`, `gc session attach`, `gc sling`, `gc convoy create`, `gc rig add` (rig-side), periodic order dispatch.

`gc doctor` does not catch this; the read-only `beads-store accessible` check passes because read paths still work. `gc doctor --fix` is a no-op for this particular issue.

**Workaround we applied during the test run:** direct dolt SQL insert into the city's `hq` database `config` table.

```bash
cd <city>/.beads/dolt
dolt --use-db hq sql -q "
  INSERT INTO config (\`key\`, value) VALUES ('issue_prefix', 'rt')
    ON DUPLICATE KEY UPDATE value='rt';
  CALL dolt_commit('-Am', 'set issue_prefix');
"
```

After applying this to the city store, `gc session wake mayor` succeeded and produced `Session rt-18e: wake requested.`

The rig's `rr` database almost certainly needs the same fix before we sling into the rig in Part 2. Apply when we get there.

**For the eventual tutorial chapter:** by publish time, lambdabaa's fix should be merged. Drop this workaround from the chapter body. Keep a single one-line aside: "if you hit `database not initialized: issue_prefix config is missing`, see GH#1232 and apply the dolt-SQL fix shown in the issue."
