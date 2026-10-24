*! rtmsample_size.ado  version 0.2.0  24oct2026  rtmtools
*! Sample size per domain, for a level or for a change, with the design effect, the nonresponse
*! multiplier, the panel attrition reserve and the number of domains.
*! Level: closed form n = z^2 p(1-p)/e^2 (proportion) or z^2 s^2/e^2 (mean), UN 2008 formula 3.7
*!   (section 3.3.10, paragraphs 59-60; PDF pp. 53-54) and HFPS Vol. 2 section 2.1.1 (p. 3);
*!   e = margin() or relmargin() x the estimate (UN 2008: 10% relative margin at 95%).
*! Change: official power twoproportions / power twomeans (HFPS Vol. 2 section 2.1.2 and Table 1,
*!   pp. 4-5, which this reproduces), per group or round.
*! Then x deff (UN 2008 para 60; HFPS p. 3), / (share x hhsize) for a person-level indicator
*!   (UN 2008 formula 3.7), x nonresponse multiplier (UN 2008 para 60: 1.1), x attrition reserve
*!   1/((1-firstloss)(1-a)^(R-1)) or 1/(1-a)^R (MPPS 2016 p. 25, PDF p. 45), x domains (UN 2008
*!   paras 39-40; MPPS 2016 p. 25).
program define rtmsample_size, rclass
    version 16
    syntax , [P(real -1) MEAN(real 0) SD(real -1) MARGin(real -1) RELmargin(real -1) LEVel(cilevel) ///
        DEFF(real 2) NONResponse(real 1.1) ATTRition(real 0) ROUNDs(integer 1) FIRSTloss(real 0) ///
        SHARE(real 1) HHsize(real 1) DOMains(integer 1) CHANGE(real 0) POWer(real 0.8) ONESided]

    * ---- checks ----
    if `p' == -1 & `sd' == -1 {
        di as err "give p(#), the expected proportion, or sd(#) (with mean()) for a continuous indicator"
        exit 198
    }
    if `p' != -1 & `sd' != -1 {
        di as err "give either p() or sd(), not both"
        exit 198
    }
    local kind = cond(`p' != -1, "proportion", "mean")
    if "`kind'" == "proportion" & (`p' <= 0 | `p' >= 1) {
        di as err "p() must be strictly between 0 and 1"
        exit 198
    }
    if "`kind'" == "mean" & `sd' <= 0 {
        di as err "sd() must be positive"
        exit 198
    }
    if `margin' != -1 & `relmargin' != -1 {
        di as err "give margin() (absolute) or relmargin() (relative to the estimate), not both"
        exit 198
    }
    if `margin' != -1 & `margin' <= 0 {
        di as err "margin() must be positive"
        exit 198
    }
    if `margin' != -1 & `p' != -1 & `margin' >= 1 {
        di as err "margin() for a proportion is a fraction, for example 0.05 for 5 percentage points"
        exit 198
    }
    if `change' != 0 & `p' != -1 & abs(`change') >= 1 {
        di as err "change() for a proportion is a fraction, for example -0.10 for a fall of 10 percentage points"
        exit 198
    }
    if `relmargin' != -1 & (`relmargin' <= 0 | `relmargin' >= 1) {
        di as err "relmargin() is a fraction of the estimate, between 0 and 1 (UN 2008: 0.10)"
        exit 198
    }
    if `deff' <= 0 {
        di as err "deff() must be positive (UN 2008 default 2.0; 1.0 for an unclustered list sample)"
        exit 198
    }
    if `nonresponse' < 1 {
        di as err "nonresponse() is a multiplier of 1 or more (UN 2008: 1.1 for 10% nonresponse)"
        exit 198
    }
    if `attrition' < 0 | `attrition' >= 1 | `firstloss' < 0 | `firstloss' >= 1 {
        di as err "attrition() and firstloss() are rates between 0 and 1"
        exit 198
    }
    if `rounds' < 1 {
        di as err "rounds() must be 1 or more"
        exit 198
    }
    if `share' <= 0 | `share' > 1 | `hhsize' <= 0 {
        di as err "share() is the target group's share of the population (0 to 1) and hhsize() the average household size"
        exit 198
    }
    if `domains' < 1 {
        di as err "domains() must be 1 or more"
        exit 198
    }
    if `change' != 0 & (`power' <= 0 | `power' >= 1) {
        di as err "power() must be between 0 and 1 (0.8 or 0.9 are usual)"
        exit 198
    }
    if `change' == 0 & "`onesided'" != "" {
        di as err "onesided applies to change() only"
        exit 198
    }
    local alpha = (100 - `level') / 100
    local z = invnormal(1 - `alpha' / 2)
    local est = cond("`kind'" == "proportion", `p', `mean')

    * ---- step 1: interviews for a simple random sample ----
    if `change' == 0 {
        if `margin' == -1 & `relmargin' == -1 local relmargin 0.10
        if `margin' != -1 local e = `margin'
        else {
            if `est' == 0 {
                di as err "relmargin() needs a nonzero estimate: give mean() for a continuous indicator"
                exit 198
            }
            local e = `relmargin' * abs(`est')
        }
        if "`kind'" == "proportion" {
            local n_srs = `z'^2 * `p' * (1 - `p') / `e'^2
            local how "z^2 p(1-p)/e^2"
        }
        else {
            local n_srs = `z'^2 * `sd'^2 / `e'^2
            local how "z^2 s^2/e^2"
        }
        local what = cond("`kind'" == "proportion", "proportion `p'", "mean `mean' (sd `sd')")
        local prec = cond(`margin' != -1, "margin of error `margin'", "relative margin " + string(100 * `relmargin') + "% (e = " + string(`e', "%9.4g") + ")")
        local title "level of a `what', `prec', `level'% confidence (z = `: di %5.3f `z'')"
    }
    else {
        if "`kind'" == "proportion" {
            local p2 = `p' + `change'
            if `p2' <= 0 | `p2' >= 1 {
                di as err "p() + change() must stay strictly between 0 and 1"
                exit 198
            }
            quietly power twoproportions `p' `p2', power(`power') alpha(`alpha') `onesided'
            local how "power twoproportions `p' `p2' (Pearson chi-squared test)"
        }
        else {
            local m2 = `mean' + `change'
            quietly power twomeans `mean' `m2', sd(`sd') power(`power') alpha(`alpha') `onesided'
            local how "power twomeans `mean' `m2', sd(`sd')"
        }
        local n_srs = r(N1)
        local e .
        local title = "change of `change' in a `kind' of `est', power `power', alpha `alpha'" + cond("`onesided'" != "", " one-sided", " two-sided") + ", per group or round"
    }

    * ---- steps 2 to 6 ----
    local n_deff = `n_srs' * `deff'
    local n_hh = `n_deff' / (`share' * `hhsize')
    local n_sel = `n_hh' * `nonresponse'
    local expo = cond(`firstloss' > 0, `rounds' - 1, `rounds')
    local fatt = 1 / ((1 - `firstloss') * (1 - `attrition')^`expo')
    local n_panel = `n_sel' * `fatt'
    local n_dom = ceil(`n_panel' - 1e-9)
    local n_total = `n_dom' * `domains'

    * ---- report ----
    di as text _n "Sample size ({bf:rtmsample size}): `title'"
    di as text "{hline 96}"
    di as text %-72s "Step" %24s "per domain"
    di as text "{hline 96}"
    di as text %-72s "Interviews, simple random sample: `how'" as result %24.1fc `n_srs'
    di as text %-72s "x design effect `deff'" as result %24.1fc `n_deff'
    if `share' * `hhsize' != 1 di as text %-72s "/ (target-group share `share' x household size `hhsize') = households" as result %24.1fc `n_hh'
    di as text %-72s "x nonresponse multiplier `nonresponse'" as result %24.1fc `n_sel'
    if `fatt' != 1 {
        local fdesc = cond(`firstloss' > 0, "1/((1-`firstloss')(1-`attrition')^`expo')", "1/(1-`attrition')^`expo'")
        di as text %-72s "x attrition reserve `fdesc' = `: di %6.3f `fatt''" as result %24.1fc `n_panel'
    }
    di as text "{hline 96}"
    di as text %-72s "Households to select per domain (rounded up)" as result %24.0fc `n_dom'
    if `domains' > 1 di as text %-72s "x `domains' domains = total" as result %24.0fc `n_total'
    di as text "{hline 96}"
    if `change' == 0 & "`kind'" == "proportion" & `deff' == 2 di as text "deff 2.0 is UN 2008's default for clustered household samples; a list-based phone sample is closer to 1.0 (HFPS Vol. 2, pp. 3-4)."
    if `change' != 0 di as text "The change case is one group or round; the comparison group or round needs the same number (HFPS Vol. 2, Table 1)."

    * ---- stored results ----
    return scalar n_total = `n_total'
    return scalar n_domain = `n_dom'
    return scalar n_panel = `n_panel'
    return scalar n_select = `n_sel'
    return scalar n_hh = `n_hh'
    return scalar n_deff = `n_deff'
    return scalar n_srs = `n_srs'
    return scalar f_attrition = `fatt'
    return scalar z = `z'
    return scalar e = `e'
    return scalar level = `level'
    return scalar deff = `deff'
    return scalar nonresponse = `nonresponse'
    return scalar attrition = `attrition'
    return scalar rounds = `rounds'
    return scalar firstloss = `firstloss'
    return scalar share = `share'
    return scalar hhsize = `hhsize'
    return scalar domains = `domains'
    return scalar change = `change'
    if `change' != 0 return scalar power = `power'
    if "`kind'" == "proportion" return scalar p = `p'
    else {
        return scalar mean = `mean'
        return scalar sd = `sd'
    }
    return local kind "`kind'"
    return local case = cond(`change' == 0, "level", "change")
    return local method "`how'"
    return local cmdline `"rtmsample size `0'"'
end
