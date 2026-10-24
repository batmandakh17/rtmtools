*! rtmsample.ado  version 0.2.0  24oct2026  rtmtools
*! Dispatcher: rtmsample size | allocate | draw
program define rtmsample, rclass
    version 16
    gettoken sub 0 : 0, parse(" ,")
    local sub = lower("`sub'")
    local full ""
    foreach s in size allocate draw grid {
        if "`sub'" != "" & strpos("`s'", "`sub'") == 1 & length("`sub'") >= 3 local full "`s'"
    }
    if "`sub'" == "" {
        di as err "rtmsample: a subcommand is required: size, allocate, draw or grid"
        di as err "see {help rtmsample}"
        exit 198
    }
    if "`full'" == "" {
        di as err "rtmsample: unknown subcommand `sub'; use size, allocate, draw or grid"
        exit 198
    }
    capture _rtm_log start, tool("rtmsample `full'") cmd(`"rtmsample `full' `0'"')
    capture noisily rtmsample_`full' `0'
    local rc = _rc
    if `rc' {
        capture _rtm_log error, tool("rtmsample `full'") cmd(`"rtmsample `full' `0'"') rc(`rc')
        exit `rc'
    }
    * log first: return add empties the live r() that the log reads
    capture _rtm_log done, tool("rtmsample `full'") cmd(`"rtmsample `full' `0'"')
    return add
end
