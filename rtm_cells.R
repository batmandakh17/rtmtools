# rtm_cells.R -- rtmtools: replacement candidates and splits for grid cells (rtmframe replace, rtmframe split)
# Arguments file (key=value): status, frame (gpkg), layer (optional), idvar, mode (replace|split),
#   cells (comma-separated ids), exclude (comma-separated ids, optional), adjacency (queen|rook),
#   parts (k for a k x k split), raster (for split, optional), out (dta), gpkg (optional).
# replace: the cells adjacent to each named cell (queen: sharing an edge or a corner; rook: an edge)
#   in the same stratum and not excluded, ranked by the distance between centroids, with their
#   measure of size: the rule of the Survey Solutions grid replacement application (susogrdframe),
#   whose output the field team uses to pick the replacement.
# split: each named cell cut into k x k sub-cells with the measure of size re-aggregated from the
#   raster (susogrdframe offers 2 x 2, 3 x 3 and 4 x 4), for areas too large to list.
args <- commandArgs(trailingOnly = TRUE)
cfg <- readLines(args[1], warn = FALSE)
kv <- strsplit(cfg, "=", fixed = TRUE)
cfg <- setNames(vapply(kv, function(x) paste(x[-1], collapse = "="), ""), vapply(kv, `[`, "", 1))
get <- function(k, default = "") if (k %in% names(cfg) && nzchar(cfg[[k]])) cfg[[k]] else default
res <- tryCatch({
  suppressPackageStartupMessages({library(sf); library(haven)})
  sf_use_s2(FALSE)
  layer <- get("layer", "cells")
  lyrs <- tryCatch(st_layers(get("frame"))$name, error = function(e) character(0))
  f <- if (layer %in% lyrs) st_read(get("frame"), layer = layer, quiet = TRUE) else st_read(get("frame"), quiet = TRUE)
  f <- st_zm(f, drop = TRUE)
  idvar <- get("idvar", "cell_id")
  if (!idvar %in% names(f)) stop(sprintf("id variable %s is not a column of the frame file", idvar))
  ids <- as.numeric(strsplit(get("cells"), ",", fixed = TRUE)[[1]])
  miss <- setdiff(ids, f[[idvar]])
  if (length(miss)) stop(sprintf("cells not in the frame file: %s", paste(miss, collapse = " ")))
  mode <- get("mode", "replace")
  llc <- function(geom) st_coordinates(st_transform(suppressWarnings(st_centroid(geom)), 4326))
  llb <- function(geom) t(vapply(seq_along(geom), function(i) as.numeric(st_bbox(st_transform(geom[i], 4326))), numeric(4)))
  if (mode == "replace") {
    excl <- get("exclude")
    excl <- if (nzchar(excl)) as.numeric(strsplit(excl, ",", fixed = TRUE)[[1]]) else numeric(0)
    adjacency <- get("adjacency", "queen")
    hasstr <- "stratum" %in% names(f)
    cent <- suppressWarnings(st_centroid(st_geometry(f)))
    rows <- list()
    for (id in ids) {
      i <- which(f[[idvar]] == id)
      nb <- if (adjacency == "rook") st_relate(f[i, ], f, pattern = "F***1****")[[1]] else st_touches(f[i, ], f)[[1]]
      nb <- setdiff(nb, i)
      if (hasstr) nb <- nb[as.character(f$stratum[nb]) == as.character(f$stratum[i])]
      nb <- nb[!f[[idvar]][nb] %in% excl]
      if (length(nb) == 0) {
        rows[[length(rows) + 1]] <- data.frame(cell = id, candidate = NA_real_, rank = NA_real_, dist_km = NA_real_, stringsAsFactors = FALSE)
        next
      }
      d <- as.numeric(st_distance(cent[i], cent[nb])) / 1000
      o <- order(d)
      cand <- f[nb[o], ]
      ll <- llc(st_geometry(cand)); bb <- llb(st_geometry(cand))
      rows[[length(rows) + 1]] <- data.frame(cell = id, candidate = cand[[idvar]], rank = seq_along(o), dist_km = d[o],
                                             stratum = if (hasstr) as.character(cand$stratum) else "all",
                                             pop = if ("pop" %in% names(cand)) as.numeric(cand$pop) else NA_real_,
                                             area_km2 = as.numeric(st_area(cand)) / 1e6,
                                             lon = ll[, 1], lat = ll[, 2], lon_min = bb[, 1], lat_min = bb[, 2], lon_max = bb[, 3], lat_max = bb[, 4],
                                             stringsAsFactors = FALSE)
    }
    out <- do.call(rbind, lapply(rows, function(r) { for (v in c("stratum", "pop", "area_km2", "lon", "lat", "lon_min", "lat_min", "lon_max", "lat_max")) if (!v %in% names(r)) r[[v]] <- if (v == "stratum") NA_character_ else NA_real_; r }))
    haven::write_dta(out, get("out"), version = 14)
    gpkg <- get("gpkg")
    if (nzchar(gpkg)) {
      sel <- f[f[[idvar]] %in% out$candidate[!is.na(out$candidate)], ]
      sel$replaces <- vapply(sel[[idvar]], function(c) paste(out$cell[which(out$candidate == c)], collapse = ";"), "")
      if (file.exists(gpkg)) unlink(gpkg)
      st_write(sel, gpkg, layer = "candidates", quiet = TRUE)
      st_write(f[f[[idvar]] %in% ids, ], gpkg, layer = "cells_to_replace", quiet = TRUE)
    }
    writeLines(c("ok", sprintf("cells=%d candidates=%d adjacency=%s", length(ids), sum(!is.na(out$candidate)), adjacency)), get("status"))
  } else {
    k <- as.integer(get("parts", "2"))
    if (!k %in% 2:4) stop("parts() must be 2, 3 or 4 (a 2 x 2, 3 x 3 or 4 x 4 split)")
    rfile <- get("raster")
    if (nzchar(rfile)) { suppressPackageStartupMessages(library(terra)); r <- rast(rfile); if (nlyr(r) > 1) r <- r[[1]] }
    rows <- list(); geoms <- list()
    for (id in ids) {
      i <- which(f[[idvar]] == id)
      sub <- st_make_grid(f[i, ], n = c(k, k), what = "polygons")
      sub <- suppressWarnings(st_intersection(sub, st_geometry(f[i, ])))
      sub <- sub[as.numeric(st_area(sub)) > 1e-9]
      part <- seq_along(sub)
      pop <- rep(NA_real_, length(sub))
      if (nzchar(rfile)) {
        rr <- if (!same.crs(crs(r), st_crs(f)$wkt)) project(r, st_crs(f)$wkt, method = "near") else r
        pop <- as.numeric(terra::extract(rr, vect(st_sf(geometry = sub)), fun = sum, exact = TRUE, na.rm = TRUE)[, 2])
      }
      ll <- llc(sub); bb <- llb(sub)
      rows[[length(rows) + 1]] <- data.frame(cell = id, part = part, pop = pop, area_km2 = as.numeric(st_area(sub)) / 1e6,
                                             lon = ll[, 1], lat = ll[, 2], lon_min = bb[, 1], lat_min = bb[, 2], lon_max = bb[, 3], lat_max = bb[, 4],
                                             stringsAsFactors = FALSE)
      geoms[[length(geoms) + 1]] <- st_sf(cell = id, part = part, pop = pop, geometry = sub)
    }
    out <- do.call(rbind, rows)
    haven::write_dta(out, get("out"), version = 14)
    gpkg <- get("gpkg")
    if (nzchar(gpkg)) {
      if (file.exists(gpkg)) unlink(gpkg)
      st_write(do.call(rbind, geoms), gpkg, layer = "parts", quiet = TRUE)
    }
    writeLines(c("ok", sprintf("cells=%d parts=%d k=%d", length(ids), nrow(out), k)), get("status"))
  }
  TRUE
}, error = function(e) { writeLines(c("error", conditionMessage(e)), get("status")); FALSE })
quit(status = 0)
