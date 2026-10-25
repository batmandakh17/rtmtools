********************************************************************************************
* 01_frame.do  --  the sampling frame of areas: checks on a list frame, and a grid frame from a
* population raster and administrative boundaries, in plain Stata (no rtmtools command, no R)
* rtmtools portable do-files, version 0.5.0 (25 October 2026)
*
* Route A (list frame): duplicate identifiers, missing or non-positive sizes, units too small or
*   too large, excluded units, population checks (Grosh and Munoz 1996 pp. 80-81; UN 2008 section 4.1.2).
* Route B (grid frame): a grid of cells over an ESRI ASCII population raster, each pixel assigned
*   to the boundary polygon it falls in (geoinpoly), cells summed, stratum from the polygon holding
*   most of the cell's population (HFPS Vol. 2 section 1.1; UN 2008 section 4.3). Needs the files
*   prepared once in a GIS program (shapefile and ASCII grid, same projected coordinate system).
* Every step is exported (schema rtm-export-1.0) like the rtmframe commands.
* To adopt it: change only the PARAMETERS block, following ADAPTATION.md.
********************************************************************************************
version 16
clear all
set more off

* ======================= PARAMETERS: change these lines only ===============================
local route          list       // list | grid
local export_dir     "rtm_exports"
local helpers        "_export_helpers.do"
local template_xlsx  "rtm_display.xlsx"
* --- route A: list frame ---
local data_frame     "template/rtm_frame.dta"   // one row per area
local area_id        ea_id
local size           ea_size_census  // measure of size (households); "" if none
local strata         "stratum"
local exclude        ""         // 0/1 variable marking excluded areas; "" if none
local minsize        80         // flag areas below this size (GM 1996 p. 81: under 30 households appended); 0 = no flag
local maxsize        250        // flag areas above this size (GM 1996 p. 84: over 300 segmented); 0 = no flag
local saving_list    "frame_checked.dta"
* --- route B: grid frame ---
local shapefile      "template/rtm_boundaries.shp"   // boundaries, ESRI shapefile, projected (metres)
local raster         "template/rtm_population.asc"   // population, ESRI ASCII grid, same coordinate system
local cellsize       5000       // cell side in metres
local strata_attr    regcode    // attribute of the shapefile giving the stratum ("" = each polygon)
local id_attr        region     // attribute naming the polygon ("" = record number)
local min_pop        500        // flag cells with population below this (0 = no flag)
local saving_grid    "frame_grid.dta"
local saving_pixels  "frame_pixels.dta"
* ===========================================================================================

capture confirm file "`helpers'"
if _rc {
    di as err "the export helpers `helpers' were not found; run this do-file from the portable_do_files folder"
    exit 601
}
run "`helpers'"
global RTM_EXPORT ""
global RTM_EXPORT_DIR "`export_dir'"
global RTM_EXPORT_TEMPLATE "`template_xlsx'"
global RTM_EXPORT_SOURCE "dofile"
if !inlist("`route'", "list", "grid") {
    di as err "parameter route must be list or grid"
    exit 198
}

if "`route'" == "list" {
    * ---- A. Checks on the list frame -----------------------------------------------------
    use "`data_frame'", clear
    rtmx_start, workflow(frame) step(list) cmd("01_frame.do route A: checks on the list frame")
    * duplicate identifiers (a frame unit must be listed once: UN 2008 section 4.1.2)
    bysort `area_id': gen byte frame_dup = (_N > 1)
    * measure of size missing or not positive (PPS needs sizes)
    gen byte frame_badsize = 0
    if "`size'" != "" replace frame_badsize = (missing(`size') | `size' <= 0)
    * too small to sample on their own, too large to list without segmentation
    gen byte frame_small = 0
    gen byte frame_large = 0
    gen double frame_segments = .
    if "`size'" != "" & `minsize' > 0 replace frame_small = (`size' < `minsize') if !frame_badsize
    if "`size'" != "" & `maxsize' > 0 {
        replace frame_large = (`size' > `maxsize') if !frame_badsize
        replace frame_segments = max(2, round(`size' / `maxsize')) if frame_large
    }
    gen byte frame_excl = 0
    if "`exclude'" != "" replace frame_excl = (`exclude' == 1)
    gen byte frame_ok = (frame_dup == 0 & frame_badsize == 0 & frame_excl == 0)
    label variable frame_ok "Usable frame unit (unique id, positive size, not excluded)"
    label variable frame_dup "Identifier not unique"
    label variable frame_badsize "Measure of size missing or not positive"
    label variable frame_small "Size below `minsize'"
    label variable frame_large "Size above `maxsize'"
    label variable frame_segments "Segments suggested for a large unit"
    label variable frame_excl "Excluded from coverage"
    quietly count
    local N = r(N)
    foreach f in dup badsize small large excl ok {
        quietly count if frame_`f' == 1
        local n_`f' = r(N)
    }
    di as text _n "Frame checks: `N' units; duplicate ids `n_dup'; bad sizes `n_badsize'; small `n_small'; large `n_large'; excluded `n_excl'; usable `n_ok'"
    * exports: the units with their flags, the summary by stratum
    capture frame drop _rtmx_fu
    gen str32 unit_id = string(`area_id')
    gen str64 flag = ""
    replace flag = "duplicate id" if frame_dup
    replace flag = flag + cond(flag == "", "", "; ") + "bad size" if frame_badsize
    replace flag = flag + cond(flag == "", "", "; ") + "small" if frame_small
    replace flag = flag + cond(flag == "", "", "; ") + "large: " + string(frame_segments) + " segments" if frame_large
    replace flag = flag + cond(flag == "", "", "; ") + "excluded" if frame_excl
    tempvar sz st
    if "`size'" != "" gen double `sz' = `size'
    else gen double `sz' = .
    egen long `st' = group(`strata')
    frame put unit_id `st' `sz' flag, into(_rtmx_fu)
    frame _rtmx_fu {
        rename (`st' `sz') (stratum_n size)
        gen str32 stratum = string(stratum_n)
        gen str32 unit = ""
        gen double x = .
        gen double y = .
        drop stratum_n
        order unit_id stratum unit size x y flag
    }
    rtmx_table, name(frame_units) frame(_rtmx_fu)
    capture frame drop _rtmx_fs
    frame create _rtmx_fs str80 stratum double(n_units size_sum size_min size_p50 size_max n_flagged)
    quietly levelsof `st', local(slev)
    foreach g of local slev {
        quietly count if `st' == `g' & frame_ok == 0
        local nf = r(N)
        quietly count if `st' == `g'
        local U = r(N)
        if "`size'" != "" quietly summarize `size' if `st' == `g' & frame_ok, detail
        frame post _rtmx_fs ("`g'") (`U') (cond("`size'" != "", r(sum), .)) (cond("`size'" != "", r(min), .)) (cond("`size'" != "", r(p50), .)) (cond("`size'" != "", r(max), .)) (`nf')
    }
    rtmx_table, name(frame_summary) frame(_rtmx_fs)
    rtmx_setting, key(id) value("`area_id'")
    rtmx_setting, key(size_bounds) value("min `minsize' max `maxsize'") source("GM 1996 pp. 80-84; UN 2008 section 4.1.2")
    drop unit_id flag
    quietly count
    rtmx_done
    save "`saving_list'", replace
    di as text "Checked frame saved to `saving_list' (flags frame_*)."
}
else {
    * ---- B. Grid frame from the raster and the boundaries ----------------------------------
    foreach cmd in shp2dta geoinpoly {
        capture which `cmd'
        if _rc {
            di as err "route grid needs `cmd' (SSC): do 00_setup.do"
            exit 199
        }
    }
    rtmx_start, workflow(frame) step(grid) cmd("01_frame.do route B: grid frame, `cellsize' m cells")
    * B1. the boundaries: shapefile to Stata, attributes and vertex coordinates (shp2dta, Crow 2006)
    * shp2dta needs a canonical absolute path (it reads the extension from the first dot): cd there and back
    local shpdir = cond(strpos("`shapefile'", "/"), substr("`shapefile'", 1, strrpos("`shapefile'", "/") - 1), ".")
    local shpfile = substr("`shapefile'", strrpos("`shapefile'", "/") + 1, .)
    local cur "`c(pwd)'"
    quietly cd "`shpdir'"
    local shpabs "`c(pwd)'/`shpfile'"
    quietly cd "`cur'"
    local base = substr("`shpabs'", 1, length("`shpabs'") - 4)
    tempfile db co
    quietly shp2dta using "`base'", database("`db'") coordinates("`co'") replace
    * B2. the raster header (ESRI ASCII grid: ncols nrows xllcorner yllcorner cellsize NODATA_value)
    tempname fh
    file open `fh' using "`raster'", read text
    forvalues i = 1/6 {
        file read `fh' line
        gettoken key val : line
        local key = lower("`key'")
        local val = trim("`val'")
        if "`key'" == "ncols" local ncols = real("`val'")
        if "`key'" == "nrows" local nrows = real("`val'")
        if inlist("`key'", "xllcorner", "xllcenter") local xll = real("`val'")
        if inlist("`key'", "yllcorner", "yllcenter") local yll = real("`val'")
        if "`key'" == "cellsize" local psize = real("`val'")
        if "`key'" == "nodata_value" local nodata = real("`val'")
    }
    file close `fh'
    * B3. the pixels as points with their population
    import delimited using "`raster'", delimiter(" ", collapse) rowrange(7) varnames(nonames) clear
    gen long row = _n
    reshape long v, i(row) j(col)
    drop if missing(v) | v == `nodata'
    rename v value
    gen double x = `xll' + (col - 0.5) * `psize'
    gen double y = `yll' + (`nrows' - row + 0.5) * `psize'
    quietly summarize value
    local pop_raster = r(sum)
    * B4. each pixel in its polygon (geoinpoly, Picard 2015; projected coordinates: noprojection)
    geoinpoly y x using "`co'", noprojection unique
    quietly count if missing(_ID)
    local pix_out = r(N)
    drop if missing(_ID)
    rename _ID unit
    * B5. the cells: index from the raster's south-west corner, population summed, stratum from the
    *     polygon holding most of the cell's population
    gen long cx = floor((x - `xll') / `cellsize')
    gen long cy = floor((y - `yll') / `cellsize')
    local ncx = ceil(`ncols' * `psize' / `cellsize')
    gen long cell_id = cy * `ncx' + cx + 1
    preserve
    keep cell_id unit x y value
    save "`saving_pixels'", replace
    restore
    collapse (sum) pop = value (count) npix = value (first) cx cy, by(cell_id unit)
    bysort cell_id: egen double tot = total(pop)
    bysort cell_id (pop unit): gen long rk = _N - _n + 1
    bysort cell_id: gen int parts = _N
    gen double unit_share = pop / tot
    keep if rk == 1
    replace pop = tot
    drop tot rk
    gen double x = `xll' + (cx + 0.5) * `cellsize'
    gen double y = `yll' + (cy + 0.5) * `cellsize'
    rename (cx cy) (col row)
    rename unit _ID
    merge m:1 _ID using "`db'", keep(master match) nogenerate
    rename _ID unit
    if "`strata_attr'" != "" gen long stratum = `strata_attr'
    else gen long stratum = unit
    gen str32 unit_name = string(unit)
    if "`id_attr'" != "" {
        capture confirm string variable `id_attr'
        if !_rc replace unit_name = `id_attr'
        else replace unit_name = string(`id_attr')
    }
    drop if pop <= 0
    gen byte small = (pop < `min_pop') if `min_pop' > 0
    if `min_pop' <= 0 replace small = 0
    sort cell_id
    char _dta[rtm_grid_cellsize] "`cellsize'"
    char _dta[rtm_grid_xll] "`xll'"
    char _dta[rtm_grid_yll] "`yll'"
    quietly count
    local ncells = r(N)
    quietly summarize pop
    di as text _n "Grid frame: `ncells' cells of `cellsize' m; population inside the boundaries " %12.0fc r(sum) " of " %12.0fc `pop_raster' " in the raster; pixels outside: `pix_out'"
    quietly count if parts > 1
    di as text "Cells straddling a boundary: " r(N) " (assigned to the polygon with most of their population)"
    * exports
    capture frame drop _rtmx_fu
    gen str32 unit_id = string(cell_id)
    gen str32 stratum_s = string(stratum)
    gen str32 flag = cond(small == 1, "small", "")
    frame put unit_id stratum_s unit_name pop x y flag, into(_rtmx_fu)
    frame _rtmx_fu {
        rename (stratum_s unit_name pop) (stratum unit size)
        order unit_id stratum unit size x y flag
    }
    rtmx_table, name(frame_units) frame(_rtmx_fu)
    capture frame drop _rtmx_fs
    frame create _rtmx_fs str32 stratum double(n_units size_sum size_min size_p50 size_max n_flagged)
    quietly levelsof stratum, local(slev)
    foreach l of local slev {
        quietly count if stratum == `l' & small
        local nf = r(N)
        quietly summarize pop if stratum == `l', detail
        frame post _rtmx_fs ("`l'") (r(N)) (r(sum)) (r(min)) (r(p50)) (r(max)) (`nf')
    }
    rtmx_table, name(frame_summary) frame(_rtmx_fs)
    capture frame drop _rtmx_bd
    frame create _rtmx_bd
    frame _rtmx_bd {
        use "`co'", clear
        gen long vertex = _n
        gen byte sep = missing(_X)
        bysort _ID (vertex): gen long part = sum(sep)
        drop if sep
        bysort _ID: egen long pmin = min(part)
        replace part = part - pmin + 1
        drop sep pmin
        bysort _ID part (vertex): replace vertex = _n
        rename (_ID _X _Y) (polygon_id x y)
        order polygon_id part vertex x y
    }
    rtmx_table, name(boundaries) frame(_rtmx_bd)
    rtmx_setting, key(cellsize) value("`cellsize'") source("HFPS Vol. 2 section 1.1; UN 2008 section 4.3")
    rtmx_setting, key(stratum_rule) value("polygon with most of the cell's population") source("no cited default; labeled choice")
    drop unit_id stratum_s flag
    quietly count
    rtmx_done
    save "`saving_grid'", replace
    di as text "Grid frame saved to `saving_grid'; pixels in `saving_pixels' (for splits). Draw from it with 03_sample.do or rtmsample grid."
}
di as text _n "Done. The runs are in `export_dir'."
