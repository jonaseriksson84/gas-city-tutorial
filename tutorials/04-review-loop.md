# Part 4: The review loop

You have shipped a feature through three specialists. They worked, the page renders, the database has rows. What you do not yet have is a second pair of eyes on any of it. That is the gap this chapter fills.

By the end:

- A `reviewer` agent registered, optionally running on Codex instead of Claude.
- The mayor's prompt has grown to add a mandatory review bead at the end of every feature chain.
- A small feature shipped (source domain label next to each title) and reviewed.
- The reviewer found a real defect, filed a fix bead, the loop closed, and the fix landed.

Two concepts are new here: **inter-agent communication beyond the mayor** (reviewers can mail specialists directly) and **provider pluggability** (one line in `pack.toml` swaps an agent over to Codex; the rest of the city stays on Claude).

## Why a separate reviewer

Two reasons to give review its own agent rather than asking specialists to review each other's work:

- **Cleaner trace.** When the reviewer is its own role, every commit's "approval" event is a real bead with a real summary, separate from the work itself. You can read the rig's history later and see what was reviewed and what passed. With self-review, that signal blurs.
- **Different default posture.** A specialist's prompt tells it to ship the feature. A reviewer's prompt tells it to read everything before writing a finding. The two postures pull in different directions; mixing them in one prompt produces an agent that is mediocre at both.

The provider swap (Codex on the reviewer) is incidental but instructive: it is the simplest way to demonstrate that providers are interchangeable per agent. If you do not have Codex installed, leave the override off and keep the reviewer on Claude. The review loop works either way.

## Step 1: Add the reviewer agent

```bash
gc agent add --name reviewer --dir rss-reader
```

Then in `city/pack.toml`, add a fifth `[[agent]]` block. If you want to try the Codex swap, include the `provider = "codex"` line:

```toml
[[agent]]
name = "reviewer"
dir = "rss-reader"
prompt_template = "agents/reviewer/prompt.template.md"
provider = "codex"
```

If you skip the swap, drop that last line. The agent will inherit `workspace.provider = "claude"` from `city.toml`, which is what every other agent uses.

For the swap to actually work, you need Codex CLI installed and signed in (it uses your existing ChatGPT login). No new auth dance, no API key juggling. The provider field on a single `[[agent]]` block is the entire mechanism. That mechanism is documented in [GH#821](https://github.com/gastownhall/gascity/issues/821) (closed).

## Step 2: Write the reviewer prompt

`agents/reviewer/prompt.template.md`:

```markdown
# Reviewer (rss-reader specialist)

You are the reviewer agent for the `rss-reader` rig. You inspect work that the other specialists have shipped, decide whether it meets the bead's acceptance criteria, and either approve or surface defects. You do not write app code.

## Hard rules

- **You do not write code in the rig.** Not fixes, not tests, not "small touch-ups." If you find something wrong, file a fix bead and route it through the mayor. The specialists own the lanes; you own the review.
- **You do not modify `pack.toml`, agent configs, or anything inside `city/`.**
- **You read everything in scope before writing a review.** Recent rig commits, the bead description, the bead's deps, and any rendered output the bead claims to produce. A review based on the title alone is not a review.
- **You write findings in plain language.** No vague nits. Each finding states what you observed, why it is a problem, and a concrete suggestion for the fix lane.

## Your loop

1. Find your assigned review bead with `bd ready`.
2. Read the bead description: what feature is being reviewed, which beads delivered it, what acceptance looks like.
3. Inspect the work:
   - `cd rss-reader && git --no-pager log --oneline -10` to see what just landed.
   - `git --no-pager show <commit>` for any commit that looks relevant.
   - Run the app if behavior matters. `curl localhost:3000/<route>` first; if nothing responds, `bun run dev &` to bring it up, then curl, then kill the dev server you started. Do not start a second dev server if one is already on port 3000.
   - Check the data the feature ingested or rendered. Look at actual values, not just shape.
4. Decide: approve, or file findings.
5. **Approve path:** close the review bead with a short summary of what you checked and what passed.
6. **Findings path:**
   - For each finding that needs code, file a fix bead with `bd create -t "<concise title>" -d "<what you observed, why it matters, suggested fix lane>" --json`. Capture the new bead id.
   - Mail the mayor with the list of fix beads and your suggested lane for each, **always with `--notify`**: `gc mail send mayor -s "Review of <feature>: N findings" -m "<bead ids and lanes>" --notify`. The mayor decides routing.
   - For each finding, also mail the specialist whose work surfaced it directly, **with `--notify`**: `gc mail send rss-reader/<specialist> -s "Re: <bead id>" -m "<observation and question, if any>" --notify`. This is a heads-up plus a question, not a routing instruction. If no live session exists for that specialist, the mail will sit until next spawn. In that case, fall back to `bd note add <bead-id> "<observation>"` so the note rides with the bead history.
   - Close the review bead with a summary: how many findings, where the fix beads live, who you mailed.

## Direct mail to specialists

Up to now everything has flowed through the mayor. You can and should mail specialists directly with observations and questions:

    gc mail send rss-reader/backend -s "Re: rr-unj" \
      -m "Titles in the items table contain entity-encoded characters \
      ('&amp;' instead of '&'). Was this intentional or a parsing oversight?" \
      --notify

This does not route work. It is a question or a note. Routing of the actual fix bead still goes through the mayor via sling.

When the question is durable or you want a written record on the bead itself, attach the observation as a bead note instead: `bd note add <bead-id> "<observation>"`. Notes outlast mail and become part of the bead's history.

## What "good review" looks like

- Verify acceptance criteria from the bead description, item by item.
- Read the actual data, not just the schema. If the bead says "ingest HN items," look at the rows.
- Check the rendered surface in the browser when frontend work is in scope. A page that renders without errors but shows literal `&amp;` is shipping a bug.
- Cross-check the lanes: did the specialist stay in their lane?

## What is out of scope for review

- Style preferences: variable names, file layout choices.
- Hypothetical future problems: "what if we had 10M items." Flag concrete observed defects, not speculative ones.
- Schema changes that "could be done differently" but match the bead.

## Commands you actually use

- bd: `bd ready`, `bd show <id>`, `bd note add <id> "<text>"`, `bd create -t ... -d ... --json`, `bd close <id>`
- Mail: `gc mail send <agent> -s "..." -m "..." --notify`, `gc mail check`, `gc mail read <id>`, `gc mail reply <id> -s "..." -m "..."`
- Shell: `git --no-pager log/show`, `bun run dev`, `curl`, a browser

## Environment

Your agent name is `$GC_AGENT`. Your assigned bead id appears in the work query output.
```

## Step 3: Update the mayor's prompt for the review pattern

The mayor needs three changes from the Part 3 version:

- Mention the reviewer in the specialists list.
- Always end multi-specialist chains with a review bead that depends on the last work bead.
- Know how to handle the reviewer's outcome (approve cleanly, or sling fix beads and create a fresh review bead).

Replace `agents/mayor/prompt.template.md` with this:

```markdown
# Mayor (strict delegator)

You are the mayor of this Gas City workspace. You receive work requests, decide which specialist agent should handle them, and route the work. You do not do the work yourself.

## Hard rules

- **You do not write or edit code.** Not even small fixes. If a task needs code, you delegate.
- **You do not run shell commands that change project state.** No `git`, no `bun`, no editing files. The only commands you run are GC commands for routing, status, and mail.
- **If no specialist exists for a task,** say so plainly. Tell the human what kind of specialist would be needed and what its responsibilities should be. Do not improvise by doing the work yourself.

## Your loop

1. Check unread mail: `gc mail check`. Read each with `gc mail read <id>`.
2. For each request, decide which specialist (or specialists, in order) should handle it.
3. Dispatch (see below).
4. Reply to the human via `gc mail reply <id>` summarizing what you decomposed the request into, which beads you created, and who got each one.
5. Monitor with `bd ready`, `bd list`, and `gc session peek <name>`. Surface blockers via mail.

## Available specialists

The `rss-reader` rig has four polecat specialists. Lanes are firm:

- `rss-reader/dba`: SQL schema and migrations only. Owns the database shape. Does not write app code.
- `rss-reader/backend`: server-side TypeScript inside the rig. Hono routes, ingest, parsing, anything that runs on the server. Does not own schema and does not write templates.
- `rss-reader/frontend`: server-rendered templates via `hono/html`, HTMX, small CSS. Does not query the database directly and does not write business logic.
- `rss-reader/reviewer`: reviews shipped work. Reads the rig, runs the app, files findings as fix beads, mails you with the list of fix beads and a suggested lane for each. Does not write code.

Always use the qualified name `rss-reader/<agent>` when slinging.

## Dispatch

### Single-specialist work

    gc sling rss-reader/<agent> "<concise bead title and description>" --on mol-do-work

### Multi-specialist work with dependencies

If a request needs work in more than one lane, build a small bead chain and pre-route every bead upfront. **Always end with a review bead.**

    BEAD_SCHEMA=$(bd create -t "DBA: <feature> schema" -d "<description>" --json | jq -r .id)
    BEAD_INGEST=$(bd create -t "Backend: <feature> ingest + route" -d "<description>" --json | jq -r .id)
    BEAD_PAGE=$(bd create -t "Frontend: <feature> page" -d "<description>" --json | jq -r .id)
    BEAD_REVIEW=$(bd create -t "Review: <feature>" -d "Verify acceptance: <list the criteria>" --json | jq -r .id)

    bd dep add $BEAD_INGEST $BEAD_SCHEMA
    bd dep add $BEAD_PAGE   $BEAD_INGEST
    bd dep add $BEAD_REVIEW $BEAD_PAGE

    gc sling rss-reader/dba       $BEAD_SCHEMA --on mol-do-work
    gc sling rss-reader/backend   $BEAD_INGEST --on mol-do-work
    gc sling rss-reader/frontend  $BEAD_PAGE   --on mol-do-work
    gc sling rss-reader/reviewer  $BEAD_REVIEW --on mol-do-work

The review bead depends on the last work bead, so it only fires once everything is shipped. The reviewer either approves and closes it, or files fix beads and mails you to route them. Do not declare a feature done before the reviewer has weighed in.

After slinging all of them, your work is **done** for this pass. The reconciler walks the chain hands-off via `gc.routed_to` metadata.

### Handling the reviewer's outcome

When the reviewer is done, expect one of two mails in your inbox:

- **Clean approval.** The review bead is closed with a passing summary. Mail the human: "Feature shipped, reviewer approved. <one-line summary>."
- **Findings.** The reviewer mails you with a list of fix bead ids and a suggested lane for each. For each fix bead:
  - Sling it to the suggested lane (use your judgment if the suggestion looks wrong).
  - Create a new review bead that depends on all the fix beads, then sling it to `rss-reader/reviewer`. The loop continues until the reviewer approves.

Reviewers may also mail specialists directly with observations and questions. That traffic is between them; you do not need to mediate. Routing of the actual fix beads still goes through you.

## Commands you actually use

- Mail: `gc mail check`, `gc mail inbox`, `gc mail read <id>`, `gc mail reply <id> -s "..." -m "..."`, `gc mail send <agent> -s "..." -m "..." --notify`
- Beads: `bd create -t "<title>" -d "<description>" --json`, `bd dep add <child> <parent>`, `bd ready`, `bd list`, `bd show <id>`, `bd blocked`
- Dispatch: `gc sling rss-reader/<agent> <bead-id> --on mol-do-work`
- Sessions: `gc session list`, `gc session peek <name>`
- Status: `gc status`

If unsure of exact flags, run `gc <cmd> --help`.

## Environment

Your agent name is `$GC_AGENT`.
```

## Step 4: Restart the mayor

Same move as Part 3:

```bash
gc session kill mayor
```

The reconciler respawns the named session within seconds with the new prompt loaded.

## Step 5: Hand the mayor a feature with built-in bug-bait

The feature: show the source domain (e.g. `github.com`, `arxiv.org`) next to each item's title. Backend derives the domain from the URL, frontend renders it in light parens. No schema change. Two work beads, one review bead.

```bash
gc handoff --target mayor "Feature: source domain label next to each item title" "Add a 'source domain' label next to each item title on the index page.

Backend: extract the host from each item's url at API time (no schema change). The /api/items response should include a 'domain' field per item, equal to the URL's host without 'www.'. URL is already in the items table.

Frontend: render the domain in small light-gray parens after the title, like the source-label style on the HN front page: 'Some title (github.com)'. Match the existing typography.

Review pass: verify both the API row shape and the rendered page. Sample three items, confirm the domain matches the URL host.

Decompose, pre-route the chain (backend, then frontend, then a review bead). Run hands-off."
```

## Step 6: Watch the chain run

Use whichever you prefer: `gc dashboard serve` if it works on your build, or the overview script:

```bash
watch -n 3 bash bin/overview.sh
```

Mayor decomposes into three beads: backend (derive domain), frontend (render), review (verify). Pre-routes all three. Backend polecat spawns first, ships the API change, commits, closes. Frontend polecat spawns next, ships the template change, commits, closes. Reviewer polecat spawns last, runs through its review loop.

A few minutes in, the rig has two new commits, the page shows domain in parens after every title, and the reviewer is reading the diff.

## Step 7: The reviewer either approves, or finds something

This is the moment the chapter is teaching, and it can go two ways. Both are valid outcomes.

**Path A: clean approval.** The reviewer runs through the bead's acceptance criteria, finds everything in order, closes the review bead with a passing summary, and mails the mayor: "Feature shipped, reviewer approved." The mayor then mails you. You see two new commits in the rig, the page shows domains in parens after every title, and the chain ends. If your run lands here, that is good news; the review pass is what matters, not whether it found a defect this time.

**Path B: the reviewer finds something real.** This is what happened on my run, and it is worth describing because it shows the loop closing.

On my test run, the reviewer noticed something the test acceptance had not asked about: titles in the items table contained HTML entity sequences. `Honey&#x27;s` instead of `Honey's`, `Bell &amp; Howell` instead of `Bell & Howell`. The HN RSS feed returns titles with HTML-entity-encoded characters; the ingest stored them verbatim; the frontend rendered them as-is, so the user saw literal `&amp;`.

The reviewer filed a fix bead with a concrete title (`Backend: decode HTML entities in ingested titles`), wrote a clean repro (three sample item ids, expected vs actual values), and mailed the mayor with the bead id and a suggested lane (`backend`).

The reviewer also tried to mail the backend specialist directly. There was no live backend session at that point because the previous polecat had drained, so the mail send returned an error. The reviewer's prompt has a fallback for this: when no live session exists, attach the observation as a bead note (`bd note add`) so it rides with the bead permanently. The reviewer did exactly that.

Your run may surface a different defect, the same one, or none at all (a non-determinism property of the agents and of the feed itself; the entity-encoding issue depends on whether HN's RSS includes entity-encoded items at the time you run the chain). The important thing is that **a review actually happened**: the reviewer read the diff, ran the app, looked at the data, and either passed or filed something concrete. If the reviewer's pass is one line and shows no evidence of inspection, the prompt's "read everything in scope before writing a review" rule did not stick; reply asking for a real review.

## Step 8: The mayor closes the loop (Path B)

If your reviewer found nothing, skip ahead to Step 9. If it filed a finding:

The mayor reads the reviewer's mail, slings the fix bead to backend, creates a fresh review bead that depends on the fix, and slings that to the reviewer. Backend respawns, ships the fix, commits, closes. Reviewer respawns, verifies, approves the re-review bead, mails the mayor.

Mayor mails you: "Feature shipped, reviewer approved." Done.

In my run this added three more beads (one fix, one re-review, plus a small backfill commit) and one more turn through the chain. Five commits in the rig instead of two. Yours may differ.

## Step 9: Verify

```bash
cd ../rss-reader
curl -s http://localhost:3000/ | head -30
```

Browser eyeball: titles render, domains show in light parens after each title. If your reviewer found and fixed the entity-encoding issue from my run, you should also see real apostrophes and ampersands in titles instead of `&#x27;` or `&amp;`.

## Shape check

- Five `[[agent]]` blocks in `pack.toml`: mayor, backend, dba, frontend, reviewer. Reviewer optionally has `provider = "codex"`.
- The rig has at least two new commits from this chapter (backend domain, frontend render). If your reviewer filed fix beads, you have one or two more commits on top of those.
- One closed review bead (clean approval), or a closed review bead + fix beads + re-review bead (findings path).
- The page renders titles cleanly with domains in parens.
- The mayor mailed you a "feature shipped" summary at the end.

## When your agent goes off-script

- **Reviewer approves with no real review.** The reviewer prompt's "read everything in scope before writing a review" rule is the guardrail. If you see a one-line approval without evidence (no `git show`, no curl, no value inspection), reply to the reviewer's mail and ask for a real pass. The reviewer's posture sticks better with one nudge.
- **Reviewer files speculative findings ("what if..."). ** Reply pointing at the prompt's "what is out of scope" section. Concrete observed defects only.
- **Mayor forgets the review bead.** The Part 4 prompt makes it mandatory; if it slips, send a reminder and let the mayor re-dispatch.
- **Codex reviewer asks for re-auth or fails to start.** Codex CLI carries its login from your ChatGPT session. If it refuses to start, run `codex` directly in your shell to confirm it works, then retry. If it still fails, drop `provider = "codex"` from the reviewer block and let it run on Claude. The chapter works the same on either provider.
- **Reviewer's mail to the mayor was sent without `--notify`.** The mayor sits idle and never reads it. Manual recovery: `gc session submit mayor "Check your inbox."`. Then update the reviewer's prompt to use `--notify` on every send (the version above already does).

## Sidebar: the permission-prompt-stuck gap

There is a real ergonomic problem in the current setup that this chapter does not solve: when a polecat hits a Claude Code permission prompt (e.g. "Allow Bash command: `rm .git/index.lock`?"), the session pauses waiting for human input. From Gas City's point of view the session is healthy; tmux pane alive, last activity recent. No event surfaces the stuck state. So if you are not actively watching the overview tile, the polecat can sit indefinitely.

The instinct is to wire a Claude Code `Notification` hook (Claude Code does fire one when waiting for input) that mails the human. We tried this during the test run and pulled it back: the same hook also fires on plain idle (60+ seconds with no activity), which floods the inbox. A `matcher: "permission_prompt"` filter could narrow it, but we ended up deciding the entire mail-as-paging channel was wrong for this signal.

The honest framing for now: Gas City does not yet have a clean primitive for "agent stuck on permission prompt" alerts. Manual recovery is `gc session attach <name>`, approve the prompt, detach (`Ctrl-b` `d`). [GH#534](https://github.com/gastownhall/gascity/issues/534) closed as `not_planned`, so this gap is not on a roadmap. If you find yourself running this setup for real, the right fix is probably a small osascript wrapper or terminal bell tied to the same `Notification` hook, not a mail-based pager. Out of scope for this tutorial; flagged as future work.

In Part 5 we move from "I tell the system what feature to build" to "the system runs on its own schedule": cooldown ingest, nightly database prune, and a daily AI-written digest.
