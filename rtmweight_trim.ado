*! rtmweight_trim.ado  version 0.5.0  25oct2026  rtmtools
*! Trim extreme weights, then rescale so that the trimmed weights keep the original total.
*!
*! rule(winsor): weights above the pct() percentile are set to that percentile value, and
*!   (if lowpct() > 0) weights below the lowpct() percentile are raised to it. HFPS Vol. 2
*!   (Himelein et al. 2020, p. 11) replaces the weights in the 99th and 100th percentiles with
*!   the highest value of the 98th; Ambel et al. 2021 (p. 11) trim at the 2nd and 98th
*!   percentiles. Default pct(98), lowpct(0).
*! rule(cap): weights above cap(), or above capmult() times the median, are set to that bound
*!   (UN 2008, section 6.8, pp. 136-138: a stratum-specific upper bound, then rescaling so
*!   that the trimmed weights sum to the original total).
*! Percentiles, bounds and rescaling are computed within by() groups when by() is given.
*! Trimming is meant to run before calibration (HFPS Vol. 2, p. 11; Ambel et al. 2021, p. 11).
program define rtmweight_trim, rclass
    version 16
    syntax varname(numeric) [if] [in], GENerate(name) ///
        [RULE(string) PCT(real 98) LOWpct(real 0) CAP(real -1) CAPMult(real -1) BY(varlist) NORESCALE ID(varname) REPLACE]
    local w `varlist'
    local rule = lower("`rule'")
    if "`rule'" == "" {
        di as err "rule() is required: rule(winsor) caps the largest weights at a percentile (pct(), default 98); rule(cap) caps them at capmult(#) times the median or at the value cap(#)"
        exit 198
    }
    if !inlist("`rule'", "winsor", "cap") {
        di as err "rule() must be winsor or cap"
        exit 198
    }
    if "`rule'" == "winsor" & (`pct' <= 50 | `pct' >= 100) {
        di as err "pct() must be between 50 and 100 (default 98)"
        exit 198
    }
    if "`rule'" == "winsor" & (`lowpct' < 0 | `lowpct' >= 50) {
        di as err "lowpct() must be between 0 and 50 (default 0, no lower trimming)"
        exit 198
    }
    if "`rule'" == "cap" & `cap' <= 0 & `capmult' <= 0 {
        di as err "rule(cap) needs cap(#) (an absolute bound) or capmult(#) (a multiple of the median)"
        exit 198
    }
    if "`rule'" == "cap" & `cap' > 0 & `capmult' > 0 {
        di as err "specify cap() or capmult(), not both"
        exit 198
    }
    _rtm_util newvar `generate', `replace'
    marksample touse
    quietly count if `touse' & `w' <= 0
    if r(N) > 0 {
        di as err "weight {bf:`w'} is not positive in " r(N) " sample observations; trimming applies to positive weights only"
        exit 459
    }

    if "`by'" == "" {
        tempvar one
        quietly gen byte `one' = 1
        local byv "`one'"
    }
    else local byv "`by'"
    tempvar g hi lo wt sum0 sum1 med
    quietly egen long `g' = group(`byv') if `touse', missing
    quietly gen double `wt' = `w' if `touse'
    quietly gen double `hi' = .
    quietly gen double `lo' = .
    quietly levelsof `g' if `touse', local(glev)
    foreach k of local glev {
        if "`rule'" == "winsor" {
            if `lowpct' > 0 {
                _pctile `w' if `touse' & `g' == `k', percentiles(`lowpct' `pct')
                quietly replace `lo' = r(r1) if `touse' & `g' == `k'
                quietly replace `hi' = r(r2) if `touse' & `g' == `k'
            }
            else {
                _pctile `w' if `touse' & `g' == `k', percentiles(`pct')
                quietly replace `hi' = r(r1) if `touse' & `g' == `k'
            }
        }
        else {
            if `cap' > 0 quietly replace `hi' = `cap' if `touse' & `g' == `k'
            else {
                quietly summarize `w' if `touse' & `g' == `k', detail
                quietly replace `hi' = `capmult' * r(p50) if `touse' & `g' == `k'
            }
        }
    }
    quietly count if `touse' & `w' > `hi'
    local ntrim_hi = r(N)
    quietly replace `wt' = `hi' if `touse' & `w' > `hi'
    local ntrim_lo 0
    if "`rule'" == "winsor" & `lowpct' > 0 {
        quietly count if `touse' & `w' < `lo'
        local ntrim_lo = r(N)
        quietly replace `wt' = `lo' if `touse' & `w' < `lo'
    }
    * rescale within by-groups so that the total is unchanged (UN 2008, p. 137)
    quietly bysort `g': egen double `sum0' = total(cond(`touse', `w', 0))
    quietly bysort `g': egen double `sum1' = total(cond(`touse', `wt', 0))
    tempvar rs
    quietly gen double `rs' = `sum0' / `sum1' if `touse'
    if "`norescale'" == "" quietly replace `wt' = `wt' * `rs' if `touse'
    quietly gen double `generate' = `wt' if `touse'
    * ordinal suffixes (1st, 2nd, 3rd, 4th, 11th to 13th)
    foreach p in pct lowpct {
        local x = round(``p'')
        if inlist(mod(`x', 100), 11, 12, 13) local ord_`p' "th"
        else if mod(`x', 10) == 1 local ord_`p' "st"
        else if mod(`x', 10) == 2 local ord_`p' "nd"
        else if mod(`x', 10) == 3 local ord_`p' "rd"
        else local ord_`p' "th"
    }
    local what = cond("`rule'" == "winsor", "winsorized at the `pct'`ord_pct' percentile" + cond(`lowpct' > 0, " and the `lowpct'`ord_lowpct'", ""), ///
        cond(`cap' > 0, "capped at `cap'", "capped at `capmult' x median"))
    if "`by'" != "" local what "`what' within `by'"
    if "`norescale'" == "" local what "`what', rescaled to the original total"
    local lbl `"Weight trimmed: `what'"'
    local lbl = usubstr(`"`lbl'"', 1, 80)
    label variable `generate' `"`lbl'"'

    * ---- report ----
    di as text _n "Trimmed weights ({bf:`generate'}): `what'"
    _rtm_util whead
    _rtm_util wline `w' if `touse', label("before trimming")
    _rtm_util wline `generate' if `touse', label("after trimming")
    di as text "{hline 100}"
    quietly count if `touse'
    local N = r(N)
    di as text "Weights lowered: " as result %6.0fc `ntrim_hi' as text " (" as result %4.1f 100 * `ntrim_hi' / `N' "%" as text ")" ///
        _c
    if "`rule'" == "winsor" & `lowpct' > 0 di as text "; raised: " as result %6.0fc `ntrim_lo' _c
    quietly summarize `rs' if `touse'
    if "`norescale'" == "" di as text "; rescaling factor " as result %7.4f r(min) as text " to " as result %7.4f r(max)
    else di ""
    _rtm_util wsum `w' if `touse'
    local kish0 = r(kish)
    _rtm_util wsum `generate' if `touse'
    di as text "Kish's 1+CV2 from " as result %6.3f `kish0' as text " to " as result %6.3f r(kish)
    return scalar N = `N'
    return scalar n_trimmed_high = `ntrim_hi'
    return scalar n_trimmed_low = `ntrim_lo'
    return scalar kish_before = `kish0'
    return scalar kish_after = r(kish)
    return scalar sum = r(sum)
    return scalar max = r(max)
    return scalar min = r(min)
    return local rule "`rule'"
    return local generate "`generate'"
    local cmd `"rtmweight trim `0'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(trim) cmd(`"`cmd'"') var(`generate')

    * ---- export tables and settings (schema rtm-export-1.0) ----
    capture _rtm_export wstage, frame(_rtmx_ws) stage("before trimming") var(`w') cond(`touse')
    capture _rtm_export wstage, frame(_rtmx_ws) stage("after trimming") var(`generate') cond(`touse') ntrimmed(`=`ntrim_hi' + `ntrim_lo'')
    capture _rtm_export table, name(weight_stages) frame(_rtmx_ws)
    * flagged units: every weight that was lowered or raised, with its id (or observation number)
    capture frame drop _rtmx_fl
    frame create _rtmx_fl str32 table str32 unit_id str32 stage double(value) str64 reason
    tempvar trimmed
    quietly gen byte `trimmed' = `touse' & (`w' > `hi' | ("`rule'" == "winsor" & `lowpct' > 0 & `w' < `lo'))
    quietly count if `trimmed'
    if r(N) > 0 & r(N) <= 5000 {
        forvalues i = 1/`=_N' {
            if `trimmed'[`i'] {
                if "`id'" != "" local uid = string(`id'[`i'])
                else local uid "obs `i'"
                local why = cond(`w'[`i'] > `hi'[`i'], "weight above the upper bound `=string(`hi'[`i'], "%12.4g")'", "weight below the lower bound")
                frame post _rtmx_fl ("weight_units") ("`uid'") ("`w'") (`w'[`i']) ("`why'")
            }
        }
    }
    capture _rtm_export table, name(flags) frame(_rtmx_fl)
    capture _rtm_export setting, key(rule) value("`rule'") source("HFPS Vol. 2 p. 11 (winsor at the 98th percentile); UN 2008 section 6.8 (cap and rescale)")
    if "`rule'" == "winsor" capture _rtm_export setting, key(pct) value("`pct'")
    if "`rule'" == "winsor" & `lowpct' > 0 capture _rtm_export setting, key(lowpct) value("`lowpct'")
    if `cap' > 0 capture _rtm_export setting, key(cap) value("`cap'")
    if `capmult' > 0 capture _rtm_export setting, key(capmult) value("`capmult'")
    if "`by'" != "" capture _rtm_export setting, key(by) value("`by'")
    capture _rtm_export setting, key(rescale) value("`=cond("`norescale'" == "", "yes", "no")'")
    capture _rtm_export setting, key(weight) value("`w'")
    capture _rtm_export setting, key(generate) value("`generate'")
end
