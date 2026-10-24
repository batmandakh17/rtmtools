*! rtmsample_grid.ado  version 0.3.0  24oct2026  rtmtools
*! Spatially balanced sample of grid cells or points (R: spsurvey::grts through rtm_grts.R), on
*! the frame in memory matched to its GeoPackage by the cell identifier: equal or size-proportional
*! inclusion probabilities, stratified, with reverse-hierarchically ordered replacement sites and
*! nearest-neighbour replacements; design weight = 1 / inclusion probability (spsurvey's wgt).
*! Sources: Dumelle et al. 2023 (spsurvey, JSS); Stevens and Olsen 2004 (GRTS); Capturing What
*! Matters 2021 (PDF p. 17); the susospatsample README (spatially balanced sampling).
program define rtmsample_grid, rclass
    version 16
    syntax using/, N(string) GENerate(name) [Layer(string) ID(name) STRata(name) AUX(name) ///
        NOVER(integer 0) NNEAR(integer 0) MINDIS(real 0) SEED(string) SAVing(string) REPLACE]
    local frame `"`using'"'
    capture confirm file `"`frame'"'
    if _rc {
        di as err `"frame file not found: `frame'"'
        exit 601
    }
    local id = cond("`id'" == "", "cell_id", "`id'")
    capture confirm variable `id'
    if _rc {
        di as err "the frame must be in memory with its identifier `id' (load it with rtmframe grid or use)"
        exit 111
    }
    quietly bysort `id': gen byte _rtm_dupid = (_N > 1)
    quietly count if _rtm_dupid
    local nd = r(N)
    drop _rtm_dupid
    if `nd' > 0 {
        di as err "identifier `id' is not unique in the frame in memory"
        exit 459
    }
    if `nover' < 0 | `nnear' < 0 | `nnear' > 10 | `mindis' < 0 {
        di as err "nover() must be 0 or more, nnear() between 0 and 10, mindis() 0 or more (in the frame's units, metres for a projected CRS)"
        exit 198
    }
    foreach s in sel pi w order reserve near site {
        _rtm_util newvar `generate'_`s', `replace'
    }
    * ---- n: a number or a variable constant within strata ----
    local nnum ""
    local nfile ""
    capture confirm number `n'
    if !_rc {
        if `n' < 1 | `n' != round(`n') {
            di as err "n() must be a positive whole number or a variable"
            exit 198
        }
        local nnum "`n'"
    }
    else {
        capture confirm numeric variable `n'
        if _rc {
            di as err "n() must be a number or a numeric variable constant within strata"
            exit 198
        }
        if "`strata'" == "" {
            di as err "a per-stratum sample size variable needs strata()"
            exit 198
        }
        tempfile nf
        preserve
        keep `id' `n'
        quietly save "`nf'"
        restore
        local nfile "`nf'"
    }
    * ---- seed ----
    local seedgiven "`seed'"
    if "`seed'" != "" {
        capture confirm integer number `seed'
        if _rc {
            di as err "seed() must be a whole number"
            exit 198
        }
    }
    else local seed = runiformint(1, 2147483647)
    tempfile args status out
    tempname fh
    quietly file open `fh' using "`args'", write text replace
    file write `fh' "status=`status'" _n `"frame=`frame'"' _n `"layer=`layer'"' _n "idvar=`id'" _n "n=`nnum'" _n ///
        "nfile=`nfile'" _n "nvar=`n'" _n "strata=`strata'" _n "aux=`aux'" _n "seltype=`=cond("`aux'" != "", "proportional", "equal")'" _n ///
        "nover=`nover'" _n "nnear=`nnear'" _n "mindis=`mindis'" _n "seed=`seed'" _n "out=`out'" _n `"gpkg=`saving'"' _n
    file close `fh'
    _rtm_runr, script(rtm_grts.R) args("`args'") status("`status'") quietly
    local msg `"`r(message)'"'
    foreach tok of local msg {
        gettoken k v : tok, parse("=")
        local v = substr("`v'", 2, .)
        local R_`k' "`v'"
    }
    * ---- merge the sites into the frame ----
    tempvar ord0
    quietly gen double `ord0' = _n
    preserve
    use "`out'", clear
    keep `id' siteID siteuse replsite stratum wgt ip site_order
    rename (siteID siteuse replsite stratum wgt ip site_order) (_s_id _s_use _s_repl _s_str _s_wgt _s_ip _s_ord)
    * a cell can be the nearest neighbour of several base sites (and an ordered replacement as
    * well): keep one row per cell, base before ordered replacement before nearest neighbour
    quietly gen byte _s_pr = cond(_s_use == "Base", 1, cond(_s_use == "Over", 2, 3))
    quietly bysort `id' (_s_pr _s_ord): keep if _n == 1
    drop _s_pr
    tempfile sites
    quietly save "`sites'"
    restore
    quietly merge 1:1 `id' using "`sites'", nogenerate keep(master match)
    quietly gen byte `generate'_sel = (_s_use == "Base") if !missing(`id')
    quietly gen double `generate'_pi = _s_ip if _s_use == "Base"
    quietly gen double `generate'_w = _s_wgt if _s_use == "Base"
    quietly gen double `generate'_order = _s_ord if _s_use == "Base"
    quietly gen double `generate'_reserve = 0
    tempvar rr
    quietly bysort _s_str _s_use (_s_ord): gen double `rr' = _n if _s_use == "Over"
    quietly replace `generate'_reserve = `rr' if _s_use == "Over"
    quietly gen double `generate'_near = real(subinstr(_s_repl, "Site-", "", .)) if substr(_s_use, 1, 4) == "Near"
    quietly gen str20 `generate'_site = _s_id
    drop _s_id _s_use _s_repl _s_str _s_wgt _s_ip _s_ord
    sort `ord0'
    label variable `generate'_sel "Selected in the GRTS base sample (rtmsample grid, seed `seed')"
    label variable `generate'_pi "Inclusion probability (base sample)"
    label variable `generate'_w "Design weight = 1 / inclusion probability (spsurvey wgt)"
    label variable `generate'_order "Site number within the base sample (reverse hierarchical order)"
    label variable `generate'_reserve "Rank among the ordered replacement sites of the stratum (0 = none)"
    label variable `generate'_near "Nearest-neighbour replacement for this base site number (lowest, if several)"
    label variable `generate'_site "spsurvey site identifier"
    * ---- report ----
    quietly count if `generate'_sel == 1
    local nsel = r(N)
    quietly count if `generate'_reserve > 0
    local nres = r(N)
    quietly count if !missing(`generate'_near)
    local nnr = r(N)
    di as text _n "Spatially balanced sample ({bf:rtmsample grid}): GRTS, `=cond("`aux'" != "", "inclusion probabilities proportional to `aux'", "equal inclusion probabilities")'" ///
        cond("`strata'" != "", ", stratified by `strata'", "")
    quietly count
    di as text "Frame: " as result strtrim(string(r(N), "%12.0fc")) as text " units; base sample " as result `nsel' as text "; ordered replacements " as result `nres' ///
        as text "; nearest-neighbour replacements " as result `nnr'
    di as text "Seed: " as result "`seed'" as text "  (pass seed(`seed') to repeat this draw); spsurvey `R_spsurvey'"
    di as text "{hline 96}"
    di as text %-24s "stratum" %9s "units" %7s "n" %8s "reserve" %10s "pi min" %10s "pi max" %12s "sum w"
    di as text "{hline 96}"
    if "`strata'" != "" quietly levelsof `strata', local(levs)
    else local levs `""all""'
    local H : word count `levs'
    tempname T
    matrix `T' = J(`H', 6, .)
    local g 0
    foreach l of local levs {
        local ++g
        local cond = cond("`strata'" != "", `"`strata' == `"`l'"'"', "1")
        capture confirm string variable `strata'
        if "`strata'" != "" & _rc local cond "`strata' == `l'"
        quietly count if `cond'
        local U = r(N)
        quietly count if `cond' & `generate'_sel == 1
        local ng = r(N)
        quietly count if `cond' & `generate'_reserve > 0
        local rg = r(N)
        quietly summarize `generate'_pi if `cond' & `generate'_sel == 1, meanonly
        local pmin = r(min)
        local pmax = r(max)
        quietly summarize `generate'_w if `cond' & `generate'_sel == 1, meanonly
        local sw = r(sum)
        if `g' <= 40 di as text %-24s abbrev(`"`l'"', 24) as result %9.0fc `U' %7.0fc `ng' %8.0fc `rg' %10.4f `pmin' %10.4f `pmax' %12.1fc `sw'
        matrix `T'[`g', 1] = `U', `ng', `rg', `pmin', `pmax', `sw'
    }
    if `H' > 40 di as text "  ... (all `H' strata are in r(table))"
    di as text "{hline 96}"
    di as text "sum w equals the units of the stratum under equal probabilities; replacement sites have no weight until used."
    if `"`saving'"' != "" di as text `"Selected sites written to {browse "`saving'"}"'
    matrix colnames `T' = units n reserve pi_min pi_max sum_w
    local rn ""
    forvalues g = 1/`H' {
        local rn "`rn' s`g'"
    }
    matrix rownames `T' = `rn'
    return matrix table = `T'
    return scalar n_selected = `nsel'
    return scalar n_reserve = `nres'
    return scalar n_near = `nnr'
    return scalar H = `H'
    return scalar seed = `seed'
    return local seltype "`=cond("`aux'" != "", "proportional", "equal")'"
    return local generate "`generate'"
    local cmd `"rtmsample grid using "`frame'" `=cond(strpos(`"`0'"', ","), substr(`"`0'"', strpos(`"`0'"', ","), .), "")'"'
    if "`seedgiven'" == "" local cmd `"`cmd' seed(`seed')"'
    return local cmdline `"`cmd'"'
    char _dta[rtm_draw_seed] "`seed'"
    _rtm_util record, step(draw) cmd(`"`cmd'"') var(`generate'_sel)
end
