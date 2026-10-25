*! make_rtm_synthetic.do  version 0.1  24oct2026
*! Builds the synthetic sample data shipped with rtmtools. No real respondent record is used.
*! Run from the rtmtools/data folder:  do make_rtm_synthetic.do
* The population is invented: 8 strata (4 regions x urban/rural), 400 enumeration areas (EAs),
* about 60,000 households with a few baseline characteristics. A two-stage baseline sample
* (PPS of EAs within strata, 12 households per EA) gives rtm_baseline.dta with exact design
* weights. Phone owners form the phone panel; round 1 and round 2 responses depend on the
* characteristics, so nonresponse and attrition adjustments have something to correct.

version 16
clear all
set seed 20261024
local here "`c(pwd)'"

* ---------- 1. population of EAs -------------------------------------------------------------
set obs 400
gen int ea_id = _n
gen byte region = 1 + mod(_n - 1, 4)
gen byte urban  = (_n <= 160)                     // 160 urban EAs, 240 rural
gen byte stratum = (region - 1) * 2 + urban + 1   // 1..8
label define region 1 "North" 2 "South" 3 "East" 4 "West"
label define urban 0 "Rural" 1 "Urban"
label values region region
label values urban urban
gen int ea_size_census = round(rnormal(cond(urban, 180, 130), 40))
replace ea_size_census = 60 if ea_size_census < 60
gen byte network = (runiform() < cond(urban, 0.99, 0.90))   // mobile network present
label var ea_id "Enumeration area"
label var region "Region"
label var urban "Urban or rural"
label var stratum "Stratum (region x urban)"
label var ea_size_census "Households in the EA (census count)"
label var network "Mobile network coverage in the EA (1 = yes)"
save rtm_frame.dta, replace

* ---------- 2. population of households ------------------------------------------------------
expand ea_size_census
bysort ea_id: gen int hh_in_ea = _n
gen long hhid_pop = ea_id * 1000 + hh_in_ea
gen byte hhsize = max(1, round(rnormal(cond(urban, 4.2, 5.4), 1.8)))
gen byte head_female = (runiform() < 0.22)
gen byte head_age = max(18, min(90, round(rnormal(46, 14))))
gen byte educ = cond(runiform() < cond(urban, 0.45, 0.22), 3, cond(runiform() < 0.5, 2, 1))
label define educ 1 "Primary or less" 2 "Secondary" 3 "Post-secondary"
label values educ educ
gen float assets = rnormal(0.3 * urban + 0.2 * (educ - 2), 1)
gen byte phone = (runiform() < invlogit(1.2 + 0.9 * urban + 0.5 * (educ - 2) + 0.4 * assets - 1.5 * (network == 0)))
gen byte agegrp = cond(head_age < 35, 1, cond(head_age < 55, 2, 3))
label define agegrp 1 "Under 35" 2 "35 to 54" 3 "55 and over"
label values agegrp agegrp
* outcome of interest: skipped a meal in the past 30 days (prevalence depends on assets)
gen byte skipmeal_pop = (runiform() < invlogit(-1.6 - 0.8 * assets - 0.3 * urban))
label var hhsize "Household size"
label var head_female "Head is a woman"
label var head_age "Age of the head"
label var educ "Education of the head"
label var assets "Asset index (standardized, synthetic)"
label var phone "Household has a mobile phone"
label var agegrp "Age group of the head"
compress
save rtm_population.dta, replace

* ---------- 3. population totals for calibration ---------------------------------------------
preserve
collapse (count) N_hh = hhid_pop, by(region urban head_female agegrp)
label var N_hh "Households in the population (synthetic census)"
save rtm_totals_cells.dta, replace
restore
preserve
collapse (count) N_hh = hhid_pop, by(region)
save rtm_totals_region.dta, replace
restore

* ---------- 4. baseline sample: PPS of 100 EAs within strata, 12 households per EA -----------
* Allocation: proportional to households in the stratum; EAs drawn by systematic PPS
* (cumulative size, random start) so that selection probabilities are exact.
use rtm_frame.dta, clear
bysort stratum: egen long N_str = total(ea_size_census)
egen long N_tot = total(ea_size_census)
gen int n_ea_str = round(100 * N_str / N_tot)
* fix rounding so the EAs add to 100
preserve
collapse (first) n_ea_str, by(stratum)
egen tot = total(n_ea_str)
local tot = tot[1]
restore
if `tot' != 100 {
    bysort stratum (ea_id): replace n_ea_str = n_ea_str + (100 - `tot') if stratum == 1
}
gen double pi_ea = n_ea_str * ea_size_census / N_str          // PPS inclusion probability
replace pi_ea = 1 if pi_ea > 1
sort stratum ea_id
by stratum: gen double cum = sum(ea_size_census)
by stratum: gen double interval = N_str / n_ea_str
by stratum: gen double start = runiform() * interval if _n == 1
by stratum: replace start = start[1]
by stratum: gen int k_lo = ceil((cum[_n] - ea_size_census - start) / interval)
by stratum: gen int k_hi = ceil((cum - start) / interval) - 1
gen byte ea_selected = (k_hi >= k_lo) & (k_hi >= 0)
label var pi_ea "First-stage inclusion probability of the EA"
label var ea_selected "EA selected into the baseline sample"
label var n_ea_str "EAs selected in the stratum"
label var N_str "Households in the stratum (census)"
keep ea_id stratum region urban ea_size_census network N_str n_ea_str pi_ea ea_selected
save rtm_frame.dta, replace

use rtm_population.dta, clear
merge m:1 ea_id using rtm_frame.dta, keepusing(pi_ea ea_selected N_str n_ea_str) nogenerate
keep if ea_selected
set seed 20261025
bysort ea_id (hhid_pop): gen double u = runiform()
bysort ea_id (u): gen byte hh_selected = (_n <= 12)
keep if hh_selected
bysort ea_id: gen int m_ea = _N
gen double pi_hh = 12 / ea_size_census                          // second stage: 12 of the listed households
replace pi_hh = 1 if pi_hh > 1
gen double w_base = 1 / (pi_ea * pi_hh)
gen long hhid = ea_id * 100 + _n
bysort ea_id (u): replace hhid = ea_id * 100 + _n
label var hhid "Household ID (baseline sample)"
label var pi_hh "Second-stage inclusion probability of the household"
label var w_base "Baseline design weight (1 / (pi_ea x pi_hh))"
label var m_ea "Households sampled in the EA"
gen int psu = ea_id
label var psu "Primary sampling unit (EA)"
drop u hh_selected hhid_pop hh_in_ea skipmeal_pop
order hhid psu stratum region urban ea_size_census pi_ea pi_hh w_base
compress
save rtm_baseline.dta, replace

* ---------- 5. phone panel, round 1 and round 2 ----------------------------------------------
* Phone owners are the panel. Response in round 1 depends on urban, education and age;
* attrition in round 2 on the same plus household size. Outcomes come from the population model.
use rtm_baseline.dta, clear
keep if phone == 1
set seed 20261026
gen double p_resp1 = invlogit(0.9 + 0.5 * urban + 0.4 * (educ - 2) - 0.015 * (head_age - 46) + 0.1 * assets)
gen byte responded_r1 = (runiform() < p_resp1)
gen byte skipmeal_r1 = (runiform() < invlogit(-1.6 - 0.8 * assets - 0.3 * urban)) if responded_r1
gen byte worked_r1 = (runiform() < invlogit(0.4 + 0.3 * urban + 0.2 * (educ - 2) - 0.02 * (head_age - 46))) if responded_r1
gen byte nphones = 1 + (runiform() < 0.25) + (runiform() < 0.08)
label var nphones "Phone numbers on file for the household"
label var responded_r1 "Interviewed in round 1 (1 = yes)"
label var skipmeal_r1 "Skipped a meal in the past 30 days (round 1)"
label var worked_r1 "Any member worked in the past 7 days (round 1)"
gen double p_resp2 = invlogit(1.4 + 0.3 * urban + 0.3 * (educ - 2) - 0.01 * (head_age - 46) - 0.05 * (hhsize - 5)) if responded_r1
gen byte responded_r2 = (runiform() < p_resp2) if responded_r1 == 1
replace responded_r2 = 0 if responded_r1 == 0
gen byte skipmeal_r2 = (runiform() < invlogit(-1.7 - 0.8 * assets - 0.3 * urban + 0.9 * skipmeal_r1)) if responded_r2
label var responded_r2 "Interviewed in round 2 (1 = yes)"
label var skipmeal_r2 "Skipped a meal in the past 30 days (round 2)"
drop p_resp1 p_resp2
note: Synthetic data made by make_rtm_synthetic.do (rtmtools). No real household is represented.
compress
save rtm_round1.dta, replace

* ---------- 5b. population totals in the long format that rtmweight calibrate, totalsfile() reads ----------
* one row per category: variable (name), level (category code), total (households)
use rtm_totals_cells.dta, clear
collapse (sum) total = N_hh, by(urban)
gen str32 variable = "urban"
rename urban level
tempfile tot_urban
save "`tot_urban'"
use rtm_totals_cells.dta, clear
collapse (sum) total = N_hh, by(region)
gen str32 variable = "region"
rename region level
append using "`tot_urban'"
label values level .
label variable variable "Calibration variable"
label variable level "Category code of the variable"
label variable total "Households in the population (synthetic census)"
order variable level total
note: Synthetic data made by make_rtm_synthetic.do (rtmtools). No real household is represented.
save rtm_totals_long.dta, replace

* ---------- 6. summary for the log --------------------------------------------------------------
use rtm_population.dta, clear
quietly count
di as text "population households: " as result r(N)
use rtm_baseline.dta, clear
quietly count
di as text "baseline sample: " as result r(N) as text " households in "
quietly tab psu
di as result r(r) as text " EAs; sum of weights = " as result %12.1f
quietly summarize w_base
di as result %12.1f r(sum)
use rtm_round1.dta, clear
quietly summarize responded_r1
di as text "phone panel: " as result r(N) as text " households; round-1 response rate " as result %5.3f r(mean)
quietly summarize responded_r2 if responded_r1
di as text "round-2 retention among round-1 respondents " as result %5.3f r(mean)

* ---------- 7. person-level file of the phone panel (for rtmweight household and the cell methods) ----------
* one row per household member of the round-1 respondents; sex and age invented, consistent with the head
use rtm_round1.dta, clear
keep if responded_r1 == 1
keep hhid psu stratum region urban hhsize head_female head_age w_base
set seed 20261027
expand hhsize
bysort hhid: gen int fmid = _n
gen byte female = cond(fmid == 1, head_female, runiform() < 0.5)
gen int age = cond(fmid == 1, head_age, max(0, min(90, round(rnormal(head_age - 20, 15)))))
replace age = max(0, age)
gen byte age_grp = cond(age <= 17, 1, cond(age <= 45, 2, 3))
label define age_grp 1 "0-17" 2 "18-45" 3 "46+"
label values age_grp age_grp
label var fmid "Member number"
label var female "Member is female"
label var age "Age of the member"
label var age_grp "Age group of the member"
label var hhsize "Household size"
gen double indw = w_base
label var indw "Person weight (baseline design weight carried to the member)"
drop head_female head_age
note: Synthetic data made by make_rtm_synthetic.do (rtmtools). No real person is represented.
compress
save rtm_persons.dta, replace
* census cell totals of persons by region x urban x sex x age group (synthetic: scaled from the population)
use rtm_population.dta, clear
expand hhsize
bysort hhid_pop: gen int fmid = _n
set seed 20261028
gen byte female = cond(fmid == 1, head_female, runiform() < 0.5)
gen int age = cond(fmid == 1, head_age, max(0, min(90, round(rnormal(head_age - 20, 15)))))
gen byte age_grp = cond(age <= 17, 1, cond(age <= 45, 2, 3))
collapse (count) N_persons = fmid, by(region urban female age_grp)
label var N_persons "Persons in the population (synthetic census)"
save rtm_totals_persons.dta, replace
