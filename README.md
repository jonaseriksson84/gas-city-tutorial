# Gas City RSS Tutorial

Companion repo for a seven-part tutorial that teaches Gas City by building a minimal Hacker-News-style RSS aggregator. You write the configs and steer the agents; the agents write the app.

## Start here

The tutorial chapters live in `tutorials/`. Start with `tutorials/00-setup.md`.

## Layout

| Path | What lives here |
|---|---|
| `tutorials/` | The seven chapters. Each is self-contained. |
| `city/` | The Gas City workspace (configs, agent prompts, orders). |
| `rss-reader/` | The rig the agents build. Its own git repo, gitignored here. |
| `design/` | The design doc with rationale for every architectural choice. |
| `notes/` | Raw notes from the test run: observed output, failure modes. |

## Recovery

Tags `chapter-0` through `chapter-6` mark the end-of-chapter state. If you fall behind, check out the matching tag to restore a known-good city config:

```bash
git checkout chapter-N -- city/
```

The chapters are self-contained; you should not need to dig into this repo while following along. It is a recovery aid.

## What you build

A small Bun + Hono app with SQLite storage, FTS5 search, and a daily AI-written digest. Five agents collaborate: a mayor, a backend specialist, a DBA, a frontend specialist, and a code reviewer. Three scheduled jobs handle feed ingestion, database pruning, and digest generation.
