# Gas City RSS Tutorial

Companion repo for a tutorial series that teaches Gas City by building a minimalist Hacker-News-style RSS aggregator. The reader configures agents and steers them; the agents write the app.

## Layout

| Path | What lives here |
|---|---|
| `design/` | The locked design doc. Read this first if you want context on the choices behind the tutorial. |
| `notes/` | Running notes captured during the test run. Raw transcripts, command output, observed failure modes. |
| `city/` | The Gas City workspace. Populated by `gc init` in Part 0. |
| `rss-reader/` | The rig the agents build. Registered with the city via `gc rig add`. |
| `tutorials/` | The seven markdown chapters. Written from `notes/` after the test run completes. |

## Status

Design phase complete. Test run not yet started. No tutorial chapters written.

## How the chapters relate to this repo

Each chapter is self-contained. You should not need to dig into this repo while following along; the markdown holds every config and command verbatim. The repo is a recovery aid only.

Tags `chapter-0` through `chapter-6` mark the end-of-chapter state once each part is verified. If you fall behind during the tutorial, `git checkout chapter-N -- city-reference/` snaps the city configs to a known-good state.
