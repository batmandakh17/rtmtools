********************************************************************************************
* 04_weights.do  --  weights of one phone-panel round, from the baseline weights
* rtmtools portable do-files, version 0.5.0 (25 October 2026). Plain Stata: no rtmtools command
* is called; the steps use official Stata and the SSC commands named in 00_setup.do.
*
* What it does, step by step (every step is explained above its code and cited):
*   1. base weights of the phone sample from the baseline weights (or from stage probabilities)
*   2. nonresponse or attrition adjustment for this round, by the method chosen below
*   3. trimming of extreme weights (optional)
*   4. calibration to population totals (optional)
*   5. a weighting report, and the export of every step (schema rtm-export-1.0: manifest, CSV
*      tables, Excel display workbook, dashboard index), the same export the rtmtools commands
*      write, so that the two can be compared and the same Excel workbook and dashboard read it.
*
* To adopt it for another program: change only the PARAMETERS block below, following
* ADAPTATION.md. Nothing below the block names a variable or a file of this project.
********************************************************************************************
version 16
clear all
set more off

* ======================= PARAMETERS: change these lines only ===============================
* --- files (paths relative to the folder this do-file is run from, or absolute) ---
local data_baseline  "template/rtm_baseline.dta"   // baseline household file: one row per household
local data_round     "template/rtm_round1.dta"     // this round's file: one row per sampled household, with the response indicator
local totals_file    "template/rtm_totals_long.dta" // population totals for calibration: variables variable, level, total ("" if none)
local cell_file      ""                            // cell totals for method post: the cell variables plus a total ("" if not used)
local export_dir     "rtm_exports"                 // where the runs are written (the dashboard and Excel read it)
local helpers        "_export_helpers.do"          // the export helpers shipped with this package (do not change)
local template_xlsx  "rtm_display.xlsx"            // the Excel display template shipped with this package (do not change)

* --- variables ---
local id             hhid        // household identifier, unique in both files
local strata         stratum     // stratum variable (the by-groups of the subsampling factor and of the report)
local psu            psu         // primary sampling unit (recorded in the export; not used in the weights)
local w_base         w_base      // baseline weight in data_baseline ("" if the file has none: then use the probabilities below)
local prob_vars      ""          // stage inclusion probabilities, e.g. "pi_ea pi_hh" (used only when w_base is "")
local phone          phone       // 1 = household is in the phone sample (has a phone); "" to skip the subsampling step
local responded      responded_r1   // 1 = interviewed this round, 0 = not (in data_round)
local round_vars     "responded_r1" // variables to take from data_round (at least the response indicator)

* --- step 2: nonresponse or attrition adjustment ---
local method         logit       // classes | logit | probit | ebalance | ebalance_nobase | post
local covariates     "urban i.educ head_age assets hhsize"  // covariates of the propensity model or of the balancing
local classes        "region urban"                        // class variables for method classes
local cells          "region urban"                        // cell variables for method post (also in cell_file)
local cell_total     total       // name of the total variable in cell_file
local ngroups        10          // propensity groups (deciles), HFPS Vol. 2 Annex A2.3.1 p. 23
local moments        1           // balancing moments: 1 means, 2 adds variances, 3 adds skewness

* --- step 3: trimming (HFPS Vol. 2 p. 11 winsorises at the 98th percentile; off by default) ---
local trim           none        // none | winsor | cap
local trim_pct       98          // winsorising percentile
local trim_cap       .           // absolute cap for trim cap (a number), or . to use trim_capmult
local trim_capmult   .           // cap as a multiple of the median (UN 2008 section 6.8)

* --- step 4: calibration (HFPS Vol. 2 pp. 10-11; off by default) ---
local calibrate      none        // none | rake | regress | post
local cal_vars       "region urban"   // calibration variables (categorical; totals_file must cover every category)
local cal_ll         .           // lower bound on the weight ratio for regress (truncated linear), or .
local cal_ul         .           // upper bound, or .

* --- names of the new weight variables ---
local w0  w0                     // base weight of the phone sample
local w1  w1                     // after the nonresponse adjustment
local w1t w1t                    // after trimming (equal to w1 when trim is none)
local w2  w2                     // after calibration (equal to w1t when calibrate is none)
local seed 20261025              // random-number seed (only the propensity groups' tie-breaking uses it)
* ===========================================================================================

* ---- 0. The export helpers and the parameter checks ------------------------------------------
* The helpers define the small programs that write the export (rtmx_start, rtmx_wstage,
* rtmx_table, rtmx_setting, rtmx_message, rtmx_done). They are plain Stata and Mata, documented
* in the file itself.
capture confirm file "`helpers'"
if _rc {
    di as err "the export helpers `helpers' were not found; run this do-file from the portable_do_files folder or set the helpers parameter"
    exit 601
}
run "`helpers'"
global RTM_EXPORT ""
global RTM_EXPORT_DIR "`export_dir'"
global RTM_EXPORT_TEMPLATE "`template_xlsx'"
global RTM_EXPORT_SOURCE "dofile"
set seed `seed'
foreach f in data_baseline data_round {
    capture confirm file "``f''"
    if _rc {
        di as err "parameter `f': file ``f'' not found"
        exit 601
    }
}
if !inlist("`method'", "classes", "logit", "probit", "ebalance", "ebalance_nobase", "post") {
    di as err "parameter method must be classes, logit, probit, ebalance, ebalance_nobase or post (it is `method')"
    exit 198
}
if !inlist("`trim'", "none", "winsor", "cap") {
    di as err "parameter trim must be none, winsor or cap"
    exit 198
}
if !inlist("`calibrate'", "none", "rake", "regress", "post") {
    di as err "parameter calibrate must be none, rake, regress or post"
    exit 198
}
if "`calibrate'" != "none" & "`totals_file'" == "" {
    di as err "calibration needs totals_file"
    exit 198
}
if "`method'" == "post" & "`cell_file'" == "" {
    di as err "method post needs cell_file"
    exit 198
}

* ---- 1. Base weights of the phone sample ----------------------------------------------------
* The baseline file carries the baseline weight. The phone sample is a subsample of it (the
* households with a phone, or the ones drawn for the panel): their weights are rescaled within
* each stratum so that they add to the baseline weight total of the stratum (HFPS Vol. 2,
* Himelein et al. 2020, pp. 10-11 and 21; Ambel et al. 2021, p. 10). Without a baseline weight,
* the base weight is 1 / (product of the stage inclusion probabilities) (UN 2008, section 6.3).
use "`data_baseline'", clear
isid `id'
merge 1:1 `id' using "`data_round'", keepusing(`round_vars') keep(master match) nogenerate
rtmx_start, workflow(weights) step(base) cmd("04_weights.do step 1: base weights")
if "`w_base'" != "" {
    confirm numeric variable `w_base'
    assert `w_base' > 0 & !missing(`w_base')
    if "`phone'" != "" {
        confirm numeric variable `phone'
        assert inlist(`phone', 0, 1)
        tempvar sumall sumsel
        bysort `strata': egen double `sumall' = total(`w_base')
        bysort `strata': egen double `sumsel' = total(cond(`phone' == 1, `w_base', 0))
        assert `sumsel' > 0                             // every stratum has phone households
        gen double `w0' = `w_base' * `sumall' / `sumsel' if `phone' == 1
        label variable `w0' "Base weight of the phone sample (baseline weight x subsampling factor, within `strata')"
        rtmx_setting, key(mode) value("baseline weight `w_base' x subsampling factor within `strata'") source("HFPS Vol. 2 pp. 10-11, 21; Ambel et al. 2021 p. 10")
        rtmx_wstage, frame(_rtmx_ws) stage("baseline weight, all sample") var(`w_base')
        keep if `phone' == 1
    }
    else {
        gen double `w0' = `w_base'
        label variable `w0' "Base weight (the baseline weight)"
        rtmx_setting, key(mode) value("baseline weight `w_base'") source("HFPS Vol. 2 pp. 10-11")
    }
}
else {
    if "`prob_vars'" == "" {
        di as err "give w_base or prob_vars"
        exit 198
    }
    gen double `w0' = 1
    foreach p of varlist `prob_vars' {
        assert `p' > 0 & `p' <= 1
        replace `w0' = `w0' / `p'
    }
    label variable `w0' "Base weight: 1 / product of `prob_vars'"
    rtmx_setting, key(mode) value("1 / product of `prob_vars'") source("UN 2008 section 6.3 pp. 122-123")
}
rtmx_wstage, frame(_rtmx_ws) stage("design weight") var(`w0')
rtmx_table, name(weight_stages) frame(_rtmx_ws)
rtmx_setting, key(generate) value("`w0'")
summarize `w0'
rtmx_done

* ---- 2. Nonresponse or attrition adjustment --------------------------------------------------
* The respondents' weights are raised so that they stand for the whole eligible sample, by the
* method chosen in the parameters (the default, a logit response propensity in deciles, is the
* HFPS Vol. 2 p. 10 and L2T 2017 pp. 7-11 recipe; the others are labeled alternatives, see the
* rtmweight help and ADAPTATION.md). Nonrespondents get a weight of 0.
confirm numeric variable `responded'
assert inlist(`responded', 0, 1)
rtmx_start, workflow(weights) step(nonresponse) cmd("04_weights.do step 2: nonresponse adjustment, method `method'")
quietly count
local Nsample = r(N)
quietly count if `responded' == 1
local Nresp = r(N)
quietly summarize `w0'
local sum_base = r(sum)
tempvar fac grp
gen double `fac' = .
capture frame drop _rtmx_rc
frame create _rtmx_rc str64 class_var str80 class double(n_sample n_respondents response_rate factor)
capture frame drop _rtmx_cf
frame create _rtmx_cf str64 constraint double(target before after diff rel_diff converged iterations)
local classvar ""

if "`method'" == "classes" {
    * Weighting classes (UN 2008 section 6.5, pp. 130-132): within each class, the respondents'
    * weights are scaled by (sum of base weights in the class) / (sum over its respondents).
    * survwgt nonresponse (Winter 2002, SSC) does exactly this.
    egen long `grp' = group(`classes'), missing
    tempvar nr
    bysort `grp': egen long `nr' = total(`responded')
    assert `nr' > 0                                  // every class has a respondent
    survwgt nonresponse `w0', by(`grp') respvar(`responded') generate(`w1')
    replace `fac' = `w1' / `w0' if `responded' == 1
    local classvar "`classes'"
    rtmx_setting, key(method) value("classes") source("UN 2008 section 6.5; HFPS Vol. 2 p. 10")
    rtmx_setting, key(classes) value("`classes'")
}
else if inlist("`method'", "logit", "probit") {
    * Response propensity (L2T 2017 pp. 7-11; HFPS Vol. 2 Annex A2.3.1 p. 23; MPPS 2016 Box 2.2):
    * a logit (or probit) of the response indicator on baseline covariates, the predicted
    * propensities cut into ngroups quantile groups, and factor = 1 / (mean propensity of the group).
    `method' `responded' `covariates'
    tempvar phat pmean
    predict double `phat', pr
    assert !missing(`phat')
    xtile `grp' = `phat', nq(`ngroups')
    bysort `grp': egen double `pmean' = mean(`phat')
    replace `fac' = 1 / `pmean' if `responded' == 1
    gen double `w1' = `w0' * `fac' if `responded' == 1
    replace `w1' = 0 if `responded' == 0
    local classvar "propensity group"
    rtmx_setting, key(method) value("`method'") source("L2T 2017 pp. 7-11; HFPS Vol. 2 Annex A2.3.1 p. 23; MPPS 2016 Box 2.2")
    rtmx_setting, key(covariates) value("`covariates'")
    rtmx_setting, key(ngroups) value("`ngroups'") source("deciles: HFPS Vol. 2 p. 23")
}
else if "`method'" == "ebalance" {
    * Entropy balancing with the base weights kept (Hainmueller 2012; L2 program practice): the
    * respondents' base weights are raked (svycal rake, Deville, Sarndal and Sautory 1993) so that
    * their weighted moments of the covariates equal the weighted moments of the whole sample.
    * i.var terms become indicators (all levels but the first; the first is implied by _cons);
    * with moments 2 or 3, x^2 and x^3 of the continuous covariates are added.
    local xlist ""
    local xlabels ""
    local k 0
    foreach term of local covariates {
        if regexm("`term'", "^i\.(.+)$") {
            local v = regexs(1)
            quietly levelsof `v', local(levs)
            local first : word 1 of `levs'
            foreach l of local levs {
                if `l' == `first' continue
                local ++k
                gen byte _x`k' = (`v' == `l')
                local xlist "`xlist' _x`k'"
                local xlabels "`xlabels' `v'==`l'"
            }
        }
        else {
            if regexm("`term'", "^c\.(.+)$") local v = regexs(1)
            else local v "`term'"
            local ++k
            gen double _x`k' = `v'
            local xlist "`xlist' _x`k'"
            local xlabels "`xlabels' `v'"
            quietly count if !inlist(`v', 0, 1)
            if r(N) > 0 & `moments' >= 2 {
                local ++k
                gen double _x`k' = `v'^2
                local xlist "`xlist' _x`k'"
                local xlabels "`xlabels' `v'^2"
                if `moments' == 3 {
                    local ++k
                    gen double _x`k' = `v'^3
                    local xlist "`xlist' _x`k'"
                    local xlabels "`xlabels' `v'^3"
                }
            }
        }
    }
    * targets: the sample's weighted totals (sum of w0, and of w0 x each covariate)
    local totspec "_cons=`sum_base'"
    local j 0
    foreach x of local xlist {
        local ++j
        quietly summarize `x' [aw=`w0']
        local M`j' = r(mean)
        local totspec "`totspec' `x'=`=r(mean) * `sum_base''"
    }
    svycal rake `xlist' [pw=`w0'] if `responded' == 1, generate(`w1') totals(`totspec')
    replace `w1' = 0 if `responded' == 0
    replace `fac' = `w1' / `w0' if `responded' == 1
    local j 0
    foreach x of local xlist {
        local ++j
        local lab : word `j' of `xlabels'
        quietly summarize `x' [aw=`w0'] if `responded' == 1
        local before = r(mean)
        quietly summarize `x' [aw=`w1'] if `responded' == 1
        frame post _rtmx_cf ("`lab'") (`M`j'') (`before') (r(mean)) (r(mean) - `M`j'') (cond(`M`j'' != 0, (r(mean) - `M`j'') / `M`j'', r(mean) - `M`j'')) (1) (.)
        assert abs(r(mean) - `M`j'') <= 1e-6 * max(1, abs(`M`j''))   // the moments are matched
    }
    drop _x*
    rtmx_setting, key(method) value("ebalance") source("Hainmueller 2012; Hainmueller and Xu 2013; Deville, Sarndal and Sautory 1993; L2 program practice")
    rtmx_setting, key(covariates) value("`covariates'")
    rtmx_setting, key(moments) value("`moments'")
}
else if "`method'" == "ebalance_nobase" {
    * The L2PHL January 2026 form (program practice): ebalance without base weights, against the
    * unweighted means of the whole sample (treated = every sample household, control = the
    * respondents), and the resulting factor multiplied into the base weight afterwards.
    capture which ebalance
    if _rc {
        di as err "method ebalance_nobase needs the SSC command ebalance: ssc install ebalance"
        exit 199
    }
    tempvar treat webal uid
    gen long `uid' = _n
    preserve
    fvrevar `covariates', list
    keep `uid' `responded' `r(varlist)'
    gen byte `treat' = 1
    tempfile all out
    save "`all'"
    keep if `responded' == 1
    replace `treat' = 0
    append using "`all'"
    ebalance `treat' `covariates', targets(`moments') generate(`webal') maxiter(100) tolerance(1e-9)
    foreach x in `r(varlist)' {
        quietly summarize `x' if `treat' == 1
        local tg = r(mean)
        quietly summarize `x' if `treat' == 0
        local bf = r(mean)
        quietly summarize `x' [aw=`webal'] if `treat' == 0
        frame post _rtmx_cf ("`x' (unweighted mean)") (`tg') (`bf') (r(mean)) (r(mean) - `tg') (cond(`tg' != 0, (r(mean) - `tg') / `tg', r(mean) - `tg')) (1) (.)
    }
    keep if `treat' == 0
    keep `uid' `webal'
    save "`out'"
    restore
    merge 1:1 `uid' using "`out'", keep(master match) nogenerate
    replace `fac' = `webal' if `responded' == 1
    gen double `w1' = `w0' * `fac' if `responded' == 1
    replace `w1' = 0 if `responded' == 0
    rtmx_setting, key(method) value("ebalance_nobase") source("L2PHL script, January 2026 (program practice); Hainmueller and Xu 2013")
    rtmx_setting, key(covariates) value("`covariates'")
    rtmx_setting, key(moments) value("`moments'")
}
else {
    * Cell post-stratification to population totals (UN 2008 section 6.6; the L2PHL form since
    * March 2026): factor = cell total / sum of the respondents' base weights in the cell.
    preserve
    use "`cell_file'", clear
    keep `cells' `cell_total'
    rename `cell_total' _celltotal
    isid `cells'
    tempfile cf
    save "`cf'"
    restore
    merge m:1 `cells' using "`cf'", keep(master match) generate(_m)
    assert _m == 3 if `responded' == 1                 // every respondent's cell has a total
    drop _m
    tempvar sresp
    bysort `cells': egen double `sresp' = total(cond(`responded' == 1, `w0', 0))
    replace `fac' = _celltotal / `sresp' if `responded' == 1
    gen double `w1' = `w0' * `fac' if `responded' == 1
    replace `w1' = 0 if `responded' == 0
    egen long `grp' = group(`cells'), missing
    drop _celltotal
    local classvar "`cells'"
    rtmx_setting, key(method) value("post") source("UN 2008 section 6.6; HFPS Vol. 2 pp. 10-11; L2PHL script since March 2026 (program practice)")
    rtmx_setting, key(cells) value("`cells'")
    rtmx_setting, key(cellfile) value("`cell_file'")
}
label variable `w1' "Weight after the nonresponse adjustment (`method')"
* the by-group table of the export: sample, respondents, response rate, factor
if "`classvar'" != "" {
    quietly levelsof `grp', local(glev)
    foreach g of local glev {
        quietly count if `grp' == `g'
        local ns = r(N)
        quietly count if `grp' == `g' & `responded' == 1
        local nr = r(N)
        quietly summarize `fac' if `grp' == `g' & `responded' == 1
        frame post _rtmx_rc ("`classvar'") ("`g'") (`ns') (`nr') (`nr' / `ns') (r(mean))
    }
}
quietly summarize `w1' if `responded' == 1
di as text "Nonresponse adjustment (`method'): " `Nsample' " eligible, " `Nresp' " respondents; sum of weights " %12.1f `sum_base' " -> " %12.1f r(sum)
rtmx_wstage, frame(_rtmx_ws) stage("base weight, all sample") var(`w0')
rtmx_wstage, frame(_rtmx_ws) stage("base weight, respondents") var(`w0') cond(`responded' == 1)
rtmx_wstage, frame(_rtmx_ws) stage("adjusted, respondents") var(`w1') cond(`responded' == 1)
rtmx_table, name(weight_stages) frame(_rtmx_ws)
rtmx_table, name(response_classes) frame(_rtmx_rc)
rtmx_table, name(calibration_fit) frame(_rtmx_cf)
rtmx_setting, key(response) value("`responded'")
rtmx_setting, key(weight) value("`w0'")
rtmx_setting, key(generate) value("`w1'")
summarize `fac' if `responded' == 1, detail
rtmx_done

* ---- 3. Trimming ------------------------------------------------------------------------------
* winsor: weights above the trim_pct percentile are set to that percentile (HFPS Vol. 2 p. 11 uses
* the 98th); cap: weights above a bound (trim_cap, or trim_capmult x the median, UN 2008 section
* 6.8) are set to it. The trimmed weights are then rescaled to the original total (UN 2008 p. 137).
if "`trim'" == "none" {
    gen double `w1t' = `w1'
    label variable `w1t' "Weight after trimming (none applied)"
}
else {
    rtmx_start, workflow(weights) step(trim) cmd("04_weights.do step 3: trimming, `trim'")
    tempvar hi
    if "`trim'" == "winsor" {
        _pctile `w1' if `responded' == 1, percentiles(`trim_pct')
        gen double `hi' = r(r1)
        rtmx_setting, key(rule) value("winsor") source("HFPS Vol. 2 p. 11; Ambel et al. 2021 p. 11")
        rtmx_setting, key(pct) value("`trim_pct'")
    }
    else {
        if `trim_cap' < . gen double `hi' = `trim_cap'
        else {
            quietly summarize `w1' if `responded' == 1, detail
            gen double `hi' = `trim_capmult' * r(p50)
        }
        rtmx_setting, key(rule) value("cap") source("UN 2008 section 6.8 pp. 136-138")
    }
    gen double `w1t' = min(`w1', `hi') if `responded' == 1
    quietly count if `responded' == 1 & `w1' > `hi'
    local ntrim = r(N)
    quietly summarize `w1' if `responded' == 1
    local s0 = r(sum)
    quietly summarize `w1t' if `responded' == 1
    replace `w1t' = `w1t' * `s0' / r(sum) if `responded' == 1    // rescale to the original total
    replace `w1t' = 0 if `responded' == 0
    label variable `w1t' "Weight after trimming (`trim'), rescaled to the original total"
    di as text "Trimming: " `ntrim' " weights lowered"
    rtmx_wstage, frame(_rtmx_ws) stage("before trimming") var(`w1') cond(`responded' == 1)
    rtmx_wstage, frame(_rtmx_ws) stage("after trimming") var(`w1t') cond(`responded' == 1) ntrimmed(`ntrim')
    rtmx_table, name(weight_stages) frame(_rtmx_ws)
    rtmx_setting, key(weight) value("`w1'")
    rtmx_setting, key(generate) value("`w1t'")
    quietly count if `responded' == 1
    rtmx_done
}

* ---- 4. Calibration ---------------------------------------------------------------------------
* The respondents' weights are adjusted so that they add to the population totals of the
* calibration variables: raking (multiplicative distance) or linear (GREG) calibration, through
* svycal (Deville and Sarndal 1992; Deville, Sarndal and Sautory 1993; HFPS Vol. 2 pp. 10-11);
* post-stratification is raking on one variable. The totals file has one row per category.
if "`calibrate'" == "none" {
    gen double `w2' = `w1t'
    label variable `w2' "Final weight (no calibration applied)"
}
else {
    rtmx_start, workflow(weights) step(calibrate) cmd("04_weights.do step 4: calibration, `calibrate' on `cal_vars'")
    preserve
    use "`totals_file'", clear
    confirm variable variable level total
    quietly count
    local nrow = r(N)
    local pairs ""
    local Npop .
    forvalues i = 1/`nrow' {
        local v = variable[`i']
        if !`: list v in cal_vars' continue
        local pairs "`pairs' `=level[`i']'.`v'=`=total[`i']'"
    }
    restore
    local fvlist ""
    foreach v of local cal_vars {
        local fvlist "`fvlist' i.`v'"
        quietly levelsof `v' if `responded' == 1, local(levs)
        local Nv 0
        foreach tok of local pairs {
            if regexm("`tok'", "^([0-9]+)\.`v'=([0-9.eE+-]+)$") {
                local Nv = `Nv' + real(regexs(2))
                assert `: list posof "`=regexs(1)'" in levs' > 0   // a total for a category absent from the sample cannot be reached
            }
        }
        if `Npop' == . local Npop = `Nv'
        else assert abs(`Nv' - `Npop') <= 0.005 * `Npop'     // the totals agree across variables
    }
    local sub = cond("`calibrate'" == "regress", "regress", "rake")
    local bopts ""
    if "`sub'" == "regress" {
        if `cal_ll' < . local bopts "`bopts' ll(`cal_ll')"
        if `cal_ul' < . local bopts "`bopts' ul(`cal_ul')"
    }
    svycal `sub' `fvlist' [pw=`w1t'] if `responded' == 1, generate(`w2') totals(_cons=`Npop' `pairs') `bopts'
    replace `w2' = 0 if `responded' == 0
    label variable `w2' "Calibrated weight (`calibrate' on `cal_vars')"
    * achieved against target totals
    capture frame drop _rtmx_cf
    frame create _rtmx_cf str64 constraint double(target before after diff rel_diff converged iterations)
    local maxrel 0
    foreach tok of local pairs {
        if !regexm("`tok'", "^([0-9]+)\.([A-Za-z_][A-Za-z0-9_]*)=([0-9.eE+-]+)$") continue
        local lev = regexs(1)
        local var = regexs(2)
        local val = real(regexs(3))
        quietly summarize `w1t' if `responded' == 1 & `var' == `lev'
        local bef = r(sum)
        quietly summarize `w2' if `responded' == 1 & `var' == `lev'
        local rd = (r(sum) - `val') / `val'
        if abs(`rd') > `maxrel' local maxrel = abs(`rd')
        frame post _rtmx_cf ("`var'==`lev'") (`val') (`bef') (r(sum)) (r(sum) - `val') (`rd') (1) (.)
    }
    di as text "Calibration: largest relative difference to the targets " %9.2e `maxrel'
    if "`sub'" == "rake" assert `maxrel' < 1e-6
    rtmx_wstage, frame(_rtmx_ws) stage("before calibration") var(`w1t') cond(`responded' == 1)
    rtmx_wstage, frame(_rtmx_ws) stage("after calibration") var(`w2') cond(`responded' == 1)
    rtmx_table, name(weight_stages) frame(_rtmx_ws)
    rtmx_table, name(calibration_fit) frame(_rtmx_cf)
    rtmx_setting, key(method) value("`calibrate'") source("HFPS Vol. 2 pp. 10-11 and Annex A2; Deville and Sarndal 1992")
    rtmx_setting, key(calibration_variables) value("`cal_vars'")
    rtmx_setting, key(totalsfile) value("`totals_file'")
    if "`bopts'" != "" rtmx_setting, key(bounds) value("`bopts'") source("no cited default; Deville, Sarndal and Sautory 1993")
    quietly count if `responded' == 1
    rtmx_done
}

* ---- 5. Report and the final export -----------------------------------------------------------
* Every stage side by side (UN 2008 ch. 5: keep each weight stage), by stratum.
rtmx_start, workflow(weights) step(report) cmd("04_weights.do step 5: report of `w0' `w1' `w1t' `w2'")
di as text _n "Weight stages (respondents): N, sum, min, median, max, CV, Kish 1+CV2"
foreach w in `w0' `w1' `w1t' `w2' {
    quietly summarize `w' if `responded' == 1 & `w' > 0, detail
    local cv = r(sd) / r(mean)
    di as text %-8s "`w'" as result %8.0f r(N) %14.1f r(sum) %10.3f r(min) %10.3f r(p50) %10.3f r(max) %8.3f `cv' %8.3f 1 + `cv'^2
    rtmx_wstage, frame(_rtmx_ws) stage("`w'") var(`w') cond(`responded' == 1)
}
rtmx_table, name(weight_stages) frame(_rtmx_ws)
capture frame drop _rtmx_wg
frame create _rtmx_wg str32 stage str32 variable str32 group_var str80 group double(n sum mean cv)
quietly levelsof `strata', local(slev)
foreach w in `w0' `w2' {
    foreach l of local slev {
        quietly summarize `w' if `responded' == 1 & `w' > 0 & `strata' == `l'
        if r(N) > 0 frame post _rtmx_wg ("`w'") ("`w'") ("`strata'") ("`l'") (r(N)) (r(sum)) (r(mean)) (r(sd) / r(mean))
    }
}
rtmx_table, name(weight_groups) frame(_rtmx_wg)
rtmx_setting, key(weights) value("`w0' `w1' `w1t' `w2'")
rtmx_setting, key(by) value("`strata'")
quietly count if `responded' == 1
rtmx_done
di as text _n "Done. The weights `w0' `w1' `w1t' `w2' are in memory; the runs are in `export_dir' (dashboard: rtm_exports.js; Excel: rtm_display.xlsx in each run folder)."
