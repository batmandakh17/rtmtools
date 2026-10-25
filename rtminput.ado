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
    syntax [using/] [, CHECK SAMPling WEIGHTS ROUND(integer 0) OUTdir(string) TEMPlate REPLACE NOFiles]
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
        _rtminput_export_check, using("`using'") n_errors(`n_errors') n_warnings(`n_warnings') present("`present'")
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
    file open _rtmin_fh using "`logfile'", write text replace
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
    foreach f in design strata frame totals cells prefixes files checks {
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
    return local keys "project seed output_dir target p relmargin margin change power deff nonresponse_mult attrition rounds firstloss domains minsize maxsize n_areas allocation power_q min_areas max_areas stage1 sort_vars reserve_areas households_per_area phone_per_psu rdd base_weight nonresponse covariates classes cells ngroups moments trim trim_pct trim_cap trim_capmult calibrate cal_vars cal_ll cal_ul report_by report_files"
    return local numeric "seed p relmargin margin change power deff nonresponse_mult attrition rounds firstloss domains minsize maxsize n_areas power_q min_areas max_areas households_per_area phone_per_psu ngroups moments trim_pct trim_cap trim_capmult cal_ll cal_ul"
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
    `macval(0)'
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
    capture confirm variable frame_ok
    local okif = cond(_rc, "", "if frame_ok == 1")
    _rtminput_note step 3: allocation of $RTMIN_n_areas areas across strata ($RTMIN_allocation)
    local ao ""
    if "$RTMIN_allocation" == "power" & "$RTMIN_power_q" != "" local ao "power($RTMIN_power_q)"
    if "$RTMIN_min_areas" != "0" local ao "`ao' min($RTMIN_min_areas)"
    if "$RTMIN_max_areas" != "0" local ao "`ao' max($RTMIN_max_areas)"
    _rtminput_do rtmsample allocate `okif', strata(stratum_id) n($RTMIN_n_areas) size(size_hh) method($RTMIN_allocation) `ao' generate(n_area)
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
    _rtminput_do save "`outdir'/rtm_sample_areas.dta", replace
    * ---- 5. second stage ----
    if "$RTMIN_households_per_area" != "" {
        if "$RTMIN_F_hl" != "" {
            _rtminput_note step 5: second stage, $RTMIN_households_per_area households per selected area from the household list
            _rtminput_asdta, path("$RTMIN_F_hl") outdir("`outdir'") name(household_list)
            local hl "`r(dta)'"
            local ha "$RTMIN_F_hl_area_id"
            _rtminput_do keep if area_sel == 1
            _rtminput_do keep area_id stratum_id area_pi area_w
            if "`ha'" != "area_id" _rtminput_do rename area_id `ha'
            _rtminput_do merge 1:m `ha' using "`hl'", keep(match) nogenerate
            _rtminput_do rtmsample draw, n($RTMIN_households_per_area) strata(`ha') `seed' id($RTMIN_F_hl_id) generate(hh)
            _rtminput_do keep if hh_sel == 1
            _rtminput_do rtmweight base, probability(area_pi hh_pi) generate(w_design)
            _rtminput_do save "`outdir'/rtm_sample_households.dta", replace
        }
        else {
            _rtminput_note step 5: second stage from the completed listing (rtmlist import), $RTMIN_households_per_area households per area
            _rtminput_do keep if area_sel == 1
            _rtminput_do keep area_id stratum_id size_hh area_pi area_w
            _rtminput_do save "`outdir'/rtm_sample_areas_selected.dta", replace
            local la "$RTMIN_F_ls_area_id"
            local lo = cond("`la'" != "" & "`la'" != "area_id", "areavar(`la')", "")
            _rtminput_do rtmlist import using "$RTMIN_F_ls", id(area_id) expected(size_hh) `lo' clear
            _rtminput_do merge m:1 area_id using "`outdir'/rtm_sample_areas_selected.dta", keep(match) keepusing(area_pi stratum_id) nogenerate
            _rtminput_do rtmsample draw, n($RTMIN_households_per_area) strata(area_id) `seed' generate(hh)
            _rtminput_do keep if hh_sel == 1
            _rtminput_do rtmweight base, probability(area_pi segment_prob hh_pi) generate(w_design)
            _rtminput_do save "`outdir'/rtm_sample_households.dta", replace
        }
    }
    * ---- 6. phone subsample of the baseline ----
    if "$RTMIN_phone_per_psu" != "" {
        _rtminput_note step 6: phone subsample, $RTMIN_phone_per_psu households per PSU of the baseline, every other household an ordered replacement
        _rtminput_asdta, path("$RTMIN_F_bl") outdir("`outdir'") name(baseline)
        _rtminput_do use "`r(dta)'", clear
        local io = cond("$RTMIN_F_bl_id" != "", "id($RTMIN_F_bl_id)", "")
        _rtminput_do rtmsample draw, n($RTMIN_phone_per_psu) strata($RTMIN_F_bl_psu) reserve(all) `seed' `io' generate(ph)
        if "$RTMIN_F_bl_weight" != "" {
            local bo = cond("$RTMIN_F_bl_strata" != "", "by($RTMIN_F_bl_strata)", "")
            _rtminput_do rtmweight base, baseweight($RTMIN_F_bl_weight) subsample(ph_sel) `bo' generate(w_phone)
        }
        _rtminput_do save "`outdir'/rtm_sample_phone.dta", replace
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
        _rtminput_note step 7: random digit dialing numbers from the Prefixes sheet (kept in rtm_rdd_numbers.dta; never exported)
        _rtminput_do rtmsample rdd, prefixes(`pl') n(`nl') digits(`dg') `seed' saving("`outdir'/rtm_rdd_numbers.dta") replace
    }
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
    if "`phone'" != "" _rtminput_do keep if `phone' == 1
    * ---- nonresponse ----
    local m "$RTMIN_nonresponse"
    if "`m'" == "none" {
        _rtminput_note step 3: no nonresponse adjustment (Design: nonresponse none)
        _rtminput_do generate double w1 = w0
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
    }
    * ---- trimming ----
    if "$RTMIN_trim" == "none" {
        _rtminput_note step 4: no trimming (Design: trim none)
        _rtminput_do generate double w1t = w1
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
    }
    * ---- calibration ----
    if "$RTMIN_calibrate" == "none" {
        _rtminput_note step 5: no calibration (Design: calibrate none)
        _rtminput_do generate double w2 = w1t
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
    }
    * ---- report and save ----
    local ro = cond("$RTMIN_report_by" != "", "by($RTMIN_report_by)", "")
    if "$RTMIN_report_files" == "yes" local ro `"`ro' docx("`outdir'/rtm_weights_round`round'.docx") excel("`outdir'/rtm_weights_round`round'.xlsx")"'
    _rtminput_note step 6: the weighting report (rtmweight report)
    _rtminput_do rtmweight report w0 w1 w1t w2 if `resp' == 1, notes `ro'
    _rtminput_do save "`outdir'/rtm_weights_round`round'.dta", replace
end
