import re
from datetime import date
from urllib.parse import urljoin

import plotly.express as px
import plotly.graph_objects as go
from shiny import App, reactive, render, req, ui
from shinywidgets import output_widget, render_widget

from model import clean_career, project_player
from scrape import fetch_page, get_page_title, get_tables, get_team_record
from sports import get_sport

px.defaults.template = "plotly_white"

# ==========================================
# Your team: paste a team link here!
# ==========================================
# Find your team on hockey-, baseball-, basketball-, pro-football-reference or fbref,
# copy the link from your browser, and paste it between the quotes.

TEAM_URL = "https://www.hockey-reference.com/teams/TOR/2026.html"

# ==========================================
# Load the team (runs once when the app starts)
# ==========================================

SPORT = get_sport(TEAM_URL)       # settings from sports.py
HTML = fetch_page(TEAM_URL)       # the web page
TABLES = get_tables(HTML)         # every table on the page

# Only keep tables that list players (they have links to player pages).
PLAYER_TABLES = [name for name, df in TABLES.items() if "link" in df.columns and "Player" in df.columns]
DEFAULT_TABLE = next((t for t in PLAYER_TABLES if t.startswith(SPORT["player_table"])), PLAYER_TABLES[0])

# ==========================================
# Layout (what you see)
# ==========================================

app_ui = ui.page_sidebar(
    ui.sidebar(
        ui.input_select("table", "Table", choices=PLAYER_TABLES, selected=DEFAULT_TABLE),
        ui.input_select("bar_stat", "Bar chart stat", choices=[]),
        ui.input_select("x_stat", "Scatter: x axis", choices=[]),
        ui.input_select("y_stat", "Scatter: y axis", choices=[]),
        width=320,
    ),
    ui.h2(ui.output_text("team_title")),
    ui.navset_card_underline(
        ui.nav_panel(
            "Team dashboard",
            ui.output_ui("headline_boxes"),
            ui.layout_columns(
                ui.card(ui.card_header("Top 10"), output_widget("bar_chart")),
                ui.card(ui.card_header("Compare two stats"), output_widget("scatter_chart")),
            ),
            ui.card(ui.card_header("All players (click a column to sort)"), ui.output_data_frame("player_table")),
        ),
        ui.nav_panel(
            "Player projection",
            ui.layout_columns(
                ui.input_select("player", "Player", choices=[]),
                ui.input_select("proj_stat", "Stat to project", choices=[]),
                ui.input_numeric("games_left", "Games left in season (0 = season over)", value=0, min=0),
            ),
            ui.layout_columns(
                ui.card(output_widget("projection_chart")),
                ui.card(ui.card_header("How we got this number"), ui.output_ui("projection_text")),
                col_widths=[8, 4],
            ),
            ui.card(ui.card_header("Career stats"), ui.output_data_frame("career_table")),
        ),
    ),
    title="UWAGGS Team Dashboard",
    fillable=False,
)


# ==========================================
# Server (what happens when you click things)
# ==========================================

def server(input, output, session):
    @reactive.calc
    def players():
        """The chosen table, players only (no 'Team Totals' rows)."""
        req(input.table() in TABLES)
        df = TABLES[input.table()]
        return df.dropna(subset=["link"]).reset_index(drop=True)

    def number_columns():
        df = players()
        return [c for c in df.columns if df[c].dtype.kind in "if" and c not in ("Rk", "Age")]

    @reactive.effect
    def _():
        # When the table changes, refresh the stat dropdowns.
        stats, sport = number_columns(), SPORT
        pick = lambda wanted, fallback: wanted if wanted in stats else fallback
        ui.update_select("bar_stat", choices=stats, selected=pick(sport["headline_stats"][0], stats[0]))
        ui.update_select("x_stat", choices=stats, selected=pick(sport["scatter"][0], stats[0]))
        ui.update_select("y_stat", choices=stats, selected=pick(sport["scatter"][1], stats[-1]))
        ui.update_select("player", choices=players()["Player"].tolist())
        ui.update_select("proj_stat", choices=stats, selected=pick(sport["projection_stat"], stats[0]))
        ui.update_numeric("games_left", value=games_left_in_season())

    def games_left_in_season():
        # Record looks like "32-36-14" or "3-0-0": add up the numbers to get games played.
        record = get_team_record(HTML)
        played = sum(int(n) for n in record.split("(")[0].split("-") if n.strip().isdigit())
        return max(SPORT["season_games"] - played, 0)

    # ---------- Team dashboard ----------

    @render.text
    def team_title():
        record = get_team_record(HTML)
        # "2025-26 Toronto Maple Leafs Roster, Stats, ..." -> "2025-26 Toronto Maple Leafs"
        title = re.split(r" Roster| Stats| Statistics", get_page_title(HTML))[0]
        return f"{title}  ·  {record}" if record else title

    @render.ui
    def headline_boxes():
        df = players()
        boxes = []
        for stat in SPORT["headline_stats"]:
            if stat in df.columns and df[stat].notna().any():
                leader = df.loc[df[stat].idxmax()]
                boxes.append(ui.value_box(f"{stat} leader", f"{leader[stat]:g}", leader["Player"]))
        return ui.layout_columns(*boxes)

    @render_widget
    def bar_chart():
        stat = input.bar_stat()
        req(stat in players().columns)
        top10 = players().nlargest(10, stat).sort_values(stat)
        return px.bar(top10, x=stat, y="Player", orientation="h", text=stat)

    @render_widget
    def scatter_chart():
        x, y = input.x_stat(), input.y_stat()
        req(x in players().columns, y in players().columns)
        df = players().copy()
        # Only write names next to the standout players so the chart isn't cluttered.
        standouts = set(df.nlargest(6, x)["Player"]) | set(df.nlargest(6, y)["Player"])
        df["label"] = df["Player"].where(df["Player"].isin(standouts), "")
        fig = px.scatter(df, x=x, y=y, text="label", hover_name="Player", hover_data=[SPORT["games_col"]])
        fig.update_traces(textposition="top center")
        return fig

    @render.data_frame
    def player_table():
        return render.DataGrid(players().drop(columns=["link"]), filters=True)

    # ---------- Player projection ----------

    @reactive.calc
    def career():
        """Download the chosen player's page and find their season-by-season table."""
        row = players()[players()["Player"] == input.player()]
        req(len(row) > 0)
        player_url = urljoin(TEAM_URL, row["link"].iloc[0])
        try:
            tables = get_tables(fetch_page(player_url))
        except Exception as error:
            ui.notification_show(str(error), type="error")
            req(False)

        # Use the matching table on the player page (same name, e.g. "player_stats").
        games_col = SPORT["games_col"]
        base_name = input.table().rstrip("0123456789_")
        for name, df in tables.items():
            if name.startswith(base_name) and "Season" in df.columns and games_col in df.columns:
                return clean_career(df, games_col)
        req(False)

    @reactive.calc
    def projection():
        stat, games_col = input.proj_stat(), SPORT["games_col"]
        req(stat in career().columns, input.games_left() is not None)
        team_rate = players()[stat].sum() / players()[games_col].sum()
        return project_player(career(), stat, games_col, SPORT["season_games"],
                              input.games_left(), team_rate, team_season_year())

    def team_season_year():
        """The season of the team page: '2025-26 Toronto Maple Leafs' -> 2025."""
        found = re.search(r"\b(19|20)\d{2}\b", get_page_title(HTML))
        if found:
            return int(found.group(0))
        today = date.today()  # fbref titles have no year: guess the current season
        return today.year if today.month >= 7 else today.year - 1

    @render_widget
    def projection_chart():
        stat, p, past = input.proj_stat(), projection(), career()
        past = past[past["year"] < int(p["label"][:4])]   # only seasons before the projected one
        fig = go.Figure()
        fig.add_scatter(x=past["Season"].astype(str), y=past[stat], mode="lines+markers", name="Actual")
        fig.add_scatter(
            x=[p["label"]], y=[p["total"]], mode="markers", name="Projected",
            marker=dict(size=14, symbol="star"),
            error_y=dict(type="data", array=[p["high"] - p["total"]], arrayminus=[p["total"] - p["low"]]),
        )
        fig.update_layout(title=f"{input.player()}: {stat} per season", xaxis_title="Season", yaxis_title=stat,
                          yaxis_rangemode="tozero", template="plotly_white")
        return fig

    @render.ui
    def projection_text():
        p, stat = projection(), input.proj_stat()
        lines = [
            f"<b>Projected {stat} for {p['label']}: {p['total']:.0f}</b> (range {p['low']:.0f}-{p['high']:.0f})",
            f"1. Recent seasons, weighted 5/4/3 and pulled toward the team average: <b>{p['rate']:.2f} {stat} per game</b>",
            f"2. Expected games played: <b>{p['expected_games']:.0f}</b> (based on how often they've played lately)",
            f"3. {p['rate']:.2f} x {p['expected_games']:.0f} = <b>{p['projected_more']:.0f}</b> more {stat}",
        ]
        if p["in_progress"]:
            lines.append(f"4. Plus {p['so_far']:.0f} so far this season = <b>{p['total']:.0f}</b>")
        lines.append("<i>Want to change the model? Open model.py.</i>")
        return ui.div(*[ui.p(ui.HTML(line)) for line in lines])

    @render.data_frame
    def career_table():
        return render.DataGrid(career().drop(columns=["link", "year"], errors="ignore"))


app = App(app_ui, server)
