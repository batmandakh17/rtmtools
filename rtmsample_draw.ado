*! rtmsample_draw.ado  version 0.2.0  24oct2026  rtmtools
*! Draw a probability sample from the frame in memory, within strata:
*!   srs         simple random sampling without replacement (gsample, Jann 2006)
*!   systematic  equal-probability systematic sampling on the sorted frame (implicit stratification,
*!               UN 2008 paras 77-79; Grosh and Munoz 1996 pp. 68-70 of the PDF)
*!   pps         PPS without replacement by random systematic selection (gsample: Hartley and Rao 1962;
*!               Brewer and Hanif 1983, procedure 2); inclusion probability n x size / sum of sizes
*!   ppssys      systematic PPS on the sorted frame: cumulative sizes, interval, random start
*!               (Grosh and Munoz 1996 pp. 68-69; UN 2008 paras 78, 100-101, 108 and 180)
*! Units whose size reaches the interval are taken with certainty and the rest re-drawn (UN 2008
*! para 101 describes the alternative of letting them be selected twice). Writes the selection flag,
*! the inclusion probability, the design weight (its inverse), the selection order, and flags for
*! certainty and reserve units; stores and records the seed so the draw can be repeated.
program define rtmsample_draw, rclass
    version 16
    syntax [if] [in], N(string) GENerate(name) [STRata(varlist) PPS(varname numeric) METHod(string) ///
        SORT(varlist) RESERVE(string) SEED(string) ID(varlist) REPLACE]
    marksample touse, novarlist
    if "`strata'" != "" markout `touse' `strata', strok
    if "`pps'" != "" markout `touse' `pps'
    local method = cond("`method'" == "", cond("`pps'" == "", "srs", "ppssys"), lower("`method'"))
    if !inlist("`method'", "srs", "systematic", "pps", "ppssys") {
        di as err "method() must be srs, systematic, pps or ppssys"
        exit 198
    }
    if inlist("`method'", "pps", "ppssys") & "`pps'" == "" {
        di as err "method(`method') needs pps(varname), the measure of size"
        exit 198
    }
    if inlist("`method'", "srs", "systematic") & "`pps'" != "" {
        di as err "pps() goes with method(pps) or method(ppssys); for equal probabilities leave pps() out"
        exit 198
    }
    if "`sort'" != "" & !inlist("`method'", "systematic", "ppssys") {
        di as err "sort() (implicit stratification) applies to method(systematic) and method(ppssys)"
        exit 198
    }
    local ispps = inlist("`method'", "pps", "ppssys")
    foreach s in sel pi w order reserve {
        _rtm_util newvar `generate'_`s', `replace'
    }
    if `ispps' _rtm_util newvar `generate'_cert, `replace'
    quietly count if `touse'
    local Nframe = r(N)
    if `Nframe' == 0 {
        di as err "no observations in the frame"
        exit 2000
    }
    if "`id'" != "" {
        tempvar dup
        quietly bysort `id': gen byte `dup' = (_N > 1) if `touse'
        quietly count if `dup' == 1
        if r(N) > 0 di as txt "note: id(`id') is not unique in the frame (" r(N) " observations share an id)"
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
    set seed `seed'

    * ---- strata, sizes and sample sizes per stratum ----
    tempvar ord0 grp U nh rh size
    quietly gen double `ord0' = _n
    if "`strata'" != "" quietly egen long `grp' = group(`strata') if `touse'
    else quietly gen long `grp' = 1 if `touse'
    quietly bysort `grp': gen long `U' = _N if `touse'
    _rtmsample_pergroup `n', touse(`touse') grp(`grp') generate(`nh') what(n())
    if "`reserve'" != "" _rtmsample_pergroup `reserve', touse(`touse') grp(`grp') generate(`rh') what(reserve())
    else quietly gen double `rh' = 0 if `touse'
    quietly count if `touse' & `nh' + `rh' > `U'
    if r(N) > 0 {
        di as err "n() plus reserve() exceeds the number of units in " r(N) " frame observations' strata; lower them or check strata()"
        exit 459
    }
    if `ispps' {
        quietly gen double `size' = `pps' if `touse'
        quietly count if `touse' & `size' <= 0
        if r(N) > 0 {
            di as err "pps(`pps') must be positive for every frame unit (" r(N) " are zero or negative); drop or fix them first"
            exit 459
        }
    }
    else quietly gen double `size' = 1 if `touse'

    * ---- main draw ----
    tempvar hit ordv piv certv
    quietly gen byte `hit' = 0
    quietly gen double `ordv' = .
    quietly gen double `piv' = .
    quietly gen byte `certv' = 0
    if inlist("`method'", "srs", "pps") {
        _rtmsample_gspass, elig(`touse') grp(`grp') n(`nh') size(`size') pps(`ispps') hit(`hit') order(`ordv') pi(`piv') cert(`certv')
    }
    else {
        _rtmsample_syspass, elig(`touse') grp(`grp') n(`nh') size(`size') pps(`ispps') hit(`hit') order(`ordv') pi(`piv') cert(`certv') ord0(`ord0') sort(`sort')
    }

    * ---- reserve draw among the units not selected ----
    tempvar elig2 rhit rordv rpiv rcertv
    quietly gen byte `elig2' = `touse' & `hit' == 0
    quietly gen byte `rhit' = 0
    quietly gen double `rordv' = .
    quietly gen double `rpiv' = .
    quietly gen byte `rcertv' = 0
    quietly count if `touse' & `rh' > 0
    if r(N) > 0 {
        if inlist("`method'", "srs", "pps") {
            _rtmsample_gspass, elig(`elig2') grp(`grp') n(`rh') size(`size') pps(`ispps') hit(`rhit') order(`rordv') pi(`rpiv') cert(`rcertv')
        }
        else {
            _rtmsample_syspass, elig(`elig2') grp(`grp') n(`rh') size(`size') pps(`ispps') hit(`rhit') order(`rordv') pi(`rpiv') cert(`rcertv') ord0(`ord0') sort(`sort')
        }
    }
    sort `ord0'

    * ---- output variables ----
    quietly gen byte `generate'_sel = `hit' if `touse'
    quietly gen double `generate'_pi = `piv' if `touse'
    quietly gen double `generate'_w = 1 / `piv' if `touse' & `hit'
    quietly gen double `generate'_order = `ordv' if `touse' & `hit'
    * reserve rank: units taken with certainty in the reserve pass come first, then the drawn order
    tempvar rc_n rc_rank
    quietly bysort `grp': egen double `rc_n' = total(cond(`touse' & `rhit' & `rcertv', 1, 0))
    quietly bysort `grp' `rcertv' (`ord0'): gen double `rc_rank' = _n if `touse' & `rhit' & `rcertv'
    sort `ord0'
    quietly gen double `generate'_reserve = 0 if `touse'
    quietly replace `generate'_reserve = cond(`rcertv', `rc_rank', `rordv' + `rc_n') if `touse' & `rhit'
    if `ispps' quietly gen byte `generate'_cert = `certv' if `touse'
    local lbl "Selected (rtmsample draw, `method', seed `seed'); 0 = in the frame, not selected"
    label variable `generate'_sel "`=usubstr("`lbl'", 1, 80)'"
    label variable `generate'_pi "Inclusion probability of the unit"
    label variable `generate'_w "Design weight = 1 / inclusion probability (selected units)"
    label variable `generate'_order "Selection order within the stratum"
    label variable `generate'_reserve "Reserve rank for replacement (0 = not a reserve unit)"
    if `ispps' label variable `generate'_cert "Selected with certainty (size at or above the interval)"

    * ---- summary by stratum ----
    quietly count if `touse' & `hit'
    local nsel = r(N)
    quietly count if `touse' & `rhit'
    local nres = r(N)
    quietly count if `touse' & `certv'
    local ncert = r(N)
    quietly summarize `grp' if `touse', meanonly
    local H = r(max)
    local mdesc "`method'"
    if "`method'" == "srs" local mdesc "simple random sampling without replacement"
    if "`method'" == "systematic" local mdesc = "systematic equal-probability sampling" + cond("`sort'" != "", " sorted by `sort'", " in the frame order")
    if "`method'" == "pps" local mdesc "PPS without replacement (random systematic, gsample) on `pps'"
    if "`method'" == "ppssys" local mdesc = "systematic PPS on `pps'" + cond("`sort'" != "", ", frame sorted by `sort'", ", in the frame order")
    di as text _n "Sample draw ({bf:rtmsample draw}): `mdesc'"
    di as text "Frame: " as result strtrim(string(`Nframe', "%12.0fc")) as text " units in " as result `H' as text " strata; selected " as result strtrim(string(`nsel', "%12.0fc")) ///
        as text cond(`ncert' > 0, " (of which `ncert' with certainty)", "") "; reserve " as result strtrim(string(`nres', "%12.0fc"))
    di as text "Seed: " as result "`seed'" as text "  (pass seed(`seed') to repeat this draw)"
    di as text "{hline 108}"
    di as text %-24s "stratum" %9s "units" %12s "size" %7s "n" %6s "cert" %8s "reserve" %10s "pi min" %10s "pi max" %12s "sum w" %9s "HT size"
    di as text "{hline 108}"
    tempname T
    matrix `T' = J(`H', 8, .)
    tempvar lab
    _rtmsample_label `strata', touse(`touse') generate(`lab')
    local showmax = cond(`H' > 40, 25, `H')
    forvalues g = 1/`H' {
        quietly count if `touse' & `grp' == `g'
        local Ug = r(N)
        quietly summarize `size' if `touse' & `grp' == `g', meanonly
        local Sg = r(sum)
        quietly count if `touse' & `grp' == `g' & `hit'
        local ng = r(N)
        quietly count if `touse' & `grp' == `g' & `certv'
        local cg = r(N)
        quietly count if `touse' & `grp' == `g' & `rhit'
        local rg = r(N)
        quietly summarize `piv' if `touse' & `grp' == `g' & `hit', meanonly
        local pmin = r(min)
        local pmax = r(max)
        quietly summarize `generate'_w if `touse' & `grp' == `g' & `hit', meanonly
        local sw = r(sum)
        tempvar ht
        quietly gen double `ht' = `size' / `piv' if `touse' & `grp' == `g' & `hit'
        quietly summarize `ht', meanonly
        local hts = r(sum)
        drop `ht'
        quietly summarize `ord0' if `touse' & `grp' == `g', meanonly
        local lg = `lab'[`r(min)']
        if `g' <= `showmax' di as text %-24s abbrev("`lg'", 24) as result %9.0fc `Ug' %12.0fc `Sg' %7.0fc `ng' %6.0fc `cg' %8.0fc `rg' %10.4f `pmin' %10.4f `pmax' %12.1fc `sw' %9.0fc `hts'
        matrix `T'[`g', 1] = `Ug', `Sg', `ng', `cg', `rg', `pmin', `pmax', `sw'
    }
    if `showmax' < `H' di as text "  ... `=`H'-`showmax'' more strata (all `H' are in r(table))"
    di as text "{hline 108}"
    di as text "size: sum of the measure of size (1 per unit without pps()); sum w: sum of the design weights of the selected"
    di as text "units (equals the units for equal-probability methods); HT size: sum of size/pi over the selected units, which"
    di as text "equals the stratum's size for PPS; pi: inclusion probability. Reserve units have no probability or weight."
    if `nres' > 0 di as text "Replacing a nonresponding unit by a reserve unit is a biased procedure (UN 2008, paras 172, 178-179); prefer oversampling, and if reserves are used, say so in the report."
    matrix colnames `T' = units size n certainty reserve pi_min pi_max sum_w
    local rn ""
    forvalues g = 1/`H' {
        local rn "`rn' s`g'"
    }
    matrix rownames `T' = `rn'

    * ---- stored results and record ----
    return matrix table = `T'
    return scalar N_frame = `Nframe'
    return scalar n_selected = `nsel'
    return scalar n_reserve = `nres'
    return scalar n_certainty = `ncert'
    return scalar H = `H'
    return scalar seed = `seed'
    return local method "`method'"
    return local strata "`strata'"
    return local pps "`pps'"
    return local generate "`generate'"
    local cmd `"rtmsample draw `0'"'
    if "`seedgiven'" == "" local cmd `"`cmd' seed(`seed')"'
    return local cmdline `"`cmd'"'
    char _dta[rtm_draw_seed] "`seed'"
    _rtm_util record, step(draw) cmd(`"`cmd'"') var(`generate'_sel)
end

* ---- a number or a variable constant within strata, written to a per-observation variable ----
program define _rtmsample_pergroup
    syntax anything(name=spec), touse(varname) grp(varname) generate(name) what(string)
    capture confirm number `spec'
    if !_rc {
        if `spec' < 0 | `spec' != round(`spec') {
            di as err "`what' must be a non-negative whole number or a variable"
            exit 198
        }
        quietly gen double `generate' = `spec' if `touse'
        exit
    }
    capture confirm numeric variable `spec'
    if _rc {
        di as err "`what' must be a number or a numeric variable (constant within strata)"
        exit 198
    }
    tempvar mn mx
    quietly bysort `grp': egen double `mn' = min(`spec') if `touse'
    quietly bysort `grp': egen double `mx' = max(`spec') if `touse'
    quietly count if `touse' & (`mn' != `mx' | missing(`mn'))
    if r(N) > 0 {
        di as err "`what': variable `spec' must be non-missing and constant within each stratum; if it varies by stratum, give strata()"
        exit 459
    }
    quietly count if `touse' & (`mn' < 0 | `mn' != round(`mn'))
    if r(N) > 0 {
        di as err "`what': variable `spec' must hold non-negative whole numbers"
        exit 459
    }
    quietly gen double `generate' = `spec' if `touse'
end

* ---- certainty units for PPS: size x n / sum(size) > 1, iterated ----
program define _rtmsample_certainty
    syntax, elig(varname) grp(varname) n(varname) size(varname) cert(varname) nrem(name) ssum(name)
    tempvar ncert
    quietly gen double `nrem' = .
    quietly gen double `ssum' = .
    local changed 1
    local iter 0
    while `changed' & `iter' < 100 {
        local ++iter
        local changed 0
        capture drop `ncert'
        quietly bysort `grp': egen double `ncert' = total(cond(`elig' & `cert', 1, 0))
        quietly replace `nrem' = `n' - `ncert'
        capture drop `ssum'
        quietly bysort `grp': egen double `ssum' = total(cond(`elig' & !`cert', `size', 0))
        quietly count if `elig' & !`cert' & `nrem' > 0 & `size' * `nrem' / `ssum' > 1 + 1e-12
        if r(N) > 0 {
            local changed 1
            quietly replace `cert' = 1 if `elig' & !`cert' & `nrem' > 0 & `size' * `nrem' / `ssum' > 1 + 1e-12
        }
    }
end

* ---- gsample pass: SRS without replacement, or PPS without replacement (random systematic) ----
program define _rtmsample_gspass
    syntax, elig(varname) grp(varname) n(varname) size(varname) pps(integer) hit(varname) order(varname) pi(varname) cert(varname)
    tempvar nrem ssum cnt u
    if `pps' {
        _rtmsample_certainty, elig(`elig') grp(`grp') n(`n') size(`size') cert(`cert') nrem(`nrem') ssum(`ssum')
        quietly replace `hit' = 1 if `elig' & `cert'
        quietly replace `pi' = 1 if `elig' & `cert'
        quietly replace `order' = 0 if `elig' & `cert'
    }
    else {
        quietly gen double `nrem' = `n'
        quietly bysort `grp': egen double `ssum' = total(cond(`elig', 1, 0))
    }
    quietly count if `elig' & !`cert' & `nrem' > 0
    if r(N) > 0 {
        if `pps' gsample `nrem' [w=`size'] if `elig' & !`cert' & `nrem' > 0, wor strata(`grp') generate(`cnt')
        else gsample `nrem' if `elig' & !`cert' & `nrem' > 0, wor strata(`grp') generate(`cnt')
        quietly replace `hit' = 1 if `elig' & !`cert' & `cnt' == 1
        quietly replace `pi' = `nrem' * `size' / `ssum' if `elig' & !`cert'
        quietly gen double `u' = runiform()
        quietly bysort `grp' `hit' `cert' (`u'): replace `order' = _n if `elig' & `hit' & !`cert'
    }
end

* ---- systematic pass on the sorted frame: equal probability (size 1) or PPS ----
program define _rtmsample_syspass
    syntax, elig(varname) grp(varname) n(varname) size(varname) pps(integer) hit(varname) order(varname) pi(varname) cert(varname) ord0(varname) [sort(varlist)]
    tempvar nrem ssum T Tprev I RS hits
    if `pps' {
        _rtmsample_certainty, elig(`elig') grp(`grp') n(`n') size(`size') cert(`cert') nrem(`nrem') ssum(`ssum')
        quietly replace `hit' = 1 if `elig' & `cert'
        quietly replace `pi' = 1 if `elig' & `cert'
        quietly replace `order' = 0 if `elig' & `cert'
    }
    else {
        quietly gen double `nrem' = `n'
        quietly bysort `grp': egen double `ssum' = total(cond(`elig', 1, 0))
    }
    sort `grp' `sort' `ord0'
    quietly by `grp': gen double `T' = sum(cond(`elig' & !`cert', `size', 0))
    quietly gen double `Tprev' = `T' - cond(`elig' & !`cert', `size', 0)
    quietly gen double `I' = `ssum' / `nrem' if `nrem' > 0
    quietly gen double `RS' = .
    quietly by `grp': replace `RS' = `I' * (1 - runiform()) if _n == 1
    quietly by `grp': replace `RS' = `RS'[1]
    quietly gen double `hits' = floor((`T' - `RS') / `I') - floor((`Tprev' - `RS') / `I') if `elig' & !`cert' & `nrem' > 0
    quietly replace `hit' = 1 if `elig' & !`cert' & `hits' >= 1 & !missing(`hits')
    quietly replace `order' = floor((`T' - `RS') / `I') + 1 if `elig' & !`cert' & `hit'
    quietly replace `pi' = `nrem' * `size' / `ssum' if `elig' & !`cert' & `nrem' > 0
end

* the per-observation stratum label is built by _rtmsample_label.ado (its own file, shared with rtmframe)
