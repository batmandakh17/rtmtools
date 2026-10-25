* test_calibrate.do -- calibration: svycal against the totals, the ipfraking cross-check,
* post-stratification by hand, totals from a file, bounds; no R
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

* ---------- 6. the engine without R: the regenesees options are gone ----------
capture rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2z) engine(regenesees) totals(`pairs')
assert _rc == 198
di as result "test_calibrate: all assertions passed"
