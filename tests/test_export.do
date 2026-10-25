* test_export.do -- the export of every run (schema rtm-export-1.0): run folders, manifest.json and
* manifest.csv, the tables, the live index, the Excel display workbook; off/on; and the dashboard page
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
local tmp "`c(tmpdir)'"
if substr("`tmp'", -1, 1) != "/" & substr("`tmp'", -1, 1) != "\" local tmp "`tmp'/"
local dir "`tmp'rtm_test_exports"
capture mkdir "`dir'"
local files : dir "`dir'" files "*"
foreach f of local files {
    capture erase "`dir'/`f'"
}
global RTM_EXPORT ""
rtmtools_dashboard, dir("`dir'") clear nobrowser
confirm file "`dir'/rtmtools_dashboard.html"
confirm file "`dir'/rtmtools_dashboard_config.js"
confirm file "`dir'/rtm_exports.js"
assert "`r(dir)'" == "`dir'"

* ---------- 1. three commands: two succeed, one fails ----------
use "../data/rtm_round1.dta", clear
rtmweight nonresponse responded_r1, weight(w_base) method(classes) classes(region urban) generate(w1c)
local run1 "$RTM_EXP_LAST"
confirm file "`run1'/manifest.json"
confirm file "`run1'/manifest.csv"
confirm file "`run1'/weight_stages.csv"
confirm file "`run1'/response_classes.csv"
confirm file "`run1'/rtm_display.xlsx"
rtmweight trim w1c if responded_r1, generate(w1t) rule(winsor) pct(90) id(hhid)
assert r(n_trimmed_high) > 0
local run2 "$RTM_EXP_LAST"
confirm file "`run2'/flags.csv"
capture noisily rtmweight trim w1c if responded_r1, generate(w1t) rule(winsor) pct(90)
assert _rc == 110
* a dispatcher still returns the subcommand's results after exporting
rtmweight nonresponse responded_r1, weight(w_base) method(ebalance) covariates(urban hhsize) generate(w1e) nocrosscheck
assert r(N_resp) == 724
assert r(max_rel_diff) < 1e-6
local run3 "$RTM_EXP_LAST"
confirm file "`run3'/calibration_fit.csv"

* ---------- 2. the live index: one statement per run, with the right events ----------
program drop _all
program define _rtmtest_count
    args file
    tempname fh
    file open `fh' using "`file'", read text
    local n 0
    local done 0
    local error 0
    local hasws 0
    local hasrc 0
    local hasset 0
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`line'"', "RTM_EXPORTS.push({") == 1 {
            local ++n
            if strpos(`"`line'"', `""status":"done""') local ++done
            if strpos(`"`line'"', `""status":"error""') local ++error
            if strpos(`"`line'"', `""weight_stages":{"cols":["stage","variable","n","sum""') local ++hasws
            if strpos(`"`line'"', `""rc":110"') local ++hasrc
            if strpos(`"`line'"', `""method":{"value":"classes","source":"UN 2008 section 6.5; HFPS Vol. 2 p. 10"}"') local ++hasset
        }
        file read `fh' line
    }
    file close `fh'
    c_local n `n'
    c_local ndone `done'
    c_local nerror `error'
    c_local nws `hasws'
    c_local nrc `hasrc'
    c_local nset `hasset'
end
_rtmtest_count "`dir'/rtm_exports.js"
assert `n' == 4
assert `ndone' == 3 & `nerror' == 1
assert `nws' == 3
assert `nrc' == 1
assert `nset' == 1

* ---------- 3. the tables read back: weight_stages of the class adjustment ----------
preserve
import delimited using "`run1'/weight_stages.csv", clear varnames(1) case(preserve) stringcols(1 2)
assert _N == 3
assert stage[1] == "base weight, all sample" & variable[1] == "w_base"
assert n[1] == 939
assert stage[3] == "adjusted, respondents"
assert reldif(sum[3], sum[1]) < 1e-9          // classes keep the base-weight total
assert kish_deff[3] >= 1
import delimited using "`run1'/response_classes.csv", clear varnames(1) case(preserve) stringcols(1 2)
assert _N == 8
assert class_var[1] == "region urban"
assert strpos(class[1], "region=North") > 0
import delimited using "`run1'/manifest.csv", clear varnames(1) case(preserve) stringcols(_all)
assert key[1] == "schema" & value[1] == "rtm-export-1.0"
quietly count if key == "summary_N_resp" & value == "724"
assert r(N) == 1
quietly count if key == "privacy"
assert r(N) == 1
restore

* ---------- 4. off stops the export, on resumes it ----------
rtmtools_dashboard, off
rtmweight nonresponse responded_r1, weight(w_base) method(classes) classes(region) generate(w1x)
_rtmtest_count "`dir'/rtm_exports.js"
assert `n' == 4
rtmtools_dashboard, on nobrowser
rtmweight nonresponse responded_r1, weight(w_base) method(classes) classes(region) generate(w1y)
_rtmtest_count "`dir'/rtm_exports.js"
assert `n' == 5
* no table frame left behind
frame dir
local fr "`r(frames)'"
assert strpos("`fr'", "_rtmx") == 0

* ---------- 5. the page and the workbook are self-contained: no external resources ----------
tempfile ff
quietly filefilter "`dir'/rtmtools_dashboard.html" "`ff'", from("https://") to("https://") replace
assert r(occurrences) == 0
quietly filefilter "`dir'/rtmtools_dashboard.html" "`ff'", from("http://") to("http://") replace
assert r(occurrences) == 0
* numbers in the index are valid JSON as far as Stata can tell: no bare leading decimal points
quietly filefilter "`dir'/rtm_exports.js" "`ff'", from(`"":."') to(`"":."') replace
assert r(occurrences) == 0
quietly filefilter "`dir'/rtm_exports.js" "`ff'", from(`",."') to(`",."') replace
assert r(occurrences) == 0

* restore the defaults for the other tests
global RTM_EXPORT_DIR ""
global RTM_EXPORT "off"
di as result "test_export: all assertions passed"
