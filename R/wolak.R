wolak <- function(data, increasing = TRUE, difference = FALSE, wolakRep = 100, zero_treshold = 1e-6){

    if (missing(data)) {
    stop("Variable 'data' is missing.")
  }

  data <- matrix_conversion(data)

  if(length(data)==1){
    if(data=="conversionFailed"){
    stop("Data cannot be converted in required input format.")
    }
  }

  if(!(is.atomic(wolakRep) & length(wolakRep) == 1 & is.numeric(wolakRep))){
    stop("The variable 'wolakRep' must be a numeric scalar.")
  }
  
  if(!(is.atomic(zero_treshold) & length(zero_treshold) == 1 & is.numeric(zero_treshold))){
    stop("The variable 'zero_treshold' must be a numeric scalar.")
  }

  if(!is(increasing,"logical")){
    stop("The variable 'increasing' must be logical.")
  }

  if(increasing){
    direction <- 1
  }else{
    direction <- -1
  }

  if(!is(difference,"logical")){
    stop("The variable 'difference' must be logical.")
  }

  if (wolakRep < 1) {
    stop("The number of wolak simulations must be positive.")
  }

  if (wolakRep < 100) {
    warning("For robust results there should be a minimum of 100 runs of the wolak simulation.")
  }

  if(!difference){
    data <- data[, 2:ncol(data)] - (data[, 1:(ncol(data) - 1)]) * direction
  }

  T <- nrow(data)
  K <- ncol(data)

  Aineq <- -diag(K)
  Bineq <- c(rep(0,K))

  # unconstrained estimate of mu
  muhat <- colMeans(data)

  lag <- floor(4*(T/100)^(2/9))

  # HAC estimator of the covariance matrix of muhat
  omegahat <- newey_west(data,lag=lag)/T

  mu <- Bineq

  mutilda <- constrOptim(f = .constrained_mean, theta = c(rep(0.01,K)),ui = -Aineq,ci = Bineq,muhat = muhat, omega = omegahat,grad = NULL, outer.iterations = 10000, outer.eps = 1e-8)
  mutilda <- mutilda$par

  # the first test stat, equation 16 of Wolak(1989, JoE)
  IU <- t(muhat-mutilda)%*%solve(omegahat)%*%(muhat-mutilda)

  # the second test statistic, see just after equation 18 of Wolak (1989, JoE)
  EI <- t(mutilda)%*%solve(omegahat)%*%mutilda

  weights <- c(rep(0,ncol(omegahat)+1))

  progress <- txtProgressBar(min = 0, max = wolakRep, style = 3)

  # use monte carlo to obtain the weights for the weighted sum of chi-squareds
  for(jj in 1:wolakRep){
    # simulating iid Normal data
    tempdata <- MASS::mvrnorm(1,mu=t(c(rep(0,ncol(omegahat)))),omegahat,1)
    mutilda1 <- constrOptim(f = .constrained_mean, theta = c(rep(0.01,K)),ui = -Aineq,ci = Bineq,muhat = tempdata, omega = omegahat,grad = NULL, outer.iterations = 10000, outer.eps = 1e-8)
    mutilda1 <- mutilda1$par

    # counting how many elements of mutilda are greater than zero
    # mutilda1 is the output of constrOptim and zeros are at the machine precision so they are not exact,
    # therefore we would always count all coordinates of mutilda1 as positive if we just check mutilda1>0
    # As a simple solution, we check against the default treshold of 1e-6 to get results like
    # in Patton/Timmermann (JoE, 2010).
    temp <- sum(mutilda1 > zero_treshold)

    # adding one more unit of weight to this element of the weight vector
    weights[1+temp] <- weights[1+temp] + 1/wolakRep

    setTxtProgressBar(progress, jj)
  }

  close(progress)

  # pvalue from wolak's first test
  result_1 <- 1 - .weighted_chi2cdf(IU,rev(weights))

  # pvalue from wolak's second test
  result_2 <- 1 - .weighted_chi2cdf(EI,weights)

  if(result_1<0){
    result_1 <- 0
  }

  if(result_2<0){
    result_2 <- 0
  }

  out <- list(as.numeric(result_1),as.numeric(result_2))
  names(out) <- c("TestOnePvalueWolak","TestTwoPvalueWolak")
  return(out)
}

.weighted_chi2cdf <- function(x, weights){
  K <- length(weights) -1

  # a chi-squared with zero degrees of freedom equals 0 with probability 1. so its CDF is zero until 0, and one for values greater or equal than 0
  ret <- weights[1]*(x>=0)
  for(ii in 1:K){
    ret <- ret +weights[ii+1]*pchisq(x,ii)
  }
  return(ret)
}

.constrained_mean <- function(mu,muhat,omega){
  # Function used to find the estimate of the mean, subject to the
  # constraint that it is weakly positive. Used in implementing Wolak's test
  ret <- t(muhat-mu)%*%solve(omega)%*%(muhat-mu)
  return(ret)
}


