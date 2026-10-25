*! rtmest.ado  version 0.1.0  24oct2026  rtmtools
*! Design-based estimates with the weights produced by rtmweight: declares the design with
*! svyset (strata, PSU, FPC, and the calibration through rake() or regress() so that the
*! variance accounts for it), then estimates means, proportions, totals or a ratio by domain
*! with svy, and reports estimate, SE, CI, design effects (deff, deft) and the coefficient of
*! variation, with a flag where the CV exceeds cvflag().
*! Method: [SVY] svyset, svy, estat effects, estat cv (Taylor linearization by default);
*! guidance on strata, PSU and singleton strata in UN 2008 ch. 7 (pp. 152-168) and Grosh and
*! Munoz 1996 (pp. 71, 166). Calibration in the variance: svyset rake()/regress() (Stata 15.1+).
program define rtmest, rclass
    version 16
    * wrapper: logs the run for the live dashboard (rtmtools_dashboard), then hands over
    capture _rtm_export start, workflow(estimation) step(estimate) cmd(`"rtmest `0'"')
    capture noisily rtmest_main `0'
    local rc = _rc
    tempname hold
    _return hold `hold'
    _return restore `hold', hold
    capture _rtm_export done, rc(`rc')
    _return restore `hold'
    if `rc' exit `rc'
    return add
end

program define rtmest_main, rclass
    version 16
    syntax varlist(numeric) [if] [in], WEIGHTvar(varname numeric) ///
        [STRata(varname) PSU(varname) FPC(varname) SINGLEunit(string) VCE(string) OVER(varname) ///
         STAT(string) RATIO(varlist numeric min=2 max=2) CVflag(real 30) LEVEL(cilevel) ///
         CALibration(string) NOCALibration SUBPOP(varname numeric) EXcel(string) NOSVYset]
    marksample touse, novarlist
    markout `touse' `weightvar'
    local stat = cond("`stat'" == "", "mean", lower("`stat'"))
    if !inlist("`stat'", "mean", "prop", "proportion", "total", "ratio") {
        di as err "stat() must be mean, proportion, total or ratio"
        exit 198
    }
    if "`stat'" == "prop" local stat "proportion"
    if "`stat'" == "ratio" & "`ratio'" == "" {
        di as err "stat(ratio) needs ratio(numerator denominator)"
        exit 198
    }
    local singleunit = cond("`singleunit'" == "", "missing", lower("`singleunit'"))
    if !inlist("`singleunit'", "missing", "certainty", "scaled", "centered") {
        di as err "singleunit() must be missing, certainty, scaled or centered (see help svyset)"
        exit 198
    }
    local vce = cond("`vce'" == "", "linearized", lower("`vce'"))
    if !inlist("`vce'", "linearized", "bootstrap", "brr", "jackknife", "sdr") {
        di as err "vce() must be linearized, bootstrap, brr, jackknife or sdr"
        exit 198
    }
    quietly count if `touse' & `weightvar' <= 0
    if r(N) > 0 {
        di as err "weight {bf:`weightvar'} is zero or negative in " r(N) " observations of the sample; estimate on the respondents (use if) or check the weights"
        exit 459
    }
    if "`psu'" == "" & "`strata'" != "" di as txt "note: no psu(): observations are treated as the sampling units within strata"
    if "`psu'" == "" & "`strata'" == "" di as txt "note: no strata() or psu(): the sample is treated as unstratified, with observations as the sampling units; give the design variables for correct standard errors"

    * ---- calibration recorded by rtmweight calibrate (svycal engine) ----
    local calspec ""
    if "`calibration'" != "" local calspec "`calibration'"
    else if "`nocalibration'" == "" {
        local c : char _dta[rtm_cal_svyset]
        if `"`c'"' != "" {
            local cg : char _dta[rtm_cal_generate]
            local ci : char _dta[rtm_cal_input]
            if "`cg'" == "" | "`weightvar'" == "`cg'" | "`weightvar'" == "`ci'" {
                local calspec `"`c'"'
                di as txt "note: the calibration recorded by rtmweight calibrate is declared in svyset (`calspec'); use nocalibration to treat the weights as fixed"
            }
            else {
                di as txt "note: a calibration is recorded for {bf:`cg'} (computed from `ci'), but weightvar(`weightvar') is a different weight, so it is not declared and the weights are treated as fixed. Use calibration() to declare one."
            }
        }
    }

    * ---- svyset ----
    local dopts ""
    if "`strata'" != "" local dopts "`dopts' strata(`strata')"
    if "`fpc'" != "" local dopts "`dopts' fpc(`fpc')"
    local psuv = cond("`psu'" == "", "_n", "`psu'")
    local setcmd `"svyset `psuv' [pw=`weightvar'], `dopts' singleunit(`singleunit') vce(`vce') `calspec'"'
    if "`nosvyset'" == "" {
        capture noisily `setcmd'
        if _rc {
            di as err "svyset failed; check strata(), psu(), fpc() and the recorded calibration (char _dta[rtm_cal_svyset])"
            exit _rc
        }
    }
    * singleton strata
    local nsingle 0
    if "`strata'" != "" {
        tempvar npsu
        if "`psu'" != "" {
            tempvar tag
            quietly egen byte `tag' = tag(`strata' `psu') if `touse'
            quietly bysort `strata': egen long `npsu' = total(cond(`touse', `tag', 0))
        }
        else quietly bysort `strata': egen long `npsu' = total(cond(`touse', 1, 0))
        quietly count if `touse' & `npsu' == 1
        local nsingle = r(N)
        if `nsingle' > 0 {
            quietly tab `strata' if `touse' & `npsu' == 1
            di as txt "note: " r(r) " stratum(a) with a single sampling unit in the sample; singleunit(`singleunit') applies" ///
                cond("`singleunit'" == "missing", " and their standard errors will be missing; consider singleunit(centered) (UN 2008, p. 157)", "")
            return scalar n_singleton_strata = r(r)
        }
        else return scalar n_singleton_strata = 0
    }

    * ---- estimation ----
    local subopt = cond("`subpop'" != "", "subpop(`subpop')", "")
    local overopt = cond("`over'" != "", "over(`over')", "")
    tempname R
    local rows ""
    local nrow 0
    if "`stat'" == "ratio" {
        local what "ratio of `: word 1 of `ratio'' to `: word 2 of `ratio''"
        local cmd `"svy, `subopt': ratio (`: word 1 of `ratio''/`: word 2 of `ratio'') if `touse', `overopt' level(`level')"'
        capture noisily `cmd'
        if _rc exit _rc
        _rtmest_collect `R' "ratio" "`over'"
    }
    else {
        foreach y of local varlist {
            local cmd `"svy, `subopt': `stat' `y' if `touse', `overopt' level(`level')"'
            capture noisily quietly `cmd'
            if _rc {
                di as err "svy: `stat' `y' failed (Stata error " _rc ")"
                exit _rc
            }
            _rtmest_collect `R' "`y'" "`over'"
        }
    }

    * ---- table ----
    di as text _n "Design-based estimates (`stat'), weight `weightvar'" cond("`strata'" != "", ", strata `strata'", "") cond("`psu'" != "", ", PSU `psu'", "") cond("`fpc'" != "", ", fpc `fpc'", "") ", vce(`vce')"
    if "`calspec'" != "" di as text "Calibration in the variance: `calspec'"
    di as text "{hline 108}"
    di as text %-24s "outcome" %-12s "domain" %10s "estimate" %10s "SE" %10s "CI low" %10s "CI high" %8s "deff" %8s "CV%" %5s "flag"
    di as text "{hline 108}"
    local nr = rowsof(`R')
    local rn : rownames `R'
    forvalues i = 1/`nr' {
        local lab : word `i' of `rn'
        local p = strpos("`lab'", "__")
        local outc = cond(`p' > 0, substr("`lab'", 1, `p' - 1), "`lab'")
        local dom = cond(`p' > 0, substr("`lab'", `p' + 2, .), "all")
        local cvp = 100 * `R'[`i', 6]
        local flag = cond(`cvp' >= `cvflag', "*", "")
        di as text %-24s abbrev("`outc'", 24) %-12s abbrev("`dom'", 12) as result %10.4g `R'[`i', 1] %10.4g `R'[`i', 2] %10.4g `R'[`i', 3] %10.4g `R'[`i', 4] %8.3f `R'[`i', 5] %8.1f `cvp' as err %5s "`flag'"
    }
    di as text "{hline 108}"
    di as text "deff: design effect (estat effects); CV%: 100 x SE / estimate (estat cv); * marks a CV of `cvflag'% or more."
    if "`singleunit'" == "missing" & "`strata'" != "" & `nsingle' > 0 di as txt "Missing SEs come from singleton strata; see singleunit()."

    * ---- Excel ----
    if "`excel'" != "" {
        quietly putexcel set "`excel'", replace
        quietly putexcel A1 = "rtmtools estimates (`stat'), weight `weightvar', `c(current_date)'"
        quietly putexcel A2 = `"`setcmd'"'
        quietly putexcel A4 = matrix(`R'), names
        di as text `"Excel table written: {browse "`excel'"}"'
    }
    return matrix table = `R'
    return local svyset `"`setcmd'"'
    return local stat "`stat'"
    return local cmdline `"rtmest `0'"'
    _rtm_util record, step(est) cmd(`"rtmest `0'"')
end

* collect estimate, se, ci, deff, cv from the last svy results into matrix R (appending rows)
program define _rtmest_collect
    version 16
    args R outc over
    tempname b T E C
    matrix `T' = r(table)
    local cn : colnames `T'
    local k : word count `cn'
    quietly estat effects
    matrix `E' = r(deff)
    quietly estat cv
    matrix `C' = r(cv)
    tempname row
    forvalues j = 1/`k' {
        local c : word `j' of `cn'
        * r(table) column names look like c.y, 1.y, c.y@0bn.g, 1.y@2.g, or num:den for ratios
        local left "`c'"
        local right ""
        if strpos("`c'", "@") {
            local left = substr("`c'", 1, strpos("`c'", "@") - 1)
            local right = substr("`c'", strpos("`c'", "@") + 1, .)
        }
        _rtmest_term "`left'"
        local o "`r(term)'"
        if "`o'" == "" | "`outc'" == "ratio" local o "`outc'"
        if "`right'" != "" {
            _rtmest_term "`right'"
            local dom "`r(term)'"
        }
        else local dom "all"
        local lab = subinstr(subinstr("`o'__`dom'", "=", "_", .), ":", "_", .)
        local lab = subinstr(subinstr(`"`lab'"', ".", "_", .), "/", "_", .)
        matrix `row' = (`T'[1, `j'], `T'[2, `j'], `T'[5, `j'], `T'[6, `j'], `E'[1, `j'], `C'[1, `j'] / 100)
        matrix rownames `row' = `lab'
        capture matrix `R' = `R' \ `row'
        if _rc matrix `R' = `row'
    }
    matrix colnames `R' = estimate se ci_low ci_high deff cv
end

* turn a factor-style term (c.y, 1.y, 0bn.g) into y or y=1
program define _rtmest_term, rclass
    version 16
    args t
    if regexm("`t'", "^c\.(.+)$") {
        local v = regexs(1)
        return local term "`v'"
        exit
    }
    if regexm("`t'", "^([0-9]+)b?n?o?\.(.+)$") {
        local l = regexs(1)
        local v = regexs(2)
        return local term "`v'=`l'"
        exit
    }
    return local term "`t'"
end
