"""Synthetic spatial data for rtmtools, without R: four regions over a 100 km square (EPSG:32633)
as an ESRI shapefile, and a 1 km population raster as an ESRI ASCII grid. The region borders are
wavy so that grid cells straddle them. No real place or person is represented.

Run from the data folder:  python3 make_rtm_spatial.py
Writes rtm_boundaries.shp (+ .shx .dbf .prj .cpg) and rtm_population.asc.
Needs geopandas and shapely (fixtures only; the Stata commands read the files with shp2dta,
geoinpoly and import delimited).
"""
import numpy as np
import geopandas as gpd
from shapely.geometry import LineString, box
from shapely.ops import split

X0, Y0, SIDE, CELL = 300000.0, 4000000.0, 100000.0, 1000.0
rng = np.random.default_rng(20261025)

# ---- regions: a square split by two wavy lines ----
square = box(X0, Y0, X0 + SIDE, Y0 + SIDE)
ys = np.linspace(Y0 - 1, Y0 + SIDE + 1, 200)
vline = LineString([(X0 + SIDE / 2 + 6000 * np.sin((y - Y0) / 12000), y) for y in ys])
xs = np.linspace(X0 - 1, X0 + SIDE + 1, 200)
hline = LineString([(x, Y0 + SIDE / 2 + 5000 * np.cos((x - X0) / 15000)) for x in xs])
pieces = [square]
for line in (vline, hline):
    out = []
    for p in pieces:
        out.extend(list(split(p, line).geoms))
    pieces = out
rows = []
for p in pieces:
    c = p.centroid
    west = c.x < X0 + SIDE / 2
    north = c.y > Y0 + SIDE / 2
    name = ("North" if north else "South") + "-" + ("West" if west else "East")
    code = {"North-West": 1, "North-East": 2, "South-West": 3, "South-East": 4}[name]
    rows.append({"region": name, "regcode": code, "geometry": p})
g = gpd.GeoDataFrame(rows, crs="EPSG:32633").dissolve(by="regcode", as_index=False)
g = g[["region", "regcode", "geometry"]]
g.to_file("rtm_boundaries.shp")

# ---- population raster: three towns on a rural background, 1 km pixels ----
n = int(SIDE / CELL)
cx = X0 + (np.arange(n) + 0.5) * CELL
cy = Y0 + SIDE - (np.arange(n) + 0.5) * CELL          # row 0 is the top row (ESRI ASCII convention)
XX, YY = np.meshgrid(cx, cy)
pop = 25 + 10 * rng.random((n, n))
for (tx, ty, peak, sd) in [(330000, 4070000, 1800, 6000), (372000, 4035000, 1200, 5000), (345000, 4022000, 600, 4000)]:
    pop += peak * np.exp(-((XX - tx) ** 2 + (YY - ty) ** 2) / (2 * sd ** 2))
pop = np.round(pop * (0.8 + 0.4 * rng.random((n, n)))).astype(int)
with open("rtm_population.asc", "w") as fh:
    fh.write(f"ncols {n}\nnrows {n}\nxllcorner {X0:.0f}\nyllcorner {Y0:.0f}\ncellsize {CELL:.0f}\nNODATA_value -9999\n")
    for r in range(n):
        fh.write(" ".join(str(v) for v in pop[r]) + "\n")
print("regions:", list(g.region), "| areas km2:", [round(a / 1e6) for a in g.area])
print("raster: %d x %d pixels of %.0f m, population %d" % (n, n, CELL, pop.sum()))
