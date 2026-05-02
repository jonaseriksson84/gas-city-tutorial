#!/usr/bin/env bash
#
# CLI overview for the rss-tutorial city while the v1.0.0 dashboard is broken.
# Pairs well with: watch -n 3 ./bin/overview.sh

set -u

CITY=/Users/jonaseriksson/Code/gas-city-tutorial/city
RIG=/Users/jonaseriksson/Code/gas-city-tutorial/rss-reader

hr() { printf '%s\n' "------------------------------------------------------------"; }

hr; echo "SESSIONS (active/creating)"; hr
gc --city "$CITY" session list 2>&1 | grep -v '^warning:' || true
echo

hr; echo "RIG BEADS — OPEN"; hr
(cd "$RIG" && bd list --status=open 2>&1 | grep -v '^warning:') || true
echo

hr; echo "RIG BEADS — RECENTLY CLOSED (last 5)"; hr
(cd "$RIG" && bd list --status=closed 2>&1 | grep -v '^warning:' | head -8) || true
echo

hr; echo "RIG COMMITS (last 5)"; hr
git -C "$RIG" --no-pager log --oneline -5 2>&1 || true
echo

hr; echo "HUMAN INBOX (last 5) — stuck-agent pages land here"; hr
gc --city "$CITY" mail inbox human 2>&1 | grep -v '^warning:' | head -8 || true
echo

hr; echo "MAYOR INBOX (last 5)"; hr
gc --city "$CITY" mail inbox mayor 2>&1 | grep -v '^warning:' | head -8 || true
echo
