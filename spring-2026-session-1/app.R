library(shiny)
library(tidyverse)

elo_data <- read_csv("eloratings.csv")
fifa_teams <- read_csv("fifa-schedule/teams.csv")
fifa_matches <- read_csv("fifa-schedule/matches.csv")

most_recent_elo <- 
  elo_data %>%
  mutate(
    date = as.Date(date, format = "%m/%d/%Y")
  ) %>% 
  group_by(team) %>% 
  slice_max(date, with_ties = F, n = 1) %>% 
  select(team, rating) %>% 
  mutate(team = str_squish(team))

fifa_teams <- 
  fifa_teams %>% 
  mutate(
    team_name = case_match(
      team_name, 
      "Winner UEFA Playoff A" ~ "Bosnia and Herzegovina",
      "Winner UEFA Playoff B" ~ "Sweden",
      "Winner UEFA Playoff C" ~ "Turkey",
      "Winner UEFA Playoff D" ~ "Czechia",
      "Winner FIFA Playoff 1" ~ "Democratic Republic of Congo",
      "Winner FIFA Playoff 2" ~ "Iraq",
      "USA" ~ "United States",
      "IR Iran" ~ "Iran",
      "Cabo Verde" ~ "Cape Verde",
      "Côte d'Ivoire" ~ "Ivory Coast",
      .default = str_squish(team_name)
    )
  ) 

fifa_teams_with_rankings <- 
  fifa_teams %>% 
  left_join(
    most_recent_elo, by = c("team_name" = "team")
  ) 

complete_schedule <- 
  fifa_matches %>% 
  left_join(
    fifa_teams_with_rankings, by = c("home_team_id" = "id")
  ) %>% 
  left_join(
    fifa_teams_with_rankings, by = c("away_team_id" = "id"), 
    suffix = c("_home", "_away")
  ) %>% 
  filter(stage_id == 1)

elo_prob <- function(rating_a, rating_b) {
  return(1 / (1 + 10^((rating_b - rating_a) / 400)))
}

simulate_group_stage <- function(schedule_data) {
  schedule_data %>% 
    mutate(
      home_win_prob = elo_prob(rating_home, rating_away),
      home_team_wins = rbinom(n(), size = 1, prob = home_win_prob),
      home_team_points = case_when(
        home_team_wins == 1 ~ 3,
        home_team_wins == 0 ~ 0
      ),
      away_team_points = case_when(
        home_team_wins == 1 ~ 0,
        home_team_wins == 0 ~ 3
      )
    )
}

ui <- fluidPage(
  titlePanel("FIFA World Cup 2026 Simulation"),
  sidebarLayout(
    sidebarPanel(
      numericInput(inputId = "num_sims", label = "Number of Simulations", value = 1000, min = 1, max = 10000),
      selectInput(
        inputId = "favourite_team",
        label = "Select Your Favourite Team",
        choices = fifa_teams_with_rankings$team_name
      )
    ),
    mainPanel(
      textOutput("advancing_probability")
    )
  )
)

server <- function(input, output) {
  
  advancing_teams <- reactive({
    n_simulations = input$num_sims
    
    simulations <- 
      map_dfr(
        1:n_simulations, 
        ~ simulate_group_stage(complete_schedule) %>% 
          mutate(simulation_id = .x)
      )
    
    simulated_standings <- 
      simulations %>% 
      select(simulation_id, group = group_letter_home, team = team_name_home, pts = home_team_points) %>% 
      group_by(simulation_id, group, team) %>% 
      summarise(total_points = sum(pts)) %>% 
      group_by(simulation_id, group) %>% 
      arrange(desc(total_points)) %>% 
      mutate(rank = row_number()) %>%
      ungroup()
    
    top_two <- 
      simulated_standings %>% 
      filter(rank <= 2)
    
    best_third <- 
      simulated_standings %>% 
      filter(rank == 3) %>% 
      group_by(simulation_id) %>% 
      arrange(desc(total_points)) %>% 
      slice_head(n = 8) %>% 
      ungroup()
    
    bind_rows(top_two, best_third) %>% 
      count(team, name = "times_advanced") %>% 
      mutate(prob_advance = times_advanced / n_simulations) %>% 
      arrange(desc(prob_advance))
  })
  
output$advancing_probability <- renderText({
  
  paste0("The probability of ", input$favourite_team, " advancing to the knockout stage is: ",
         advancing_teams() %>% filter(team == input$favourite_team) %>% pull(prob_advance) * 100, "%")
})
}
shinyApp(ui = ui, server = server)
