*! rtmlist_import.ado  version 0.5.0  25oct2026  rtmtools
*! Listing support, step 2: the completed listing read back, checked against the selected areas,
*! and turned into the second-stage frame (one row per listed eligible household) from which
*! rtmsample draw selects the households (UN 2008 para 131 p. 72: a fixed number of households
*! per area from the current listing, selected in the office).
*! The data in memory are the selected areas (as for rtmlist prepare, with list_segments if any);
*! using names the completed listing: a Stata file, a CSV, or the workbook's long sheet (one row
*! per listed household) with the area identifier, the structure number, the household number and
*! the eligibility flag (variable names set by the options). Checks: areas selected but not
*! returned, listed households in areas that were not selected, duplicate structure/household
*! numbers within an area, listed count against expected (ratio() bounds, a labeled setting with
*! no cited default), eligibility. The frame replaces the data in memory (clear) or is saved.
program define rtmlist_import, rclass
    version 16
    syntax using/, ID(varname) [AREAvar(name) STRUCTure(name) HOUSEhold(name) ELIGible(name) PHONE(name) ///
        EXPected(varname numeric) SHEET(string) RATIO(numlist min=2 max=2 >0) SAVing(string) REPLACE CLEAR]
    local areavar = cond("`areavar'" == "", "area_id", "`areavar'")
    local structure = cond("`structure'" == "", "structure_no", "`structure'")
    local household = cond("`household'" == "", "household_no", "`household'")
    local eligible = cond("`eligible'" == "", "eligible", "`eligible'")
    if "`ratio'" == "" local ratio "0.5 2"
    local rlo : word 1 of `ratio'
    local rhi : word 2 of `ratio'
    if `rlo' >= `rhi' {
        di as err "ratio(low high): low must be below high (default 0.5 2)"
        exit 198
    }
    capture confirm file `"`using'"'
    if _rc {
        di as err `"listing file not found: `using'"'
        exit 601
    }
    local changed = c(changed)
    quietly count
    local N_areas = r(N)
    tempvar dup
    quietly bysort `id': gen byte `dup' = (_N > 1)
    quietly count if `dup'
    if r(N) > 0 {
        di as err "id(`id') is not unique among the areas in memory"
        exit 459
    }
    * ---- the areas in memory, as a file to merge ----
    tempfile areas
    preserve
    capture confirm string variable `id'
    local idstr = (_rc == 0)
    foreach v in list_segments list_segment_selected list_segment_prob {
        capture confirm variable `v'
        if _rc quietly gen double `v' = 1
    }
    keep `id' `expected' list_segments list_segment_selected list_segment_prob
    if `idstr' quietly gen str32 area_id_s = `id'
    else quietly gen str32 area_id_s = string(`id', "%20.0g")
    quietly gen byte _area_selected = 1
    drop `id'
    quietly save "`areas'"
    restore
    * ---- the listing ----
    preserve
    local ext = lower(substr(`"`using'"', strrpos(`"`using'"', "."), .))
    if "`ext'" == ".dta" quietly use `"`using'"', clear
    else if "`ext'" == ".csv" quietly import delimited using `"`using'"', clear varnames(1) case(preserve)
    else if inlist("`ext'", ".xlsx", ".xls") {
        local shopt = cond("`sheet'" != "", `"sheet("`sheet'")"', "")
        quietly import excel using `"`using'"', firstrow case(preserve) `shopt' clear
    }
    else {
        di as err "the listing must be a .dta, .csv or .xlsx file"
        exit 198
    }
    foreach v in `areavar' `structure' `household' `eligible' {
        capture confirm variable `v'
        if _rc {
            di as err "the listing has no variable {bf:`v'}; name it with areavar(), structure(), household() or eligible()"
            exit 111
        }
    }
    quietly count
    local N_rows = r(N)
    capture confirm string variable `areavar'
    if _rc quietly gen str32 area_id_s = string(`areavar', "%20.0g")
    else quietly gen str32 area_id_s = trim(`areavar')
    quietly drop if area_id_s == "" & missing(`structure') & missing(`household')
    quietly count
    local N_rows = r(N)
    capture confirm numeric variable `eligible'
    if _rc {
        quietly destring `eligible', replace force
    }
    quietly count if !inlist(`eligible', 0, 1, .)
    local n_badelig = r(N)
    quietly count if missing(`eligible')
    local n_miselig = r(N)
    * duplicates of structure and household within an area
    tempvar d
    quietly bysort area_id_s `structure' `household': gen byte `d' = (_N > 1)
    quietly count if `d'
    local n_dupl = r(N)
    * merge with the selected areas
    quietly merge m:1 area_id_s using "`areas'", generate(_m)
    quietly count if _m == 1
    local n_notselected = r(N)
    quietly levelsof area_id_s if _m == 1, local(extra) clean
    local n_extra_areas : word count `extra'
    quietly count if _m == 2
    local n_notreturned = r(N)
    quietly levelsof area_id_s if _m == 2, local(missing_areas) clean
    * per-area counts
    tempvar one el
    quietly gen byte `one' = (_m == 3)
    quietly gen byte `el' = (_m == 3 & `eligible' == 1)
    capture frame drop _rtmx_la
    frame create _rtmx_la str32 area_id str80 stratum double(expected listed eligible ratio segments segment_selected) str32 flag
    capture frame drop _rtmx_lc
    frame create _rtmx_lc str64 check double(n) str16 status str244 detail
    tempfile counts
    capture frame drop _rtmx_cnt
    frame put area_id_s `one' `el' `expected' list_segments list_segment_selected _area_selected, into(_rtmx_cnt)
    frame _rtmx_cnt {
    quietly collapse (sum) listed = `one' eligible_n = `el' (first) `expected' list_segments list_segment_selected _area_selected, by(area_id_s)
    quietly gen double ratio = cond("`expected'" != "", listed / `expected', .)
    quietly gen str32 flag = ""
    quietly replace flag = "not returned" if _area_selected == 1 & listed == 0
    quietly replace flag = "not selected" if missing(_area_selected)
    if "`expected'" != "" {
        quietly replace flag = "under-listed" if flag == "" & ratio < `rlo'
        quietly replace flag = "over-listed" if flag == "" & ratio > `rhi' & !missing(ratio)
    }
    quietly count if flag == "under-listed"
    local n_under = r(N)
    quietly count if flag == "over-listed"
    local n_over = r(N)
    quietly count if _area_selected == 1 & listed > 0
    local n_returned = r(N)
    forvalues i = 1/`=_N' {
        frame post _rtmx_la (area_id_s[`i']) ("") (cond("`expected'" != "", `expected'[`i'], .)) (listed[`i']) (eligible_n[`i']) (ratio[`i']) (list_segments[`i']) (list_segment_selected[`i']) (flag[`i'])
    }
    rename area_id_s area_id
    quietly save "`counts'"
    }
    frame drop _rtmx_cnt
    * the second-stage frame: listed eligible households of the selected areas
    quietly keep if _m == 3 & `eligible' == 1
    quietly drop _m
    capture drop `areavar'
    capture confirm variable area_id, exact
    if !_rc drop area_id
    rename area_id_s area_id
    sort area_id `structure' `household'
    quietly by area_id: gen long hh_seq = _n
    label variable hh_seq "Household number within the area's listing"
    label variable area_id "Selected area (identifier)"
    quietly count
    local N_frame = r(N)
    quietly merge m:1 area_id using "`counts'", keepusing(listed eligible_n ratio flag) nogenerate keep(master match)
    rename (listed eligible_n) (area_listed area_eligible)
    label variable area_listed "Households listed in the area"
    label variable area_eligible "Eligible households listed in the area"
    label variable ratio "Listed / expected households"
    label variable flag "Listing check flag of the area"
    capture rename list_segment_prob segment_prob
    frame post _rtmx_lc ("rows in the listing file") (`N_rows') ("ok") ("")
    frame post _rtmx_lc ("selected areas returned") (`n_returned') (cond(`n_notreturned' > 0, "warn", "ok")) ("of `N_areas' selected areas; not returned: `n_notreturned'")
    frame post _rtmx_lc ("listed households in areas not selected") (`n_notselected') (cond(`n_notselected' > 0, "warn", "ok")) ("in `n_extra_areas' areas, dropped from the frame")
    frame post _rtmx_lc ("duplicate structure and household numbers") (`n_dupl') (cond(`n_dupl' > 0, "error", "ok")) ("rows sharing area, structure and household number")
    frame post _rtmx_lc ("eligibility missing") (`n_miselig') (cond(`n_miselig' > 0, "warn", "ok")) ("rows with no eligibility flag, not in the frame")
    frame post _rtmx_lc ("eligibility not 0 or 1") (`n_badelig') (cond(`n_badelig' > 0, "error", "ok")) ("")
    if "`expected'" != "" {
        frame post _rtmx_lc ("areas under-listed (ratio below `rlo')") (`n_under') (cond(`n_under' > 0, "warn", "ok")) ("listed / expected; the bounds are a labeled setting, ratio()")
        frame post _rtmx_lc ("areas over-listed (ratio above `rhi')") (`n_over') (cond(`n_over' > 0, "warn", "ok")) ("")
    }
    frame post _rtmx_lc ("eligible households in the second-stage frame") (`N_frame') ("ok") ("one row per listed eligible household of a selected area")
    * ---- report ----
    di as text _n "Listing import ({bf:rtmlist import}): `N_rows' rows from `using'"
    di as text "{hline 96}"
    di as text %-56s "Check" %10s "n" %8s "status" "  detail"
    di as text "{hline 96}"
    frame _rtmx_lc {
        forvalues i = 1/`=_N' {
            di as text %-56s check[`i'] as result %10.0fc n[`i'] as text %8s status[`i'] "  " detail[`i']
        }
    }
    di as text "{hline 96}"
    if `n_notreturned' > 0 di as txt "areas not returned: `missing_areas'"
    if `n_dupl' > 0 di as err "duplicate structure and household numbers must be resolved before the draw (rows are kept so that they can be found: list area_id `structure' `household' if duplicates)"
    di as text "Next: rtmsample draw, n(#) strata(area_id) seed(#) generate(hh) on this frame; the household probability is n / area_eligible, times the segment probability where the area was segmented."
    if `"`saving'"' != "" {
        quietly save `"`saving'"', `replace'
        di as text `"Second-stage frame saved to `saving'"'
    }
    capture _rtm_export table, name(listing_areas) frame(_rtmx_la)
    capture _rtm_export table, name(listing_checks) frame(_rtmx_lc)
    if "`clear'" != "" {
        restore, not
        if `changed' di as text "note: the areas data in memory had unsaved changes; the household frame has replaced them (clear)"
    }
    else restore
    return scalar N_rows = `N_rows'
    return scalar N_frame = `N_frame'
    return scalar N_areas = `N_areas'
    return scalar n_returned = `n_returned'
    return scalar n_not_returned = `n_notreturned'
    return scalar n_not_selected = `n_notselected'
    return scalar n_duplicates = `n_dupl'
    return scalar n_under = `n_under'
    return scalar n_over = `n_over'
    return local areas_not_returned "`missing_areas'"
    local cmd `"rtmlist import using "`using'" `=cond(strpos(`"`0'"', ","), substr(`"`0'"', strpos(`"`0'"', ","), .), "")'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(listing) cmd(`"`cmd'"')
    capture _rtm_export setting, key(listing_file) value(`"`using'"')
    capture _rtm_export setting, key(ratio_bounds) value("`rlo' `rhi'") source("no cited default; labeled setting")
    capture _rtm_export setting, key(id) value("`id'")
end
