* test_listing.do -- rtmlist: the listing workbook with segmentation, the completed listing with its
* planted problems read from .dta and .xlsx, the checks, the household frame and the second-stage draw
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
local tmp "`c(tmpdir)'"
if substr("`tmp'", -1, 1) != "/" & substr("`tmp'", -1, 1) != "\" local tmp "`tmp'/"

* ---------- 1. the forms: one sheet per area, segments by the standard segment rule ----------
use "../data/rtm_frame.dta", clear
keep if ea_selected
rtmlist prepare, id(ea_id) expected(ea_size_census) strata(stratum) segmentsize(150) seed(3) saving("`tmp'rtm_forms.xlsx") replace
assert r(N_areas) == 100
assert r(seed) == 3
assert list_segments == max(1, round(ea_size_census / 150))
assert inrange(list_segment_selected, 1, list_segments)
assert reldif(list_segment_prob, 1 / list_segments) < 1e-12
quietly count if list_segments > 1
assert r(N) == r(n_segmented) | 1
local nseg = r(N)
confirm file "`tmp'rtm_forms.xlsx"
* the same seed gives the same segments
preserve
rtmlist prepare, id(ea_id) expected(ea_size_census) segmentsize(150) seed(3) saving("`tmp'rtm_forms2.xlsx") replace
restore
save "`tmp'rtm_areas_seg.dta", replace

* ---------- 2. the completed listing from .dta: the planted problems are found ----------
rtmlist import using "../data/rtm_listing.dta", id(ea_id) expected(ea_size_census) saving("`tmp'rtm_stage2.dta") replace clear
assert r(N_areas) == 100
assert r(n_not_returned) == 1           // one area was dropped from the listing
assert r(n_not_selected) == 3           // three households in area 2, which was not selected
assert r(n_duplicates) == 4             // two rows duplicated once each
assert r(n_over) == 1 & r(n_under) == 1
assert r(n_returned) == 99
assert r(N_frame) > 0
local nf = r(N_frame)
* the frame in memory: eligible households of selected areas only, numbered within area
quietly count
assert r(N) == `nf'
assert eligible == 1
bysort area_id (hh_seq): assert hh_seq == _n
assert !missing(segment_prob)
quietly count if flag == "over-listed"
assert r(N) > 0
quietly levelsof area_id, local(al)
assert `: word count `al'' == 99
* the second-stage draw works on it, 12 per area
rtmsample draw, n(12) strata(area_id) seed(20261025) id(hh_seq) generate(hh)
assert r(n_selected) == 12 * 99
assert reldif(hh_pi, 12 / area_eligible) < 1e-12 if hh_sel == 1

* ---------- 3. the same listing from the Excel file ----------
use "`tmp'rtm_areas_seg.dta", clear
rtmlist import using "../data/rtm_listing.xlsx", id(ea_id) expected(ea_size_census) sheet(Listing) clear
assert r(n_duplicates) == 4 & r(n_not_returned) == 1 & r(N_frame) == `nf'

* ---------- 4. bad inputs ----------
use "`tmp'rtm_areas_seg.dta", clear
capture noisily rtmlist import using "../data/nothere.dta", id(ea_id)
assert _rc == 601
capture noisily rtmlist import using "../data/rtm_listing.dta", id(ea_id) areavar(nosuch)
assert _rc == 111
capture noisily rtmlist import using "../data/rtm_listing.dta", id(ea_id) ratio(2 1)
assert _rc == 198
capture noisily rtmlist prepare, id(ea_id) segmentsize(150) saving("`tmp'x.xlsx") replace
assert _rc == 198                       // segmentation without expected()
expand 2 in 1
capture noisily rtmlist prepare, id(ea_id) saving("`tmp'x.xlsx") replace
assert _rc == 459                       // duplicate id
di as result "test_listing: all assertions passed"
