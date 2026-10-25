*! rtminput.ado  version 0.6.0  25oct2026  rtmtools
*! One input workbook (or a folder of CSV files) for a whole program, schema rtm-input-1.0: the
*! Design sheet holds the method choices as key/value rows, Strata/Frame/Totals/Cells/Prefixes the
*! aggregate inputs, and Files points to the household-level data files, which stay outside the
*! workbook. check validates every sheet and writes a Checks sheet into a copy of the workbook;
*! sampling and weights run the package's commands with the workbook's choices and write the
*! commands they ran into a do-file next to the outputs. Nothing here is a method: every statistical
*! step is an rtmtools command (rtmframe, rtmsample, rtmlist, rtmweight), and each default's source
*! is on the Design sheet and in those commands' help files.
program define rtminput, rclass
    version 16
    syntax [using/] [, CHECK SAMPling WEIGHTS ROUND(integer 0) OUTdir(string) TEMPlate REPLACE NOFiles NOSUMmary]
    if "`template'" != "" {
        _rtminput_template, `replace'
        exit
    }
    if `"`using'"' == "" {
        di as err "using is required: rtminput using rtm_inputs.xlsx, check | sampling | weights round(#)"
        exit 100
    }
    local nmode = ("`check'" != "") + ("`sampling'" != "") + ("`weights'" != "")
    if `nmode' > 1 {
        di as err "choose one of check, sampling, weights"
        exit 198
    }
    if `nmode' == 0 local check check
    if "`weights'" != "" & `round' < 1 {
        di as err "weights needs round(#): the round number on the Files sheet"
        exit 198
    }
    local mode = cond("`check'" != "", "check", cond("`sampling'" != "", "sampling", "weights"))
    * ---- where the inputs are: a workbook or a folder of CSV files ----
    local using = subinstr(`"`using'"', "\", "/", .)
    mata: st_local("isdir", strofreal(direxists(st_local("using"))))
    if `isdir' {
        if substr("`using'", -1, 1) == "/" local using = substr("`using'", 1, strlen("`using'") - 1)
        local indir "`using'"
    }
    else {
        capture confirm file `"`using'"'
        if _rc {
            di as err `"input workbook or folder not found: `using'"'
            exit 601
        }
        local ext = lower(substr("`using'", strrpos("`using'", "."), .))
        if !inlist("`ext'", ".xlsx", ".xls") {
            di as err "using must name an Excel workbook (.xlsx) or a folder of CSV files"
            exit 198
        }
        local indir = cond(strpos("`using'", "/"), substr("`using'", 1, strrpos("`using'", "/") - 1), ".")
    }
    _rtminput_dropframes
    capture file close _rtmin_fh
    capture frame drop _rtmin_summary
    frame create _rtmin_summary str40 section strL text
    * ---- read, validate ----
    _rtminput_read, using("`using'") isdir(`isdir')
    local present "`r(present)'"
    if !`: list posof "design" in present' {
        di as err "the Design sheet (design.csv) is missing: it holds the method choices"
        _rtminput_dropframes
        exit 459
    }
    capture noisily _rtminput_check, mode(`mode') round(`round') indir("`indir'") present("`present'") `nofiles'
    local rc = _rc
    if `rc' {
        _rtminput_dropframes
        exit `rc'
    }
    local n_errors = r(n_errors)
    local n_warnings = r(n_warnings)
    local outdir = cond(`"`outdir'"' != "", `"`outdir'"', "`r(output_dir)'")
    * ---- check: report, write the Checks sheet into a copy, export ----
    if "`mode'" == "check" {
        _rtminput_report_checks
        if !`isdir' {
            local stub = substr("`using'", 1, strrpos("`using'", ".") - 1)
            local checked "`stub'_checked`ext'"
            capture copy "`using'" "`checked'", replace
            if !_rc {
                capture frame _rtmin_checks: export excel using "`checked'", sheet("Checks", replace) firstrow(variables)
                if _rc local checked ""
            }
            else local checked ""
        }
        else {
            local checked "`using'/checks.csv"
            capture frame _rtmin_checks: export delimited using "`checked'", replace
            if _rc local checked ""
        }
        if "`checked'" != "" di as text `"Checks written to {browse "`checked'"} (the original is not changed)"'
        _rtminput_summary, mode(check) outdir("`indir'") using("`using'") round(0) n_errors(`n_errors') n_warnings(`n_warnings') checked("`checked'") `nosummary'
        _rtminput_export_check, using("`using'") n_errors(`n_errors') n_warnings(`n_warnings') present("`present'")
        return local summary "$RTMTOOLS_LAST_SUMMARY"
        return scalar n_errors = `n_errors'
        return scalar n_warnings = `n_warnings'
        return local checked `"`checked'"'
        return local sheets "`present'"
        _rtminput_dropframes
        exit
    }
    * ---- a run: stop on errors, otherwise call the commands with the Design choices ----
    if `n_errors' > 0 {
        _rtminput_report_checks
        di as err `n_errors' " problem(s) in the inputs; fix them (rtminput using ..., check writes them into a copy of the workbook)"
        _rtminput_dropframes
        exit 459
    }
    if `n_warnings' > 0 _rtminput_report_checks
    capture mkdir "`outdir'"
    local logfile "`outdir'/rtm_input_`mode'`=cond(`round' > 0, "_round`round'", "")'_commands.do"
    quietly file open _rtmin_fh using "`logfile'", write text replace
    file write _rtmin_fh "* commands run by rtminput using `using', `mode'`=cond(`round' > 0, " round(`round')", "")' on `c(current_date)' `c(current_time)'" _n
    file write _rtmin_fh "* (rtmtools 0.6.0; every line below is an rtmtools or Stata command; rerun this file to repeat the run)" _n
    if "`mode'" == "sampling" capture noisily _rtminput_sampling, indir("`indir'") outdir("`outdir'") present("`present'")
    else capture noisily _rtminput_weights, indir("`indir'") outdir("`outdir'") present("`present'") round(`round')
    local rc = _rc
    capture file close _rtmin_fh
    if `rc' {
        di as err "the run stopped (see the message above); the commands run so far are in `logfile'"
        _rtminput_dropframes
        exit `rc'
    }
    di as text _n `"Outputs in {browse "`outdir'"}; the commands run are in `logfile'"'
    _rtminput_summary, mode(`mode') outdir("`outdir'") using("`using'") round(`round') n_errors(0) n_warnings(`n_warnings') logfile("`logfile'") `nosummary'
    return local summary "$RTMTOOLS_LAST_SUMMARY"
    return local outdir "`outdir'"
    return local commands "`logfile'"
    return scalar n_warnings = `n_warnings'
    _rtminput_dropframes
end

* ---- copy the shipped template into the current folder ----
program define _rtminput_template
    syntax [, REPLACE]
    quietly findfile rtm_inputs.xlsx
    local src "`r(fn)'"
    capture confirm file "rtm_inputs.xlsx"
    if !_rc & "`replace'" == "" {
        di as err "rtm_inputs.xlsx exists in the current folder; add replace to overwrite it"
        exit 602
    }
    copy "`src'" "rtm_inputs.xlsx", replace
    di as text `"Template written: {browse "rtm_inputs.xlsx"} (fill it in, then rtminput using rtm_inputs.xlsx, check)"'
end

* ---- a sheet frame saved as a dataset, without the sheet-row bookkeeping column ----
program define _rtminput_saveframe
    syntax, frame(name) file(string)
    frame `frame' {
        capture drop _xlrow
        quietly save "`file'", replace
    }
end

program define _rtminput_dropframes
    foreach f in design strata frame totals cells prefixes files checks summary {
        capture frame drop _rtmin_`f'
    }
    capture macro drop RTMIN_*
end

* ---- read the sheets into frames _rtmin_<sheet> ----
program define _rtminput_read, rclass
    syntax, using(string) isdir(integer)
    local present ""
    local wanted "design strata frame totals cells prefixes files"
    if `isdir' {
        foreach s of local wanted {
            capture confirm file "`using'/`s'.csv"
            if _rc continue
            frame create _rtmin_`s'
            local strcols = cond(inlist("`s'", "design", "files"), "stringcols(_all)", "")
            capture frame _rtmin_`s': import delimited using "`using'/`s'.csv", varnames(1) case(lower) `strcols' clear
            if _rc {
                di as err "could not read `using'/`s'.csv (rc " _rc ")"
                exit _rc
            }
            local present "`present' `s'"
        }
    }
    else {
        quietly import excel using "`using'", describe
        local nws = r(N_worksheet)
        forvalues i = 1/`nws' {
            local ws`i' "`r(worksheet_`i')'"
        }
        foreach s of local wanted {
            local found ""
            forvalues i = 1/`nws' {
                if lower("`ws`i''") == "`s'" local found "`ws`i''"
            }
            if "`found'" == "" continue
            frame create _rtmin_`s'
            local allstr = cond(inlist("`s'", "design", "files"), "allstring", "")
            capture frame _rtmin_`s': import excel using "`using'", sheet("`found'") firstrow case(lower) `allstr' clear
            if _rc {
                di as err "could not read sheet `found' of `using' (rc " _rc ")"
                exit _rc
            }
            local present "`present' `s'"
        }
    }
    * drop rows whose first column is empty (blank lines at the end of a sheet)
    foreach s of local present {
        frame _rtmin_`s' {
            quietly gen long _xlrow = _n + 1
            unab vars : _all
            local v1 : word 1 of `vars'
            capture confirm string variable `v1'
            if !_rc quietly drop if strtrim(`v1') == ""
            else quietly drop if missing(`v1')
            foreach v of varlist _all {
                capture confirm string variable `v'
                if !_rc quietly replace `v' = strtrim(`v')
            }
        }
    }
    return local present "`present'"
end

* ---- one problem ----
program define _rtminput_flag
    args sheet row column severity problem
    frame post _rtmin_checks ("`sheet'") (`row') ("`column'") ("`severity'") (`"`problem'"')
end

* ---- the Design keys, their defaults and allowed values ----
program define _rtminput_keys, rclass
    return local keys "project seed output_dir target p relmargin margin change power deff nonresponse_mult attrition rounds firstloss domains minsize maxsize n_areas allocation power_q min_areas max_areas stage1 sort_vars reserve_areas households_per_area segment_size phone_per_psu rdd base_weight nonresponse covariates classes cells ngroups moments trim trim_pct trim_cap trim_capmult calibrate cal_vars cal_ll cal_ul report_by report_files"
    return local numeric "seed p relmargin margin change power deff nonresponse_mult attrition rounds firstloss domains minsize maxsize n_areas power_q min_areas max_areas households_per_area segment_size phone_per_psu ngroups moments trim_pct trim_cap trim_capmult cal_ll cal_ul"
    return local v_target "level change"
    return local v_allocation "proportional equal neyman power"
    return local v_stage1 "ppssys pps systematic srs grid"
    return local v_rdd "yes no"
    return local v_base_weight "baseline probabilities"
    return local v_nonresponse "propensity probit classes ebalance ebalance_nobase post none"
    return local v_trim "none winsor cap"
    return local v_calibrate "none rake regress post"
    return local v_report_files "yes no"
end

* ---- validate everything; the Design values end in globals RTMIN_<key> for the runners ----
program define _rtminput_check, rclass
    syntax, mode(string) round(integer) indir(string) present(string) [NOFiles]
    capture frame drop _rtmin_checks
    frame create _rtmin_checks str16 sheet double row str32 column str8 severity str244 problem
    _rtminput_keys
    local keys "`r(keys)'"
    local numeric "`r(numeric)'"
    foreach k in target allocation stage1 rdd base_weight nonresponse trim calibrate report_files {
        local v_`k' "`r(v_`k')'"
    }
    * defaults
    macro drop RTMIN_*
    foreach k of local keys {
        global RTMIN_`k' ""
    }
    global RTMIN_output_dir "rtm_outputs"
    global RTMIN_target "level"
    global RTMIN_allocation "proportional"
    global RTMIN_stage1 "ppssys"
    global RTMIN_reserve_areas "2"
    global RTMIN_rdd "no"
    global RTMIN_base_weight "baseline"
    global RTMIN_nonresponse "propensity"
    global RTMIN_trim "none"
    global RTMIN_calibrate "none"
    global RTMIN_report_files "yes"
    global RTMIN_minsize "0"
    global RTMIN_maxsize "0"
    global RTMIN_min_areas "0"
    global RTMIN_max_areas "0"
    global RTMIN_segment_size "150"
    local sev_s = cond("`mode'" == "sampling", "error", "warning")
    local sev_w = cond("`mode'" == "weights", "error", "warning")
    * ---- Design ----
    frame _rtmin_design {
        capture confirm variable key value
        if _rc {
            _rtminput_flag Design 1 "key value" error "the Design sheet needs the columns key and value"
        }
        else {
            quietly count
            forvalues i = 1/`r(N)' {
                local k = lower(strtrim(key[`i']))
                local v = strtrim(value[`i'])
                if "`k'" == "" | substr("`k'", 1, 1) == "#" continue
                if !`: list posof "`k'" in keys' {
                    _rtminput_flag Design `=_xlrow[`i']' key warning "unknown key `k' (ignored)"
                    continue
                }
                if "`v'" == "" continue
                if `: list posof "`k'" in numeric' {
                    capture confirm number `v'
                    if _rc {
                        _rtminput_flag Design `=_xlrow[`i']' value error "`k' must be a number (found `v')"
                        continue
                    }
                }
                if "`k'" == "reserve_areas" & lower("`v'") != "all" {
                    capture confirm integer number `v'
                    if _rc {
                        _rtminput_flag Design `=_xlrow[`i']' value error "reserve_areas must be a whole number, all or 0 (found `v')"
                        continue
                    }
                }
                if "`v_`k''" != "" {
                    local vl = lower("`v'")
                    if !`: list posof "`vl'" in v_`k'' {
                        _rtminput_flag Design `=_xlrow[`i']' value error "`k' must be one of: `v_`k'' (found `v')"
                        continue
                    }
                    local v "`vl'"
                }
                global RTMIN_`k' `"`v'"'
            }
        }
    }
    if "$RTMIN_target" == "change" & "$RTMIN_change" == "" _rtminput_flag Design . change error "target change needs a value for change"
    if "$RTMIN_stage1" == "grid" & `: list posof "frame" in present' {
        frame _rtmin_frame: capture confirm numeric variable x y
        if _rc _rtminput_flag Frame 1 "x y" `sev_s' "stage1 grid needs numeric x and y columns on the Frame sheet"
    }
    if "`mode'" == "sampling" & "$RTMIN_n_areas" == "" _rtminput_flag Design . n_areas error "n_areas is required for sampling"
    if inlist("$RTMIN_nonresponse", "propensity", "probit", "ebalance", "ebalance_nobase") & "$RTMIN_covariates" == "" ///
        _rtminput_flag Design . covariates `sev_w' "nonresponse $RTMIN_nonresponse needs covariates"
    if "$RTMIN_nonresponse" == "classes" & "$RTMIN_classes" == "" _rtminput_flag Design . classes `sev_w' "nonresponse classes needs classes"
    if "$RTMIN_nonresponse" == "post" & "$RTMIN_cells" == "" _rtminput_flag Design . cells `sev_w' "nonresponse post needs cells (the Cells sheet columns)"
    if "$RTMIN_trim" == "cap" & "$RTMIN_trim_cap" == "" & "$RTMIN_trim_capmult" == "" _rtminput_flag Design . trim_cap `sev_w' "trim cap needs trim_cap or trim_capmult"
    * ---- Strata ----
    local has_strata = `: list posof "strata" in present'
    if `has_strata' {
        frame _rtmin_strata {
            capture confirm variable stratum_id
            if _rc _rtminput_flag Strata 1 stratum_id error "the Strata sheet needs the column stratum_id"
            else {
                tempvar d
                quietly bysort stratum_id: gen byte `d' = _N > 1
                quietly count if `d'
                if r(N) > 0 _rtminput_flag Strata . stratum_id error "`r(N)' rows share a stratum_id"
                capture confirm string variable stratum_id
                if !_rc quietly count if stratum_id == ""
                else quietly count if missing(stratum_id)
                if r(N) > 0 _rtminput_flag Strata . stratum_id error "`r(N)' rows have no stratum_id"
            }
        }
    }
    * ---- Frame ----
    if `: list posof "frame" in present' {
        frame _rtmin_frame {
            foreach c in area_id stratum_id size_hh {
                capture confirm variable `c'
                if _rc _rtminput_flag Frame 1 `c' error "the Frame sheet needs the column `c'"
            }
            capture confirm variable area_id stratum_id size_hh
            if !_rc {
                quietly count
                local N = r(N)
                if `N' == 0 _rtminput_flag Frame 2 area_id `sev_s' "the Frame sheet has no rows"
                tempvar d
                quietly bysort area_id: gen byte `d' = _N > 1
                quietly count if `d'
                if r(N) > 0 {
                    local n = 0
                    forvalues i = 1/`N' {
                        if `d'[`i'] & `n' < 25 {
                            _rtminput_flag Frame `=_xlrow[`i']' area_id error "area_id `=area_id[`i']' appears more than once"
                            local ++n
                        }
                    }
                }
                capture confirm string variable area_id
                if !_rc quietly count if area_id == ""
                else quietly count if missing(area_id)
                if r(N) > 0 _rtminput_flag Frame . area_id error "`r(N)' rows have no area_id"
                capture confirm numeric variable size_hh
                if _rc _rtminput_flag Frame 1 size_hh error "size_hh must be numeric (households per area)"
                else {
                    quietly count if missing(size_hh) | size_hh <= 0
                    if r(N) > 0 {
                        local n = 0
                        forvalues i = 1/`N' {
                            if (missing(size_hh[`i']) | size_hh[`i'] <= 0) & `n' < 25 {
                                _rtminput_flag Frame `=_xlrow[`i']' size_hh error "size_hh is missing or not positive"
                                local ++n
                            }
                        }
                    }
                }
                capture confirm variable exclude
                if !_rc {
                    capture confirm numeric variable exclude
                    if _rc _rtminput_flag Frame 1 exclude error "exclude must be 0, 1 or empty"
                    else {
                        quietly count if !missing(exclude) & !inlist(exclude, 0, 1)
                        if r(N) > 0 _rtminput_flag Frame . exclude error "`r(N)' rows have exclude not 0 or 1"
                    }
                }
                if `has_strata' {
                    frame _rtmin_strata: capture confirm string variable stratum_id
                    local s_str = !_rc
                    capture confirm string variable stratum_id
                    local f_str = !_rc
                    if `s_str' != `f_str' _rtminput_flag Frame 1 stratum_id error "stratum_id is text on one sheet and numeric on the other (Strata, Frame)"
                    else {
                        tempvar lk
                        capture frlink m:1 stratum_id, frame(_rtmin_strata) generate(`lk')
                        if !_rc {
                            quietly count if missing(`lk')
                            if r(N) > 0 _rtminput_flag Frame . stratum_id error "`r(N)' rows have a stratum_id that is not on the Strata sheet"
                        }
                    }
                }
                foreach v in $RTMIN_sort_vars {
                    capture confirm variable `v'
                    if _rc _rtminput_flag Design . sort_vars error "sort_vars names `v', which is not a Frame column"
                }
            }
        }
    }
    else if "`mode'" == "sampling" _rtminput_flag Frame . . error "the Frame sheet is required for sampling"
    * ---- Totals ----
    local need_totals = ("$RTMIN_calibrate" != "none")
    if `: list posof "totals" in present' {
        frame _rtmin_totals {
            foreach c in variable level total {
                capture confirm variable `c'
                if _rc _rtminput_flag Totals 1 `c' error "the Totals sheet needs the column `c'"
            }
            capture confirm variable variable level total
            if !_rc {
                capture confirm numeric variable total
                if _rc _rtminput_flag Totals 1 total error "total must be numeric"
                else {
                    quietly count if missing(total) | total <= 0
                    if r(N) > 0 _rtminput_flag Totals . total error "`r(N)' rows have a missing or non-positive total"
                }
                tempvar d
                quietly bysort variable level: gen byte `d' = _N > 1
                quietly count if `d'
                if r(N) > 0 _rtminput_flag Totals . "variable level" error "`r(N)' rows repeat a variable and level"
                quietly levelsof variable, local(tvars) clean
                foreach v in $RTMIN_cal_vars {
                    if !`: list posof "`v'" in tvars' _rtminput_flag Design . cal_vars `sev_w' "cal_vars names `v', which has no rows on the Totals sheet"
                }
            }
        }
    }
    else if `need_totals' _rtminput_flag Totals . . `sev_w' "calibrate $RTMIN_calibrate needs the Totals sheet"
    * ---- Cells ----
    if `: list posof "cells" in present' {
        frame _rtmin_cells {
            capture confirm numeric variable total
            if _rc _rtminput_flag Cells 1 total error "the Cells sheet needs a numeric column total (the last column)"
            foreach v in $RTMIN_cells {
                capture confirm variable `v'
                if _rc _rtminput_flag Design . cells `sev_w' "cells names `v', which is not a Cells column"
            }
            capture confirm variable $RTMIN_cells
            if !_rc & "$RTMIN_cells" != "" {
                tempvar d
                quietly bysort $RTMIN_cells: gen byte `d' = _N > 1
                quietly count if `d'
                if r(N) > 0 _rtminput_flag Cells . "$RTMIN_cells" error "`r(N)' rows repeat a cell"
            }
        }
    }
    else if "$RTMIN_nonresponse" == "post" _rtminput_flag Cells . . `sev_w' "nonresponse post needs the Cells sheet"
    * ---- Prefixes ----
    if `: list posof "prefixes" in present' {
        frame _rtmin_prefixes {
            foreach c in prefix n_numbers digits {
                capture confirm numeric variable `c'
                if _rc _rtminput_flag Prefixes 1 `c' error "the Prefixes sheet needs a numeric column `c'"
            }
            capture confirm numeric variable prefix n_numbers digits
            if !_rc {
                quietly count if missing(prefix) | prefix < 0 | prefix != int(prefix)
                if r(N) > 0 _rtminput_flag Prefixes . prefix error "`r(N)' rows have a prefix that is not a whole number"
                quietly count if missing(n_numbers) | n_numbers < 1 | n_numbers != int(n_numbers)
                if r(N) > 0 _rtminput_flag Prefixes . n_numbers error "`r(N)' rows have n_numbers below 1"
                quietly count if missing(digits) | digits < 1 | digits > 12 | digits != int(digits)
                if r(N) > 0 _rtminput_flag Prefixes . digits error "`r(N)' rows have digits outside 1 to 12"
                quietly summarize digits
                if r(min) != r(max) _rtminput_flag Prefixes . digits error "digits must be the same on every row (one length per draw)"
            }
        }
    }
    else if "$RTMIN_rdd" == "yes" _rtminput_flag Prefixes . . `sev_s' "rdd yes needs the Prefixes sheet"
    * ---- Files ----
    foreach r in bl hl ls {
        global RTMIN_F_`r' ""
    }
    global RTMIN_F_rds ""
    if `: list posof "files" in present' {
        frame _rtmin_files {
            foreach c in role path {
                capture confirm variable `c'
                if _rc _rtminput_flag Files 1 `c' error "the Files sheet needs the column `c'"
            }
            foreach c in id response psu strata weight probabilities phone area_id round {
                capture confirm variable `c'
                if _rc quietly gen str1 `c' = ""
            }
            capture confirm variable role path
            if !_rc {
                quietly count
                forvalues i = 1/`r(N)' {
                    local role = lower(role[`i'])
                    local xr = _xlrow[`i']
                    if "`role'" == "" continue
                    if !inlist("`role'", "baseline", "round", "household_list", "listing") {
                        _rtminput_flag Files `xr' role error "role must be baseline, round, household_list or listing (found `role')"
                        continue
                    }
                    local rcode = cond("`role'" == "baseline", "bl", cond("`role'" == "household_list", "hl", cond("`role'" == "listing", "ls", "rd")))
                    local path = subinstr(path[`i'], "\", "/", .)
                    if "`path'" == "" {
                        _rtminput_flag Files `xr' path error "`role' has no path"
                        continue
                    }
                    if substr("`path'", 1, 1) != "/" & substr("`path'", 2, 1) != ":" local path "`indir'/`path'"
                    local pext = lower(substr("`path'", strrpos("`path'", "."), .))
                    if "`nofiles'" == "" {
                        capture confirm file "`path'"
                        if _rc {
                            _rtminput_flag Files `xr' path error "`role' file not found: `path'"
                            continue
                        }
                    }
                    local vl ""
                    if "`pext'" == ".dta" & "`nofiles'" == "" {
                        capture describe using "`path'", varlist
                        if !_rc local vl "`r(varlist)'"
                    }
                    local need ""
                    if "`role'" == "baseline" local need "id"
                    if "`role'" == "round" local need "id response"
                    if inlist("`role'", "household_list", "listing") local need "id area_id"
                    if "`role'" == "listing" local need "area_id"
                    foreach c of local need {
                        if "`=`c'[`i']'" == "" _rtminput_flag Files `xr' `c' error "`role' needs `c' (the variable's name in that file)"
                    }
                    if "`role'" == "round" {
                        local rn = round[`i']
                        capture confirm integer number `rn'
                        if _rc _rtminput_flag Files `xr' round error "round needs the round number"
                        else {
                            if `: list posof "`rn'" in rounds_seen' _rtminput_flag Files `xr' round error "round `rn' appears twice"
                            local rounds_seen "`rounds_seen' `rn'"
                            global RTMIN_F_rd`rn' `"`path'"'
                            global RTMIN_F_rd`rn'_id "`=id[`i']'"
                            global RTMIN_F_rd`rn'_response "`=response[`i']'"
                            global RTMIN_F_rds "$RTMIN_F_rds `rn'"
                        }
                    }
                    else {
                        if "${RTMIN_F_`rcode'}" != "" _rtminput_flag Files `xr' role error "`role' appears twice; one row per role (rounds are numbered)"
                        global RTMIN_F_`rcode' `"`path'"'
                        foreach c in id psu strata weight probabilities phone area_id {
                            global RTMIN_F_`rcode'_`c' "`=`c'[`i']'"
                        }
                    }
                    * the named variables exist in the file
                    if "`vl'" != "" {
                        foreach c in id response psu strata weight probabilities phone area_id {
                            foreach v in `=`c'[`i']' {
                                if !`: list posof "`v'" in vl' _rtminput_flag Files `xr' `c' error "`role' file has no variable `v'"
                            }
                        }
                    }
                    else if "`pext'" != ".dta" & "`nofiles'" == "" _rtminput_flag Files `xr' path warning "`role' is not a .dta file: its variables are not checked here"
                }
            }
        }
    }
    * what the requested run needs from Files
    if "`mode'" == "weights" {
        if "$RTMIN_F_bl" == "" _rtminput_flag Files . role error "weights needs a baseline row on the Files sheet"
        else {
            if "$RTMIN_base_weight" == "baseline" & "$RTMIN_F_bl_weight" == "" _rtminput_flag Files . weight error "base_weight baseline needs the baseline's weight column"
            if "$RTMIN_base_weight" == "probabilities" & "$RTMIN_F_bl_probabilities" == "" _rtminput_flag Files . probabilities error "base_weight probabilities needs the baseline's probabilities column"
        }
        if "${RTMIN_F_rd`round'}" == "" _rtminput_flag Files . round error "weights round(`round') needs a round row with round = `round'"
    }
    if "`mode'" == "sampling" {
        if "$RTMIN_households_per_area" != "" & "$RTMIN_F_hl" == "" & "$RTMIN_F_ls" == "" ///
            _rtminput_flag Files . role error "households_per_area needs a household_list or a listing row on the Files sheet (blank it for no second stage)"
        if "$RTMIN_phone_per_psu" != "" {
            if "$RTMIN_F_bl" == "" _rtminput_flag Files . role error "phone_per_psu needs a baseline row on the Files sheet"
            else if "$RTMIN_F_bl_psu" == "" _rtminput_flag Files . psu error "phone_per_psu needs the baseline's psu column"
        }
    }
    if "$RTMIN_report_by" != "" & "$RTMIN_F_bl" != "" & "`nofiles'" == "" {
        capture describe using "$RTMIN_F_bl", varlist
        local bvl "`r(varlist)'"
        if !_rc & !`: list posof "$RTMIN_report_by" in bvl' _rtminput_flag Design . report_by `sev_w' "report_by names $RTMIN_report_by, which is not in the baseline file"
    }
    frame _rtmin_checks {
        quietly count if severity == "error"
        local ne = r(N)
        quietly count if severity == "warning"
        local nw = r(N)
        if `ne' + `nw' == 0 frame post _rtmin_checks ("all") (.) ("") ("ok") ("every sheet checked; no problem found")
    }
    return scalar n_errors = `ne'
    return scalar n_warnings = `nw'
    return local output_dir "$RTMIN_output_dir"
end

program define _rtminput_report_checks
    frame _rtmin_checks {
        quietly count if severity == "error"
        local ne = r(N)
        quietly count if severity == "warning"
        local nw = r(N)
        di as text _n "Input checks: " as result `ne' as text " error(s), " as result `nw' as text " warning(s)"
        if `ne' + `nw' > 0 {
            sort sheet row
            list sheet row column severity problem, noobs sepby(sheet) abbreviate(12) string(70)
        }
    }
end

program define _rtminput_export_check
    syntax, using(string) n_errors(integer) n_warnings(integer) present(string)
    capture _rtm_export start, workflow(input) step(check) cmd(`"rtminput using `using', check"')
    _rtminput_keys
    foreach k in `r(keys)' {
        if "${RTMIN_`k'}" != "" capture _rtm_export setting, key(`k') value(`"${RTMIN_`k'}"') source("Design sheet of `using'")
    }
    capture _rtm_export table, name(input_checks) frame(_rtmin_checks)
    capture _rtm_export message, text("sheets present: `present'; `n_errors' error(s), `n_warnings' warning(s)")
    capture _rtm_export done
end

* ---- run one command: show it, write it to the commands do-file, execute it ----
program define _rtminput_do
    di as text `"{bf:.} `macval(0)'"'
    capture file write _rtmin_fh `"`macval(0)'"' _n
    capture noisily `macval(0)'
    local rc = _rc
    if `rc' {
        di as err _n "This step stopped (Stata error `rc'). In plain words:"
        if `rc' == 111 di as err "  a variable named on the Files or Design sheet (id, response, psu, strata, weight, phone, area_id, covariates, classes, cells, cal_vars, sort_vars) is not in the file it is used with; check the spelling on that sheet"
        else if inlist(`rc', 601, 603) di as err "  a file named on the Files sheet was not found or could not be read; check its path (relative to the workbook's folder)"
        else if `rc' == 602 di as err "  an output file exists and could not be replaced; close it if it is open in another program"
        else if `rc' == 459 di as err "  the data do not fit this step: repeated identifiers, a stratum with no units, or more units asked for than exist; the message above says which"
        else if `rc' == 198 di as err "  a setting on the Design sheet produced an option this command does not accept; the message above names it (help rtminput lists the allowed values)"
        else if inlist(`rc', 2000, 2001) di as err "  no observations were left for this step: check the response indicator and the phone column on the Files sheet, and that the round file's ids match the baseline's"
        else if `rc' == 430 di as err "  the calibration or balancing did not converge: fewer calibration variables or covariates, or bounds, usually fix it"
        else if `rc' == 1 di as err "  the step was interrupted"
        else di as err "  see the message above; the commands that ran before this one are in the commands do-file of the output folder"
        exit `rc'
    }
end

* ---- one line of the plain-language summary ----
program define _rtminput_say
    args section text
    frame post _rtmin_summary ("`section'") (`"`macval(text)'"')
end

* ---- the summary page: what was done, in plain words, with the numbers and the files ----
program define _rtminput_summary
    syntax, mode(string) outdir(string) using(string) round(integer) n_errors(integer) n_warnings(integer) [checked(string) logfile(string) NOSUMmary]
    local stamp : di %tcCCYYNNDD-HHMMSS clock("`c(current_date)' `c(current_time)'", "DMY hms")
    local tag = cond(`round' > 0, "`mode'_round`round'", "`mode'")
    local f "`outdir'/rtm_summary_`tag'_`stamp'.html"
    local when "`c(current_date)' `c(current_time)'"
    local title = cond("`mode'" == "check", "Check of the input workbook", cond("`mode'" == "sampling", "Sampling run", "Weights of round `round'"))
    local proj "$RTMIN_project"
    tempname fh
    capture file close `fh'
    quietly file open `fh' using "`f'", write text replace
    file write `fh' "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>" _n
    file write `fh' "<title>`title'</title>" _n
    file write `fh' "<style>:root{--page:#f9f9f7;--ink:#0b0b0b;--muted:#8f8d86;--line:#e2e0da;--accent:#1c5cab;--good:#0ca30c;--crit:#d03b3b;--box:#eef4fc}" _n
    file write `fh' "@media (prefers-color-scheme: dark){:root{--page:#0d0d0d;--ink:#ffffff;--muted:#898781;--line:#34332f;--accent:#86b6ef;--box:#16202c}}" _n
    file write `fh' "body{margin:0;background:var(--page);color:var(--ink);font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;font-size:16px;line-height:1.55}" _n
    file write `fh' "main{max-width:860px;margin:0 auto;padding:24px 16px 48px}h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 8px;border-bottom:1px solid var(--line);padding-bottom:4px}" _n
    file write `fh' ".meta{color:var(--muted);margin-bottom:18px}.ok{color:var(--good);font-weight:600}.bad{color:var(--crit);font-weight:600}" _n
    file write `fh' "table{border-collapse:collapse;width:100%;font-size:14.5px;margin:8px 0}th,td{text-align:left;padding:5px 8px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-weight:600}" _n
    file write `fh' "p{margin:6px 0}code{font-family:ui-monospace,Menlo,monospace;font-size:13.5px;background:var(--box);padding:1px 5px;border-radius:4px}.box{background:var(--box);border-radius:8px;padding:12px 14px;margin:10px 0}</style></head><body><main>" _n
    file write `fh' "<h1>`title'</h1><div class='meta'>" `"`=cond("`proj'" != "", "`proj' &middot; ", "")'"' "`when' &middot; from <code>`using'</code></div>" _n
    * ---- the verdict line ----
    if "`mode'" == "check" {
        if `n_errors' == 0 file write `fh' "<p class='ok'>The workbook is ready: every sheet checked, 0 errors" `"`=cond(`n_warnings' > 0, ", `n_warnings' warning(s) to read below", "")'"' ".</p>" _n
        else file write `fh' "<p class='bad'>`n_errors' error(s) to fix before a run" `"`=cond(`n_warnings' > 0, ", and `n_warnings' warning(s)", "")'"' ". Each line below names the sheet, the Excel row and the column.</p>" _n
        if "`checked'" != "" file write `fh' "<p>The same list is on the <b>Checks</b> sheet of <code>`checked'</code>. Fix the cells in your own workbook and run the check again.</p>" _n
    }
    else {
        file write `fh' "<p class='ok'>The run completed. What was done, in order:</p>" _n
    }
    * ---- the steps said by the runners ----
    frame _rtmin_summary {
        quietly count
        local N = r(N)
        local last ""
        forvalues i = 1/`N' {
            local sec = section[`i']
            local txt = text[`i']
            if "`sec'" != "`last'" {
                if "`last'" != "" & "`last'" != "table" file write `fh' "</div>" _n
                if "`sec'" == "table" {
                    file write `fh' `"`macval(txt)'"' _n
                }
                else {
                    file write `fh' "<h2>`sec'</h2><div class='box'>" _n
                    file write `fh' "<p>" `"`macval(txt)'"' "</p>" _n
                }
                local last "`sec'"
            }
            else {
                if "`sec'" == "table" file write `fh' `"`macval(txt)'"' _n
                else file write `fh' "<p>" `"`macval(txt)'"' "</p>" _n
            }
        }
        if "`last'" != "" & "`last'" != "table" file write `fh' "</div>" _n
    }
    * ---- the problems (check) ----
    if "`mode'" == "check" | `n_warnings' > 0 {
        frame _rtmin_checks {
            quietly count if severity != "ok"
            if r(N) > 0 {
                file write `fh' "<h2>Problems found</h2><table><tr><th>Sheet</th><th>Row</th><th>Column</th><th>Severity</th><th>What is wrong</th></tr>" _n
                quietly count
                forvalues i = 1/`r(N)' {
                    if severity[`i'] == "ok" continue
                    local rw = cond(missing(row[`i']), "", string(row[`i']))
                    local pr = subinstr(subinstr(problem[`i'], "&", "&amp;", .), "<", "&lt;", .)
                    local sev = cond(severity[`i'] == "error", "bad", "")
                    file write `fh' "<tr><td>" (sheet[`i']) "</td><td>`rw'</td><td>" (column[`i']) "</td><td class='`sev''>" (severity[`i']) "</td><td>`pr'</td></tr>" _n
                }
                file write `fh' "</table>" _n
            }
        }
    }
    * ---- files and how to repeat ----
    if "`mode'" != "check" {
        file write `fh' "<h2>Files written</h2><table><tr><th>File</th><th>What it holds</th></tr>" _n
        foreach pair in "rtm_sample_areas.dta|the area frame with the selection, probabilities, weights, reserve ranks" ///
                        "rtm_sample_households.dta|the selected households with their design weights" ///
                        "rtm_listing_forms.xlsx|the listing forms: one sheet per selected area, with the segment to list" ///
                        "rtm_sample_areas_selected.dta|the selected areas with their segments (the file a returned listing is checked against)" ///
                        "rtm_sample_phone.dta|the baseline with the phone sample marked and every other household's replacement rank" ///
                        "rtm_rdd_numbers.dta|the random digit dialing numbers (kept here only)" ///
                        "rtm_weights_round`round'.dta|the phone sample with the weights w0 (base), w1 (adjusted), w1t (trimmed), w2 (calibrated)" ///
                        "rtm_weights_round`round'.docx|the weighting method note (Word)" ///
                        "rtm_weights_round`round'.xlsx|the weighting report (Excel)" {
            gettoken fn desc : pair, parse("|")
            local desc = substr("`desc'", 2, .)
            if "`mode'" == "sampling" & strpos("`fn'", "rtm_weights") continue
            if "`mode'" == "weights" & !strpos("`fn'", "rtm_weights") continue
            capture confirm file "`outdir'/`fn'"
            if !_rc file write `fh' "<tr><td><code>`outdir'/`fn'</code></td><td>`desc'</td></tr>" _n
        }
        file write `fh' "</table>" _n
        file write `fh' "<h2>To repeat or adapt this run</h2><p>Every command that ran is in <code>`logfile'</code>, one line per step with a comment above it. Running that file in Stata repeats the run exactly (the seed is in it); each command's own tables are in the export folder the dashboard shows.</p>" _n
    }
    file write `fh' "<p class='meta'>Written by rtmtools (rtminput). Every number comes from the package's documented commands; the method choices are the Design sheet's. Nothing was sent anywhere.</p></main></body></html>" _n
    file close `fh'
    global RTMTOOLS_LAST_SUMMARY "`f'"
    global RTMTOOLS_LAST_OUTDIR "`outdir'"
    di as text `"Summary: {browse "`f'"}"'
    if "`nosummary'" == "" _rtm_osopen "`f'"
end

program define _rtminput_note
    di as text `"* `macval(0)'"'
    capture file write _rtmin_fh `"* `macval(0)'"' _n
end

* ---- a file named on the Files sheet as a Stata dataset (csv and xlsx are converted into outdir) ----
program define _rtminput_asdta, rclass
    syntax, path(string) outdir(string) name(string)
    local pext = lower(substr("`path'", strrpos("`path'", "."), .))
    if "`pext'" == ".dta" {
        return local dta "`path'"
        exit
    }
    preserve
    if "`pext'" == ".csv" _rtminput_do import delimited using "`path'", varnames(1) case(preserve) clear
    else _rtminput_do import excel using "`path'", firstrow case(preserve) clear
    _rtminput_do save "`outdir'/rtm_input_`name'.dta", replace
    restore
    return local dta "`outdir'/rtm_input_`name'.dta"
end

* ================================ sampling ================================
program define _rtminput_sampling
    syntax, indir(string) outdir(string) present(string)
    local seed = cond("$RTMIN_seed" != "", "seed($RTMIN_seed)", "")
    * ---- 1. sample size ----
    if "$RTMIN_p" != "" | "$RTMIN_change" != "" {
        local o ""
        foreach k in p margin relmargin deff attrition rounds firstloss domains {
            if "${RTMIN_`k'}" != "" local o "`o' `k'(${RTMIN_`k'})"
        }
        if "$RTMIN_nonresponse_mult" != "" local o "`o' nonresponse($RTMIN_nonresponse_mult)"
        if "$RTMIN_target" == "change" {
            local o "`o' change($RTMIN_change)"
            if "$RTMIN_power" != "" local o "`o' power($RTMIN_power)"
        }
        _rtminput_note step 1: sample size per domain (rtmsample size)
        _rtminput_do rtmsample size, `o'
        _rtminput_say "Sample size" `"For a `=cond("$RTMIN_target" == "change", "change of $RTMIN_change", "proportion of about $RTMIN_p")' with the precision asked, each domain needs <b>`: di %9.0fc r(n_domain)'</b> households and the `=r(domains)' domains together <b>`: di %9.0fc r(n_total)'</b>, after the design effect, nonresponse and the attrition reserve for `=r(rounds)' rounds (UN 2008 section 3.3; HFPS Vol. 2)."'
    }
    * ---- 2. the frame: checked, allocated, drawn ----
    _rtminput_note step 2: the area frame from the Frame sheet, checked (rtmframe list)
    _rtminput_saveframe, frame(_rtmin_frame) file("`outdir'/rtm_input_frame.dta")
    if `: list posof "strata" in present' {
        _rtminput_saveframe, frame(_rtmin_strata) file("`outdir'/rtm_input_strata.dta")
    }
    _rtminput_do use "`outdir'/rtm_input_frame.dta", clear
    if `: list posof "strata" in present' {
        frame _rtmin_strata: capture confirm variable label
        if !_rc {
            capture _rtminput_do merge m:1 stratum_id using "`outdir'/rtm_input_strata.dta", keep(master match) keepusing(label) nogenerate
            if !_rc capture _rtminput_do rename label stratum_label
        }
    }
    local exo ""
    capture confirm numeric variable exclude
    if !_rc local exo "exclude(exclude)"
    _rtminput_do rtmframe list, id(area_id) size(size_hh) strata(stratum_id) minsize($RTMIN_minsize) maxsize($RTMIN_maxsize) `exo'
    _rtminput_say "Area frame" `"The Frame sheet has <b>`: di %9.0fc r(N)'</b> areas in <b>`=r(H)'</b> strata; <b>`: di %9.0fc r(N_ok)'</b> can be sampled. Flagged: `=r(n_dup)' repeated ids, `=r(n_badsize)' with a missing or zero size, `=r(n_small)' below $RTMIN_minsize households, `=r(n_large)' above $RTMIN_maxsize (large areas are listed in segments), `=r(n_excluded)' excluded."'
    capture confirm variable frame_ok
    local okif = cond(_rc, "", "if frame_ok == 1")
    _rtminput_note step 3: allocation of $RTMIN_n_areas areas across strata ($RTMIN_allocation)
    local ao ""
    if "$RTMIN_allocation" == "power" & "$RTMIN_power_q" != "" local ao "power($RTMIN_power_q)"
    if "$RTMIN_min_areas" != "0" local ao "`ao' min($RTMIN_min_areas)"
    if "$RTMIN_max_areas" != "0" local ao "`ao' max($RTMIN_max_areas)"
    _rtminput_do rtmsample allocate `okif', strata(stratum_id) n($RTMIN_n_areas) size(size_hh) method($RTMIN_allocation) `ao' generate(n_area)
    _rtminput_say "Allocation" `"<b>$RTMIN_n_areas</b> areas were allocated across the strata by <b>$RTMIN_allocation</b> allocation`=cond("$RTMIN_min_areas" != "0" | "$RTMIN_max_areas" != "0", " (at least $RTMIN_min_areas and at most $RTMIN_max_areas per stratum)", "")'; `=r(n_bounded)' strata were held at a bound."'
    _rtminput_alloctable
    _rtminput_note step 4: first stage ($RTMIN_stage1), $RTMIN_reserve_areas reserve(s) per stratum
    local sv = cond("$RTMIN_sort_vars" != "", "$RTMIN_sort_vars", "stratum_id area_id")
    local ro = cond("$RTMIN_reserve_areas" != "0", "reserve($RTMIN_reserve_areas)", "")
    if "$RTMIN_stage1" == "grid" {
        _rtminput_do rtmsample grid `okif', n(n_area) strata(stratum_id) pps(size_hh) xy(x y) `ro' `seed' id(area_id) generate(area)
    }
    else {
        local pp = cond(inlist("$RTMIN_stage1", "pps", "ppssys"), "pps(size_hh)", "")
        _rtminput_do rtmsample draw `okif', n(n_area) strata(stratum_id) `pp' method($RTMIN_stage1) sort(`sv') `ro' `seed' id(area_id) generate(area)
    }
    _rtminput_say "First stage" `"<b>`: di %9.0fc r(n_selected)'</b> areas were selected by <b>$RTMIN_stage1</b>`=cond(inlist("$RTMIN_stage1", "pps", "ppssys"), " (probability proportional to households)", "")'`=cond("$RTMIN_sort_vars" != "", ", the frame sorted by $RTMIN_sort_vars within strata", "")', with <b>`: di %9.0fc r(n_reserve)'</b> reserve areas ranked for replacement`=cond(r(n_certainty) > 0 & r(n_certainty) < ., " and `=r(n_certainty)' taken with certainty", "")'. Seed `=r(seed)': the same seed repeats the draw."'
    _rtminput_do save "`outdir'/rtm_sample_areas.dta", replace
    * ---- 5. listing forms for the selected areas (no household list), then 6. the second stage ----
    if "$RTMIN_F_hl" == "" {
        _rtminput_note step 5: listing forms for the selected areas, one sheet per area, areas above $RTMIN_segment_size households in segments (rtmlist prepare)
        _rtminput_do keep if area_sel == 1
        _rtminput_do keep area_id stratum_id size_hh area_pi area_w
        _rtminput_do rtmlist prepare, id(area_id) expected(size_hh) strata(stratum_id) segmentsize($RTMIN_segment_size) `seed' saving("`outdir'/rtm_listing_forms.xlsx") replace
        _rtminput_say "Listing forms" `"The listing workbook for the <b>`: di %9.0fc r(N_areas)'</b> selected areas was written (<code>rtm_listing_forms.xlsx</code>: an Instructions sheet, an Areas sheet and one sheet per area). <b>`: di %9.0fc r(n_segmented)'</b> areas larger than $RTMIN_segment_size households were divided into segments of about that size and one segment per area was chosen at random (UN 2008 paras 138-140): the listers list that segment only, and its probability enters the household weights."'
        _rtminput_do save "`outdir'/rtm_sample_areas_selected.dta", replace
    }
    if "$RTMIN_households_per_area" != "" {
        if "$RTMIN_F_hl" != "" {
            _rtminput_note step 6: second stage, $RTMIN_households_per_area households per selected area from the household list
            _rtminput_asdta, path("$RTMIN_F_hl") outdir("`outdir'") name(household_list)
            local hl "`r(dta)'"
            local ha "$RTMIN_F_hl_area_id"
            _rtminput_do use "`outdir'/rtm_sample_areas.dta", clear
            _rtminput_do keep if area_sel == 1
            _rtminput_do keep area_id stratum_id area_pi area_w
            if "`ha'" != "area_id" _rtminput_do rename area_id `ha'
            _rtminput_do merge 1:m `ha' using "`hl'", keep(match) nogenerate
            _rtminput_do rtmsample draw, n($RTMIN_households_per_area) strata(`ha') `seed' id($RTMIN_F_hl_id) generate(hh)
            _rtminput_do keep if hh_sel == 1
            _rtminput_do rtmweight base, probability(area_pi hh_pi) generate(w_design)
            _rtminput_say "Households" `"<b>`: di %9.0fc r(N)'</b> households were selected, $RTMIN_households_per_area in each selected area, from the household list. Their design weights (1 / the product of the two stage probabilities) add to <b>`: di %12.0fc r(sum)'</b> households, which should be close to the frame's total."'
            _rtminput_do save "`outdir'/rtm_sample_households.dta", replace
        }
        else if "$RTMIN_F_ls" != "" {
            _rtminput_note step 6: second stage from the completed listing (rtmlist import), $RTMIN_households_per_area households per area
            local la "$RTMIN_F_ls_area_id"
            local lo = cond("`la'" != "" & "`la'" != "area_id", "areavar(`la')", "")
            _rtminput_do use "`outdir'/rtm_sample_areas_selected.dta", clear
            local idtype : type area_id
            _rtminput_do rtmlist import using "$RTMIN_F_ls", id(area_id) expected(size_hh) `lo' clear
            _rtminput_say "Listing returned" `"The completed listing was read and checked: <b>`: di %9.0fc r(n_returned)'</b> areas returned, `=r(n_not_returned)' not returned, `=r(n_duplicates)' duplicate rows, `=r(n_over)' areas listed far above and `=r(n_under)' far below the expected count. The household frame holds <b>`: di %9.0fc r(N_frame)'</b> eligible households."'
            * the household frame carries the area id as text; match the areas file's type before merging
            capture confirm string variable area_id
            local nowstr = !_rc
            if `nowstr' & !strpos("`idtype'", "str") _rtminput_do destring area_id, replace
            if !`nowstr' & strpos("`idtype'", "str") _rtminput_do tostring area_id, replace
            _rtminput_do merge m:1 area_id using "`outdir'/rtm_sample_areas_selected.dta", keep(match) keepusing(area_pi stratum_id) nogenerate
            _rtminput_do rtmsample draw, n($RTMIN_households_per_area) strata(area_id) `seed' generate(hh)
            _rtminput_do keep if hh_sel == 1
            _rtminput_do rtmweight base, probability(area_pi segment_prob hh_pi) generate(w_design)
            _rtminput_say "Households" `"<b>`: di %9.0fc r(N)'</b> households were selected, $RTMIN_households_per_area in each selected area, from the completed listing; the segment's probability is part of the design weight. The design weights add to <b>`: di %12.0fc r(sum)'</b> households."'
            _rtminput_do save "`outdir'/rtm_sample_households.dta", replace
        }
    }
    * ---- 7. phone subsample of the baseline ----
    if "$RTMIN_phone_per_psu" != "" {
        _rtminput_note step 7: phone subsample, $RTMIN_phone_per_psu households per PSU of the baseline, every other household an ordered replacement
        _rtminput_asdta, path("$RTMIN_F_bl") outdir("`outdir'") name(baseline)
        _rtminput_do use "`r(dta)'", clear
        local io = cond("$RTMIN_F_bl_id" != "", "id($RTMIN_F_bl_id)", "")
        local psu "$RTMIN_F_bl_psu"
        local ph "$RTMIN_F_bl_phone"
        * the phone sample is drawn among the households with a phone (the Files sheet's phone column);
        * a PSU with fewer than phone_per_psu of them is taken in full
        local eligif ""
        if "`ph'" != "" local eligif "if `ph' == 1"
        _rtminput_do capture drop _rtmx_nph
        _rtminput_do bysort `psu': egen double _rtmx_nph = total(`=cond("`ph'" != "", "`ph' == 1", "1")')
        _rtminput_do quietly replace _rtmx_nph = min(_rtmx_nph, $RTMIN_phone_per_psu)
        quietly egen byte _rtmx_tag = tag(`psu')
        quietly count if _rtmx_tag & _rtmx_nph < $RTMIN_phone_per_psu
        local n_full = r(N)
        quietly drop _rtmx_tag
        _rtminput_do rtmsample draw `eligif', n(_rtmx_nph) strata(`psu') reserve(all) `seed' `io' generate(ph)
        local nsel = r(n_selected)
        local nres = r(n_reserve)
        _rtminput_do quietly replace ph_sel = 0 if missing(ph_sel)
        _rtminput_do drop _rtmx_nph
        _rtminput_say "Phone sample" `"<b>`: di %9.0fc `nsel''</b> baseline households were drawn to be called first, $RTMIN_phone_per_psu per PSU`=cond("`ph'" != "", " among the households that gave a phone number", "")'; the other <b>`: di %9.0fc `nres''</b>`=cond("`ph'" != "", " with a phone", "")' are ranked as replacements within their PSU (ph_reserve), so a household that cannot be reached is replaced by the next one in its own PSU.`=cond(`n_full' == 1, " In 1 PSU fewer than $RTMIN_phone_per_psu households had a phone, and all of them were taken.", cond(`n_full' > 1, " In `n_full' PSUs fewer than $RTMIN_phone_per_psu households had a phone, and all of them were taken.", ""))'"'
        if "$RTMIN_F_bl_weight" != "" {
            local bo = cond("$RTMIN_F_bl_strata" != "", "by($RTMIN_F_bl_strata)", "")
            _rtminput_do rtmweight base, baseweight($RTMIN_F_bl_weight) subsample(ph_sel) `bo' generate(w_phone)
            _rtminput_say "Phone sample" `"Their weights carry the baseline's total of <b>`: di %12.0fc r(sum_baseline)'</b> (the baseline weight redistributed to the called households within strata, HFPS Vol. 2 p. 21)."'
        }
        _rtminput_do save "`outdir'/rtm_sample_phone.dta", replace
        _rtminput_say "Phone sample" "For the weights of the rounds, point the Files sheet's baseline row to this file (<code>rtm_sample_phone.dta</code>) and its phone column to <code>ph_sel</code>: the households called first are then the phone sample the weights start from."
    }
    * ---- 7. random digit dialing ----
    if "$RTMIN_rdd" == "yes" {
        frame _rtmin_prefixes {
            quietly count
            local pl ""
            local nl ""
            forvalues i = 1/`r(N)' {
                local pl "`pl' `=prefix[`i']'"
                local nl "`nl' `=n_numbers[`i']'"
            }
            local dg = digits[1]
        }
        _rtminput_note step 8: random digit dialing numbers from the Prefixes sheet (kept in rtm_rdd_numbers.dta; never exported)
        _rtminput_do rtmsample rdd, prefixes(`pl') n(`nl') digits(`dg') `seed' saving("`outdir'/rtm_rdd_numbers.dta") replace
        _rtminput_say "Random digit dialing" `"<b>`: di %9.0fc r(n_numbers)'</b> numbers were generated from `=r(n_prefixes)' prefixes with `=r(digits)' random digits, none twice; they are in the output folder only and never in the export."'
    }
end

* ---- the allocation by stratum, as an HTML table in the summary ----
program define _rtminput_alloctable
    capture confirm variable stratum_id n_area size_hh
    if _rc exit
    capture confirm variable stratum_label
    local haslab = !_rc
    capture confirm variable frame_ok
    local okc = cond(_rc, "1", "frame_ok == 1")
    tempname fr
    frame put stratum_id `=cond(`haslab', "stratum_label", "")' size_hh n_area if `okc', into(`fr')
    frame `fr' {
        collapse (count) n_units = size_hh (sum) size_sum = size_hh (first) n_area `=cond(`haslab', "(first) stratum_label", "")', by(stratum_id)
        local h = "<table><tr><th>Stratum</th>" + cond(`haslab', "<th>Label</th>", "") + "<th>Areas in frame</th><th>Households</th><th>Areas allocated</th></tr>"
        _rtminput_say "table" `"`h'"'
        quietly count
        forvalues i = 1/`r(N)' {
            local lab = cond(`haslab', "<td>" + stratum_label[`i'] + "</td>", "")
            _rtminput_say "table" `"<tr><td>`=stratum_id[`i']'</td>`lab'<td>`: di %9.0fc n_units[`i']'</td><td>`: di %12.0fc size_sum[`i']'</td><td>`=n_area[`i']'</td></tr>"'
        }
        _rtminput_say "table" "</table>"
    }
    frame drop `fr'
end

* ================================ weights ================================
program define _rtminput_weights
    syntax, indir(string) outdir(string) present(string) round(integer)
    local id "$RTMIN_F_bl_id"
    local resp "${RTMIN_F_rd`round'_response}"
    local rid = cond("${RTMIN_F_rd`round'_id}" != "", "${RTMIN_F_rd`round'_id}", "`id'")
    local strata "$RTMIN_F_bl_strata"
    local phone "$RTMIN_F_bl_phone"
    _rtminput_note step 1: the baseline merged with round `round' (nonrespondents kept; a household absent from the round file counts as not interviewed)
    _rtminput_asdta, path("$RTMIN_F_bl") outdir("`outdir'") name(baseline)
    local bl "`r(dta)'"
    _rtminput_asdta, path("${RTMIN_F_rd`round'}") outdir("`outdir'") name(round`round')
    local rd "`r(dta)'"
    if "`rid'" != "`id'" {
        _rtminput_do use `rid' `resp' using "`rd'", clear
        _rtminput_do rename `rid' `id'
        _rtminput_do save "`outdir'/rtm_input_round`round'_keyed.dta", replace
        local rd "`outdir'/rtm_input_round`round'_keyed.dta"
    }
    _rtminput_do use "`bl'", clear
    _rtminput_do merge 1:1 `id' using "`rd'", keepusing(`resp') keep(master match) nogenerate
    _rtminput_say "Data" `"The baseline (<b>`: di %9.0fc _N'</b> households) was merged with the round `round' file on <code>`id'</code>; a household absent from the round file counts as not interviewed."'
    _rtminput_do quietly replace `resp' = 0 if missing(`resp')
    * ---- base weights ----
    local so = cond("`phone'" != "", "subsample(`phone')", "")
    local bo = cond("`strata'" != "", "by(`strata')", "")
    if "$RTMIN_base_weight" == "baseline" {
        _rtminput_note step 2: base weights, the baseline weight redistributed to the phone sample within strata (rtmweight base)
        _rtminput_do rtmweight base, baseweight($RTMIN_F_bl_weight) `so' `bo' generate(w0)
    }
    else {
        _rtminput_note step 2: base weights, 1 / product of the stage probabilities (rtmweight base)
        _rtminput_do rtmweight base, probability($RTMIN_F_bl_probabilities) `so' `bo' generate(w0)
    }
    _rtminput_say "Base weights" `"`=cond("$RTMIN_base_weight" == "baseline", "The baseline weight was redistributed to the phone sample within strata", "The base weight is 1 / the product of the stage probabilities")' (w0): <b>`: di %9.0fc r(N)'</b> households, weights adding to <b>`: di %12.0fc r(sum)'</b>."'
    if "`phone'" != "" _rtminput_do keep if `phone' == 1
    * ---- nonresponse ----
    local m "$RTMIN_nonresponse"
    if "`m'" == "none" {
        _rtminput_note step 3: no nonresponse adjustment (Design: nonresponse none)
        _rtminput_do generate double w1 = w0
        _rtminput_say "Nonresponse adjustment" "No adjustment was asked (Design: nonresponse none): w1 equals w0, and the households not interviewed are not compensated for."
    }
    else {
        local mm = cond("`m'" == "propensity", "logit", "`m'")
        local no ""
        if inlist("`mm'", "logit", "probit") {
            local no "covariates($RTMIN_covariates)"
            if "$RTMIN_ngroups" != "" local no "`no' ngroups($RTMIN_ngroups)"
        }
        if inlist("`mm'", "ebalance", "ebalance_nobase") {
            local no "covariates($RTMIN_covariates)"
            if "$RTMIN_moments" != "" local no "`no' moments($RTMIN_moments)"
        }
        if "`mm'" == "classes" local no "classes($RTMIN_classes)"
        if "`mm'" == "post" {
            _rtminput_saveframe, frame(_rtmin_cells) file("`outdir'/rtm_input_cells.dta")
            local no `"cells($RTMIN_cells) cellfile("`outdir'/rtm_input_cells.dta") celltotal(total)"'
        }
        _rtminput_note step 3: nonresponse and attrition adjustment, method `mm' (rtmweight nonresponse)
        _rtminput_do rtmweight nonresponse `resp', weight(w0) method(`mm') `no' generate(w1)
        local mtxt = cond("`mm'" == "logit", "a logit response propensity in `=cond("$RTMIN_ngroups" != "", "$RTMIN_ngroups", "10")' groups (the guidelines' method, HFPS Vol. 2 Annex A2.3.1)", cond("`mm'" == "probit", "a probit response propensity in groups", cond("`mm'" == "classes", "weighting classes $RTMIN_classes (UN 2008 section 6.5)", cond("`mm'" == "ebalance", "entropy balancing of the respondents to the sample's weighted means of $RTMIN_covariates (the L2 programs' practice; equal to raking)", cond("`mm'" == "ebalance_nobase", "entropy balancing without base weights (the L2PHL 2026 form)", "post-stratification of the respondents to the Cells sheet (the L2PHL form)")))))
        _rtminput_say "Nonresponse adjustment" `"Of <b>`: di %9.0fc r(N_sample)'</b> households in the phone sample, <b>`: di %9.0fc r(N_resp)'</b> were interviewed (response rate `: di %4.1f 100 * r(rr_unweighted)' percent unweighted, `: di %4.1f 100 * r(rr_weighted)' weighted). Their weights were raised by `mtxt' so that they stand for the whole sample (w1): adjustment factors from `: di %5.2f r(factor_min)' to `: di %5.2f r(factor_max)', median `: di %5.2f r(factor_p50)'; Kish's design effect from the weights `: di %5.3f r(kish)'."'
    }
    * ---- trimming ----
    if "$RTMIN_trim" == "none" {
        _rtminput_note step 4: no trimming (Design: trim none)
        _rtminput_do generate double w1t = w1
        _rtminput_say "Trimming" "No trimming was asked (Design: trim none): w1t equals w1."
    }
    else {
        local to ""
        if "$RTMIN_trim" == "winsor" & "$RTMIN_trim_pct" != "" local to "pct($RTMIN_trim_pct)"
        if "$RTMIN_trim" == "cap" {
            if "$RTMIN_trim_cap" != "" local to "cap($RTMIN_trim_cap)"
            else local to "capmult($RTMIN_trim_capmult)"
        }
        _rtminput_note step 4: trimming, rule $RTMIN_trim (rtmweight trim)
        _rtminput_do rtmweight trim w1 if `resp' == 1, generate(w1t) rule($RTMIN_trim) `to'
        _rtminput_say "Trimming" `"The largest weights were `=cond("$RTMIN_trim" == "winsor", "winsorised at the `=cond("$RTMIN_trim_pct" != "", "$RTMIN_trim_pct", "98")'th percentile (HFPS Vol. 2 p. 11)", "capped (UN 2008 section 6.8)")' and the rest rescaled (w1t): <b>`=r(n_trimmed_high)'</b> weights lowered`=cond(r(n_trimmed_low) > 0, ", `=r(n_trimmed_low)' raised", "")'; Kish's design effect `: di %5.3f r(kish_before)' before, `: di %5.3f r(kish_after)' after."'
    }
    * ---- calibration ----
    if "$RTMIN_calibrate" == "none" {
        _rtminput_note step 5: no calibration (Design: calibrate none)
        _rtminput_do generate double w2 = w1t
        _rtminput_say "Calibration" "No calibration was asked (Design: calibrate none): w2 equals w1t."
    }
    else {
        _rtminput_saveframe, frame(_rtmin_totals) file("`outdir'/rtm_input_totals.dta")
        local cv "$RTMIN_cal_vars"
        if "`cv'" == "" {
            frame _rtmin_totals: quietly levelsof variable, local(cv) clean
        }
        local iv ""
        foreach v of local cv {
            local iv "`iv' i.`v'"
        }
        local co ""
        if "$RTMIN_cal_ll" != "" local co "ll($RTMIN_cal_ll)"
        if "$RTMIN_cal_ul" != "" local co "`co' ul($RTMIN_cal_ul)"
        _rtminput_note step 5: calibration to the Totals sheet, method $RTMIN_calibrate (rtmweight calibrate)
        _rtminput_do rtmweight calibrate `iv' [pw=w1t] if `resp' == 1, generate(w2) totalsfile("`outdir'/rtm_input_totals.dta") method($RTMIN_calibrate) `co'
        _rtminput_say "Calibration" `"The weights were calibrated by <b>$RTMIN_calibrate</b> to the Totals sheet (`cv') so that they add to the population totals (w2; Deville and Sarndal 1992): largest relative gap to a total after calibration `: di %8.6f r(max_rel_diff)', weights adding to <b>`: di %12.0fc r(sum_after)'</b>; the calibration factors range from `: di %5.2f r(g_min)' to `: di %5.2f r(g_max)'; Kish's design effect `: di %5.3f r(kish_after)'."'
    }
    * ---- report and save ----
    local ro = cond("$RTMIN_report_by" != "", "by($RTMIN_report_by)", "")
    if "$RTMIN_report_files" == "yes" local ro `"`ro' docx("`outdir'/rtm_weights_round`round'.docx") excel("`outdir'/rtm_weights_round`round'.xlsx")"'
    _rtminput_note step 6: the weighting report (rtmweight report)
    _rtminput_do rtmweight report w0 w1 w1t w2 if `resp' == 1, notes `ro'
    _rtminput_say "Report" `"The weighting report puts the four weights side by side`=cond("$RTMIN_report_by" != "", " and by $RTMIN_report_by", "")'`=cond("$RTMIN_report_files" == "yes", "; the Word method note and the Excel report are in the output folder", "")'. The weight to use for this round's estimates is <b>w2</b>`=cond("$RTMIN_calibrate" == "none", " (equal to w1t: no calibration was asked)", "")'."'
    _rtminput_do save "`outdir'/rtm_weights_round`round'.dta", replace
end
