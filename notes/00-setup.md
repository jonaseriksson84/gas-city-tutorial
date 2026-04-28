# Notes: Part 0, Setup

Raw notes from the test run of Part 0. Source material for `tutorials/00-setup.md` later.

## Environment captured at start

| Tool | Version |
|---|---|
| Bun | 1.3.6 |
| Gas City `gc` | 1.0.0 |
| Beads `bd` | 1.0.3 |
| Claude Code | 2.1.121 |
| Codex | 0.125.0 |
| tmux | 3.6a |

`ANTHROPIC_API_KEY` not set in shell. Claude Code is presumed authenticated via its own login flow.

## Commands run

### Step 1: Initialize the city

```
gc init --provider claude --name rss-tutorial city
```

Output (8-step sequence):

```
[1/8] Creating runtime scaffold
[2/8] Installing hooks (Claude Code)
[3/8] Writing default prompts
[4/8] Writing pack.toml
[5/8] Writing city configuration
Welcome to Gas City!
Initialized city "rss-tutorial" with default provider "claude".
[6/8] Checking provider readiness
[7/8] Registering city with supervisor
Registered city 'rss-tutorial' (/Users/jonaseriksson/code/gas-city-tutorial/city)
Installed launchd service: /Users/jonaseriksson/Library/LaunchAgents/com.gascity.supervisor.plist
[8/8] Waiting for supervisor to start city
```

Step 8 returns silently (prompt comes back) once the supervisor finishes starting the city.

## Observations and surprises

- `gc init --provider claude` is fully non-interactive. Useful for tutorial scripts.
- A launchd service `com.gascity.supervisor.plist` gets installed on first init. This is a per-user daemon that manages all cities. Fine, but worth calling out in the tutorial so readers are not surprised.
- The default minimal city already includes a `dog` agent pool (scaled 0 to 3, all stopped) defined by the `maintenance` system pack at `.gc/system/packs/maintenance/`. Dog is a city-scoped utility worker for housekeeping formulas (shutdown dance, jsonl backup). Tutorial readers will see it in `gc status`; explain briefly so they do not think they broke something.
- The default mayor's prompt is a generalist (plan + dispatch + manage). Our design calls for a strict-delegator mayor. Override happens in Part 1.
- A `mayor` named session is created with `mode = "always"` but starts in `reserved-unmaterialized` state. It does not actually spawn until a session is needed (via `gc session attach mayor` or similar).

## Failure modes encountered

None yet.
