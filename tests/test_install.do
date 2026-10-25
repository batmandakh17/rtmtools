* test_install.do -- net install from the local package folder into a temporary ado directory,
* following only the README, then run the README's command sequence with that installation alone
clear
matrix drop _all
set more off
local here "`c(pwd)'"
local pkg "`here'/.."
tempfile dummy
local tmpado "`c(tmpdir)'/rtmtools_install_test"
capture mkdir "`tmpado'"
* install into the temporary PLUS directory
local oldplus "`c(sysdir_plus)'"
sysdir set PLUS "`tmpado'/"
capture net install rtmtools, from("`pkg'") replace
local rc_install = _rc
di "net install rc = `rc_install'"
assert `rc_install' == 0
* the installed files are found through PLUS only (the package folder is not on the adopath)
adopath
capture which rtmweight
assert _rc == 0
capture findfile rtmweight_base.dlg
assert _rc == 0
capture findfile rtmsample_grid.dlg
assert _rc == 0
capture findfile rtm_display.xlsx
assert _rc == 0
capture findfile rtmweight.sthlp
assert _rc == 0
* ancillary files
local olddir "`c(pwd)'"
cd "`tmpado'"
capture net get rtmtools, from("`pkg'") replace
di "net get rc = " _rc
capture confirm file "rtm_baseline.dta"
local rc_data = _rc
if `rc_data' {
    capture confirm file "data/rtm_baseline.dta"
    local rc_data = _rc
    if !`rc_data' local datadir "data/"
}
assert `rc_data' == 0
* the portable package: do-files, template data and the guide (a second .pkg, since one package file may list at most 100 files)
capture net get rtmtools_portable, from("`pkg'") replace
di "net get rtmtools_portable rc = " _rc
capture confirm file "04_weights.do"
local rc_port = _rc
if `rc_port' {
    capture confirm file "portable_do_files/04_weights.do"
    local rc_port = _rc
}
assert `rc_port' == 0
capture confirm file "ADAPTATION.md"
if _rc capture confirm file "portable_do_files/ADAPTATION.md"
assert _rc == 0
* the README sequence
use "`datadir'rtm_baseline", clear
merge 1:1 hhid using "`datadir'rtm_round1", keepusing(responded_r1 skipmeal_r1 worked_r1) nogenerate
rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
keep if phone == 1
rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)
rtmweight trim w1 if responded_r1, generate(w1t) rule(winsor) pct(98)
rtmweight calibrate i.region i.urban [pw=w1t] if responded_r1, generate(w2) totalsfile("`datadir'rtm_totals_long.dta")
rtmweight report w0 w1 w1t w2 if responded_r1, notes
rtmest skipmeal_r1 worked_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) over(urban)
rtmtools_setup, check nomenu
cd "`olddir'"
sysdir set PLUS "`oldplus'"
di as result "test_install: net install from the local folder and the README sequence passed"
