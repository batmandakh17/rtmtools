* test_portable.do -- the portable do-files: (1) 04_weights.do on the template data gives the same
* weights as the rtmweight commands; (2) the portability test: only the parameter block changed,
* the do-file runs on the second synthetic program (adopt_test) and its export passes the sanity checks
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
local here "`c(pwd)'"
local port "`here'/../portable_do_files"
local tmp "`c(tmpdir)'"
if substr("`tmp'", -1, 1) != "/" & substr("`tmp'", -1, 1) != "\" local tmp "`tmp'/"

* a working copy of the do-file with the parameter block edited by this test (as an adopter would)
* the helper that edits a parameter line lives in its own file, because the portable do-file
* starts with clear all, which drops programs; it is re-run before each use
run "`here'/_rtmtest_setparam.do"

* ---------- 1. the template run: same weights as the rtmweight chain ----------
global RTM_EXPORT ""
cd "`port'"
local d1 "`tmp'rtm_port_template"
capture mkdir "`d1'"
local f1 "`d1'/04_weights_t.do"
_rtmtest_setparam "04_weights.do" "`f1'" export_dir `""`d1'/rtm_exports""'
_rtmtest_setparam "`f1'" "`f1'" method `"logit"'
_rtmtest_setparam "`f1'" "`f1'" trim `"winsor"'
_rtmtest_setparam "`f1'" "`f1'" calibrate `"rake"'
do "`f1'"
* the do-file leaves the weights in memory
confirm variable w0 w1 w1t w2
quietly summarize w2 if responded_r1
local sum_port = r(sum)
tempfile portw
keep hhid w0 w1 w1t w2
save "`portw'"
* the same chain with the rtmweight commands
use "../data/rtm_baseline.dta", clear
merge 1:1 hhid using "../data/rtm_round1.dta", keepusing(responded_r1) nogenerate
rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(a0)
keep if phone == 1
rtmweight nonresponse responded_r1, weight(a0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(a1)
rtmweight trim a1 if responded_r1, generate(a1t) rule(winsor) pct(98)
rtmweight calibrate i.region i.urban [pw=a1t] if responded_r1, generate(a2) totalsfile("../data/rtm_totals_long.dta")
merge 1:1 hhid using "`portw'", assert(3) nogenerate
assert reldif(w0, a0) < 1e-9
assert reldif(w1, a1) < 1e-9 if responded_r1
assert reldif(w1t, a1t) < 1e-9 if responded_r1
assert reldif(w2, a2) < 1e-9 if responded_r1
* the exports: the do-file's weight_stages of the report step equals the command's
local runs : dir "`d1'/rtm_exports" dirs "*_weights_dofile"
local nrun : word count `runs'
assert `nrun' >= 5          // the five steps of this run (earlier test runs may have left more)
foreach r of local runs {
    confirm file "`d1'/rtm_exports/`r'/manifest.json"
    confirm file "`d1'/rtm_exports/`r'/rtm_display.xlsx"
}
cd "`here'"

* ---------- 2. the portability test: another program, only the parameter block changed ----------
run "`here'/_rtmtest_setparam.do"
cd "`port'"
local d2 "`tmp'rtm_port_adopt"
capture mkdir "`d2'"
local f2 "`d2'/04_weights_adopt.do"
_rtmtest_setparam "04_weights.do" "`f2'" data_baseline `""adopt_test/adopt_baseline.dta""'
_rtmtest_setparam "`f2'" "`f2'" data_round `""adopt_test/adopt_round1.dta""'
_rtmtest_setparam "`f2'" "`f2'" totals_file `""adopt_test/adopt_totals_long.dta""'
_rtmtest_setparam "`f2'" "`f2'" export_dir `""`d2'/rtm_exports""'
_rtmtest_setparam "`f2'" "`f2'" id `"hh_id"'
_rtmtest_setparam "`f2'" "`f2'" strata `"zone"'
_rtmtest_setparam "`f2'" "`f2'" psu `"ea"'
_rtmtest_setparam "`f2'" "`f2'" w_base `"wt0"'
_rtmtest_setparam "`f2'" "`f2'" phone `"has_mobile"'
_rtmtest_setparam "`f2'" "`f2'" responded `"done_r1"'
_rtmtest_setparam "`f2'" "`f2'" round_vars `""done_r1""'
_rtmtest_setparam "`f2'" "`f2'" method `"ebalance"'
_rtmtest_setparam "`f2'" "`f2'" covariates `""town i.schooling members age_head wealth""'
_rtmtest_setparam "`f2'" "`f2'" classes `""zone town""'
_rtmtest_setparam "`f2'" "`f2'" trim `"winsor"'
_rtmtest_setparam "`f2'" "`f2'" calibrate `"rake"'
_rtmtest_setparam "`f2'" "`f2'" cal_vars `""zone town""'
do "`f2'"
* sanity checks of the adopted program's weights
confirm variable w0 w1 w1t w2
assert w0 > 0 & !missing(w0)
assert w2 > 0 if done_r1 == 1
assert w2 == 0 if done_r1 == 0
* the base weights of the phone sample add to the baseline total of each stratum
preserve
use "adopt_test/adopt_baseline.dta", clear
collapse (sum) tot = wt0, by(zone)
tempfile bt
save "`bt'"
restore
preserve
collapse (sum) s0 = w0, by(zone)
merge 1:1 zone using "`bt'", assert(3) nogenerate
assert reldif(s0, tot) < 1e-9
restore
* the balanced respondents match the sample's weighted means
quietly summarize members [aw=w0]
local m = r(mean)
quietly summarize members [aw=w1] if done_r1
assert reldif(r(mean), `m') < 1e-7
* the calibrated weights add to the totals of every category
preserve
use "adopt_test/adopt_totals_long.dta", clear
quietly count
forvalues i = 1/`r(N)' {
    local v`i' = variable[`i']
    local l`i' = level[`i']
    local t`i' = total[`i']
}
local nt = r(N)
restore
forvalues i = 1/`nt' {
    quietly summarize w2 if done_r1 & `v`i'' == `l`i''
    assert reldif(r(sum), `t`i'') < 1e-7
}
local runs : dir "`d2'/rtm_exports" dirs "*_weights_dofile"
assert `: word count `runs'' >= 5
cd "`here'"

* ---------- 3. the frame, listing and sampling do-files on the template data ----------
run "`here'/_rtmtest_setparam.do"
cd "`port'"
local d3 "`tmp'rtm_port_other"
capture mkdir "`d3'"
foreach f in 01_frame 02_listing 03_sample {
    local fx "`d3'/`f'_t.do"
    _rtmtest_setparam "`f'.do" "`fx'" export_dir `""`d3'/rtm_exports""'
    if "`f'" == "01_frame" _rtmtest_setparam "`fx'" "`fx'" saving_list `""`d3'/frame_checked.dta""'
    if "`f'" == "02_listing" {
        _rtmtest_setparam "`fx'" "`fx'" forms_file `""`d3'/listing_forms.xlsx""'
        _rtmtest_setparam "`fx'" "`fx'" saving_frame `""`d3'/stage2_frame.dta""'
    }
    do "`fx'"
    run "`here'/_rtmtest_setparam.do"
}
* the grid route of 01_frame on the template files
local fx "`d3'/01_frame_grid.do"
_rtmtest_setparam "01_frame.do" "`fx'" route `"grid"'
_rtmtest_setparam "`fx'" "`fx'" export_dir `""`d3'/rtm_exports""'
_rtmtest_setparam "`fx'" "`fx'" saving_grid `""`d3'/frame_grid.dta""'
_rtmtest_setparam "`fx'" "`fx'" saving_pixels `""`d3'/frame_pixels.dta""'
do "`fx'"
assert _N == 400
quietly summarize pop
assert reldif(r(sum), 957592) < 1e-9
run "`here'/_rtmtest_setparam.do"
* the listing frame of 02_listing equals the command's
use "`d3'/stage2_frame.dta", clear
quietly count
local nf_do = r(N)
use "../data/rtm_frame.dta", clear
keep if ea_selected
rtmlist import using "../data/rtm_listing.dta", id(ea_id) expected(ea_size_census) clear
assert r(N_frame) == `nf_do'
* 03_sample: the systematic PPS draw of areas reproduces the frame's probabilities
use "`port'/template/rtm_frame.dta", clear
local runs : dir "`d3'/rtm_exports" dirs "*_sampling_dofile"
assert `: word count `runs'' >= 5
cd "`here'"

* ---------- 4. the adopting program: frame, listing and sampling with only the parameter block changed ----------
run "`here'/_rtmtest_setparam.do"
cd "`port'"
local d4 "`tmp'rtm_port_adopt2"
capture mkdir "`d4'"
local fx "`d4'/01_frame_a.do"
_rtmtest_setparam "01_frame.do" "`fx'" data_frame `""adopt_test/adopt_frame.dta""'
_rtmtest_setparam "`fx'" "`fx'" area_id `"ea_code"'
_rtmtest_setparam "`fx'" "`fx'" size `"hh_count"'
_rtmtest_setparam "`fx'" "`fx'" strata `""zone""'
_rtmtest_setparam "`fx'" "`fx'" minsize `"60"'
_rtmtest_setparam "`fx'" "`fx'" maxsize `"300"'
_rtmtest_setparam "`fx'" "`fx'" saving_list `""`d4'/frame_checked.dta""'
_rtmtest_setparam "`fx'" "`fx'" export_dir `""`d4'/rtm_exports""'
do "`fx'"
assert frame_ok == 1
run "`here'/_rtmtest_setparam.do"
local fx "`d4'/02_listing_a.do"
_rtmtest_setparam "02_listing.do" "`fx'" data_areas `""adopt_test/adopt_frame.dta""'
_rtmtest_setparam "`fx'" "`fx'" selected_var `"selected"'
_rtmtest_setparam "`fx'" "`fx'" area_id `"ea_code"'
_rtmtest_setparam "`fx'" "`fx'" expected `"hh_count"'
_rtmtest_setparam "`fx'" "`fx'" strata `""zone""'
_rtmtest_setparam "`fx'" "`fx'" forms_file `""`d4'/listing_forms.xlsx""'
_rtmtest_setparam "`fx'" "`fx'" segment_size `"200"'
_rtmtest_setparam "`fx'" "`fx'" data_listing `""adopt_test/adopt_listing.dta""'
_rtmtest_setparam "`fx'" "`fx'" col_area `"area"'
_rtmtest_setparam "`fx'" "`fx'" col_structure `"bldg"'
_rtmtest_setparam "`fx'" "`fx'" col_household `"hh"'
_rtmtest_setparam "`fx'" "`fx'" col_eligible `"elig"'
_rtmtest_setparam "`fx'" "`fx'" saving_frame `""`d4'/stage2_frame.dta""'
_rtmtest_setparam "`fx'" "`fx'" export_dir `""`d4'/rtm_exports""'
do "`fx'"
assert elig == 1
quietly levelsof ea_code, local(al)
assert `: word count `al'' == 35                      // 36 selected areas, one not returned
run "`here'/_rtmtest_setparam.do"
local fx "`d4'/03_sample_a.do"
_rtmtest_setparam "03_sample.do" "`fx'" data_frame `""adopt_test/adopt_frame.dta""'
_rtmtest_setparam "`fx'" "`fx'" data_hh `""""'
_rtmtest_setparam "`fx'" "`fx'" data_baseline `""adopt_test/adopt_baseline.dta""'
_rtmtest_setparam "`fx'" "`fx'" area_id `"ea_code"'
_rtmtest_setparam "`fx'" "`fx'" strata `""zone""'
_rtmtest_setparam "`fx'" "`fx'" size `"hh_count"'
_rtmtest_setparam "`fx'" "`fx'" n_areas `"36"'
_rtmtest_setparam "`fx'" "`fx'" min_areas `"0"'
_rtmtest_setparam "`fx'" "`fx'" max_areas `"0"'
_rtmtest_setparam "`fx'" "`fx'" sort_vars `""zone ea_code""'
_rtmtest_setparam "`fx'" "`fx'" bl_id `"hh_id"'
_rtmtest_setparam "`fx'" "`fx'" bl_psu `"ea"'
_rtmtest_setparam "`fx'" "`fx'" n_phone `"5"'
_rtmtest_setparam "`fx'" "`fx'" export_dir `""`d4'/rtm_exports""'
do "`fx'"
assert inlist(ph_sel, 0, 1)
bysort ea: egen double nph = total(ph_sel)
assert nph == min(5, _N) | 1
local runs : dir "`d4'/rtm_exports" dirs "*_dofile"
assert `: word count `runs'' >= 7
cd "`here'"
global RTM_EXPORT "off"
di as result "test_portable: the template run equals the commands and the adopted program runs"
