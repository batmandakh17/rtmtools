*! rtmtools_dashboard.ado  version 0.5.0  25oct2026  rtmtools
*! The export folder and the dashboard. Every rtmtools command writes its run (schema
*! rtm-export-1.0) into a folder under the export folder and appends one line to its live index,
*! rtm_exports.js. This command sets the export folder, writes the self-contained dashboard page
*! next to the index and opens it in the browser; the page reads the index and refreshes itself
*! while commands run. No network: the page loads nothing but the local files.
*!   rtmtools_dashboard                  write the page into the export folder and open it
*!   rtmtools_dashboard, dir(path)       use (and from now on write to) another export folder
*!   rtmtools_dashboard, off | on        stop or resume exporting in this session
*!   rtmtools_dashboard, clear           delete the live index (the run folders stay)
*!   rtmtools_dashboard, nobrowser       write the page without opening the browser
program define rtmtools_dashboard, rclass
    version 16
    syntax [, DIR(string) OFF ON CLEAR NOBrowser]
    if "`off'" != "" & "`on'" != "" {
        di as err "choose off or on, not both"
        exit 198
    }
    if "`off'" != "" {
        global RTM_EXPORT "off"
        di as txt "rtmtools: exporting is off for this session ({bf:rtmtools_dashboard, on} resumes it)"
        exit
    }
    if "`on'" != "" {
        global RTM_EXPORT ""
        di as txt "rtmtools: exporting is on"
    }
    if `"`dir'"' != "" global RTM_EXPORT_DIR `"`dir'"'
    local d "$RTM_EXPORT_DIR"
    if `"`d'"' == "" local d "rtm_exports"
    local d : subinstr local d "\" "/", all
    if !regexm(`"`d'"', "^(/|[A-Za-z]:)") local d `"`c(pwd)'/`d'"'
    local d : subinstr local d "//" "/", all
    if substr(`"`d'"', -1, 1) == "/" local d = substr(`"`d'"', 1, length(`"`d'"') - 1)
    capture mkdir `"`d'"'
    local idx `"`d'/rtm_exports.js"'
    if "`clear'" != "" {
        capture erase `"`idx'"'
        di as txt `"rtmtools: live index cleared (the run folders in `d' were kept)"'
    }
    local html `"`d'/rtmtools_dashboard.html"'
    quietly findfile rtmtools_dashboard.html
    copy `"`r(fn)'"' `"`html'"', replace
    tempname fh
    capture confirm file `"`idx'"'
    if _rc {
        quietly file open `fh' using `"`idx'"', write text replace
        file write `fh' "// rtmtools export index: one RTM_EXPORTS.push({...}); per run, written by the commands" _n
        file close `fh'
    }
    * the page reads this small file to learn the folder (for its source notes)
    local d_e : subinstr local d `"\"' `"\\"', all
    local d_e : subinstr local d_e `"""' `"\""', all
    quietly file open `fh' using `"`d'/rtmtools_dashboard_config.js"', write text replace
    file write `fh' `"var RTM_FOLDER = "`d_e'";"' _n
    file close `fh'
    di as txt `"Export folder: `d'"'
    di as txt `"Dashboard written: {browse "`html'"}"'
    di as txt `"It reads rtm_exports.js in the same folder and refreshes itself while rtmtools commands run."'
    if "`nobrowser'" == "" {
        * hand the file to the operating system's default browser (never to Stata's viewer,
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
    return local dir `"`d'"'
end
