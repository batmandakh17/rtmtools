*! rtmweight_nonresponse.ado  version 0.5.0  25oct2026  rtmtools
*! Nonresponse and attrition adjustment of survey weights, one round at a time. Five methods,
*! all labeled choices (the default, logit, follows HFPS Vol. 2 p. 10 and the L2T 2017 report):
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
*! method(ebalance): entropy balancing with the base weights as base weights (Hainmueller 2012;
*!   Hainmueller and Xu 2013): the respondents' weights are raked so that their weighted moments
*!   of the covariates (means; with moments(2|3) also variances and skewness through x^2, x^3)
*!   equal the weighted moments of the whole eligible sample. Computed by Stata's svycal rake
*!   (Deville, Sarndal and Sautory 1993), which gives the same weights as ebalance's two-group
*!   form with basewt() and wttreat (verified; ebalance is run as a cross-check when installed).
*!   L2 program practice (L2T 2023-, L2KGZ, L2Arm, L2Geo).
*! method(ebalance_nobase): the L2PHL (January 2026) form: ebalance without base weights, against
*!   the unweighted means of the whole sample, and the resulting factor multiplied into the base
*!   weight afterwards. Program practice, kept as a labeled choice; needs the SSC command ebalance.
*! method(post): cell post-stratification, each round, to population totals of cells(varlist)
*!   read from cellfile() (the L2PHL form since March 2026): factor = cell total / sum of the
*!   respondents' base weights in the cell (UN 2008, section 6.6; HFPS Vol. 2, pp. 10-11).
program define rtmweight_nonresponse, rclass
    version 16
    syntax varname(numeric) [if] [in], WEIGHTvar(varname numeric) GENerate(name) ///
        /* weightvar() is typed as weight(): an option local named weight would clash with marksample */ ///
        [METHod(string) CLASSes(varlist) COVariates(varlist fv) BY(varlist) NGroups(integer 10) ///
         MINcell(integer 0) WEIGHTEDmodel MOMents(integer 1) CELLs(varlist) CELLFile(string) CELLTotal(name) ///
         NOCROSScheck REPLACE NOIsily]
    local resp `varlist'
    marksample touse, novarlist
    markout `touse' `weightvar'

    * ---- method ----
    local method = lower("`method'")
    if "`method'" == "" {
        if "`classes'" != "" & "`covariates'" == "" & "`cells'" == "" local method "classes"
        else if "`covariates'" != "" & "`classes'" == "" & "`cells'" == "" local method "logit"
        else if "`cells'" != "" & "`cellfile'" != "" local method "post"
        else {
            di as err "specify method(): classes with classes(varlist); logit, probit or ebalance with covariates(varlist); ebalance_nobase with covariates(); post with cells(varlist) and cellfile(filename)"
            exit 198
        }
    }
    if !inlist("`method'", "classes", "logit", "probit", "ebalance", "ebalance_nobase", "post") {
        di as err "method() must be classes, logit, probit, ebalance, ebalance_nobase or post"
        exit 198
    }
    if "`method'" == "classes" & "`classes'" == "" {
        di as err "method(classes) requires classes(varlist)"
        exit 198
    }
    if inlist("`method'", "logit", "probit", "ebalance", "ebalance_nobase") & "`covariates'" == "" {
        di as err "method(`method') requires covariates(varlist)"
        exit 198
    }
    if "`method'" == "post" & ("`cells'" == "" | "`cellfile'" == "") {
        di as err "method(post) requires cells(varlist), the cell variables, and cellfile(filename), a Stata file with the same variables and the cell totals"
        exit 198
    }
    if `ngroups' < 2 {
        di as err "ngroups() must be 2 or more"
        exit 198
    }
    if !inlist(`moments', 1, 2, 3) {
        di as err "moments() must be 1 (means), 2 (means and variances) or 3 (and skewness)"
        exit 198
    }
    if "`celltotal'" == "" local celltotal "total"
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
    quietly gen double `fac' = .
    local classvar ""
    local source ""

    * ================= weighting classes =================
    if "`method'" == "classes" {
        capture which survwgt
        if _rc {
            di as err "method(classes) uses the SSC command survwgt, which is not installed; type {stata ssc install survwgt} and run again"
            exit 199
        }
        quietly egen long `grp' = group(`classes') if `touse', missing
        tempvar nr nt
        quietly bysort `grp': egen long `nr' = total(cond(`touse' & `resp' == 1, 1, 0))
        quietly bysort `grp': egen long `nt' = total(cond(`touse', 1, 0))
        quietly count if `touse' & `nr' == 0
        if r(N) > 0 {
            di as err "some weighting classes have no respondent, so their weight cannot be carried; " r(N) " sample households are in such classes"
            di as err "collapse small classes (for example with wgtcellcollapse from the ipfraking package) or use fewer class variables"
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
        quietly replace `fac' = `sclass' / `sresp' if `touse' & `resp' == 1
        local how "weighting classes `classes'"
        local classvar "`classes'"
        local source "UN 2008 section 6.5; HFPS Vol. 2 p. 10"
    }

    * ================= response propensity =================
    else if inlist("`method'", "logit", "probit") {
        tempvar phat
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
        quietly gen long `grp' = .
        foreach b of local blev {
            tempvar q
            quietly xtile `q' = `phat' if `touse' & `bygrp' == `b', nq(`ngroups')
            quietly replace `grp' = (`b' - 1) * `ngroups' + `q' if `touse' & `bygrp' == `b'
            drop `q'
        }
        tempvar pmean
        quietly bysort `grp': egen double `pmean' = mean(cond(`touse', `phat', .))
        quietly replace `fac' = 1 / `pmean' if `touse' & `resp' == 1
        quietly gen double `wadj' = `weightvar' * `fac' if `touse' & `resp' == 1
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
        local classvar "propensity group"
        local source "L2T 2017 pp. 7-11; HFPS Vol. 2 Annex A2.3.1 p. 23; MPPS 2016 Box 2.2"
    }

    * ================= entropy balancing with base weights (= raking to the sample's weighted moments) =================
    else if "`method'" == "ebalance" {
        capture which svycal
        if _rc {
            di as err "method(ebalance) uses svycal rake (Stata 18); in an earlier Stata use method(ebalance_nobase) with the SSC command ebalance, or method(classes)"
            exit 199
        }
        * expand the covariates: i.var -> indicators for every level but the first; others continuous
        _rtmweight_expandcov `covariates' if `touse', moments(`moments')
        local xlist "`r(xlist)'"
        local xlabels `"`r(xlabels)'"'
        local ncont = r(ncont)
        * targets: weighted sums over the whole eligible sample
        quietly summarize `weightvar' if `touse'
        local W = r(sum)
        local totspec "_cons=`W'"
        local j 0
        foreach x of local xlist {
            local ++j
            quietly summarize `x' [aw=`weightvar'] if `touse'
            local T`j' = r(mean) * `W'
            local M`j' = r(mean)
            local totspec "`totspec' `x'=`T`j''"
        }
        tempvar wcal
        capture noisily svycal rake `xlist' [pw=`weightvar'] if `touse' & `resp' == 1, generate(`wcal') totals(`totspec')
        if _rc {
            di as err "the balancing did not converge (svycal rake, Stata error " _rc "): the respondents cannot match every moment; drop a covariate, use moments(1), or collapse categories"
            capture drop _rtmx_x*
            exit 430
        }
        quietly gen double `wadj' = `wcal' if `touse' & `resp' == 1
        quietly replace `wadj' = 0 if `touse' & `resp' == 0
        quietly replace `fac' = `wadj' / `weightvar' if `touse' & `resp' == 1
        * achieved moments
        capture frame drop _rtmx_cf
        frame create _rtmx_cf str64 constraint double(target before after diff rel_diff converged iterations)
        local maxrel 0
        local j 0
        foreach x of local xlist {
            local ++j
            local lab : word `j' of `xlabels'
            quietly summarize `x' [aw=`weightvar'] if `touse' & `resp' == 1
            local before = r(mean)
            quietly summarize `x' [aw=`wadj'] if `touse' & `resp' == 1
            local after = r(mean)
            local rd = cond(`M`j'' != 0, (`after' - `M`j'') / `M`j'', `after' - `M`j'')
            if abs(`rd') > `maxrel' local maxrel = abs(`rd')
            frame post _rtmx_cf ("`lab'") (`M`j'') (`before') (`after') (`after' - `M`j'') (`rd') (1) (.)
        }
        if `maxrel' > 1e-6 {
            di as err "the balancing did not reach the sample moments (largest relative difference " %9.2e `maxrel' "); drop a covariate, use moments(1), or collapse categories"
            capture frame drop _rtmx_cf
            capture drop _rtmx_x*
            exit 430
        }
        di as text _n "Entropy balancing (base weights kept): " as result `j' as text " moment constraints matched; weights raked by svycal"
        di as text %-30s "constraint" %12s "target" %12s "before" %12s "after"
        forvalues i = 1/`j' {
            di as text %-30s "`=_frval(_rtmx_cf, constraint, `i')'" as result %12.4g _frval(_rtmx_cf, target, `i') %12.4g _frval(_rtmx_cf, before, `i') %12.4g _frval(_rtmx_cf, after, `i')
        }
        return scalar max_rel_diff = `maxrel'
        return scalar n_constraints = `j'
        * cross-check with ebalance's two-group form (base weights on both sides)
        if "`nocrosscheck'" == "" {
            capture which ebalance
            if _rc {
                di as txt "(ebalance is not installed, so the cross-check against it was skipped; ssc install ebalance)"
                capture _rtm_export message, text("ebalance not installed: cross-check skipped")
            }
            else {
                tempvar treat webal eb_keep
                quietly gen byte `eb_keep' = `touse'
                preserve
                quietly keep if `eb_keep'
                quietly keep `weightvar' `resp' `xlist' `wadj'
                quietly gen byte `treat' = 1
                tempfile ctrl
                quietly save "`ctrl'"
                quietly keep if `resp' == 1
                quietly replace `treat' = 0
                quietly append using "`ctrl'"
                capture quietly ebalance `treat' `xlist', basewt(`weightvar') wttreat generate(`webal') maxiter(100) tolerance(1e-9)
                if _rc {
                    di as txt "(ebalance could not run the cross-check: Stata error " _rc ")"
                    capture _rtm_export message, text("ebalance cross-check could not run (error `=_rc')")
                    restore
                }
                else {
                    tempvar rdiff
                    quietly gen double `rdiff' = abs(`webal' - `wadj') / `wadj' if `treat' == 0
                    quietly summarize `rdiff'
                    local ebmax = r(max)
                    restore
                    return scalar ebalance_maxreldiff = `ebmax'
                    if `ebmax' < 1e-5 di as text "Cross-check: ebalance (two-group form, base weights on both sides) gives the same weights (largest relative difference " %9.2e `ebmax' ")"
                    else {
                        di as txt "warning: ebalance's weights differ from svycal's by up to " %9.2e `ebmax' " (relative); the svycal weights are kept"
                        capture _rtm_export message, text("ebalance cross-check differs: max relative difference `ebmax'")
                    }
                }
            }
        }
        capture drop _rtmx_x*
        local how "entropy balancing (base weights kept) on `covariates', moments(`moments')"
        local classvar ""
        local source "Hainmueller 2012; Hainmueller and Xu 2013; Deville, Sarndal and Sautory 1993; L2 program practice"
    }

    * ================= entropy balancing without base weights (L2PHL January 2026) =================
    else if "`method'" == "ebalance_nobase" {
        capture which ebalance
        if _rc {
            di as err "method(ebalance_nobase) uses the SSC command ebalance, which is not installed; type {stata ssc install ebalance} and run again"
            exit 199
        }
        tempvar treat webal eb_keep uid
        quietly gen byte `eb_keep' = `touse'
        quietly gen long `uid' = _n
        preserve
        quietly keep if `eb_keep'
        fvrevar `covariates', list
        local covvars "`r(varlist)'"
        quietly keep `uid' `resp' `covvars'
        quietly gen byte `treat' = 1
        tempfile ctrl out
        quietly save "`ctrl'"
        quietly keep if `resp' == 1
        quietly replace `treat' = 0
        quietly append using "`ctrl'"
        capture `noisily' ebalance `treat' `covariates', targets(`moments') generate(`webal') maxiter(100) tolerance(1e-9)
        if _rc {
            di as err "ebalance did not converge (Stata error " _rc "); drop a covariate, use moments(1), or collapse categories"
            restore
            exit 430
        }
        * targets and achieved (unweighted means, as the method defines them)
        capture frame drop _rtmx_cf
        frame create _rtmx_cf str64 constraint double(target before after diff rel_diff converged iterations)
        foreach x of local covvars {
            quietly summarize `x' if `treat' == 1
            local tg = r(mean)
            quietly summarize `x' if `treat' == 0
            local bf = r(mean)
            quietly summarize `x' [aw=`webal'] if `treat' == 0
            local af = r(mean)
            frame post _rtmx_cf ("`x' (unweighted mean)") (`tg') (`bf') (`af') (`af' - `tg') (cond(`tg' != 0, (`af' - `tg') / `tg', `af' - `tg')) (1) (.)
        }
        quietly keep if `treat' == 0
        quietly keep `uid' `webal'
        quietly save "`out'"
        restore
        quietly merge 1:1 `uid' using "`out'", keep(master match) nogenerate
        quietly replace `fac' = `webal' if `touse' & `resp' == 1
        quietly gen double `wadj' = `weightvar' * `fac' if `touse' & `resp' == 1
        quietly replace `wadj' = 0 if `touse' & `resp' == 0
        drop `webal'
        di as text _n "Entropy balancing without base weights (ebalance, targets(`moments')); the factor is multiplied into {bf:`weightvar'} afterwards"
        di as text "The targets are the unweighted sample means; the weighted means after multiplication are not targeted (see the help file)."
        local how "entropy balancing without base weights (ebalance) on `covariates', moments(`moments'), factor x `weightvar'"
        local source "L2PHL script, January 2026 (program practice); Hainmueller and Xu 2013"
    }

    * ================= cell post-stratification to population totals =================
    else {
        capture confirm file "`cellfile'"
        if _rc {
            di as err `"cellfile("`cellfile'") not found"'
            exit 601
        }
        tempvar uid
        quietly gen long `uid' = _n
        tempfile cells_f
        preserve
        quietly use "`cellfile'", clear
        foreach v of local cells {
            capture confirm variable `v'
            if _rc {
                di as err "cellfile() must contain the cell variable {bf:`v'}"
                exit 198
            }
        }
        capture confirm numeric variable `celltotal'
        if _rc {
            di as err "cellfile() must contain the numeric total variable {bf:`celltotal'} (or name it with celltotal())"
            exit 198
        }
        quietly duplicates report `cells'
        if r(unique_value) != r(N) {
            di as err "cellfile() has more than one row for some cells of `cells'; one row per cell is needed"
            exit 459
        }
        quietly count if missing(`celltotal') | `celltotal' <= 0
        if r(N) > 0 {
            di as err "the cell totals must be positive; " r(N) " rows of cellfile() are not"
            exit 459
        }
        quietly keep `cells' `celltotal'
        rename `celltotal' _rtm_celltotal
        quietly save "`cells_f'"
        restore
        tempvar mrg ctot
        quietly merge m:1 `cells' using "`cells_f'", generate(`mrg')
        quietly count if `touse' & `resp' == 1 & `mrg' == 1
        if r(N) > 0 {
            di as err r(N) " respondents are in cells of `cells' that have no total in cellfile(); add those cells or collapse the cells"
            exit 459
        }
        * cells with a total but no respondent: their population is not represented
        tempvar nr
        quietly bysort `cells': egen long `nr' = total(cond(`touse' & `resp' == 1, 1, 0))
        quietly summarize _rtm_celltotal if `mrg' == 2
        local uncovered = cond(r(N) > 0, r(sum), 0)
        local ncells_empty = r(N)
        quietly count if `mrg' == 2
        quietly drop if `mrg' == 2
        if `ncells_empty' > 0 {
            di as txt "note: `ncells_empty' cells of cellfile() have no respondent this round; their population (" %12.0fc `uncovered' ") is not represented by the adjusted weights"
            capture _rtm_export message, text("`ncells_empty' cells have no respondent; population not represented: `uncovered'")
        }
        tempvar sresp
        quietly bysort `cells': egen double `sresp' = total(cond(`touse' & `resp' == 1, `weightvar', 0))
        quietly replace `fac' = _rtm_celltotal / `sresp' if `touse' & `resp' == 1
        quietly gen double `wadj' = `weightvar' * `fac' if `touse' & `resp' == 1
        quietly replace `wadj' = 0 if `touse' & `resp' == 0
        quietly egen long `grp' = group(`cells') if `touse', missing
        quietly gen double `ctot' = _rtm_celltotal
        drop _rtm_celltotal `mrg'
        local how "cell post-stratification to the totals of `cells' in `cellfile'"
        local classvar "`cells'"
        local source "UN 2008 section 6.6; HFPS Vol. 2 pp. 10-11; L2PHL script since March 2026 (program practice)"
        return scalar population_uncovered = `uncovered'
        return scalar n_cells_empty = `ncells_empty'
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

    * by-group table (classes, propensity groups, cells): group, sample n, respondents, response rate, factor
    capture frame drop _rtmx_rc
    frame create _rtmx_rc str64 class_var str80 class double(n_sample n_respondents response_rate factor)
    if "`classvar'" != "" {
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
            * a readable class label: the values of the class variables for this group
            local clab "`g'"
            if "`classvar'" != "propensity group" {
                local clab ""
                foreach v of local classvar {
                    quietly summarize `v' if `touse' & `grp' == `g'
                    local vl : value label `v'
                    local vv = r(min)
                    if "`vl'" != "" local vtxt : label `vl' `vv'
                    else local vtxt "`vv'"
                    local clab "`clab'`=cond("`clab'" == "", "", " | ")'`v'=`vtxt'"
                }
            }
            frame post _rtmx_rc ("`classvar'") (`"`=usubstr(`"`clab'"', 1, 80)'"') (`T'[`i', 1]) (`T'[`i', 2]) (`T'[`i', 3]) (`T'[`i', 4])
        }
        matrix colnames `T' = n_sample n_resp resp_rate factor
        if `G' <= 30 {
            di as text _n "By group: sample size, respondents, response rate, adjustment factor"
            matlist `T', format(%9.3g) names(columns) lines(none)
        }
        else di as text "(" `G' " groups; the table is in r(groups))"
        return matrix groups = `T'
    }

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

    * ---- export tables and settings (schema rtm-export-1.0) ----
    capture _rtm_export wstage, frame(_rtmx_ws) stage("base weight, all sample") var(`weightvar') cond(`touse')
    capture _rtm_export wstage, frame(_rtmx_ws) stage("base weight, respondents") var(`weightvar') cond(`touse' & `resp' == 1)
    capture _rtm_export wstage, frame(_rtmx_ws) stage("adjusted, respondents") var(`generate') cond(`touse' & `resp' == 1)
    capture _rtm_export table, name(weight_stages) frame(_rtmx_ws)
    capture _rtm_export table, name(response_classes) frame(_rtmx_rc)
    capture _rtm_export table, name(calibration_fit) frame(_rtmx_cf)
    capture _rtm_export setting, key(method) value("`method'") source("`source'")
    capture _rtm_export setting, key(response) value("`resp'")
    capture _rtm_export setting, key(weight) value("`weightvar'")
    capture _rtm_export setting, key(generate) value("`generate'")
    if "`covariates'" != "" capture _rtm_export setting, key(covariates) value("`covariates'")
    if "`classes'" != "" capture _rtm_export setting, key(classes) value("`classes'")
    if "`cells'" != "" capture _rtm_export setting, key(cells) value("`cells'")
    if "`cellfile'" != "" capture _rtm_export setting, key(cellfile) value("`cellfile'")
    if inlist("`method'", "logit", "probit") capture _rtm_export setting, key(ngroups) value("`ngroups'") source("deciles: HFPS Vol. 2 p. 23; L2T 2017")
    if inlist("`method'", "ebalance", "ebalance_nobase") capture _rtm_export setting, key(moments) value("`moments'") source("Hainmueller and Xu 2013, targets()")
    if "`by'" != "" capture _rtm_export setting, key(by) value("`by'")
    if "`weightedmodel'" != "" capture _rtm_export setting, key(weightedmodel) value("yes")
end

* expand a covariate list for the balancing: i.var -> indicators for every level but the first
* (the omitted level is implied by the _cons constraint); c.var or bare var -> continuous, with
* powers up to moments(); binary 0/1 variables get no powers. The new variables are named
* _rtmx_x1, _rtmx_x2, ... in the caller's data (the caller drops them). Returns r(xlist),
* r(xlabels) (readable names) and r(ncont).
program define _rtmweight_expandcov, rclass
    version 16
    syntax varlist(fv) [if] [in], MOMents(integer)
    marksample touse, novarlist
    capture drop _rtmx_x*
    local xlist ""
    local xlabels ""
    local ncont 0
    local k 0
    foreach term of local varlist {
        if regexm("`term'", "^i\.(.+)$") {
            local v = regexs(1)
            quietly levelsof `v' if `touse', local(levs)
            local first : word 1 of `levs'
            foreach l of local levs {
                if `l' == `first' continue
                local ++k
                quietly gen byte _rtmx_x`k' = (`v' == `l') if `touse'
                local xlist "`xlist' _rtmx_x`k'"
                local xlabels `"`xlabels' "`v'==`l'""'
            }
        }
        else {
            if regexm("`term'", "^c\.(.+)$") local v = regexs(1)
            else local v "`term'"
            capture confirm numeric variable `v'
            if _rc {
                di as err "covariate {bf:`v'} must be numeric (use i.var for categorical variables)"
                exit 198
            }
            quietly count if `touse' & !inlist(`v', 0, 1)
            local isbinary = (r(N) == 0)
            local ++k
            quietly gen double _rtmx_x`k' = `v' if `touse'
            local xlist "`xlist' _rtmx_x`k'"
            local xlabels `"`xlabels' "`v'""'
            local ++ncont
            if !`isbinary' & `moments' >= 2 {
                local ++k
                quietly gen double _rtmx_x`k' = `v'^2 if `touse'
                local xlist "`xlist' _rtmx_x`k'"
                local xlabels `"`xlabels' "`v'^2""'
                if `moments' == 3 {
                    local ++k
                    quietly gen double _rtmx_x`k' = `v'^3 if `touse'
                    local xlist "`xlist' _rtmx_x`k'"
                    local xlabels `"`xlabels' "`v'^3""'
                }
            }
        }
    }
    return local xlist "`=trim("`xlist'")'"
    return local xlabels `"`=trim(`"`xlabels'"')'"'
    return scalar ncont = `ncont'
end
