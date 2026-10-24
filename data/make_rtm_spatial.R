# make_rtm_spatial.R -- synthetic spatial data for rtmtools (no real place is represented)
# Writes rtm_boundaries.gpkg (four regions of a 100 km square "country" with a corner cut off,
# projected CRS EPSG:32633) and rtm_population.tif (1 km population raster with two towns).
# Run from the data folder: Rscript make_rtm_spatial.R
suppressPackageStartupMessages({library(sf); library(terra)})
set.seed(20261024)
x0 <- 300000; y0 <- 4000000; L <- 100000
xs <- x0 + 46000; ys <- y0 + 54000          # region borders, off the 10 km grid on purpose
country <- st_polygon(list(rbind(c(x0, y0), c(x0 + L, y0), c(x0 + L, y0 + 70000), c(x0 + 70000, y0 + L),
                                 c(x0, y0 + L), c(x0, y0))))
rect <- function(a, b, c, d) st_polygon(list(rbind(c(a, b), c(c, b), c(c, d), c(a, d), c(a, b))))
quads <- st_sfc(rect(x0, ys, xs, y0 + L), rect(xs, ys, x0 + L, y0 + L), rect(x0, y0, xs, ys), rect(xs, y0, x0 + L, ys), crs = 32633)
regions <- st_sf(region = c("North-West", "North-East", "South-West", "South-East"),
                 region_code = 1:4, geometry = st_intersection(quads, st_sfc(country, crs = 32633)))
r <- rast(xmin = x0, xmax = x0 + L, ymin = y0, ymax = y0 + L, resolution = 1000, crs = "EPSG:32633")
xy <- xyFromCell(r, 1:ncell(r))
d1 <- sqrt((xy[, 1] - (x0 + 30000))^2 + (xy[, 2] - (y0 + 70000))^2) / 1000
d2 <- sqrt((xy[, 1] - (x0 + 75000))^2 + (xy[, 2] - (y0 + 25000))^2) / 1000
pop <- 2000 * exp(-d1 / 8) + 600 * exp(-d2 / 6) + 15 + rexp(ncell(r), 1 / 10)
pop <- round(pop * (runif(ncell(r)) > 0.15))
values(r) <- pop
names(r) <- "population"
writeRaster(r, "rtm_population.tif", overwrite = TRUE, datatype = "INT4S")
st_write(regions, "rtm_boundaries.gpkg", layer = "regions", delete_dsn = TRUE, quiet = TRUE)
cat("rtm_boundaries.gpkg:", nrow(regions), "regions;", "rtm_population.tif:", ncell(r), "cells, total",
    global(r, "sum", na.rm = TRUE)[[1]], "\n")
