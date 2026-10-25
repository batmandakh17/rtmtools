*! rtmweight_base.ado  version 0.5.0  25oct2026  rtmtools
*! Design (base) weights: from stage selection probabilities, or from a baseline weight
*! and a phone-subsampling indicator, with an optional multiplicity adjustment.
*!
*! Method: base weight = 1 / (product of the stage inclusion probabilities)
*!   (UN 2008, Designing Household Survey Samples, section 6.3, pp. 122-123 of the PDF).
*! Subsample factor: within each by() group, sum of the baseline weights over all baseline
*!   households divided by the sum over the subsampled households, so that the weights of the
*!   phone subsample add to the baseline weight total of the group (HFPS Vol. 2, Himelein et al.
*!   2020, pp. 10-11, 21; Ambel et al. 2021, p. 10).
*! Multiplicity: weight divided by the number of phone numbers through which the household
*!   could be selected (HFPS Vol. 2, p. 11).
program define rtmweight_base, rclass
    version 16
    syntax [if] [in], GENerate(name) [PROBability(varlist numeric) BASEweight(varname numeric) ///
        SUBsample(varname numeric) BY(varlist) MULTiplicity(varname numeric) REPLACE]

    * ---- which mode ----
    if "`probability'" != "" & "`baseweight'" != "" {
        di as err "specify either probability() or baseweight(), not both"
        exit 198
    }
    if "`probability'" == "" & "`baseweight'" == "" {
        di as err "specify probability(varlist) with the stage inclusion probabilities, or baseweight(varname) with a baseline weight"
        exit 198
    }
    if "`subsample'" != "" & "`baseweight'" == "" {
        di as err "subsample() requires baseweight()"
        exit 198
    }
    if "`by'" != "" & "`subsample'" == "" {
        di as err "by() is used with subsample(): the subsampling factor is computed within by() groups"
        exit 198
    }
    _rtm_util newvar `generate', `replace'
    marksample touse, novarlist

    tempvar w
    quietly gen double `w' = .

    * ---- mode A: product of probabilities ----
    if "`probability'" != "" {
        foreach p of varlist `probability' {
            quietly count if `touse' & missing(`p')
            if r(N) > 0 {
                di as err "probability variable {bf:`p'} is missing in " r(N) " sample observations"
                exit 416
            }
            quietly count if `touse' & (`p' <= 0 | `p' > 1)
            if r(N) > 0 {
                di as err "probability variable {bf:`p'} must lie in (0, 1]; " r(N) " observations do not"
                exit 459
            }
        }
        quietly replace `w' = 1 if `touse'
        foreach p of varlist `probability' {
            quietly replace `w' = `w' / `p' if `touse'
        }
        local mode "stage probabilities `probability'"
    }

    * ---- mode B: baseline weight, with a subsampling factor ----
    else {
        quietly count if `touse' & (missing(`baseweight') | `baseweight' <= 0)
        if r(N) > 0 {
            di as err "baseline weight {bf:`baseweight'} is missing or not positive in " r(N) " sample observations"
            exit 459
        }
        if "`subsample'" == "" {
            quietly replace `w' = `baseweight' if `touse'
            local mode "baseline weight `baseweight'"
        }
        else {
            _rtm_util binary `subsample' if `touse', what("subsample indicator")
            quietly count if `touse' & `subsample' == 0
            if r(N) == 0 {
                di as txt "note: every observation in the sample is in the subsample ({bf:`subsample'} is never 0), so the subsampling factor is 1."
                di as txt "      Run this step on the full baseline sample, before dropping the households outside the phone sample."
            }
            tempvar sumall sumsel fac
            if "`by'" == "" {
                tempvar one
                quietly gen byte `one' = 1
                local by "`one'"
            }
            quietly bysort `by': egen double `sumall' = total(cond(`touse', `baseweight', 0))
            quietly bysort `by': egen double `sumsel' = total(cond(`touse' & `subsample' == 1, `baseweight', 0))
            quietly count if `touse' & `subsample' == 1 & `sumsel' == 0
            quietly count if `touse' & `sumall' > 0 & `sumsel' == 0
            if r(N) > 0 {
                di as err "a by() group has baseline households but no subsampled household; its weights cannot be redistributed"
                di as err "merge that group with a neighbour in by(), or drop by()"
                exit 459
            }
            quietly gen double `fac' = `sumall' / `sumsel' if `touse' & `subsample' == 1
            quietly replace `w' = `baseweight' * `fac' if `touse' & `subsample' == 1
            quietly summarize `fac' if `touse' & `subsample' == 1
            return scalar factor_min = r(min)
            return scalar factor_max = r(max)
            local mode "baseline weight `baseweight' x subsampling factor (subsample `subsample'"
            if "`one'" == "" local mode "`mode', within `by'"
            local mode "`mode')"
        }
    }

    * ---- multiplicity ----
    if "`multiplicity'" != "" {
        quietly count if `touse' & !missing(`w') & (missing(`multiplicity') | `multiplicity' < 1 | `multiplicity' != int(`multiplicity'))
        if r(N) > 0 {
            di as err "multiplicity variable {bf:`multiplicity'} must be a whole number of 1 or more; " r(N) " weighted observations are not"
            exit 459
        }
        quietly replace `w' = `w' / `multiplicity' if `touse' & !missing(`w')
        local mode "`mode', divided by `multiplicity'"
    }

    quietly gen double `generate' = `w'
    local lbl `"Design weight: `mode'"'
    local lbl = usubstr(`"`lbl'"', 1, 80)
    label variable `generate' `"`lbl'"'

    * ---- report ----
    di as text _n "Design weights ({bf:`generate'}): `mode'"
    _rtm_util whead
    if "`baseweight'" != "" {
        _rtm_util wline `baseweight' if `touse', label("baseline weight (all)")
    }
    _rtm_util wline `generate' if `touse', label("design weight")
    di as text "{hline 100}"
    if "`subsample'" != "" {
        quietly summarize `baseweight' if `touse'
        local sall = r(sum)
    }
    * the summary of the new weight comes last, so that r() describes it
    _rtm_util wsum `generate' if `touse'
    if "`subsample'" != "" {
        di as text "Sum of baseline weights, all sample households: " as result %12.1fc `sall' ///
            as text "; subsample after adjustment: " as result %12.1fc r(sum)
        return scalar sum_baseline = `sall'
    }
    return scalar N = r(N)
    return scalar sum = r(sum)
    return scalar min = r(min)
    return scalar max = r(max)
    return scalar cv = r(cv)
    return scalar kish = r(kish)
    return local generate "`generate'"
    return local mode "`mode'"
    local cmd `"rtmweight base `0'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(base) cmd(`"`cmd'"') var(`generate')

    * ---- export tables and settings (schema rtm-export-1.0) ----
    if "`baseweight'" != "" capture _rtm_export wstage, frame(_rtmx_ws) stage("baseline weight, all sample") var(`baseweight') cond(`touse')
    capture _rtm_export wstage, frame(_rtmx_ws) stage("design weight") var(`generate') cond(`touse')
    capture _rtm_export table, name(weight_stages) frame(_rtmx_ws)
    capture _rtm_export setting, key(mode) value("`mode'") source("UN 2008 section 6.3; HFPS Vol. 2 pp. 10-11, 21")
    capture _rtm_export setting, key(generate) value("`generate'")
    if "`probability'" != "" capture _rtm_export setting, key(probability) value("`probability'")
    if "`baseweight'" != "" capture _rtm_export setting, key(baseweight) value("`baseweight'")
    if "`subsample'" != "" capture _rtm_export setting, key(subsample) value("`subsample'")
    if "`by'" != "" & "`one'" == "" capture _rtm_export setting, key(by) value("`by'")
    if "`multiplicity'" != "" capture _rtm_export setting, key(multiplicity) value("`multiplicity'")
end
