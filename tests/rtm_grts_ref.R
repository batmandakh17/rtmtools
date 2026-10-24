# rtm_grts_ref.R -- reference example for test_frame.do: spsurvey's documented NE_Lakes example
# (?grts: grts(NE_Lakes, n_base = 100), and the stratified one with n_base = 25 low and 30 high)
# run directly with set.seed(51), plus the frame exported so that rtmsample grid can repeat the
# draw through the Stata command with the same seed.
# Arguments file: status, gpkg (NE_Lakes with lake_id), frame (dta with lake_id and attributes),
# ref (dta with the sites of the direct call; the stratified one goes to <ref>_strat.dta).
args <- commandArgs(trailingOnly = TRUE)
cfg <- readLines(args[1], warn = FALSE)
kv <- strsplit(cfg, "=", fixed = TRUE)
cfg <- setNames(vapply(kv, function(x) paste(x[-1], collapse = "="), ""), vapply(kv, `[`, "", 1))
res <- tryCatch({
  suppressPackageStartupMessages({library(sf); library(spsurvey); library(haven)})
  data(NE_Lakes)
  lakes <- NE_Lakes
  lakes$lake_id <- seq_len(nrow(lakes))
  lakes$ELEV_CAT <- as.character(lakes$ELEV_CAT)
  lakes$AREA_CAT <- as.character(lakes$AREA_CAT)
  if (file.exists(cfg[["gpkg"]])) unlink(cfg[["gpkg"]])
  st_write(lakes, cfg[["gpkg"]], layer = "lakes", quiet = TRUE)
  xy <- st_coordinates(lakes)
  haven::write_dta(data.frame(lake_id = lakes$lake_id, AREA = lakes$AREA, AREA_CAT = lakes$AREA_CAT,
                              ELEV = lakes$ELEV, ELEV_CAT = lakes$ELEV_CAT, x = xy[, 1], y = xy[, 2]),
                   cfg[["frame"]], version = 14)
  set.seed(51)
  s <- grts(lakes, n_base = 100)
  out <- st_drop_geometry(s$sites_base)[, c("siteID", "lake_id", "wgt", "ip")]
  out$site_order <- as.integer(sub(".*-", "", out$siteID))
  haven::write_dta(out, cfg[["ref"]], version = 14)
  set.seed(51)
  s2 <- grts(lakes, n_base = c(high = 30, low = 25), stratum_var = "ELEV_CAT")   # strata in alphabetical order, as rtmsample grid passes them
  out2 <- st_drop_geometry(s2$sites_base)[, c("siteID", "lake_id", "stratum", "wgt", "ip")]
  haven::write_dta(out2, sub("\\.dta$", "_strat.dta", cfg[["ref"]]), version = 14)
  writeLines(c("ok", sprintf("NE_Lakes n=%d base=%d strat=%d spsurvey=%s", nrow(lakes), nrow(out), nrow(out2),
                             as.character(packageVersion("spsurvey")))), cfg[["status"]])
  TRUE
}, error = function(e) { writeLines(c("error", conditionMessage(e)), cfg[["status"]]); FALSE })
quit(status = 0)
