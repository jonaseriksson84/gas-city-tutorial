# Gas City RSS Tutorial: Locked Design

A tutorial series teaching Gas City through building a minimalist Hacker-News-style RSS aggregator. The reader configures agents and steers them; the agents write the app code.

This document captures the design decisions made during the planning session. Read this before drafting any chapter or proposing a structural change.

## Audience

Working developers who use Cursor or Claude Code daily but have never used multi-agent orchestration. Not for AI newcomers. Not for CrewAI or LangGraph veterans.

## App: minimalist Hacker-News-style RSS aggregator

Why this app:

- Periodic feed-fetching is the textbook scheduled-job use case, which gives orders something real to do.
- Frontend, backend, and DB split is natural, which gives specialists distinct lanes.
- SQLite is genuinely the right choice for the use case, not bolted on.
- The reader actually uses the result after, so it is memorable and shareable.

## Stack

Bun, Hono, `bun:sqlite`, `hono/html`, HTMX, `rss-parser`, TypeScript.

Why:

- Bun avoids Node version management and native compile steps. No `node-gyp` for SQLite.
- Hono is Bun-idiomatic and well-trodden by 2026.
- HTMX removes a build step, so agent failures stay legible.
- TypeScript chosen despite an earlier lean toward JS, because the user prefers it. Mitigated by Bun's native TS handling.

## Tutorial shape: hybrid project-driven, 7 parts

Project narrative leads, GC primitives surface as the project demands them. Chapter titles are project verbs ("First contact", "Building the bones"), not primitive names. The 7-part count matches the official tutorials so a contribution back is a clean drop-in.

| # | Part | Concepts surfaced |
|---|---|---|
| 0 | Setup | cities, rigs |
| 1 | First contact | agents, sessions, mail |
| 2 | Building the bones | sling, beads, hooks |
| 3 | Specialists at work | formulas, polecats vs crew, molecules vs wisps |
| 4 | The review loop | inter-agent communication, optional Codex provider swap |
| 5 | Going live | orders (cooldown + cron) |
| 6 | Capstone: ship-it autonomously | synthesis |

## Reader's role

Reader writes Gas City configs (every `agent.toml`, `prompt.template.md`, `formula.toml`, `order.toml`) and shell commands. Agents write the app code. The rig code is throwaway proof-of-life. The city configs are the artifacts the reader keeps.

## Pedagogical curve: progressive scaffolding

| Part | What is given | What reader writes |
|---|---|---|
| 0 | All commands verbatim | Nothing |
| 1 | Mayor's `agent.toml` and prompt verbatim | Nothing |
| 2 | All sling commands, first formula skeleton | Nothing |
| 3 | Backend agent verbatim, frontend agent as fill-in-the-blank | One agent prompt from a template |
| 4 | Reviewer requirements as bullets, example reviewer shown after | Reviewer agent from scratch |
| 5 | One order verbatim, second order from requirements | One order config from scratch |
| 6 | Principle of writing a feature request to the mayor, example shown after | Capstone prompt and post-mortem |

## Non-determinism contract

Stated explicitly in Part 0 and referenced in every chapter:

> Your agents will produce code that differs from mine. Each chapter ends with a *shape check*, not a byte check.

Shape check covers directory layout, route names, schema, and behavior. Each chapter has a "When your agent goes off-script" sidebar with two or three observed failure modes and recovery nudges. Escape hatch: `git checkout chapter-N` in the companion repo.

## Agent roster (5)

- `mayor`: crew, always-on (`mode = "always"`), strict delegator. Receives reader requests, slings to specialists. Prompt explicitly forbids writing code.
- `backend`: polecat. Server, routes, db access.
- `frontend`: polecat. Templates, HTMX, styles.
- `dba`: polecat. Schema, migrations.
- `reviewer`: polecat. Code review. Optionally swapped to Codex on the main path in Part 4.

DBA earns its slot by enabling a real `needs` chain in the formulas chapter: DBA migration must finish before the backend writes routes that touch new columns, and the frontend needs the backend's route shapes to know what to call.

Specialist scoping (`dir` field) is not used. Single-rig setup makes it irrelevant.

## Provider strategy

Claude on the main path. Codex is used for the reviewer in Part 4 to demonstrate provider pluggability. Reader can stay on Claude with a one-line swap noted in the chapter.

## Capstone prompt strategy

Hybrid. Reader gets one tested verbatim prompt as the recommended path, plus a "go off-script" callout. The blog post embeds the actual transcript captured during the test run.

## Companion repo: single repo, tags per chapter

```
gas-city-tutorial/
├── design/                   # this document
├── notes/                    # captured during the test run
├── city/                     # `gc init` populates
├── rss-reader/               # the rig
└── tutorials/                # markdown chapters, written after the test run
```

Tags `chapter-0` through `chapter-6` mark the end-of-chapter state. Reader can `git checkout chapter-N` to recover.

## Markdown is the primary artifact

Every config the reader writes appears verbatim in the markdown. The reader should not need to constantly reference the repo while following the tutorial.

## Output format

Seven separate markdown files. Plain CommonMark. No Jekyll or Mintlify-specific frontmatter. Same files publish to the user's blog (multi-post series) and drop into `docs.gascityhall.com` if accepted as a contribution.

## Prerequisites (what `brew install gastownhall/gascity/gascity` does NOT cover)

- macOS or Linux (or Windows + WSL, with caveat)
- Homebrew
- Bun (`curl -fsSL https://bun.sh/install | bash`)
- Coding agent CLIs: Claude Code on the main path, Codex CLI added in Part 4
- API keys: Anthropic on the main path, OpenAI for Part 4 (Claude fallback noted)
- Roughly $2 to $5 of API credit (rough; will tighten after the test run)
- Familiarity with at least one coding agent

`brew install gastownhall/gascity/gascity` covers tmux, jq, git, dolt, bd, flock automatically.

## Production workflow

Test, then write. Provision a city, run the full 7-chapter sequence end to end first, capture transcripts and screenshots, document observed failure modes, then write all markdown from those notes. Estimate: half a day plus $5 to $15 in API credit.

## Voice and tone

No em dashes. No typical LLM phrasing patterns (delve, leverage, robust, seamless, "imagine if", "in summary", and similar). Applies to tutorial markdown, blog content, and conversational replies on this project.
