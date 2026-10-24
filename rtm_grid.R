# rtm_grid.R -- rtmtools: build a grid frame over boundaries (used by rtmframe grid)
# Arguments file (key=value): status, boundaries (file), layer (optional), raster (optional),
#   points (optional), pointweight (optional), cellsize (metres) or ncells, strata (column of the
#   boundaries or empty), groups (k-means groups, 0 = none), minpop, keepempty (0/1), crs (EPSG, 0 =
#   choose), seed, out (dta), gpkg (optional), map (png, optional).
# Method: cells of a square grid over the boundaries, clipped to them; stratum = the boundary
#   feature with the largest overlap; measure of size = sum of the raster inside the cell (exact
#   fraction of boundary raster cells, terra::extract(exact = TRUE)) or the number (or weight) of
#   points inside; optional k-means grouping of log(1 + size) into homogeneous strata (the grouping
#   susorastoframe offers). Nothing is downloaded; all files are local.
args <- commandArgs(trailingOnly = TRUE)
cfg <- readLines(args[1], warn = FALSE)
kv <- strsplit(cfg, "=", fixed = TRUE)
cfg <- setNames(vapply(kv, function(x) paste(x[-1], collapse = "="), ""), vapply(kv, `[`, "", 1))
get <- function(k, default = "") if (k %in% names(cfg) && nzchar(cfg[[k]])) cfg[[k]] else default
res <- tryCatch({
  suppressPackageStartupMessages({library(sf); library(haven)})
  suppressMessages(sf_use_s2(FALSE))
  layer <- get("layer")
  b <- if (nzchar(layer)) st_read(get("boundaries"), layer = layer, quiet = TRUE) else st_read(get("boundaries"), quiet = TRUE)
  b <- st_zm(b, drop = TRUE)
  if (is.na(st_crs(b))) stop("the boundaries file has no coordinate reference system; assign one (for example EPSG:4326) before using it")
  crs_arg <- as.numeric(get("crs", "0"))
  if (crs_arg > 0) b <- st_transform(b, crs_arg)
  else if (st_is_longlat(b)) {
    ctr <- suppressWarnings(st_coordinates(st_centroid(st_union(b))))
    zone <- floor((ctr[1] + 180) / 6) + 1
    b <- st_transform(b, if (ctr[2] >= 0) 32600 + zone else 32700 + zone)
  }
  epsg <- st_crs(b)$epsg
  if (!all(st_is_valid(b))) b <- st_make_valid(b)
  bcols <- setdiff(names(b), attr(b, "sf_column"))
  strata <- get("strata")
  if (nzchar(strata) && !strata %in% bcols) stop(sprintf("strata variable %s is not a column of the boundaries (columns: %s)", strata, paste(bcols, collapse = " ")))
  outline <- st_union(st_geometry(b))
  total_area <- as.numeric(st_area(outline))
  cellsize <- as.numeric(get("cellsize", "0"))
  ncells <- as.numeric(get("ncells", "0"))
  if (cellsize <= 0 && ncells <= 0) stop("give cellsize() in metres or ncells()")
  if (cellsize <= 0) cellsize <- sqrt(total_area / ncells)
  bb <- st_bbox(b)
  est <- ((bb["xmax"] - bb["xmin"]) / cellsize) * ((bb["ymax"] - bb["ymin"]) / cellsize)
  if (est > 250000) stop(sprintf("cellsize %.0f m would give about %.0f cells over the boundaries' extent; cellsize() is in metres (10 km = 10000), choose a larger cell or ncells()", cellsize, est))
  grid <- st_make_grid(b, cellsize = cellsize, what = "polygons", square = TRUE)
  grid <- grid[lengths(st_intersects(grid, outline)) > 0]
  # clip every cell to the boundaries (one multipolygon per cell)
  clip <- lapply(seq_along(grid), function(i) {
    x <- suppressWarnings(st_intersection(grid[i], outline))
    if (length(x) == 0) return(st_sfc(st_polygon(), crs = st_crs(b)))
    st_sfc(st_union(x), crs = st_crs(b))
  })
  cells <- st_sf(gid = seq_along(grid), geometry = do.call(c, clip))
  cells <- cells[!st_is_empty(cells), ]
  cells$area_km2 <- as.numeric(st_area(cells)) / 1e6
  cells <- cells[cells$area_km2 > 1e-9, ]
  # stratum: the boundary feature with the largest overlap
  bgeom <- st_geometry(b)
  hits <- st_intersects(cells, bgeom)
  cells$feature <- vapply(seq_len(nrow(cells)), function(i) {
    fs <- hits[[i]]
    if (length(fs) == 0) return(NA_integer_)
    if (length(fs) == 1) return(as.integer(fs))
    a <- vapply(fs, function(j) as.numeric(st_area(suppressWarnings(st_intersection(st_geometry(cells)[i], bgeom[j])))), 0)
    as.integer(fs[which.max(a)])
  }, 1L)
  cells <- cells[!is.na(cells$feature), ]
  cells$stratum <- if (nzchar(strata)) as.character(st_drop_geometry(b)[[strata]][cells$feature]) else "all"
  # measure of size
  rfile <- get("raster"); pfile <- get("points"); pw <- get("pointweight")
  cells$pop <- NA_real_
  raster_total <- NA_real_
  if (nzchar(rfile)) {
    suppressPackageStartupMessages(library(terra))
    r <- rast(rfile)
    if (nlyr(r) > 1) r <- r[[1]]
    if (!same.crs(crs(r), st_crs(cells)$wkt)) r <- project(r, st_crs(cells)$wkt, method = "near")
    ex <- terra::extract(r, vect(cells), fun = sum, exact = TRUE, na.rm = TRUE)
    cells$pop <- as.numeric(ex[, 2])
    raster_total <- as.numeric(terra::extract(r, vect(st_sf(geometry = outline)), fun = sum, exact = TRUE, na.rm = TRUE)[, 2])
  } else if (nzchar(pfile)) {
    p <- st_read(pfile, quiet = TRUE)
    p <- st_transform(st_zm(p, drop = TRUE), st_crs(cells))
    w <- if (nzchar(pw)) as.numeric(st_drop_geometry(p)[[pw]]) else rep(1, nrow(p))
    ph <- st_intersects(cells, p)
    cells$pop <- vapply(ph, function(i) sum(w[i], na.rm = TRUE), 0)
    raster_total <- sum(w, na.rm = TRUE)
  }
  n_before <- nrow(cells)
  minpop <- as.numeric(get("minpop", "0"))
  keepempty <- get("keepempty", "0") == "1"
  if (!all(is.na(cells$pop)) && !keepempty) cells <- cells[cells$pop > minpop, ]
  dropped <- n_before - nrow(cells)
  groups <- as.integer(get("groups", "0"))
  if (groups > 1) {
    if (all(is.na(cells$pop))) stop("groups() needs a measure of size: give raster() or points()")
    if (groups >= nrow(cells)) stop("groups() must be smaller than the number of cells")
    set.seed(as.integer(get("seed", "1")))
    km <- kmeans(log1p(cells$pop), centers = groups, nstart = 25)
    ord <- order(tapply(cells$pop, km$cluster, mean))
    cells$group <- match(km$cluster, ord)
  }
  cells <- cells[order(cells$gid), ]
  cells$cell_id <- seq_len(nrow(cells))
  cent <- suppressWarnings(st_centroid(st_geometry(cells)))
  xy <- st_coordinates(cent)
  ll <- st_coordinates(st_transform(cent, 4326))
  bb <- t(vapply(seq_len(nrow(cells)), function(i) as.numeric(st_bbox(st_transform(st_geometry(cells)[i], 4326))), numeric(4)))
  out <- data.frame(cell_id = cells$cell_id, stratum = cells$stratum, pop = cells$pop, area_km2 = cells$area_km2,
                    x = xy[, 1], y = xy[, 2], lon = ll[, 1], lat = ll[, 2],
                    lon_min = bb[, 1], lat_min = bb[, 2], lon_max = bb[, 3], lat_max = bb[, 4],
                    feature = cells$feature, stringsAsFactors = FALSE)
  if (groups > 1) out$group <- cells$group
  battrs <- st_drop_geometry(b)[cells$feature, bcols, drop = FALSE]
  names(battrs) <- make.names(paste0("b_", names(battrs)), unique = TRUE)
  rownames(battrs) <- NULL
  out <- cbind(out, battrs)
  haven::write_dta(out, get("out"), version = 14)
  gpkg <- get("gpkg")
  if (nzchar(gpkg)) {
    cells_out <- cells
    cells_out$lon <- ll[, 1]; cells_out$lat <- ll[, 2]
    keepcols <- c("cell_id", "stratum", if (groups > 1) "group", "pop", "area_km2", "lon", "lat", "feature")
    if (file.exists(gpkg)) unlink(gpkg)
    st_write(cells_out[, keepcols], gpkg, layer = "cells", quiet = TRUE)
    st_write(b, gpkg, layer = "boundaries", quiet = TRUE)
  }
  mapfile <- get("map")
  if (nzchar(mapfile)) {
    png(mapfile, width = 1600, height = 1400, res = 180)
    par(mar = c(1, 1, 2, 1))
    if (!all(is.na(cells$pop))) {
      brks <- unique(quantile(cells$pop, probs = seq(0, 1, 0.2), na.rm = TRUE))
      if (length(brks) < 2) brks <- range(cells$pop) + c(-1, 1)
      q <- cut(cells$pop, breaks = brks, include.lowest = TRUE)
      cols <- hcl.colors(nlevels(q), "YlOrRd", rev = TRUE)
      plot(st_geometry(cells), col = cols[q], border = "grey60", lwd = 0.5, main = sprintf("Grid frame: %d cells of %.1f km", nrow(cells), cellsize / 1000))
      legend("bottomleft", legend = levels(q), fill = cols, bty = "n", cex = 0.7, title = "measure of size")
    } else plot(st_geometry(cells), border = "grey60", lwd = 0.5, main = sprintf("Grid frame: %d cells", nrow(cells)))
    plot(st_geometry(b), add = TRUE, border = "black", lwd = 1.5)
    dev.off()
  }
  writeLines(c("ok", sprintf("cells=%d dropped=%d pop=%.6g raster_total=%.6g epsg=%s cellsize=%.6g strata=%d groups=%d sf=%s terra=%s",
                             nrow(cells), dropped, sum(cells$pop, na.rm = TRUE), raster_total, as.character(epsg), cellsize,
                             length(unique(cells$stratum)), groups, as.character(packageVersion("sf")),
                             if (nzchar(rfile)) as.character(packageVersion("terra")) else "none")), get("status"))
  TRUE
}, error = function(e) { writeLines(c("error", conditionMessage(e)), get("status")); FALSE })
quit(status = 0)
