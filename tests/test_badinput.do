* test_badinput.do -- wrong variables, strings, empty data, missing options: clear errors, no crash
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
use "../data/rtm_round1.dta", clear
gen str8 sreg = string(region)

* both or neither mode in base
capture noisily rtmweight base, probability(pi_ea) baseweight(w_base) generate(x)
assert _rc == 198
capture noisily rtmweight base, generate(x)
assert _rc == 198
* string variable where numeric is expected
capture noisily rtmweight base, probability(sreg) generate(x)
assert _rc != 0
* probability out of range
gen double pbad = 1.5
capture noisily rtmweight base, probability(pbad) generate(x)
assert _rc == 459
* existing variable without replace
capture noisily rtmweight base, probability(pi_ea pi_hh) generate(w_base)
assert _rc == 110
rtmweight base, probability(pi_ea pi_hh) generate(w_base) replace
* response indicator not 0/1
capture noisily rtmweight nonresponse hhsize, weight(w_base) method(classes) classes(region) generate(x)
assert _rc == 450
* missing method information
capture noisily rtmweight nonresponse responded_r1, weight(w_base) generate(x)
assert _rc == 198
* non-positive weight
gen double wneg = -1
capture noisily rtmweight nonresponse responded_r1, weight(wneg) method(classes) classes(region) generate(x)
assert _rc == 459
* trim with a bad rule, bad percentile, cap without a bound
capture noisily rtmweight trim w_base, generate(x) rule(median)
assert _rc == 198
capture noisily rtmweight trim w_base, generate(x) rule(winsor) pct(120)
assert _rc == 198
capture noisily rtmweight trim w_base, generate(x) rule(cap)
assert _rc == 198
* calibrate: no weight, no totals, bad pair, unknown method, interaction term
capture noisily rtmweight calibrate i.region, generate(x) totals(1.region=1)
assert _rc == 198
capture noisily rtmweight calibrate i.region [pw=w_base], generate(x)
assert _rc == 198
capture noisily rtmweight calibrate i.region [pw=w_base], generate(x) totals(region=100)
assert _rc == 198
capture noisily rtmweight calibrate i.region [pw=w_base], generate(x) totals(1.region=1) method(logit)
assert _rc == 198
capture noisily rtmweight calibrate i.region#i.urban [pw=w_base], generate(x) totals(1.region=1)
assert _rc == 198
* rtmest: bad stat, ratio without variables, bad singleunit
capture noisily rtmest skipmeal_r1, weight(w_base) stat(median)
assert _rc == 198
capture noisily rtmest skipmeal_r1, weight(w_base) stat(ratio)
assert _rc == 198
capture noisily rtmest skipmeal_r1, weight(w_base) singleunit(drop)
assert _rc == 198
* empty data
clear
capture noisily rtmweight base, probability(p) generate(x)
assert _rc != 0
* dispatcher: unknown subcommand
use "../data/rtm_round1.dta", clear
capture noisily rtmweight frobnicate, generate(x)
assert _rc == 198
di as result "test_badinput: all assertions passed"
