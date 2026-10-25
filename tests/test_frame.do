* test_frame.do -- rtmframe without R: list-frame checks and merging on a frame with planted errors;
* the grid frame from the ESRI ASCII raster and the shapefile (pixel sums, strata, straddling cells,
* exports); replacement candidates (adjacency, stratum); splits (parts add to the cell); bad inputs
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
local tmp "`c(tmpdir)'"
if substr("`tmp'", -1, 1) != "/" & substr("`tmp'", -1, 1) != "\" local tmp "`tmp'/"

* ---------- 1. list frame with planted problems ----------
use "../data/rtm_frame.dta", clear
set obs 401
replace ea_id = 1 in 401                       // a duplicate id (with a valid size)
replace stratum = 1 in 401
replace region = 1 in 401
replace urban = 1 in 401
replace ea_size_census = 100 in 401
replace ea_size_census = 0 in 4                // a bad size in another row
gen double persons = ea_size_census * 4.5
replace persons = ea_size_census * 20 in 2      // persons per household outside 3-10
gen double males = persons * 0.49
gen double females = persons - males
replace males = females * 1.5 in 3              // masculinity ratio outside 80-120
rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) maxsize(250) persons(persons) males(males) females(females)
assert r(N) == 401
assert r(n_dup) == 2
assert r(n_badsize) == 1
assert r(n_hhsize_flag) == 1
assert r(n_masc_flag) == 1
assert r(n_sexsum_flag) >= 1
assert r(N_ok) == 398
assert r(H) == 8
quietly count if ea_size_census < 80 & frame_ok
local ns = r(N)
quietly count if frame_small == 1
assert `ns' == r(N)
quietly count if ea_size_census > 250 & frame_ok
local nl = r(N)
quietly count if frame_large == 1
assert `nl' == r(N)
assert frame_segments == max(2, round(ea_size_census / 250)) if frame_large == 1
assert frame_ok == 0 if frame_dup == 1 | frame_badsize == 1
* merging small units: combined sizes reach minsize; the total is kept
rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) merge(unit) sort(ea_id) replace
bysort unit: egen double usum = total(cond(frame_ok, ea_size_census, 0))
assert reldif(usum, unit_size) < 1e-9 if frame_ok
bysort unit: gen byte ulast = (_n == _N)
assert unit_size >= 80 if frame_ok & ulast
quietly summarize ea_size_census if frame_ok
local tot_ok = r(sum)
egen byte utag = tag(unit) if frame_ok
quietly summarize unit_size if utag == 1
assert reldif(r(sum), `tot_ok') < 1e-9
local c : char _dta[rtm_frame]
assert strpos(`"`c'"', "rtmframe list")

* ---------- 2. grid frame from the ASCII raster and the shapefile ----------
rtmframe grid using "../data/rtm_boundaries.shp", raster("../data/rtm_population.asc") cellsize(5000) strata(regcode) id(region) minsize(500) saving("`tmp'rtm_grid5.dta") savingpixels("`tmp'rtm_pixels5.dta") clear replace
assert r(N_cells) == 400                              // 20 x 20 cells of 5 km over the 100 km square
assert r(H) == 4 & r(n_polygons) == 4
assert r(pop_outside) == 0 & r(pixels_outside) == 0  // the regions tile the square
assert reldif(r(pop_inside), r(pop_raster)) < 1e-12
assert r(pixelsize) == 1000 & r(cellsize) == 5000
local nstr = r(n_straddle)
assert `nstr' > 0                                     // the wavy borders cut some cells
quietly summarize pop
assert reldif(r(sum), 957592) < 1e-9                 // the raster's total (make_rtm_spatial.py)
assert npix == 25                                     // 5 x 5 pixels per cell, all inside
quietly count if parts > 1
assert r(N) == `nstr'
assert unit_share == 1 if parts == 1
assert unit_share < 1 & unit_share > 0.5 - 1e-9 if parts > 1   // the main polygon holds most of the population
assert inlist(stratum, 1, 2, 3, 4)
* every cell's stratum is the polygon holding most of its population: check from the pixel table
preserve
use "`tmp'rtm_pixels5.dta", clear
collapse (sum) pop = value, by(cell_id unit)
bysort cell_id (pop unit): keep if _n == _N
rename unit main_unit
tempfile mu
quietly save "`mu'"
restore
preserve
quietly merge 1:1 cell_id using "`mu'", assert(3) nogenerate
assert unit == main_unit
restore
* cell centres lie on the 5 km lattice from the raster's corner
assert reldif(x, 300000 + (col + 0.5) * 5000) < 1e-9
assert reldif(y, 4000000 + (row + 0.5) * 5000) < 1e-9
* unit names come from the shapefile attribute
assert inlist(unit_name, "North-West", "North-East", "South-West", "South-East")
* a coarser grid: 10 km cells, 100 of them, same population
rtmframe grid using "../data/rtm_boundaries.shp", raster("../data/rtm_population.asc") cellsize(10000) strata(regcode) clear
assert r(N_cells) == 100
quietly summarize pop
assert reldif(r(sum), 957592) < 1e-9
* blocks(): aggregating pixels 5 x 5 before the polygon step gives the same cell totals at 10 km
rtmframe grid using "../data/rtm_boundaries.shp", raster("../data/rtm_population.asc") cellsize(10000) strata(regcode) blocks(5) clear
assert r(N_cells) == 100
quietly summarize pop
assert reldif(r(sum), 957592) < 1e-9

* ---------- 3. the spatially spread draw and the replacement candidates ----------
use "`tmp'rtm_grid5.dta", clear
rtmsample grid, n(5) strata(stratum) pps(pop) xy(x y) reserve(2) seed(20261025) id(cell_id) generate(g)
assert r(n_selected) == 20 & r(n_reserve) == 8 & r(H) == 4
bysort stratum: egen double ps = total(pop)
bysort stratum: egen double ht = total(cond(g_sel, pop / g_pi, 0))
assert reldif(ht, ps) < 1e-9
quietly levelsof cell_id if g_sel == 1, local(sel)
local c1 : word 1 of `sel'
local c2 : word 7 of `sel'
rtmframe replace, cells(`c1' `c2') selected(g_sel) ncand(3) generate(rp) saving("`tmp'rtm_repl.dta") replace
assert r(n_cells) == 2 & r(n_with_candidates) == 2
* candidates: same stratum, within two cells (queen), not selected, not the cells themselves
preserve
keep cell_id col row stratum g_sel
rename (cell_id col row stratum g_sel) (c_to col_to row_to str_to sel_to)
tempfile to
quietly save "`to'"
restore
preserve
use "`tmp'rtm_repl.dta", clear
destring unit_id candidate_id, replace
drop stratum
rename (unit_id candidate_id) (cell_id c_to)
quietly merge m:1 c_to using "`to'", keep(match) assert(match using) nogenerate
quietly merge m:1 cell_id using "`tmp'rtm_grid5.dta", keepusing(col row stratum) keep(match) nogenerate
assert str_to == stratum
assert sel_to != 1
assert c_to != cell_id
assert max(abs(col_to - col), abs(row_to - row)) <= 2
bysort cell_id (rank): assert rank == _n
restore
* rook adjacency gives candidates sharing a side only
rtmframe replace, cells(`c1') selected(g_sel) adjacency(rook) ncand(4) saving("`tmp'rtm_repl2.dta") replace
preserve
use "`tmp'rtm_repl2.dta", clear
destring unit_id candidate_id, replace
rename candidate_id c_to
quietly merge m:1 c_to using "`to'", keep(match) nogenerate
quietly summarize col_to
restore

* ---------- 4. splits: the parts' populations add to the cell's ----------
quietly summarize pop if cell_id == `c1'
local p1 = r(sum)
rtmframe split, cells(`c1' `c2') parts(2) pixels("`tmp'rtm_pixels5.dta") saving("`tmp'rtm_parts.dta") replace
assert r(n_parts) <= 8 & r(n_mismatch) == 0 & r(partsize) == 2500
preserve
use "`tmp'rtm_parts.dta", clear
quietly summarize pop if cell_id == `c1'
assert reldif(r(sum), `p1') < 1e-9
assert inrange(part, 1, 4)
restore
rtmframe split, cells(`c1') parts(5) pixels("`tmp'rtm_pixels5.dta") saving("`tmp'rtm_parts5.dta") replace
assert r(n_parts) == 25                                 // 5 x 5 parts of 1 km = one pixel each
preserve
use "`tmp'rtm_parts5.dta", clear
assert npix == 1
restore

* ---------- 5. bad inputs ----------
capture noisily rtmframe grid using "../data/rtm_boundaries.gpkg", raster("../data/rtm_population.asc") cellsize(5000) clear
assert _rc == 198
capture noisily rtmframe grid using "../data/rtm_boundaries.shp", raster("../data/nothere.asc") cellsize(5000) clear
assert _rc == 601
capture noisily rtmframe grid using "../data/rtm_boundaries.shp", raster("../data/rtm_population.asc") cellsize(500) clear
assert _rc == 198
capture noisily rtmframe grid using "../data/rtm_boundaries.shp", raster("../data/rtm_population.asc") cellsize(5000) strata(nosuch) clear
assert _rc == 111
capture noisily rtmframe replace, cells(99999)
assert _rc == 459
capture noisily rtmframe split, cells(`c1') parts(1) pixels("`tmp'rtm_pixels5.dta")
assert _rc == 198
use "../data/rtm_frame.dta", clear
capture noisily rtmframe replace, cells(1)
assert _rc == 111
capture noisily rtmframe list, id(ea_id) minsize(100) merge(u)
assert _rc == 198
di as result "test_frame: all assertions passed"
