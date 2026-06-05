# library(devtools)
# install_github("lme4/lme4",dependencies=TRUE)

set.seed(12345)

Nplayers = 1000

centres = runif(Nplayers, min=25, max=30)

Nyears = rgeom(Nplayers, 0.3)
start_age = 27.5 - 0.5*Nyears

Ntrades = rpois(Nplayers, Nyears * 0.25)

peak_values = Nyears^2 * runif(Nplayers, min=0.5, 1.5)

trade_player_idx = which(Ntrades > 0)

trade_player_ids = rep(trade_player_idx, times=Ntrades[trade_player_idx])

trade_times = runif(sum(Ntrades), min=0, max=1)
trade_age = start_age[trade_player_ids] + trade_times * Nyears[trade_player_ids]

trade_values = peak_values[trade_player_ids]*(1-(0.5 - trade_times)^2)  * 
  runif(sum(Ntrades), min=0.8, max=1.2)



plot(trade_values ~ trade_times)

plot(trade_values ~ trade_age)


df_trades = data.frame(player = trade_player_ids, age = trade_age, fee = trade_values, 
                       peak = peak_values[trade_player_ids])
  

library(lme4)
mod = lmer(fee ~ age + I(age^2) + (1| player), data = df_trades)
summary(mod)

