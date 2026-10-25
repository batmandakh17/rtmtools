*! rtmweight_household.ado  version 0.5.0  25oct2026  rtmtools
*! Household weights derived from person weights, the way the L2PHL scripts do it (program
*! practice, kept as a labeled step; no foundational document prescribes it):
*!   population weight of the household = sum of its members' person weights;
*!   household weight = mean of its members' person weights, optionally averaged within the
*!   PSU (psuaverage()), and optionally rescaled so that the household weights add to census
*!   household totals by stratum (strata() with totals() as level.stratum=total pairs or a
*!   totalsfile()).
*! The data in memory are the person-level file (one row per member) with the household id.
*! Consequence stated in the help: after the PSU average or the rescaling, population weight
*! and household weight x household size no longer agree; both are kept and labeled.
program define rtmweight_household, rclass
    version 16
    syntax varname(numeric) [if] [in], HHid(varname) GENerate(namelist min=2 max=2) ///
        [PSUaverage(varname) STRata(varname numeric) TOTals(string) TOTALSFile(string) REPLACE]
    local pw `varlist'
    marksample touse
    markout `touse' `hhid'
    gettoken g_pop g_hh : generate
    foreach g in `g_pop' `g_hh' {
        _rtm_util newvar `g', `replace'
    }
    quietly count if `touse' & `pw' <= 0
    if r(N) > 0 {
        di as err "person weight {bf:`pw'} is not positive in " r(N) " observations"
        exit 459
    }
    if ("`totals'" != "" | "`totalsfile'" != "") & "`strata'" == "" {
        di as err "totals() or totalsfile() need strata(varname), the variable the household totals refer to"
        exit 198
    }
    if "`totals'" != "" & "`totalsfile'" != "" {
        di as err "specify totals() or totalsfile(), not both"
        exit 198
    }
    tempvar n_hh
    quietly bysort `hhid': egen long `n_hh' = total(cond(`touse', 1, 0))
    * population weight: sum of the members' person weights; household weight: their mean
    quietly bysort `hhid': egen double `g_pop' = total(cond(`touse', `pw', .))
    quietly bysort `hhid': egen double `g_hh' = mean(cond(`touse', `pw', .))
    quietly replace `g_pop' = . if !`touse'
    quietly replace `g_hh' = . if !`touse'
    local how "population weight = sum of `pw' within `hhid'; household weight = its mean"
    * PSU average of the household weight (one value per PSU)
    if "`psuaverage'" != "" {
        tempvar tag hhw1
        quietly egen byte `tag' = tag(`hhid') if `touse'
        quietly bysort `psuaverage': egen double `hhw1' = mean(cond(`touse' & `tag', `g_hh', .))
        quietly replace `g_hh' = `hhw1' if `touse'
        local how "`how', averaged within `psuaverage'"
    }
    * rescale to census household totals by stratum
    local nrow 0
    if "`totals'" != "" | "`totalsfile'" != "" {
        local pairs ""
        if "`totalsfile'" != "" {
            preserve
            quietly use "`totalsfile'", clear
            capture confirm variable variable level total
            if _rc {
                di as err "totalsfile() must have the variables {bf:variable}, {bf:level} and {bf:total}"
                exit 198
            }
            quietly keep if variable == "`strata'"
            quietly count
            if r(N) == 0 {
                di as err "totalsfile() has no rows for variable == `strata'"
                exit 198
            }
            forvalues i = 1/`r(N)' {
                local pairs "`pairs' `=level[`i']'.`strata'=`=total[`i']'"
            }
            restore
        }
        else local pairs "`totals'"
        tempvar tag tot sumhh
        quietly egen byte `tag' = tag(`hhid') if `touse'
        quietly gen double `tot' = .
        foreach tok of local pairs {
            if !regexm("`tok'", "^([0-9]+)\.([A-Za-z_][A-Za-z0-9_]*)=([0-9.eE+-]+)$") {
                di as err `"cannot read the total "`tok'"; write totals as level.`strata'=number"'
                exit 198
            }
            local lev = regexs(1)
            local var = regexs(2)
            local val = regexs(3)
            if "`var'" != "`strata'" {
                di as err "the totals must refer to strata(`strata'), not `var'"
                exit 198
            }
            quietly replace `tot' = `val' if `touse' & `strata' == `lev'
            local ++nrow
        }
        quietly count if `touse' & missing(`tot')
        if r(N) > 0 {
            di as err "no household total for the stratum of " r(N) " observations; give a total for every stratum"
            exit 198
        }
        quietly bysort `strata': egen double `sumhh' = total(cond(`touse' & `tag', `g_hh', 0))
        quietly replace `g_hh' = `g_hh' * `tot' / `sumhh' if `touse'
        local how "`how', rescaled to household totals by `strata'"
    }
    label variable `g_pop' "Population weight of the household (sum of `pw')"
    label variable `g_hh' "Household weight (mean of `pw'`=cond("`psuaverage'" != "", ", PSU average", "")'`=cond(`nrow' > 0, ", rescaled", "")')"

    * ---- report (household level: one row per household) ----
    tempvar tag2
    quietly egen byte `tag2' = tag(`hhid') if `touse'
    di as text _n "Household weights from person weights ({bf:`g_pop'}, {bf:`g_hh'}): `how'"
    _rtm_util whead
    _rtm_util wline `pw' if `touse', label("person weight")
    _rtm_util wline `g_pop' if `touse' & `tag2', label("population weight (hh)")
    _rtm_util wline `g_hh' if `touse' & `tag2', label("household weight (hh)")
    di as text "{hline 100}"
    quietly count if `touse' & `tag2'
    local nhh = r(N)
    quietly summarize `g_pop' if `touse' & `tag2'
    local spop = r(sum)
    quietly summarize `g_hh' if `touse' & `tag2'
    local shh = r(sum)
    di as text "Households: " as result %8.0fc `nhh' as text "; sum of population weights " as result %14.1fc `spop' ///
        as text "; sum of household weights " as result %14.1fc `shh'
    tempvar ratio
    quietly gen double `ratio' = `g_pop' / (`g_hh' * `n_hh') if `touse' & `tag2'
    quietly summarize `ratio'
    di as text "Population weight / (household weight x members): min " as result %7.4f r(min) as text ", max " as result %7.4f r(max) ///
        as text cond(r(max) - r(min) < 1e-9, " (consistent)", " (the two weights differ after the PSU average or rescaling; see the help)")
    return scalar N_hh = `nhh'
    return scalar sum_pop = `spop'
    return scalar sum_hh = `shh'
    return scalar ratio_min = r(min)
    return scalar ratio_max = r(max)
    _rtm_util wsum `g_hh' if `touse' & `tag2'
    return scalar kish_hh = r(kish)
    return scalar cv_hh = r(cv)
    return local generate "`g_pop' `g_hh'"
    local cmd `"rtmweight household `0'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(household) cmd(`"`cmd'"') var(`g_hh')
    char `g_pop'[rtm_step] "household"
    char `g_pop'[rtm_cmd] `"`cmd'"'

    * ---- export ----
    capture _rtm_export wstage, frame(_rtmx_ws) stage("person weight") var(`pw') cond(`touse')
    capture _rtm_export wstage, frame(_rtmx_ws) stage("population weight (one row per household)") var(`g_pop') cond(`touse' & `tag2')
    capture _rtm_export wstage, frame(_rtmx_ws) stage("household weight (one row per household)") var(`g_hh') cond(`touse' & `tag2')
    capture _rtm_export table, name(weight_stages) frame(_rtmx_ws)
    capture _rtm_export setting, key(person_weight) value("`pw'")
    capture _rtm_export setting, key(hhid) value("`hhid'")
    capture _rtm_export setting, key(generate) value("`g_pop' `g_hh'")
    if "`psuaverage'" != "" capture _rtm_export setting, key(psuaverage) value("`psuaverage'") source("L2PHL script (program practice)")
    if `nrow' > 0 capture _rtm_export setting, key(rescaled_to) value("household totals by `strata'") source("L2PHL script (program practice)")
end
