#############################  Read CSVs #######################################
library(dplyr)
x <- read.csv("2.0_Files/Results/2016-17/NCAA_Hoops_Results_6_29_2017.csv", as.is = T)
y <- read.csv("2.0_Files/Results/2017-18/NCAA_Hoops_Results_3_25_2018.csv", as.is = T)
mins <- read.csv("2.0_Files/Info/mins.csv", as.is = T)
rec <- read.csv("2.0_Files/Info/recruiting.csv", as.is = T)
transfers <- read.csv("2.0_Files/Info/transfers.csv", as.is = T)
confs <- read.csv("2.0_Files/Info/conferences.csv", as.is = T)
deadlines <- read.csv("2.0_Files/Info/deadlines.csv", as.is = T)
source("2.0_Files/powerrankings.R")
source("2.0_Files/Ivy_Sims.R")
source("2.0_Files/rpi.R")
source("2.0_Files/record_evaluator.R")
source("2.0_Files/bracketology.R")
source("2.0_Files/helpers.R")
source("2.0_Files/tourney_sim.R")
source("2.0_Files/ncaa_sims.R")
########################  Data Cleaning ########################################
x <- x %>%
  mutate(season_id = "2016-17", game_id = NA, opp_game_id = NA, 
         team_conf = NA, opp_conf = NA, conf_game = NA, GEI = NA)

y <- y %>%
  mutate(scorediff = teamscore - oppscore, predscorediff = NA, wins = NA,
         season_id = "2017-18", game_id = NA, opp_game_id = NA, 
         team_conf = NA, opp_conf = NA, conf_game = NA, GEI = NA)

teams <- unique(x$team)

### Game IDs
for(i in 1:length(teams)) {
  x[x$team == teams[i],] <- x %>%
    filter(team == teams[i]) %>%
    mutate(game_id = seq(1, sum(team == teams[i]), 1))
  
  y[y$team == teams[i],] <- y %>%
    filter(team == teams[i]) %>%
    mutate(game_id = seq(1, sum(team == teams[i]), 1))
}

### Opp Game IDs
for(i in 1:nrow(x)) {
  x$opp_game_id[i] <- get_opp_id(x, i)
}
for(i in 1:nrow(y)) {
  y$opp_game_id[i] <- get_opp_id(y, i)[1]
}

### Confs
for(i in 1:length(teams)) {
  x$team_conf[x$team == teams[i]] <- get_conf(teams[i])
  x$opp_conf[x$opponent == teams[i]] <- get_conf(teams[i])
  y$team_conf[y$team == teams[i]] <- get_conf(teams[i])
  y$opp_conf[y$opponent == teams[i]] <- get_conf(teams[i])
}
x$conf_game <- x$team_conf == x$opp_conf
y$conf_game <- y$team_conf == y$opp_conf
x$reg_season <- (x$month < 3 | x$month >= 11) | (x$month == 3 & x$day <= 4)
y$reg_season <- NA
for(i in 1:nrow(y)) {
  y$reg_season[i] <- reg_season(y$month[i], y$day[i], y$team_conf[i])
}

################################# Set Weights ##################################
x$weights <- 0
for(i in 1:nrow(x)) {
  tmp1 <- (max(c(1, y$game_id[y$team == x$team[i]]), na.rm = T) 
           - 2 * max(c(0, y$game_id[y$team == x$team[i] & !is.na(y$scorediff)]), na.rm = T))/
    max(c(1, y$game_id[y$team == x$team[i]]), na.rm = T)
  tmp2 <- (max(c(1,y$game_id[y$team == x$opponent[i]]), na.rm = T)
           - 2 * max(c(0, y$game_id[y$team == x$opponent[i] & !is.na(y$scorediff)]), na.rm = T))/
    max(c(1, y$game_id[y$team == x$opponent[i]]), na.rm = T)
  x$weights[i] <- min(0.5, max(0, 0.5 * (mins$mins[mins$team == x$team[i]] * tmp1 
                                         + mins$mins[mins$team == x$opponent[i]] * tmp2)), na.rm = T)
}

y$weights <- 0
for(i in 1:nrow(y)) {
  w_team <- 1 - (max(c(0, y$game_id[y$team == y$team[i] & !is.na(y$scorediff)])) - y$game_id[i])/
    max(c(0, y$game_id[y$team == y$team[i] & !is.na(y$scorediff)]))
  w_opponent <- 1 - (max(c(0, y$game_id[y$team == y$opponent[i] & !is.na(y$scorediff)])) - y$opp_game_id[i])/
    max(c(1, y$game_id[y$team == y$opponent[i] & !is.na(y$scorediff)]))
  rr <- mean(c(w_team, w_opponent))
  y$weights[i] <- 1/(1 + (0.5^(5 * rr)) * exp(-rr))
}   


############################### Create Model ###################################
lm.hoops <- lm(scorediff ~ team + opponent + location, weights = weights, data = rbind(x,y)) 

####################### Adjust for Recruiting Class of 2017 ####################
rec$adjustment <- rec$score/sd(rec$score[rec$score > 0])
for(i in 2:(length(teams))) {
  tmp1 <- (max(c(0, y$game_id[y$team == teams[i]]), na.rm = T) 
           - 2 * max(c(0, y$game_id[y$team == teams[i] & !is.na(y$scorediff)]), na.rm = T))/
    max(c(1, y$game_id[y$team == teams[i]]), na.rm = T)
  lm.hoops$coefficients[paste("team", teams[i], sep = "")]  <-
    lm.hoops$coefficients[paste("team", teams[i], sep = "")] +
    rec$adjustment[rec$Team == teams[i]] * tmp1
  lm.hoops$coefficients[paste("opponent", teams[i], sep = "")] <- 
    lm.hoops$coefficients[paste("opponent", teams[i], sep = "")] -
    rec$adjustment[rec$Team == teams[i]] * tmp1
}

########################### Adjust for Transfers ###############################
t.teams <- unique(transfers$Team)
for(i in 1:(length(t.teams))) {
  tmp1 <- (max(c(0, y$game_id[y$team == t.teams[i]]), na.rm = T) 
           - 2 * max(c(0, y$game_id[y$team == t.teams[i] & !is.na(y$scorediff)]), na.rm = T))/
    max(c(1, y$game_id[y$team == t.teams[i]]), na.rm = T)
  lm.hoops$coefficients[paste("team", t.teams[i], sep = "")]  <-
    lm.hoops$coefficients[paste("team", t.teams[i], sep = "")] +
    sum(transfers$Adjust[transfers$Team == t.teams[i]])*tmp1
  lm.hoops$coefficients[paste("opponent", t.teams[i], sep = "")] <- 
    lm.hoops$coefficients[paste("opponent", t.teams[i], sep = "")] -
    sum(transfers$Adjust[transfers$Team == t.teams[i]])*tmp1
}

######################## Point Spread to Win Percentage Model #################
y$predscorediff <- round(predict(lm.hoops, newdata = y), 1)
y$wins[y$scorediff > 0] <- 1
y$wins[y$scorediff < 0] <- 0
glm.pointspread <- glm(wins ~ predscorediff, data = rbind(x,y), family=binomial) 
summary(glm.pointspread)
y$wins[is.na(y$wins)] <- 
  round(predict(glm.pointspread, newdata = y[is.na(y$wins),], type = "response"), 3)

y$date <- as.Date(paste(y$year, y$month, y$day, sep = "/"))
curdate <- as.Date("2018/3/25")
y$dist <- y$date - curdate
preds <- read.csv("predictions.csv")
preds$prediction_made_date <- as.Date(preds$prediction_made_date)
preds$date <- as.Date(preds$date)
z <- filter(y, dist >= 0, dist <= 3)
z$prediction_made_date <- curdate
write.csv(rbind(preds,z), "predictions.csv", row.names = F)
################################ Power Rankings ################################
powranks <- pr_compute(by_conf = F)
by_conf <- pr_compute(by_conf = T)
yusag_plot(powranks)

########################### NCAA Sims ##############################
ncaa_sims <- ncaa_sim(nsims = 10000)
write.csv(ncaa_sims, "2.0_Files/Predictions/ncaa_sims.csv", row.names = F)

########################### Bracketology #######################################
rpi <- rpi_compute(new = F)
resumes <- get_resumes(new = F)
bracket <- make_bracket(tourney = T)
bracket_math <- make_bracket(tourney = F)

################################ Ivy Sims ######################################
playoffs <- ivy.sim(nsims = 5000)
psf_results <- psf(nsims = 1000, year = 2018, months = c(3,3), days = c(2,3))

######################### Conf Undefeated Watch ################################
confs <- confs[order(confs$team), ]
confs$conf_loss <- aggregate(1-wins ~ team, data = filter(y, conf_game, !is.na(scorediff)), sum)[,2]
undefeateds <- filter(confs, conf_loss == 0)
undefeateds$prob <- NA
for(i in 1:nrow(undefeateds)) {
  undefeateds$prob[i] <- prod(y$wins[is.na(y$scorediff) & y$conf_game & y$team == undefeateds$team[i]])
}
write.csv(undefeateds[,c(1,2,7)], "2.0_Files/Predictions/undeafeateds.csv", row.names = F)

############################# Conference Sims (No Tie-Breaks) ##################
conf_results <- conf_sim("Ivy", 10000)

#### Select Games
filter(y, month == 2, day %in% 9:10, conf_game, team_conf == "Ivy", location == "H")

par(mfrow = c(2,4))
colors <- c("brown", "skyblue", "red", "forestgreen", "firebrick4", "maroon", "orange", "navy")
for(i in 1:8) {
  hist(simresults[,i], xlab = "Conference Wins", col = colors[i], main = names(simresults)[i],
       xlim = c(0, 14))
}
######################### Mess Around w/ Ivy Sims ##############################
simresults <- fast.sim(nsims = 20000)
write.csv(simresults, "2.0_Files/Predictions/mens_simresults.csv", row.names = F)

winmat <- apply(simresults, 1, sort, decreasing = T)
table(winmat[4,] == winmat[5,])/20000
table(winmat[3,] == winmat[6,])/20000
apply(winmat, 1, mean)
table(winmat[4,])/20000
table(simresults$Yale)/20000
apply(simresults, 2, mean)

champs <- c("Lipscomb", "Radford", "Michigan", "Col. of Charleston", "Wright St.",
            "Iona", "Loyola Chicago", "LIU Brooklyn", "Murray St.", "Bucknell",
            "UNCG", "South Dakota St.", "Gonzaga", "UMBC", "Virginia", "Kansas",
            "New Mexico St.", "Villanova", "Arizona", "N.C. Central", "Buffalo",
            "Texas Southern", "San Diego St.", "Montana", "Marshall", "SFA",
            "Cal St. Fullerton", "Penn", "Kentucky", "Davidson")