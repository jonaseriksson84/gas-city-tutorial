# Part 1: First contact

In Part 0 you initialized a city. The supervisor is running, the rig is registered, and the mayor exists as a "reserved" named session. In this chapter we wake the mayor up and have the first conversation with it.

By the end:

- You have written your own mayor prompt.
- You wake the mayor and watch it boot.
- You send it a message about the project. It reads, replies, and waits.

Three Gas City concepts surface here: **agents** (the configured roles), **sessions** (a running instance of an agent), and **mail** (how you and the agents talk to each other).

## Why we replace the default mayor prompt

`gc init` writes a default mayor prompt at `city/agents/mayor/prompt.template.md` that describes a generalist coordinator: plan, dispatch, manage. For this tutorial we want something tighter. Specifically, a **strict delegator**: a mayor that never writes code, never edits the rig, only routes work to specialists and replies to the human. There are two reasons for the strictness.

First, the value of multi-agent orchestration is the lanes. If the mayor reaches into the rig itself when nobody is watching, the lanes blur, and you end up with a one-agent system in disguise. Strict-delegator prompts produce cleaner traces: you can read the rig's git history later and know exactly which specialist did what.

Second, when a mayor is allowed to "just fix this small thing," it has a strong tendency to. Coding agents are good at coding, and the path of least resistance is to do the work. A hard-stop rule in the prompt is the simplest way to keep the role intact.

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

This prompt grows in later chapters as you add specialists and routing patterns. Right now it covers exactly what the mayor needs to do today.

## Step 2: Verify the compiled prompt

```bash
gc prime mayor
```

`gc prime` shows what the agent will actually receive at session start, after any template directives are expanded. Our prompt has no `{{ ... }}` directives, so the output is identical to what you wrote. The exception worth knowing: if you later use `{{ template "..." }}` to include shared snippets, `gc prime` shows the expanded result, which is not the same as `cat`-ing the file.

Re-read the output. If anything looks off, edit the file and run `gc prime` again. There is no reload step needed for prompt edits: the prompt file is read fresh every time a session starts.

## Step 3: Wake the mayor

```bash
gc session wake mayor
```

Expected output:

```
Session rt-18e: wake requested.
```

The session id (`rt-18e` here, yours will differ) is a short random suffix on the city's prefix. You will see these prefixed ids throughout: `rt-` for city-scoped, `rr-` for rig-scoped (in our case the rig is `rss-reader`).

If this command instead errors with `database not initialized: issue_prefix config is missing`, you are hitting [GH#1232](https://github.com/gastownhall/gascity/issues/1232), a v1.0.0 bd init bug where bd silently fails to write its `issue_prefix` config row during city init. Apply the fix directly to the city's bd database via dolt:

```bash
cd .beads/dolt
dolt --use-db hq sql -q "
  INSERT INTO config (\`key\`, value) VALUES ('issue_prefix', 'rt')
    ON DUPLICATE KEY UPDATE value='rt';
  CALL dolt_commit('-Am', 'set issue_prefix');"
cd ../..
```

`hq` is the city's bd database name and `rt` is the city's bead prefix you have been seeing in session ids. After this, retry:

```bash
gc session wake mayor
```

By the time you read this the fix may have shipped, in which case the original error never appears and you can skip the workaround entirely.

## Step 4: Watch the mayor boot

```bash
gc session peek mayor
```

`gc session peek` shows the recent transcript of the named session. The mayor wakes inside its own tmux pane running Claude Code (or whichever provider you configured), reads its prompt, and follows the instructions in step 1 of the loop: `gc mail check`, `gc status`, then it posts a brief "ready" summary like:

> Mayor ready, standing by. Inbox is empty. No specialists registered yet.

If you instead want to watch the live tmux pane, attach with:

```bash
gc session attach mayor
```

Detach with `Ctrl-b` then `d` (the standard tmux prefix sequence). **Do not** type `exit` inside the pane. Exit kills the session.

## Step 5: Send the first mail

You are addressed as `human` for the purposes of mail. Send the mayor a message that explains the project, so it has context for everything that comes next:

```bash
gc mail send mayor \
  -s "Project kickoff: rss-reader tutorial" \
  -m "We are building an HN-style RSS reader. The rig is rss-reader/. Stack is Bun + Hono + bun:sqlite + hono/html + HTMX. Over the next chapters we will register specialists (backend, then DBA and frontend, then a code reviewer) and ship features through you. For now, just acknowledge and let me know what you would expect to see in the next chapter." \
  --notify
```

The `--notify` flag matters. Without it the mail bead is written but no recipient nudge is queued, and the mayor sits idle waiting for input it does not know to fetch. With `--notify`, the runtime queues a wake for the recipient as soon as the mail bead lands. Make `--notify` the default any time you mail an agent that might be sitting idle.

## Step 6: Read the reply

The mayor receives the mail, runs through its loop, and replies. Watch it:

```bash
gc session peek mayor
```

You will see it execute `gc mail check`, `gc mail read <id>`, then `gc mail reply <id> -s "Re: Project kickoff" -m "..."`. Your reply lands in your inbox:

```bash
gc mail inbox human
```

You should see a single unread mail. Open it:

```bash
gc mail read <id>
```

(The `<id>` shows up in the inbox listing.)

Your reply is back. The mayor confirmed it understood the project, acknowledged it has no specialists yet, and outlined what would help in the next chapter (a backend agent for server work).

## Step 7: Or just attach and chat

Mail is one way to talk to an agent. The other way, which is closer to what you are probably used to, is to attach to its tmux pane and type at it like a normal Claude Code session:

```bash
gc session attach mayor
```

You land inside the mayor's tmux pane, looking at its Claude Code prompt. Type a message, hit return, watch it respond. Detach with `Ctrl-b` then `d` (the standard tmux prefix sequence). The mayor keeps running in the background.

This works for **any** agent session, not just the mayor. Once the backend specialist exists in Part 2 and a polecat session has spawned (something like `rss-reader/backend-1` in `gc session list`), `gc session attach rss-reader/backend-1` drops you into that pane the same way. Want to ask a specialist a clarifying question without going through the mayor? Attach and chat. Want to review what the reviewer is looking at in real time? Attach and watch.

So why use mail at all? Mail is what makes the orchestration shape work. When you mail the mayor, the mayor decides who handles it and routes the work; specialists run, commit, close beads, and the mayor reports back. The trace is durable: every message is a bead, every bead is queryable later. If you instead chat directly with each agent, you are doing the routing in your head. That is fine for a one-off question, but it skips the part of Gas City that is doing real work: the orchestration and the audit trail.

The pattern that lands well: **drive the project through mail, attach when you want to inspect or steer in the moment.** If you find yourself attaching all the time, the mayor's prompt probably needs to be tighter, not the mail pattern abandoned.

## What just happened, mechanically

You wrote a prompt and saved it on disk. You waked a named session, which spawned a Claude Code instance inside a tmux pane managed by the supervisor. The session loaded your prompt as its system message. You sent a mail bead addressed to `mayor`; the runtime nudged the live session, the session's hook fired on next prompt submit, the agent saw a new mail in its check, read it, decided what to do, and used `gc mail reply` to write a new mail bead addressed back to `human`.

Three primitives touched: agents (mayor is configured at `agents/mayor/prompt.template.md`), sessions (the live `mayor` instance is a named session because the default city has `[[named_session]] template = "mayor", mode = "always"` in `pack.toml`), and mail (every message is itself a small bead, queryable with `bd list`).

## Shape check

- `agents/mayor/prompt.template.md` matches what you wrote.
- `gc prime mayor` returns that prompt verbatim.
- `gc session list` shows `mayor` as awake (or "active").
- One mail you sent. One reply from the mayor in your `human` inbox.
- The mayor's reply mentions specialists, the next chapter, or anything else that proves it actually read the project context.

## When your agent goes off-script

- **The mayor "ready" summary never appears.** First, confirm `gc session peek mayor` shows real activity (commands being run). If the pane is sitting at an empty prompt, it might have hit the issue where idle sessions do not auto-poll: `gc session submit mayor "Check your inbox"` will wake it. The default intent on `submit` queues for in-turn sessions and wakes idle ones, so it is safe.
- **The reply has the wrong subject (or `gc mail reply` failed).** Subject is required on reply; without `-s "..."` it errors. The prompt teaches this, but the agent may need a turn or two to get it right. If you see it fail, just let the loop run; it will retry.
- **The mayor offers to write code anyway.** Reply with a short reminder of the rule: "Per your prompt, do not write code yourself. Acknowledge and stand by." The strict-delegator stance reasserts cleanly with one nudge.

## Sidebar: idle agents and how mail actually wakes them

Claude Code sessions only check for new mail when something triggers a hook. Hooks fire on `SessionStart`, `UserPromptSubmit`, `Stop`, and `PreCompact`. None of those fire on a fully idle session, so mail addressed to an idle agent does not get processed unless something starts a turn.

`--notify` on `gc mail send` (and `gc mail reply`) is the runtime's solution. The send-side stamps a follow-up nudge that wakes the recipient as soon as the mail bead is durable. The chain of fixes that made `--notify` reliable was [GH#1370](https://github.com/gastownhall/gascity/issues/1370) plus [GH#1404](https://github.com/gastownhall/gascity/pull/1404), both closed. Older notes (and earlier states of `gc`) sometimes claimed `--notify` was unreliable; that was true in an intermediate state and is no longer.

If you ever forget `--notify` on a send and the recipient is idle, recover with:

```bash
gc session submit mayor "Check your inbox"
```

`gc session submit` with default intent tells the runtime to wake an idle session or queue for an in-turn one. Avoid `--intent interrupt_now` for everyday use; it interrupts mid-turn work, which is rude to a working agent.

In Part 2 we add a backend specialist and let the mayor route a real task to it.
