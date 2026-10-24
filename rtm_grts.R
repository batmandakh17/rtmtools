# rtm_grts.R -- rtmtools: spatially balanced (GRTS) sample of grid cells or points (used by rtmsample grid)
# Arguments file (key=value): status, frame (gpkg/shp), layer (optional), idvar, n (number) or nfile
#   (dta with idvar and the per-stratum sample size column nvar), nvar, strata (column or empty),
#   seltype (equal|proportional), aux (column for proportional), nover, nnear, mindis, seed, out (dta),
#   gpkg (optional, the selected sites).
# Method: spsurvey::grts() (Dumelle et al. 2023) on the cell centroids (a finite frame), stratified by
#   the strata column, with reverse-hierarchically ordered replacement sites (n_over) and nearest
#   neighbour replacements (n_near); the design weight is spsurvey's wgt = 1/inclusion probability.
#   set.seed(seed) is called right before grts(), so the same seed repeats the draw.
args <- commandArgs(trailingOnly = TRUE)
cfg <- readLines(args[1], warn = FALSE)
kv <- strsplit(cfg, "=", fixed = TRUE)
cfg <- setNames(vapply(kv, function(x) paste(x[-1], collapse = "="), ""), vapply(kv, `[`, "", 1))
get <- function(k, default = "") if (k %in% names(cfg) && nzchar(cfg[[k]])) cfg[[k]] else default
res <- tryCatch({
  suppressPackageStartupMessages({library(sf); library(spsurvey); library(haven)})
  sf_use_s2(FALSE)
  layer <- get("layer")
  f <- if (nzchar(layer)) st_read(get("frame"), layer = layer, quiet = TRUE) else st_read(get("frame"), quiet = TRUE)
  f <- st_zm(f, drop = TRUE)
  idvar <- get("idvar", "cell_id")
  if (!idvar %in% names(f)) stop(sprintf("id variable %s is not a column of the frame file (columns: %s)", idvar, paste(setdiff(names(f), attr(f, "sf_column")), collapse = " ")))
  if (anyDuplicated(f[[idvar]])) stop(sprintf("id variable %s is not unique in the frame file", idvar))
  if (is.na(st_crs(f))) stop("the frame file has no coordinate reference system")
  if (st_is_longlat(f)) {
    ctr <- suppressWarnings(st_coordinates(st_centroid(st_union(f))))
    zone <- floor((ctr[1] + 180) / 6) + 1
    f <- st_transform(f, if (ctr[2] >= 0) 32600 + zone else 32700 + zone)
  }
  if (!all(st_is(f, c("POINT", "MULTIPOINT")))) {
    geom <- suppressWarnings(st_centroid(st_geometry(f)))
    f <- st_sf(st_drop_geometry(f), geometry = geom)
  }
  strata <- get("strata")
  if (nzchar(strata) && !strata %in% names(f)) stop(sprintf("strata variable %s is not a column of the frame file (columns: %s; a grid frame's strata column is named stratum)", strata, paste(setdiff(names(f), attr(f, "sf_column")), collapse = " ")))
  if (nzchar(strata)) f[[strata]] <- as.character(f[[strata]])
  n <- as.numeric(get("n", "0"))
  nfile <- get("nfile"); nvar <- get("nvar")
  if (nzchar(nfile)) {
    nd <- haven::read_dta(nfile)
    if (!nzchar(strata)) stop("a per-stratum sample size variable needs strata()")
    key <- as.character(f[[strata]])[match(nd[[idvar]], f[[idvar]])]
    nb <- tapply(as.numeric(nd[[nvar]]), key, function(v) v[1])
    nb <- nb[!is.na(names(nb))]
    n_base <- as.list(nb)
  } else if (nzchar(strata)) {
    lev <- sort(unique(f[[strata]]))
    n_base <- setNames(as.list(rep(n, length(lev))), lev)
  } else n_base <- n
  seltype <- get("seltype", "equal")
  aux <- get("aux")
  if (seltype == "proportional" && !nzchar(aux)) stop("seltype(proportional) needs aux(), the measure of size")
  if (nzchar(aux)) {
    if (!aux %in% names(f)) stop(sprintf("aux variable %s is not a column of the frame file", aux))
    if (any(is.na(f[[aux]]) | f[[aux]] <= 0)) stop("the measure of size for proportional selection must be positive for every unit")
  }
  nover <- as.integer(get("nover", "0")); nnear <- as.integer(get("nnear", "0")); mindis <- as.numeric(get("mindis", "0"))
  # feasibility: n_base + n_over per stratum must not exceed the units
  if (nzchar(strata)) {
    cnt <- table(f[[strata]])
    for (s in names(n_base)) {
      if (!s %in% names(cnt)) stop(sprintf("stratum %s has no units in the frame", s))
      if (n_base[[s]] + nover > cnt[[s]]) stop(sprintf("stratum %s: n + nover = %d exceeds its %d units", s, n_base[[s]] + nover, cnt[[s]]))
    }
  } else if (n + nover > nrow(f)) stop(sprintf("n + nover = %d exceeds the %d units of the frame", n + nover, nrow(f)))
  seed <- as.integer(get("seed", "1"))
  set.seed(seed)
  s <- grts(f, n_base = n_base, stratum_var = if (nzchar(strata)) strata else NULL,
            seltype = if (nzchar(aux)) "proportional" else "equal", aux_var = if (nzchar(aux)) aux else NULL,
            n_over = if (nover > 0) nover else NULL, n_near = if (nnear > 0) nnear else NULL,
            mindis = if (mindis > 0) mindis else NULL)
  parts <- list(s$sites_base, s$sites_over, s$sites_near)
  parts <- parts[!vapply(parts, is.null, TRUE)]
  sites <- do.call(rbind, lapply(parts, function(p) p[, intersect(c("siteID", "siteuse", "replsite", "stratum", "wgt", "ip", idvar), names(p))]))
  xy <- st_coordinates(sites)
  ll <- st_coordinates(st_transform(sites, 4326))
  out <- data.frame(st_drop_geometry(sites), x = xy[, 1], y = xy[, 2], lon = ll[, 1], lat = ll[, 2], stringsAsFactors = FALSE)
  out$site_order <- as.integer(sub(".*-", "", out$siteID))
  haven::write_dta(out, get("out"), version = 14)
  gpkg <- get("gpkg")
  if (nzchar(gpkg)) {
    if (file.exists(gpkg)) unlink(gpkg)
    st_write(sites, gpkg, layer = "sites", quiet = TRUE)
  }
  writeLines(c("ok", sprintf("n_base=%d n_over=%d n_near=%d seed=%d seltype=%s spsurvey=%s", nrow(s$sites_base),
                             if (is.null(s$sites_over)) 0L else nrow(s$sites_over), if (is.null(s$sites_near)) 0L else nrow(s$sites_near),
                             seed, if (nzchar(aux)) "proportional" else "equal", as.character(packageVersion("spsurvey")))), get("status"))
  TRUE
}, error = function(e) { writeLines(c("error", conditionMessage(e)), get("status")); FALSE })
quit(status = 0)
