********************************************************************************************
* 02_listing.do  --  listing support: the listing forms of the selected areas (with segmentation
* of large areas) and the completed listing checked into the household frame, in plain Stata
* rtmtools portable do-files, version 0.5.0 (25 October 2026)
*
* Step 1 (forms): one sheet per selected area in an Excel workbook, written with putexcel; large
*   areas divided into segments of about segment_size households, one chosen at random (UN 2008
*   paras 138-140, the standard segment design; para 86, segmentation as an office task).
* Step 2 (import): the completed listing (one row per listed household) merged with the selected
*   areas; checks (areas not returned, households in areas not selected, duplicates, listed against
*   expected, eligibility); the household frame of listed eligible households (UN 2008 para 131:
*   the sample is drawn in the office from the listing). The draw itself is 03_sample.do step 4
*   or rtmsample draw, n(#) strata(area_id).
* Every step is exported (schema rtm-export-1.0) like the rtmlist commands.
* To adopt it: change only the PARAMETERS block, following ADAPTATION.md.
********************************************************************************************
version 16
clear all
set more off

* ======================= PARAMETERS: change these lines only ===============================
local data_areas     "template/rtm_frame.dta"    // the frame with the selected areas
local selected_var   ea_selected                 // 0/1 variable marking the selected areas ("" if the file holds only them)
local area_id        ea_id
local expected       ea_size_census              // expected households per area (from the frame); "" if none
local strata         "stratum"
local forms_file     "listing_forms.xlsx"        // the workbook of listing forms to write
local segment_size   150                         // households per segment (0 = no segmentation)
local seed           3
local data_listing   "template/rtm_listing.dta"  // the completed listing: .dta, .csv or .xlsx, one row per household
local listing_sheet  ""                          // sheet name for an Excel listing ("" = first)
local col_area       area_id                     // column names in the listing file
local col_structure  structure_no
local col_household  household_no
local col_eligible   eligible
local ratio_low      0.5                         // flag areas with listed/expected below this (no cited default)
local ratio_high     2
local saving_frame   "stage2_frame.dta"          // the household frame to write
local export_dir     "rtm_exports"
local helpers        "_export_helpers.do"
local template_xlsx  "rtm_display.xlsx"
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

* ---- 1. The listing forms and the segmentation --------------------------------------------
use "`data_areas'", clear
if "`selected_var'" != "" keep if `selected_var' == 1
isid `area_id'
quietly count
local N = r(N)
rtmx_start, workflow(listing) step(prepare) cmd("02_listing.do step 1: listing forms for `N' areas")
set seed `seed'
* segments: round(expected / segment_size), one chosen with equal probability, probability 1/segments
gen long list_segments = 1
gen long list_segment_selected = 1
gen double list_segment_prob = 1
if `segment_size' > 0 & "`expected'" != "" {
    replace list_segments = max(1, round(`expected' / `segment_size'))
    replace list_segment_selected = runiformint(1, list_segments)
    replace list_segment_prob = 1 / list_segments
}
label variable list_segments "Segments before listing (1 = whole area)"
label variable list_segment_selected "Segment selected for listing"
label variable list_segment_prob "Probability of the listed segment"
quietly count if list_segments > 1
di as text _n "Listing forms for `N' areas; `=r(N)' areas segmented (segments of about `segment_size' households)"
* the workbook: instructions, the areas, one sheet per area
quietly putexcel set "`forms_file'", sheet("Instructions") replace
quietly putexcel A1 = "Household listing: instructions"
quietly putexcel A3 = "One sheet per selected area. List every structure in the area (or in the selected segment), from a fixed starting point, in one direction, without gaps."
quietly putexcel A4 = "For each structure: its number, a short location description, the households in it; one row per household with its number, eligible (1/0) and has a telephone (1/0/9)."
quietly putexcel A5 = "Return the completed sheets; the sample of households is drawn in the office from the listing (UN 2008, para 131)."
quietly putexcel set "`forms_file'", sheet("Areas") modify
quietly putexcel A1 = "area_id" B1 = "stratum" C1 = "expected_households" D1 = "segments" E1 = "segment_selected" F1 = "segment_prob"
forvalues i = 1/`N' {
    local r = `i' + 1
    local ex = cond("`expected'" != "", string(`expected'[`i']), "")
    quietly putexcel A`r' = (`area_id'[`i']) B`r' = (`strata'[`i']) C`r' = "`ex'" D`r' = (list_segments[`i']) E`r' = (list_segment_selected[`i']) F`r' = (list_segment_prob[`i'])
}
forvalues i = 1/`N' {
    local sh = string(`area_id'[`i'])
    quietly putexcel set "`forms_file'", sheet("`sh'") modify
    quietly putexcel A1 = "Area `sh'" B1 = "Lister:" D1 = "Date:"
    quietly putexcel A3 = "structure_no" B3 = "location_description" C3 = "n_households" D3 = "household_no" E3 = "eligible" F3 = "has_phone" G3 = "notes"
}
di as text "Workbook written: `forms_file'"
capture frame drop _rtmx_la
frame create _rtmx_la str32 area_id str80 stratum double(expected listed eligible ratio segments segment_selected) str32 flag
forvalues i = 1/`N' {
    frame post _rtmx_la (string(`area_id'[`i'])) (string(`strata'[`i'])) (cond("`expected'" != "", `expected'[`i'], .)) (.) (.) (.) (list_segments[`i']) (list_segment_selected[`i']) (cond(list_segments[`i'] > 1, "segmented", ""))
}
rtmx_table, name(listing_areas) frame(_rtmx_la)
rtmx_setting, key(workbook) value("`forms_file'")
rtmx_setting, key(segmentsize) value("`segment_size'") source("UN 2008 paras 138-140 (standard segment design)")
quietly count
rtmx_done
tempfile areas
save "`areas'"

* ---- 2. The completed listing: checks and the household frame ------------------------------
rtmx_start, workflow(listing) step(import) cmd("02_listing.do step 2: the completed listing checked into the household frame")
local ext = lower(substr("`data_listing'", strrpos("`data_listing'", "."), .))
if "`ext'" == ".dta" use "`data_listing'", clear
else if "`ext'" == ".csv" import delimited using "`data_listing'", clear varnames(1) case(preserve)
else {
    local shopt = cond("`listing_sheet'" != "", `"sheet("`listing_sheet'")"', "")
    import excel using "`data_listing'", firstrow case(preserve) `shopt' clear
}
foreach v in `col_area' `col_structure' `col_household' `col_eligible' {
    confirm variable `v'
}
rename `col_area' `area_id'
quietly count
local N_rows = r(N)
* duplicates of structure and household within an area: an error to resolve before the draw
bysort `area_id' `col_structure' `col_household': gen byte dup = (_N > 1)
quietly count if dup
local n_dup = r(N)
* merge with the selected areas
merge m:1 `area_id' using "`areas'", keepusing(`expected' `strata' list_segments list_segment_selected list_segment_prob) generate(_m)
quietly count if _m == 1
local n_notsel = r(N)
quietly count if _m == 2
local n_notret = r(N)
quietly levelsof `area_id' if _m == 2, local(notret)
* per-area counts and flags
gen byte listed1 = (_m == 3)
gen byte elig1 = (_m == 3 & `col_eligible' == 1)
preserve
collapse (sum) listed = listed1 eligible_n = elig1 (first) `expected' list_segments list_segment_selected, by(`area_id' _m)
gen double ratio = cond("`expected'" != "", listed / `expected', .)
gen str32 flag = ""
replace flag = "not returned" if _m == 2
replace flag = "not selected" if _m == 1
replace flag = "under-listed" if flag == "" & ratio < `ratio_low'
replace flag = "over-listed" if flag == "" & ratio > `ratio_high' & !missing(ratio)
quietly count if flag == "under-listed"
local n_under = r(N)
quietly count if flag == "over-listed"
local n_over = r(N)
capture frame drop _rtmx_la
frame create _rtmx_la str32 area_id str80 stratum double(expected listed eligible ratio segments segment_selected) str32 flag
forvalues i = 1/`=_N' {
    frame post _rtmx_la (string(`area_id'[`i'])) ("") (cond("`expected'" != "", `expected'[`i'], .)) (listed[`i']) (eligible_n[`i']) (ratio[`i']) (list_segments[`i']) (list_segment_selected[`i']) (flag[`i'])
}
keep `area_id' listed eligible_n ratio flag
tempfile counts
save "`counts'"
restore
* the household frame: listed eligible households of the selected areas
keep if _m == 3 & `col_eligible' == 1
drop _m listed1 elig1
sort `area_id' `col_structure' `col_household'
by `area_id': gen long hh_seq = _n
merge m:1 `area_id' using "`counts'", nogenerate keep(master match)
rename (listed eligible_n list_segment_prob) (area_listed area_eligible segment_prob)
quietly count
local N_frame = r(N)
capture frame drop _rtmx_lc
frame create _rtmx_lc str64 check double(n) str16 status str244 detail
frame post _rtmx_lc ("rows in the listing file") (`N_rows') ("ok") ("")
frame post _rtmx_lc ("selected areas not returned") (`n_notret') (cond(`n_notret' > 0, "warn", "ok")) ("`notret'")
frame post _rtmx_lc ("listed households in areas not selected") (`n_notsel') (cond(`n_notsel' > 0, "warn", "ok")) ("dropped from the frame")
frame post _rtmx_lc ("duplicate structure and household numbers") (`n_dup') (cond(`n_dup' > 0, "error", "ok")) ("resolve before the draw")
frame post _rtmx_lc ("areas under-listed (ratio below `ratio_low')") (`n_under') (cond(`n_under' > 0, "warn", "ok")) ("")
frame post _rtmx_lc ("areas over-listed (ratio above `ratio_high')") (`n_over') (cond(`n_over' > 0, "warn", "ok")) ("")
frame post _rtmx_lc ("eligible households in the household frame") (`N_frame') ("ok") ("")
frame _rtmx_lc: list, noobs clean
rtmx_table, name(listing_areas) frame(_rtmx_la)
rtmx_table, name(listing_checks) frame(_rtmx_lc)
rtmx_setting, key(listing_file) value("`data_listing'")
rtmx_setting, key(ratio_bounds) value("`ratio_low' `ratio_high'") source("no cited default; labeled setting")
quietly count
rtmx_done
save "`saving_frame'", replace
di as text _n "Household frame saved to `saving_frame' (`N_frame' eligible households). Draw with 03_sample.do step 4 or rtmsample draw, n(#) strata(`area_id')."
if `n_dup' > 0 di as err "`n_dup' duplicate rows must be resolved before the draw"
di as text "The runs are in `export_dir'."
