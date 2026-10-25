*! rtmweight_calibrate.ado  version 0.5.0  25oct2026  rtmtools
*! Calibration of survey weights to population totals.
*!
*! engine(stata), the default: official svycal (Stata 18; Deville and Sarndal 1992; Deville,
*!   Sarndal and Sautory 1993). method(rake) is raking-ratio (multiplicative) calibration to the
*!   margins of the calibration variables; method(regress) is linear (GREG) calibration, with
*!   ll()/ul() giving truncated linear calibration; method(post) is post-stratification to the
*!   cells of one variable (raking on a single variable). The population total N (the _cons
*!   total) is taken from the totals and must agree across calibration variables.
*! engine(ipfraking): raking through ipfraking (Kolenikov 2014, 2019), with its trimming of the
*!   adjustment factors as approximate bounds; totals() must then be ipfraking's control-total
*!   matrices (see the help file).
*! No R: the bounded logit distance is available in Stata through sreweight (Pacifico 2014, SSC),
*!   run by hand; trimming that preserves the calibration constraints is not offered.
*! Method sources: HFPS Vol. 2 (Himelein et al. 2020) pp. 10-11 and Annex A2; Ambel et al. 2021
*!   pp. 7, 10-11; UN 2008 section 6.6. No foundational document gives bounds, so bounds are off
*!   unless the user sets them.
program define rtmweight_calibrate, rclass
    version 16
    syntax varlist(numeric fv) [if] [in] [pw], GENerate(name) ///
        [TOTals(string) TOTALSFile(string) METHod(string) LL(real -1) UL(real -1) ITERate(integer 1000) ///
         TOLerance(real 1e-7) FORCE ENGine(string) REPLACE]

    * ---- options ----
    if "`exp'" == "" {
        di as err "a weight is required: [pw=weightvar]"
        exit 198
    }
    local wvar = subinstr("`exp'", "=", "", 1)
    local wvar = trim("`wvar'")
    capture confirm numeric variable `wvar'
    if _rc {
        di as err "the weight must be a single numeric variable, as in [pw=w1]"
        exit 198
    }
    local method = cond("`method'" == "", "rake", lower("`method'"))
    if !inlist("`method'", "rake", "regress", "post") {
        di as err "method() must be rake, regress or post"
        exit 198
    }
    local engine = cond("`engine'" == "", "stata", lower("`engine'"))
    if !inlist("`engine'", "stata", "ipfraking") {
        di as err "engine() must be stata (svycal) or ipfraking"
        exit 198
    }
    if "`totals'" == "" & "`totalsfile'" == "" {
        di as err "population totals are required: totals(1.region=14781 2.region=15345 ...), totals(matrixname) or totalsfile(filename)"
        exit 198
    }
    if "`totals'" != "" & "`totalsfile'" != "" {
        di as err "specify totals() or totalsfile(), not both"
        exit 198
    }
    _rtm_util newvar `generate', `replace'
    marksample touse
    quietly count if `touse' & `wvar' <= 0
    if r(N) > 0 {
        di as err "weight {bf:`wvar'} is not positive in " r(N) " sample observations; calibrate the respondents only (use if)"
        exit 459
    }

    * ---- calibration variables: i.var terms or bare categorical names ----
    local calvars ""
    local contvars ""
    foreach term of local varlist {
        * (regexs() must be read on a separate line: Stata expands `=regexs(1)' before running the if)
        if regexm("`term'", "^i\.(.+)$") {
            local v = regexs(1)
            local calvars "`calvars' `v'"
        }
        else if regexm("`term'", "^c\.(.+)$") {
            local v = regexs(1)
            local contvars "`contvars' `v'"
        }
        else if regexm("`term'", "[#]") {
            di as err "interaction terms are not supported; build one combined variable with egen group() and use it"
            exit 198
        }
        else local calvars "`calvars' `term'"
    }
    local calvars = trim("`calvars'")
    local contvars = trim("`contvars'")
    if "`contvars'" != "" & "`method'" != "regress" {
        di as err "continuous calibration variables (c.var) need method(regress)"
        exit 198
    }
    if "`method'" == "post" & wordcount("`calvars'") != 1 {
        di as err "method(post) takes exactly one categorical variable (the post-strata)"
        exit 198
    }
    foreach v of local calvars {
        capture confirm numeric variable `v'
        if _rc {
            di as err "calibration variable {bf:`v'} must be numeric with integer categories"
            exit 198
        }
        quietly count if `touse' & (missing(`v') | `v' != int(`v') | `v' < 0)
        if r(N) > 0 {
            di as err "calibration variable {bf:`v'} has missing, negative or non-integer values in " r(N) " sample observations"
            exit 459
        }
    }

    * ---- totals: build the long table (variable, level, total) unless a matrix or ipfraking matrices were given ----
    tempname TOT
    local ismatrix 0
    local pairs ""
    if "`totalsfile'" != "" {
        preserve
        quietly use "`totalsfile'", clear
        capture confirm variable variable level total
        if _rc {
            di as err "totalsfile() must have the variables {bf:variable} (name), {bf:level} (category) and {bf:total}"
            exit 198
        }
        quietly count
        forvalues i = 1/`r(N)' {
            local pairs "`pairs' `=level[`i']'.`=variable[`i']'=`=total[`i']'"
        }
        restore
    }
    else {
        capture confirm matrix `totals'
        if !_rc & wordcount("`totals'") == 1 local ismatrix 1
        else local pairs "`totals'"
    }
    local ipfmats ""
    if "`engine'" == "ipfraking" & `ismatrix' == 0 & !regexm("`pairs'", "=") {
        * totals name ipfraking control matrices: pass through
        foreach m of local pairs {
            capture confirm matrix `m'
            if _rc {
                di as err "engine(ipfraking) needs totals as level.variable=number pairs, a totalsfile(), or control-total matrices in ipfraking's format; {bf:`m'} is none of these"
                exit 198
            }
        }
        local ipfmats "`pairs'"
        local pairs ""
    }
    if `ismatrix' == 0 & "`pairs'" != "" {
        * parse pairs k.var=value into the long table and check them
        local pairs = trim("`pairs'")
        local nrow = wordcount("`pairs'")
        matrix `TOT' = J(`nrow', 2, .)
        local rownames ""
        local i 0
        foreach tok of local pairs {
            local ++i
            if !regexm("`tok'", "^([0-9]+)\.([A-Za-z_][A-Za-z0-9_]*)=([0-9.eE+-]+)$") {
                di as err `"cannot read the total "`tok'"; write totals as level.variable=number with no spaces around = and no thousands separators, for example 2.region=15345"'
                exit 198
            }
            local lev = regexs(1)
            local var = regexs(2)
            local val = regexs(3)
            local TOTvar`i' "`var'"
            local TOTlev`i' = `lev'
            local TOTval`i' = `val'
            if !`: list var in calvars' {
                di as err "total given for {bf:`var'}, which is not among the calibration variables (`calvars')"
                exit 198
            }
        }
        * every calibration variable: totals for every sample level, and no sample level without a total
        local Nref .
        foreach v of local calvars {
            quietly levelsof `v' if `touse', local(levs)
            local Nv 0
            local nlev 0
            forvalues j = 1/`nrow' {
                if "`TOTvar`j''" == "`v'" {
                    local Nv = `Nv' + `TOTval`j''
                    local ++nlev
                    if !`: list TOTlev`j' in levs' {
                        di as err "a total is given for `v' == `TOTlev`j'' but no sample observation has that value; the total cannot be reached"
                        exit 459
                    }
                }
            }
            if `nlev' == 0 {
                di as err "no totals given for calibration variable {bf:`v'}"
                exit 198
            }
            foreach l of local levs {
                local found 0
                forvalues j = 1/`nrow' {
                    if "`TOTvar`j''" == "`v'" & `TOTlev`j'' == `l' local found 1
                }
                if !`found' {
                    di as err "no population total for `v' == `l', which occurs in the sample; give a total for every category"
                    exit 198
                }
            }
            if `Nref' == . local Nref = `Nv'
            else if abs(`Nv' - `Nref') > 0.005 * `Nref' {
                di as err "population totals disagree across calibration variables: the categories of `v' add to " %14.1fc `Nv' " but the first variable's add to " %14.1fc `Nref'
                di as err "use totals from the same population and year for every variable"
                exit 459
            }
        }
        local Npop = `Nref'
        return scalar N_pop = `Npop'
    }

    * ---- weight summary before ----
    _rtm_util wsum `wvar' if `touse'
    local kish0 = r(kish)
    local sum0 = r(sum)

    local conv 1
    * ================= engine: stata (svycal) =================
    if "`engine'" == "stata" {
        capture which svycal
        if _rc {
            di as err "svycal is not available in this Stata (it is part of Stata 18); use engine(ipfraking) for raking"
            exit 199
        }
        if "`method'" == "rake" & (`ll' > 0 | `ul' > 0) {
            di as err "svycal rake has no bounds; use method(regress) with ll()/ul() (truncated linear), engine(ipfraking) (approximate bounds through trimming), or sreweight (SSC) for the bounded logit distance"
            exit 198
        }
        local fvlist ""
        foreach v of local calvars {
            local fvlist "`fvlist' i.`v'"
        }
        foreach v of local contvars {
            local fvlist "`fvlist' c.`v'"
        }
        if `ismatrix' local totspec "`totals'"
        else local totspec "_cons=`Npop' `pairs'"
        local sub = cond("`method'" == "regress", "regress", "rake")
        local bopts ""
        if "`sub'" == "regress" {
            if `ll' > 0 local bopts "`bopts' ll(`ll')"
            if `ul' > 0 local bopts "`bopts' ul(`ul')"
            local bopts "`bopts' iterate(`iterate') tolerance(`tolerance') `force'"
        }
        capture noisily svycal `sub' `fvlist' [pw=`wvar'] if `touse', generate(`generate') totals(`totspec') `bopts'
        if _rc {
            di as err "svycal `sub' failed (Stata error " _rc "); check that the totals cover every category and that the bounds are not too tight"
            exit _rc
        }
        local how "svycal `sub' on `fvlist', totals `totspec'`bopts'"
        char _dta[rtm_cal_svyset] "`sub'(`fvlist', totals(`totspec'))"
        char _dta[rtm_cal_generate] "`generate'"
        char _dta[rtm_cal_input] "`wvar'"
    }

    * ================= engine: ipfraking =================
    else if "`engine'" == "ipfraking" {
        capture which ipfraking
        if _rc {
            di as err "ipfraking is not installed; type {stata ssc install ipfraking}"
            exit 199
        }
        if "`method'" != "rake" {
            di as err "engine(ipfraking) performs raking; use method(rake)"
            exit 198
        }
        local topts ""
        if `ul' > 0 local topts "`topts' trimhirel(`ul')"
        if `ll' > 0 local topts "`topts' trimlorel(`ll')"
        * control-total matrices in ipfraking's format: one row vector per variable, column names
        * the categories, column equation the total variable (_one), row name the variable
        local madeone 0
        if "`ipfmats'" == "" {
            capture confirm variable _one
            if _rc {
                quietly gen byte _one = 1
                local madeone 1
            }
            foreach v of local calvars {
                tempname M_`v'
                local vals ""
                local cols ""
                local eqs ""
                forvalues j = 1/`nrow' {
                    if "`TOTvar`j''" == "`v'" {
                        local vals "`vals' `TOTval`j''"
                        local cols "`cols' `TOTlev`j''"
                        local eqs "`eqs' _one"
                    }
                }
                matrix `M_`v'' = (`=subinstr(trim("`vals'"), " ", ", ", .)')
                matrix colnames `M_`v'' = `cols'
                matrix coleq `M_`v'' = `eqs'
                matrix rownames `M_`v'' = `v'
                local ipfmats "`ipfmats' `M_`v''"
            }
        }
        capture quietly ipfraking [pw=`wvar'] if `touse', ctotal(`ipfmats') generate(`generate') iterate(`iterate') tolerance(`tolerance') `topts' nograph
        local rc = _rc
        local conv = r(converged)
        local badc = r(badcontrols)
        if `madeone' drop _one
        if `rc' {
            di as err "ipfraking failed (Stata error " `rc' "); run it directly to see its log: ipfraking [pw=`wvar'], ctotal(...) generate(...)"
            exit `rc'
        }
        return scalar converged = `conv'
        di as text "ipfraking: converged = " as result `conv' as text "; controls met: " as result cond(`badc' == 0, "yes", "no")
        local how "ipfraking on `calvars'`topts'"
        if `ll' > 0 | `ul' > 0 local how "`how' (trimming of the adjustment factors as approximate bounds)"
    }

    local lbl `"Calibrated weight: `how'"'
    local lbl = usubstr(`"`lbl'"', 1, 80)
    label variable `generate' `"`lbl'"'
    char _dta[rtm_cal_vars] "`calvars'"
    char _dta[rtm_cal_pairs] "`pairs'"

    local conv_x = cond("`engine'" == "ipfraking", `conv', 1)
    * ---- diagnostics in Stata: achieved against target totals, g-weights ----
    _rtm_util wsum `generate' if `touse'
    local kish1 = r(kish)
    local sum1 = r(sum)
    di as text _n "Calibrated weights ({bf:`generate'}): `how'"
    _rtm_util whead
    _rtm_util wline `wvar' if `touse', label("before calibration")
    _rtm_util wline `generate' if `touse', label("after calibration")
    di as text "{hline 100}"
    tempvar g
    quietly gen double `g' = `generate' / `wvar' if `touse'
    quietly summarize `g' if `touse', detail
    di as text "Adjustment (g-weights = calibrated / input): min " as result %7.4f r(min) as text ", median " as result %7.4f r(p50) as text ", max " as result %7.4f r(max)
    return scalar g_min = r(min)
    return scalar g_max = r(max)
    return scalar g_p50 = r(p50)
    if `ismatrix' == 0 {
        di as text _n "Target against achieved totals:"
        di as text %-12s "variable" %6s "level" %14s "target" %14s "achieved" %10s "rel.diff"
        local maxrel 0
        capture frame drop _rtmx_cf
        frame create _rtmx_cf str64 constraint double(target before after diff rel_diff converged iterations)
        forvalues j = 1/`nrow' {
            quietly summarize `wvar' if `touse' & `TOTvar`j'' == `TOTlev`j''
            local bef = r(sum)
            quietly summarize `generate' if `touse' & `TOTvar`j'' == `TOTlev`j''
            local ach = r(sum)
            local rd = (`ach' - `TOTval`j'') / `TOTval`j''
            if abs(`rd') > `maxrel' local maxrel = abs(`rd')
            di as text %-12s "`TOTvar`j''" as result %6.0f `TOTlev`j'' %14.1fc `TOTval`j'' %14.1fc `ach' %10.5f `rd'
            frame post _rtmx_cf ("`TOTvar`j''==`TOTlev`j''") (`TOTval`j'') (`bef') (`ach') (`ach' - `TOTval`j'') (`rd') (`conv_x') (.)
        }
        di as text "Largest relative difference: " as result %8.6f `maxrel'
        return scalar max_rel_diff = `maxrel'
        if `maxrel' > 1e-4 {
            if "`force'" == "" {
                di as err "the calibration did not reach the population totals (largest relative difference " %8.6f `maxrel' ")."
                di as err "Widen or drop the bounds, drop a calibration variable or collapse categories, or add {bf:force} to keep these weights anyway; {bf:`generate'} was not created."
                drop `generate'
                exit 430
            }
            di as txt "note: the totals are not matched exactly (bounds, trimming or a non-converged adjustment); kept because force was specified"
        }
    }
    di as text "Kish's 1+CV2 from " as result %6.3f `kish0' as text " to " as result %6.3f `kish1' ///
        as text "; sum of weights from " as result %14.1fc `sum0' as text " to " as result %14.1fc `sum1'
    return scalar kish_before = `kish0'
    return scalar kish_after = `kish1'
    return scalar sum_before = `sum0'
    return scalar sum_after = `sum1'
    return local method "`method'"
    return local engine "`engine'"
    return local calvars "`calvars'"
    return local generate "`generate'"
    local cmd `"rtmweight calibrate `0'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(calibrate) cmd(`"`cmd'"') var(`generate')

    * ---- export tables and settings (schema rtm-export-1.0) ----
    capture _rtm_export wstage, frame(_rtmx_ws) stage("before calibration") var(`wvar') cond(`touse')
    capture _rtm_export wstage, frame(_rtmx_ws) stage("after calibration") var(`generate') cond(`touse')
    capture _rtm_export table, name(weight_stages) frame(_rtmx_ws)
    capture _rtm_export table, name(calibration_fit) frame(_rtmx_cf)
    capture _rtm_export setting, key(method) value("`method'") source("HFPS Vol. 2 pp. 10-11 and Annex A2; Deville and Sarndal 1992")
    capture _rtm_export setting, key(engine) value("`engine'")
    capture _rtm_export setting, key(calibration_variables) value("`calvars' `contvars'")
    capture _rtm_export setting, key(weight) value("`wvar'")
    capture _rtm_export setting, key(generate) value("`generate'")
    if `ll' > 0 | `ul' > 0 capture _rtm_export setting, key(bounds) value("ll `ll' ul `ul'") source("no cited default; Deville, Sarndal and Sautory 1993")
    if "`totalsfile'" != "" capture _rtm_export setting, key(totalsfile) value("`totalsfile'")
end
