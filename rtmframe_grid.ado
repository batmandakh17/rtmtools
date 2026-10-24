*! rtmframe_grid.ado  version 0.3.0  24oct2026  rtmtools
*! Grid frame over boundaries (R: sf and terra through rtm_grid.R): square cells clipped to the
*! boundaries, a stratum from the boundary feature with the largest overlap, the measure of size
*! from a population raster (exact zonal sums) or from points, optional k-means groups, and the
*! cells written as a GeoPackage for maps and field work. The frame replaces the data in memory.
*! Sources: Capturing What Matters 2021 (PDF p. 17: grid-based sampling where no frame exists);
*! Wild 2021 (Spatial Sampling Application manual) and the susospatsample and susorastoframe
*! READMEs for the steps the apps take; UN 2008 section 4.1.2 (frame properties).
program define rtmframe_grid, rclass
    version 16
    syntax using/, [Layer(string) RASTER(string) POINTS(string) POINTWeight(string) CELLsize(real 0) ///
        NCELLs(integer 0) STRata(string) GROUPS(integer 0) MINpop(real 0) KEEPempty CRS(integer 0) ///
        SEED(integer 1) SAVing(string) MAP(string) CLEAR]
    local boundaries `"`using'"'
    capture confirm file `"`boundaries'"'
    if _rc {
        di as err `"boundaries file not found: `boundaries'"'
        exit 601
    }
    if `"`raster'"' != "" {
        capture confirm file `"`raster'"'
        if _rc {
            di as err `"raster file not found: `raster'"'
            exit 601
        }
    }
    if `"`points'"' != "" {
        capture confirm file `"`points'"'
        if _rc {
            di as err `"points file not found: `points'"'
            exit 601
        }
    }
    if `"`raster'"' != "" & `"`points'"' != "" {
        di as err "give raster() or points() for the measure of size, not both"
        exit 198
    }
    if `cellsize' <= 0 & `ncells' <= 0 {
        di as err "give cellsize(#), the side of a cell in metres, or ncells(#), the approximate number of cells"
        exit 198
    }
    if `cellsize' > 0 & `ncells' > 0 {
        di as err "give cellsize() or ncells(), not both"
        exit 198
    }
    if `groups' < 0 | `groups' == 1 {
        di as err "groups() is the number of homogeneous groups to form from the measure of size (2 or more)"
        exit 198
    }
    if `groups' > 1 & `"`raster'"' == "" & `"`points'"' == "" {
        di as err "groups() needs a measure of size: give raster() or points()"
        exit 198
    }
    if c(changed) & "`clear'" == "" {
        di as err "no; the data in memory would be lost (the grid frame replaces them); add the clear option"
        exit 4
    }
    tempfile args status out
    tempname fh
    quietly file open `fh' using "`args'", write text replace
    file write `fh' "status=`status'" _n `"boundaries=`boundaries'"' _n `"layer=`layer'"' _n `"raster=`raster'"' _n ///
        `"points=`points'"' _n "pointweight=`pointweight'" _n "cellsize=`cellsize'" _n "ncells=`ncells'" _n ///
        "strata=`strata'" _n "groups=`groups'" _n "minpop=`minpop'" _n "keepempty=`=("`keepempty'" != "")'" _n ///
        "crs=`crs'" _n "seed=`seed'" _n "out=`out'" _n `"gpkg=`saving'"' _n `"map=`map'"' _n
    file close `fh'
    _rtm_runr, script(rtm_grid.R) args("`args'") status("`status'") quietly
    local msg `"`r(message)'"'
    foreach tok of local msg {
        gettoken k v : tok, parse("=")
        local v = substr("`v'", 2, .)
        local R_`k' "`v'"
    }
    use "`out'", clear
    quietly compress
    label variable cell_id "Grid cell identifier"
    label variable stratum "Stratum (boundary feature with the largest overlap)"
    label variable pop "Measure of size (raster sum or points inside the cell)"
    label variable area_km2 "Area of the cell inside the boundaries, km2"
    label variable x "Centroid x (projected, EPSG `R_epsg')"
    label variable y "Centroid y (projected, EPSG `R_epsg')"
    label variable lon "Centroid longitude (WGS84)"
    label variable lat "Centroid latitude (WGS84)"
    label variable lon_min "Bounding box west (WGS84)"
    label variable lat_min "Bounding box south (WGS84)"
    label variable lon_max "Bounding box east (WGS84)"
    label variable lat_max "Bounding box north (WGS84)"
    label variable feature "Row of the boundary feature the cell belongs to"
    capture label variable group "k-means group of the measure of size (1 = smallest)"
    sort cell_id
    label data "Grid frame built by rtmframe grid (rtmtools): `R_cells' cells of `R_cellsize' m"
    * ---- report ----
    di as text _n "Grid frame ({bf:rtmframe grid}): " as result "`R_cells'" as text " cells of " as result strtrim(string(real("`R_cellsize'"), "%12.0fc")) ///
        as text " m, clipped to " as result `"`boundaries'"'
    di as text "Coordinates: EPSG " as result "`R_epsg'" as text cond(`"`raster'"' != "", `"; measure of size: raster `raster'"', cond(`"`points'"' != "", `"; measure of size: points `points'"', "; no measure of size"))
    if `"`raster'"' != "" | `"`points'"' != "" {
        di as text "Population in the frame: " as result strtrim(string(real("`R_pop'"), "%14.0fc")) as text "; in the boundaries: " as result strtrim(string(real("`R_raster_total'"), "%14.0fc")) ///
            as text cond(real("`R_dropped'") > 0, "; cells dropped for size at or below minpop(`minpop'): " + "`R_dropped'", "")
    }
    quietly levelsof stratum, local(levs)
    local H : word count `levs'
    di as text "{hline 96}"
    di as text %-24s "stratum" %9s "cells" %14s "size total" %10s "min" %10s "median" %10s "max" %12s "area km2"
    di as text "{hline 96}"
    tempname T
    matrix `T' = J(`H', 6, .)
    local g 0
    foreach l of local levs {
        local ++g
        quietly count if stratum == `"`l'"'
        local n = r(N)
        quietly summarize pop if stratum == `"`l'"', detail
        local Sg = r(sum)
        local mn = r(min)
        local md = r(p50)
        local mx = r(max)
        if r(N) == 0 local Sg .
        quietly summarize area_km2 if stratum == `"`l'"', meanonly
        local A = r(sum)
        if `g' <= 40 di as text %-24s abbrev(`"`l'"', 24) as result %9.0fc `n' %14.0fc `Sg' %10.0fc `mn' %10.0fc `md' %10.0fc `mx' %12.1fc `A'
        matrix `T'[`g', 1] = `n', `Sg', `mn', `md', `mx', `A'
    }
    if `H' > 40 di as text "  ... (all `H' strata are in r(table))"
    di as text "{hline 96}"
    if `groups' > 1 {
        di as text "Groups from k-means on log(1 + size), `groups' groups (variable group, 1 = smallest):"
        tabulate group, missing
    }
    if `"`saving'"' != "" di as text `"Cells and boundaries written to {browse "`saving'"} (layers cells, boundaries)"'
    if `"`map'"' != "" di as text `"Map written to {browse "`map'"}"'
    matrix colnames `T' = cells size_total size_min size_p50 size_max area_km2
    local rn ""
    forvalues g = 1/`H' {
        local rn "`rn' s`g'"
    }
    matrix rownames `T' = `rn'
    return matrix table = `T'
    return scalar N_cells = real("`R_cells'")
    return scalar dropped = real("`R_dropped'")
    return scalar pop_total = real("`R_pop'")
    return scalar pop_boundaries = real("`R_raster_total'")
    return scalar cellsize = real("`R_cellsize'")
    return scalar epsg = real("`R_epsg'")
    return scalar H = `H'
    return scalar groups = `groups'
    return local gpkg `"`saving'"'
    return local boundaries `"`boundaries'"'
    return local versions "sf `R_sf' terra `R_terra'"
    local cmd `"rtmframe grid using "`boundaries'" `=cond(strpos(`"`0'"', ","), substr(`"`0'"', strpos(`"`0'"', ","), .), "")'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(frame) cmd(`"`cmd'"')
end
