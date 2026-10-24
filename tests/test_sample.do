* test_sample.do -- rtmsample: reference examples (UN 2008, HFPS Vol. 2 Table 1, MPPS 2016), hand
* calculations for allocation and systematic selection, inclusion probabilities against the synthetic
* frame and by Monte Carlo, reserve flags, reproducibility with the seed, bad inputs
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."

* ---------- 1. size: UN 2008 examples B, C, D (paras 61-63) with the deff of 1.2 their formula 3.8 carries ----------
rtmsample size, p(0.1) share(0.65) hhsize(6) deff(1.2)
assert abs(r(n_select) / 1170 - 1) < 0.005
rtmsample size, p(0.05) share(0.15) hhsize(6) deff(1.2)
assert abs(r(n_select) / 10704 - 1) < 0.005
rtmsample size, p(0.05) hhsize(6) deff(1.2)
assert r(n_select) > 1600 & r(n_select) < 1610
* the level formula by hand: z^2 p(1-p)/e^2 with e = 0.10 p
local z = invnormal(0.975)
assert reldif(r(n_srs), `z'^2 * 0.05 * 0.95 / 0.005^2) < 1e-10
assert reldif(r(n_deff), r(n_srs) * 1.2) < 1e-10
assert reldif(r(n_hh), r(n_deff) / 6) < 1e-10
assert reldif(r(n_select), r(n_hh) * 1.1) < 1e-10

* ---------- 2. size: HFPS Vol. 2 Table 1 (p. 5), all six cells ----------
foreach pw in 0.8 0.9 {
    foreach d in 0.05 0.10 0.15 {
        rtmsample size, p(0.5) change(-`d') power(`pw') deff(1) nonresponse(1)
        local got = r(n_srs)
        quietly power twoproportions 0.5 `=0.5-`d'', power(`pw')
        assert `got' == r(N1)
    }
}
rtmsample size, p(0.5) change(-0.10) power(0.8) deff(1) nonresponse(1)
assert r(n_srs) == 388
rtmsample size, p(0.5) change(-0.10) power(0.9) deff(1) nonresponse(1)
assert r(n_srs) == 519
rtmsample size, p(0.5) change(-0.05) power(0.8) deff(2.5) nonresponse(1)
assert r(n_domain) == ceil(1565 * 2.5)

* ---------- 3. size: MPPS 2016 attrition reserve (p. 45): 1,438 and 1,573 from 1,000 ----------
rtmsample size, p(0.5) margin(0.05) deff(1) nonresponse(1) attrition(0.015) rounds(24)
assert reldif(r(f_attrition), 1 / 0.985^24) < 1e-12
assert ceil(1000 * r(f_attrition) - 1e-9) == 1438
rtmsample size, p(0.5) margin(0.05) deff(1) nonresponse(1) attrition(0.015) rounds(24) firstloss(0.10)
assert reldif(r(f_attrition), 1 / (0.9 * 0.985^23)) < 1e-12
assert ceil(1000 * r(f_attrition) - 1e-9) == 1573
* domains multiply the rounded per-domain size
rtmsample size, p(0.5) margin(0.05) deff(1) nonresponse(1) domains(3)
assert r(n_total) == 3 * r(n_domain)
assert r(n_domain) == ceil(`z'^2 * 0.25 / 0.0025 - 1e-9)
* continuous: z^2 s^2 / e^2 and power twomeans
rtmsample size, mean(100) sd(40) relmargin(0.05) deff(1) nonresponse(1)
assert reldif(r(n_srs), `z'^2 * 1600 / 25) < 1e-10
rtmsample size, mean(100) sd(40) change(10) power(0.8) deff(1) nonresponse(1)
local got = r(n_srs)
quietly power twomeans 100 110, sd(40) power(0.8)
assert `got' == r(N1)

* ---------- 4. allocate: hand calculations on a two-stratum table ----------
clear
input byte str double Nh double S
1 1000 2
2 3000 1
end
rtmsample allocate, strata(str) n(400) size(Nh)
matrix A = r(alloc)
assert A[1, 4] == 100 & A[2, 4] == 300
assert reldif(A[1, 5], 10) < 1e-12
rtmsample allocate, strata(str) n(400) size(Nh) method(equal)
matrix A = r(alloc)
assert A[1, 4] == 200 & A[2, 4] == 200
rtmsample allocate, strata(str) n(400) size(Nh) method(neyman) sd(S)
matrix A = r(alloc)
assert A[1, 4] == 160 & A[2, 4] == 240
rtmsample allocate, strata(str) n(400) size(Nh) method(power) power(0.5)
matrix A = r(alloc)
assert reldif(A[1, 3], 400 * sqrt(1000) / (sqrt(1000) + sqrt(3000))) < 1e-10
assert A[1, 4] + A[2, 4] == 400
rtmsample allocate, strata(str) n(400) size(Nh) min(150) generate(nh)
matrix A = r(alloc)
assert A[1, 4] == 150 & A[2, 4] == 250
assert nh[1] == 150 & nh[2] == 250
assert r(n_bounded) == 1
* rounding keeps the total on a three-stratum table with awkward fractions
clear
input byte str double Nh
1 100
2 100
3 100
end
rtmsample allocate, strata(str) n(10) size(Nh)
matrix A = r(alloc)
assert A[1, 4] + A[2, 4] + A[3, 4] == 10
assert r(n_rounded) == 10
* a unit-level frame: the cap by the number of units applies
clear
set obs 30
gen byte str = 1 + (_n > 20)
gen double sz = 100
rtmsample allocate, strata(str) n(25) size(sz)
matrix A = r(alloc)
assert A[1, 4] <= 20 & A[2, 4] <= 10
assert A[1, 4] + A[2, 4] == 25

* ---------- 5. draw: the frame's own PPS probabilities reproduced exactly (ppssys and pps) ----------
use "../data/rtm_frame.dta", clear
rtmsample draw, n(n_ea_str) strata(stratum) pps(ea_size_census) sort(ea_id) seed(12345) generate(a)
assert reldif(a_pi, pi_ea) < 1e-12
assert r(n_selected) == 100
assert r(n_certainty) == 0
quietly count if a_sel == 1
assert r(N) == 100
bysort stratum: egen double nsel = total(a_sel)
assert nsel == n_ea_str
* HT estimate of the stratum size is exact
bysort stratum: egen double ht = total(cond(a_sel, ea_size_census / a_pi, 0))
assert reldif(ht, N_str) < 1e-9
rtmsample draw, n(n_ea_str) strata(stratum) pps(ea_size_census) method(pps) seed(7) generate(b)
assert reldif(b_pi, pi_ea) < 1e-12
assert r(n_selected) == 100
* the written weight is 1/pi for selected units and missing otherwise
assert reldif(a_w, 1 / a_pi) < 1e-12 if a_sel == 1
assert missing(a_w) if a_sel == 0

* ---------- 6. draw: equal-probability methods, reserve flags, systematic order ----------
rtmsample draw, n(5) strata(stratum) reserve(2) seed(3) generate(c)
assert reldif(c_pi, 5 / 60) < 1e-12 if inlist(stratum, 1, 3, 5, 7)
assert reldif(c_pi, 5 / 40) < 1e-12 if inlist(stratum, 2, 4, 6, 8)
assert r(n_selected) == 40 & r(n_reserve) == 16
bysort stratum: egen double nres = total(c_reserve > 0)
assert nres == 2
assert c_reserve == 0 if c_sel == 1
bysort stratum (c_reserve): assert c_reserve[_N] == 2 & c_reserve[_N - 1] == 1
rtmsample draw, n(12) strata(stratum) method(systematic) sort(ea_id) seed(4) generate(d)
assert reldif(d_pi, 12 / 60) < 1e-12 if inlist(stratum, 1, 3, 5, 7)
bysort stratum: egen double nsel_d = total(d_sel)
assert nsel_d == 12
* systematic: exactly one selection in every interval of 5 units (60/12) when sorted by ea_id
sort stratum ea_id
by stratum: gen int pos = _n
by stratum: gen int block = ceil(pos / (_N / 12)) if inlist(stratum, 1, 3, 5, 7)
bysort stratum block: egen double nblk = total(d_sel) if !missing(block)
assert nblk == 1 if !missing(block)
* selection order runs 1..n_h
bysort stratum (d_order): assert d_order[_N] == 12 if d_sel[_N] == 1

* ---------- 7. draw: certainty units ----------
clear
input byte id double sz
1 50
2 60
3 70
4 2000
5 80
end
rtmsample draw, n(2) pps(sz) seed(1) generate(c)
assert c_cert[4] == 1 & c_sel[4] == 1 & c_pi[4] == 1
assert reldif(c_pi[5], 80 / 260) < 1e-12
assert r(n_certainty) == 1 & r(n_selected) == 2
rtmsample draw, n(2) pps(sz) method(pps) seed(1) generate(g)
assert g_cert[4] == 1 & g_pi[4] == 1
assert reldif(g_pi[1], 50 / 260) < 1e-12

* ---------- 8. draw: Monte Carlo inclusion frequencies against pi (ppssys and pps) ----------
clear
set obs 6
gen byte id = _n
gen double sz = 10 * _n
gen double pi = 2 * sz / 210
gen double hit_sys = 0
gen double hit_pps = 0
local R 300
forvalues r = 1/`R' {
    quietly rtmsample draw, n(2) pps(sz) seed(`r') generate(s)
    quietly replace hit_sys = hit_sys + s_sel
    drop s_*
    quietly rtmsample draw, n(2) pps(sz) method(pps) seed(`=`r'+10000') generate(s)
    quietly replace hit_pps = hit_pps + s_sel
    drop s_*
}
gen double se = sqrt(pi * (1 - pi) / `R')
assert abs(hit_sys / `R' - pi) < 4 * se
assert abs(hit_pps / `R' - pi) < 4 * se
list id sz pi hit_sys hit_pps se, clean noobs

* ---------- 9. draw: second stage on the synthetic population reproduces the baseline's pi_hh ----------
use "../data/rtm_frame.dta", clear
keep if ea_selected
keep ea_id pi_ea
tempfile sel
quietly save "`sel'"
use "../data/rtm_population.dta", clear
quietly merge m:1 ea_id using "`sel'", keep(match) nogenerate
rtmsample draw, n(12) strata(ea_id) seed(99) generate(h)
assert r(n_selected) == 1200 & r(H) == 100
bysort ea_id: egen double M = total(1)
assert reldif(h_pi, 12 / M) < 1e-12
preserve
use "../data/rtm_baseline.dta", clear
keep ea_id pi_hh
quietly duplicates drop
tempfile bl
quietly save "`bl'"
restore
quietly merge m:1 ea_id using "`bl'", keep(match) nogenerate
assert reldif(h_pi, pi_hh) < 1e-12

* ---------- 10. reproducibility: the seed and the recorded command ----------
use "../data/rtm_frame.dta", clear
rtmsample draw, n(n_ea_str) strata(stratum) pps(ea_size_census) sort(ea_id) generate(x)
local seed = r(seed)
local cmd `"`r(cmdline)'"'
assert strpos(`"`cmd'"', "seed(`seed')")
local c : char _dta[rtm_draw]
assert `"`c'"' == `"`cmd'"'
local vc : char x_sel[rtm_cmd]
assert `"`vc'"' == `"`cmd'"'
rename (x_sel x_pi x_order) (y_sel y_pi y_order)
drop x_*
`cmd'
assert x_sel == y_sel & reldif(x_pi, y_pi) < 1e-12 & (x_order == y_order | y_sel == 0)
rtmsample draw, n(n_ea_str) strata(stratum) pps(ea_size_census) sort(ea_id) seed(`seed') generate(z)
assert z_sel == y_sel
* a different seed gives a different sample
rtmsample draw, n(n_ea_str) strata(stratum) pps(ea_size_census) sort(ea_id) seed(`=`seed'+1') generate(v)
quietly count if v_sel != y_sel
assert r(N) > 0
* allocate then draw with the allocation variable
rtmsample allocate, strata(stratum) n(100) size(ea_size_census) min(10) max(16) generate(n_ea)
rtmsample draw, n(n_ea) strata(stratum) pps(ea_size_census) sort(region urban ea_id) seed(5) generate(e)
local nsel_e = r(n_selected)
bysort stratum: egen double ne = total(e_sel)
assert ne == n_ea
assert `nsel_e' == 100

* ---------- 11. bad inputs ----------
use "../data/rtm_frame.dta", clear
capture noisily rtmsample draw, n(70) strata(stratum) seed(1) generate(q)
assert _rc == 459
capture noisily rtmsample draw, n(5) strata(stratum) method(pps) seed(1) generate(q)
assert _rc == 198
capture noisily rtmsample draw, n(5) strata(stratum) sort(ea_id) seed(1) generate(q)
assert _rc == 198
gen double sz0 = ea_size_census
replace sz0 = 0 in 1
capture noisily rtmsample draw, n(5) strata(stratum) pps(sz0) seed(1) generate(q)
assert _rc == 459
capture noisily rtmsample draw, n(5) strata(stratum) seed(1.5) generate(q)
assert _rc == 198
capture noisily rtmsample draw, n(n_ea_str) seed(1) generate(q)
assert _rc == 459
capture noisily rtmsample allocate, strata(stratum) n(100) size(ea_size_census) method(neyman)
assert _rc == 198
capture noisily rtmsample allocate, strata(stratum) n(50) size(ea_size_census) min(10)
assert _rc == 459
capture noisily rtmsample allocate, strata(stratum) n(100.5) size(ea_size_census)
assert _rc == 198
capture noisily rtmsample size, p(1.2)
assert _rc == 198
capture noisily rtmsample size, p(0.95) change(0.10)
assert _rc == 198
capture noisily rtmsample size, p(0.2) margin(0.02) relmargin(0.1)
assert _rc == 198
capture noisily rtmsample size, sd(40)
assert _rc == 198
capture noisily rtmsample frob, n(1)
assert _rc == 198
di as result "test_sample: all assertions passed"
