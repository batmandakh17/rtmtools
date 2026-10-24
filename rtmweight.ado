*! rtmweight.ado  version 0.1.0  24oct2026  rtmtools
*! Dispatcher: rtmweight base | nonresponse | calibrate | trim | report
program define rtmweight, rclass
    version 16
    gettoken sub 0 : 0, parse(" ,")
    local sub = lower(trim("`sub'"))
    if "`sub'" == "" {
        di as err "rtmweight: a subcommand is required: base, nonresponse, calibrate, trim or report"
        di as err "see {help rtmweight}"
        exit 198
    }
    * accept unambiguous abbreviations
    local full ""
    foreach s in base nonresponse calibrate trim report {
        if strpos("`s'", "`sub'") == 1 local full "`full' `s'"
    }
    local full = trim("`full'")
    if wordcount("`full'") != 1 {
        di as err "rtmweight: unknown subcommand {bf:`sub'}; use base, nonresponse, calibrate, trim or report"
        exit 198
    }
    capture _rtm_log start, tool("rtmweight `full'") cmd(`"rtmweight `full' `0'"')
    capture noisily rtmweight_`full' `0'
    local rc = _rc
    if `rc' {
        capture _rtm_log error, tool("rtmweight `full'") cmd(`"rtmweight `full' `0'"') rc(`rc')
        exit `rc'
    }
    * log first: return add empties the live r() that the log reads
    capture _rtm_log done, tool("rtmweight `full'") cmd(`"rtmweight `full' `0'"')
    return add
end
