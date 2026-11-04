"""
Plotly play animation for the BDB 2027 tracking data.

Adapted from our BDB 2025 visualization.py (github.com/ZekeWeng/BigDataBowl2025),
which was based on Nick Wan's work:
https://www.kaggle.com/code/nickwan/animate-plays-with-plotly-real-no-lies-here

Changes for 2027:
- No football: only the tracked rookies are drawn.
- Expects standardized tracking (offense moves right), so the first-down line is
  los_x + yards_to_go and the offense's own end zone is on the left.
- Column names follow the 2027 files (snake_case, team_abbr instead of club).
- Speed is converted from yd/s (3600 / 1760), not m/s.
- Field markings are drawn once; animation frames only update the player markers.
"""

import numpy as np
import pandas as pd
import plotly.graph_objects as go


COLORS = {
    'ARI':["#97233F","#000000","#FFB612"],
    'ATL':["#A71930","#000000","#A5ACAF"],
    'BAL':["#241773","#000000"],
    'BUF':["#00338D","#C60C30"],
    'CAR':["#0085CA","#101820","#BFC0BF"],
    'CHI':["#0B162A","#C83803"],
    'CIN':["#FB4F14","#000000"],
    'CLE':["#311D00","#FF3C00"],
    'DAL':["#003594","#041E42","#869397"],
    'DEN':["#FB4F14","#002244"],
    'DET':["#0076B6","#B0B7BC","#000000"],
    'GB' :["#203731","#FFB612"],
    'HOU':["#03202F","#A71930"],
    'IND':["#002C5F","#A2AAAD"],
    'JAX':["#101820","#D7A22A","#9F792C"],
    'KC' :["#E31837","#FFB81C"],
    'LA' :["#003594","#FFA300","#FF8200"],
    'LAR':["#003594","#FFA300","#FF8200"],   # 2027 data uses both LA and LAR
    'LAC':["#0080C6","#FFC20E","#FFFFFF"],
    'LV' :["#000000","#A5ACAF"],
    'MIA':["#008E97","#FC4C02","#005778"],
    'MIN':["#4F2683","#FFC62F"],
    'NE' :["#002244","#C60C30","#B0B7BC"],
    'NO' :["#101820","#D3BC8D"],
    'NYG':["#0B2265","#A71930","#A5ACAF"],
    'NYJ':["#125740","#000000","#FFFFFF"],
    'PHI':["#004C54","#A5ACAF","#ACC0C6"],
    'PIT':["#FFB612","#101820"],
    'SEA':["#002244","#69BE28","#A5ACAF"],
    'SF' :["#AA0000","#B3995D"],
    'TB' :["#D50A0A","#FF7900","#0A0A08"],
    'TEN':["#0C2340","#4B92DB","#C8102E"],
    'WAS':["#5A1414","#FFB612"],
}

MPH = 3600 / 1760   # yd/s -> mph
FIELD_WIDTH = 160 / 3


def get_color_similarity(hex1, hex2):
    """
    Distance between two hex colors in RGB space (weighted for human perception).
    """
    def get_rgb(color):
        return tuple(int(color[i:i+2], 16) for i in (1, 3, 5))

    if hex1 == hex2:
        return 0
    rgb1, rgb2 = get_rgb(hex1), get_rgb(hex2)
    rm = 0.5 * (rgb1[0] + rgb2[0])
    r_diff, g_diff, b_diff = (a - b for a, b in zip(rgb1, rgb2))
    return ((2 + rm / 256) * r_diff ** 2 + 4 * g_diff ** 2 +
            (3 - rm / 256) * b_diff ** 2) ** 0.5


def get_color_pairs(team_a, team_b):
    """
    [fill, outline] colors for two teams. If their primary colors are too close,
    team_b switches to its secondary color.
    """
    a, b = COLORS[team_a], COLORS[team_b]
    if get_color_similarity(a[0], b[0]) < 500:
        return {team_a: [a[0], a[1]], team_b: [b[1], b[0]]}
    return {team_a: [a[0], a[1]], team_b: [b[0], b[1]]}


def animate_play(play_df, plays, games, players=None, frame_ms=100):
    """
    Animate one play on a full field, with play/pause buttons and a frame slider.

    Params:
    - play_df: tracking for ONE play after add_frame_id(), standardize_tracking()
      and add_los(), merged with team_abbr and lined_up_position from player_play
      (e.g. ex_play_df in the tutorial)
    - plays: player_play rows (e.g. reg_plays), for down, distance, clock and description
    - games: games.csv, for the home and visitor teams
    - players: players.csv (optional), to show names on hover
    - frame_ms: milliseconds per frame (100 = real time at 10 Hz)

    Returns:
    - A plotly Figure; call .show() on it
    """
    game_id, play_id = play_df.game_id.iloc[0], play_df.play_id.iloc[0]
    info = plays[(plays.game_id == game_id) & (plays.play_id == play_id)].iloc[0]
    game = games[games.game_id == game_id].iloc[0]
    offense = info.possession_team
    defense = game.visitor_team_abbr if offense == game.home_team_abbr else game.home_team_abbr
    color_orders = get_color_pairs(offense, defense)

    df = play_df.sort_values("frame_id")
    if players is not None and "display_name" not in df:
        df = df.merge(players[["nfl_id", "display_name"]], on="nfl_id", how="left")
    if "display_name" not in df:
        df = df.assign(display_name=df.nfl_id.astype(str))

    line_of_scrimmage = df.los_x.iloc[0]
    first_down_marker = (line_of_scrimmage + info.yards_to_go
                         if pd.notna(info.yards_to_go) else None)

    # Static field: drawn once, not in every frame
    data = []
    yard_x = np.arange(20, 110, 10)
    yard_labels = [str(i) for i in list(range(10, 51, 10)) + list(range(40, 9, -10))]
    for y in (5, FIELD_WIDTH - 5):
        data.append(go.Scatter(x=yard_x, y=[y] * len(yard_x), mode="text", text=yard_labels,
                               textfont=dict(size=30, family="Courier New, monospace",
                                             color="#ffffff"),
                               showlegend=False, hoverinfo="none"))

    # End zones: offense's own on the left, the one it's driving toward on the right
    for x_min, team in ((0, offense), (110, defense)):
        data.append(go.Scatter(x=[x_min, x_min, x_min + 10, x_min + 10, x_min],
                               y=[0, FIELD_WIDTH, FIELD_WIDTH, 0, 0],
                               fill="toself", fillcolor=color_orders[team][0], mode="lines",
                               line=dict(color="white", width=3),
                               showlegend=False, hoverinfo="skip"))

    data.append(go.Scatter(x=[line_of_scrimmage] * 2, y=[0, FIELD_WIDTH], mode="lines",
                           line=dict(dash="dash", color="blue"),
                           showlegend=False, hoverinfo="none"))
    if first_down_marker is not None:
        data.append(go.Scatter(x=[first_down_marker] * 2, y=[0, FIELD_WIDTH], mode="lines",
                               line=dict(dash="dash", color="yellow"),
                               showlegend=False, hoverinfo="none"))

    # Players: one trace per team, updated by each animation frame
    def team_trace(team, now):
        team_now = now[now.team_abbr == team]
        hover = [f"{p.display_name} ({p.lined_up_position})<br>nfl_id: {int(p.nfl_id)}"
                 f"<br>Speed: {p.s * MPH:.1f} mph" for p in team_now.itertuples()]
        return go.Scatter(x=team_now.x, y=team_now.y, mode="markers", name=team,
                          marker=dict(color=color_orders[team][0], size=12,
                                      line=dict(width=2, color=color_orders[team][1])),
                          hovertext=hover, hoverinfo="text")

    player_traces = [len(data), len(data) + 1]
    frame_ids = df.frame_id.unique()
    frames, slider_steps = [], []
    for frame_id in frame_ids:
        now = df[df.frame_id == frame_id]
        frames.append(go.Frame(data=[team_trace(offense, now), team_trace(defense, now)],
                               traces=player_traces, name=str(frame_id)))
        slider_steps.append({"args": [[str(frame_id)],
                                      {"frame": {"duration": frame_ms, "redraw": False},
                                       "mode": "immediate", "transition": {"duration": 0}}],
                             "label": str(frame_id), "method": "animate"})
    data += list(frames[0].data)

    updatemenus = [{
        "buttons": [
            {"args": [None, {"frame": {"duration": frame_ms, "redraw": False},
                             "fromcurrent": True, "transition": {"duration": 0}}],
             "label": "Play", "method": "animate"},
            {"args": [[None], {"frame": {"duration": 0, "redraw": False},
                               "mode": "immediate", "transition": {"duration": 0}}],
             "label": "Pause", "method": "animate"},
        ],
        "direction": "left", "pad": {"r": 10, "t": 87}, "showactive": False,
        "type": "buttons", "x": 0.1, "xanchor": "right", "y": 0, "yanchor": "top",
    }]
    sliders = [{
        "active": 0, "yanchor": "top", "xanchor": "left",
        "currentvalue": {"font": {"size": 20}, "prefix": "Frame: ", "visible": True,
                         "xanchor": "right"},
        "transition": {"duration": 0},
        "pad": {"b": 10, "t": 50}, "len": 0.9, "x": 0.1, "y": 0,
        "steps": slider_steps,
    }]

    description = info.play_description
    if len(description) > 115:   # wrap long descriptions onto two lines
        words = description.split(" ")
        description = " ".join(words[:16]) + "<br>" + " ".join(words[16:])

    scale = 10
    fig = go.Figure(
        data=data,
        frames=frames,
        layout=go.Layout(
            autosize=False, width=120 * scale, height=60 * scale + 120,
            xaxis=dict(range=[0, 120], autorange=False, tickmode="array",
                       tickvals=np.arange(10, 111, 5).tolist(), showticklabels=False,
                       showgrid=True, gridcolor="white", zeroline=False),
            yaxis=dict(range=[0, FIELD_WIDTH], autorange=False, showgrid=False,
                       showticklabels=False, zeroline=False),
            plot_bgcolor="#00B140",
            title=(f"{game.visitor_team_abbr} @ {game.home_team_abbr} · "
                   f"Q{info.quarter} {info.game_clock} · "
                   f"{int(info.down)} & {int(info.yards_to_go)}"
                   f"<br><sub>{description}</sub>"),
            updatemenus=updatemenus,
            sliders=sliders,
        ),
    )

    # Down markers on both sidelines
    if first_down_marker is not None:
        for y_val in (0, FIELD_WIDTH):
            fig.add_annotation(x=first_down_marker, y=y_val, text=str(int(info.down)),
                               showarrow=False,
                               font=dict(family="Courier New, monospace", size=16,
                                         color="black"),
                               align="center", bordercolor="black", borderwidth=2,
                               borderpad=4, bgcolor="#ff7f0e", opacity=1)

    # Team names in the end zones
    for x_min, team, angle in ((0, offense, 270), (110, defense, 90)):
        fig.add_annotation(x=x_min + 5, y=FIELD_WIDTH / 2, text=team, showarrow=False,
                           font=dict(family="Courier New, monospace", size=32,
                                     color="white"),
                           textangle=angle)
    return fig
