*! rtmframe_split.ado  version 0.5.0  25oct2026  rtmtools
*! Split large grid cells into parts x parts sub-cells, without R, from the pixel table written
*! by rtmframe grid, savingpixels(): each pixel inside the boundaries is assigned to the sub-cell
*! holding its centre, and the sub-cells' populations are the sums of their pixels. The frame in
*! memory must be the grid frame (for the cell size and origin); the parts are listed, saved with
*! saving(), and exported as frame units; with clear they replace the data in memory. Splitting a
*! selected cell before listing it is the standard segment design of UN 2008 (paras 138-140,
*! pp. 74-75): one part is then chosen at random with equal probability (rtmsample draw, n(1)
*! strata(cell_id)) and its probability multiplies the cell's. The rules follow the Survey
*! Solutions toolbox (susogrdframe, 2 x 2, 3 x 3 or 4 x 4 splits) for comparison.
program define rtmframe_split, rclass
    version 16
    syntax , CELLs(numlist integer >=1) PARTS(integer) PIXels(string) [SAVing(string) REPLACE CLEAR]
    if `parts' < 2 | `parts' > 10 {
        di as err "parts() is the number of sub-cells per side, between 2 and 10"
        exit 198
    }
    foreach v in cell_id col row x y pop {
        capture confirm variable `v'
        if _rc {
            di as err "the frame in memory must be a grid frame from rtmframe grid (variable `v' missing)"
            exit 111
        }
    }
    local cs : char _dta[rtm_grid_cellsize]
    local xll : char _dta[rtm_grid_xll]
    local yll : char _dta[rtm_grid_yll]
    if "`cs'" == "" | "`xll'" == "" | "`yll'" == "" {
        di as err "the frame in memory carries no grid characteristics (rtm_grid_cellsize); rebuild it with rtmframe grid"
        exit 459
    }
    capture confirm file `"`pixels'"'
    if _rc {
        di as err `"pixel file not found: `pixels' (write it with rtmframe grid, savingpixels())"'
        exit 601
    }
    if c(changed) & "`clear'" != "" {
        di as err "the data in memory have unsaved changes; save them before clear"
        exit 4
    }
    foreach c of local cells {
        quietly count if cell_id == `c'
        if r(N) == 0 {
            di as err "cell `c' is not in the frame"
            exit 459
        }
    }
    local sub = `cs' / `parts'
    tempfile cellinfo
    preserve
    quietly keep cell_id col row x y pop
    rename (x y pop) (cell_x cell_y cell_pop)
    quietly save "`cellinfo'"
    restore
    preserve
    quietly use `"`pixels'"', clear
    foreach v in cell_id x y value {
        capture confirm variable `v'
        if _rc {
            di as err "the pixel file must have cell_id, x, y and value (written by rtmframe grid, savingpixels())"
            exit 111
        }
    }
    tempvar keep
    quietly gen byte `keep' = 0
    foreach c of local cells {
        quietly replace `keep' = 1 if cell_id == `c'
    }
    quietly keep if `keep'
    quietly count
    if r(N) == 0 {
        di as err "no pixel of the listed cells in the pixel file"
        exit 459
    }
    quietly merge m:1 cell_id using "`cellinfo'", keep(match) nogenerate
    * sub-cell of each pixel: from the cell's south-west corner
    quietly gen long pcol = floor((x - (`xll' + col * `cs')) / `sub')
    quietly gen long prow = floor((y - (`yll' + row * `cs')) / `sub')
    quietly replace pcol = min(max(pcol, 0), `parts' - 1)
    quietly replace prow = min(max(prow, 0), `parts' - 1)
    quietly gen long part = prow * `parts' + pcol + 1
    quietly collapse (sum) pop = value (count) npix = value (first) col row cell_pop, by(cell_id part pcol prow)
    quietly gen double x = `xll' + col * `cs' + (pcol + 0.5) * `sub'
    quietly gen double y = `yll' + row * `cs' + (prow + 0.5) * `sub'
    quietly gen double share = pop / cell_pop
    quietly gen str32 part_id = string(cell_id) + "-" + string(part)
    label variable cell_id "Cell that was split"
    label variable part "Part number (row-major from the south-west)"
    label variable part_id "Identifier of the part (cell-part)"
    label variable x "Centre x of the part"
    label variable y "Centre y of the part"
    label variable pop "Population of the part (pixels inside the boundaries)"
    label variable npix "Pixels of the part inside the boundaries"
    label variable share "Share of the cell's population"
    order cell_id part part_id pcol prow x y pop npix share
    sort cell_id part
    di as text _n "Cell splits ({bf:rtmframe split}): `parts' x `parts' parts of " as result `sub' as text " m from the pixels of `pixels'"
    di as text "{hline 72}"
    di as text %-10s "cell" %6s "part" %12s "x" %12s "y" %12s "population" %8s "share" %8s "pixels"
    di as text "{hline 72}"
    forvalues i = 1/`=_N' {
        if `i' <= 60 di as text %-10s string(cell_id[`i']) as result %6.0f part[`i'] %12.0f x[`i'] %12.0f y[`i'] %12.0fc pop[`i'] %8.3f share[`i'] %8.0f npix[`i']
    }
    if _N > 60 di as text "  ... (`=_N' parts; all are in the saved file)"
    di as text "{hline 72}"
    local nparts = _N
    tempvar chk
    quietly bysort cell_id: egen double `chk' = total(pop)
    quietly count if abs(`chk' - cell_pop) > 1e-6 * cell_pop
    if r(N) > 0 di as txt "note: for " r(N) " parts the parts' populations do not add to the cell's (pixels on the cell edge or outside the boundaries)"
    local nbad = r(N)
    drop `chk'
    if `"`saving'"' != "" {
        quietly save `"`saving'"', `replace'
        di as text `"Parts saved to `saving'"'
    }
    * export
    capture frame drop _rtmx_fu
    frame put part_id cell_id pop x y, into(_rtmx_fu)
    frame _rtmx_fu {
        rename (part_id pop) (unit_id size)
        quietly gen str32 unit = string(cell_id)
        quietly gen str32 stratum = ""
        quietly gen str32 flag = ""
        drop cell_id
        order unit_id stratum unit size x y flag
    }
    capture _rtm_export table, name(frame_units) frame(_rtmx_fu)
    if "`clear'" != "" {
        restore, not
    }
    else restore
    return scalar n_parts = `nparts'
    return scalar parts = `parts'
    return scalar n_mismatch = `nbad'
    return scalar partsize = `sub'
    local cmd `"rtmframe split `0'"'
    return local cmdline `"`cmd'"'
    _rtm_util record, step(split) cmd(`"`cmd'"')
    capture _rtm_export setting, key(cells) value("`cells'")
    capture _rtm_export setting, key(parts) value("`parts' x `parts'") source("UN 2008 paras 138-140 (standard segments); susogrdframe (Wild n.d.-d)")
    capture _rtm_export setting, key(pixels) value(`"`pixels'"')
end
