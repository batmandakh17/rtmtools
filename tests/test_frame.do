* test_frame.do -- rtmframe and rtmsample grid: list-frame checks with planted problems, the grid
* frame against the raster total, exact geometry checks (strata, areas, adjacency, splits), GRTS
* draws (weights, strata, reproducibility, allocation variable, proportional), spsurvey's documented
* NE_Lakes example reproduced through the command, and bad inputs. The R parts are skipped with
* a note when R, sf, terra or spsurvey is missing.
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."

* ---------- 1. list frame: planted duplicate, zero size, bad counts; flags and merge ----------
use "../data/rtm_frame.dta", clear
gen double persons = ea_size_census * 5.2
gen double males = round(persons * 0.49)
gen double females = round(persons - males)
replace persons = ea_size_census * 12 in 3
replace males = females * 1.5 in 4
replace ea_size_census = 0 in 1
expand 2 in 2
rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) maxsize(250) persons(persons) males(males) females(females) merge(unit) sort(ea_id)
assert r(N) == 401
assert r(n_dup) == 2
assert r(n_badsize) == 1
assert r(n_hhsize_flag) == 1
assert r(n_masc_flag) == 1
assert r(n_sexsum_flag) >= 1
assert r(N_ok) == 398
assert r(H) == 8
quietly count if frame_small == 1
local ns = r(N)
quietly count if frame_ok & ea_size_census < 80
assert `ns' == r(N)
quietly count if frame_large == 1
local nl = r(N)
quietly count if frame_ok & ea_size_census > 250
assert `nl' == r(N)
assert frame_segments == max(2, round(ea_size_census / 250)) if frame_large == 1
assert frame_ok == 0 if frame_dup == 1 | frame_badsize == 1
* combined units: sizes add up, every combined unit reaches minsize, totals preserved
bysort unit: egen double usum = total(cond(frame_ok, ea_size_census, 0))
assert reldif(usum, unit_size) < 1e-9 if frame_ok
preserve
keep if frame_ok
collapse (first) unit_size (sum) ea_size_census, by(stratum unit)
assert unit_size >= 80
assert reldif(unit_size, ea_size_census) < 1e-9
restore
quietly summarize ea_size_census if frame_ok
local tot_ok = r(sum)
preserve
keep if frame_ok
bysort unit: keep if _n == 1
quietly summarize unit_size
assert reldif(r(sum), `tot_ok') < 1e-9
restore
* the record
local c : char _dta[rtm_frame]
assert strpos(`"`c'"', "rtmframe list")

* ---------- R available? ----------
_rtm_runr find
local rs "`r(rscript)'"
local haveR 0
if "`rs'" != "" {
    tempfile a s
    tempname fh
    quietly file open `fh' using "`a'", write text replace
    file write `fh' "status=`s'" _n
    file close `fh'
    capture _rtm_runr, script(rtmtools_check.R) args("`a'") status("`s'") quietly
    local m `"`r(message)'"'
    if !_rc & strpos(`"`m'"', "sf ") & strpos(`"`m'"', "terra") & strpos(`"`m'"', "spsurvey") & !strpos(`"`m'"', "MISSING") local haveR 1
}
if !`haveR' {
    global rtm_test_note "$rtm_test_note (R with sf, terra and spsurvey not available: grid checks skipped)"
    di as result "test_frame: list-frame assertions passed; R parts skipped"
    exit
}
local tmp "`c(tmpdir)'"
if substr("`tmp'", -1, 1) != "/" & substr("`tmp'", -1, 1) != "\" local tmp "`tmp'/"
local gp "`tmp'rtm_test_grid.gpkg"

* ---------- 2. grid frame: cells, strata, raster total, areas, groups, determinism ----------
rtmframe grid using "../data/rtm_boundaries.gpkg", raster("../data/rtm_population.tif") cellsize(10000) strata(region) groups(3) saving("`gp'") clear
assert r(N_cells) == 97
assert r(H) == 4
assert r(dropped) == 0
assert reldif(r(pop_total), r(pop_boundaries)) < 1e-9
assert r(epsg) == 32633
quietly count if stratum == "North-East"
assert r(N) == 22
quietly count if stratum == "North-West"
assert r(N) == 25
quietly summarize area_km2
assert reldif(r(sum), 9550) < 1e-6
quietly summarize pop
local popsum = r(sum)
quietly levelsof group, local(gl)
assert `: word count `gl'' == 3
assert inrange(group, 1, 3)
assert !missing(lon) & !missing(lat) & lon_min < lon_max & lat_min < lat_max
assert b_region == stratum
local pop45 = pop[45]
local c : char _dta[rtm_frame]
assert strpos(`"`c'"', "rtmframe grid")
tempfile g1
quietly save "`g1'"
rtmframe grid using "../data/rtm_boundaries.gpkg", raster("../data/rtm_population.tif") cellsize(10000) strata(region) groups(3) clear
rename (pop group) (pop2 group2)
quietly merge 1:1 cell_id using "`g1'", keepusing(pop group) nogenerate
assert reldif(pop, pop2) < 1e-12 & group == group2
* ncells() and points() variants, keepempty and minpop
rtmframe grid using "../data/rtm_boundaries.gpkg", raster("../data/rtm_population.tif") ncells(50) strata(region) clear
assert inrange(r(N_cells), 35, 70)
rtmframe grid using "../data/rtm_boundaries.gpkg", raster("../data/rtm_population.tif") cellsize(10000) minpop(3000) clear
assert r(dropped) > 0
quietly count if pop <= 3000
assert r(N) == 0

* ---------- 3. GRTS: equal, stratified, ordered replacements; weights, reproducibility ----------
use "`g1'", clear
rtmsample grid using "`gp'", n(5) strata(stratum) nover(2) seed(1) generate(g)
assert r(n_selected) == 20 & r(n_reserve) == 8 & r(n_near) == 0 & r(H) == 4
bysort stratum: egen double nb = total(g_sel)
bysort stratum: egen double nr = total(g_reserve > 0)
bysort stratum: egen double U = total(1)
assert nb == 5 & nr == 2
assert reldif(g_w, U / 5) < 1e-9 if g_sel == 1
assert reldif(g_pi, 5 / U) < 1e-9 if g_sel == 1
bysort stratum: egen double sw = total(cond(g_sel, g_w, 0))
assert reldif(sw, U) < 1e-9
assert g_reserve == 0 if g_sel == 1
bysort stratum (g_reserve): assert g_reserve[_N] == 2 & g_reserve[_N - 1] == 1
assert !missing(g_order) if g_sel == 1
assert missing(g_w) & missing(g_pi) if g_sel == 0
* same seed, same sample; another seed, another sample
rtmsample grid using "`gp'", n(5) strata(stratum) nover(2) seed(1) generate(g2)
assert g2_sel == g_sel & g2_reserve == g_reserve & (g2_order == g_order | g_sel == 0)
rtmsample grid using "`gp'", n(5) strata(stratum) nover(2) seed(2) generate(g3)
quietly count if g3_sel != g_sel
assert r(N) > 0
* the recorded command carries the seed and reruns identically
rtmsample grid using "`gp'", n(5) strata(stratum) generate(g4)
local seed = r(seed)
local cmd `"`r(cmdline)'"'
assert strpos(`"`cmd'"', "seed(`seed')")
local vc : char g4_sel[rtm_cmd]
assert `"`vc'"' == `"`cmd'"'
rename (g4_sel g4_order) (y_sel y_order)
drop g4_*
`cmd'
assert g4_sel == y_sel & (g4_order == y_order | y_sel == 0)
* allocation variable per stratum
rtmsample allocate, strata(stratum) n(24) size(pop) generate(n_cell)
rtmsample grid using "`gp'", n(n_cell) strata(stratum) seed(2) generate(h)
local nsel_h = r(n_selected)
bysort stratum: egen double nh = total(h_sel)
assert nh == n_cell
assert `nsel_h' == 24
* proportional to size with nearest neighbours
rtmsample grid using "`gp'", n(12) aux(pop) nnear(1) seed(3) generate(k)
* a cell can be the nearest neighbour of two base sites, so up to 12 distinct cells are flagged
assert r(n_selected) == 12 & inrange(r(n_near), 6, 12)
assert inrange(k_pi, 0, 1) if k_sel == 1
* proportional to size: pi / size is constant for the units not capped at 1
gen double ratio = k_pi / pop if k_sel == 1 & k_pi < 1
quietly summarize ratio
assert r(N) >= 8 & (r(sd) / r(mean)) < 1e-6
assert reldif(k_w, 1 / k_pi) < 1e-9 if k_sel == 1
quietly count if !missing(k_near)
assert inrange(r(N), 6, 12)
assert inrange(k_near, 1, 12) if !missing(k_near)
* larger cells have larger inclusion probabilities
quietly correlate pop k_pi if k_sel == 1
assert r(rho) > 0.9

* ---------- 4. replacement candidates and splits: exact geometry on the 10 km grid ----------
rtmframe replace using "`gp'", cells(45 46) exclude(34) clear
assert r(N_cells) == 2
quietly levelsof candidate if cell == 45, local(c45)
assert "`c45'" == "35 44"
assert rank == 1 & abs(dist_km - 10) < 1e-6 if cell == 45 & candidate == 35
quietly levelsof candidate if cell == 46, local(c46)
assert "`c46'" == "36 37 47"
assert stratum == "South-West" if cell == 45
assert stratum == "South-East" if cell == 46
assert candidate != 34
* rook adjacency: 34 touches cell 45 only at a corner, so only 35 and 44 remain in the stratum
rtmframe replace using "`gp'", cells(45) adjacency(rook) clear
quietly levelsof candidate, local(c45r)
assert "`c45r'" == "35 44"
rtmframe replace using "`gp'", cells(45) clear
quietly levelsof candidate, local(c45q)
assert "`c45q'" == "34 35 44"
use "`g1'", clear
gen byte picked = inlist(cell_id, 34, 35)
rtmframe replace using "`gp'", cells(45) selected(picked) clear
quietly levelsof candidate, local(c45s)
assert "`c45s'" == "44"
rtmframe split using "`gp'", cells(45) parts(2) raster("../data/rtm_population.tif") clear
assert r(N_parts) == 4 & r(parts) == 2
quietly summarize pop
assert reldif(r(sum), `pop45') < 1e-9
assert reldif(area_km2, 25) < 1e-6
rtmframe split using "`gp'", cells(45 46) parts(3) raster("../data/rtm_population.tif") clear
assert r(N_parts) == 18

* ---------- 5. spsurvey's documented NE_Lakes example through the command ----------
tempfile lk lf lr st ar
tempname fh
local lr_strat = subinstr("`lr'", ".dta", "", .) + "_strat.dta"
quietly file open `fh' using "`ar'", write text replace
file write `fh' "status=`st'" _n "gpkg=`tmp'rtm_test_lakes.gpkg" _n "frame=`lf'" _n "ref=`lr'.dta" _n
file close `fh'
quietly findfile rtm_grts_ref.R
shell "`rs'" --vanilla "`r(fn)'" "`ar'" > /dev/null 2>&1
file open `fh' using "`st'", read text
file read `fh' line
file close `fh'
assert "`line'" == "ok"
use "`lf'", clear
rtmsample grid using "`tmp'rtm_test_lakes.gpkg", n(100) id(lake_id) seed(51) generate(L)
assert r(n_selected) == 100
preserve
use "`lr'.dta", clear
rename (wgt ip site_order) (ref_w ref_pi ref_order)
tempfile ref
quietly save "`ref'"
restore
quietly merge 1:1 lake_id using "`ref'", keepusing(ref_w ref_pi ref_order)
assert (_merge == 3) == (L_sel == 1)
assert reldif(L_w, ref_w) < 1e-10 & L_order == ref_order if L_sel == 1
drop _merge
rtmsample grid using "`tmp'rtm_test_lakes.gpkg", n(25) id(lake_id) seed(51) generate(M) strata(ELEV_CAT)
* the documented stratified example uses 25 low and 30 high: repeat it with a per-stratum variable
gen int n_lk = cond(ELEV_CAT == "low", 25, 30)
rtmsample grid using "`tmp'rtm_test_lakes.gpkg", n(n_lk) id(lake_id) seed(51) strata(ELEV_CAT) generate(S)
assert r(n_selected) == 55
preserve
use "`lr_strat'", clear
rename wgt ref_w2
tempfile ref2
quietly save "`ref2'"
restore
quietly merge 1:1 lake_id using "`ref2'", keepusing(ref_w2)
assert (_merge == 3) == (S_sel == 1)
assert reldif(S_w, ref_w2) < 1e-10 if S_sel == 1

* ---------- 6. bad inputs ----------
use "`g1'", clear
capture noisily rtmframe grid using "../data/nothere.gpkg", cellsize(10000) clear
assert _rc == 601
capture noisily rtmframe grid using "../data/rtm_boundaries.gpkg", cellsize(10000) strata(nope) clear
assert _rc == 199
capture noisily rtmframe grid using "../data/rtm_boundaries.gpkg", clear
assert _rc == 198
capture noisily rtmframe grid using "../data/rtm_boundaries.gpkg", cellsize(10000) groups(3) clear
assert _rc == 198
capture noisily rtmsample grid using "`gp'", n(30) strata(stratum) generate(z)
assert _rc == 199
capture noisily rtmsample grid using "`gp'", n(5) generate(z) seed(1.5)
assert _rc == 198
capture noisily rtmsample grid using "`gp'", n(n_cell) generate(z)
assert _rc == 198
capture noisily rtmframe split using "`gp'", cells(45) parts(5) clear
assert _rc == 198
capture noisily rtmframe replace using "`gp'", cells(999) clear
assert _rc == 199
capture noisily rtmframe frob
assert _rc == 198
di as result "test_frame: all assertions passed"
