**Session:** Intro Night: Build a Team Dashboard & Player Projection <br>
**Date:** October 1, 2026 <br>
**Recording Link:** https://drive.google.com/file/d/1JSAB8Nhy1bcHf1jD68zI7KZO1BxALGpb/view?usp=sharing

# UWAGGS Team Dashboard

Paste a team link from a sports-reference site and get a dashboard. Then pick a player and project their season.

Works with:
- hockey-reference.com
- baseball-reference.com
- basketball-reference.com
- pro-football-reference.com
- fbref.com

## Setup (2 minutes)

1. Install **uv** (a fast Python installer):
   - Mac/Linux: `curl -LsSf https://astral.sh/uv/install.sh | sh`
   - Windows (PowerShell): `powershell -c "irm https://astral.sh/uv/install.ps1 | iex"`
2. In this folder, run:
   ```
   uv run --python 3.12 --with-requirements requirements.txt shiny run --reload app.py
   ```
3. Open the link it prints (usually http://127.0.0.1:8000).

`--reload` means the app refreshes whenever you save a file, so you can edit and see the change right away.

> **Note on fbref / pro-football-reference:** You'll need Chrome installed if you want to use these sites.

## What's in each file

| File | What it does | Should you edit it? |
|---|---|---|
| `sports.py` | Settings for each website: which stats to show and how many games are in a season | **Yes, start here** |
| `model.py` | The player projection model (~40 lines) | **Yes, part 2** |
| `app.py` | Your team's link (`TEAM_URL`, at the top), plus the dashboard layout and charts | **Yes, change the link first** |
| `scrape.py` | Downloads pages and turns them into tables | You can ignore this |

## Things to try

**Part 1: the dashboard**
1. Load your favourite team. Find its page on a sports-reference site, copy the link, and replace `TEAM_URL` at the top of `app.py`. Save, and the app reloads with your team.
2. In `sports.py`, change `headline_stats` to the stats you're interested in seeing.
3. Switch the Table dropdown (e.g. `goalie_stats`, `advanced`, `passing`, `defense`).
4. Find an interesting scatter plot. Who's an outlier?

**Part 2: player projections**
1. Pick a player and look at their projection. Do you agree with it?
2. In `model.py`, try `SEASON_WEIGHTS = [1, 1, 1]` and see how much the projection moves.
3. Try `REGRESSION_GAMES = 0`, then `200`. Which players change the most, and why?
4. Add an age adjustment: young players tend to improve and older players decline.
5. Stretch: compare your projection with basketball-reference's own (the `projection` table on NBA player pages).

## Be nice to these websites!
Sports-reference bans you for an hour if you make more than ~20 requests a minute. The app saves every page it downloads in `cache/` and never downloads the same page twice. A few teams (including the Leafs) are already saved in `snapshots/`, so they work offline too.
