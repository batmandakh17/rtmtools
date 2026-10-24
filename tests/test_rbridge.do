* test_rbridge.do -- the R bridge: finding Rscript, a round trip of labels and missing values
* through haven, and clean failure when R reports an error
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
_rtm_runr find
local rs "`r(rscript)'"
if "`rs'" == "" {
    global rtm_test_note "$rtm_test_note (R not found: bridge tests skipped)"
    di as txt "R not found; skipping"
    exit
}
* ---------- 1. the check script runs and reports ----------
tempfile a s
tempname fh
file open `fh' using "`a'", write text replace
file write `fh' "status=`s'" _n
file close `fh'
_rtm_runr, script(rtmtools_check.R) args("`a'") status("`s'") quietly
assert "`r(status)'" == "ok"
assert strpos("`r(message)'", "haven")
local haveRG = !strpos("`r(message)'", "ReGenesees MISSING") & strpos("`r(message)'", "ReGenesees")

* ---------- 2. clean failure: a data file that does not exist ----------
if `haveRG' {
    tempfile a2 s2 out diag tot
    file open `fh' using "`a2'", write text replace
    file write `fh' "data=/nonexistent/file.dta" _n "totals=`tot'" _n "out=`out'" _n "diag=`diag'" _n "status=`s2'" _n
    file write `fh' "idvar=id" _n "wvar=w" _n "stratavar=" _n "calvars=x" _n "method=rake" _n "calfun=raking" _n "bounds=" _n "trimcal=" _n "aggvar=" _n
    file close `fh'
    capture _rtm_runr, script(rtm_calibrate.R) args("`a2'") status("`s2'") quietly
    assert _rc == 199
    assert "`r(status)'" == "error"
    assert "`r(message)'" != ""
}

* ---------- 3. round trip: value labels, variable labels and extended missing values survive haven ----------
clear
set obs 6
gen long id = _n
gen double w = 10 * _n
gen byte region = mod(_n, 3) + 1
label define region 1 "North" 2 "South" 3 "East"
label values region region
label var region "Region of residence"
gen double y = _n
replace y = .a in 1
replace y = . in 2
tempfile rt rtout rts rta
save "`rt'"
file open `fh' using "`rta'", write text replace
file write `fh' "status=`rts'" _n "in=`rt'" _n "out=`rtout'" _n
file close `fh'
quietly findfile rtm_roundtrip.R
shell "`rs'" --vanilla "`r(fn)'" "`rta'" > /dev/null 2>&1
file open `fh' using "`rts'", read text
file read `fh' line
file close `fh'
assert "`line'" == "ok"
use "`rtout'", clear
assert region[1] == 2 & region[3] == 1
local lab : value label region
assert "`lab'" != ""
local l2 : label (region) 2
assert "`l2'" == "South"
local vl : variable label region
assert "`vl'" == "Region of residence"
assert y[1] == .a
assert y[2] == .
assert reldif(w[6], 60) < 1e-12
di as result "test_rbridge: all assertions passed"
