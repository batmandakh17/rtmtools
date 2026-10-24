*! rtmframe.ado  version 0.3.0  24oct2026  rtmtools
*! Dispatcher: rtmframe list | grid | replace | split
program define rtmframe, rclass
    version 16
    gettoken sub 0 : 0, parse(" ,")
    local sub = lower("`sub'")
    local full ""
    foreach s in list grid replace split {
        if "`sub'" != "" & strpos("`s'", "`sub'") == 1 & length("`sub'") >= 2 local full "`s'"
    }
    if "`sub'" == "" {
        di as err "rtmframe: a subcommand is required: list, grid, replace or split"
        di as err "see {help rtmframe}"
        exit 198
    }
    if "`full'" == "" {
        di as err "rtmframe: unknown subcommand `sub'; use list, grid, replace or split"
        exit 198
    }
    capture _rtm_log start, tool("rtmframe `full'") cmd(`"rtmframe `full' `0'"')
    capture noisily rtmframe_`full' `0'
    local rc = _rc
    if `rc' {
        capture _rtm_log error, tool("rtmframe `full'") cmd(`"rtmframe `full' `0'"') rc(`rc')
        exit `rc'
    }
    * log first: return add empties the live r() that the log reads
    capture _rtm_log done, tool("rtmframe `full'") cmd(`"rtmframe `full' `0'"')
    return add
end
