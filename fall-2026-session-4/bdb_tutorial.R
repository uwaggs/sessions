# Big Data Bowl 2027: Getting Started with Tracking Data & EDA
# UWAGGS & UTSPAN · Fall 2026, session 4
#
# Packages:  install.packages(c("tidyverse", "arrow", "gganimate", "gifski",
#                               "patchwork", "plotly"))
# Data:      run from this folder, or set BDB_DIR (see "Find the data" below).
# RStudio:   the "# ---- ... ----" headers show up in the document outline
#            (Ctrl/Cmd+Shift+O).


# ==== Part 1 · Load data ====

# ---- Packages ----
library(tidyverse)   # readr, dplyr, tidyr, ggplot2, purrr
library(arrow)       # Parquet + lazy, out-of-memory queries
library(gganimate)   # animations (renders GIFs with gifski)
library(patchwork)   # put ggplots side by side

theme_set(theme_minimal(base_size = 14))
side_cols <- c(Offense = "#0072B2", Defense = "#D55E00")   # Okabe-Ito


# ---- Find the data ----
# On Kaggle, generate an API token, then either set
#   export KAGGLE_USERNAME={your_username}
#   export KAGGLE_API_TOKEN={your_key}
# or save it to ~/.kaggle/access_token:
#   mkdir -p ~/.kaggle && echo {your_key} > ~/.kaggle/access_token && chmod 600 ~/.kaggle/access_token
#
# Then download the data once (it's large, no need to rerun):
# system("kaggle competitions download -c nfl-big-data-bowl-2027 -p nfl-big-data-bowl-2027")
# system("unzip -j nfl-big-data-bowl-2027/nfl-big-data-bowl-2027.zip -d nfl-big-data-bowl-2027")

# Returns the first directory that exists, checking in order:
#   1. the BDB_DIR environment variable, if set
#   2. the Kaggle notebook input path
#   3. ../../nfl-big-data-bowl-2027 (two levels up)
#   4. ./nfl-big-data-bowl-2027 (next to this script)
find_bdb_dir <- function() {
  candidates <- c(Sys.getenv("BDB_DIR"),                      # your own override
                  "/kaggle/input/nfl-big-data-bowl-2027",     # Kaggle notebook
                  "../../nfl-big-data-bowl-2027",             # this repo
                  "nfl-big-data-bowl-2027")
  found <- candidates[candidates != "" & dir.exists(candidates)]
  if (length(found) == 0) stop("Can't find the BDB 2027 data: set BDB_DIR")
  found[1]
}

bdb_dir   <- find_bdb_dir()
cache_dir <- Sys.getenv("BDB_CACHE", "bdb_cache")   # Kaggle input is read-only
dir.create(cache_dir, showWarnings = FALSE)
dir.create("figs", showWarnings = FALSE)


# ---- Looking at some tables ----
players <- read_csv(file.path(bdb_dir, "players.csv"), show_col_types = FALSE)          # the 510 prospects
combine <- read_csv(file.path(bdb_dir, "combine_results.csv"), show_col_types = FALSE)  # Combine measurements and testing
games   <- read_csv(file.path(bdb_dir, "games.csv"), show_col_types = FALSE)            # every game in 2023/24/25 (PRE, REG, POST)
plays   <- read_csv(file.path(bdb_dir, "player_play.csv"), guess_max = 1e5,             # one row per prospect per play
                    show_col_types = FALSE)

# `players` is just the 510 prospects' metadata (e.g. their actual names)
players |> arrange(draft_overall_pick) |> head(5)

# `combine` has each player's testing at the Combine. It's sparse: why?
combine |> head(5)

# `games` mixes preseason (PRE), regular season (REG) and postseason (POST)
count(games, season_type)

# A design choice: plays called back by a penalty don't count, so drop them
reg_plays    <- plays |> filter(play_nullified_by_penalty == "N")
reg_game_ids <- unique(reg_plays$game_id)


# ---- Example of looking at a particular player's performance ----
# An intuitive look at how a player's Combine compares with others at his position
combine_w_names <- players |>
  select(nfl_id, display_name) |>
  right_join(combine, by = "nfl_id")

# kind: "low" = lower is better, "high" = higher is better, "size" = neither
combine_tests <- tribble(
  ~test,                   ~label,                  ~kind,
  "forty",                 "40-yard dash (s)",      "low",
  "ten_yd_split",          "10-yard split (s)",     "low",
  "vertical",              "Vertical (in)",         "high",
  "broad_jump",            "Broad jump (in)",       "high",
  "three_cone",            "3-cone (s)",            "low",
  "short_shuttle",         "Short shuttle (s)",     "low",
  "bench_reps",            "Bench (reps)",          "high",
  "combine_weight",        "Weight (lb)",           "size",
  "arm_length",            "Arm length (in)",       "size",
  "ngs_athleticism_score", "NGS athleticism score", "high")

plot_player_vs_position <- function(name, df = combine_w_names, tests = combine_tests) {
  player <- df |> filter(display_name == name) |> slice(1)
  peers  <- df |> filter(combine_position == player$combine_position)

  done <- tests |>                                        # skip tests he didn't do
    mutate(value = map_dbl(test, \(col) player[[col]])) |>
    filter(!is.na(value))

  peer_vals <- peers |>
    select(all_of(done$test)) |>
    pivot_longer(everything(), names_to = "test", values_to = "peer") |>
    filter(!is.na(peer)) |>
    left_join(done, by = "test")

  facets <- peer_vals |>
    summarise(share = if_else(first(kind) == "low",
                              mean(peer > first(value)), mean(peer < first(value))),
              n = n(), .by = c(test, label, kind, value)) |>
    mutate(word  = if_else(kind == "size", "above", "better than"),
           facet = str_glue("{label}\n{as.character(value)} · {word} ",
                            "{scales::percent(share, accuracy = 1)} of {n}"),
           facet = fct_inorder(facet))

  peer_vals <- peer_vals |> left_join(select(facets, test, facet), by = "test")

  ggplot(peer_vals, aes(peer)) +
    geom_histogram(bins = 20, fill = "grey75", colour = "white") +
    geom_vline(data = facets, aes(xintercept = value), colour = "#D55E00", linewidth = 1.2) +
    facet_wrap(~facet, scales = "free", ncol = 3) +
    labs(x = NULL, y = NULL,
         title = str_glue("{name} vs. other {player$combine_position} at the Combine")) +
    theme(axis.text.y = element_blank(), panel.grid = element_blank(),
          strip.text = element_text(size = 10))
}

plot_player_vs_position("Will Anderson")


# ---- Tracking: convert to Parquet once ----
# 2 GB of CSV is slow to re-read. Convert it once to Parquet, a compressed, columnar
# format that both languages read, then query it lazily. 
tracking_dir <- file.path(cache_dir, "game_tracking")

if (!dir.exists(tracking_dir)) {                       # a minute or two, once
  for (yr in 2023:2025) {
    open_dataset(file.path(bdb_dir, str_glue("game_tracking_{yr}.csv")), format = "csv",
                 col_types = schema(event = utf8())) |>  # event is mostly NA: force text
      write_dataset(file.path(tracking_dir, str_glue("season={yr}")), format = "parquet")
  }
}

# `tracking` is a lazy arrow dataset: nothing is in memory until you collect().
# Say what you want first (filter/select), then collect
tracking <- open_dataset(tracking_dir)
tracking |> count(season) |> collect()


# ---- Pull one play ----
# A Week 18 2025 play (HOU vs IND) with 11 tracked rookies, a full-ish picture.
ex_game <- 2026010405
ex_play <- 4313

ex_raw <- tracking |>
  filter(game_id == ex_game, play_id == ex_play) |>
  collect()            # only now does data enter memory

# Davis Mills completes a pass to Jaylin Noel, 13 yards to the IND 28, tackled by
# Camryn Bynum and Zaire Franklin
reg_plays |>
  filter(game_id == ex_game, play_id == ex_play) |>
  distinct(play_description) |> pull()

# event is missing for most rows: it only appears at ball_snap, pass_forward,
# pass_arrived, tackle, ... and is NA otherwise (e.g. presnap)
ex_raw |> select(nfl_id, time, x, y, s, a, o, dir, event)


# ==== Part 2 · Cleaning the tracking data ====

# ---- Anatomy of a tracking row ----
#   x, y   position in yards (end zones are 0–10 and 110–120)
#   s      speed (yd/s)              a    acceleration (yd/s²)
#   dis    distance since the last frame (yd)
#   dir    direction of motion (°)   o    direction the player faces (°)
#   event  ball_snap, pass_forward, tackle, …
# Angles: 0° points to +y, and they increase clockwise.


# ---- Frame ids from `time` ----
# Frames are 0.1 s apart (10 Hz): start the count at the play's earliest
# timestamp, then +1 per 0.1 s elapsed.
add_frame_id <- function(tracking) {
  tracking |>
    mutate(frame_id = 1L + as.integer(round(
             10 * as.numeric(time - min(time), units = "secs"))),
           .by = c(game_id, play_id))
}

# only the frames where an event is labelled, i.e. the key frames of the play
ex_raw |> add_frame_id() |> filter(!is.na(event)) |> distinct(frame_id, event)


# ---- `standardize_tracking()`: offense always moves right ----
# The ngscleanR clean_and_rotate() step. Flip plays so the offense always moves
# toward increasing x. Why? So features line up across plays: e.g. to overlay a
# player's route tree, every route should stem the same way.
standardize_tracking <- function(tracking, plays) {
  dirs <- plays |>
    filter(!is.na(play_direction)) |>
    distinct(game_id, play_id, play_direction)
  tracking |>
    inner_join(dirs, by = c("game_id", "play_id")) |>
    mutate(flip = play_direction == "left",
           x    = if_else(flip, 120 - x, x),
           y    = if_else(flip, 160 / 3 - y, y),
           dir  = if_else(flip, (dir + 180) %% 360, dir),
           o    = if_else(flip, (o + 180) %% 360, o),
           dir_x = sin(dir * pi / 180), dir_y = cos(dir * pi / 180),  # unit vector
           s_x = s * dir_x, s_y = s * dir_y) |>                       # velocity
    select(-flip)
}


# ---- Before and after ----
ex_std <- ex_raw |> add_frame_id() |> standardize_tracking(reg_plays)

bind_rows(Raw = ex_raw, Standardized = ex_std, .id = "version") |>
  arrange(time) |>
  ggplot(aes(x, y, group = nfl_id)) +
  annotate("rect", xmin = 0, xmax = 120, ymin = 0, ymax = 160 / 3,
           fill = NA, colour = "grey60") +
  geom_path(alpha = 0.7, colour = "grey20") +
  geom_point(data = \(d) slice_max(d, time, by = c(version, nfl_id)),
             size = 1.5, colour = "grey10") +
  facet_wrap(~version, ncol = 1) +
  coord_fixed() +
  labs(x = NULL, y = NULL)


# ---- `add_los()`: where is the line of scrimmage? ----
# Helps to know where people line up, e.g. how far off the line a corner plays.
add_los <- function(tracking, plays) {
  los <- plays |>
    distinct(game_id, play_id, .keep_all = TRUE) |>
    mutate(los_x = case_when(
      is.na(yardline_side)             ~ 60,                         # midfield
      yardline_side == possession_team ~ 10 + yardline_number,       # own half
      TRUE                             ~ 110 - yardline_number)) |>  # their half
    select(game_id, play_id, los_x)
  tracking |>
    left_join(los, by = c("game_id", "play_id")) |>
    mutate(x_from_los = x - los_x)
}

roles <- reg_plays |>
  select(game_id, play_id, nfl_id, team_abbr, possession_team, lined_up_position)

ex_play_df <- ex_std |>
  add_los(reg_plays) |>
  inner_join(roles, by = c("game_id", "play_id", "nfl_id")) |>
  mutate(side = if_else(team_abbr == possession_team, "Offense", "Defense"))

ex_play_df |>
  filter(event == "ball_snap") |>
  select(side, lined_up_position, x_from_los) |>
  arrange(x_from_los)


# ---- `trim_plays()`: cutting out frames ----
# The ngscleanR cut_plays() step. Keep the frames from the snap to the throw (or
# sack, handoff, ...). Change the events to get e.g. only presnap frames instead.
END_EVENTS <- c("pass_forward", "qb_sack", "qb_strip_sack",
                "handoff", "run", "qb_kneel", "qb_spike")

trim_plays <- function(tracking, start_events = "ball_snap", end_events = END_EVENTS,
                       frames_after_end = 0) {
  windows <- tracking |>
    filter(!is.na(event)) |>
    distinct(game_id, play_id, frame_id, event) |>
    arrange(frame_id) |>
    summarise(snap_frame = first(frame_id[event %in% start_events]),
              end_frame  = first(frame_id[event %in% end_events &
                                            frame_id > snap_frame]),
              .by = c(game_id, play_id)) |>
    filter(!is.na(snap_frame), !is.na(end_frame))
  tracking |>
    inner_join(windows, by = c("game_id", "play_id")) |>
    filter(between(frame_id, snap_frame, end_frame + frames_after_end)) |>
    mutate(frames_since_snap = frame_id - snap_frame)
}

ex_play_df |> trim_plays() |> count(side)


# ==== Part 3 · Visualization ====

# ---- Making a field ----
geom_field <- function(xlim = c(0, 120)) {
  ticks  <- setdiff(11:109, seq(10, 110, 5))
  hashes <- c(23.36667, 29.96667)
  list(
    annotate("rect", xmin = 0, xmax = 120, ymin = 0, ymax = 160 / 3, fill = "#eef3ea"),
    annotate("rect", xmin = c(0, 110), xmax = c(10, 120), ymin = 0, ymax = 160 / 3,
             fill = "grey85"),
    annotate("segment", x = seq(10, 110, 5), xend = seq(10, 110, 5),
             y = 0, yend = 160 / 3, colour = "grey70"),
    annotate("segment", x = rep(ticks, 2), xend = rep(ticks, 2),
             y = rep(hashes, each = length(ticks)) - 0.4,
             yend = rep(hashes, each = length(ticks)) + 0.4, colour = "grey70"),
    annotate("text", x = seq(20, 100, 10), y = 5, colour = "grey50", size = 4,
             label = c(10, 20, 30, 40, 50, 40, 30, 20, 10)),
    annotate("rect", xmin = 0, xmax = 120, ymin = 0, ymax = 160 / 3,
             fill = NA, colour = "grey40"),
    coord_fixed(xlim = xlim, ylim = c(0, 160 / 3), expand = FALSE),
    theme_void()
  )
}

# zoom to the action, but show at least `min_width` yards of field
play_xlim <- function(x, min_width = 60) {
  half <- max(diff(range(x)) / 2 + 5, min_width / 2)
  mean(range(x)) + c(-half, half)
}


# ---- `plot_play()`: one frame, with trails ----
plot_play <- function(play_df, frame = max(play_df$frame_id), arrow_len = 2.5) {
  now <- filter(play_df, frame_id == frame)
  los <- play_df$los_x[1]
  ggplot() +
    geom_field(xlim = play_xlim(play_df$x)) +
    annotate("segment", x = los, xend = los, y = 0, yend = 160 / 3, linetype = "dashed") +
    geom_path(data = filter(play_df, frame_id <= frame) |> arrange(frame_id),
              aes(x, y, group = nfl_id, colour = side), alpha = 0.35) +
    geom_segment(data = now, aes(x, y, xend = x + arrow_len * dir_x,
                                 yend = y + arrow_len * dir_y, colour = side),
                 arrow = arrow(length = unit(0.08, "inches"))) +
    geom_point(data = now, aes(x, y, fill = side), shape = 21, size = 4, colour = "white") +
    geom_text(data = now, aes(x, y + 1.7, label = lined_up_position), size = 2.6) +
    scale_colour_manual(values = side_cols, aesthetics = c("colour", "fill")) +
    labs(colour = NULL, fill = NULL)
}

throw_frame <- ex_play_df |> filter(event == "pass_forward") |> pull(frame_id) |> first()
plot_play(ex_play_df, frame = throw_frame)


# ---- Animate the play ----
# Plenty of ways to animate. Animations are great for bringing up specific plays
# to illustrate your point.
los <- ex_play_df$los_x[1]
anim <- ggplot(ex_play_df) +
  geom_field(xlim = play_xlim(ex_play_df$x)) +
  annotate("segment", x = los, xend = los, y = 0, yend = 160 / 3, linetype = "dashed") +
  geom_point(aes(x, y, fill = side, group = nfl_id),
             shape = 21, size = 5, colour = "white") +
  scale_fill_manual(values = side_cols) +
  labs(fill = NULL, title = "Frame {round(frame_time)}") +
  transition_time(frame_id)

play_gif <- animate(anim, nframes = n_distinct(ex_play_df$frame_id), fps = 10,
                    width = 900, height = 420, units = "px", res = 100,
                    renderer = gifski_renderer())
anim_save("figs/play_r.gif", play_gif)
play_gif             # shows in the RStudio viewer


# ---- Alternative: interactive Plotly animation ----
# The python notebook I use, uses bdb_viz.animate_play() which is from our BDB24 submission done in python
#This is a lighter R version: play/pause, a frame slider, and name/position/speed on hover.
if (requireNamespace("plotly", quietly = TRUE)) {
  hover_df <- ex_play_df |>
    left_join(select(players, nfl_id, display_name), by = "nfl_id") |>
    mutate(label = str_glue("{display_name} ({lined_up_position})<br>",
                            "{round(s * 3600 / 1760, 1)} mph")) |>
    arrange(frame_id)

  plotly::plot_ly(hover_df, x = ~x, y = ~y, frame = ~frame_id, ids = ~nfl_id,
                  color = ~side, colors = side_cols, text = ~label, hoverinfo = "text",
                  type = "scatter", mode = "markers",
                  marker = list(size = 13, line = list(color = "white", width = 1))) |>
    plotly::layout(
      xaxis = list(range = play_xlim(hover_df$x), title = "", zeroline = FALSE),
      yaxis = list(range = c(0, 160 / 3), title = "", scaleanchor = "x", zeroline = FALSE),
      plot_bgcolor = "#eef3ea",
      shapes = list(list(type = "line", x0 = los, x1 = los, y0 = 0, y1 = 160 / 3,
                         line = list(dash = "dash", color = "black", width = 1)))) |>
    plotly::animation_opts(frame = 100, transition = 0, redraw = FALSE)
} else {
  message("install.packages('plotly') for the interactive version")
}


# ---- Example: a receiver's NFL route tree ----
# Puka Nacua (2023, pick 177) ran 1,300+ tracked routes. Here they are from the
# snap to the throw, relative to where he lined up.
puka_id <- players |> filter(display_name == "Puka Nacua") |> pull(nfl_id)

# every play where he ran a route (drop screens and missing routes)
puka_routes <- reg_plays |>
  filter(nfl_id == puka_id, !is.na(route_ran), route_ran != "SCREEN") |>
  select(game_id, play_id, nfl_id, route_ran)

puka_tree <- tracking |>
  filter(nfl_id == puka_id) |>
  collect() |>                                             # all of Puka's tracking
  inner_join(puka_routes, by = c("game_id", "play_id", "nfl_id")) |>  # route plays only
  add_frame_id() |>
  standardize_tracking(reg_plays) |>
  trim_plays(end_events = "pass_forward") |>               # snap -> throw
  arrange(game_id, play_id, frame_id) |>
  mutate(downfield = x - first(x),
         # flip so + always points toward the sideline he lined up nearest; without
         # this, routes from the two sides are mirror images of each other
         toward_sideline = (y - first(y)) * if_else(first(y) < 160 / 6, -1, 1),
         .by = c(game_id, play_id))

# number of plays where he ran a route
puka_tree |> distinct(game_id, play_id) |> nrow()


# ---- Plotting Puka's route tree ----
keep_routes <- puka_routes |> count(route_ran) |> filter(n >= 20) |> pull(route_ran)

puka_tree |>
  filter(route_ran %in% keep_routes) |>
  ggplot(aes(toward_sideline, downfield, group = interaction(game_id, play_id))) +
  geom_path(alpha = 0.12, colour = "#0072B2", linewidth = 0.4) +
  facet_wrap(~route_ran, nrow = 2) +
  coord_fixed(xlim = c(-20, 20), ylim = c(-3, 30)) +
  labs(x = "← toward the middle · yards · toward the sideline →",
       y = "Yards downfield",
       title = "Puka Nacua's NFL routes, snap to throw (2023–25 regular season)")

# What else would make sense to visualize?
#  * how long each route takes to develop (his average speed vs. time since the snap)
#  * success rate by route (separation, catches, ...): a report card per route
#  * game state (time, score) when he runs each route


# ==== Part 4 · The Combine ====

# ---- Combine tracking: load and tidy ----
# Drill names are inconsistent across seasons, so map them to one name each
drill_aliases <- c(LINE                     = "LINE_DRILL",
                   "PASS_PRO-MIRROR_DRILL"  = "PASS_PRO_MIRROR_DRILL",
                   OVER_THE_SHOULDER_ADJUST = "OVER_SHOULDER_ADJUST",
                   SPEED_OUT_LEFT           = "SPEED_OUT_ROUTE_LEFT")

# players only (no ball); then, within each attempt, the time since it started
# and the distance travelled so far
combine_trk <- read_csv(file.path(bdb_dir, "combine_tracking.csv"), show_col_types = FALSE) |>
  filter(entity_type == "PLAYER") |>                         # drop the ball
  mutate(drill_name = coalesce(unname(drill_aliases[drill_name]), drill_name)) |>
  arrange(nfl_id, drill_name, attempt, time) |>
  mutate(t = as.numeric(time - first(time), units = "secs"),
         step = sqrt((x - lag(x, default = first(x)))^2 +
                     (y - lag(y, default = first(y)))^2),
         path_length = cumsum(step),
         .by = c(event_id, nfl_id, drill_name, attempt))

# players taking part in each drill type, by year (e.g. 138 ran a tracked 40 in 2023)
combine_trk |>
  distinct(drill_type, draft_year, nfl_id) |>
  count(drill_type, draft_year) |>
  pivot_wider(names_from = draft_year, values_from = n, values_fill = 0)


# ---- What a 40 looks like ----
# fastest official 40 among players with tracked 40 attempts
dash <- combine_trk |> filter(drill_name == "FORTY_YARD_DASH")
fastest <- combine |>
  filter(nfl_id %in% dash$nfl_id) |>
  slice_min(forty, n = 1, with_ties = FALSE)
fastest_name <- players$display_name[players$nfl_id == fastest$nfl_id]
mph <- 3600 / 1760                                   # yd/s -> mph

dash |>
  filter(nfl_id == fastest$nfl_id) |>
  mutate(t_start = min(t[s > 1]), .by = attempt) |>  # clock starts once he's moving
  ggplot(aes(t - t_start, s * mph, colour = factor(attempt))) +
  geom_line(linewidth = 1.2) +
  geom_vline(xintercept = fastest$forty, linetype = "dashed") +
  annotate("text", x = fastest$forty, y = 4, label = "official time ", hjust = 1) +
  scale_colour_manual(values = c("#0072B2", "#E69F00", "#009E73"),
                      labels = \(a) paste("Attempt", a)) +
  labs(x = "Seconds since he starts moving", y = "Speed (mph)", colour = NULL,
       title = str_glue("{fastest_name}: official 40 of {fastest$forty} s"))


# ---- Combine routes vs. NFL routes ----
# Normalize each Combine attempt: start at (0, 0), then rotate so the first 3 yards
# of the stem point straight up.
normalize_attempt <- function(d) {
  d <- arrange(d, t)
  i <- which(d$path_length >= 3)[1]
  if (is.na(i)) i <- 1
  dx <- d$x - d$x[1]
  dy <- d$y - d$y[1]
  theta <- atan2(dy[i], dx[i])
  mutate(d, downfield = dx * cos(theta) + dy * sin(theta),
            lateral   = dx * sin(theta) - dy * cos(theta))   # + = runner's right
}

puka_combine <- combine_trk |>
  filter(nfl_id == puka_id, str_detect(drill_name, "ROUTE|FADE")) |>
  group_by(drill_name, attempt, event_id) |>
  group_modify(\(d, key) normalize_attempt(d)) |>
  ungroup() |>
  # LEFT/RIGHT in a drill name is the side he lines up on (a Slant Left breaks
  # to his right), so we can put both panels on the same "toward sideline" axis
  mutate(toward_sideline = if_else(str_ends(drill_name, "LEFT"), -lateral, lateral),
         drill = str_to_title(str_replace_all(str_remove(drill_name, "_ROUTE"), "_", " ")))

p_combine <- ggplot(puka_combine, aes(toward_sideline, downfield)) +
  geom_path(aes(group = interaction(drill_name, attempt, event_id), colour = drill),
            linewidth = 0.8) +
  labs(title = "Combine route drills (vs. air)", colour = "Combine drill",
       x = "Yards (+ = toward sideline)", y = "Yards downfield")
p_nfl <- ggplot(puka_tree, aes(toward_sideline, downfield)) +
  geom_path(aes(group = interaction(game_id, play_id)), alpha = 0.05, colour = "grey20") +
  labs(title = "NFL routes (snap to throw)", x = "Yards (+ = toward sideline)", y = NULL)

(p_combine | p_nfl) +
  plot_layout(guides = "collect") &
  coord_fixed(xlim = c(-25, 25), ylim = c(-3, 35)) &
  theme(legend.position = "bottom", legend.text = element_text(size = 8)) &
  guides(colour = guide_legend(ncol = 4, title.position = "top"))

# LEFT/RIGHT in the drill names is the side the receiver lines up on, not the
# direction of the break; that was inferred from the traces, which is why you plot
# before you trust a label. Combine routes are run against air and continue past
# the catch; the NFL routes stop at the throw.


# ==== Part 5 · A first Combine → NFL link ====

# ---- In-game top speed ----
# Do 40 times reflect a player's real game speed? Get each player's top speed in
# games. 
top_speed_file <- file.path(cache_dir, "game_top_speed.parquet")

if (!file.exists(top_speed_file)) {
  speeds <- tracking |>
    filter(game_id %in% reg_game_ids) |>
    select(nfl_id, s) |>
    collect()
  speeds |>
    summarise(game_top_speed = quantile(s, 0.99, names = FALSE),  # robust "top speed":
              n_frames = n(), .by = nfl_id) |>                     # there are tracking glitches
    write_parquet(top_speed_file)
}
game_speed <- read_parquet(top_speed_file)


# ---- Join the Combine to Sundays ----
pos_groups <- c(WR = "WR", TE = "TE", RB = "RB", FB = "RB",
                CB = "DB", SS = "DB", FS = "DB", DB = "DB",
                OLB = "LB", ILB = "LB", MLB = "LB",
                DE = "DL", DT = "DL", NT = "DL", G = "OL", T = "OL", C = "OL")
pos_cols <- c(WR = "#E69F00", DB = "#56B4E9", TE = "#009E73",
              LB = "#CC79A7", DL = "#D55E00", OL = "#0072B2")

# one row per player: top speed in any tracked 40 attempt + official 40 time
forty <- dash |>
  summarise(peak_speed = max(s), .by = nfl_id) |>                 # yd/s
  inner_join(select(combine, nfl_id, official_40 = forty), by = "nfl_id")

# add in-game top speed; keep players with 3000+ frames (5+ minutes) of game tracking
link <- forty |>
  inner_join(game_speed, by = "nfl_id") |>
  inner_join(select(players, nfl_id, display_name, nfl_position), by = "nfl_id") |>
  mutate(pos_group = unname(pos_groups[nfl_position]),
         peak_speed_mph = peak_speed * mph,
         game_top_speed_mph = game_top_speed * mph) |>
  filter(n_frames >= 3000,
         pos_group != "RB")           # only one RB, so leave them out for now

count(link, pos_group, sort = TRUE)
link |> head(5)


# ---- Does Combine speed matter in actual games? ----
ggplot(link, aes(peak_speed_mph, game_top_speed_mph)) +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE, colour = "grey40",
              linewidth = 0.8) +
  geom_point(aes(colour = pos_group), size = 2.2, alpha = 0.85) +
  scale_colour_manual(values = pos_cols) +
  labs(x = "Combine 40: tracked peak speed (mph)",
       y = "NFL games: 99th-percentile speed (mph)", colour = NULL,
       title = "Fast at the Combine, fast on Sundays (mostly)")

# same plot on equal axes, with the "same speed in games as at the Combine" line
lims <- c(8, 25)
ggplot(link, aes(peak_speed_mph, game_top_speed_mph)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = "dashed") +
  annotate("text", x = 24.6, y = 24.2, label = "same speed in games\nas at the Combine",
           hjust = 1, vjust = 1, angle = 45, size = 3, colour = "grey45") +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE, colour = "grey25",
              linewidth = 0.8) +
  geom_point(aes(colour = pos_group), size = 2.2, alpha = 0.85) +
  scale_colour_manual(values = pos_cols) +
  coord_equal(xlim = lims, ylim = lims) +
  labs(x = "Combine 40: tracked peak speed (mph)",
       y = "NFL games: 99th-percentile speed (mph)", colour = NULL,
       title = "Fast at the Combine, fast on Sundays (mostly)")

# the official (laser) 40 time instead of the tracked peak speed
link |>
  filter(!is.na(official_40)) |>
  ggplot(aes(official_40, game_top_speed_mph)) +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE, colour = "grey40",
              linewidth = 0.8) +
  geom_point(aes(colour = pos_group), size = 2.2, alpha = 0.85) +
  scale_colour_manual(values = pos_cols) +
  scale_x_reverse() +                               # faster (lower) times on the right
  labs(x = "Combine: official 40 time (s)  →  faster",
       y = "NFL games: 99th-percentile speed (mph)", colour = NULL)


# ---- Why split by position? ----
# The pooled r looks strong but mostly connects position clusters: linemen are slow
# at the Combine and don't sprint on Sundays; receivers are fast at both. The real
# question is within a position. So compute the correlations per position group:
#   r_tracked_peak: top speed from the tracking data in the 40
#   r_official_40:  the official 40 time, negated so that faster = positive
bind_rows(mutate(link, pos_group = "All"), link) |>
  summarise(n = n(),
            r_tracked_peak = cor(peak_speed, game_top_speed),
            r_official_40  = cor(-official_40, game_top_speed, use = "complete.obs"),
            .by = pos_group) |>
  mutate(across(starts_with("r_"), \(r) round(r, 2))) |>
  arrange(desc(n))

# Is this a submission? No! It's a way to get familiar with the data. Look at past
# BDB projects for ideas on visualizations, formatting and thesis, and cite them.

