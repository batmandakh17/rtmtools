*! rtmframe_replace.ado  version 0.3.0  24oct2026  rtmtools
*! Replacement candidates for grid cells that cannot be surveyed (R: sf through rtm_cells.R):
*! the cells adjacent to each named cell, in the same stratum, not already selected or excluded,
*! ranked by the distance between centroids, with their measure of size and coordinates. This is
*! the rule of the Survey Solutions grid replacement application (susogrdframe README); UN 2008
*! paras 172 and 178 (PDF pp. 81-82) warn that substituting an area is a biased procedure, so the
*! replacement should be documented and kept to areas that truly cannot be surveyed.
program define rtmframe_replace, rclass
    version 16
    syntax using/, CELLs(numlist) [Layer(string) ID(name) EXclude(numlist) SELected(varname numeric) ///
        ADJacency(string) SAVing(string) CLEAR]
    local frame `"`using'"'
    capture confirm file `"`frame'"'
    if _rc {
        di as err `"frame file not found: `frame'"'
        exit 601
    }
    local id = cond("`id'" == "", "cell_id", "`id'")
    local adjacency = cond("`adjacency'" == "", "queen", lower("`adjacency'"))
    if !inlist("`adjacency'", "queen", "rook") {
        di as err "adjacency() must be queen (cells sharing an edge or a corner) or rook (an edge)"
        exit 198
    }
    local excl "`exclude'"
    if "`selected'" != "" {
        capture confirm variable `id'
        if _rc {
            di as err "selected() needs the frame in memory with the identifier `id'"
            exit 111
        }
        quietly levelsof `id' if `selected' == 1, local(sel) separate(,)
        local excl "`excl' `sel'"
    }
    local excl : subinstr local excl " " ",", all
    local excl : subinstr local excl ",," ",", all
    if substr("`excl'", 1, 1) == "," local excl = substr("`excl'", 2, .)
    local cellcsv : subinstr local cells " " ",", all
    if c(changed) & "`clear'" == "" {
        di as err "no; the data in memory would be lost (the candidate list replaces them); add the clear option"
        exit 4
    }
    tempfile args status out
    tempname fh
    quietly file open `fh' using "`args'", write text replace
    file write `fh' "status=`status'" _n `"frame=`frame'"' _n `"layer=`layer'"' _n "idvar=`id'" _n "mode=replace" _n ///
        "cells=`cellcsv'" _n "exclude=`excl'" _n "adjacency=`adjacency'" _n "out=`out'" _n `"gpkg=`saving'"' _n
    file close `fh'
    _rtm_runr, script(rtm_cells.R) args("`args'") status("`status'") quietly
    local msg `"`r(message)'"'
    use "`out'", clear
    quietly compress
    label variable cell "Cell to be replaced"
    label variable candidate "Candidate replacement cell (adjacent, same stratum)"
    label variable rank "Rank by distance between centroids (1 = nearest)"
    label variable dist_km "Distance between centroids, km"
    label variable stratum "Stratum"
    label variable pop "Measure of size of the candidate"
    label variable area_km2 "Area of the candidate, km2"
    label variable lon "Centroid longitude (WGS84)"
    label variable lat "Centroid latitude (WGS84)"
    label variable lon_min "Bounding box west"
    label variable lat_min "Bounding box south"
    label variable lon_max "Bounding box east"
    label variable lat_max "Bounding box north"
    label data "Replacement candidates (rtmframe replace, rtmtools), adjacency `adjacency'"
    quietly count if !missing(candidate)
    local ncand = r(N)
    quietly levelsof cell, local(cl)
    di as text _n "Replacement candidates ({bf:rtmframe replace}): `adjacency' adjacency, same stratum" ///
        cond("`excl'" != "", ", excluding the cells listed or selected", "")
    foreach c of local cl {
        quietly count if cell == `c' & !missing(candidate)
        if r(N) == 0 di as text "  cell " as result `c' as text ": no adjacent cell available in its stratum"
        else {
            di as text "  cell " as result `c' as text ": " _c
            quietly levelsof candidate if cell == `c', local(cands)
            local line ""
            forvalues k = 1/`=r(r)' {
                quietly summarize candidate if cell == `c' & rank == `k', meanonly
                local line "`line' `=r(min)'"
            }
            di as result "`line'" as text " (nearest first)"
        }
    }
    di as text "Each row: candidate, rank, distance, measure of size, centroid and bounding box for the field team."
    di as text "Substituting an area is a biased procedure (UN 2008 paras 172, 178); record every replacement in the survey report."
    if `"`saving'"' != "" di as text `"Candidates and the cells to replace written to {browse "`saving'"}"'
    local ncl : word count `cl'
    return scalar N_cells = `ncl'
    return scalar N_candidates = `ncand'
    return local adjacency "`adjacency'"
    return local cmdline `"rtmframe replace using "`frame'", cells(`cells') adjacency(`adjacency')"'
end
