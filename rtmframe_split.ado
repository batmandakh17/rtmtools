*! rtmframe_split.ado  version 0.3.0  24oct2026  rtmtools
*! Split grid cells too large to list into k x k sub-cells with the measure of size re-aggregated
*! from the raster (R: sf and terra through rtm_cells.R). susogrdframe offers 2 x 2, 3 x 3 and
*! 4 x 4 splits; UN 2008 para 177 (PDF p. 82) and Grosh and Munoz 1996 (PDF p. 84) describe
*! segmenting large areas and selecting one segment at random for listing.
program define rtmframe_split, rclass
    version 16
    syntax using/, CELLs(numlist) [PARTS(integer 2) Layer(string) ID(name) RASTER(string) SAVing(string) CLEAR]
    local frame `"`using'"'
    capture confirm file `"`frame'"'
    if _rc {
        di as err `"frame file not found: `frame'"'
        exit 601
    }
    if !inlist(`parts', 2, 3, 4) {
        di as err "parts() must be 2, 3 or 4: a 2 x 2, 3 x 3 or 4 x 4 split"
        exit 198
    }
    if `"`raster'"' != "" {
        capture confirm file `"`raster'"'
        if _rc {
            di as err `"raster file not found: `raster'"'
            exit 601
        }
    }
    local id = cond("`id'" == "", "cell_id", "`id'")
    local cellcsv : subinstr local cells " " ",", all
    if c(changed) & "`clear'" == "" {
        di as err "no; the data in memory would be lost (the list of parts replaces them); add the clear option"
        exit 4
    }
    tempfile args status out
    tempname fh
    quietly file open `fh' using "`args'", write text replace
    file write `fh' "status=`status'" _n `"frame=`frame'"' _n `"layer=`layer'"' _n "idvar=`id'" _n "mode=split" _n ///
        "cells=`cellcsv'" _n "parts=`parts'" _n `"raster=`raster'"' _n "out=`out'" _n `"gpkg=`saving'"' _n
    file close `fh'
    _rtm_runr, script(rtm_cells.R) args("`args'") status("`status'") quietly
    use "`out'", clear
    quietly compress
    label variable cell "Cell that was split"
    label variable part "Sub-cell number (`parts' x `parts' grid)"
    label variable pop "Measure of size of the sub-cell (from the raster)"
    label variable area_km2 "Area of the sub-cell, km2"
    label variable lon "Centroid longitude (WGS84)"
    label variable lat "Centroid latitude (WGS84)"
    label variable lon_min "Bounding box west"
    label variable lat_min "Bounding box south"
    label variable lon_max "Bounding box east"
    label variable lat_max "Bounding box north"
    label data "Sub-cells of split grid cells (rtmframe split, rtmtools), `parts' x `parts'"
    quietly count
    local np = r(N)
    di as text _n "Split cells ({bf:rtmframe split}): " as result "`cells'" as text " into `parts' x `parts' sub-cells; " as result `np' as text " parts"
    quietly levelsof cell, local(cl)
    foreach c of local cl {
        quietly count if cell == `c'
        local np_c = r(N)
        quietly summarize pop if cell == `c', meanonly
        di as text "  cell " as result `c' as text ": " as result `np_c' as text " parts" cond(`"`raster'"' != "", ", measure of size " + strtrim(string(r(sum), "%12.0fc")) + " (min " + strtrim(string(r(min), "%12.0fc")) + ", max " + strtrim(string(r(max), "%12.0fc")) + ")", " (give raster() for their sizes)")
    }
    di as text "Select one part at random for listing, with probability proportional to its size, and multiply the area's weight accordingly (UN 2008 para 177)."
    if `"`saving'"' != "" di as text `"Sub-cell boundaries written to {browse "`saving'"}"'
    return scalar N_parts = `np'
    return scalar parts = `parts'
    return local cmdline `"rtmframe split using "`frame'", cells(`cells') parts(`parts')"'
end
