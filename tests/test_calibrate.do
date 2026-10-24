* test_calibrate.do -- calibration: svycal against the totals, ipfraking and ReGenesees cross-checks,
* post-stratification by hand, totals from a file, bounds, and ReGenesees' documented example
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
local pairs "1.region=14781 2.region=15345 3.region=14898 4.region=14807 0.urban=31458 1.urban=28373"

use "../data/rtm_baseline.dta", clear
merge 1:1 hhid using "../data/rtm_round1.dta", keepusing(responded_r1) nogenerate
rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
keep if phone == 1
rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)

* ---------- 1. svycal rake reaches the totals exactly ----------
rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2) totals(`pairs')
assert r(max_rel_diff) < 1e-8
local npop = r(N_pop)
forvalues k = 1/4 {
    quietly summarize w2 if responded_r1 & region == `k'
    local tgt = real(substr(word("`pairs'", `k'), strpos(word("`pairs'", `k'), "=") + 1, .))
    assert reldif(r(sum), `tgt') < 1e-8
}
assert reldif(`npop', 59831) < 1e-9

* ---------- 2. totals from a file give the same weights ----------
rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2f) totalsfile("../data/rtm_totals_long.dta")
assert reldif(w2, w2f) < 1e-9 if responded_r1

* ---------- 3. post-stratification by hand (one variable) ----------
rtmweight calibrate region [pw=w1] if responded_r1, generate(w2p) method(post) totals(1.region=14781 2.region=15345 3.region=14898 4.region=14807)
bysort region: egen double sreg = total(cond(responded_r1, w1, 0))
gen double tgt = cond(region == 1, 14781, cond(region == 2, 15345, cond(region == 3, 14898, 14807)))
gen double w2ph = w1 * tgt / sreg if responded_r1
assert reldif(w2p, w2ph) < 1e-8 if responded_r1

* ---------- 4. linear calibration with bounds respects them ----------
rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2r) method(regress) ll(0.8) ul(1.5) totals(`pairs')
gen double g = w2r / w1 if responded_r1
quietly summarize g
assert r(min) >= 0.8 - 1e-6 & r(max) <= 1.5 + 1e-6

* ---------- 5. ipfraking cross-check (raking) ----------
capture which ipfraking
if _rc global rtm_test_note "$rtm_test_note (ipfraking not installed: cross-check skipped)"
else {
    rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2i) engine(ipfraking) totals(`pairs')
    assert r(converged) == 1
    assert reldif(w2i, w2) < 1e-5 if responded_r1
}

* ---------- 6. ReGenesees cross-check (raking, logit) ----------
_rtm_runr find
local rs "`r(rscript)'"
local haveR 0
if "`rs'" != "" {
    tempfile a s
    tempname fh
    file open `fh' using "`a'", write text replace
    file write `fh' "status=`s'" _n
    file close `fh'
    capture _rtm_runr, script(rtmtools_check.R) args("`a'") status("`s'") quietly
    if !_rc & strpos("`r(message)'", "ReGenesees") & !strpos("`r(message)'", "ReGenesees MISSING") local haveR 1
}
if !`haveR' global rtm_test_note "$rtm_test_note (R or ReGenesees not available: ReGenesees checks skipped)"
else {
    rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2g) engine(regenesees) ids(hhid) strata(stratum) totals(`pairs')
    assert reldif(w2g, w2) < 1e-7 if responded_r1
    assert r(max_rel_diff) < 1e-8
    rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2gl) engine(regenesees) ids(hhid) strata(stratum) totals(`pairs') distance(logit) bounds(0.7 1.5)
    gen double gl = w2gl / w1 if responded_r1
    quietly summarize gl
    assert r(min) >= 0.7 - 1e-6 & r(max) <= 1.5 + 1e-6
    assert `r(N)' == 724

    * ---------- 7. ReGenesees' documented example (data.examples, pop02: ~sex + marstat) reproduced in svycal ----------
    tempfile exdata extot exstatus exargs
    file open `fh' using "`exargs'", write text replace
    file write `fh' "status=`exstatus'" _n "data=`exdata'" _n "totals=`extot'" _n
    file close `fh'
    quietly findfile rtm_refexample.R
    local script "`r(fn)'"
    shell "`rs'" --vanilla "`script'" "`exargs'" > /dev/null 2>&1
    file open `fh' using "`exstatus'", read text
    file read `fh' line
    file close `fh'
    assert "`line'" == "ok"
    preserve
    use "`extot'", clear
    local expairs ""
    quietly count
    forvalues i = 1/`r(N)' {
        local expairs "`expairs' `=level[`i']'.`=variable[`i']'=`=total[`i']'"
    }
    use "`exdata'", clear
    rtmweight calibrate i.sex i.marstat [pw=weight], generate(w_stata) totals(`expairs')
    assert r(max_rel_diff) < 1e-8
    * w_regenesees holds the weights that ReGenesees' e.calibrate produced for the same model
    assert reldif(w_stata, w_regenesees) < 1e-7
    restore
}
di as result "test_calibrate: all assertions passed"
