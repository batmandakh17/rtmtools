*! rtmlist_prepare.ado  version 0.5.0  25oct2026  rtmtools
*! Listing support, step 1: the listing workbook for the selected areas and, for large areas, the
*! segmentation before listing. The data in memory are the selected areas, one row per area, with
*! their identifier and (optionally) the expected number of households from the frame.
*! Segmentation (UN 2008 paras 138-140, pp. 74-75, the standard segment design; para 86 p. 103,
*! segmentation as an office task): an area whose expected count exceeds segmentsize() is divided
*! into round(expected / segmentsize) segments of roughly equal size, one of which is chosen at
*! random with equal probability; the listing covers that segment only and its selection
*! probability (1 / segments) multiplies the area's. The segments are drawn by the listers on the
*! map (natural boundaries), the number of segments and the selected one being fixed here.
*! The workbook (putexcel) has an Instructions sheet, an Areas sheet and one listing sheet per area
*! with the columns to fill in the field; it prescribes no names: structure and household numbers,
*! a location description, the number of households, eligibility and a phone flag identify the
*! units (UN 2008 paras 95-96 p. 63, 108 p. 66, 131 p. 72: listing in the sampled units; the
*! sample of households is drawn in the office from the returned listing, not by the lister).
program define rtmlist_prepare, rclass
    version 16
    syntax [if] [in], ID(varname) SAVing(string) [EXPected(varname numeric) STRata(varlist) SEGmentsize(real 0) ///
        SEED(string) LISTINGvars(string) REPLACE]
    marksample touse, novarlist
    markout `touse' `id', strok
    quietly count if `touse'
    local N = r(N)
    if `N' == 0 {
        di as err "no areas in the data"
        exit 2000
    }
    if `N' > 500 {
        di as err "`N' areas: the workbook would get `N' sheets; prepare the listing in batches of 500 areas or fewer (use if)"
        exit 459
    }
    if `segmentsize' < 0 {
        di as err "segmentsize() is the number of households a segment should hold, positive (0 = no segmentation)"
        exit 198
    }
    if `segmentsize' > 0 & "`expected'" == "" {
        di as err "segmentation needs expected(varname), the expected number of households of each area"
        exit 198
    }
    tempvar dup
    quietly bysort `touse' `id': gen byte `dup' = (_N > 1) if `touse'
    quietly count if `dup' == 1
    if r(N) > 0 {
        di as err "id(`id') is not unique among the areas (" r(N) " rows share an identifier)"
        exit 459
    }
    if lower(substr(`"`saving'"', -5, 5)) != ".xlsx" local saving `"`saving'.xlsx"'
    capture confirm file `"`saving'"'
    if !_rc & "`replace'" == "" {
        di as err `"`saving' exists; add replace to overwrite it"'
        exit 602
    }
    if "`listingvars'" == "" local listingvars "structure_no location_description n_households household_no eligible has_phone notes"
    local seedgiven "`seed'"
    if `segmentsize' > 0 {
        if "`seed'" != "" {
            capture confirm integer number `seed'
            if _rc {
                di as err "seed() must be a whole number"
                exit 198
            }
        }
        else local seed = runiformint(1, 2147483647)
        set seed `seed'
    }
    * ---- segments ----
    capture drop list_segments list_segment_selected list_segment_prob
    quietly gen long list_segments = 1 if `touse'
    quietly gen long list_segment_selected = 1 if `touse'
    quietly gen double list_segment_prob = 1 if `touse'
    if `segmentsize' > 0 {
        quietly replace list_segments = max(1, round(`expected' / `segmentsize')) if `touse' & !missing(`expected')
        quietly replace list_segment_selected = runiformint(1, list_segments) if `touse'
        quietly replace list_segment_prob = 1 / list_segments if `touse'
    }
    label variable list_segments "Segments the area is divided into before listing (1 = whole area)"
    label variable list_segment_selected "Segment selected for listing (equal probability)"
    label variable list_segment_prob "Selection probability of the listed segment (1 / segments)"
    quietly count if `touse' & list_segments > 1
    local nseg = r(N)
    * ---- the workbook ----
    tempvar lab
    _rtmsample_label `strata', touse(`touse') generate(`lab')
    quietly putexcel set `"`saving'"', sheet("Instructions") replace
    quietly putexcel A1 = "Household listing: instructions"
    quietly putexcel A3 = "One sheet per selected area (named by the area identifier). List every structure in the area (or in the selected segment, see the Areas sheet), from a fixed starting point, in one direction, without gaps."
    quietly putexcel A4 = "For each structure write its number, a short location description, the number of households in it, then one row per household with its number, whether it is an eligible household (1 = yes, 0 = no), and whether it has a telephone (1 = yes, 0 = no, 9 = unknown)."
    quietly putexcel A5 = "Do not select the sample households yourself: return the completed sheets, and the sample is drawn in the office from the listing (UN 2008, para 131)."
    quietly putexcel A6 = "Areas with more than one segment: list only the segment marked as selected on the Areas sheet, with the segment boundaries drawn on the map by the team leader before listing (UN 2008, paras 138-140)."
    quietly putexcel A8 = "Prepared by rtmtools (rtmlist prepare) on `c(current_date)'. Expected household counts come from the sampling frame and are a guide: the listing determines the actual count."
    quietly putexcel set `"`saving'"', sheet("Areas") modify
    quietly putexcel A1 = "area_id" B1 = "stratum" C1 = "expected_households" D1 = "segments" E1 = "segment_selected" F1 = "segment_prob" G1 = "listed_households (fill in)" H1 = "eligible_households (fill in)"
    local r 1
    quietly levelsof `id' if `touse', local(ids)
    forvalues i = 1/`N' {
        local ++r
    }
    tempvar ord
    quietly gen double `ord' = _n
    local r 1
    local sheets ""
    forvalues i = 1/`=_N' {
        if !`touse'[`i'] continue
        local ++r
        capture confirm string variable `id'
        if _rc local aid = string(`id'[`i'])
        else local aid = `id'[`i']
        local st = `lab'[`i']
        local ex = cond("`expected'" != "", string(`expected'[`i']), "")
        quietly putexcel A`r' = "`aid'" B`r' = "`st'" C`r' = "`ex'" D`r' = (list_segments[`i']) E`r' = (list_segment_selected[`i']) F`r' = (list_segment_prob[`i'])
        local sheets `"`sheets' "`aid'""'
    }
    * one listing sheet per area
    local k 0
    foreach aid of local sheets {
        local ++k
        local sh = usubstr(subinstr(subinstr(`"`aid'"', "/", "-", .), "\", "-", .), 1, 31)
        quietly putexcel set `"`saving'"', sheet("`sh'") modify
        quietly putexcel A1 = "Area `aid'" B1 = "Lister:" D1 = "Date:" F1 = "Segment listed (see Areas):"
        local c 0
        foreach v of local listingvars {
            local ++c
            local col = char(64 + `c')
            quietly putexcel `col'3 = "`v'"
        }
        if mod(`k', 25) == 0 di as text "  `k' of `N' area sheets written"
    }
    di as text _n "Listing workbook ({bf:rtmlist prepare}): " as result `N' as text " areas, one sheet each, in " as result `"`saving'"'
    if `segmentsize' > 0 di as text "Segmentation: " as result `nseg' as text " areas with more than one segment of about `segmentsize' households (UN 2008 paras 138-140); seed `seed'"
    di as text "Listing columns: `listingvars'"
    di as text "Return the completed workbook to rtmlist import; the sample of households is then drawn in the office (rtmsample draw)."
    * ---- stored results, record, export ----
    return scalar N_areas = `N'
    return scalar n_segmented = `nseg'
    if `segmentsize' > 0 return scalar seed = `seed'
    return local saving `"`saving'"'
    return local listingvars "`listingvars'"
    local cmd `"rtmlist prepare `0'"'
    if `segmentsize' > 0 & "`seedgiven'" == "" local cmd `"`cmd' seed(`seed')"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(listing) cmd(`"`cmd'"') var(list_segments)
    capture frame drop _rtmx_la
    frame create _rtmx_la str32 area_id str80 stratum double(expected listed eligible ratio segments segment_selected) str32 flag
    forvalues i = 1/`=_N' {
        if !`touse'[`i'] continue
        capture confirm string variable `id'
        if _rc local aid = string(`id'[`i'])
        else local aid = `id'[`i']
        local ex = cond("`expected'" != "", `expected'[`i'], .)
        frame post _rtmx_la ("`aid'") (`"`=usubstr(`lab'[`i'], 1, 80)'"') (`ex') (.) (.) (.) (list_segments[`i']) (list_segment_selected[`i']) (cond(list_segments[`i'] > 1, "segmented", ""))
    }
    capture _rtm_export table, name(listing_areas) frame(_rtmx_la)
    capture _rtm_export setting, key(workbook) value(`"`saving'"')
    capture _rtm_export setting, key(areas) value("`N'")
    if `segmentsize' > 0 capture _rtm_export setting, key(segmentsize) value("`segmentsize'") source("UN 2008 paras 138-140 (standard segment design)")
    capture _rtm_export setting, key(listing_columns) value("`listingvars'") source("UN 2008 paras 95-96, 108, 131")
end
