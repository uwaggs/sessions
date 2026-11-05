# Generated from bdb-2027-tutorial.qmd by extract_code.R.
# Edit the deck, not this file. Run it from this folder, or set BDB_DIR.

# ---- Packages ----
library(tidyverse)   # readr, dplyr, tidyr, ggplot2, purrr
library(arrow)       # Parquet + lazy, out-of-memory queries
library(gganimate)   # animations (renders GIFs with gifski)
library(patchwork)   # put ggplots side by side

theme_set(theme_minimal(base_size = 14))
side_cols <- c(Offense = "#0072B2", Defense = "#D55E00")   # Okabe-Ito

# ---- Find the data, locally or on Kaggle ----
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
cache_dir <- Sys.getenv("BDB_CACHE", "bdb_cache")  # Kaggle input is read-only
dir.create(cache_dir, showWarnings = FALSE)
dir.create("figs", showWarnings = FALSE)

# ---- The small tables ----
players <- read_csv(file.path(bdb_dir, "players.csv"))
combine <- read_csv(file.path(bdb_dir, "combine_results.csv"))
games   <- read_csv(file.path(bdb_dir, "games.csv"))
plays   <- read_csv(file.path(bdb_dir, "player_play.csv"), guess_max = 1e5)

# the prompt is about the regular season, and nullified plays didn't count
reg_game_ids <- games |> filter(season_type == "REG") |> pull(game_id)
reg_plays <- plays |>
  filter(game_id %in% reg_game_ids, play_nullified_by_penalty == "N")

c(all = nrow(plays), regular_season = nrow(reg_plays))

# ---- Tracking: convert to Parquet once ----
tracking_dir <- file.path(cache_dir, "game_tracking")

if (!dir.exists(tracking_dir)) {                 # a minute or two, once
  for (yr in 2023:2025) {
    open_dataset(file.path(bdb_dir, str_glue("game_tracking_{yr}.csv")),
                 format = "csv") |>
      write_dataset(file.path(tracking_dir, str_glue("season={yr}")),
                    format = "parquet")
  }
}

tracking <- open_dataset(tracking_dir)   # lazy: nothing is in memory yet
tracking |> count(season) |> collect()

# ---- Pull one play ----
ex_game <- 2026010405
ex_play <- 4313

ex_raw <- tracking |>
  filter(game_id == ex_game, play_id == ex_play) |>
  collect()            # only now does data enter memory

reg_plays |>
  filter(game_id == ex_game, play_id == ex_play) |>
  distinct(play_description) |> pull()

ex_raw |> select(nfl_id, time, x, y, s, a, o, dir, event) |> head(4)

# ---- Frame ids from `time` ----
add_frame_id <- function(tracking) {
  tracking |>
    mutate(frame_id = 1L + as.integer(round(
             10 * as.numeric(time - min(time), units = "secs"))),
           .by = c(game_id, play_id))
}

ex_raw |> add_frame_id() |> filter(!is.na(event)) |> distinct(frame_id, event)

# ---- `standardize_tracking()`: offense always moves right ----
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
  ggplot(aes(x, y, group = nfl_id)) +
  annotate("rect", xmin = 0, xmax = 120, ymin = 0, ymax = 160 / 3,
           fill = NA, colour = "grey60") +
  geom_path(alpha = 0.7) +
  geom_point(data = \(d) slice_max(d, time, by = c(version, nfl_id)), size = 2) +
  facet_wrap(~version, ncol = 1) +
  coord_fixed() +
  labs(x = "x (yards)", y = "y (yards)")

# ---- Sanity check: does `dir` match the motion? ----
ex_std |>
  arrange(nfl_id, frame_id) |>
  mutate(motion_angle = atan2(lead(x) - x, lead(y) - y) * 180 / pi,
         gap = abs((dir - motion_angle + 180) %% 360 - 180),
         .by = nfl_id) |>
  filter(s > 2) |>                 # angles are noise when standing still
  summarise(median_gap_degrees = median(gap, na.rm = TRUE))

# ---- `add_los()`: where is the line of scrimmage? ----
add_los <- function(tracking, plays) {
  los <- plays |>
    distinct(game_id, play_id, .keep_all = TRUE) |>
    mutate(los_x = case_when(
      is.na(yardline_side)             ~ 60,                     # midfield
      yardline_side == possession_team ~ 10 + yardline_number,   # own half
      TRUE                             ~ 110 - yardline_number)) |>  # their half
    select(game_id, play_id, los_x)
  tracking |>
    left_join(los, by = c("game_id", "play_id")) |>
    mutate(x_from_los = x - los_x)
}

ex_play_df <- ex_std |>
  add_los(reg_plays) |>
  left_join(select(reg_plays, game_id, play_id, nfl_id, team_abbr,
                   possession_team, lined_up_position),
            by = c("game_id", "play_id", "nfl_id")) |>
  mutate(side = if_else(team_abbr == possession_team, "Offense", "Defense"))

ex_play_df |>
  filter(event == "ball_snap") |>
  select(side, lined_up_position, x_from_los) |>
  arrange(x_from_los)

# ---- `trim_plays()`: keep the frames that matter ----
trim_plays <- function(tracking,
                       start_events = "ball_snap",
                       end_events = c("pass_forward", "qb_sack", "qb_strip_sack",
                                      "handoff", "run", "qb_kneel", "qb_spike"),
                       frames_after_end = 0) {
  windows <- tracking |>
    filter(!is.na(event)) |>
    distinct(game_id, play_id, frame_id, event) |>
    arrange(frame_id) |>
    summarise(snap_frame = first(frame_id[event %in% start_events]),
              end_frame  = first(frame_id[event %in% end_events &
                                            frame_id > snap_frame]),
              .by = c(game_id, play_id))
  tracking |>
    inner_join(windows, by = c("game_id", "play_id")) |>
    filter(between(frame_id, snap_frame, end_frame + frames_after_end)) |>
    mutate(frames_since_snap = frame_id - snap_frame)
}

ex_play_df |> trim_plays() |> summarise(frames = n(), .by = side)

# ---- A field to draw on ----
geom_field <- function(xlim = c(0, 120)) {
  ticks <- setdiff(11:109, seq(10, 110, 5))
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
    geom_path(data = filter(play_df, frame_id <= frame),
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
                    width = 900, height = 420, units = "px", res = 100,  # units matter
                    renderer = gifski_renderer())                       # when knitting!
anim_save("figs/play_r.gif", play_gif)

# ---- A receiver's NFL route tree: data ----
puka_id <- players |> filter(display_name == "Puka Nacua") |> pull(nfl_id)

puka_routes <- reg_plays |>
  filter(nfl_id == puka_id, !is.na(route_ran), route_ran != "SCREEN") |>
  select(game_id, play_id, nfl_id, route_ran)

puka_tree <- tracking |>
  filter(nfl_id == puka_id) |>
  collect() |>
  inner_join(puka_routes, by = c("game_id", "play_id", "nfl_id")) |>
  add_frame_id() |>
  standardize_tracking(reg_plays) |>
  trim_plays(end_events = "pass_forward") |>          # snap -> throw
  arrange(game_id, play_id, frame_id) |>
  mutate(downfield = x - first(x),
         # flip so + always points toward the sideline he lined up nearest
         toward_sideline = (y - first(y)) * if_else(first(y) < 160 / 6, -1, 1),
         .by = c(game_id, play_id))

n_distinct(puka_tree$play_id, puka_tree$game_id)

# ---- A receiver's NFL route tree: plot ----
keep_routes <- puka_routes |> count(route_ran) |> filter(n >= 20) |> pull(route_ran)

puka_tree |>
  filter(route_ran %in% keep_routes) |>
  ggplot(aes(toward_sideline, downfield, group = interaction(game_id, play_id))) +
  geom_path(alpha = 0.12, colour = "#0072B2") +
  facet_wrap(~route_ran, nrow = 2) +
  coord_fixed(xlim = c(-20, 20), ylim = c(-3, 30)) +
  labs(x = "← toward the middle · yards · toward the sideline →",
       y = "Yards downfield",
       title = "Puka Nacua's NFL routes, snap to throw (2023–25 regular season)")

# ---- Combine tracking: load and tidy ----
drill_aliases <- c(LINE = "LINE_DRILL",                       # names drift by year
                   "PASS_PRO-MIRROR_DRILL"  = "PASS_PRO_MIRROR_DRILL",
                   OVER_THE_SHOULDER_ADJUST = "OVER_SHOULDER_ADJUST",
                   SPEED_OUT_LEFT           = "SPEED_OUT_ROUTE_LEFT")

combine_trk <- read_csv(file.path(bdb_dir, "combine_tracking.csv")) |>
  filter(entity_type == "PLAYER") |>                         # drop the ball
  mutate(drill_name = coalesce(unname(drill_aliases[drill_name]), drill_name)) |>
  arrange(nfl_id, drill_name, attempt, time) |>
  mutate(t = as.numeric(time - first(time), units = "secs"),
         step = sqrt((x - lag(x, default = first(x)))^2 +
                     (y - lag(y, default = first(y)))^2),
         path_length = cumsum(step),                         # don't trust `dis`
         .by = c(event_id, nfl_id, drill_name, attempt))

combine_trk |>
  distinct(drill_type, draft_year, nfl_id) |>
  count(drill_type, draft_year) |>
  pivot_wider(names_from = draft_year, values_from = n, values_fill = 0)

# ---- The 40-yard dash, frame by frame ----
forty_attempts <- combine_trk |>
  filter(drill_name == "FORTY_YARD_DASH") |>
  summarise(tracked_40 = t[path_length >= 40][1],     # first frame past 40 yards
            peak_speed = max(s),                      # yd/s
            .by = c(nfl_id, event_id, attempt))

forty <- forty_attempts |>
  filter(!is.na(tracked_40)) |>
  summarise(tracked_40 = min(tracked_40), peak_speed = max(peak_speed), .by = nfl_id) |>
  inner_join(select(combine, nfl_id, official_40 = forty), by = "nfl_id")

forty |>
  summarise(players = n(),
            mean_gap_s = mean(tracked_40 - official_40, na.rm = TRUE),
            r = cor(tracked_40, official_40, use = "complete.obs"))

# ---- What a 40 looks like ----
fastest <- forty |> slice_min(official_40, n = 1, with_ties = FALSE)
fastest_name <- players$display_name[players$nfl_id == fastest$nfl_id]
mph <- 3600 / 1760                                  # yd/s -> mph

combine_trk |>
  filter(drill_name == "FORTY_YARD_DASH", nfl_id == fastest$nfl_id) |>
  ggplot(aes(t, s * mph, colour = factor(attempt))) +
  geom_line(linewidth = 1.2) +
  geom_vline(data = filter(forty_attempts, nfl_id == fastest$nfl_id),
             aes(xintercept = tracked_40, colour = factor(attempt)), linetype = "dotted") +
  geom_vline(xintercept = fastest$official_40, linetype = "dashed") +
  annotate("text", x = fastest$official_40, y = 4, label = "official time ",
           hjust = 1) +
  scale_colour_manual(values = c("#0072B2", "#E69F00", "#009E73")) +
  labs(x = "Seconds since the clip starts", y = "Speed (mph)", colour = "Attempt",
       title = str_glue("{fastest_name}: official 40 of {fastest$official_40} s"),
       subtitle = "Dotted lines: when the tracked path passes 40 yards")

# ---- Combine routes vs. NFL routes ----
normalize_attempt <- function(d) {
  i <- which(d$path_length >= 3)[1]
  theta <- atan2(d$y[i] - d$y[1], d$x[i] - d$x[1])
  dx <- d$x - d$x[1]
  dy <- d$y - d$y[1]
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
  mutate(toward_sideline = if_else(str_ends(drill_name, "LEFT"), -lateral, lateral))

labels <- puka_combine |>                 # last point of attempt 1 inside the window
  filter(attempt == min(attempt), abs(toward_sideline) < 21, downfield < 33,
         .by = drill_name) |>
  slice_max(t, n = 1, by = drill_name) |>
  mutate(label = str_to_title(str_replace_all(str_remove(drill_name, "_ROUTE"), "_", " ")))

p_combine <- ggplot(puka_combine, aes(toward_sideline, downfield)) +
  geom_path(aes(group = interaction(drill_name, attempt, event_id), colour = drill_name),
            show.legend = FALSE) +
  geom_text(data = labels, aes(label = label), size = 2.6, vjust = -0.4) +
  labs(title = "Combine route drills (vs. air)", y = "Yards downfield",
       x = "Yards (+ = toward sideline)")
p_nfl <- ggplot(puka_tree, aes(toward_sideline, downfield)) +
  geom_path(aes(group = interaction(game_id, play_id)), alpha = 0.05) +
  labs(title = "NFL routes (snap to throw)", x = "Yards (+ = toward sideline)", y = NULL)

(p_combine | p_nfl) & coord_fixed(xlim = c(-25, 25), ylim = c(-3, 35))

# ---- In-game top speed, without loading 22M rows ----
top_speed_file <- file.path(cache_dir, "game_top_speed.parquet")

if (!file.exists(top_speed_file)) {
  tracking |>
    filter(game_id %in% reg_game_ids, s <= 12.5) |>      # > 12.5 yd/s = glitch
    group_by(nfl_id) |>
    summarise(game_top_speed = quantile(s, 0.99),        # robust "top speed"
              n_frames = n()) |>
    collect() |>                                         # arrow did the work
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

link <- forty |>
  inner_join(game_speed, by = "nfl_id") |>
  inner_join(select(players, nfl_id, display_name, nfl_position), by = "nfl_id") |>
  mutate(pos_group = unname(pos_groups[nfl_position]),
         peak_speed_mph = peak_speed * mph,
         game_top_speed_mph = game_top_speed * mph) |>
  filter(n_frames >= 3000,            # at least ~5 minutes of tracked game time
         pos_group != "RB")           # only a couple in the cohort

count(link, pos_group)

# ---- Does Combine speed show up on Sundays? ----
ggplot(link, aes(peak_speed_mph, game_top_speed_mph)) +
  geom_smooth(method = "lm", se = FALSE, colour = "grey40", linewidth = 0.8) +
  geom_point(aes(colour = pos_group), size = 2.2, alpha = 0.85) +
  scale_colour_manual(values = pos_cols) +
  labs(x = "Combine 40: tracked peak speed (mph)",
       y = "NFL games: 99th-percentile speed (mph)", colour = NULL,
       title = "Fast at the Combine, fast on Sundays (mostly)")

# ---- Most of that is position ----
bind_rows(mutate(link, pos_group = "All"), link) |>
  summarise(n = n(),
            r_tracked_peak = cor(peak_speed, game_top_speed),
            r_official_40  = cor(-official_40, game_top_speed, use = "complete.obs"),
            .by = pos_group) |>
  mutate(across(starts_with("r_"), \(r) round(r, 2))) |>
  arrange(desc(n))

