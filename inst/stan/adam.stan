// Bacon as a Stan model
// 03.08.2020 Andrew Dolman
// Add flexible addtional layer to alphas.

data {
  int<lower=0, upper=1> inflate_errors;
  int<lower=0> N;
  int<lower=0> K_fine;  // no of fine sections
  int<lower=0> K_tot;  // total no of gamma parameters
  int<lower=0> nu; // degrees of freedom of t error distribution
  vector[N] depth;
  vector[N] obs_age;
  vector[N] obs_err;
  vector[K_fine] c_depth_bottom;
  vector[K_fine] c_depth_top;
  int parent[K_tot]; // index sections to their parent sections
  
  int which_c[N]; // index observations to their fine sections
  real<lower = 0> delta_c; // width of each fine section
  
  // hyperparameters
  
  // parameters for the prior distribution of the overall mean acc rate
  real<lower = 0> acc_mean_prior;
  
  // shape of the gamma distributions
  real<lower = 0> shape; 
  
  real<lower = 0> mem_mean;
  real<lower = 0> mem_strength;
  
}
transformed data{
  
  // transform mean and strength of memory beta distribution to alpha and beta
  real<lower=0> mem_alpha = mem_strength * mem_mean;
  real<lower=0> mem_beta = mem_strength * (1-mem_mean);
  
  // position of the first highest resolution innovation (alpha)
  int<lower = 1> first_K_fine = K_tot - K_fine+1;
  
  real<lower=0> mean_obs_err = mean(obs_err);
  
}
parameters {
  // AR1 coeffiecient at 1 depth unit
  real<lower = 0, upper = 1> R;
  
  // the hierarchical gamma innovations in one long vector that will be indexed
  vector<lower = 0>[K_tot] alpha;
  
  // the age at the first modelled depth
  real age0;
  
  // the measurement error inflation factors
  // these have length 0 if inflate_errors == 0 meaning that the parameters are 
  // in scope, so the model runs, but are zero length so nothing is sampled
  real<lower = 0> infl_mean[inflate_errors];
  real<lower = 0> infl_shape[inflate_errors];
  vector<lower = 0>[inflate_errors ? N : 0] infl;
  real<lower = 0> infl_sigma[inflate_errors];
}
transformed parameters{
  
  // the AR1 coefficient scaled for the thickness of the modelled sediment sections
  real<lower = 0, upper = 1> w = R^(delta_c);
  
  // the highest resolution AR1 correlated innovations
  vector[K_fine] x;
  
  // the modelled ages
  vector[K_fine+1] c_ages;
  
  // the modelled ages interpolated to the positions of the data
  vector[N] Mod_age;
  
  // the inflated observation errors
  vector[N] obs_err_infl;
  
  if (inflate_errors == 1){
    for (n in 1:N)
    obs_err_infl[n] = obs_err[n] + infl_sigma[1] * infl[n];
  } else {
    obs_err_infl = obs_err;
  }
  
 
  // only the "fine" alphas
  // the first innovation
  x[1] = alpha[first_K_fine];
  
  // the remaining innovations with the AR1 parameter applied
  for(i in 2:K_fine){
    x[i] = w*x[i-1] + (1-w)*alpha[i + first_K_fine -1];
  }
  
  
  // Get the cumulative sum of the highest resolution innovations
  c_ages[1] = age0;
  c_ages[2:(K_fine+1)] = age0 + cumulative_sum(x * delta_c);
  
  // Interpolate to the positions of the observations
  Mod_age = c_ages[which_c] + x[which_c] .* (depth - c_depth_top[which_c]);
}

model {
  // the overall mean accumulation rate
  alpha[1] ~ normal(0, 10*acc_mean_prior);
  
  // the gamma distributed innovations
  alpha[2:K_tot] ~ gamma(shape, shape ./ alpha[parent[2:K_tot]]);
  
  // the memory parameters
  R ~ beta(mem_alpha, mem_beta);
  
  // the observation error inflation model
  if (inflate_errors == 1){
    infl_mean ~ gamma(1, 1);
    infl_shape ~ gamma(1, 1);
    infl ~ gamma(infl_shape[1], infl_shape[1] / infl_mean[1]);
    
    infl_sigma ~ normal(0, mean_obs_err);
  }
  
  // the Likelihood of the data given the model
  obs_age ~ student_t(nu, Mod_age, obs_err_infl);
}
