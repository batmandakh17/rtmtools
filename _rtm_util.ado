*! _rtm_util.ado  version 0.2.0  24oct2026  rtmtools
*! Shared helpers: version stamp, dataset notes and characteristics, weight summaries,
*! new-variable checks. Called by the rtmweight, rtmest and rtmtools_setup programs.

program define _rtm_util
    version 16
    gettoken sub 0 : 0, parse(" ,")
    _rtm_util_`sub' `0'
end

* ---- version string of the package ---------------------------------------------------------
program define _rtm_util_version, rclass
    version 16
    return local pkgversion "0.2.0"
    return local stamp "rtmtools 0.2.0, Stata `c(stata_version)' (`c(flavor)'), `c(current_date)' `c(current_time)'"
end

* ---- record a step in the dataset: a characteristic and a note -----------------------------
* syntax: _rtm_util record, step(name) cmd(string)
program define _rtm_util_record
    version 16
    syntax, STEP(string) CMD(string) [VAR(name)]
    _rtm_util_version
    local stamp "`r(stamp)'"
    char _dta[rtm_`step'] `"`cmd'"'
    char _dta[rtm_`step'_stamp] "`stamp'"
    note _dta: `cmd' (`stamp')
    * the weight variable carries its own record, so that a report on several weights can list the command behind each
    if "`var'" != "" {
        char `var'[rtm_step] "`step'"
        char `var'[rtm_cmd] `"`cmd'"'
        char `var'[rtm_stamp] "`stamp'"
    }
end

* ---- summary statistics of a weight variable ----------------------------------------------
* syntax: _rtm_util wsum varname [if] [in]  -> r(N) r(sum) r(mean) r(min) r(max) r(p50) r(cv) r(kish)
* Kish's design effect from unequal weights is 1 + CV^2 (UN 2008, Designing Household Survey
* Samples, section 6.8; Kish 1992).
program define _rtm_util_wsum, rclass
    version 16
    syntax varname(numeric) [if] [in]
    marksample touse
    quietly count if `touse' & `varlist' < 0
    local nneg = r(N)
    quietly summarize `varlist' if `touse' & `varlist' > 0, detail
    local N = r(N)
    if `N' == 0 {
        return scalar N = 0
        return scalar nneg = `nneg'
        exit
    }
    return scalar N = r(N)
    return scalar sum = r(sum)
    return scalar mean = r(mean)
    return scalar min = r(min)
    return scalar max = r(max)
    return scalar p50 = r(p50)
    return scalar p5 = r(p5)
    return scalar p95 = r(p95)
    local cv = r(sd) / r(mean)
    return scalar cv = `cv'
    return scalar kish = 1 + `cv'^2
    return scalar nneg = `nneg'
end

* ---- display a one-line weight summary -----------------------------------------------------
* syntax: _rtm_util wline varname [if] [in], label(string)
program define _rtm_util_wline
    version 16
    syntax varname(numeric) [if] [in], LABel(string)
    _rtm_util_wsum `varlist' `if' `in'
    if r(N) == 0 {
        di as text %-28s "`label'" as text "  no positive weights"
        exit
    }
    di as text %-28s "`label'" as result %8.0fc r(N) %14.1fc r(sum) %10.3f r(min) %10.3f r(p50) %10.3f r(max) %8.3f r(cv) %8.3f r(kish)
end

program define _rtm_util_whead
    version 16
    di as text "{hline 100}"
    di as text %-28s "Weight" %8s "N" %14s "Sum" %10s "Min" %10s "Median" %10s "Max" %8s "CV" %8s "1+CV2"
    di as text "{hline 100}"
end

* ---- check that a new variable can be created ----------------------------------------------
* syntax: _rtm_util newvar name [, replace]
program define _rtm_util_newvar
    version 16
    syntax name [, REPLACE]
    capture confirm new variable `namelist'
    if _rc {
        if "`replace'" == "" {
            di as err "variable {bf:`namelist'} already exists; use a new name in generate() or add the replace option"
            exit 110
        }
        drop `namelist'
    }
end

* ---- confirm a 0/1 variable without missing values in the sample ----------------------------
program define _rtm_util_binary
    version 16
    syntax varname(numeric) [if] [in], WHAT(string)
    marksample touse, novarlist
    quietly count if `touse' & missing(`varlist')
    if r(N) > 0 {
        di as err "`what' {bf:`varlist'} is missing in " r(N) " observations of the sample; code every sample member 0 or 1, or exclude the others with if or in"
        exit 416
    }
    quietly count if `touse' & !inlist(`varlist', 0, 1)
    if r(N) > 0 {
        di as err "`what' {bf:`varlist'} must be 0 or 1; " r(N) " observations have other values"
        exit 450
    }
end
