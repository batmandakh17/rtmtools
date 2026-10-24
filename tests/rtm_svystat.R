# rtm_svystat.R -- cross-language check for rtmest (used by crosscheck_engines.do)
# ReGenesees' svystatTM on the same stratified cluster design as rtmest: the mean of skipmeal_r1
# with the adjusted weights, and again after raking to the region and urban totals.
# Arguments file: status=<file>, data=<dta in>, out=<dta out>.
args <- commandArgs(trailingOnly = TRUE)
cfg <- readLines(args[1], warn = FALSE)
kv <- strsplit(cfg, "=", fixed = TRUE)
cfg <- setNames(vapply(kv, function(x) paste(x[-1], collapse = "="), ""), vapply(kv, `[`, "", 1))
res <- tryCatch({
  suppressPackageStartupMessages({ library(haven); library(ReGenesees) })
  d <- as.data.frame(haven::zap_labels(haven::read_dta(cfg[["data"]])))
  d$region <- factor(d$region)
  d$urban <- factor(d$urban)
  d$stratum <- factor(d$stratum)
  des <- e.svydesign(data = d, ids = ~psu, strata = ~stratum, weights = ~w1)
  m0 <- svystatTM(des, ~skipmeal_r1, estimator = "Mean")
  pt <- pop.template(des, calmodel = ~region + urban - 1)
  tot <- c(region1 = 14781, region2 = 15345, region3 = 14898, region4 = 14807, urban1 = 28373)
  miss <- setdiff(names(pt), names(tot))
  if (length(miss)) stop("template columns not matched: ", paste(names(pt), collapse = " "))
  for (nm in names(pt)) pt[1, nm] <- tot[[nm]]
  cal <- e.calibrate(des, pt, calmodel = ~region + urban - 1, calfun = "raking")
  m1 <- svystatTM(cal, ~skipmeal_r1, estimator = "Mean")
  out <- data.frame(design = c("design", "calibrated"),
                    est = c(as.numeric(coef(m0))[1], as.numeric(coef(m1))[1]),
                    se = c(as.numeric(SE(m0))[1], as.numeric(SE(m1))[1]))
  haven::write_dta(out, cfg[["out"]], version = 14)
  writeLines(c("ok", sprintf("ReGenesees %s svystatTM: n = %d", as.character(packageVersion("ReGenesees")), nrow(d))),
             cfg[["status"]])
  TRUE
}, error = function(e) { writeLines(c("error", conditionMessage(e)), cfg[["status"]]); FALSE })
quit(status = 0)
