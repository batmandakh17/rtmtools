* test_input.do -- rtminput: the input workbook (schema rtm-input-1.0) checked, planted problems
* found, the sampling and weighting runs equal to the commands typed directly, the CSV folder
* equal to the workbook, the commands do-file reproducing the run, and the portable filler
clear
matrix drop _all
set more off
adopath ++ "`c(pwd)'/.."
local here "`c(pwd)'"
local tmp "`c(tmpdir)'"
if substr("`tmp'", -1, 1) != "/" & substr("`tmp'", -1, 1) != "\" local tmp "`tmp'/"
local d "`tmp'rtm_input_test"
capture mkdir "`d'"
foreach f in rtm_baseline rtm_round1 rtm_population {
    copy "../data/`f'.dta" "`d'/`f'.dta", replace
}
copy "../rtm_inputs.xlsx" "`d'/rtm_inputs.xlsx", replace

* ---------- 1. the shipped template checks clean ----------
rtminput using "`d'/rtm_inputs.xlsx", check
assert r(n_errors) == 0 & r(n_warnings) == 0
assert strpos("`r(sheets)'", "design") & strpos("`r(sheets)'", "frame") & strpos("`r(sheets)'", "files")
confirm file "`d'/rtm_inputs_checked.xlsx"
import excel using "`d'/rtm_inputs_checked.xlsx", sheet("Checks") firstrow clear
assert _N == 1 & severity[1] == "ok"
* the template is also the installed one (findfile) and rtminput, template copies it
cd "`d'"
rtminput, template replace
confirm file "rtm_inputs.xlsx"
cd "`here'"

* ---------- 2. planted problems are found, with the sheet, row and column ----------
local pw "`d'/rtm_inputs_bad.xlsx"
import excel using "`d'/rtm_inputs.xlsx", sheet("Design") firstrow case(lower) allstring clear
quietly replace value = "nayman" if key == "allocation"
quietly replace value = "many" if key == "n_areas"
export excel using "`pw'", sheet("Design") firstrow(variables) replace
import excel using "`d'/rtm_inputs.xlsx", sheet("Strata") firstrow case(lower) clear
quietly drop in 8                                   // stratum 8 disappears: Frame rows will refer to it
export excel using "`pw'", sheet("Strata", replace) firstrow(variables)
import excel using "`d'/rtm_inputs.xlsx", sheet("Frame") firstrow case(lower) clear
quietly replace area_id = area_id[1] in 2            // a duplicate area_id (two rows flagged)
quietly replace size_hh = 0 in 3                    // a size that is not positive
export excel using "`pw'", sheet("Frame", replace) firstrow(variables)
import excel using "`d'/rtm_inputs.xlsx", sheet("Totals") firstrow case(lower) clear
quietly expand 2 in 1                               // a repeated category
export excel using "`pw'", sheet("Totals", replace) firstrow(variables)
import excel using "`d'/rtm_inputs.xlsx", sheet("Cells") firstrow case(lower) clear
export excel using "`pw'", sheet("Cells", replace) firstrow(variables)
import excel using "`d'/rtm_inputs.xlsx", sheet("Prefixes") firstrow case(lower) clear
export excel using "`pw'", sheet("Prefixes", replace) firstrow(variables)
import excel using "`d'/rtm_inputs.xlsx", sheet("Files") firstrow case(lower) allstring clear
quietly replace path = "nothere.dta" if role == "round"
export excel using "`pw'", sheet("Files", replace) firstrow(variables)
rtminput using "`pw'", check
local ne = r(n_errors)
di as text "planted problems found: `ne'"
assert `ne' == 8
import excel using "`d'/rtm_inputs_bad_checked.xlsx", sheet("Checks") firstrow clear
assert _N == 8
quietly count if sheet == "Frame" & column == "area_id" & inlist(row, 2, 3)
assert r(N) == 2                                     // the two duplicated rows, by their Excel row numbers
quietly count if sheet == "Frame" & column == "size_hh" & row == 4
assert r(N) == 1
quietly count if sheet == "Design" & strpos(problem, "allocation must be one of")
assert r(N) == 1
quietly count if sheet == "Design" & strpos(problem, "n_areas must be a number")
assert r(N) == 1
quietly count if sheet == "Totals" & strpos(problem, "repeat a variable and level")
assert r(N) == 1
quietly count if sheet == "Files" & column == "path" & strpos(problem, "not found")
assert r(N) == 1
quietly count if sheet == "Frame" & column == "stratum_id" & strpos(problem, "not on the Strata sheet")
assert r(N) == 1
* a run stops on errors
capture noisily rtminput using "`pw'", sampling outdir("`d'/out_bad")
assert _rc == 459

* ---------- 3. sampling from the workbook: the commands' results, reproducible from the commands do-file ----------
cd "`d'"
rtminput using "rtm_inputs.xlsx", sampling outdir("out1")
assert "`r(outdir)'" == "out1"
confirm file "out1/rtm_input_sampling_commands.do"
use "out1/rtm_sample_areas.dta", clear
quietly count if area_sel == 1
assert r(N) == 100
quietly count if area_reserve > 0
assert r(N) == 16                                    // 2 reserves x 8 strata
assert !missing(stratum_label)                       // the Strata labels were merged
use "out1/rtm_sample_households.dta", clear
assert _N == 1200                                    // 12 households x 100 areas
quietly summarize w_design
assert reldif(r(sum), 59831) < 1e-9                  // the design weights add to the population's households
use "out1/rtm_sample_phone.dta", clear
quietly count if ph_sel == 1
assert r(N) == 600                                   // 6 per PSU x 100 PSUs
quietly summarize w_phone
assert reldif(r(sum), 59831) < 1e-9
bysort psu (ph_reserve): assert ph_reserve[_N] == 6 | ph_reserve[_N] == 0   // every other household an ordered replacement
* the commands do-file, run again, gives the same selection
use "out1/rtm_sample_areas.dta", clear
keep area_id area_sel area_reserve area_pi
rename (area_sel area_reserve area_pi) (sel0 res0 pi0)
tempfile first
save "`first'"
do "out1/rtm_input_sampling_commands.do"
use "out1/rtm_sample_areas.dta", clear
merge 1:1 area_id using "`first'", assert(3) nogenerate
assert area_sel == sel0 & area_reserve == res0 & reldif(area_pi, pi0) < 1e-12

* ---------- 4. weights from the workbook equal the commands typed directly ----------
rtminput using "rtm_inputs.xlsx", weights round(1) outdir("out1")
confirm file "out1/rtm_weights_round1.dta"
confirm file "out1/rtm_weights_round1.docx"
confirm file "out1/rtm_input_weights_round1_commands.do"
use "rtm_baseline.dta", clear
merge 1:1 hhid using "rtm_round1.dta", keepusing(responded_r1) keep(master match) nogenerate
quietly replace responded_r1 = 0 if missing(responded_r1)
rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(v0)
keep if phone == 1
rtmweight nonresponse responded_r1, weight(v0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(v1)
rtmweight calibrate i.region i.urban [pw=v1] if responded_r1 == 1, generate(v2) totalsfile("out1/rtm_input_totals.dta") method(rake)
keep hhid v0 v1 v2
merge 1:1 hhid using "out1/rtm_weights_round1.dta", assert(3) nogenerate keepusing(w0 w1 w1t w2 region urban responded_r1)
assert reldif(w0, v0) < 1e-9
assert reldif(w1, v1) < 1e-9 if responded_r1 == 1
assert reldif(w1t, w1) < 1e-12 if responded_r1 == 1      // trim none: carried forward
assert reldif(w2, v2) < 1e-9 if responded_r1 == 1
* the calibrated weights add to the Totals sheet
use "out1/rtm_input_totals.dta", clear
quietly count
forvalues i = 1/`r(N)' {
    local v`i' = variable[`i']
    local l`i' = level[`i']
    local t`i' = total[`i']
}
local nt = r(N)
use "out1/rtm_weights_round1.dta", clear
forvalues i = 1/`nt' {
    quietly summarize w2 if responded_r1 == 1 & `v`i'' == `l`i''
    assert reldif(r(sum), `t`i'') < 1e-7
}

* ---------- 5. a folder of CSV files is the same input ----------
capture mkdir "rtm_inputs_csv"
foreach s in Design Strata Frame Totals Cells Prefixes Files {
    local allstr = cond(inlist("`s'", "Design", "Files"), "allstring", "")
    import excel using "rtm_inputs.xlsx", sheet("`s'") firstrow case(lower) `allstr' clear
    if "`s'" == "Files" quietly replace path = "../" + path     // paths are relative to the inputs' own folder
    export delimited using "rtm_inputs_csv/`=lower("`s'")'.csv", replace
}
rtminput using "rtm_inputs_csv", check
assert r(n_errors) == 0
confirm file "rtm_inputs_csv/checks.csv"
rtminput using "rtm_inputs_csv", sampling outdir("out_csv")
use "out_csv/rtm_sample_areas.dta", clear
keep area_id area_sel
rename area_sel sel_csv
merge 1:1 area_id using "out1/rtm_sample_areas.dta", assert(3) nogenerate keepusing(area_sel)
assert area_sel == sel_csv

* ---------- 6. the Design choices reach the commands: entropy balancing and winsorising from the workbook ----------
import excel using "rtm_inputs.xlsx", sheet("Design") firstrow case(lower) allstring clear
quietly replace value = "ebalance" if key == "nonresponse"
quietly replace value = "winsor" if key == "trim"
quietly replace value = "none" if key == "calibrate"
export excel using "rtm_inputs_eb.xlsx", sheet("Design") firstrow(variables) replace
foreach s in Strata Frame Totals Cells Prefixes Files {
    local allstr = cond("`s'" == "Files", "allstring", "")
    import excel using "rtm_inputs.xlsx", sheet("`s'") firstrow case(lower) `allstr' clear
    export excel using "rtm_inputs_eb.xlsx", sheet("`s'", replace) firstrow(variables)
}
rtminput using "rtm_inputs_eb.xlsx", weights round(1) outdir("out_eb")
use "out_eb/rtm_weights_round1.dta", clear
quietly summarize hhsize [aw=w0]
local m0 = r(mean)
quietly summarize hhsize [aw=w1] if responded_r1 == 1
assert reldif(r(mean), `m0') < 1e-6                 // balanced to the sample's weighted mean
quietly summarize w1t if responded_r1 == 1
assert r(max) < .
quietly summarize w1 if responded_r1 == 1, detail
assert w1t <= r(p98) + 1e-9 if responded_r1 == 1    // winsorised at the 98th percentile
assert reldif(w2, w1t) < 1e-12 if responded_r1 == 1  // calibrate none: carried forward
cd "`here'"

* ---------- 7. the portable filler: 00_inputs.do writes filled do-files that run and give the same weights ----------
cd "../portable_do_files"
do "00_inputs.do"
confirm file "03_sample_filled.do"
confirm file "04_weights_filled.do"
confirm file "inputs_data/rtm_input_frame.dta"
do "04_weights_filled.do"
keep hhid w2 responded_r1
rename w2 w2_do
merge 1:1 hhid using "`d'/out1/rtm_weights_round1.dta", assert(3) nogenerate keepusing(w2)
assert reldif(w2, w2_do) < 1e-9 if responded_r1 == 1
do "03_sample_filled.do"
quietly count if ph_sel == 1
assert r(N) == 600
cd "`here'"
global RTM_EXPORT "off"
di as result "test_input: the workbook checks, runs and reproduces the commands; the CSV folder and the portable filler agree"
