# rtmtools_check.R  version 0.1.0  24oct2026  rtmtools
# Reports the R version and whether the packages the R steps need are installed.
# Called by rtmtools_setup, check. Writes a status file: first line ok, then one line per item.
args <- commandArgs(trailingOnly = TRUE)
cfg <- readLines(args[1], warn = FALSE)
kv <- strsplit(cfg, "=", fixed = TRUE)
cfg <- setNames(vapply(kv, function(x) paste(x[-1], collapse = "="), ""), vapply(kv, `[`, "", 1))
lines <- c(paste("R", R.version.string))
need <- list(haven = 'install.packages("haven")', sf = 'install.packages("sf")', terra = 'install.packages("terra")',
             spsurvey = 'install.packages("spsurvey")', sae = 'install.packages("sae")',
             ReGenesees = 'remotes::install_github("DiegoZardetto/ReGenesees")')
for (p in names(need)) {
  if (requireNamespace(p, quietly = TRUE)) {
    lines <- c(lines, sprintf("package %s %s installed", p, as.character(packageVersion(p))))
  } else {
    lines <- c(lines, sprintf("package %s MISSING; in R run %s", p, need[[p]]))
  }
}
writeLines(c("ok", lines), cfg[["status"]])
quit(status = 0)
