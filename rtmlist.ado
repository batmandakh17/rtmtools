*! rtmlist.ado  version 0.5.0  25oct2026  rtmtools
*! Dispatcher: rtmlist prepare | import (listing support for the selected areas)
*! Every run is exported (manifest, tables, Excel display, dashboard index) by _rtm_export.
program define rtmlist, rclass
    version 16
    gettoken sub 0 : 0, parse(" ,")
    local sub = lower(trim("`sub'"))
    if "`sub'" == "" {
        di as err "rtmlist: a subcommand is required: prepare or import"
        di as err "see {help rtmlist}"
        exit 198
    }
    local full ""
    foreach s in prepare import {
        if strpos("`s'", "`sub'") == 1 local full "`full' `s'"
    }
    local full = trim("`full'")
    if wordcount("`full'") != 1 {
        di as err "rtmlist: unknown subcommand {bf:`sub'}; use prepare or import"
        exit 198
    }
    capture _rtm_export start, workflow(listing) step(`full') cmd(`"rtmlist `full' `0'"')
    capture noisily rtmlist_`full' `0'
    local rc = _rc
    tempname hold
    _return hold `hold'
    _return restore `hold', hold
    capture _rtm_export done, rc(`rc')
    _return restore `hold'
    if `rc' exit `rc'
    return add
end
