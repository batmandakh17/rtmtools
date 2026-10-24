* test_weights.do -- hand calculations on a tiny frame, and checks on the synthetic data
* base weights, nonresponse (classes and propensity), trimming
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."

* ---------- 1. tiny frame, hand-calculated design weights ----------
* 2 strata; stratum 1 has EAs A (size 100) and B (size 300), 1 EA drawn PPS -> pi_A = .25, pi_B = .75;
* stratum 2 has EA C (size 200) drawn with certainty -> pi_C = 1. Two households drawn in each EA of
* 4 listed -> pi_hh = 0.5. Base weight = 1/(pi_ea x pi_hh): B: 1/(.75 x .5) = 2.6667; C: 1/(1 x .5) = 2.
clear
input str1 ea double pi_ea double pi_hh byte resp double wbl byte sub byte str
"B" .75 .5 1 10 1 1
"B" .75 .5 0 20 1 1
"C" 1   .5 1 30 0 2
"C" 1   .5 1 40 1 2
end
rtmweight base, probability(pi_ea pi_hh) generate(w)
assert reldif(w[1], 1/(.75*.5)) < 1e-12
assert reldif(w[3], 2) < 1e-12
assert reldif(r(sum), 2/(.75*.5) + 2*2) < 1e-12

* subsample factor: stratum 1 both subsampled (factor 1); stratum 2: 70 total, 40 subsampled -> factor 1.75
rtmweight base, baseweight(wbl) subsample(sub) by(str) generate(w0)
assert reldif(w0[1], 10) < 1e-12
assert reldif(w0[2], 20) < 1e-12
assert missing(w0[3])
assert reldif(w0[4], 40 * 70/40) < 1e-12
assert reldif(r(sum), 100) < 1e-12
* r() describes the new weight (3 subsampled units), not the baseline weight
assert r(N) == 3
assert r(kish) < .
assert reldif(r(sum_baseline), 100) < 1e-12

* multiplicity: divide by number of phones
gen byte nph = 2
rtmweight base, probability(pi_ea pi_hh) multiplicity(nph) generate(wm)
assert reldif(wm[1], 1/(.75*.5)/2) < 1e-12

* ---------- 2. tiny class adjustment by hand ----------
* one class with base weights 10, 20, 30, 40 and responses 1 0 1 1: factor = 100/80 = 1.25
clear
input byte resp double w0 byte cls
1 10 1
0 20 1
1 30 1
1 40 1
end
capture which survwgt
if _rc {
    global rtm_test_note "$rtm_test_note (survwgt not installed: class test skipped)"
}
else {
    rtmweight nonresponse resp, weight(w0) method(classes) classes(cls) generate(w1)
    assert reldif(w1[1], 12.5) < 1e-10
    assert w1[2] == 0
    assert reldif(w1[3], 37.5) < 1e-10
    assert reldif(w1[4], 50) < 1e-10
    assert reldif(r(sum_adj), 100) < 1e-10
    assert reldif(r(factor_min), 1.25) < 1e-10
}

* ---------- 3. propensity adjustment: factor equals 1/mean(phat) of the group ----------
use "../data/rtm_round1.dta", clear
rtmweight nonresponse responded_r1, weight(w_base) method(logit) covariates(urban i.educ head_age assets hhsize) ngroups(5) generate(w1p)
local nresp = r(N_resp)
local nsamp = r(N_sample)
matrix G = r(groups)
* recompute by hand
quietly logit responded_r1 urban i.educ head_age assets hhsize
predict double ph, pr
xtile g5 = ph, nq(5)
bysort g5: egen double pm = mean(ph)
gen double w1h = w_base / pm if responded_r1
assert reldif(w1p, w1h) < 1e-9 if responded_r1
assert w1p == 0 if responded_r1 == 0
assert `nresp' == 724 & `nsamp' == 939
assert rowsof(G) == 5
* probit within by-groups runs and gives positive factors
rtmweight nonresponse responded_r1, weight(w_base) method(probit) covariates(i.educ head_age assets) by(urban) generate(w1pb)
assert r(factor_min) > 0

* ---------- 4. trimming by hand ----------
clear
set obs 10
gen double w = _n
* winsor at the 80th percentile: Stata's percentile of 1..10 at 80 is 8.5 (_pctile); weights 9, 10 -> 8.5; then rescale
_pctile w, percentiles(80)
local p80 = r(r1)
rtmweight trim w, generate(wt) rule(winsor) pct(80)
assert r(n_trimmed_high) == 2
local sumtrim = 36 + 2 * `p80'
assert reldif(wt[10], `p80' * 55 / `sumtrim') < 1e-10
quietly summarize wt
assert reldif(r(sum), 55) < 1e-10
* cap at 6 without rescaling
rtmweight trim w, generate(wc) rule(cap) cap(6) norescale
assert wc[10] == 6 & wc[5] == 5
assert r(n_trimmed_high) == 4
* lower trimming
rtmweight trim w, generate(wl) rule(winsor) pct(90) lowpct(10)
assert r(n_trimmed_low) >= 1

* ---------- 5. synthetic data: totals preserved through the chain ----------
use "../data/rtm_baseline.dta", clear
merge 1:1 hhid using "../data/rtm_round1.dta", keepusing(responded_r1) nogenerate
quietly summarize w_base
local s = r(sum)
assert reldif(`s', 59831) < 1e-9
rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
assert r(factor_min) > 1
keep if phone == 1
quietly summarize w0
assert reldif(r(sum), `s') < 1e-9
capture which survwgt
if !_rc {
    rtmweight nonresponse responded_r1, weight(w0) method(classes) classes(region urban) generate(w1c)
    quietly summarize w1c if responded_r1
    assert reldif(r(sum), `s') < 1e-9
}
di as result "test_weights: all assertions passed"
