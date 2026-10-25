********************************************************************************************
* 00_inputs.do -- rtmtools portable do-files: fill the parameter blocks from the input workbook
*
* The input workbook (rtm_inputs.xlsx, schema rtm-input-1.0; see ADAPTATION.md section 0b and
* help rtminput) holds the program's choices (Design sheet), its aggregate inputs (Strata, Frame,
* Totals, Cells, Prefixes) and the names of its data files and variables (Files sheet). This
* do-file reads it and writes:
*   inputs_data/rtm_input_frame.dta, rtm_input_totals.dta, rtm_input_cells.dta  (the sheets as data)
*   03_sample_filled.do   a copy of 03_sample.do with its parameter lines replaced from the workbook
*   04_weights_filled.do  a copy of 04_weights.do with its parameter lines replaced from the workbook
* Then run:  do 03_sample_filled.do   and   do 04_weights_filled.do
* Nothing below the parameter block is specific to a project. Choices the do-files do not cover
* (grid frames, random digit dialing, a listing-based second stage, Neyman allocation, reserve all,
* no nonresponse adjustment) are reported and left at the do-files' own values.
********************************************************************************************
version 16
set more off

* ======================= PARAMETERS: change these lines only ===============================
local inputs        "rtm_inputs.xlsx"   // the input workbook, or a folder of CSV files (design.csv, ...)
local round         1                   // the round whose weights 04_weights_filled.do computes (Files sheet, column round)
local data_dir      "inputs_data"       // where the Frame, Totals and Cells sheets are written as Stata files
* ===========================================================================================

* ---- 0. a helper that replaces the value of a parameter line "local name   value   // comment" ----
capture program drop rtmx_setparam
program define rtmx_setparam
    args infile outfile name value quoted
    tempname fi fo
    file open `fi' using "`infile'", read text
    file open `fo' using "`outfile'", write text replace
    file read `fi' line
    while r(eof) == 0 {
        if regexm(`"`macval(line)'"', "^local `name' ") {
            local cmt ""
            if strpos(`"`macval(line)'"', "//") local cmt = substr(`"`macval(line)'"', strpos(`"`macval(line)'"', "//"), .)
            if "`quoted'" == "q" file write `fo' `"local `name' "`macval(value)'"   `cmt'"' _n
            else file write `fo' `"local `name' `macval(value)'   `cmt'"' _n
        }
        else file write `fo' `"`macval(line)'"' _n
        file read `fi' line
    }
    file close `fi'
    file close `fo'
end

* ---- 1. read the workbook (or the CSV folder) ----
local inputs = subinstr("`inputs'", "\", "/", .)
mata: st_local("isdir", strofreal(direxists(st_local("inputs"))))
local wdir = cond(`isdir', "`inputs'", cond(strpos("`inputs'", "/"), substr("`inputs'", 1, strrpos("`inputs'", "/") - 1), "."))
capture mkdir "`data_dir'"
tempfile design files
foreach s in design strata frame totals cells files {
    capture frame drop _in_`s'
    if `isdir' {
        capture confirm file "`inputs'/`s'.csv"
        if _rc continue
        frame create _in_`s'
        local strcols = cond(inlist("`s'", "design", "files"), "stringcols(_all)", "")
        frame _in_`s': import delimited using "`inputs'/`s'.csv", varnames(1) case(lower) `strcols' clear
    }
    else {
        quietly import excel using "`inputs'", describe
        local found ""
        forvalues i = 1/`r(N_worksheet)' {
            if lower("`r(worksheet_`i')'") == "`s'" local found "`r(worksheet_`i')'"
        }
        if "`found'" == "" continue
        frame create _in_`s'
        local allstr = cond(inlist("`s'", "design", "files"), "allstring", "")
        frame _in_`s': import excel using "`inputs'", sheet("`found'") firstrow case(lower) `allstr' clear
    }
    frame _in_`s' {
        unab vars : _all
        local v1 : word 1 of `vars'
        capture confirm string variable `v1'
        if !_rc quietly drop if strtrim(`v1') == ""
        else quietly drop if missing(`v1')
    }
    local present "`present' `s'"
}
if !`: list posof "design" in present' {
    di as err "the Design sheet is missing from `inputs'"
    exit 459
}

* ---- 2. the Design choices into locals d_<key> ----
frame _in_design {
    quietly count
    forvalues i = 1/`r(N)' {
        local k = lower(strtrim(key[`i']))
        if "`k'" == "" | substr("`k'", 1, 1) == "#" continue
        local d_`k' = strtrim(value[`i'])
    }
}
* ---- 3. the Files rows into locals f_<role>_<column> (paths relative to the workbook's folder) ----
if `: list posof "files" in present' {
    frame _in_files {
        foreach c in id response psu strata weight probabilities phone area_id round {
            capture confirm variable `c'
            if _rc quietly gen str1 `c' = ""
        }
        quietly count
        forvalues i = 1/`r(N)' {
            local role = lower(role[`i'])
            local pth = subinstr(path[`i'], "\", "/", .)
            if substr("`pth'", 1, 1) != "/" & substr("`pth'", 2, 1) != ":" & "`wdir'" != "." local pth "`wdir'/`pth'"
            if "`role'" == "round" local role "round`=round[`i']'"
            local f_`role'_path "`pth'"
            foreach c in id response psu strata weight probabilities phone area_id {
                local f_`role'_`c' = `c'[`i']
            }
        }
    }
}
* ---- 4. the aggregate sheets as Stata files ----
foreach s in frame totals cells {
    if `: list posof "`s'" in present' {
        frame _in_`s': quietly save "`data_dir'/rtm_input_`s'.dta", replace
        di as text "written: `data_dir'/rtm_input_`s'.dta"
    }
}

* ---- 5. 03_sample_filled.do ----
local notes ""
local src "03_sample.do"
local out "03_sample_filled.do"
copy "`src'" "`out'", replace
local a "`out'"
local b "`out'.tmp"
local set03 ""
local set03 `"`set03' "data_frame|q|`data_dir'/rtm_input_frame.dta""'
if "`d_households_per_area'" != "" & "`f_household_list_path'" != "" {
    local set03 `"`set03' "data_hh|q|`f_household_list_path'" "hh_area_id|b|`f_household_list_area_id'" "hh_id|b|`f_household_list_id'" "m_hh|b|`d_households_per_area'""'
}
else {
    local set03 `"`set03' "data_hh|q|""'
    if "`d_households_per_area'" != "" local notes `"`notes' "the second stage from a completed listing is not in 03_sample.do (rtminput, sampling does it); data_hh left empty""'
}
if "`d_phone_per_psu'" != "" & "`f_baseline_path'" != "" {
    local set03 `"`set03' "data_baseline|q|`f_baseline_path'" "bl_id|b|`f_baseline_id'" "bl_psu|b|`f_baseline_psu'" "n_phone|b|`d_phone_per_psu'""'
}
else local set03 `"`set03' "data_baseline|q|""'
foreach k in p relmargin deff attrition rounds firstloss domains {
    if "`d_`k''" != "" local set03 `"`set03' "`k'|b|`d_`k''""'
}
if "`d_nonresponse_mult'" != "" local set03 `"`set03' "nonresponse|b|`d_nonresponse_mult'""'
local set03 `"`set03' "area_id|b|area_id" "strata|q|stratum_id" "size|b|size_hh""'
if "`d_n_areas'" != "" local set03 `"`set03' "n_areas|b|`d_n_areas'""'
if "`d_allocation'" != "" {
    if "`d_allocation'" == "neyman" local notes `"`notes' "Neyman allocation is not in 03_sample.do (rtminput, sampling does it); proportional kept""'
    else local set03 `"`set03' "alloc|b|`d_allocation'""'
}
foreach k in power_q min_areas max_areas {
    if "`d_`k''" != "" local set03 `"`set03' "`k'|b|`d_`k''""'
}
if "`d_stage1'" != "" & !inlist("`d_stage1'", "ppssys", "") local notes `"`notes' "stage1 `d_stage1' is not in 03_sample.do, which draws by systematic PPS (rtminput, sampling runs the other methods)""'
local sv = cond("`d_sort_vars'" != "", "`d_sort_vars'", "stratum_id area_id")
local set03 `"`set03' "sort_vars|q|`sv'""'
if "`d_reserve_areas'" != "" {
    if lower("`d_reserve_areas'") == "all" local notes `"`notes' "reserve_areas all is not in 03_sample.do (a number of reserves); 2 kept""'
    else local set03 `"`set03' "reserve_areas|b|`d_reserve_areas'""'
}
if "`d_seed'" != "" local set03 `"`set03' "seed1|b|`d_seed'" "seed2|b|`d_seed'" "seed3|b|`d_seed'""'
if "`d_rdd'" == "yes" local notes `"`notes' "random digit dialing is not in 03_sample.do (rtmsample rdd, or rtminput, sampling)""'
foreach item of local set03 {
    gettoken name rest : item, parse("|")
    gettoken bar rest : rest, parse("|")
    gettoken qq rest : rest, parse("|")
    local value = substr("`rest'", 2, .)
    rtmx_setparam "`a'" "`b'" "`name'" "`value'" "`qq'"
    copy "`b'" "`a'", replace
}
erase "`b'"
di as text "written: `out'"

* ---- 6. 04_weights_filled.do ----
local src "04_weights.do"
local out "04_weights_filled.do"
copy "`src'" "`out'", replace
local a "`out'"
local b "`out'.tmp"
local set04 ""
if "`f_baseline_path'" != "" local set04 `"`set04' "data_baseline|q|`f_baseline_path'""'
else local notes `"`notes' "no baseline row on the Files sheet: data_baseline of 04_weights.do left as is""'
if "`f_round`round'_path'" != "" local set04 `"`set04' "data_round|q|`f_round`round'_path'" "responded|b|`f_round`round'_response'" "round_vars|q|`f_round`round'_response'""'
else local notes `"`notes' "no round `round' on the Files sheet: data_round of 04_weights.do left as is""'
if "`d_calibrate'" != "" & "`d_calibrate'" != "none" local set04 `"`set04' "totals_file|q|`data_dir'/rtm_input_totals.dta" "calibrate|b|`d_calibrate'""'
else local set04 `"`set04' "totals_file|q|" "calibrate|b|none""'
if "`d_nonresponse'" == "post" local set04 `"`set04' "cell_file|q|`data_dir'/rtm_input_cells.dta" "cell_total|b|total""'
else local set04 `"`set04' "cell_file|q|""'
foreach c in id strata psu phone {
    if "`f_baseline_`c''" != "" local set04 `"`set04' "`c'|b|`f_baseline_`c''""'
}
if "`d_base_weight'" == "probabilities" local set04 `"`set04' "w_base|b|" "prob_vars|q|`f_baseline_probabilities'""'
else if "`f_baseline_weight'" != "" local set04 `"`set04' "w_base|b|`f_baseline_weight'" "prob_vars|q|""'
if "`d_nonresponse'" != "" {
    if "`d_nonresponse'" == "none" local notes `"`notes' "nonresponse none is not in 04_weights.do, which always adjusts (rtminput, weights carries the weight forward); logit kept""'
    else local set04 `"`set04' "method|b|`=cond("`d_nonresponse'" == "propensity", "logit", "`d_nonresponse'")'""'
}
foreach k in covariates classes cells cal_vars {
    if "`d_`k''" != "" local set04 `"`set04' "`k'|q|`d_`k''""'
}
foreach k in ngroups moments trim trim_pct cal_ll cal_ul seed {
    if "`d_`k''" != "" local set04 `"`set04' "`k'|b|`d_`k''""'
}
if "`d_trim'" == "cap" {
    if "`d_trim_cap'" != "" local set04 `"`set04' "trim_cap|b|`d_trim_cap'""'
    if "`d_trim_capmult'" != "" local set04 `"`set04' "trim_capmult|b|`d_trim_capmult'""'
}
foreach item of local set04 {
    gettoken name rest : item, parse("|")
    gettoken bar rest : rest, parse("|")
    gettoken qq rest : rest, parse("|")
    local value = substr("`rest'", 2, .)
    rtmx_setparam "`a'" "`b'" "`name'" "`value'" "`qq'"
    copy "`b'" "`a'", replace
}
erase "`b'"
di as text "written: `out'"

* ---- 7. what the workbook asked for that the do-files do not cover ----
if `"`notes'"' != "" {
    di as text _n "Choices of the Design sheet that the portable do-files do not cover (use the rtmtools commands or rtminput for them):"
    foreach n of local notes {
        di as text "  - `n'"
    }
}
foreach s in design strata frame totals cells files {
    capture frame drop _in_`s'
}
di as text _n "Next:  do 03_sample_filled.do   and   do 04_weights_filled.do   (ADAPTATION.md explains every line of their parameter blocks)"
