* test_est.do -- rtmest reproduces svyset + svy exactly; calibration enters the variance
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
use "../data/rtm_baseline.dta", clear
merge 1:1 hhid using "../data/rtm_round1.dta", keepusing(responded_r1 skipmeal_r1 worked_r1) nogenerate
rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
keep if phone == 1
rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)
local pairs "1.region=14781 2.region=15345 3.region=14898 4.region=14807 0.urban=31458 1.urban=28373"
rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2) totals(`pairs')

* ---------- 1. mean: equals svy: mean with the same design ----------
rtmest skipmeal_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) nocalibration
matrix T = r(table)
svyset psu [pw=w2], strata(stratum)
quietly svy: mean skipmeal_r1 if responded_r1
matrix B = r(table)
assert reldif(T[1,1], B[1,1]) < 1e-10
assert reldif(T[1,2], B[2,1]) < 1e-10
quietly estat effects
matrix D = r(deff)
assert reldif(T[1,5], D[1,1]) < 1e-8
quietly estat cv
matrix C = r(cv)
assert reldif(T[1,6], C[1,1] / 100) < 1e-8

* ---------- 2. calibration in the variance: SE differs from the fixed-weight SE, estimate equal ----------
rtmest skipmeal_r1 if responded_r1, weight(w2) strata(stratum) psu(psu)
matrix Tc = r(table)
assert reldif(Tc[1,1], T[1,1]) < 1e-10
assert abs(Tc[1,2] - T[1,2]) > 1e-8
svyset psu [pw=w1], strata(stratum) rake(i.region i.urban, totals(_cons=59831 `pairs'))
quietly svy: mean skipmeal_r1 if responded_r1
matrix Bc = r(table)
assert reldif(Tc[1,2], Bc[2,1]) < 1e-8

* ---------- 3. over, proportion, total, ratio run and store the table ----------
rtmest skipmeal_r1 worked_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) over(urban) cvflag(20)
matrix T2 = r(table)
assert rowsof(T2) == 4
rtmest skipmeal_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) stat(proportion)
matrix T3 = r(table)
assert rowsof(T3) == 2
assert reldif(T3[1,1] + T3[2,1], 1) < 1e-10
rtmest hhsize if responded_r1, weight(w2) strata(stratum) psu(psu) stat(total) singleunit(centered)
matrix T4 = r(table)
assert T4[1,1] > 0
rtmest skipmeal_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) stat(ratio) ratio(skipmeal_r1 worked_r1)
matrix T5 = r(table)
assert rowsof(T5) == 1
assert r(n_singleton_strata) == 0

* ---------- 4. no design variables: runs, stores the table, equals svy: mean on observations ----------
rtmest skipmeal_r1 if responded_r1, weight(w2) nocalibration
matrix T6 = r(table)
svyset _n [pw=w2]
quietly svy: mean skipmeal_r1 if responded_r1
matrix B6 = r(table)
assert reldif(T6[1,1], B6[1,1]) < 1e-10
assert reldif(T6[1,2], B6[2,1]) < 1e-10

* ---------- 5. a weight that is neither the calibrated one nor its input: calibration not declared ----------
rtmest skipmeal_r1 if responded_r1, weight(w0) strata(stratum) psu(psu)
matrix T7 = r(table)
svyset psu [pw=w0], strata(stratum)
quietly svy: mean skipmeal_r1 if responded_r1
matrix B7 = r(table)
assert reldif(T7[1,2], B7[2,1]) < 1e-10
assert !strpos(`"`r(svyset)'"', "rake(")

* ---------- 6. cross-language: ReGenesees svystatTM on the same design (skipped without R) ----------
_rtm_runr find
local rs "`r(rscript)'"
local haveR 0
if "`rs'" != "" {
    tempfile a s
    tempname fh
    quietly file open `fh' using "`a'", write text replace
    file write `fh' "status=`s'" _n
    file close `fh'
    capture _rtm_runr, script(rtmtools_check.R) args("`a'") status("`s'") quietly
    if !_rc & strpos("`r(message)'", "ReGenesees") & !strpos("`r(message)'", "ReGenesees MISSING") local haveR 1
}
if !`haveR' global rtm_test_note "$rtm_test_note (R or ReGenesees not available: svystatTM check skipped)"
else {
    tempfile sd sout sst sargs
    preserve
    keep if responded_r1
    keep hhid psu stratum region urban w1 skipmeal_r1
    save "`sd'"
    restore
    quietly file open `fh' using "`sargs'", write text replace
    file write `fh' "status=`sst'" _n "data=`sd'" _n "out=`sout'" _n
    file close `fh'
    quietly findfile rtm_svystat.R
    shell "`rs'" --vanilla "`r(fn)'" "`sargs'" > /dev/null 2>&1
    file open `fh' using "`sst'", read text
    file read `fh' line
    file close `fh'
    assert "`line'" == "ok"
    rtmest skipmeal_r1 if responded_r1, weight(w1) strata(stratum) psu(psu) nocalibration
    matrix T8 = r(table)
    rtmest skipmeal_r1 if responded_r1, weight(w2) strata(stratum) psu(psu)
    matrix T9 = r(table)
    preserve
    use "`sout'", clear
    local est0 = est[1]
    local se0 = se[1]
    local est1 = est[2]
    local se1 = se[2]
    restore
    * design weights: the same Taylor-linearized estimator in both packages
    assert reldif(T8[1,1], `est0') < 1e-10
    assert reldif(T8[1,2], `se0') < 1e-8
    * raked weights: the estimates agree; the SEs differ by the documented residual variant
    * (Stata: residuals from the regression with the calibrated weights; ReGenesees: g-weighted
    * residuals, Deville 1999), by a fraction of a percent on these data
    assert reldif(T9[1,1], `est1') < 1e-10
    assert abs(T9[1,2] / `se1' - 1) < 0.01
}
di as result "test_est: all assertions passed"
