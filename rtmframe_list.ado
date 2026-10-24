*! rtmframe_list.ado  version 0.3.0  24oct2026  rtmtools
*! Checks and flags for a list frame of areas (census enumeration areas or similar): unique
*! identifiers, missing or non-positive measures of size, units too small to sample (combined
*! with the following units in the sort order within the stratum) or too large to list (number
*! of segments suggested), excluded units, and consistency checks on population counts.
*! Sources: UN 2008 section 4.1.2 (a frame must be complete, accurate and up to date; PDF p. 88)
*! and ch. 4; Grosh and Munoz 1996, PDF pp. 80-81 (checks on the PSU list: totals, masculinity
*! ratio 80-120 percent, 3-10 persons per household, PSUs under 30 households appended to a
*! neighbour) and p. 84 (segmenting PSUs over 300 households).
program define rtmframe_list, rclass
    version 16
    syntax [if] [in], ID(varlist) [SIZE(varname numeric) STRata(varlist) EXclude(varname numeric) ///
        MINsize(real 0) MAXsize(real 0) MERGE(name) SORT(varlist) PERsons(varname numeric) ///
        MALES(varname numeric) FEMales(varname numeric) REPLACE]
    marksample touse, novarlist
    if "`strata'" != "" markout `touse' `strata', strok
    if `minsize' < 0 | `maxsize' < 0 | (`maxsize' > 0 & `maxsize' <= `minsize') {
        di as err "minsize() and maxsize() must be non-negative, with maxsize() above minsize()"
        exit 198
    }
    if "`merge'" != "" & "`size'" == "" {
        di as err "merge() needs size(): small units are combined until their sizes reach minsize()"
        exit 198
    }
    if "`merge'" != "" & `minsize' <= 0 {
        di as err "merge() needs minsize(), the smallest size a unit may have"
        exit 198
    }
    if ("`males'" != "") != ("`females'" != "") {
        di as err "give males() and females() together"
        exit 198
    }
    capture confirm variable frame_ok
    if !_rc & "`replace'" == "" {
        di as err "the frame_* flag variables exist from an earlier run; add the replace option to overwrite them"
        exit 110
    }
    foreach v in ok dup badsize small large segments excl {
        _rtm_util newvar frame_`v', `replace'
    }
    if "`merge'" != "" {
        _rtm_util newvar `merge', `replace'
        _rtm_util newvar `merge'_size, `replace'
    }
    quietly count if `touse'
    local N = r(N)
    if `N' == 0 {
        di as err "no observations"
        exit 2000
    }
    tempvar ord0 grp
    quietly gen double `ord0' = _n
    if "`strata'" != "" quietly egen long `grp' = group(`strata') if `touse'
    else quietly gen long `grp' = 1 if `touse'

    * ---- duplicates ----
    tempvar ndup
    quietly bysort `touse' `id': gen long `ndup' = _N if `touse'
    quietly gen byte frame_dup = (`ndup' > 1) if `touse'
    quietly count if frame_dup == 1
    local n_dup = r(N)
    * ---- size ----
    quietly gen byte frame_badsize = 0 if `touse'
    if "`size'" != "" quietly replace frame_badsize = (missing(`size') | `size' <= 0) if `touse'
    quietly count if frame_badsize == 1
    local n_bad = r(N)
    quietly gen byte frame_small = 0 if `touse'
    quietly gen byte frame_large = 0 if `touse'
    quietly gen double frame_segments = . if `touse'
    if "`size'" != "" & `minsize' > 0 quietly replace frame_small = (`size' < `minsize') if `touse' & frame_badsize == 0
    if "`size'" != "" & `maxsize' > 0 {
        quietly replace frame_large = (`size' > `maxsize') if `touse' & frame_badsize == 0
        quietly replace frame_segments = max(2, round(`size' / `maxsize')) if frame_large == 1
    }
    quietly count if frame_small == 1
    local n_small = r(N)
    quietly count if frame_large == 1
    local n_large = r(N)
    * ---- exclusions ----
    quietly gen byte frame_excl = 0 if `touse'
    if "`exclude'" != "" quietly replace frame_excl = (`exclude' == 1) if `touse'
    quietly count if frame_excl == 1
    local n_excl = r(N)
    quietly gen byte frame_ok = (frame_dup == 0 & frame_badsize == 0 & frame_excl == 0) if `touse'
    quietly count if frame_ok == 1
    local n_ok = r(N)
    label variable frame_ok "Usable frame unit (unique id, positive size, not excluded)"
    label variable frame_dup "Identifier not unique"
    label variable frame_badsize "Measure of size missing or not positive"
    label variable frame_small "Size below minsize()"
    label variable frame_large "Size above maxsize()"
    label variable frame_segments "Segments suggested for a large unit (size / maxsize, rounded)"
    label variable frame_excl "Excluded from coverage"

    * ---- population checks (Grosh and Munoz 1996) ----
    local n_hhsize .
    local n_sexsum .
    local n_masc .
    if "`persons'" != "" & "`size'" != "" {
        tempvar pph
        quietly gen double `pph' = `persons' / `size' if `touse' & `size' > 0
        quietly count if `touse' & (`pph' < 3 | `pph' > 10) & !missing(`pph')
        local n_hhsize = r(N)
    }
    if "`males'" != "" {
        if "`persons'" != "" {
            quietly count if `touse' & abs(`males' + `females' - `persons') > 0.5
            local n_sexsum = r(N)
        }
        tempvar masc
        quietly gen double `masc' = 100 * `males' / `females' if `touse' & `females' > 0
        quietly count if `touse' & (`masc' < 80 | `masc' > 120) & !missing(`masc')
        local n_masc = r(N)
    }

    * ---- merge small units with the following units in the sort order within strata ----
    local n_merged 0
    local n_groups .
    if "`merge'" != "" {
        tempvar s cum closed gid
        sort `grp' `sort' `ord0'
        quietly gen double `s' = cond(frame_ok & `touse', `size', 0)
        quietly gen long `gid' = .
        quietly gen double `cum' = .
        * walk through each stratum: open a combined unit, add units until the size reaches minsize
        quietly by `grp': replace `cum' = cond(_n == 1, `s', cond(`cum'[_n-1] >= `minsize', `s', `cum'[_n-1] + `s'))
        quietly by `grp': replace `gid' = cond(_n == 1, 1, cond(`cum'[_n-1] >= `minsize', `gid'[_n-1] + 1, `gid'[_n-1]))
        * a last combined unit that stays below minsize joins the previous one
        tempvar gsize last
        quietly bysort `grp' `gid': egen double `gsize' = total(`s')
        quietly bysort `grp' (`gid'): gen byte `last' = (`gid' == `gid'[_N])
        quietly replace `gid' = `gid' - 1 if `last' & `gsize' < `minsize' & `gid' > 1
        capture drop `gsize'
        quietly bysort `grp' `gid': egen double `gsize' = total(`s')
        quietly bysort `grp' `gid' (`ord0'): gen `merge' = `id'[1] if `touse' & frame_ok
        local idtype : type `id'
        quietly gen double `merge'_size = `gsize' if `touse' & frame_ok
        quietly count if `touse' & frame_ok & `merge' != `id'
        local n_merged = r(N)
        tempvar tagg
        quietly egen byte `tagg' = tag(`grp' `gid') if `touse' & frame_ok
        quietly count if `tagg' == 1
        local n_groups = r(N)
        label variable `merge' "Combined frame unit (id of its first unit), sizes reaching minsize()"
        label variable `merge'_size "Size of the combined unit"
        sort `ord0'
    }
    sort `ord0'

    * ---- report ----
    quietly summarize `grp' if `touse', meanonly
    local H = r(max)
    di as text _n "Frame checks ({bf:rtmframe list}): " as result `N' as text " units" cond("`strata'" != "", " in `H' strata", "") ///
        cond("`size'" != "", ", measure of size `size'", "")
    di as text "{hline 96}"
    di as text %-46s "Check" %12s "units" "  what to do"
    di as text "{hline 96}"
    di as text %-46s "duplicate identifiers (`id')" as result %12.0fc `n_dup' as text "  " cond(`n_dup' > 0, "make the identifier unique", "")
    if "`size'" != "" {
        di as text %-46s "size missing or not positive" as result %12.0fc `n_bad' as text "  " cond(`n_bad' > 0, "fix or exclude; PPS needs sizes", "")
        if `minsize' > 0 di as text %-46s "size below minsize() = `minsize'" as result %12.0fc `n_small' as text "  " cond(`n_small' > 0, cond("`merge'" != "", "combined into `merge'", "combine with neighbours (merge())"), "")
        if `maxsize' > 0 di as text %-46s "size above maxsize() = `maxsize'" as result %12.0fc `n_large' as text "  " cond(`n_large' > 0, "segment before listing (frame_segments)", "")
    }
    if "`exclude'" != "" di as text %-46s "excluded (`exclude' = 1)" as result %12.0fc `n_excl' as text "  " cond(`n_excl' > 0, "state the exclusion in the report", "")
    if `n_hhsize' < . di as text %-46s "persons per household outside 3-10" as result %12.0fc `n_hhsize' as text "  " cond(`n_hhsize' > 0, "check the counts", "")
    if `n_sexsum' < . di as text %-46s "males + females differs from persons" as result %12.0fc `n_sexsum' as text "  " cond(`n_sexsum' > 0, "check the counts", "")
    if `n_masc' < . di as text %-46s "masculinity ratio outside 80-120 percent" as result %12.0fc `n_masc' as text "  " cond(`n_masc' > 0, "check the counts", "")
    di as text %-46s "usable units (frame_ok = 1)" as result %12.0fc `n_ok'
    if "`merge'" != "" di as text %-46s "combined units after merge()" as result %12.0fc `n_groups' as text "  `n_merged' units joined another"
    di as text "{hline 96}"
    tempname T
    matrix `T' = J(`H', 6, .)
    if "`strata'" != "" | "`size'" != "" {
        di as text %-24s "stratum" %9s "units" %9s "usable" %14s "size total" %10s "min" %10s "median" %10s "max"
        di as text "{hline 96}"
        tempvar lab
        _rtmsample_label `strata', touse(`touse') generate(`lab')
        forvalues g = 1/`H' {
            quietly count if `touse' & `grp' == `g'
            local Ug = r(N)
            quietly count if `touse' & `grp' == `g' & frame_ok
            local Og = r(N)
            local Sg .
            local mn .
            local md .
            local mx .
            if "`size'" != "" {
                quietly summarize `size' if `touse' & `grp' == `g' & frame_ok, detail
                local Sg = r(sum)
                local mn = r(min)
                local md = r(p50)
                local mx = r(max)
            }
            quietly summarize `ord0' if `touse' & `grp' == `g', meanonly
            local lg = `lab'[`r(min)']
            if `g' <= 40 di as text %-24s abbrev("`lg'", 24) as result %9.0fc `Ug' %9.0fc `Og' %14.0fc `Sg' %10.0fc `mn' %10.0fc `md' %10.0fc `mx'
            matrix `T'[`g', 1] = `Ug', `Og', `Sg', `mn', `md', `mx'
        }
        if `H' > 40 di as text "  ... (all `H' strata are in r(table))"
        di as text "{hline 96}"
    }
    matrix colnames `T' = units usable size_total size_min size_p50 size_max
    local rn ""
    forvalues g = 1/`H' {
        local rn "`rn' s`g'"
    }
    matrix rownames `T' = `rn'
    return matrix table = `T'
    return scalar N = `N'
    return scalar N_ok = `n_ok'
    return scalar n_dup = `n_dup'
    return scalar n_badsize = `n_bad'
    return scalar n_small = `n_small'
    return scalar n_large = `n_large'
    return scalar n_excluded = `n_excl'
    return scalar n_hhsize_flag = `n_hhsize'
    return scalar n_sexsum_flag = `n_sexsum'
    return scalar n_masc_flag = `n_masc'
    return scalar n_merged = `n_merged'
    return scalar n_combined_units = `n_groups'
    return scalar H = `H'
    local cmd `"rtmframe list `0'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(frame) cmd(`"`cmd'"') var(frame_ok)
end
