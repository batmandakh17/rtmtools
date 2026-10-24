*! rtmsample_allocate.ado  version 0.2.0  24oct2026  rtmtools
*! Allocation of a total sample n across strata: proportional (n_h = n N_h/N), equal (n/H),
*! Neyman (n N_h S_h / sum N_k S_k) or power allocation (n N_h^q / sum N_k^q, Bankier 1988), with a
*! minimum and a maximum per stratum (strata fixed at the bound, the rest re-allocated, the LSMS
*! practice of boosting small domains: Grosh and Munoz 1996, pp. 64-65 of the PDF) and
*! largest-remainder rounding that keeps the total.
*! Sources: UN 2008 section 3.4.1, paras 68-70 (PDF pp. 55-56): proportional and equal allocation;
*! HFPS Vol. 2 p. 5 (Neyman); Cochran 1977, section 5.5 (Neyman formula); Bankier 1988 (power allocation).
program define rtmsample_allocate, rclass
    version 16
    syntax [if] [in], STRata(varlist) N(real) [SIZE(varname numeric) METHod(string) SD(varname numeric) ///
        POWer(real 0.5) MIN(real 0) MAX(real 0) UNITS(varname numeric) GENerate(name) REPLACE NOROUND]
    marksample touse, novarlist
    markout `touse' `strata', strok
    local method = cond("`method'" == "", "proportional", lower("`method'"))
    if "`method'" == "prop" local method "proportional"
    if !inlist("`method'", "proportional", "equal", "neyman", "power") {
        di as err "method() must be proportional, equal, neyman or power"
        exit 198
    }
    if "`method'" == "neyman" & "`sd'" == "" {
        di as err "method(neyman) needs sd(varname): the within-stratum standard deviation of the key indicator"
        exit 198
    }
    if `n' <= 0 | `n' != round(`n') {
        di as err "n() must be a positive whole number, the total sample to allocate"
        exit 198
    }
    if `power' < 0 | `power' > 1 {
        di as err "power() is the exponent q of power allocation, between 0 (equal) and 1 (proportional); see help rtmsample"
        exit 198
    }
    if `min' < 0 | `max' < 0 | (`max' > 0 & `max' < `min') {
        di as err "min() and max() must be non-negative, with max() at least min()"
        exit 198
    }
    if "`generate'" != "" _rtm_util newvar `generate', `replace'
    quietly count if `touse'
    if r(N) == 0 {
        di as err "no observations"
        exit 2000
    }
    if "`size'" != "" {
        quietly count if `touse' & (`size' <= 0 | missing(`size'))
        if r(N) > 0 {
            di as err "size() must be positive and non-missing for every unit (`r(N)' are not)"
            exit 459
        }
    }
    if "`units'" != "" {
        quietly count if `touse' & (`units' < 1 | missing(`units') | `units' != round(`units'))
        if r(N) > 0 {
            di as err "units() must be a positive whole number for every stratum"
            exit 459
        }
    }

    * ---- stratum groups and labels ----
    tempvar grp lab
    quietly egen long `grp' = group(`strata') if `touse'
    quietly gen str244 `lab' = ""
    local k 0
    foreach v of local strata {
        local ++k
        tempvar part
        capture confirm string variable `v'
        if !_rc quietly gen str244 `part' = `v'
        else {
            local vl : value label `v'
            if "`vl'" != "" quietly decode `v', gen(`part')
            else quietly gen str244 `part' = string(`v')
        }
        quietly replace `lab' = `lab' + cond(`k' > 1, " ", "") + `part' if `touse'
    }

    * ---- stratum table ----
    tempvar Nh Uh S1 S2 cnt
    preserve
    quietly keep if `touse'
    if "`size'" != "" quietly gen double `Nh' = `size'
    else quietly gen double `Nh' = 1
    if "`units'" != "" quietly gen double `Uh' = `units'
    else quietly gen double `Uh' = 1
    if "`sd'" != "" {
        quietly gen double `S1' = `sd'
        quietly gen double `S2' = `sd'
    }
    else {
        quietly gen double `S1' = .
        quietly gen double `S2' = .
    }
    quietly gen double `cnt' = 1
    tempvar rows
    quietly bysort `grp': gen double `rows' = _N
    quietly summarize `rows', meanonly
    local maxrows = r(max)
    collapse (sum) Nh = `Nh' cnt = `cnt' (max) Umax = `Uh' (mean) S1 = `S1' (sd) S2 = `S2' (first) lab = `lab', by(`grp')
    quietly gen double Uh = cond("`units'" != "", Umax, cnt)
    * the cap by the number of units applies when units() is given, or when the rows are the units
    local capunits = ("`units'" != "") | ("`size'" == "") | (`maxrows' > 1)
    quietly count
    local H = r(N)
    if "`sd'" != "" {
        quietly gen double S = cond(S2 == 0 | missing(S2), S1, S2)
        quietly count if S <= 0 | missing(S)
        if r(N) > 0 {
            di as err "sd() must be positive within every stratum (`r(N)' strata are not)"
            exit 459
        }
    }
    quietly summarize Nh, meanonly
    local Ntot = r(sum)
    quietly gen double share = Nh / `Ntot'
    if "`method'" == "proportional" quietly gen double a0 = `n' * share
    else if "`method'" == "equal" quietly gen double a0 = `n' / `H'
    else if "`method'" == "neyman" {
        quietly gen double NS = Nh * S
        quietly summarize NS, meanonly
        quietly gen double a0 = `n' * NS / r(sum)
    }
    else {
        quietly gen double Np = Nh^`power'
        quietly summarize Np, meanonly
        quietly gen double a0 = `n' * Np / r(sum)
    }

    * ---- bounds: units, max(), min(); fixed strata take the bound, the rest is re-allocated ----
    quietly gen double a = a0
    quietly gen byte fixed = 0
    quietly gen byte newfix = 0
    quietly gen double bound = .
    quietly gen str8 flag = ""
    local iter 0
    local changed 1
    while `changed' & `iter' < 100 {
        local ++iter
        local changed 0
        quietly replace newfix = 0
        if `capunits' {
            quietly replace newfix = 1 if !fixed & a > Uh + 1e-9
            quietly replace bound = Uh if newfix == 1
            quietly replace flag = "units" if newfix == 1
        }
        if `max' > 0 {
            quietly replace newfix = 2 if !fixed & newfix == 0 & a > `max' + 1e-9
            quietly replace bound = cond(`capunits', min(`max', Uh), `max') if newfix == 2
            quietly replace flag = "max" if newfix == 2
        }
        if `min' > 0 {
            quietly replace newfix = 3 if !fixed & newfix == 0 & a < `min' - 1e-9
            quietly replace bound = cond(`capunits', min(`min', Uh), `min') if newfix == 3
            quietly replace flag = "min" if newfix == 3
        }
        quietly count if newfix > 0
        if r(N) > 0 {
            local changed 1
            quietly replace a = bound if newfix > 0
            quietly replace fixed = 1 if newfix > 0
            quietly summarize a if fixed, meanonly
            local nfix = r(sum)
            local nrem = `n' - `nfix'
            quietly count if !fixed
            if r(N) == 0 {
                if abs(`nrem') > 1e-6 {
                    di as err "every stratum is held at a bound (min(), max() or its number of units) and the bounds add to " strtrim(string(`nfix', "%12.0f")) ", not n() = `n'; change the bounds or n()"
                    exit 459
                }
            }
            else {
                if `nrem' < 0 {
                    di as err "min() times the number of strata exceeds n(); raise n() or lower min()"
                    exit 459
                }
                quietly summarize a0 if !fixed, meanonly
                quietly replace a = `nrem' * a0 / r(sum) if !fixed
            }
        }
    }

    * ---- rounding: largest remainder, keeping the total ----
    if "`noround'" == "" {
        quietly gen double afl = floor(a + 1e-9)
        quietly gen double frac = a - afl
        quietly summarize afl, meanonly
        local left = round(`n' - r(sum))
        quietly gen double nh = afl
        if `left' > 0 {
            gsort -frac `grp'
            quietly replace nh = afl + 1 in 1/`left'
            sort `grp'
        }
    }
    else quietly gen double nh = a
    quietly gen double wh = Nh / nh if nh > 0
    quietly gen double fh = nh / Nh

    * ---- report ----
    local sizelab = cond("`size'" != "", "size N_h", "units N_h")
    local mdesc "`method'"
    if "`method'" == "power" local mdesc "power (q = `power')"
    di as text _n "Allocation ({bf:rtmsample allocate}): `mdesc', n = " as result strtrim(string(`n', "%12.0fc")) as text ", `H' strata" ///
        cond(`min' > 0, ", min `min' per stratum", "") cond(`max' > 0, ", max `max'", "")
    di as text "{hline 100}"
    di as text %-28s "stratum" %14s "`sizelab'" %8s "share" %12s "exact" %9s "n_h" %12s "N_h/n_h" %10s "n_h/N_h" %7s "note"
    di as text "{hline 100}"
    forvalues i = 1/`H' {
        di as text %-28s abbrev(lab[`i'], 28) as result %14.0fc Nh[`i'] %8.3f share[`i'] %12.2f a[`i'] %9.0fc nh[`i'] %12.2f wh[`i'] %10.4f fh[`i'] as text %7s flag[`i']
    }
    di as text "{hline 100}"
    quietly summarize nh, meanonly
    local nsum = r(sum)
    di as text %-28s "total" as result %14.0fc `Ntot' %8.3f 1 %12.2f `n' %9.0fc `nsum' %12.2f `Ntot' / `nsum'
    di as text "{hline 100}"
    di as text "exact: before rounding; N_h/n_h: the design weight if n_h units are drawn with equal probability from N_h;"
    di as text "note: a stratum held at a bound (min, max, or the number of units), with the remainder re-allocated."
    if "`sd'" != "" di as text "S_h: the within-stratum standard deviation from sd(); a constant within the stratum is used as given."

    * ---- stored results ----
    tempname A
    mkmat Nh share a nh wh fh, matrix(`A')
    matrix colnames `A' = N_h share exact n_h N_over_n f_h
    local rn ""
    forvalues i = 1/`H' {
        local rn "`rn' s`i'"
    }
    matrix rownames `A' = `rn'
    local labs ""
    forvalues i = 1/`H' {
        local labs `"`labs' "`=lab[`i']'""'
    }
    quietly count if fixed
    local nfixed = r(N)
    tempfile T
    tempvar nhv
    keep `grp' nh
    rename nh `nhv'
    quietly save "`T'"
    restore

    * ---- write the allocation to the data ----
    if "`generate'" != "" {
        quietly merge m:1 `grp' using "`T'", nogenerate keep(master match)
        quietly gen double `generate' = `nhv' if `touse'
        drop `nhv'
        label variable `generate' "Allocated sample size of the stratum (`mdesc', n = `n')"
    }
    return matrix alloc = `A'
    return scalar n = `n'
    return scalar n_rounded = `nsum'
    return scalar N = `Ntot'
    return scalar H = `H'
    return scalar n_bounded = `nfixed'
    return local strata_labels `"`labs'"'
    return local method "`method'"
    return local strata "`strata'"
    local cmd `"rtmsample allocate `0'"'
    return local cmdline `"`cmd'"'
    if "`generate'" != "" _rtm_util record, step(allocate) cmd(`"`cmd'"') var(`generate')
end
