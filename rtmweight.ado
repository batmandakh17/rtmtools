*! rtmweight.ado  version 0.5.0  25oct2026  rtmtools
*! Dispatcher: rtmweight base | nonresponse | calibrate | trim | household | report
*! Every run is exported (manifest, tables, Excel display, dashboard index) by _rtm_export.
program define rtmweight, rclass
    version 16
    gettoken sub 0 : 0, parse(" ,")
    local sub = lower(trim("`sub'"))
    if "`sub'" == "" {
        di as err "rtmweight: a subcommand is required: base, nonresponse, calibrate, trim, household or report"
        di as err "see {help rtmweight}"
        exit 198
    }
    * accept unambiguous abbreviations
    local full ""
    foreach s in base nonresponse calibrate trim household report {
        if strpos("`s'", "`sub'") == 1 local full "`full' `s'"
    }
    local full = trim("`full'")
    if wordcount("`full'") != 1 {
        di as err "rtmweight: unknown subcommand {bf:`sub'}; use base, nonresponse, calibrate, trim, household or report"
        exit 198
    }
    capture _rtm_export start, workflow(weights) step(`full') cmd(`"rtmweight `full' `0'"')
    capture noisily rtmweight_`full' `0'
    local rc = _rc
    * the export reads the command's r() and may touch r() itself: hold and restore around it
    tempname hold
    _return hold `hold'
    _return restore `hold', hold
    capture _rtm_export done, rc(`rc')
    _return restore `hold'
    if `rc' exit `rc'
    return add
end
