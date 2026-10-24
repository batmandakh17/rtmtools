# rtm_refexample.R -- reference example for test_calibrate.do
# Runs the calibration documented in ReGenesees' data.examples (?data.examples, ?e.calibrate):
# design ids = towcod + famcod, strata = SUPERSTRATUM, weights = weight; calmodel ~ sex + marstat
# with the bundled population totals pop02 (raking). Exports the data with the calibrated
# weights and the totals in rtmtools' long format, so that Stata's svycal can reproduce it.
args <- commandArgs(trailingOnly = TRUE)
cfg <- readLines(args[1], warn = FALSE)
kv <- strsplit(cfg, "=", fixed = TRUE)
cfg <- setNames(vapply(kv, function(x) paste(x[-1], collapse = "="), ""), vapply(kv, `[`, "", 1))
res <- tryCatch({
  suppressPackageStartupMessages({ library(haven); library(ReGenesees) })
  data(data.examples)
  des <- e.svydesign(data = example, ids = ~towcod + famcod, strata = ~SUPERSTRATUM, weights = ~weight)
  cal <- e.calibrate(design = des, df.population = pop02, calmodel = ~sex + marstat - 1, calfun = "raking")
  ex <- example
  ex$w_regenesees <- as.numeric(weights(cal))
  ex$sex_n <- as.integer(ex$sex)            # f = 1, m = 2
  ex$marstat_n <- as.integer(ex$marstat)    # married = 1, unmarried = 2, widowed = 3
  out <- data.frame(id = seq_len(nrow(ex)), weight = ex$weight, sex = ex$sex_n, marstat = ex$marstat_n,
                    strata = as.integer(ex$SUPERSTRATUM), w_regenesees = ex$w_regenesees)
  haven::write_dta(out, cfg[["data"]], version = 14)
  # totals: pop02 has sexf, sexm, marstatunmarried, marstatwidowed; married = N - unmarried - widowed
  N <- pop02$sexf + pop02$sexm
  tot <- data.frame(variable = c("sex", "sex", "marstat", "marstat", "marstat"),
                    level = c(1L, 2L, 1L, 2L, 3L),
                    total = c(pop02$sexf, pop02$sexm, N - pop02$marstatunmarried - pop02$marstatwidowed,
                              pop02$marstatunmarried, pop02$marstatwidowed))
  haven::write_dta(tot, cfg[["totals"]], version = 14)
  writeLines(c("ok", sprintf("ReGenesees %s example: n = %d, N = %.1f", as.character(packageVersion("ReGenesees")), nrow(ex), N)), cfg[["status"]])
  TRUE
}, error = function(e) { writeLines(c("error", conditionMessage(e)), cfg[["status"]]); FALSE })
quit(status = 0)
