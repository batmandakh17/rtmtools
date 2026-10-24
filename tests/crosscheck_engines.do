* crosscheck_engines.do -- computes the figures quoted in ../VALIDATION.md: the largest relative
* differences between the calibration engines, the ReGenesees reference example, and ReGenesees'
* svystatTM against rtmest on the same design. It reports; the pass/fail versions of these checks
* are in test_calibrate.do and test_est.do. Needs R with ReGenesees and haven for the R parts.
clear
set more off
set linesize 200
adopath ++ "`c(pwd)'/.."
local pairs "1.region=14781 2.region=15345 3.region=14898 4.region=14807 0.urban=31458 1.urban=28373"

* ---------- the synthetic data and the weights ----------
use "../data/rtm_baseline.dta", clear
quietly count
local n_base = r(N)
merge 1:1 hhid using "../data/rtm_round1.dta", keepusing(responded_r1 skipmeal_r1 worked_r1) nogenerate
quietly rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
keep if phone == 1
quietly count
local n_phone = r(N)
quietly count if responded_r1
local n_resp = r(N)
di as txt _n "synthetic data: baseline households " as res `n_base' as txt ", phone subsample " as res `n_phone' ///
    as txt ", round-1 respondents " as res `n_resp'
quietly rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)

* ---------- 1. calibration engines ----------
quietly rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2) totals(`pairs')
di as txt _n "svycal rake, largest relative gap to the totals: " as res %9.2e r(max_rel_diff)
quietly rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2i) engine(ipfraking) totals(`pairs')
di as txt "ipfraking, largest relative gap to the totals:   " as res %9.2e r(max_rel_diff)
quietly rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2g) engine(regenesees) ids(hhid) strata(stratum) totals(`pairs')
di as txt "ReGenesees raking, largest relative gap:         " as res %9.2e r(max_rel_diff)
quietly rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2r) method(regress) totals(`pairs')
capture quietly rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2gr) engine(regenesees) ids(hhid) strata(stratum) totals(`pairs') distance(linear)
local rc_lin = _rc
gen double d_ipf = reldif(w2i, w2) if responded_r1
gen double d_rg = reldif(w2g, w2) if responded_r1
gen double d_rl = reldif(w2r, w2) if responded_r1
quietly summarize d_ipf
di as txt _n "raking: svycal vs ipfraking, largest relative difference in a weight:  " as res %9.2e r(max)
quietly summarize d_rg
di as txt "raking: svycal vs ReGenesees, largest relative difference in a weight: " as res %9.2e r(max)
if `rc_lin' == 0 {
    gen double d_lin = reldif(w2gr, w2r) if responded_r1
    quietly summarize d_lin
    di as txt "linear: svycal regress vs ReGenesees linear, largest relative difference: " as res %9.2e r(max)
}
else di as txt "linear cross-check not run (rc = `rc_lin')"
quietly summarize d_rl
di as txt "(for scale) raking vs linear weights in svycal differ by up to:        " as res %9.2e r(max)

* ---------- 2. ReGenesees' documented example (data.examples, pop02) ----------
_rtm_runr find
local rs "`r(rscript)'"
tempname fh
tempfile exdata extot exstatus exargs
quietly file open `fh' using "`exargs'", write text replace
file write `fh' "status=`exstatus'" _n "data=`exdata'" _n "totals=`extot'" _n
file close `fh'
quietly findfile rtm_refexample.R
local script "`r(fn)'"
shell "`rs'" --vanilla "`script'" "`exargs'" > /dev/null 2>&1
file open `fh' using "`exstatus'", read text
file read `fh' line
file read `fh' line2
file close `fh'
di as txt _n "reference example status: `line'; `line2'"
preserve
use "`extot'", clear
local expairs ""
quietly count
forvalues i = 1/`r(N)' {
    local expairs "`expairs' `=level[`i']'.`=variable[`i']'=`=total[`i']'"
}
use "`exdata'", clear
quietly rtmweight calibrate i.sex i.marstat [pw=weight], generate(w_stata) totals(`expairs')
gen double d_ex = reldif(w_stata, w_regenesees)
quietly summarize d_ex
di as txt "svycal vs ReGenesees' e.calibrate on its own example: n = " as res r(N) ///
    as txt ", largest relative difference in a weight " as res %9.2e r(max)
restore

* ---------- 3. rtmest against ReGenesees svystatTM on the same design ----------
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
local script "`r(fn)'"
shell "`rs'" --vanilla "`script'" "`sargs'" > /dev/null 2>&1
file open `fh' using "`sst'", read text
file read `fh' line
file read `fh' line2
file close `fh'
di as txt _n "svystatTM status: `line'; `line2'"
if "`line'" == "ok" {
    quietly rtmest skipmeal_r1 if responded_r1, weightvar(w1) strata(stratum) psu(psu) nocalibration
    matrix T0 = r(table)
    quietly rtmest skipmeal_r1 if responded_r1, weightvar(w2) strata(stratum) psu(psu)
    matrix T1 = r(table)
    preserve
    use "`sout'", clear
    local est0 = est[1]
    local se0 = se[1]
    local est1 = est[2]
    local se1 = se[2]
    restore
    di as txt "mean of skipmeal_r1 with the adjusted weights"
    di as txt "   rtmest:     " as res %10.7f T0[1,1] as txt "  SE " as res %10.7f T0[1,2]
    di as txt "   ReGenesees: " as res %10.7f `est0' as txt "  SE " as res %10.7f `se0'
    di as txt "   relative difference: estimate " as res %9.2e reldif(T0[1,1], `est0') as txt ", SE " as res %9.2e reldif(T0[1,2], `se0')
    di as txt "mean of skipmeal_r1 with the raked weights (calibration in the variance)"
    di as txt "   rtmest:     " as res %10.7f T1[1,1] as txt "  SE " as res %10.7f T1[1,2]
    di as txt "   ReGenesees: " as res %10.7f `est1' as txt "  SE " as res %10.7f `se1'
    di as txt "   relative difference: estimate " as res %9.2e reldif(T1[1,1], `est1') as txt ", SE " as res %9.2e reldif(T1[1,2], `se1')
}
