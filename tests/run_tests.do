* run_tests.do -- rtmtools test runner (24oct2026)
* Runs every test_*.do in this folder, prints PASS or FAIL for each, and writes tests/results.txt.
* Usage, from the tests folder:   do run_tests.do
* The tests use the package files in the parent folder (adopath ++ ..) and the synthetic data
* in ../data. The R tests report SKIP notes when R or ReGenesees is not available.
clear all
set more off
capture log close _all
global rtm_here "`c(pwd)'"
adopath ++ "${rtm_here}/.."
global rtm_tests "test_weights test_calibrate test_est test_rbridge test_edge test_badinput test_repro test_sample test_frame test_install"
tempname fh
file open `fh' using "${rtm_here}/results.txt", write text replace
file write `fh' "rtmtools tests, `c(current_date)' `c(current_time)', Stata `c(stata_version)'" _n
file close `fh'
global rtm_npass 0
global rtm_nfail 0
foreach t of global rtm_tests {
    di as text _n "{hline 70}" _n "running `t'.do" _n "{hline 70}"
    global rtm_test_status "PASS"
    global rtm_test_note ""
    capture noisily do "${rtm_here}/`t'.do"
    local rc = _rc
    if `rc' != 0 global rtm_test_status "FAIL (rc = `rc')"
    di as result _n "`t': ${rtm_test_status} ${rtm_test_note}"
    tempname fh
    file open `fh' using "${rtm_here}/results.txt", write text append
    file write `fh' "`t': ${rtm_test_status} ${rtm_test_note}" _n
    file close `fh'
    if strpos("${rtm_test_status}", "PASS") global rtm_npass = ${rtm_npass} + 1
    else global rtm_nfail = ${rtm_nfail} + 1
}
di as text _n "{hline 70}"
di as result "${rtm_npass} passed, ${rtm_nfail} failed" as text " (details in results.txt)"
type "${rtm_here}/results.txt"
