import numpy as np
import pandas as pd
from shiny import App, reactive, render, ui

# ==========================================
# Data Loading and Pre-processing
# ==========================================

def normalize_team_name(series):
    return (
        series.astype(str)
        .str.replace("\xa0", " ", regex=False)
        .str.replace(r"\s+", " ", regex=True)
        .str.strip()
    )


# Read CSVs
elo_data = pd.read_csv("eloratings.csv")
fifa_teams = pd.read_csv("fifa-schedule/teams.csv")
fifa_matches = pd.read_csv("fifa-schedule/matches.csv")

# Get most recent Elo rating per team
elo_data = elo_data.assign(
    date=pd.to_datetime(elo_data["date"], format="%m/%d/%Y", errors="coerce"),
    team_key=lambda df: normalize_team_name(df["team"]),
)

most_recent_elo = (
    elo_data.sort_values("date")
    .drop_duplicates(subset="team_key", keep="last")
    .loc[:, ["team_key", "rating"]]
)

# Team name mapping dictionary
team_name_mapping = {
    "Winner UEFA Playoff A": "Bosnia and Herzegovina",
    "Winner UEFA Playoff B": "Sweden",
    "Winner UEFA Playoff C": "Turkey",
    "Winner UEFA Playoff D": "Czechia",
    "Winner FIFA Playoff 1": "Democratic Republic of Congo",
    "Winner FIFA Playoff 2": "Iraq",
    "USA": "United States",
    "IR Iran": "Iran",
    "Cabo Verde": "Cape Verde",
    "Côte d'Ivoire": "Ivory Coast"
}

# Apply mapping and squish strings
fifa_teams = fifa_teams.assign(
    team_name=lambda df: df["team_name"].replace(team_name_mapping).pipe(normalize_team_name)
)

# Join rankings to teams
fifa_teams_with_rankings = fifa_teams.merge(
    most_recent_elo,
    left_on="team_name",
    right_on="team_key",
    how="left",
).drop(columns=["team_key"])

# Build the complete schedule with ratings
complete_schedule = fifa_matches[fifa_matches["stage_id"] == 1].copy()

# Join home teams
complete_schedule = pd.merge(
    complete_schedule, 
    fifa_teams_with_rankings, 
    left_on="home_team_id", 
    right_on="id", 
    how="left"
)

# Join away teams
complete_schedule = pd.merge(
    complete_schedule, 
    fifa_teams_with_rankings, 
    left_on="away_team_id", 
    right_on="id", 
    suffixes=("_home", "_away"), 
    how="left"
)

# ==========================================
# Simulation Functions
# ==========================================

def elo_prob(rating_a, rating_b):
    return 1 / (1 + 10 ** ((rating_b - rating_a) / 400))

def simulate_group_stage(schedule_data):
    df = schedule_data.copy()
    
    # Calculate probabilities
    df["home_win_prob"] = elo_prob(df["rating_home"], df["rating_away"])
    
    # Simulate games (1 = home win, 0 = away win)
    df["home_team_wins"] = np.random.binomial(n=1, p=df["home_win_prob"])
    
    # Assign points based on results
    df["home_team_points"] = np.where(df["home_team_wins"] == 1, 3, 0)
    df["away_team_points"] = np.where(df["home_team_wins"] == 1, 0, 3)
    
    return df

# ==========================================
# Shiny UI Definition
# ==========================================

app_ui = ui.page_fluid(
    ui.panel_title("FIFA World Cup 2026 Simulation"),
    ui.layout_sidebar(
        ui.sidebar(
            ui.input_numeric(
                "num_sims",
                "Number of Simulations",
                value=1000,
                min=1,
                max=10000
            ),
            ui.input_select(
                "favourite_team",
                "Select Your Favourite Team",
                choices=sorted(fifa_teams_with_rankings["team_name"].dropna().tolist())
            )
        ),
        ui.output_text("advancing_probability")
    )
)

# ==========================================
# Shiny Server Logic
# ==========================================

def server(input, output, session):
    
    @reactive.calc
    def advancing_teams():
        n_simulations = input.num_sims()
        
        # Run all simulations and aggregate them into one DataFrame
        sims = []
        for i in range(1, n_simulations + 1):
            sim = simulate_group_stage(complete_schedule)
            sim["simulation_id"] = i
            sims.append(sim)

        simulations = pd.concat(sims, ignore_index=True)
        
        # Select required columns and group by simulation, group, and team
        simulated_standings = simulations[[
            "simulation_id", "group_letter_home", "team_name_home", "home_team_points"
        ]].copy()
        simulated_standings.columns = ["simulation_id", "group", "team", "pts"]
        
        # Summarise points
        grouped = simulated_standings.groupby(["simulation_id", "group", "team"], as_index=False)["pts"].sum()
        grouped.rename(columns={"pts": "total_points"}, inplace=True)
        
        # Sort and assign rank (replicates arrange(desc) + row_number)
        grouped = grouped.sort_values(by=["simulation_id", "group", "total_points"], ascending=[True, True, False])
        grouped["rank"] = grouped.groupby(["simulation_id", "group"]).cumcount() + 1
        
        # Get Top Two
        top_two = grouped[grouped["rank"] <= 2]
        
        # Get Best Thirds (Top 8 across all groups within each simulation)
        best_third = grouped[grouped["rank"] == 3].copy()
        best_third = best_third.sort_values(by=["simulation_id", "total_points"], ascending=[True, False])
        best_third = best_third.groupby("simulation_id").head(8)
        
        # Combine advancing teams and calculate probabilities
        advancing = pd.concat([top_two, best_third], ignore_index=True)
        
        prob_df = advancing["team"].value_counts().reset_index()
        prob_df.columns = ["team", "times_advanced"]
        prob_df["prob_advance"] = prob_df["times_advanced"] / n_simulations
        
        return prob_df

    @render.text
    def advancing_probability():
        df = advancing_teams()
        team = input.favourite_team()
        
        # Extract the probability for the selected team
        team_data = df[df["team"] == team]
        prob_val = team_data["prob_advance"].values[0] if not team_data.empty else 0.0
        
        return f"The probability of {team} advancing to the knockout stage is: {prob_val * 100:.2f}%"

app = App(app_ui, server)
