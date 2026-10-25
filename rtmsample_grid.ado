*! rtmsample_grid.ado  version 0.5.0  25oct2026  rtmtools
*! Spatially spread sample of grid cells or points from the frame in memory, without R: the units
*! are put in serpentine geographic order within each stratum (horizontal bands of the y
*! coordinate, the x direction alternating from band to band) and a systematic sample is taken
*! along that order, with equal probabilities or probability proportional to size (pps()).
*! This is the geographic implicit stratification of UN 2008 paras 77-79 (sort the frame
*! geographically, select systematically) applied to cells. It spreads the sample over the
*! territory; it is NOT the GRTS design of Stevens and Olsen 2004 (spsurvey): there is no reverse
*! hierarchical ordering (a contiguous subset of the sample is only approximately balanced), no
*! local neighbourhood variance estimator, and balance is along the bands rather than at every
*! scale. Replacements (reserve()) are the next units in the same order within the stratum.
*! Inclusion probabilities, design weights, order, reserve ranks and the seed are written as in
*! rtmsample draw, which does the draw (method systematic or ppssys, sorted by the serpentine key).
program define rtmsample_grid, rclass
    version 16
    syntax [if] [in], N(string) GENerate(name) XY(varlist min=2 max=2 numeric) [STRata(varlist) PPS(varname numeric) ///
        BANDS(integer 0) BANDwidth(real 0) RESERVE(string) SEED(string) ID(varlist) REPLACE]
    marksample touse, novarlist
    markout `touse' `xy'
    if "`strata'" != "" markout `touse' `strata', strok
    if `bands' < 0 | `bandwidth' < 0 {
        di as err "bands() is the number of horizontal bands (default: about the square root of the units per stratum), bandwidth() their height in the coordinates' units; give one or neither"
        exit 198
    }
    if `bands' > 0 & `bandwidth' > 0 {
        di as err "give bands() or bandwidth(), not both"
        exit 198
    }
    local xv : word 1 of `xy'
    local yv : word 2 of `xy'
    quietly count if `touse'
    if r(N) == 0 {
        di as err "no observations in the frame"
        exit 2000
    }
    * ---- the serpentine key within strata ----
    tempvar grp band ymin ymax bw key U
    if "`strata'" != "" quietly egen long `grp' = group(`strata') if `touse'
    else quietly gen long `grp' = 1 if `touse'
    quietly bysort `grp': egen double `ymin' = min(cond(`touse', `yv', .))
    quietly bysort `grp': egen double `ymax' = max(cond(`touse', `yv', .))
    quietly bysort `grp': egen long `U' = total(cond(`touse', 1, 0))
    if `bandwidth' > 0 quietly gen double `bw' = `bandwidth'
    else {
        if `bands' > 0 quietly gen double `bw' = (`ymax' - `ymin') / `bands'
        else quietly gen double `bw' = (`ymax' - `ymin') / max(1, round(sqrt(`U')))
    }
    quietly replace `bw' = 1 if `bw' <= 0 | missing(`bw')
    quietly gen long `band' = floor((`yv' - `ymin') / `bw') if `touse'
    * the key: band number, then x ascending in even bands and descending in odd bands
    tempvar xmin xmax
    quietly bysort `grp': egen double `xmin' = min(cond(`touse', `xv', .))
    quietly bysort `grp': egen double `xmax' = max(cond(`touse', `xv', .))
    quietly gen double `key' = `band' * (`xmax' - `xmin' + 1) + cond(mod(`band', 2) == 0, `xv' - `xmin', `xmax' - `xv') if `touse'
    quietly gen double _rtmx_serp = `key' if `touse'
    label variable _rtmx_serp "Serpentine geographic order (rtmsample grid)"
    quietly summarize `band' if `touse', meanonly
    local nb = r(max) + 1
    * ---- the draw ----
    local method = cond("`pps'" != "", "ppssys", "systematic")
    local ppsopt = cond("`pps'" != "", "pps(`pps')", "")
    local resopt = cond("`reserve'" != "", "reserve(`reserve')", "")
    local seedopt = cond("`seed'" != "", "seed(`seed')", "")
    local idopt = cond("`id'" != "", "id(`id')", "")
    local stropt = cond("`strata'" != "", "strata(`strata')", "")
    capture noisily rtmsample_draw if `touse', n(`n') generate(`generate') `stropt' `ppsopt' method(`method') sort(_rtmx_serp) `resopt' `seedopt' `idopt' xy(`xy') `replace'
    local rc = _rc
    if `rc' {
        capture drop _rtmx_serp
        exit `rc'
    }
    local seedused = r(seed)
    di as text "Serpentine order: " as result `nb' as text " bands of height " as result %9.4g `=`bw'[1]' as text " in the coordinates' units, x alternating by band; systematic " ///
        cond("`pps'" != "", "PPS", "equal-probability") " selection along it (UN 2008 paras 77-79). Not GRTS: see the help for what differs."
    * keep the draw's results, add the grid settings
    return add
    return scalar bands = `nb'
    return local order "serpentine"
    local cmd `"rtmsample grid `0'"'
    if "`seed'" == "" local cmd `"`cmd' seed(`seedused')"'
    return local cmdline `"`cmd'"'
    char _dta[rtm_draw] `"`cmd'"'
    char `generate'_sel[rtm_cmd] `"`cmd'"'
    capture _rtm_export setting, key(order) value("serpentine, `nb' bands") source("UN 2008 paras 77-79 (geographic sort, systematic selection); not GRTS (Stevens and Olsen 2004)")
    capture _rtm_export setting, key(xy) value("`xy'")
    quietly drop _rtmx_serp
end
