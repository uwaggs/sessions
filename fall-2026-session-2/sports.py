# ==========================================
# One entry per website. Edit me!
# ==========================================
# player_table:    which table on the team page lists the players
#                  (you can pick a different one in the app too)
# games_col:       the "games played" column in that table
# season_games:    games in a full season (used for projections)
# headline_stats:  the stat leaders shown at the top of the dashboard
# scatter:         the default x and y stats for the scatter plot
# projection_stat: the default stat to project for a player

SPORTS = {
    "hockey-reference.com": {
        "league": "NHL",
        "player_table": "player_stats",
        "games_col": "GP",
        "season_games": 82,
        "headline_stats": ["PTS", "G", "A", "+/-"],
        "scatter": ["G", "A"],
        "projection_stat": "PTS",
    },
    "baseball-reference.com": {
        "league": "MLB",
        "player_table": "players_standard_batting",
        "games_col": "G",
        "season_games": 162,
        "headline_stats": ["WAR", "HR", "H", "SB"],
        "scatter": ["OBP", "SLG"],
        "projection_stat": "HR",
    },
    "basketball-reference.com": {
        "league": "NBA",
        "player_table": "totals_stats",
        "games_col": "G",
        "season_games": 82,
        "headline_stats": ["PTS", "TRB", "AST", "3P"],
        "scatter": ["AST", "TRB"],
        "projection_stat": "PTS",
    },
    "pro-football-reference.com": {
        "league": "NFL",
        "player_table": "rushing_and_receiving",
        "games_col": "G",
        "season_games": 17,
        "headline_stats": ["Yds", "TD", "Rec", "Receiving Yds"],
        "scatter": ["Yds", "Receiving Yds"],
        "projection_stat": "Receiving Yds",
    },
    "fbref.com": {
        "league": "Soccer",
        "player_table": "stats_standard",
        "games_col": "MP",
        "season_games": 38,
        "headline_stats": ["Gls", "Ast", "G+A", "Min"],
        "scatter": ["Gls", "Ast"],
        "projection_stat": "G+A",
    },
}


def get_sport(url):
    """Find the SPORTS entry for a URL, e.g. 'https://www.fbref.com/...' -> SPORTS['fbref.com']"""
    for domain, settings in SPORTS.items():
        if domain in url:
            return settings
    raise ValueError("Paste a team link from hockey-, baseball-, basketball-, pro-football-reference or fbref.")
