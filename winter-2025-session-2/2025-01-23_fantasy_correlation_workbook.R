setwd("D:/WAGGS/Fantasy Correlation")

library(baseballr)
library(lubridate) # for date seq
library(dplyr) # for bind_rows

#daybat <- bref_daily_batter("2015-08-01", "2015-08-12")

#daybat

regseas_dates = seq(from=ymd("2024-03-28"), to=ymd("2024-04-30"), by="days")
#regseas_dates = seq(from=ymd("2023-03-30"), to=ymd("2023-09-30"), by="days")
Ndays = length(regseas_dates)

for(k in 1:Ndays)
{
  thisday = regseas_dates[k]
  thisdaypks = mlb_game_pks(thisday)

  if(k == 1)
  {
    allpks = thisdaypks
  }
  if(k > 1)
  {
    allpks = bind_rows(allpks, thisdaypks)
    
  }
 
  print(thisday)
  Sys.sleep(5)
}

allpks = data.frame(allpks)


write.csv(allpks, "Game PKs 2024.csv", row.names=FALSE)
###################################################################

gamepks = allpks$game_pk
Ngames = length(gamepks)

for(k in 1:Ngames)
{
  thisgamepk = gamepks[k]
  thisbatorder = mlb_batting_orders(thisgamepk)
  thisbatorder$game_pk = thisgamepk
  
  if(k == 1)
  {
    allbatorders = thisbatorder
  }
  if(k > 1)
  {
    allbatorders = bind_rows(allbatorders, thisbatorder)
    
  }
  
  print(c(k, Ngames))
  Sys.sleep(5)
}

allbatorders = data.frame(allbatorders)
write.csv(allbatorders, "All Batorders 2024.csv", row.names=FALSE)


#mlb_player_game_stats(person_id = 605151, game_pk = 531368)

#############################################################


playerids = allbatorders$id
gameids = allbatorders$game_pk
batorders = allbatorders$batting_order
teamids = allbatorders$teamID
Nids = length(playerids)

for(k in 1:Nids)
{
  thisstats = mlb_player_game_stats(person_id = playerids[k], game_pk = gameids[k])
  thisstats$batting_order = batorders[k]
  thisstats$team_id = teamids[k]
  
  
  if(k == 1)
  {
    allstats = thisstats
  }
  if(k > 1)
  {
    allstats = bind_rows(allstats, thisstats)
    
  }
  
  print(c(k, Nids))
  Sys.sleep(5)
}





write.csv(allstats, "All Stats 2024.csv", row.names=FALSE)



allhits = data.frame(subset(allstats, group == "hitting"))


allhits_mini = allhits[,c("team_id", "player_id", "game_pk", "hits", "home_runs", "stolen_bases", "batting_order")]
head(allhits_mini)





# Average variance overall
var(allhits$hits)


# Average variance within team-game
vars_by_team = numeric(0)
allhits$team_game = allhits$game_pk*1000 + allhits$team_id
tg_list = unique(allhits$team_game)

for(k in 1:length(tg_list))
{
  this_tg_hits = subset(allhits, team_game == tg_list[k])
  vars_by_team[k] = var(this_tg_hits$hits)
}

mean(vars_by_team)



# Correlation 1st batting order, 2nd batting order
bat1 = subset(allhits, batting_order == 1)
bat2 = subset(allhits, batting_order == 2)
cor(bat1$hits,bat2$hits)

# Correlation matrix
hitsmat = matrix(NA, nrow=nrow(allhits)/9, ncol=9)
for(k in 1:9)
{
  hitsmat[,k] = allhits$hits[allhits$batting_order == k]
}

cormat = cor(hitsmat)


# Yahoo! Sports
#  Batting_Stat = c("1B","2B","3B","HR","R","RBI","BB","SB","HBP"),
#Points =  c(2.6, 5.2, 7.8, 10.4, 1.9, 1.9, 2.6, 4.2, 2.6)
allhits$singles = allhits$hits - allhits$home_runs - allhits$doubles - allhits$triples
allhits$fs_yahoo = 2.6*allhits$singles +   5.2*allhits$doubles + 7.8*allhits$triples + 
                  10.4*allhits$home_runs + 1.9*allhits$runs    + 1.9*allhits$rbi +
                   2.6*allhits$base_on_balls + 4.2*allhits$stolen_bases + 
                    2.6*allhits$hit_by_pitch


fsymat =  matrix(NA, nrow=nrow(allhits)/9, ncol=9)
for(k in 1:9)
{
  fsymat[,k] = allhits$fs_yahoo[allhits$batting_order == k]
}

cormat_fsy = cor(fsymat)


# Simplified: 1-2, 2-3, ... , 8-9, 9-1 all the same
dist_idx_mat = matrix(NA, nrow=9, ncol=9)
cor_by_dist_mat = matrix(NA, nrow=9, ncol=9)
for(rowcount in 1:9)
{
  dist_idx_mat[rowcount,] = ((rowcount - 1)*9 + (1:9)*10) %% 81   # [1,2], [2,3], ... [8,9], [9,1]
  dist_idx_mat[9,9] = 81
  cor_by_dist_mat[rowcount,] = cormat_fsy[dist_idx_mat[rowcount,]]
}


avg_cor_by_dist = apply(cor_by_dist_mat, 1, mean)[1:8]


# n=8000 correlations each, TO DO TODO replace with actual N
df_avg_cbd = data.frame(
  dist = 1:8,
  cor = avg_cor_by_dist,
  se = sqrt((1 - avg_cor_by_dist^2)^2/8000)*2)



ggplot(df_avg_cbd, aes(x=dist, y=cor, fill=cor)) + 
  labs(x = "Batting Order Distance", y = "Pearson Correlation") +
  geom_bar(stat="identity", position=position_dodge()) +
  geom_errorbar(aes(ymin=cor-se, ymax=cor+se), width=.2,
                position=position_dodge(.9))









cormat_fsy_for_df = round(cormat_fsy , 2)
diag(cormat_fsy_for_df) = NA #0

df_fsymat = data.frame(
  value = c(cormat_fsy_for_df),
  x = rep(1:9, times=9),
  y = rep(1:9, each=9)
)




ggplot(df_fsymat, aes(x = x, y = y, fill = value)) +
  geom_tile(color = "black") +
  geom_text(aes(label = value), color = "white", size = 4) +
  coord_fixed() + 
  scale_y_reverse() + 
  theme(axis.ticks = element_blank(),
    axis.title.x=element_blank(), axis.title.y=element_blank(), 
    axis.text.x = element_blank(),axis.text.y = element_blank())

# Get official date from allpks to allhits
allhits$officialDate = NA
for(hitcount in 1:nrow(allhits))
{
  thisdate = allpks$officialDate[which(allpks$game_pk == allhits$game_pk[hitcount])[1]]
  allhits$officialDate[hitcount] = thisdate
}




### Box and whisker of outcomes where players are selected at random from
### 9 different teams
### 5 teams, 2-2-2-2-1
### 3 teams, 3-3-3
### 2 teams, 5-4
### 1 team   9

# Let's sample from N teams

for(Nteams in c(1,2,3,5,9))
{
  
if(Nteams == 9){plrs_per_team = c(1,1,1,1,1, 1,1,1,1)}
if(Nteams == 5){plrs_per_team = c(2,2,2,2,1)}
if(Nteams == 3){plrs_per_team = c(3,3,3)}
if(Nteams == 2){plrs_per_team = c(5,4)}
if(Nteams == 1){plrs_per_team = c(9)}
teamlist = unique(allhits$team_id)
#daylist = unique(allhits$officialDate)
daylist = names(table(allhits$officialDate))[as.numeric(table(allhits$officialDate)) >= Nteams*9]

Ndays = length(daylist)
Nruns = 10000
team_scores = rep(NA, Nruns)

for(runcount in 1:Nruns)
{

# Select a day at random
thisdate = sample(x=daylist, size=1)
# Select the teams at random
today_teamlist = unique(allhits$team_id[allhits$officialDate == thisdate])
teams_picked = sample(x=today_teamlist, size=Nteams)
plr_score = numeric(0)

for(team_count in 1:Nteams)
{
  this_team = teams_picked[team_count]
  
  idxlist = which((allhits$team_id == this_team) & (allhits$officialDate == thisdate))
  this_idx = sample(x=idxlist, size=plrs_per_team[team_count])
  
 
  plr_score = c(plr_score, allhits$fs_yahoo[this_idx])
}  
  
team_scores[runcount] = sum(plr_score)

}



this_fs_df = data.frame(
  Nteams = Nteams,
  fantasy_score = team_scores
)

if(Nteams == 1)
{
  all_fs_df = this_fs_df
}

if(Nteams > 1)
{
  all_fs_df = bind_rows(all_fs_df, this_fs_df)
}

}


over125 = c(length(which(all_fs_df$fantasy_score > 100 & all_fs_df$Nteams == 1)), 
            length(which(all_fs_df$fantasy_score > 100 & all_fs_df$Nteams == 2)), 
            length(which(all_fs_df$fantasy_score > 100 & all_fs_df$Nteams == 3)), 
            length(which(all_fs_df$fantasy_score > 100 & all_fs_df$Nteams == 5)), 
            length(which(all_fs_df$fantasy_score > 100 & all_fs_df$Nteams == 9))) / Nruns


boxplot(all_fs_df$fantasy_score ~ all_fs_df$Nteams,
        xlab = )
text(x=1:5, y=max(all_fs_df$fantasy_score), labels=over125)

backup = all_fs_df

all_fs_df$Nteams = as.factor(all_fs_df$Nteams)



ggplot(all_fs_df, aes(x = Nteams, y = fantasy_score)) + 
  geom_boxplot(fill = "dodgerblue1",
               colour = "black",
               alpha = 0.5,
               outlier.colour = "tomato2") +
  annotate("text", x=1:5, y=rep(max(all_fs_df$fantasy_score),5), 
           label=over125) + 
  annotate("text", x=3, y=max(all_fs_df$fantasy_score)*0.9, 
           label="Proportion over 125") +
  labs(x = "Number of Teams", y = "Fantasy Score")




