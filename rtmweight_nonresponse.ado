*! rtmweight_nonresponse.ado  version 0.1.0  24oct2026  rtmtools
*! Nonresponse and attrition adjustment of survey weights, one round at a time.
*!
*! method(classes): weighting-class adjustment through survwgt nonresponse (Winter 2002):
*!   within each class the respondents' weights are scaled so that they add to the base
*!   weights of all eligible sample members in the class; nonrespondents get 0
*!   (UN 2008, section 6.5, pp. 130-132; HFPS Vol. 2, Himelein et al. 2020, p. 10).
*! method(logit|probit): response-propensity adjustment: a logit or probit of the response
*!   indicator on the covariates, the predicted propensity grouped into ngroups() quantile
*!   groups, and each respondent's weight multiplied by 1 / (mean propensity of its group)
*!   (L2T 2017, Broccolini, Seitz and Azevedo, pp. 7-11; HFPS Vol. 2, Annex A2.3.1, p. 23;
*!   Dabalen et al. 2016, Box 2.2, p. 49). The model is unweighted unless weightedmodel is given.
program define rtmweight_nonresponse, rclass
    version 16
    syntax varname(numeric) [if] [in], WEIGHTvar(varname numeric) GENerate(name) ///
        /* weightvar() is typed as weight(): an option local named weight would clash with marksample */ ///
        [METHod(string) CLASSes(varlist) COVariates(varlist fv) BY(varlist) NGroups(integer 10) ///
         MINcell(integer 0) WEIGHTEDmodel REPLACE NOIsily]
    local resp `varlist'
    marksample touse, novarlist
    markout `touse' `weightvar'

    * ---- method ----
    local method = lower("`method'")
    if "`method'" == "" {
        if "`classes'" != "" & "`covariates'" == "" local method "classes"
        else if "`covariates'" != "" & "`classes'" == "" local method "logit"
        else {
            di as err "specify method(classes) with classes(varlist), or method(logit) or method(probit) with covariates(varlist)"
            exit 198
        }
    }
    if !inlist("`method'", "classes", "logit", "probit") {
        di as err "method() must be classes, logit or probit"
        exit 198
    }
    if "`method'" == "classes" & "`classes'" == "" {
        di as err "method(classes) requires classes(varlist)"
        exit 198
    }
    if inlist("`method'", "logit", "probit") & "`covariates'" == "" {
        di as err "method(`method') requires covariates(varlist)"
        exit 198
    }
    if `ngroups' < 2 {
        di as err "ngroups() must be 2 or more"
        exit 198
    }
    _rtm_util newvar `generate', `replace'
    _rtm_util binary `resp' if `touse', what("response indicator")
    quietly count if `touse' & `weightvar' <= 0
    if r(N) > 0 {
        di as err "weight {bf:`weightvar'} is not positive in " r(N) " sample observations"
        exit 459
    }
    quietly count if `touse'
    local Nsample = r(N)
    quietly count if `touse' & `resp' == 1
    local Nresp = r(N)
    if `Nresp' == 0 {
        di as err "no respondents in the sample (`resp' == 1 nowhere)"
        exit 2000
    }
    if `Nresp' == `Nsample' {
        di as txt "note: every sample member responded; the adjusted weights equal the base weights"
    }
    quietly summarize `weightvar' if `touse'
    local sum_base = r(sum)
    quietly summarize `weightvar' if `touse' & `resp' == 1
    local sum_resp_base = r(sum)
    local rr_w = `sum_resp_base' / `sum_base'
    local rr_u = `Nresp' / `Nsample'

    tempvar wadj grp fac

    * ================= weighting classes =================
    if "`method'" == "classes" {
        capture which survwgt
        if _rc {
            di as err "method(classes) uses the SSC command survwgt, which is not installed; type {stata ssc install survwgt} and run again"
            exit 199
        }
        quietly egen long `grp' = group(`classes') if `touse', missing
        quietly count if `touse' & missing(`grp')
        * respondents per class
        tempvar nr nt
        quietly bysort `grp': egen long `nr' = total(cond(`touse' & `resp' == 1, 1, 0))
        quietly bysort `grp': egen long `nt' = total(cond(`touse', 1, 0))
        quietly count if `touse' & `nr' == 0
        if r(N) > 0 {
            di as err "some weighting classes have no respondent, so their weight cannot be carried; " r(N) " sample households are in such classes"
            di as err "collapse small classes (for example with wgtcellcollapse from the ipfraking package) or use fewer class variables"
            quietly levelsof `grp' if `touse' & `nr' == 0, local(bad)
            exit 459
        }
        if `mincell' > 0 {
            quietly count if `touse' & `nr' < `mincell' & `resp' == 1
            if r(N) > 0 {
                quietly tab `grp' if `touse' & `nr' < `mincell'
                di as err "classes with fewer than `mincell' respondents: " r(r) "; collapse them before adjusting (see the help file) or lower mincell()"
                exit 459
            }
        }
        * survwgt nonresponse: within each class, respondents' weights are scaled to the class total
        tempvar wtmp
        quietly gen double `wtmp' = `weightvar' if `touse'
        quietly survwgt nonresponse `wtmp' if `touse', by(`grp') respvar(`resp') generate(`wadj')
        quietly replace `wadj' = . if !`touse'
        * self-check against the direct formula (sum of base weights in class / sum over respondents)
        tempvar chk sclass sresp
        quietly bysort `grp': egen double `sclass' = total(cond(`touse', `weightvar', 0))
        quietly bysort `grp': egen double `sresp' = total(cond(`touse' & `resp' == 1, `weightvar', 0))
        quietly gen double `chk' = `weightvar' * `sclass' / `sresp' if `touse' & `resp' == 1
        quietly count if `touse' & `resp' == 1 & abs(`chk' - `wadj') > 1e-6 * `chk'
        if r(N) > 0 {
            di as err "internal check failed: survwgt's adjusted weights differ from the class formula in " r(N) " observations"
            exit 498
        }
        quietly gen double `fac' = `sclass' / `sresp' if `touse' & `resp' == 1
        local how "weighting classes `classes'"
    }

    * ================= response propensity =================
    else {
        tempvar phat
        quietly gen double `wadj' = .
        quietly gen double `phat' = .
        if "`by'" == "" {
            tempvar one
            quietly gen byte `one' = 1 if `touse'
            local byv "`one'"
        }
        else local byv "`by'"
        tempvar bygrp
        quietly egen long `bygrp' = group(`byv') if `touse', missing
        quietly levelsof `bygrp' if `touse', local(blev)
        local nb : word count `blev'
        local converged_all 1
        local pr2list ""
        foreach b of local blev {
            if "`weightedmodel'" != "" local wopt "[pw=`weightvar']"
            else local wopt ""
            capture `noisily' `method' `resp' `covariates' `wopt' if `touse' & `bygrp' == `b'
            if _rc {
                di as err "the `method' model did not fit in by-group `b' (Stata error " _rc "); check the covariates for collinearity or empty categories"
                exit _rc
            }
            if e(converged) == 0 local converged_all 0
            local pr2list "`pr2list' `=round(e(r2_p), 0.001)'"
            quietly predict double `phat'_b if e(sample), pr
            quietly replace `phat' = `phat'_b if `touse' & `bygrp' == `b'
            drop `phat'_b
        }
        quietly count if `touse' & missing(`phat')
        if r(N) > 0 {
            di as err r(N) " sample observations have no predicted propensity (missing covariates); fill or exclude them"
            exit 416
        }
        * propensity groups (quantiles of the predicted propensity) within by-groups
        quietly gen long `grp' = .
        foreach b of local blev {
            tempvar q
            quietly xtile `q' = `phat' if `touse' & `bygrp' == `b', nq(`ngroups')
            quietly replace `grp' = (`b' - 1) * `ngroups' + `q' if `touse' & `bygrp' == `b'
            drop `q'
        }
        tempvar pmean nr
        quietly bysort `grp': egen double `pmean' = mean(cond(`touse', `phat', .))
        quietly bysort `grp': egen long `nr' = total(cond(`touse' & `resp' == 1, 1, 0))
        quietly count if `touse' & `resp' == 1 & `nr' == 0
        quietly gen double `fac' = 1 / `pmean' if `touse' & `resp' == 1
        quietly replace `wadj' = `weightvar' * `fac' if `touse' & `resp' == 1
        quietly replace `wadj' = 0 if `touse' & `resp' == 0
        local how "`method' response propensity on `covariates', `ngroups' groups"
        if "`by'" != "" local how "`how', fitted within `by'"
        if "`weightedmodel'" != "" local how "`how', weighted model"
        return scalar converged = `converged_all'
        return local pseudo_r2 "`=trim("`pr2list'")'"
        if `converged_all' == 0 di as txt "warning: at least one `method' model did not converge"
        if "`noisily'" == "" & `nb' == 1 {
            di as text _n "Response propensity model (`method'): N = " as result e(N) as text ", pseudo R2 = " as result %6.3f e(r2_p)
        }
    }

    quietly gen double `generate' = `wadj'
    local lbl `"Weight after nonresponse adjustment (`how')"'
    local lbl = usubstr(`"`lbl'"', 1, 80)
    label variable `generate' `"`lbl'"'

    * ---- diagnostics ----
    quietly summarize `generate' if `touse' & `resp' == 1
    local sum_adj = r(sum)
    di as text _n "Nonresponse adjustment ({bf:`generate'}): `how'"
    di as text "Sample: " as result %8.0fc `Nsample' as text " eligible; respondents " as result %8.0fc `Nresp' ///
        as text "; response rate " as result %5.1f 100*`rr_u' "%" as text " unweighted, " as result %5.1f 100*`rr_w' "%" as text " weighted"
    _rtm_util whead
    _rtm_util wline `weightvar' if `touse', label("base weight, all sample")
    _rtm_util wline `weightvar' if `touse' & `resp' == 1, label("base weight, respondents")
    _rtm_util wline `generate' if `touse' & `resp' == 1, label("adjusted, respondents")
    di as text "{hline 100}"
    di as text "Sum of weights: base (all) " as result %14.1fc `sum_base' as text "; adjusted (respondents) " as result %14.1fc `sum_adj' ///
        as text "; ratio " as result %6.4f `sum_adj' / `sum_base'
    quietly summarize `fac' if `touse' & `resp' == 1, detail
    di as text "Adjustment factor: min " as result %6.3f r(min) as text ", median " as result %6.3f r(p50) as text ", max " as result %6.3f r(max)
    return scalar factor_min = r(min)
    return scalar factor_max = r(max)
    return scalar factor_p50 = r(p50)
    if r(min) < 1 - 1e-9 di as txt "note: some adjustment factors are below 1 (groups whose respondents are over-represented)"

    * by-group table: group, sample n, respondents, response rate, factor
    tempname T
    quietly levelsof `grp' if `touse', local(glev)
    local G : word count `glev'
    matrix `T' = J(`G', 4, .)
    local i 0
    foreach g of local glev {
        local ++i
        quietly count if `touse' & `grp' == `g'
        matrix `T'[`i', 1] = r(N)
        quietly count if `touse' & `grp' == `g' & `resp' == 1
        matrix `T'[`i', 2] = r(N)
        matrix `T'[`i', 3] = `T'[`i', 2] / `T'[`i', 1]
        quietly summarize `fac' if `touse' & `grp' == `g' & `resp' == 1
        matrix `T'[`i', 4] = r(mean)
    }
    matrix colnames `T' = n_sample n_resp resp_rate factor
    if `G' <= 30 {
        di as text _n "By group: sample size, respondents, response rate, adjustment factor"
        matlist `T', format(%9.3g) names(columns) lines(none)
    }
    else di as text "(" `G' " groups; the table is in r(groups))"
    return matrix groups = `T'

    _rtm_util wsum `generate' if `touse' & `resp' == 1
    return scalar N_sample = `Nsample'
    return scalar N_resp = `Nresp'
    return scalar rr_unweighted = `rr_u'
    return scalar rr_weighted = `rr_w'
    return scalar sum_base = `sum_base'
    return scalar sum_adj = `sum_adj'
    return scalar kish = r(kish)
    return scalar cv = r(cv)
    return local method "`method'"
    return local generate "`generate'"
    local cmd `"rtmweight nonresponse `0'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(nonresponse) cmd(`"`cmd'"') var(`generate')
end
