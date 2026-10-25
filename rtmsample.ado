*! rtmsample.ado  version 0.2.0  24oct2026  rtmtools
*! Dispatcher: rtmsample size | allocate | draw
program define rtmsample, rclass
    version 16
    gettoken sub 0 : 0, parse(" ,")
    local sub = lower("`sub'")
    local full ""
    foreach s in size allocate draw grid rdd {
        if "`sub'" != "" & strpos("`s'", "`sub'") == 1 & length("`sub'") >= 3 local full "`s'"
    }
    if "`sub'" == "" {
        di as err "rtmsample: a subcommand is required: size, allocate, draw, grid or rdd"
        di as err "see {help rtmsample}"
        exit 198
    }
    if "`full'" == "" {
        di as err "rtmsample: unknown subcommand `sub'; use size, allocate, draw, grid or rdd"
        exit 198
    }
    capture _rtm_export start, workflow(sampling) step(`full') cmd(`"rtmsample `full' `0'"')
    capture noisily rtmsample_`full' `0'
    local rc = _rc
    tempname hold
    _return hold `hold'
    _return restore `hold', hold
    capture _rtm_export done, rc(`rc')
    _return restore `hold'
    if `rc' exit `rc'
    return add
end
