* test_repro.do -- rerunning the recorded commands reproduces the weights exactly (including a
* command with a quoted file name), and the dataset and the weight variables carry the record
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
use "../data/rtm_baseline.dta", clear
merge 1:1 hhid using "../data/rtm_round1.dta", keepusing(responded_r1 skipmeal_r1) nogenerate
local pairs "1.region=14781 2.region=15345 3.region=14898 4.region=14807 0.urban=31458 1.urban=28373"
rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
keep if phone == 1
rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)
rtmweight trim w1 if responded_r1, generate(w1t) rule(winsor) pct(98)
rtmweight calibrate i.region i.urban [pw=w1t] if responded_r1, generate(w2) totals(`pairs')
local c3 : char _dta[rtm_calibrate]
rtmweight calibrate i.region i.urban [pw=w1t] if responded_r1, generate(w2f) totalsfile("../data/rtm_totals_long.dta")
local c4 : char _dta[rtm_calibrate]
tempfile first
save "`first'"
* the record: dataset characteristics, notes, and each weight's own characteristics
local c0 : char _dta[rtm_base]
local c1 : char _dta[rtm_nonresponse]
local c2 : char _dta[rtm_trim]
assert "`c0'" != "" & "`c1'" != "" & "`c2'" != "" & "`c3'" != "" & `"`c4'"' != ""
assert strpos(`"`c4'"', `"totalsfile("../data/rtm_totals_long.dta")"')
local st : char _dta[rtm_calibrate_stamp]
assert strpos("`st'", "rtmtools 0.2.0")
assert strpos("`st'", "Stata")
local v2 : char w2[rtm_cmd]
assert `"`v2'"' == `"`c3'"'
local v2f : char w2f[rtm_cmd]
assert `"`v2f'"' == `"`c4'"'
local vstep : char w1t[rtm_step]
assert "`vstep'" == "trim"
notes _dta
* rerun from the recorded commands on a fresh copy
use "../data/rtm_baseline.dta", clear
merge 1:1 hhid using "../data/rtm_round1.dta", keepusing(responded_r1 skipmeal_r1) nogenerate
`c0'
keep if phone == 1
`c1'
`c2'
`c3'
`c4'
rename (w0 w1 w1t w2 w2f) (v0 v1 v1t v2 v2f)
merge 1:1 hhid using "`first'", keepusing(w0 w1 w1t w2 w2f) nogenerate
assert reldif(v0, w0) < 1e-12
assert reldif(v1, w1) < 1e-12 if responded_r1
assert reldif(v1t, w1t) < 1e-12 if responded_r1
assert reldif(v2, w2) < 1e-12 if responded_r1
assert reldif(v2f, w2f) < 1e-12 if responded_r1
di as result "test_repro: all assertions passed"
