library("flexsurv")
library("mstate")
library("data.table")
library("Rcpp")
library("ggplot2")
library("hesim")
# setwd("tests/manual") # tests should be run of this directory
rm(list = ls())

# State probabilities: hesim vs. mstate ----------------------------------------
# Model structure
tmat <- rbind(c(NA, 1, 2), 
              c(3, NA, 4), 
              c(NA, NA, NA))

# Fit survival models
fit_data <- data.table(mstate3_exdata$transitions)
fit_data[, trans := factor(trans)]

fit_models <- function(clock = c("reset", "forward")){
  clock <- match.arg(clock)
  
  # Parametric models
  dists <- c("exponential", "weibull", "gompertz", "gamma", "lnorm", "llogis",
             "gengamma")
  fits <- vector(mode = "list", length = length(dists))
  names(fits) <- dists
  for (i in 1:length(fits)){
    if (clock == "reset"){
      fits[[i]] <-  flexsurvreg(Surv(years, status) ~ trans, data = fit_data, 
                                dist = dists[i]) 
    } else{
      fits[[i]] <-  flexsurvreg(Surv(Tstart, Tstop, status) ~ trans, data = fit_data, 
                                dist = dists[i]) 
    }
    print(paste0("Fit ", dists[i], " model"))
  } 
  
  # Spline model
  if (clock == "reset"){
    fits$spline <- flexsurvspline(Surv(years, status) ~ trans, data = fit_data) 
  } else{
    fits$spline <- flexsurvspline(Surv(Tstart, Tstop, status) ~ trans, data = fit_data) 
  }
  print(paste0("Fit spline model"))
  
  # Return
  return(fits)
}
fits_reset <- fit_models(clock = "reset")
fits_forward <- fit_models(clock = "forward")

# Compute cumulative hazards
hesim_msfit <- function(fit, tmat, t_grid){
  input_dat <- data.frame(strategy_id = 1, patient_id = 1, 
                          transition_id = 1, 
                          trans = factor(1:max(tmat, na.rm = TRUE)))
  setattr(input_dat, "class", c("expanded_hesim_data", "data.table", "data.frame"))
  attr(input_dat, "id_vars") <- c('strategy_id', "patient_id", "transition_id")
  transmod <- create_IndivCtstmTrans(fit, 
                                     input_data = input_dat, trans_mat = tmat,
                                     point_estimate = TRUE)
  cumhaz <- transmod$cumhazard(t = t_grid)[, .(t, cumhazard, trans)]
  setnames(cumhaz, c("t", "cumhazard", "trans"), c("time", "Haz", "trans"))
  return(cumhaz)
}

# Simulate 
## mstate
sim_stprobs_mstate <- function(fit, n_patients, t_grid,
                               clock = c("reset", "forward")){
  clock <- match.arg(clock)
  cumhaz <- hesim_msfit(fit, tmat, t_grid)
  if (clock == "reset"){
    stprobs <- mstate::mssample(Haz = cumhaz, trans = tmat, tvec = t_grid, 
                                clock = clock, M = n_patients) 
  } else{
    msfit <- list(Haz = cumhaz,
                  trans = tmat)
    class(msfit) <- "msfit"
    stprobs <- probtrans(msfit, predt = 0, variance = FALSE)[[1]]
  }
  stprobs <- data.table(stprobs)
  stprobs <- melt(stprobs, id.vars = "time", 
                  variable.name = "state", value.name = "prob")
  stprobs[, state := factor(state,
                            levels = paste0("pstate", 1:3),
                            labels = paste0("State ", 1:3))] 
  stprobs[, lab := "mstate"]
  return(stprobs)
}

## hesim
sim_stprobs_hesim <- function(fit, n_patients, t_grid, 
                              clock = c("reset", "forward")){
  clock <- match.arg(clock)
  # Input data
  transitions <- create_trans_dt(tmat)
  transitions[, trans := factor(transition_id)]
  hesim_dat <- hesim_data(strategies <- data.table(strategy_id = 1),
                          patients <- data.table(patient_id = 1:n_patients),
                          transitions = transitions)
  hesim_edat <- expand(hesim_dat, by = c("strategies", "patients", "transitions")) 
  
  # Simulate
  ## hesim
  transmod <- create_IndivCtstmTrans(fit, 
                                     input_data = hesim_edat, trans_mat = tmat,
                                     point_estimate = TRUE,
                                     clock = clock) 
  stprobs <- transmod$sim_stateprobs(t = t_grid)  
  stprobs[, state := factor(state_id,
                                   levels = 1:3,
                                   labels = paste0("State ", 1:3))]
  stprobs[, c("sample", "strategy_id", "state_id", "grp_id") := NULL]
  stprobs[, lab := "hesim"]
  setnames(stprobs, "t", "time")
  return(stprobs)
}

## comparison plot
plot_comparison1 <- function(fit, n_patients = 1000, clock){
  t_grid <- seq(0, max(fit_data$Tstop), .01)
  mstate_stprobs <- sim_stprobs_mstate(fit, n_patients, t_grid, clock)
  hesim_stprobs <- sim_stprobs_hesim(fit, n_patients, t_grid, clock)
  
  # plot
  pdat <- rbind(mstate_stprobs, hesim_stprobs)
  p <- ggplot(pdat, aes(x = time, y = prob, col = lab)) +
       geom_line() + 
       facet_wrap(~state) +
    xlab("Years") + ylab("Probability in health state") +
    scale_color_discrete(name = "") + theme_minimal() +
    theme(legend.position = "bottom") 
  return(p)
}

plot_comparisons <- function(fits, n_patients, clock,
                             filename){
  pdf(paste0("figs/", filename))
  for (i in 1:length(fits)){
    p <- plot_comparison1(fits[[i]], n_patients, clock)
    p <- p + labs(title = names(fits)[[i]])
    print(p)
    print(paste0("Completed plot for ", names(fits)[[i]], " model."))
  }
  dev.off()
}
plot_comparisons(fits_reset, 1000, "reset", 
                 "stprobs-ictstm-reset-hesim-vs-mstate.pdf")
plot_comparisons(fits_forward, 10000, "forward", 
                 "stprobs-ictstm-forward-hesim-vs-mstate.pdf") 

# State probabilities: fractional polynomial vs. weibull -----------------------
t_grid <- seq(0, max(fit_data$Tstop), .01)

# Weibull NMA fit
weiNMA_fit <- flexsurvreg(Surv(years, status) ~ trans, data = fit_data, 
                         dist = hesim_survdists$weibullNMA)
weiNMA_params <- create_params(weiNMA_fit, point_estimate = TRUE)

# Equivalent fractional polynomial parameters
fp_params <- weiNMA_params  
fp_params$dist <- "fracpoly"
fp_params$aux <- list(powers = c(0, 0),
                      cumhaz_method = "riemann", 
                      step = 1/12,
                      random_method = "discrete")
names(fp_params$coefs) <- c("gamma0", "gamma1")
colnames(fp_params$coefs$gamma0)[1] <- "gamma0"
colnames(fp_params$coefs$gamma1)[1] <- "gamma1"

# Simulate
sim_stprobs_fp <- function(obj, param_names, n_patients, mod_name){
  transitions <- create_trans_dt(tmat)
  hesim_dat <- hesim_data(strategies <- data.table(strategy_id = 1),
                        patients <- data.table(patient_id = 1:n_patients),
                        transitions = transitions)
  input_dat <- expand(hesim_dat, by = c("strategies", "patients", "transitions")) 
  input_dat[, trans2 := 1 * (transition_id == 2)]
  input_dat[, trans3 := 1 * (transition_id == 3)]
  input_dat[, trans4 := 1 * (transition_id == 4)]
  input_dat[, (param_names) := 1]
  transmod <- create_IndivCtstmTrans(obj, 
                                    input_data = input_dat, trans_mat = tmat,
                                    clock = "reset") 
  stprobs <- transmod$sim_stateprobs(t = t_grid)
  stprobs[, lab := mod_name]
  return(stprobs)
}

fp_plot <- function(fp_stprobs, wei_stprobs){
  pdat <- rbind(fp_stprobs, wei_stprobs)
  p <- ggplot(pdat, aes(x = t, y = prob, col = lab)) +
            geom_line() + 
            facet_wrap(~state_id) +
            xlab("Years") + ylab("Probability in health state") +
            scale_color_discrete(name = "") + theme_minimal() +
            theme(legend.position = "bottom") 
 return(p)
}

weiNMA_stprobs <- sim_stprobs_fp(weiNMA_params, c("a0", "a1"), 10000, 
                                 "Weibull")

## Sample and riemann integration
fp_stprobs <- sim_stprobs_fp(fp_params, c("gamma0", "gamma1"), 10000, 
                             "Fractional polynomial")
p <- fp_plot(weiNMA_stprobs, fp_stprobs)
ggsave("figs/stprobs-reset-fracpoly-sample-riemann.pdf", p, width = 5, height = 7)

## Sample and quadrature (Note: this is very slow)
# fp_params$aux$cumhaz_method <- "quad"
# fp_stprobs <- sim_stprobs_fp(fp_params, c("gamma0", "gamma1"), 100, 
#                              "Fractional polynomial")
# p <- fp_plot(weiNMA_stprobs, fp_stprobs)

# Inverse CDF and quadrature 
fp_params$aux$cumhaz_method <- "quad"
fp_params$aux$random_method <- "invcdf"
fp_stprobs <- sim_stprobs_fp(fp_params, c("gamma0", "gamma1"), 1000,
                             "Fractional polynomial")
p <- fp_plot(weiNMA_stprobs, fp_stprobs)
ggsave("figs/stprobs-reset-fracpoly-invcdf-quad.pdf", p, width = 5, height = 7)

# Inverse CDF and riemann
fp_params$aux$cumhaz_method <- "riemann"
fp_stprobs <- sim_stprobs_fp(fp_params, c("gamma0", "gamma1"), 10000, 
                             "Fractional polynomial")
p <- fp_plot(weiNMA_stprobs, fp_stprobs)
ggsave("figs/stprobs-reset-fracpoly-invcdf-riemann.pdf", p, width = 5, height = 7)

# Modify step size
fp_params$aux$step <- .02
fp_stprobs <- sim_stprobs_fp(fp_params, c("gamma0", "gamma1"), 10000, 
                             "Fractional polynomial")
p <- fp_plot(weiNMA_stprobs, fp_stprobs)

# Simulate survival from arbitrary cumulative hazards --------------------------
module <- Rcpp::Module('distributions', PACKAGE = "hesim")

compute_surv <- function(step, lower, upper, hazfun){
  time <- seq(lower, upper, by = step)
  cumhaz <- rep(NA, length(time))
  cumhaz[1] <- 0
  for (i in 2:length(time)){
    cumhaz[i] <- (step * do.call("hazfun", list(time[i]))) + cumhaz[i - 1]
  }
  surv <- exp(-cumhaz)
  dat <- data.frame(time = time, surv = surv,
                    cumhaz = cumhaz,
                    lab = "Analytical") 
  return(dat)
}

# Test #1 = fractional polynomial from [0, inf)
FracPoly <- module$fracpoly
gamma = c(-1.2, -.567, 1.15)
powers = c(1, 0)
fp <- new(FracPoly, gamma = gamma, powers = powers,
          cumhaz_method = "riemann", step = 1/12, random_method = "discrete")
fp$max_x_ <- 40
lower <- 0
upper <- fp$max_x_
step <- 1/12
time <- seq(lower, upper, step)

## Random sample with hesim
r1 <- replicate(1000, fp$random())
fun <- ecdf(r1)
esurv <- 1 - fun(time)
dat1 <- data.frame(time = time, surv = esurv, lab = "Random")

## Analytically compute survival
dat2 <- compute_surv(step = step, lower = lower, upper = upper, 
                     hazfun = fp$hazard)

## Compare
dat <- rbind(dat1, dat2[, c("time", "surv", "lab")])
ggplot(dat, aes(x = time, y = surv, col = lab)) + geom_line()

# Test #2 = truncated exponential distribution
Exponential <- module$exponential
exp <- new(Exponential, rate = 1.5)
lower <- 5; upper <- 10
step <- 1/12

## Sample using inverse CDF method
r1 <- replicate(1000, exp$trandom(lower, upper))

## Sample from arbitrary cumulative hazard with R
surv_df <- compute_surv(step = step, lower = lower, upper = upper,
                        hazfun = exp$hazard)
r2 <- replicate(1000,
                hesim:::C_test_rsurv(time = surv_df$time, cumhaz = surv_df$cumhaz, 
                                     time_inf = FALSE))

## Compare
time <- seq(lower, upper, step)
fun1 <- ecdf(r1)
fun2 <- ecdf(r2)
esurv1 <- 1 - fun1(time)
esurv2 <- 1 - fun2(time)
dat1 <- data.frame(time = time, surv = esurv1, lab = "Empirical CDF")
dat2 <- data.frame(time = time, surv = esurv2, lab = "Empirical hazard")
dat <- rbind(dat1, dat2)
ggplot(dat, aes(x = time, y = surv, col = lab)) + geom_line() 

# Random number generation for piecewise exponential distributions -------------
module <- Rcpp::Module('distributions', PACKAGE = "hesim")
PwExp <- module$piecewise_exponential
rate <- c(0.5, 0.8, 1.2, 1.5)
time <- c(0, 5, 10, 15)
pwexp <- new(PwExp, rate = rate, time = time)
pwexp$trandom(lower = 17, upper = Inf)

# Compare approaches for sampling
compare_trandom <- function(lower, n = 1000){
  # Rejection sampling
  r1 <- rpwexp(n * 10, rate = rate, time = time)
  r1 <- r1[r1 >= lower]
  
  # hesim
  r2 <- replicate(n, pwexp$trandom(lower = lower, upper = Inf))
  
  # Compare
  summary <- 
  p_df <- data.frame(x = c(r1, r2),
                     method = rep(c("Rejection", "hesim"), 
                                  times = c(length(r1), length(r2))))
  p <- ggplot(p_df, aes(x = x, col = method)) +
    geom_density() +
    geom_vline(xintercept = lower, linetype = "dashed", col = "red") +
    scale_x_continuous(breaks = seq(floor(min(p_df$x)), ceiling(max(p_df$x)), 
                                    by = 1)) +
    scale_colour_discrete("") +
    ylab("Density")

  return(list(r1 = r1, r2 = r2,
              p = p,
              n_r1 = length(r1),
              summary = rbind(r1 = summary(r1), r2 = summary(r2))
  ))
}  
comp <- list(`Lower = 3` = compare_trandom(lower = 3, n = 100000),
             `Lower = 8` = compare_trandom(lower = 8, n = 100000))

## Plot results
pdf("figs/pwexp_trandom_comp.pdf")
for (i in 1:length(comp)){
  print(comp[[i]]$p + labs(title = names(comp)[[i]]))
}
dev.off()






