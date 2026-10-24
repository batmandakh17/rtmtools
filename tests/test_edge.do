* test_edge.do -- edge cases: a stratum with one PSU, an empty class, infeasible totals,
* full response in a class, extreme weights, categories without totals
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
use "../data/rtm_baseline.dta", clear
merge 1:1 hhid using "../data/rtm_round1.dta", keepusing(responded_r1 skipmeal_r1) nogenerate
rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
keep if phone == 1
local pairs "1.region=14781 2.region=15345 3.region=14898 4.region=14807 0.urban=31458 1.urban=28373"

* ---------- 1. classes: no respondent in a class stops; full response gives factor 1; mincell ----------
capture which survwgt
if !_rc {
    gen byte resp_x = responded_r1
    replace resp_x = 0 if region == 4 & urban == 1
    capture noisily rtmweight nonresponse resp_x, weight(w0) method(classes) classes(region urban) generate(wx)
    assert _rc == 459
    gen byte resp_full = responded_r1
    replace resp_full = 1 if region == 1
    rtmweight nonresponse resp_full, weight(w0) method(classes) classes(region) generate(wf)
    assert reldif(wf, w0) < 1e-10 if region == 1
    capture noisily rtmweight nonresponse responded_r1, weight(w0) method(classes) classes(region urban educ agegrp) mincell(30) generate(wx2)
    assert _rc == 459
}
else global rtm_test_note "$rtm_test_note (survwgt not installed: class edge cases skipped)"

* ---------- 2. infeasible calibration: tight bounds fail unless forced; forced shows the gap ----------
rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age) generate(w1)
capture noisily rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(wb) method(regress) ll(0.99) ul(1.01) totals(`pairs')
local rc_tight = _rc
di "tight bounds rc = `rc_tight'"
* without force the command refuses weights that miss the totals (error 430), or svycal itself fails
assert `rc_tight' != 0
capture confirm variable wb
assert _rc != 0
rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(wb) method(regress) ll(0.99) ul(1.01) totals(`pairs') force
assert r(max_rel_diff) > 1e-4

* ---------- 3. a total for a category absent from the sample; a sample category without a total ----------
capture noisily rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(wc) totals(`pairs' 5.region=1)
assert _rc == 459
capture noisily rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(wc) totals(1.region=14781 2.region=15345 3.region=14898 0.urban=31458 1.urban=28373)
assert _rc == 198

* ---------- 4. extreme weights: the cap holds and the total is kept ----------
gen double wext = w1
replace wext = 50 * w1 in 1/3
rtmweight trim wext if responded_r1, generate(wtx) rule(cap) capmult(3)
quietly summarize wext if responded_r1
local s0 = r(sum)
quietly summarize wtx if responded_r1
assert reldif(r(sum), `s0') < 1e-9
assert r(n_trimmed_high) >= 1
quietly summarize wtx if responded_r1, detail
assert r(max) < 3 * r(p50) * 1.5

* ---------- 5. one PSU in a stratum: rtmest reports it; singleunit(centered) gives a standard error ----------
gen int stratum2 = stratum
quietly summarize psu if responded_r1
replace stratum2 = 99 if psu == r(min)
rtmest skipmeal_r1 if responded_r1, weight(w1) strata(stratum2) psu(psu) nocalibration
assert r(n_singleton_strata) == 1
matrix T = r(table)
assert T[1,2] == .
rtmest skipmeal_r1 if responded_r1, weight(w1) strata(stratum2) psu(psu) singleunit(centered) nocalibration
matrix T2 = r(table)
assert T2[1,2] < .

* ---------- 6. an empty by() group in the subsample factor stops with a message ----------
preserve
use "../data/rtm_baseline.dta", clear
replace phone = 0 if stratum == 3
capture noisily rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0e)
assert _rc == 459
restore

* ---------- 7. a very large frame runs (500,000 rows) ----------
preserve
clear
set obs 500000
gen double p1 = runiform() * 0.5 + 0.25
gen double p2 = 0.5
gen byte resp = runiform() < 0.8
gen byte cls = ceil(runiform() * 20)
rtmweight base, probability(p1 p2) generate(wbig)
rtmweight nonresponse resp, weight(wbig) method(classes) classes(cls) generate(wbig1)
rtmweight trim wbig1 if resp, generate(wbig2) rule(winsor) pct(99)
restore
di as result "test_edge: all assertions passed"
