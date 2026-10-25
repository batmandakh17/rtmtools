*! rtmtools_dashboard.ado  version 0.4.0  25oct2026  rtmtools
*! Live dashboard of the runs. Every rtmtools command appends its start, progress, results or
*! error to a run log (rtmtools_runs.js in the working directory, or the file set here). This
*! command writes a self-contained page, rtmtools_dashboard.html, next to the log and opens it
*! in the browser; the page reads the log and refreshes itself every few seconds, so it follows
*! a do-file as it runs. No network: the page loads nothing but the two local files.
*!   rtmtools_dashboard                  write the page and open it
*!   rtmtools_dashboard, file(path)      use (and from now on write) another log file
*!   rtmtools_dashboard, off | on        stop or resume logging in this session
*!   rtmtools_dashboard, clear           delete the log and start a fresh dashboard
*!   rtmtools_dashboard, nobrowser       write the page without opening the browser
program define rtmtools_dashboard, rclass
    version 16
    syntax [, FILE(string) OFF ON CLEAR NOBrowser]
    if "`off'" != "" & "`on'" != "" {
        di as err "choose off or on, not both"
        exit 198
    }
    if "`off'" != "" {
        global RTM_DASHBOARD "off"
        di as txt "rtmtools: run logging is off for this session ({bf:rtmtools_dashboard, on} resumes it)"
        exit
    }
    if "`on'" != "" {
        global RTM_DASHBOARD ""
        di as txt "rtmtools: run logging is on"
    }
    if `"`file'"' != "" global RTM_DASHBOARD_FILE `"`file'"'
    local log "$RTM_DASHBOARD_FILE"
    if `"`log'"' == "" local log "rtmtools_runs.js"
    local log : subinstr local log "\" "/", all
    if !regexm(`"`log'"', "^(/|[A-Za-z]:)") local log `"`c(pwd)'/`log'"'
    local log : subinstr local log "//" "/", all
    if "`clear'" != "" {
        capture erase `"`log'"'
        di as txt `"rtmtools: run log cleared"'
    }
    local dir = substr(`"`log'"', 1, strrpos(`"`log'"', "/"))
    local base = substr(`"`log'"', strrpos(`"`log'"', "/") + 1, .)
    local html `"`dir'rtmtools_dashboard.html"'
    quietly findfile rtmtools_dashboard.html
    local tpl `"`r(fn)'"'
    copy `"`tpl'"' `"`html'"', replace
    * the page reads this small file to learn the log's name and the folder
    local base_e : subinstr local base `"\"' `"\\"', all
    local base_e : subinstr local base_e `"""' `"\""', all
    local dir_e : subinstr local dir `"\"' `"\\"', all
    local dir_e : subinstr local dir_e `"""' `"\""', all
    tempname fh
    quietly file open `fh' using `"`dir'rtmtools_dashboard_config.js"', write text replace
    file write `fh' `"var RTM_LOG_FILE = "`base_e'";"' _n `"var RTM_FOLDER = "`dir_e'";"' _n
    file close `fh'
    capture confirm file `"`log'"'
    if _rc {
        quietly file open `fh' using `"`log'"', write text replace
        file write `fh' "// rtmtools run log: one RTM_RUNS.push({...}); statement per event, written by the commands" _n
        file close `fh'
    }
    di as txt `"Dashboard written: {browse "`html'"}"'
    di as txt `"It reads `base' in the same folder and refreshes itself while rtmtools commands run."'
    if "`nobrowser'" == "" {
        * hand the file to the operating system's default browser (never to Stata's own viewer,
        * which is not a web browser and cannot show the page)
        if "`c(os)'" == "Windows" {
            local winpath : subinstr local html "/" "\", all
            capture winexec rundll32 url.dll,FileProtocolHandler "`winpath'"
        }
        else if strpos("`c(machine_type)'", "Mac") capture shell open "`html'"
        else capture shell xdg-open "`html'" > /dev/null 2>&1 &
        if _rc di as txt "(the browser could not be opened from here; open the file above by hand)"
        else di as txt "Opening the page in your browser. It stays open and refreshes itself; close it when done."
    }
    return local html `"`html'"'
    return local log `"`log'"'
end
