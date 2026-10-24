* test_dashboard.do -- the run log and the dashboard page: events for started, done and failed
* commands, the results and matrices recorded, off/on, clear, and the files written
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
local tmp "`c(tmpdir)'"
if substr("`tmp'", -1, 1) != "/" & substr("`tmp'", -1, 1) != "\" local tmp "`tmp'/"
local log "`tmp'rtm_test_runs.js"
capture erase "`log'"
capture erase "`tmp'rtmtools_dashboard.html"
capture erase "`tmp'rtmtools_dashboard_config.js"
global RTM_DASHBOARD ""
rtmtools_dashboard, file("`log'") nobrowser
confirm file "`tmp'rtmtools_dashboard.html"
confirm file "`tmp'rtmtools_dashboard_config.js"
confirm file "`log'"
assert "`r(html)'" == "`tmp'rtmtools_dashboard.html"

* ---------- 1. three commands: two succeed, one fails ----------
rtmsample size, p(0.2) deff(1) domains(2)
use "../data/rtm_frame.dta", clear
rtmsample allocate, strata(stratum) n(100) size(ea_size_census) generate(n_ea)
capture noisily rtmsample draw, n(70) strata(stratum) generate(z)
assert _rc == 459
* a dispatcher still returns the subcommand's results after logging
rtmsample size, p(0.5) margin(0.05) deff(1) nonresponse(1)
assert r(n_domain) == 385

* ---------- 2. read the log: one statement per event, with the right events ----------
program drop _all
program define _rtmtest_count
    args file
    tempname fh
    file open `fh' using "`file'", read text
    local n 0
    local start 0
    local done 0
    local error 0
    local hasres 0
    local hasmat 0
    local hasseed 0
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`line'"', "RTM_RUNS.push({") == 1 {
            local ++n
            if strpos(`"`line'"', `""event":"start""') local ++start
            if strpos(`"`line'"', `""event":"done""') local ++done
            if strpos(`"`line'"', `""event":"error""') local ++error
            if strpos(`"`line'"', `""n_total":"') local ++hasres
            if strpos(`"`line'"', `""alloc":{"rows":["') local ++hasmat
            if strpos(`"`line'"', `""rc":459"') local ++hasseed
        }
        file read `fh' line
    }
    file close `fh'
    c_local n `n'
    c_local nstart `start'
    c_local ndone `done'
    c_local nerror `error'
    c_local nres `hasres'
    c_local nmat `hasmat'
    c_local nrc `hasseed'
end
_rtmtest_count "`log'"
assert `n' == 8
assert `nstart' == 4 & `ndone' == 3 & `nerror' == 1
assert `nres' == 2
assert `nmat' == 1
assert `nrc' == 1

* ---------- 3. off stops the log, on resumes it ----------
rtmtools_dashboard, off
rtmsample size, p(0.3)
_rtmtest_count "`log'"
assert `n' == 8
rtmtools_dashboard, on nobrowser
rtmsample size, p(0.4)
_rtmtest_count "`log'"
assert `n' == 10

* ---------- 4. clear starts a fresh log ----------
rtmtools_dashboard, clear nobrowser
_rtmtest_count "`log'"
assert `n' == 0

* ---------- 5. the page is self-contained: no external resources ----------
tempfile ff
quietly filefilter "`tmp'rtmtools_dashboard.html" "`ff'", from("https://") to("https://") replace
assert r(occurrences) == 0
quietly filefilter "`tmp'rtmtools_dashboard.html" "`ff'", from("http://") to("http://") replace
assert r(occurrences) == 0
* the log lines are valid JSON objects as far as Stata can tell: every value quoted or numeric
rtmtools_dashboard, nobrowser
rtmsample size, p(0.2) deff(1)
quietly filefilter "`log'" "`ff'", from(`"":."') to(`"":."') replace
assert r(occurrences) == 0
quietly filefilter "`log'" "`ff'", from(`"":-."') to(`"":-."') replace
assert r(occurrences) == 0

* restore the defaults for the other tests
global RTM_DASHBOARD_FILE ""
global RTM_DASHBOARD "off"
di as result "test_dashboard: all assertions passed"
