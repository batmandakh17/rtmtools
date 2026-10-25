*! rtmframe_replace.ado  version 0.5.0  25oct2026  rtmtools
*! Replacement candidates for grid cells that cannot be surveyed, without R: for each cell named
*! in cells(), the adjacent cells (queen: sharing a side or a corner; rook: a side) of the same
*! stratum that are not selected, not excluded and not themselves to be replaced, ranked by the
*! distance between cell centres and then by population; when no adjacent cell qualifies, the
*! ring of cells two steps away is tried and the candidate is flagged. The frame in memory is the
*! cell frame of rtmframe grid (cell_id, col, row, x, y, stratum, pop). Replacing a unit is a
*! substitution, which UN 2008 (paras 172, 178-179) calls biased: record every replacement and say
*! so in the report; the export keeps the candidate list. The rules follow the Survey Solutions
*! toolbox (susogrdframe, Wild n.d.-d) for comparison: adjacent, same stratum.
program define rtmframe_replace, rclass
    version 16
    syntax , CELLs(numlist integer >=1) [ADJacency(string) SELected(varname numeric) EXclude(varname numeric) ///
        NCAND(integer 3) GENerate(name) SAVing(string) REPLACE]
    foreach v in cell_id col row x y stratum pop {
        capture confirm variable `v'
        if _rc {
            di as err "the frame in memory must be a grid frame from rtmframe grid (variable `v' missing)"
            exit 111
        }
    }
    local adjacency = cond("`adjacency'" == "", "queen", lower("`adjacency'"))
    if !inlist("`adjacency'", "queen", "rook") {
        di as err "adjacency() must be queen (sides and corners) or rook (sides)"
        exit 198
    }
    if `ncand' < 1 {
        di as err "ncand() must be 1 or more"
        exit 198
    }
    if "`generate'" != "" {
        _rtm_util newvar `generate'_for, `replace'
        _rtm_util newvar `generate'_rank, `replace'
        quietly gen long `generate'_for = .
        quietly gen long `generate'_rank = .
    }
    tempvar tocell
    quietly gen byte `tocell' = 0
    foreach c of local cells {
        quietly count if cell_id == `c'
        if r(N) == 0 {
            di as err "cell `c' is not in the frame"
            exit 459
        }
        quietly replace `tocell' = 1 if cell_id == `c'
    }
    * candidates: every pair (cell to replace, other cell of the same stratum) within two steps
    capture frame drop _rtmx_rp
    frame create _rtmx_rp str32 unit_id str32 candidate_id double(rank distance) str32 stratum str16 adjacency
    local ncells : word count `cells'
    local nfound 0
    local nring2 0
    tempvar d dcol drow ok ring
    quietly gen double `d' = .
    quietly gen long `dcol' = .
    quietly gen long `drow' = .
    quietly gen byte `ok' = 0
    quietly gen byte `ring' = .
    di as text _n "Replacement candidates ({bf:rtmframe replace}): `adjacency' adjacency, same stratum, up to `ncand' per cell"
    di as text "{hline 84}"
    di as text %-12s "cell" %-10s "stratum" %6s "rank" %12s "candidate" %12s "distance" %12s "population" %10s "ring"
    di as text "{hline 84}"
    foreach c of local cells {
        quietly summarize col if cell_id == `c', meanonly
        local c0 = r(mean)
        quietly summarize row if cell_id == `c', meanonly
        local r0 = r(mean)
        quietly summarize x if cell_id == `c', meanonly
        local x0 = r(mean)
        quietly summarize y if cell_id == `c', meanonly
        local y0 = r(mean)
        quietly summarize stratum if cell_id == `c', meanonly
        local s0 = r(mean)
        quietly replace `dcol' = abs(col - `c0')
        quietly replace `drow' = abs(row - `r0')
        quietly replace `d' = sqrt((x - `x0')^2 + (y - `y0')^2)
        quietly replace `ok' = (stratum == `s0') & (cell_id != `c') & !`tocell'
        if "`selected'" != "" quietly replace `ok' = `ok' & `selected' != 1
        if "`exclude'" != "" quietly replace `ok' = `ok' & `exclude' != 1
        if "`adjacency'" == "queen" quietly replace `ring' = cond(max(`dcol', `drow') == 1, 1, cond(max(`dcol', `drow') == 2, 2, .))
        else quietly replace `ring' = cond(`dcol' + `drow' == 1, 1, cond(`dcol' + `drow' == 2, 2, .))
        quietly count if `ok' & `ring' == 1
        local use = cond(r(N) > 0, 1, 2)
        if `use' == 2 local ++nring2
        tempvar key
        quietly gen double `key' = cond(`ok' & `ring' == `use', `d' - pop * 1e-9, .)
        sort `key'
        local k 0
        local vl : value label stratum
        if "`vl'" != "" local st : label `vl' `s0'
        else local st "`s0'"
        forvalues i = 1/`=_N' {
            if missing(`key'[`i']) continue, break
            if `k' >= `ncand' continue, break
            local ++k
            local cid = cell_id[`i']
            di as text %-12s "`c'" %-10s abbrev("`st'", 10) as result %6.0f `k' %12.0f `cid' %12.0f `d'[`i'] %12.0fc pop[`i'] %10.0f `use'
            frame post _rtmx_rp ("`c'") ("`cid'") (`k') (`d'[`i']) ("`st'") ("`adjacency' ring `use'")
            if "`generate'" != "" {
                quietly replace `generate'_for = `c' if cell_id == `cid' & missing(`generate'_for)
                quietly replace `generate'_rank = `k' if cell_id == `cid' & `generate'_for == `c'
            }
        }
        if `k' == 0 di as text %-12s "`c'" %-10s abbrev("`st'", 10) as txt "  no candidate within two cells in the same stratum"
        else local ++nfound
        drop `key'
    }
    sort cell_id
    di as text "{hline 84}"
    di as text "ring 1: adjacent; ring 2: two cells away, used only when no adjacent cell qualifies. A replacement is a substitution"
    di as text "(UN 2008 paras 172, 178-179): record which cell replaced which, and say so in the report."
    if "`generate'" != "" {
        label variable `generate'_for "Cell this cell can replace (first match)"
        label variable `generate'_rank "Rank among that cell's candidates"
    }
    if `"`saving'"' != "" {
        frame _rtmx_rp: quietly save `"`saving'"', `replace'
        di as text `"Candidates saved to `saving'"'
    }
    return scalar n_cells = `ncells'
    return scalar n_with_candidates = `nfound'
    return scalar n_ring2 = `nring2'
    return local adjacency "`adjacency'"
    local cmd `"rtmframe replace `0'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(replace) cmd(`"`cmd'"')
    capture _rtm_export table, name(replacements) frame(_rtmx_rp)
    capture _rtm_export setting, key(cells) value("`cells'")
    capture _rtm_export setting, key(adjacency) value("`adjacency'") source("susogrdframe rules (Wild n.d.-d); UN 2008 paras 172, 178-179 on substitution")
    capture _rtm_export setting, key(ncand) value("`ncand'")
    if "`selected'" != "" capture _rtm_export setting, key(selected) value("`selected'")
    if "`exclude'" != "" capture _rtm_export setting, key(exclude) value("`exclude'")
end
