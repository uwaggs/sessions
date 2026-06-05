# Get the transfers for everyone


#devtools::install_github("JaseZiv/worldfootballR") # Recommended based on how much faster it updates compared to CRAN

library(worldfootballR)
library(stringr)

all_league_urls = read.csv("main_comp_seasons.csv")

all_league_urls = subset(all_league_urls, season_start_year >= 2000)


for(k in 1:nrow(all_league_urls))
{
  
  this_league_url = all_league_urls$comp_url[k]
  this_year = all_league_urls$season_start_year[k]
  
  
  league_team_urls = tm_league_team_urls(start_year = this_year, league_url = this_league_url)
  

  
  if(k == 1)
  {
    all_team_urls = league_team_urls
  }
  if(k > 1)
  {
    all_team_urls = c(all_team_urls, league_team_urls)
  }
  
  print(k)
  print(this_league_url)
  print(this_year)
  Sys.sleep(20)
}

writeLines(all_team_urls, "All Team URLS 2026-05-16.csv")


############################################################

library(rvest)


year_list = as.character(2024:2000)

for(yearcount in 1:length(year_list))
{

# Let's start with only 2024
  
  all_team_urls = readLines("All Team URLS 2026-05-16.csv")
  all_team_urls = all_team_urls[str_detect(all_team_urls, paste0(year_list[yearcount],"$"))]
  
for(k in 1:length(all_team_urls))
{
  
  this_team_url = all_team_urls[k]
  
  
  htmltext = read_html(all_team_urls[k]) 
  detailstext = htmltext |>
    html_element("div") |> 
    html_text2()
  
  longtext = unlist(str_split(detailstext, "\n"))
  isgood = !any(str_detect(longtext, "Ital|France|Saudi|rankfurt|darmstad"))
  Sys.sleep(5)
  
  if(!isgood)
  {
    print("Skipping because issue with tm_team_transfers")
  }
  
  if(isgood)
  {
  df_this_team_transfers = try(tm_team_transfers(this_team_url))
  if(!is.data.frame(df_this_team_transfers))
   {
    df_this_team_transfers = subset(df_all_team_transfers, player_position == "ALL FALSE")
    }
  }
  
  if(k == 1){df_all_team_transfers = df_this_team_transfers}
  
  if(k > 1 &  !is.null(nrow(df_this_team_transfers)))
  {
    df_all_team_transfers = rbind(df_all_team_transfers, df_this_team_transfers)
    df_this_team_transfers = subset(df_this_team_transfers, player_position == "ALL FALSE")
    Sys.sleep(15)
  }
  
  print(k)
  print(this_team_url)
  print(year_list[yearcount])


} # end of for each year


df_all_team_transfers$player_id = str_extract(df_all_team_transfers$player_url, "[0-9]+$")
df_all_team_transfers$player_age = as.numeric(df_all_team_transfers$player_age)

df_all_team_transfers$log_fee = log(df_all_team_transfers$transfer_fee + 1)


filename = paste0("All Team Transfers",year_list[yearcount],".csv")
write.csv(df_all_team_transfers, filename, row.names=FALSE)
}








#############################################

df_player_trans = read.csv("All Players Age 35 Transfer History.csv")
df_player_trans = subset(df_player_trans, transfer_date < "2024-07-01")
df_team_trans = read.csv("All Team Transfers 2024.csv")
df_team_trans = subset(df_team_trans, player_age >= 35)


player_name_list = unique(df_player_trans$player_name)

df_player_trans$current_team = df_player_trans$team_to[1]

# First add the current team for name disambiguation
for(k in 2:nrow(df_player_trans))
{
  if(df_player_trans$player_name[k] == df_player_trans$player_name[k-1])
  {
    df_player_trans$current_team[k] = df_player_trans$current_team[k-1]
  }
  
  if(df_player_trans$player_name[k] != df_player_trans$player_name[k-1])
  {
    df_player_trans$current_team[k] = df_player_trans$team_to[k]
  }
}


library(stringr)
df_team_trans$team_name = str_replace(df_team_trans$team_name, " FC$", "")
df_team_trans$player_id = str_extract(df_team_trans$player_url, "[0-9]+$")

df_player_trans$player_url = ""
df_player_trans$player_id = 0
df_player_trans$player_age_now = 0



# Next, get the URLs and IDs of the players
for(k in 1:nrow(df_team_trans))
{
  thisname = df_team_trans$player_name[k]
  thisteam = df_team_trans$team_name[k]
  idx = which(df_player_trans$player_name == thisname & df_player_trans$current_team == thisteam)
  
  df_player_trans$player_url[idx] = df_team_trans$player_url[k]
  df_player_trans$player_id[idx] = df_team_trans$player_id[k]
  df_player_trans$player_age_now[idx] = df_team_trans$player_age[k]
}

# Next get the age at the time of each trade
df_player_trans$player_age_now = as.numeric(df_player_trans$player_age_now)
df_player_trans = subset(df_player_trans, player_age_now > 0)
df_player_trans$player_age = 0



for(k in 1:nrow(df_player_trans))
{
  age_ago = as.numeric(difftime("2024-07-01", df_player_trans$transfer_date[k], units="days"))/365
  df_player_trans$player_age[k] = df_player_trans$player_age_now[k] - age_ago
}



#### Now model curves


df = subset(df_player_trans, !is.na(transfer_value))
df$player_age_cent = df$player_age - 27
df$player_age_sq = df$player_age_cent^2
df$log_transfer_value = log(df$transfer_value + 1000)

# Usually too young or too far back to get a market value
df$market_value[is.na(df$market_value)] = 1



library(lme4)

#mod = lmer(transfer_value ~ player_age_cent + player_age_sq +  
#             (player_age_cent | player_id) + (1 | player_id), data = df)


mod = lmer(transfer_value ~ player_age_cent + player_age_sq  + (1 | player_id), data = df)


df$market_value_adj = pmax(0, predict(mod))/1000


plot(df$market_value_adj ~ df$player_age, 
     xlab = "Player Age at Trade",
     ylab = "Pedicted Transfer Value",
     main = "Predicted Transfer Value (1000 euros) vs.
     Player Age at trade",
     las=1,
     xlim=c(15,40))


library(ggplot2)

ggplot(df, aes(x = player_age, y = market_value_adj, group=player_id)) + 
  geom_line() + 
  xlab("Player Age at Trade") + 
  ylab("Predicted Transfer Value") + 
  ggtitle("Predicted Transfer Value (1000 euros) vs. Player Age at trade") + 
  coord_cartesian(xlim=c(15,40))




ggplot(df, aes(x = player_age, y = transfer_value, group=player_id)) + 
  geom_line() + 
  xlab("Player Age at Trade") + 
  ylab("Measured Transfer Fee") + 
  ggtitle("Measured Transfer Fee (1000 euros) vs. Player Age at trade") + 
  coord_cartesian(xlim=c(15,40))




mod2 = lmer(log_transfer_value ~ player_age_cent + player_age_sq  + (1 | player_id), data = df)

df$exp_log_predicted = exp(predict(mod2))

df$exp_log_predicted  = pmax(0, df$exp_log_predicted)/1000


ggplot(df, aes(x = player_age, y = exp_log_predicted, group=player_id)) + 
  geom_line() + 
  xlab("Player Age at Trade") + 
  ylab("Predicted Transfer Value") + 
  ggtitle("Predicted Transfer Value (1000 euros, log model) vs. Player Age at trade") + 
  coord_cartesian(xlim=c(15,40))





plot(df$transfer_value, predict(mod2))


plot(df$transfer_value ~ df$player_age)

plot(df$log_transfer_value ~ df$player_age)





mod = lmer(transfer_value ~ player_age_cent + player_age_sq  + (1 | player_id), data = df)



plot(df$transfer_value, predict(mod))






coefs = data.frame(coef(mod)[1])

names(coefs)

coefs$player_id = row.names(coefs)
coefs = coefs[, c(4,1,2,3)]
names(coefs) = c("Player_ID", "Beta0", "Beta1", "Beta2")
coefs = coefs[rev(order(coefs$Beta0)), ]


player_ids = coefs$Player_ID
coefs$Player_Name = ""

for(k in 1:length(player_ids))
{
  
  coefs$Player_Name[k] = df$player_name[which(df$player_id == player_ids[k])][1]
  
  
}









coefs = data.frame(coef(mod2)[1])

names(coefs)

coefs$player_id = row.names(coefs)
coefs = coefs[, c(4,1,2,3)]
names(coefs) = c("Player_ID", "Beta0", "Beta1", "Beta2")
coefs = coefs[rev(order(coefs$Beta0)), ]


player_ids = coefs$Player_ID
coefs$Player_Name = ""

for(k in 1:length(player_ids))
{
  coefs$Player_Name[k] = df$player_name[which(df$player_id == player_ids[k])][1]
}

coefs$expBeta0 = exp(coefs$Beta0)




hist(df$transfer_value, n=200, main="Histogram of transfer value", xlab="Transfer Value (Euros)", las=1)


hist(df$market_value, n=200, main="Histogram of crowd-consensus value", xlab="Market Value (Euros)", las=1)


hist(log(df$market_value), n=200, main="Histogram of crowd-consensus value", xlab="Market Value (Euros)", las=1)

