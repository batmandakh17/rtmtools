*! rtmsample_rdd.ado  version 0.5.0  25oct2026  rtmtools
*! Random digit dialing sample: telephone numbers generated at random from operator prefixes
*! (the L2Som and L2Arm/L2Geo practice: prefix plus random digits, then an activity check by the
*! call centre). Each prefix is a stratum of the number space: n() numbers per prefix (a number,
*! or a numlist with one entry per prefix), digits() random digits after the prefix, no number
*! twice, and a recorded seed. The selection probability of a number within its prefix is
*! n / 10^digits; a household reachable on several numbers needs the multiplicity adjustment
*! (rtmweight base, multiplicity(); HFPS Vol. 2 p. 21). The generated numbers replace the data
*! in memory (clear) and are never exported: the export holds the counts per prefix only.
*! Sources: HFPS Vol. 2 pp. 7-8 (RDD frames and their limits); Waksberg 1978 (RDD designs).
program define rtmsample_rdd, rclass
    version 16
    syntax , PREfixes(numlist integer >=0) N(numlist integer >=1) [DIGits(integer 7) SEED(string) CLEAR SAVing(string) REPLACE]
    local np : word count `prefixes'
    local nn : word count `n'
    if `nn' != 1 & `nn' != `np' {
        di as err "n() must be one number (per prefix) or one number for each of the `np' prefixes"
        exit 198
    }
    if `digits' < 1 | `digits' > 12 {
        di as err "digits() must be between 1 and 12"
        exit 198
    }
    if c(changed) & "`clear'" == "" {
        di as err "the data in memory have unsaved changes; save them or add clear"
        exit 4
    }
    local seedgiven "`seed'"
    if "`seed'" != "" {
        capture confirm integer number `seed'
        if _rc {
            di as err "seed() must be a whole number"
            exit 198
        }
    }
    else local seed = runiformint(1, 2147483647)
    set seed `seed'
    local space = 10^`digits'
    local total 0
    forvalues i = 1/`np' {
        local pf : word `i' of `prefixes'
        local ni = cond(`nn' == 1, `n', `: word `i' of `n'')
        if `ni' > `space' {
            di as err "n() for prefix `pf' exceeds the `=strtrim(string(`space', "%14.0fc"))' numbers its `digits' digits allow"
            exit 459
        }
        local n`i' = `ni'
        local total = `total' + `ni'
    }
    * one row per number: draw the suffixes without replacement within each prefix by sorting
    * random keys over an oversampled set (numbers are rare in the space, so duplicates are few)
    clear
    quietly set obs `total'
    quietly gen long prefix = .
    quietly gen double suffix = .
    local row 1
    forvalues i = 1/`np' {
        local pf : word `i' of `prefixes'
        local hi = `row' + `n`i'' - 1
        quietly replace prefix = `pf' in `row'/`hi'
        local row = `hi' + 1
    }
    quietly replace suffix = floor(runiform() * `space')
    quietly duplicates tag prefix suffix, generate(_dup)
    local iter 0
    quietly count if _dup > 0
    while r(N) > 0 & `iter' < 50 {
        local ++iter
        tempvar first
        quietly bysort prefix suffix: gen byte `first' = (_n == 1)
        quietly replace suffix = floor(runiform() * `space') if _dup > 0 & !`first'
        drop _dup `first'
        quietly duplicates tag prefix suffix, generate(_dup)
        quietly count if _dup > 0
    }
    drop _dup
    quietly gen str20 number = string(prefix) + string(suffix, "%0`digits'.0f")
    quietly gen double prob = .
    forvalues i = 1/`np' {
        local pf : word `i' of `prefixes'
        quietly replace prob = `n`i'' / `space' if prefix == `pf'
    }
    quietly gen double weight = 1 / prob
    label variable prefix "Operator prefix (stratum of the number space)"
    label variable number "Telephone number generated at random (prefix + `digits' digits)"
    label variable prob "Selection probability of the number within its prefix (n / 10^`digits')"
    label variable weight "Design weight of the number = 1 / prob (before activity and multiplicity adjustments)"
    sort prefix number
    * ---- report ----
    di as text _n "Random digit dialing sample ({bf:rtmsample rdd}): `digits' random digits after each prefix, no number twice"
    di as text "Seed: " as result "`seed'" as text "  (pass seed(`seed') to repeat this draw)"
    di as text "{hline 76}"
    di as text %-14s "prefix" %14s "number space" %10s "numbers" %12s "prob" %14s "weight"
    di as text "{hline 76}"
    capture frame drop _rtmx_ds
    frame create _rtmx_ds str80 stratum double(n_units n_selected n_reserve prob_min prob_max interval random_start)
    forvalues i = 1/`np' {
        local pf : word `i' of `prefixes'
        di as text %-14s "`pf'" as result %14.0fc `space' %10.0fc `n`i'' %12.6f `n`i'' / `space' %14.1fc `space' / `n`i''
        frame post _rtmx_ds ("prefix `pf'") (`space') (`n`i'') (0) (`n`i'' / `space') (`n`i'' / `space') (.) (.)
    }
    di as text "{hline 76}"
    di as text "Numbers that are not active, not households or not eligible are found by the call centre; keep every number's"
    di as text "outcome, because the response adjustment needs the eligible numbers that did not respond (HFPS Vol. 2 pp. 7-8)."
    di as text "The numbers stay in memory and in saving(); the export holds the counts per prefix only."
    if `"`saving'"' != "" {
        quietly save `"`saving'"', `replace'
        di as text `"Numbers saved to `saving'"'
    }
    * ---- stored results and export ----
    return scalar n_numbers = `total'
    return scalar n_prefixes = `np'
    return scalar digits = `digits'
    return scalar seed = `seed'
    return local prefixes "`prefixes'"
    local cmd `"rtmsample rdd `0'"'
    if "`seedgiven'" == "" local cmd `"`cmd' seed(`seed')"'
    return local cmdline `"`cmd'"'
    char _dta[rtm_draw_seed] "`seed'"
    _rtm_util record, step(rdd) cmd(`"`cmd'"') var(number)
    capture _rtm_export table, name(draw_summary) frame(_rtmx_ds)
    capture _rtm_export setting, key(method) value("random digit dialing: prefix + `digits' random digits") source("HFPS Vol. 2 pp. 7-8; Waksberg 1978")
    capture _rtm_export setting, key(prefixes) value("`prefixes'")
    capture _rtm_export setting, key(n) value("`n'")
    capture _rtm_export setting, key(seed) value("`seed'")
    capture _rtm_export message, text("telephone numbers are not exported (identifiers only)")
end
