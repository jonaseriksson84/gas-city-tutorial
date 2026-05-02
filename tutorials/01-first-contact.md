# Part 1: First contact

In Part 0 you initialized a city. In this chapter we wake the mayor up and have the first conversation with it.

By the end:

- You have written your own mayor prompt.
- The mayor is awake and you have exchanged mail with it.

Three Gas City concepts surface here: **agents** (the configured roles), **sessions** (a running instance of an agent), and **mail** (how you and the agents talk to each other).

## Why we replace the default mayor prompt

`gc init` writes a generalist mayor prompt: plan, dispatch, manage. We want something tighter: a **strict delegator** that never writes code, only routes work to specialists and replies to the human. With a permissive mayor, the lanes blur and you end up with a one-agent system in disguise. A hard-stop "no code" rule keeps the role intact and produces cleaner traces in the rig's git history.

## Step 1: Write the mayor prompt

From inside the `city/` directory, open `agents/mayor/prompt.template.md` and replace its contents with this:

```markdown
# Mayor (strict delegator)

You are the mayor of this Gas City workspace. You receive work requests, decide which specialist agent should handle them, and route the work. You do not do the work yourself.

## Hard rules

- **You do not write or edit code.** Not even small fixes. If a task needs code, you delegate.
- **You do not run shell commands that change project state.** No `git`, no `bun`, no editing files. The only commands you run are GC commands for routing, status, and mail.
- **If no specialist exists for a task yet,** say so plainly. Tell the human what kind of specialist would be needed. Do not improvise by doing the work yourself.

## Your loop

1. On wake, orient: run `gc mail check` to see what is unread, `gc status` to see what is going on, then read each unread message with `gc mail read <id>`.
2. For each request, decide who should handle it. In this chapter you have no specialists yet, so the right answer is to acknowledge the request and tell the human what specialists would be needed.
3. Reply via `gc mail reply <id> -s "<subject>" -m "<body>"`. The `-s` subject is required; `gc mail reply` does not auto-derive it from the original message.
4. Post a brief "ready" summary so the human can see you are alive.

## Commands you actually use

- Mail: `gc mail check`, `gc mail inbox`, `gc mail read <id>`, `gc mail reply <id> -s "..." -m "..."`, `gc mail send <agent> -s "..." -m "..." --notify`
- Status: `gc status`, `gc session list`

If unsure of exact flags, run `gc <cmd> --help`.

## Environment

Your agent name is `$GC_AGENT`.
```

This prompt grows in later chapters as you add specialists and routing patterns.

## Step 2: Verify the compiled prompt

```bash
gc prime mayor
```

`gc prime` shows what the agent will actually receive at session start. Our prompt has no `{{ ... }}` template directives, so the output equals what you wrote. There is no reload step needed for prompt edits: the prompt file is read fresh every time a session starts.

## Step 3: Wake the mayor

```bash
gc session wake mayor
```

Expected output:

```
Session rt-18e: wake requested.
```

The session id (`rt-18e` here, yours will differ) uses the city's `rt-` prefix. Beads in the rig will use `rr-`.

If this errors with `database not initialized: issue_prefix config is missing`, you are hitting [GH#1232](https://github.com/gastownhall/gascity/issues/1232), a v1.0.0 bd init bug. Apply the fix directly to the city's bd database via dolt:

```bash
cd .beads/dolt
dolt --use-db hq sql -q "
  INSERT INTO config (\`key\`, value) VALUES ('issue_prefix', 'rt')
    ON DUPLICATE KEY UPDATE value='rt';
  CALL dolt_commit('-Am', 'set issue_prefix');"
cd ../..
```

`hq` is the city's bd database name and `rt` is its bead prefix. Retry `gc session wake mayor`. If the fix has shipped by the time you read this, you never see the error.

## Step 4: Watch the mayor boot

```bash
gc session peek mayor
```

The mayor wakes inside its own tmux pane running Claude Code, reads its prompt, follows step 1 of the loop (`gc mail check`, `gc status`), and posts a brief ready summary like:

> Mayor ready, standing by. Inbox is empty. No specialists registered yet.

To watch the live tmux pane instead, attach with `gc session attach mayor`. Detach with `Ctrl-b` then `d` (the tmux prefix sequence). **Do not** type `exit` inside the pane; that kills the session.

## Step 5: Send the first mail

You are addressed as `human` for the purposes of mail. Send the mayor a message that explains the project:

```bash
gc mail send mayor \
  -s "Project kickoff: rss-reader tutorial" \
  -m "We are building an HN-style RSS reader. The rig is rss-reader/. Stack is Bun + Hono + bun:sqlite + hono/html + HTMX. Over the next chapters we will register specialists (backend, then DBA and frontend, then a code reviewer) and ship features through you. For now, just acknowledge and let me know what you would expect to see in the next chapter." \
  --notify
```

`--notify` is what makes this work. Without it the mail bead is written but no recipient nudge is queued, and the mayor sits idle. With `--notify`, the runtime wakes the recipient as soon as the mail bead lands. **Default to `--notify` whenever you mail an agent that might be sitting idle.**

<details>
<summary><strong>Sidebar:</strong> why <code>--notify</code> matters (idle agents and how mail wakes them)</summary>

Claude Code sessions check for new mail only when something triggers a hook. Hooks fire on `SessionStart`, `UserPromptSubmit`, `Stop`, and `PreCompact`. None of those fire on a fully idle session, so mail to an idle agent does not get processed unless something starts a turn.

`--notify` on `gc mail send` (and `gc mail reply`) stamps a follow-up nudge that wakes the recipient as soon as the mail bead is durable. The fixes that made `--notify` reliable were [GH#1370](https://github.com/gastownhall/gascity/issues/1370) and [GH#1404](https://github.com/gastownhall/gascity/pull/1404), both closed.

If you forget `--notify` and the recipient is idle, recover with `gc session submit mayor "Check your inbox"`. Default intent on `submit` wakes idle sessions and queues for in-turn ones; safe in either case. Avoid `--intent interrupt_now` for everyday use; it interrupts mid-turn work.

</details>

## Step 6: Read the reply

The mayor receives the mail, runs through its loop, replies. Watch:

```bash
gc session peek mayor
```

You will see it execute `gc mail check`, `gc mail read <id>`, then `gc mail reply <id> -s "Re: Project kickoff" -m "..."`. Your reply lands in your inbox:

```bash
gc mail inbox human
gc mail read <id>
```

## Step 7: Or just attach and chat

Mail is one way to talk to an agent. The other way, closer to what you are used to, is to attach to its tmux pane and type at it like a normal Claude Code session:

```bash
gc session attach mayor
```

You land inside the mayor's pane, looking at its Claude Code prompt. Type a message, hit return, watch it respond. Detach with `Ctrl-b` then `d`.

This works for **any** agent session, not just the mayor. Once a polecat session has spawned in Part 2 (something like `rss-reader/backend-1`), `gc session attach rss-reader/backend-1` drops you into that pane the same way.

So why use mail at all? Mail is what makes the orchestration shape work. When you mail the mayor, the mayor decides who handles it and routes the work; specialists run, commit, close beads, and the mayor reports back. The trace is durable: every message is a bead, queryable later. If you instead chat directly with each agent, you are doing the routing in your head. Fine for a one-off question, but it skips the part of Gas City that is doing real work.

The pattern that lands well: **drive the project through mail, attach when you want to inspect or steer in the moment.**

## What just happened, mechanically

You wrote a prompt and saved it on disk. You waked a named session, which spawned a Claude Code instance inside a tmux pane managed by the supervisor. The session loaded your prompt as its system message. You sent a mail bead addressed to `mayor`; the runtime nudged the live session, the session's hook fired on next prompt submit, the agent saw a new mail in its check, read it, decided what to do, and used `gc mail reply` to write a new mail bead addressed back to `human`.

Three primitives touched: agents (the mayor is configured at `agents/mayor/prompt.template.md`), sessions (the live `mayor` instance is a named session per `pack.toml`'s `[[named_session]] template = "mayor", mode = "always"`), and mail (every message is itself a small bead, queryable with `bd list`).

## Shape check

- `agents/mayor/prompt.template.md` matches what you wrote.
- `gc prime mayor` returns that prompt verbatim.
- `gc session list` shows `mayor` as awake.
- One mail you sent. One reply from the mayor in your `human` inbox.
- The mayor's reply mentions specialists, the next chapter, or anything else that proves it actually read the project context.

## When your agent goes off-script

- **The mayor "ready" summary never appears.** `gc session peek mayor` is sitting at an empty prompt, meaning the session went idle without acting on the mail. `gc session submit mayor "Check your inbox"` will wake it.
- **The mayor offers to write code anyway.** Reply: "Per your prompt, do not write code yourself. Acknowledge and stand by." The strict-delegator stance reasserts cleanly with one nudge.

In Part 2 we add a backend specialist and let the mayor route a real task to it.
