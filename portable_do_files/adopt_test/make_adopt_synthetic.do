*! make_adopt_synthetic.do  version 0.5.0  25oct2026
*! A second synthetic program, standing in for another task team's launching survey, used by the
*! portability test: different variable names, 3 strata, PSUs of unequal size, a wide totals
*! file, other education codes, a different response rate. No real household is represented.
*! Run from the adopt_test folder:  do make_adopt_synthetic.do
version 16
clear all
set seed 20261029

* ---- population: 3 strata (zone), 90 PSUs of unequal size ----
set obs 90
gen int ea = _n
gen byte zone = 1 + mod(_n - 1, 3)
label define zone 1 "Coast" 2 "Hills" 3 "Plains"
label values zone zone
gen int n_hh_census = round(exp(rnormal(5.0, 0.5)))        // 60 to 400 households, skewed
replace n_hh_census = 50 if n_hh_census < 50
bysort zone: egen long N_zone = total(n_hh_census)
gen int n_ea_zone = 12                                       // 12 PSUs per stratum (equal allocation)
gen double p_ea = n_ea_zone * n_hh_census / N_zone
replace p_ea = 1 if p_ea > 1
sort zone ea
by zone: gen double cum = sum(n_hh_census)
by zone: gen double interval = N_zone / n_ea_zone
by zone: gen double start = runiform() * interval if _n == 1
by zone: replace start = start[1]
by zone: gen int k_lo = ceil((cum - n_hh_census - start) / interval)
by zone: gen int k_hi = ceil((cum - start) / interval) - 1
gen byte ea_sel = (k_hi >= k_lo) & (k_hi >= 0)
keep ea zone n_hh_census N_zone n_ea_zone p_ea ea_sel
tempfile frame
save "`frame'"

* ---- baseline sample: 15 households per selected PSU ----
keep if ea_sel
expand 15
bysort ea: gen int k = _n
gen long hh_id = ea * 100 + k
gen double p_hh = 15 / n_hh_census
replace p_hh = 1 if p_hh > 1
gen double wt0 = 1 / (p_ea * p_hh)
gen byte town = (runiform() < 0.4)
gen byte schooling = 1 + floor(runiform() * 4)              // 1 none, 2 primary, 3 secondary, 4 tertiary (other codes than the template)
label define schooling 1 "None" 2 "Primary" 3 "Secondary" 4 "Tertiary"
label values schooling schooling
gen byte members = max(1, round(rnormal(5.5, 2)))
gen int age_head = max(18, min(85, round(rnormal(44, 13))))
gen byte has_mobile = (runiform() < invlogit(1.0 + 0.6 * town + 0.3 * (schooling - 2)))
gen double wealth = rnormal(0.2 * town + 0.15 * (schooling - 2), 1)
label var hh_id "Household identifier"
label var ea "Enumeration area (PSU)"
label var zone "Zone (stratum)"
label var wt0 "Baseline design weight"
label var town "Urban (1) or rural (0)"
label var schooling "Schooling of the head"
label var members "Household members"
label var age_head "Age of the head"
label var has_mobile "Household has a mobile phone"
label var wealth "Wealth index (synthetic)"
keep hh_id ea zone wt0 town schooling members age_head has_mobile wealth
order hh_id ea zone wt0
compress
save adopt_baseline.dta, replace

* ---- round 1: a different response pattern (attrition stronger among the poor and the young) ----
keep if has_mobile == 1
gen double p = invlogit(0.4 + 0.4 * town + 0.3 * wealth + 0.015 * (age_head - 44))
gen byte done_r1 = (runiform() < p)
gen byte food_short = (runiform() < invlogit(-1.2 - 0.7 * wealth)) if done_r1
drop p
label var done_r1 "Interviewed in round 1"
label var food_short "Ran short of food in the past month"
keep hh_id done_r1 food_short
compress
save adopt_round1.dta, replace

* ---- totals in the long layout the do-file reads (variable, level, total), from the frame ----
use "`frame'", clear
collapse (sum) total = n_hh_census, by(zone)
gen str32 variable = "zone"
rename zone level
tempfile tz
save "`tz'"
* town totals: an invented 40/60 split of the same households
clear
set obs 2
gen str32 variable = "town"
gen byte level = _n - 1
gen double total = .
use "`frame'", clear
quietly summarize n_hh_census
local N = r(sum)
clear
set obs 2
gen str32 variable = "town"
gen byte level = _n - 1
gen double total = cond(level == 1, round(0.4 * `N'), `N' - round(0.4 * `N'))
append using "`tz'"
order variable level total
label values level .
save adopt_totals_long.dta, replace
di as text "adopt_test data written: adopt_baseline.dta, adopt_round1.dta, adopt_totals_long.dta"

* ---- the area frame of the adopting program and a completed listing of its selected areas ----
use "`frame'", clear
rename (ea n_hh_census ea_sel p_ea) (ea_code hh_count selected prob_ea)
label var ea_code "Enumeration area code"
label var hh_count "Households in the area (census)"
label var selected "Area selected into the baseline"
label var prob_ea "First-stage probability"
keep ea_code zone hh_count selected prob_ea
save adopt_frame.dta, replace
keep if selected
set seed 20261030
gen int listed_n = round(hh_count * (0.85 + 0.3 * runiform()))
sort ea_code
drop in 3                                          // one area not returned
expand listed_n
bysort ea_code: gen int bldg = _n
gen byte hh = 1
gen byte elig = (runiform() < 0.96)
rename ea_code area
keep area bldg hh elig
label var area "Enumeration area code (listing)"
label var bldg "Building number"
label var hh "Household number in the building"
label var elig "Eligible household (1/0)"
save adopt_listing.dta, replace
di as text "adopt_test frame and listing written: adopt_frame.dta, adopt_listing.dta"
