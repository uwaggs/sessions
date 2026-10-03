import re

import pandas as pd

# ==========================================
# A simple player projection model ("Marcel-lite")
# ==========================================
# Idea: a player's future is mostly like their recent past...
#   1. Look at the last 3 seasons, counting recent seasons more.
#   2. Pull that rate a little toward the team average
#      ("regression to the mean": hot streaks cool off, cold streaks warm up).
#   3. Multiply by how many games they'll likely play.
#
# The real "Marcel" system (by Tom Tango) does the same thing for baseball,
# and it's surprisingly hard to beat. Try changing the numbers below!

SEASON_WEIGHTS = [5, 4, 3]   # most recent season first
REGRESSION_GAMES = 20        # how many games of "team average" to mix in


def clean_career(career, games_col):
    """One row per season, with a numeric 'year' column."""
    career = career.copy()
    career["Season"] = career["Season"].astype(str).str.replace(r"\.0$", "", regex=True)  # 2018.0 -> 2018
    career["year"] = career["Season"].astype(str).str.extract(r"^(\d{4})")[0]
    career = career.dropna(subset=["year", games_col])   # drops "Career" / "162 Game Avg" rows
    career["year"] = career["year"].astype(int)

    # A player traded mid-season shows up on several rows. Keep the row with
    # the most games (that's the season total on sports-reference).
    career = career.sort_values(games_col).drop_duplicates("year", keep="last")
    return career.sort_values("year").reset_index(drop=True)


def project_player(career, stat, games_col, season_games, games_left, team_rate, current_year):
    """
    career:       the player's season-by-season table (from clean_career)
    stat:         which column to project, e.g. "PTS"
    games_left:   games left in the season (0 = season is over, project next season)
    team_rate:    the team's average stat per game (what we regress toward)
    current_year: the season of the team page you loaded, e.g. 2025 for 2025-26
    """
    career = career[career["year"] <= current_year]   # ignore anything after that season
    in_progress = 0 < games_left < season_games
    if not in_progress:
        games_left = season_games  # season over -> project the whole next one

    # ---- Step 1: weighted rate over the last 3 seasons ----
    recent = career.tail(len(SEASON_WEIGHTS)).iloc[::-1]   # most recent first
    weights = SEASON_WEIGHTS[: len(recent)]
    weighted_stat = sum(w * s for w, s in zip(weights, recent[stat]))
    weighted_games = sum(w * g for w, g in zip(weights, recent[games_col]))

    # ---- Step 2: regression to the mean ----
    # Pretend the player also played REGRESSION_GAMES games at the team-average rate.
    rate = (weighted_stat + REGRESSION_GAMES * team_rate) / (weighted_games + REGRESSION_GAMES)

    # ---- Step 3: how many games will they play? ----
    # Share of games played over recent full seasons (injuries, rest days, benchings...)
    full_seasons = career[career["year"] < current_year] if in_progress else career
    availability = (full_seasons[games_col].tail(3) / season_games).clip(upper=1).mean()
    if pd.isna(availability):
        availability = 0.8
    expected_games = games_left * availability

    # ---- Projection ----
    projected_more = rate * expected_games
    this_season = career[career["year"] == current_year]
    so_far = this_season[stat].sum() if in_progress else 0
    total = so_far + projected_more

    # A rough range: how much did their per-game rate bounce around year to year?
    rates = (career[stat] / career[games_col]).tail(5)
    spread = rates.std() * expected_games if len(rates) > 1 else 0.25 * projected_more
    if pd.isna(spread):
        spread = 0.25 * projected_more

    return {
        "label": label_for(career, current_year, in_progress),
        "in_progress": in_progress,
        "so_far": so_far,
        "rate": rate,
        "expected_games": expected_games,
        "projected_more": projected_more,
        "total": total,
        "low": max(so_far, total - spread),
        "high": total + spread,
    }


def label_for(career, current_year, in_progress):
    year = current_year if in_progress else current_year + 1
    example = str(career["Season"].iloc[-1])
    # Match the site's style: "2026-27" for hockey/basketball, "2027" for baseball.
    return f"{year}-{str(year + 1)[-2:]}" if re.match(r"^\d{4}-", example) else str(year)


# TODO ideas:
#   - Change SEASON_WEIGHTS to [1, 1, 1]. Does the projection change a lot?
#   - Set REGRESSION_GAMES to 0, then 200. What happens to a player with 10 games?
#   - Add an age adjustment: young players improve, older players decline.
#     (career["Age"] has their age each season.)
