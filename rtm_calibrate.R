# rtm_calibrate.R  version 0.1.0  24oct2026  rtmtools
# Calibration through ReGenesees (Zardetto 2015), called in the background by
# rtmweight calibrate, engine(regenesees). Reads a .dta written by Stata, calibrates, and writes
# the calibrated weights and diagnostics back as .dta files. Nothing leaves this machine.
#
# Arguments file (key=value lines): data, totals, out, diag, status, idvar, wvar, stratavar,
# calvars (space separated), method (rake|regress|post), calfun (raking|linear|logit),
# bounds (two numbers or empty), trimcal (two numbers or empty), aggvar (optional).
args <- commandArgs(trailingOnly = TRUE)
cfg <- readLines(args[1], warn = FALSE)
kv <- strsplit(cfg, "=", fixed = TRUE)
cfg <- setNames(vapply(kv, function(x) paste(x[-1], collapse = "="), ""), vapply(kv, `[`, "", 1))
status <- function(ok, msg) {
  writeLines(c(ifelse(ok, "ok", "error"), msg), cfg[["status"]])
}
res <- tryCatch({
  for (p in c("haven", "ReGenesees")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      inst <- if (p == "ReGenesees") 'remotes::install_github("DiegoZardetto/ReGenesees")' else sprintf('install.packages("%s")', p)
      stop(sprintf("R package %s is not installed; in R run %s", p, inst))
    }
  }
  suppressPackageStartupMessages({ library(haven); library(ReGenesees) })
  d <- as.data.frame(haven::read_dta(cfg[["data"]]))
  tot <- as.data.frame(haven::read_dta(cfg[["totals"]]))   # columns: variable, level, total
  tot$variable <- as.character(tot$variable)
  calvars <- strsplit(trimws(cfg[["calvars"]]), " +")[[1]]
  idvar <- cfg[["idvar"]]; wvar <- cfg[["wvar"]]; stratavar <- cfg[["stratavar"]]
  method <- cfg[["method"]]; calfun <- cfg[["calfun"]]
  bounds <- if (nzchar(trimws(cfg[["bounds"]]))) as.numeric(strsplit(trimws(cfg[["bounds"]]), " +")[[1]]) else c(-Inf, Inf)
  trim <- if (nzchar(trimws(cfg[["trimcal"]]))) as.numeric(strsplit(trimws(cfg[["trimcal"]]), " +")[[1]]) else NULL
  aggvar <- cfg[["aggvar"]]
  for (v in calvars) d[[v]] <- factor(haven::zap_labels(d[[v]]))
  if (nzchar(stratavar)) d[[stratavar]] <- factor(haven::zap_labels(d[[stratavar]]))
  d[[wvar]] <- as.numeric(d[[wvar]])
  ids_f <- as.formula(paste0("~", idvar))
  des <- e.svydesign(data = d, ids = ids_f, weights = as.formula(paste0("~", wvar)),
                     strata = if (nzchar(stratavar)) as.formula(paste0("~", stratavar)) else NULL,
                     check.data = TRUE)
  if (method == "post") {
    if (length(calvars) != 1) stop("method(post) needs exactly one calibration variable")
    calmodel <- as.formula(paste0("~", calvars, " - 1"))
  } else {
    calmodel <- as.formula(paste0("~", paste(calvars, collapse = " + ")))
  }
  tmpl <- pop.template(d, calmodel = calmodel)
  cols <- names(tmpl)
  # fill the template from the long totals table
  getN <- function(v) sum(tot$total[tot$variable == v])
  Ns <- vapply(calvars, getN, numeric(1))
  if (max(Ns) - min(Ns) > 0.005 * max(Ns)) stop(sprintf("population totals disagree across calibration variables: %s", paste(sprintf("%s=%.1f", calvars, Ns), collapse = ", ")))
  for (cn in cols) {
    if (cn == "(Intercept)") { tmpl[[cn]] <- Ns[[1]]; next }
    hit <- FALSE
    for (v in calvars) {
      if (startsWith(cn, v)) {
        lev <- substring(cn, nchar(v) + 1)
        row <- tot[tot$variable == v & as.character(tot$level) == lev, ]
        if (nrow(row) == 1) { tmpl[[cn]] <- row$total; hit <- TRUE; break }
      }
    }
    if (!hit) stop(sprintf("no population total for template column %s", cn))
  }
  cal <- e.calibrate(des, tmpl, calmodel = calmodel, calfun = calfun, bounds = bounds,
                     aggregate.stage = if (nzchar(aggvar)) 1 else NULL, force = TRUE)
  msgs <- character(0)
  if (!is.null(trim)) {
    cal <- trimcal(cal, w.range = trim, force = TRUE)
    msgs <- c(msgs, sprintf("trimcal applied with w.range %s to %s", trim[1], trim[2]))
  }
  ck <- check.cal(cal)
  gr <- g.range(cal)
  w_cal <- weights(cal)
  out <- data.frame(id = d[[idvar]], w_cal = as.numeric(w_cal))
  names(out)[1] <- idvar
  haven::write_dta(out, cfg[["out"]], version = 14)
  # diagnostics: achieved against target totals
  diag <- data.frame(column = cols, target = as.numeric(unlist(tmpl[1, cols])),
                     achieved = as.numeric(unlist(aux.estimates(cal, template = tmpl)[1, cols])))
  diag$rel_diff <- (diag$achieved - diag$target) / diag$target
  haven::write_dta(diag, cfg[["diag"]], version = 14)
  msgs <- c(msgs, sprintf("ReGenesees %s: calfun %s, bounds %s to %s; g-weights %.4f to %.4f; check.cal return code %s",
                          as.character(packageVersion("ReGenesees")), calfun, bounds[1], bounds[2], gr[1], gr[2], ck$return.code))
  status(TRUE, msgs)
  TRUE
}, error = function(e) { status(FALSE, conditionMessage(e)); FALSE })
quit(status = 0)
