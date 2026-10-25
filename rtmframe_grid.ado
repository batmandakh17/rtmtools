*! rtmframe_grid.ado  version 0.5.0  25oct2026  rtmtools
*! Grid frame from a population raster and administrative boundaries, without R: a regular grid of
*! cells of cellsize() laid over the raster, the population of each cell summed from the raster's
*! pixels, each pixel assigned to the boundary polygon it falls in (geoinpoly, Picard 2015), the
*! cell's stratum taken from the polygon holding most of its population, and the boundary
*! polygons' attributes carried into the frame. Pixels outside every polygon are dropped and
*! counted, so a cell's population is the population inside the boundaries, exact at the raster's
*! resolution (the cell's area inside the boundaries is counted in pixels, not clipped).
*! Inputs (converted once in a GIS program if needed; see the help): an ESRI shapefile of the
*! boundaries (using) and the raster as an ESRI ASCII grid (raster()), both in the same projected
*! coordinate system in metres. Sources: HFPS Vol. 2 section 1.1 pp. 1-2 (frame options); UN 2008
*! section 4.3 pp. 89-93 (area frames); the Survey Solutions toolbox manual (Wild 2021) for the
*! approach of grid frames, for comparison. The frame replaces the data in memory.
program define rtmframe_grid, rclass
    version 16
    syntax using/, RASter(string) CELLsize(real) [STRata(name) ID(name) MINsize(real 0) SAVing(string) ///
        SAVINGPixels(string) BLOCKs(integer 1) MAXPixels(integer 4000000) CLEAR REPLACE]
    local shp `"`using'"'
    if lower(substr(`"`shp'"', -4, 4)) != ".shp" {
        di as err "using must name the boundaries shapefile (.shp); convert a GeoPackage or GeoJSON file once in QGIS (Layer > Export > Save Features As, ESRI Shapefile, in the raster's projection; see the help)"
        exit 198
    }
    capture confirm file `"`shp'"'
    if _rc {
        di as err `"shapefile not found: `shp'"'
        exit 601
    }
    capture confirm file `"`raster'"'
    if _rc {
        di as err `"raster not found: `raster' (an ESRI ASCII grid, .asc; convert GeoTIFF with QGIS, Raster > Conversion > Translate)"'
        exit 601
    }
    if `cellsize' <= 0 {
        di as err "cellsize() is the side of a cell in the coordinates' units (metres), positive"
        exit 198
    }
    if `blocks' < 1 {
        di as err "blocks() is the number of pixels per side aggregated before the point-in-polygon step (1 = none)"
        exit 198
    }
    if c(changed) & "`clear'" == "" {
        di as err "the data in memory have unsaved changes; save them or add clear"
        exit 4
    }
    foreach cmd in shp2dta geoinpoly {
        capture which `cmd'
        if _rc {
            di as err "rtmframe grid needs the SSC command `cmd'; type {stata ssc install `cmd'} (or rtmtools_setup, install) and run again"
            exit 199
        }
    }
    * shp2dta reads the extension from the first dot of the name, so a path with "." or ".." segments
    * fails: resolve the folder to its canonical absolute form (cd there and back)
    local shpn `"`shp'"'
    local shpn : subinstr local shpn "\" "/", all
    local shpdir = cond(strpos(`"`shpn'"', "/"), substr(`"`shpn'"', 1, strrpos(`"`shpn'"', "/") - 1), ".")
    local shpfile = substr(`"`shpn'"', strrpos(`"`shpn'"', "/") + 1, .)
    local cur `"`c(pwd)'"'
    quietly cd `"`shpdir'"'
    local shpabs `"`c(pwd)'/`shpfile'"'
    quietly cd `"`cur'"'
    local base = substr(`"`shpabs'"', 1, length(`"`shpabs'"') - 4)
    local id = cond("`id'" == "", "_ID", "`id'")

    * ---- 1. the boundaries: shapefile to Stata (attributes and vertex coordinates) ----
    tempfile db co
    quietly shp2dta using `"`base'"', database("`db'") coordinates("`co'") replace
    preserve
    quietly use "`db'", clear
    capture confirm variable _ID
    if _rc {
        di as err "the shapefile could not be read (no _ID after shp2dta)"
        exit 459
    }
    if "`strata'" != "" {
        capture confirm variable `strata'
        if _rc {
            di as err "strata(`strata') is not an attribute of the shapefile; its attributes are: `: di _dup(0) ""'"
            describe, varlist
            exit 111
        }
    }
    if "`id'" != "_ID" {
        capture confirm variable `id'
        if _rc {
            di as err "id(`id') is not an attribute of the shapefile"
            exit 111
        }
    }
    quietly count
    local npoly = r(N)
    tempfile attr
    quietly save "`attr'"
    restore

    * ---- 2. the raster: ESRI ASCII grid header, then the values as pixels ----
    tempname fh
    file open `fh' using `"`raster'"', read text
    local xll .
    local yll .
    local xcenter 0
    forvalues i = 1/6 {
        file read `fh' line
        local line = lower(trim(`"`line'"'))
        gettoken key val : line
        local val = trim("`val'")
        if "`key'" == "ncols" local ncols = real("`val'")
        else if "`key'" == "nrows" local nrows = real("`val'")
        else if "`key'" == "xllcorner" local xll = real("`val'")
        else if "`key'" == "yllcorner" local yll = real("`val'")
        else if "`key'" == "xllcenter" {
            local xll = real("`val'")
            local xcenter 1
        }
        else if "`key'" == "yllcenter" {
            local yll = real("`val'")
            local xcenter 1
        }
        else if "`key'" == "cellsize" local psize = real("`val'")
        else if "`key'" == "nodata_value" local nodata = real("`val'")
    }
    file close `fh'
    if "`ncols'" == "" | "`nrows'" == "" | `xll' == . | `yll' == . | "`psize'" == "" {
        di as err "the raster header is not an ESRI ASCII grid (ncols, nrows, xllcorner, yllcorner, cellsize, NODATA_value expected in the first six lines)"
        exit 198
    }
    if "`nodata'" == "" local nodata -9999
    if `xcenter' {
        local xll = `xll' - `psize' / 2
        local yll = `yll' - `psize' / 2
    }
    if `ncols' * `nrows' > `maxpixels' {
        di as err "the raster has " strtrim(string(`ncols' * `nrows', "%14.0fc")) " pixels, above maxpixels(`maxpixels'); use a coarser product (WorldPop publishes 1 km rasters) or aggregate with blocks()"
        exit 459
    }
    if `cellsize' < `psize' {
        di as err "cellsize(`cellsize') is smaller than the raster's pixels (`psize'); cells must be at least one pixel"
        exit 198
    }
    quietly import delimited using `"`raster'"', delimiter(" ", collapse) rowrange(7) varnames(nonames) clear
    if _N != `nrows' | c(k) < `ncols' {
        di as err "the raster body has " _N " rows and " c(k) " columns, not the nrows x ncols of its header"
        exit 459
    }
    if c(k) > `ncols' {
        * a trailing separator makes an empty last column
        forvalues j = `=`ncols' + 1'/`=c(k)' {
            capture drop v`j'
        }
    }
    quietly gen long row = _n
    quietly reshape long v, i(row) j(col)
    quietly drop if missing(v) | v == `nodata'
    quietly count
    local npix = r(N)
    rename v value
    quietly gen double x = `xll' + (col - 0.5) * `psize'
    quietly gen double y = `yll' + (`nrows' - row + 0.5) * `psize'
    quietly summarize value, meanonly
    local pop_raster = r(sum)
    if `blocks' > 1 {
        * aggregate pixels into blocks (sum of values, centre of the block) before the polygon step
        quietly gen long bcol = floor((col - 1) / `blocks')
        quietly gen long brow = floor((row - 1) / `blocks')
        quietly collapse (sum) value (mean) x y (count) npix = value, by(brow bcol)
        local psize = `psize' * `blocks'
    }
    else quietly gen long npix = 1

    * ---- 3. pixels in polygons ----
    capture drop _ID
    quietly geoinpoly y x using "`co'", noprojection unique
    rename _ID _pid
    quietly count if missing(_pid)
    local npix_out = r(N)
    quietly summarize value if missing(_pid), meanonly
    local pop_out = cond(r(N) > 0, r(sum), 0)
    quietly drop if missing(_pid)
    quietly count
    if r(N) == 0 {
        di as err "no pixel falls inside the boundaries: are the raster and the shapefile in the same projected coordinate system?"
        exit 459
    }
    quietly summarize value, meanonly
    local pop_in = r(sum)
    * keep the pixel table for splits
    quietly gen long cx = floor((x - `xll') / `cellsize')
    quietly gen long cy = floor((y - `yll') / `cellsize')
    local ncx = ceil(`ncols' * `psize' / `cellsize')
    quietly gen long cell_id = cy * `ncx' + cx + 1
    if `"`savingpixels'"' != "" {
        preserve
        keep cell_id _pid x y value npix
        rename _pid unit
        label variable cell_id "Cell of the grid frame"
        label variable unit "Boundary polygon (_ID of the shapefile record)"
        label variable value "Population of the pixel"
        label variable npix "Raster pixels in this record (blocks() > 1 aggregates pixels)"
        quietly save `"`savingpixels'"', `replace'
        restore
    }

    * ---- 4. cells: population by cell and polygon, stratum from the polygon with the largest share ----
    quietly collapse (sum) pop = value npix (first) cx cy, by(cell_id _pid)
    tempvar tot rk
    quietly bysort cell_id: egen double `tot' = total(pop)
    quietly bysort cell_id (pop _pid): gen long `rk' = _N - _n + 1       // 1 = the polygon with the most population (lowest _ID on ties)
    quietly bysort cell_id: gen int parts = _N
    quietly gen double unit_share = pop / `tot'
    quietly bysort cell_id: egen long npix_cell = total(npix)
    quietly keep if `rk' == 1
    quietly replace pop = `tot'
    drop `tot' `rk' npix
    rename npix_cell npix
    rename _pid unit
    quietly gen double x = `xll' + (cx + 0.5) * `cellsize'
    quietly gen double y = `yll' + (cy + 0.5) * `cellsize'
    rename (cx cy) (col row)
    * attributes of the polygon
    rename unit _ID
    quietly merge m:1 _ID using "`attr'", keep(master match) nogenerate
    rename _ID unit
    if "`id'" != "_ID" {
        capture confirm string variable `id'
        if _rc quietly gen str32 unit_name = string(`id')
        else quietly gen str32 unit_name = `id'
    }
    else quietly gen str32 unit_name = string(unit)
    if "`strata'" != "" {
        capture confirm string variable `strata'
        if !_rc {
            tempvar s
            quietly encode `strata', gen(`s')
            drop `strata'
            rename `s' stratum
        }
        else {
            quietly gen long stratum = `strata'
            local lbl : value label `strata'
            if "`lbl'" != "" label values stratum `lbl'
        }
    }
    else quietly gen long stratum = unit
    quietly count if pop <= 0
    local n_empty = r(N)
    quietly drop if pop <= 0
    if `minsize' > 0 quietly gen byte small = (pop < `minsize')
    else quietly gen byte small = 0
    quietly count if small
    local n_small = r(N)
    quietly count if parts > 1
    local n_straddle = r(N)
    quietly count
    local ncells = r(N)
    sort cell_id
    order cell_id col row x y unit unit_name stratum pop npix parts unit_share small
    label variable cell_id "Cell identifier (row-major over the grid)"
    label variable col "Cell column (0 = west)"
    label variable row "Cell row (0 = south)"
    label variable x "Cell centre x (coordinates of the shapefile)"
    label variable y "Cell centre y"
    label variable unit "Boundary polygon holding most of the cell's population (_ID)"
    label variable unit_name "Its identifier (id())"
    label variable stratum "Stratum of the cell (strata() of that polygon)"
    label variable pop "Population of the cell inside the boundaries (sum of the raster pixels)"
    label variable npix "Raster pixels inside the boundaries in the cell"
    label variable parts "Boundary polygons the cell's pixels fall in (above 1: the cell straddles a boundary)"
    label variable unit_share "Share of the cell's population in its main polygon"
    label variable small "Population below minsize()"
    char _dta[rtm_grid_cellsize] "`cellsize'"
    char _dta[rtm_grid_pixel] "`psize'"
    char _dta[rtm_grid_xll] "`xll'"
    char _dta[rtm_grid_yll] "`yll'"
    char _dta[rtm_grid_ncx] "`ncx'"
    char _dta[rtm_grid_shapefile] `"`shp'"'
    char _dta[rtm_grid_raster] `"`raster'"'

    * ---- 5. report ----
    quietly levelsof stratum, local(slev)
    local H : word count `slev'
    di as text _n "Grid frame ({bf:rtmframe grid}): cells of " as result `cellsize' as text " m over " as result "`raster'" as text " (" `nrows' " x " `ncols' " pixels of " `psize' " m), boundaries " as result "`shp'" as text " (" `npoly' " polygons)"
    di as text "Cells with population inside the boundaries: " as result strtrim(string(`ncells', "%12.0fc")) as text "; empty cells dropped: " as result `n_empty' ///
        as text "; cells straddling a boundary: " as result `n_straddle' cond(`minsize' > 0, "; below minsize(`minsize'): " + string(`n_small'), "")
    di as text "Population: raster " as result %14.0fc `pop_raster' as text "; inside the boundaries (the frame) " as result %14.0fc `pop_in' ///
        as text "; outside " as result %14.0fc `pop_out' as text " in " strtrim(string(`npix_out', "%12.0fc")) " pixels"
    di as text "{hline 84}"
    di as text %-24s "stratum" %9s "cells" %14s "population" %10s "min" %10s "median" %10s "max"
    di as text "{hline 84}"
    tempname T
    matrix `T' = J(`H', 5, .)
    local g 0
    local vl : value label stratum
    foreach l of local slev {
        local ++g
        quietly summarize pop if stratum == `l', detail
        if "`vl'" != "" local lt : label `vl' `l'
        else local lt "`l'"
        if `g' <= 40 di as text %-24s abbrev("`lt'", 24) as result %9.0fc r(N) %14.0fc r(sum) %10.0fc r(min) %10.0fc r(p50) %10.0fc r(max)
        matrix `T'[`g', 1] = r(N), r(sum), r(min), r(p50), r(max)
    }
    di as text "{hline 84}"
    di as text "A straddling cell belongs to the polygon with most of its population (unit_share shows how much); its area inside"
    di as text "the boundaries is counted in pixels. Replacement cells: rtmframe replace; splits of large cells: rtmframe split (needs savingpixels())."
    matrix colnames `T' = cells pop pop_min pop_p50 pop_max
    if `"`saving'"' != "" {
        quietly save `"`saving'"', `replace'
        di as text `"Frame saved to `saving'"'
    }
    return matrix table = `T', copy
    return scalar N_cells = `ncells'
    return scalar H = `H'
    return scalar n_polygons = `npoly'
    return scalar n_empty = `n_empty'
    return scalar n_straddle = `n_straddle'
    return scalar n_small = `n_small'
    return scalar pop_raster = `pop_raster'
    return scalar pop_inside = `pop_in'
    return scalar pop_outside = `pop_out'
    return scalar pixels_outside = `npix_out'
    return scalar cellsize = `cellsize'
    return scalar pixelsize = `psize'
    local cmd `"rtmframe grid using "`shp'" `=cond(strpos(`"`0'"', ","), substr(`"`0'"', strpos(`"`0'"', ","), .), "")'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(frame) cmd(`"`cmd'"') var(cell_id)

    * ---- 6. export: the cells, the summary by stratum, the boundary vertices for the map ----
    capture frame drop _rtmx_fu
    frame put cell_id stratum unit_name pop x y small, into(_rtmx_fu)
    frame _rtmx_fu {
        quietly gen str32 unit_id = string(cell_id)
        rename (unit_name pop) (unit size)
        quietly gen str32 flag = cond(small == 1, "small", "")
        quietly gen str32 stratum_s = string(stratum)
        drop stratum small cell_id
        rename stratum_s stratum
        order unit_id stratum unit size x y flag
    }
    capture _rtm_export table, name(frame_units) frame(_rtmx_fu)
    capture frame drop _rtmx_fs
    frame create _rtmx_fs str32 stratum double(n_units size_sum size_min size_p50 size_max n_flagged)
    local g 0
    foreach l of local slev {
        local ++g
        quietly count if stratum == `l' & small
        frame post _rtmx_fs ("`l'") (`T'[`g', 1]) (`T'[`g', 2]) (`T'[`g', 3]) (`T'[`g', 4]) (`T'[`g', 5]) (r(N))
    }
    capture _rtm_export table, name(frame_summary) frame(_rtmx_fs)
    capture frame drop _rtmx_bd
    frame create _rtmx_bd
    frame _rtmx_bd {
        quietly use "`co'", clear
        quietly gen long vertex = _n
        * shp2dta separates the parts of a polygon by a row of missing coordinates
        quietly gen byte sep = missing(_X)
        quietly bysort _ID (vertex): gen long part = sum(sep)
        quietly drop if sep
        tempvar pmin
        quietly bysort _ID: egen long `pmin' = min(part)
        quietly replace part = part - `pmin' + 1
        drop sep `pmin'
        quietly bysort _ID part (vertex): replace vertex = _n
        rename (_ID _X _Y) (polygon_id x y)
        order polygon_id part vertex x y
    }
    capture _rtm_export table, name(boundaries) frame(_rtmx_bd)
    capture _rtm_export setting, key(shapefile) value(`"`shp'"')
    capture _rtm_export setting, key(raster) value(`"`raster'"')
    capture _rtm_export setting, key(cellsize) value("`cellsize'") source("HFPS Vol. 2 section 1.1; UN 2008 section 4.3")
    capture _rtm_export setting, key(stratum_rule) value("polygon with most of the cell's population") source("no cited default; labeled choice")
    if "`strata'" != "" capture _rtm_export setting, key(strata) value("`strata'")
    if `minsize' > 0 capture _rtm_export setting, key(minsize) value("`minsize'")
    if `blocks' > 1 capture _rtm_export setting, key(blocks) value("`blocks'")
    capture _rtm_export setting, key(crs) value("as in the shapefile; coordinates in its units")
end
