********************************************************************************************
* 03_sample.do  --  sample size, allocation and the draw of a two-stage sample from a list frame,
* and the phone subsample of a baseline, in plain Stata (no rtmtools command is called)
* rtmtools portable do-files, version 0.5.0 (25 October 2026)
*
* Steps (each explained above its code and cited):
*   1. sample size per domain (UN 2008 formula 3.7; HFPS Vol. 2 section 2.1; MPPS 2016 attrition reserve)
*   2. allocation of the areas across strata (proportional, equal, Neyman or power; bounds; rounding)
*   3. first stage: systematic PPS draw of areas within strata, frame sorted geographically
*      (UN 2008 paras 77-79 and 118-119: cumulative sizes, interval, random start), with reserves
*   4. second stage: a fixed number of households per selected area, SRS (gsample) or systematic
*   5. the phone subsample of a baseline: n per PSU, every other baseline household an ordered
*      replacement (the L2 practice), and the design weight 1 / (p1 x p2 x p3)
* Every step is exported (schema rtm-export-1.0) like the rtmsample commands.
* To adopt it: change only the PARAMETERS block, following ADAPTATION.md.
********************************************************************************************
version 16
clear all
set more off

* ======================= PARAMETERS: change these lines only ===============================
local data_frame     "template/rtm_frame.dta"       // area frame: one row per area with id, strata, measure of size
local data_hh        "template/rtm_population.dta"  // household list of the areas (one row per household) for step 4; "" to skip
local data_baseline  "template/rtm_baseline.dta"    // a baseline sample for the phone subsample of step 5; "" to skip
local export_dir     "rtm_exports"
local helpers        "_export_helpers.do"
local template_xlsx  "rtm_display.xlsx"
* --- step 1: size ---
local p              0.2       // expected proportion of the key indicator
local relmargin      0.10      // relative margin of error at 95% (UN 2008 para 59: 10%)
local deff           2.0       // design effect (UN 2008 para 60: 2.0 for clustered samples; about 1 for a list sample)
local nonresponse    1.1       // nonresponse multiplier (UN 2008 para 60)
local attrition      0.015     // attrition per round (0 = none); MPPS 2016 p. 45
local rounds         24        // rounds of the panel
local firstloss      0.25      // loss between baseline and the first phone round (0 = none)
local domains        4         // domains needing equal reliability
* --- step 2: allocation ---
local area_id        ea_id
local strata         "region urban"
local size           ea_size_census  // measure of size of the areas (households)
local n_areas        100        // areas to select in total
local alloc          proportional   // proportional | equal | power
local power_q        0.5        // exponent of power allocation (Bankier 1988), used when alloc is power
local min_areas      10         // minimum areas per stratum (GM 1996 pp. 78-79: small domains boosted); 0 = none
local max_areas      16         // maximum per stratum; 0 = none
* --- step 3: first-stage draw ---
local sort_vars      "region urban ea_id"   // geographic order for the implicit stratification
local reserve_areas  2          // reserve areas per stratum (0 = none)
local seed1          20261024
* --- step 4: second stage ---
local hh_area_id     ea_id      // area identifier in the household list
local hh_id          hhid_pop   // household identifier in the household list
local m_hh           12         // households per selected area
local seed2          20261025
* --- step 5: phone subsample of the baseline (the L2 practice) ---
local bl_id          hhid
local bl_psu         psu
local n_phone        6          // households per PSU in the phone sample ("all" to call every one)
local seed3          20251027
* ===========================================================================================

capture confirm file "`helpers'"
if _rc {
    di as err "the export helpers `helpers' were not found; run this do-file from the portable_do_files folder"
    exit 601
}
run "`helpers'"
global RTM_EXPORT ""
global RTM_EXPORT_DIR "`export_dir'"
global RTM_EXPORT_TEMPLATE "`template_xlsx'"
global RTM_EXPORT_SOURCE "dofile"
capture which gsample
if _rc {
    di as err "step 4 needs gsample (SSC): do 00_setup.do"
    exit 199
}

* ---- 1. Sample size per domain ---------------------------------------------------------------
* n = z^2 p(1-p) / e^2 for a simple random sample with e = relmargin x p (UN 2008 formula 3.7,
* paras 59-60), times the design effect, times the nonresponse multiplier, times the attrition
* reserve 1 / ((1 - firstloss)(1 - attrition)^(rounds - 1)) (MPPS 2016 p. 45), rounded up, per domain.
rtmx_start, workflow(sampling) step(size) cmd("03_sample.do step 1: sample size")
local z = invnormal(0.975)
local e = `relmargin' * `p'
local n_srs = `z'^2 * `p' * (1 - `p') / `e'^2
local n_deff = `n_srs' * `deff'
local n_sel = `n_deff' * `nonresponse'
local expo = cond(`firstloss' > 0, `rounds' - 1, `rounds')
local fatt = 1 / ((1 - `firstloss') * (1 - `attrition')^`expo')
local n_dom = ceil(`n_sel' * `fatt' - 1e-9)
local n_total = `n_dom' * `domains'
di as text _n "Sample size: SRS " %9.1f `n_srs' " x deff `deff' = " %9.1f `n_deff' " x nonresponse `nonresponse' = " %9.1f `n_sel' " x attrition reserve " %6.3f `fatt' " -> " `n_dom' " per domain, " `n_total' " in all"
capture frame drop _rtmx_sz
frame create _rtmx_sz str32 domain double(p margin deff nonresponse attrition rounds n_effective n_final)
frame post _rtmx_sz ("each domain") (`p') (`e') (`deff') (`nonresponse') (`attrition') (`rounds') (`n_srs') (`n_dom')
frame post _rtmx_sz ("all `domains' domains") (`p') (`e') (`deff') (`nonresponse') (`attrition') (`rounds') (`n_srs' * `domains') (`n_total')
rtmx_table, name(size) frame(_rtmx_sz)
rtmx_setting, key(case) value("level") source("UN 2008 section 3.3 formula 3.7; HFPS Vol. 2 section 2.1")
rtmx_setting, key(deff) value("`deff'") source("UN 2008 para 60")
rtmx_setting, key(attrition) value("`attrition' per round, `rounds' rounds, first loss `firstloss'") source("MPPS 2016 p. 45")
quietly count
rtmx_done

* ---- 2. Allocation of the areas across strata ------------------------------------------------
* n_h = n N_h / N (proportional), n / H (equal) or n N_h^q / sum N_k^q (power, Bankier 1988),
* with a minimum and a maximum per stratum: strata held at a bound take it and the rest is
* re-allocated; largest-remainder rounding keeps the total (UN 2008 paras 68-70; GM 1996 pp. 78-79).
use "`data_frame'", clear
isid `area_id'
rtmx_start, workflow(sampling) step(allocate) cmd("03_sample.do step 2: allocation, `alloc'")
tempvar grp
egen long `grp' = group(`strata')
preserve
collapse (sum) Nh = `size' (count) Uh = `size', by(`grp' `strata')
quietly count
local H = r(N)
quietly summarize Nh
local Ntot = r(sum)
gen double share = Nh / `Ntot'
if "`alloc'" == "proportional" gen double a0 = `n_areas' * share
else if "`alloc'" == "equal" gen double a0 = `n_areas' / `H'
else {
    gen double Np = Nh^`power_q'
    quietly summarize Np
    gen double a0 = `n_areas' * Np / r(sum)
}
gen double a = a0
gen byte fixed = 0
local changed 1
local iter 0
while `changed' & `iter' < 100 {
    local ++iter
    local changed 0
    gen byte newfix = 0
    replace newfix = 1 if !fixed & a > Uh + 1e-9
    gen double bound = Uh if newfix == 1
    if `max_areas' > 0 {
        replace newfix = 2 if !fixed & newfix == 0 & a > `max_areas' + 1e-9
        replace bound = min(`max_areas', Uh) if newfix == 2
    }
    if `min_areas' > 0 {
        replace newfix = 3 if !fixed & newfix == 0 & a < `min_areas' - 1e-9
        replace bound = min(`min_areas', Uh) if newfix == 3
    }
    quietly count if newfix > 0
    if r(N) > 0 {
        local changed 1
        replace a = bound if newfix > 0
        replace fixed = 1 if newfix > 0
        quietly summarize a if fixed
        local nrem = `n_areas' - r(sum)
        quietly summarize a0 if !fixed
        if r(N) > 0 replace a = `nrem' * a0 / r(sum) if !fixed
        else assert abs(`nrem') < 1e-6    // every stratum at a bound: the bounds must add to n
    }
    drop newfix bound
}
gen double afl = floor(a + 1e-9)
gen double frac = a - afl
quietly summarize afl
local left = round(`n_areas' - r(sum))
gen double nh = afl
if `left' > 0 {
    gsort -frac `grp'
    replace nh = afl + 1 in 1/`left'
}
sort `grp'
gen double fh = nh / Nh
capture frame drop _rtmx_al
frame create _rtmx_al str80 stratum double(n_units size_sum share n_planned n_min n_max n_final sampling_fraction)
forvalues i = 1/`H' {
    local lab ""
    foreach v of local strata {
        local vl : value label `v'
        if "`vl'" != "" local lt : label `vl' `=`v'[`i']'
        else local lt = string(`v'[`i'])
        local lab "`lab'`=cond("`lab'" == "", "", " ")'`lt'"
    }
    frame post _rtmx_al ("`lab'") (Uh[`i']) (Nh[`i']) (share[`i']) (a0[`i']) (cond(`min_areas' > 0, `min_areas', .)) (cond(`max_areas' > 0, `max_areas', .)) (nh[`i']) (fh[`i'])
}
list `strata' Nh share a0 nh fh, noobs clean
quietly summarize nh
assert r(sum) == `n_areas'
keep `grp' nh
tempfile alloc
save "`alloc'"
restore
merge m:1 `grp' using "`alloc'", nogenerate
rename nh n_ea
label variable n_ea "Areas allocated to the stratum"
rtmx_table, name(allocation) frame(_rtmx_al)
rtmx_setting, key(method) value("`alloc'") source("UN 2008 paras 68-70; GM 1996 pp. 78-79; Bankier 1988")
rtmx_setting, key(n) value("`n_areas'")
rtmx_setting, key(bounds) value("min `min_areas' max `max_areas'")
quietly count
rtmx_done

* ---- 3. First stage: systematic PPS draw of areas within strata ------------------------------
* Frame sorted geographically within strata (implicit stratification, UN 2008 paras 77-79);
* cumulative measure of size, interval = total size / n_h, random start in [0, interval);
* a unit is selected when a selection number falls in its cumulative range (UN 2008 paras 118-119,
* Figure 3.2). Inclusion probability n_h x size / total size. A unit whose size reaches the
* interval (probability above 1) is taken with certainty (pi = 1) and removed from the cumulation,
* and the interval is recomputed for the remaining units and allocation; this is repeated until no
* unit exceeds the interval (UN 2008 para 101, p. 65). Reserve areas: the same procedure among the
* unselected units.
rtmx_start, workflow(sampling) step(draw) cmd("03_sample.do step 3: systematic PPS draw of areas")
set seed `seed1'
sort `grp' `sort_vars'
gen byte ea_cert = 0
gen double n_rem = .
local changed 1
local iter 0
while `changed' & `iter' < 100 {
    local ++iter
    local changed 0
    capture drop n_cert
    by `grp': egen double n_cert = total(ea_cert)
    quietly replace n_rem = n_ea - n_cert
    capture drop S
    by `grp': egen double S = total(cond(!ea_cert, `size', 0))
    quietly count if !ea_cert & n_rem > 0 & `size' * n_rem / S > 1 + 1e-12
    if r(N) > 0 {
        local changed 1
        quietly replace ea_cert = 1 if !ea_cert & n_rem > 0 & `size' * n_rem / S > 1 + 1e-12
    }
}
quietly count if ea_cert
if r(N) > 0 di as text r(N) " areas taken with certainty (size at or above the interval)"
by `grp': gen double cum = sum(cond(!ea_cert, `size', 0))
by `grp': gen double I = S / n_rem if n_rem > 0
by `grp': gen double RS = I * runiform() if _n == 1
by `grp': replace RS = RS[1]
gen double k_hi = floor((cum - RS) / I) if !ea_cert
gen double k_lo = floor((cum - `size' - RS) / I) if !ea_cert
gen byte ea_sel = ea_cert | (k_hi > k_lo & !missing(k_hi, k_lo))
gen double pi1 = cond(ea_cert, 1, n_rem * `size' / S)
gen double ea_pi = pi1
gen double ea_w = 1 / ea_pi if ea_sel
* reserves among the unselected units, in the same order
gen byte ea_reserve = 0
if `reserve_areas' > 0 {
    by `grp': egen double S2 = total(cond(!ea_sel, `size', 0))
    by `grp': gen double cum2 = sum(cond(!ea_sel, `size', 0))
    by `grp': gen double I2 = S2 / `reserve_areas'
    by `grp': gen double RS2 = I2 * runiform() if _n == 1
    by `grp': replace RS2 = RS2[1]
    gen double k2_hi = floor((cum2 - RS2) / I2) if !ea_sel
    gen double k2_lo = floor((cum2 - cond(!ea_sel, `size', 0) - RS2) / I2) if !ea_sel
    replace ea_reserve = k2_hi + 1 if !ea_sel & k2_hi > k2_lo
    drop S2 cum2 I2 RS2 k2_hi k2_lo
}
drop k_hi k_lo pi1 n_cert n_rem
label variable ea_sel "Area selected (systematic PPS, seed `seed1')"
label variable ea_cert "Selected with certainty (size at or above the interval)"
label variable ea_pi "First-stage inclusion probability"
label variable ea_w "First-stage design weight"
label variable ea_reserve "Reserve rank (0 = not a reserve)"
quietly count if ea_sel
di as text "Areas selected: " r(N) " (planned `n_areas'); reserves: " _c
quietly count if ea_reserve > 0
di as result r(N)
* exports: the selection and the summary by stratum
capture frame drop _rtmx_ds
frame create _rtmx_ds str80 stratum double(n_units n_selected n_reserve prob_min prob_max interval random_start)
quietly levelsof `grp', local(glev)
foreach g of local glev {
    quietly count if `grp' == `g'
    local U = r(N)
    quietly count if `grp' == `g' & ea_sel
    local ns = r(N)
    quietly count if `grp' == `g' & ea_reserve > 0
    local nr = r(N)
    quietly summarize ea_pi if `grp' == `g' & ea_sel
    quietly summarize I if `grp' == `g', meanonly
    local Ig = r(mean)
    quietly summarize RS if `grp' == `g', meanonly
    quietly summarize ea_pi if `grp' == `g' & ea_sel
    frame post _rtmx_ds ("`g'") (`U') (`ns') (`nr') (r(min)) (r(max)) (`Ig') (.)
}
rtmx_table, name(draw_summary) frame(_rtmx_ds)
capture frame drop _rtmx_sl
frame put `area_id' `grp' `size' cum ea_sel ea_reserve ea_pi ea_w, into(_rtmx_sl)
frame _rtmx_sl {
    gen str32 unit_id = string(`area_id')
    gen str32 stratum = string(`grp')
    rename (`size' cum ea_sel ea_reserve ea_pi ea_w) (size cum_size selected reserve prob weight)
    gen double order = _n
    gen double key = .
    gen double selection_number = .
    gen double rank = .
    gen double x = .
    gen double y = .
    drop `area_id' `grp'
    order unit_id stratum size order key cum_size selected reserve rank prob weight x y
}
rtmx_table, name(selection) frame(_rtmx_sl)
rtmx_setting, key(method) value("systematic PPS on `size', sorted by `sort_vars'") source("UN 2008 paras 77-79, 118-119")
rtmx_setting, key(reserve) value("`reserve_areas'") source("UN 2008 paras 172, 178-179")
rtmx_setting, key(seed) value("`seed1'")
drop S cum I RS
quietly count
rtmx_done
tempfile areas
save "`areas'"

* ---- 4. Second stage: a fixed number of households per selected area --------------------------
* Simple random sampling without replacement of m households in each selected area (gsample,
* Jann 2006), probability m / households in the area (UN 2008 para 108); design weight of the
* household = 1 / (ea_pi x hh_pi) (UN 2008 section 6.3).
if "`data_hh'" != "" {
    rtmx_start, workflow(sampling) step(draw) cmd("03_sample.do step 4: `m_hh' households per selected area")
    use "`data_hh'", clear
    rename `hh_area_id' `area_id'
    merge m:1 `area_id' using "`areas'", keepusing(ea_sel ea_pi) keep(match) nogenerate
    keep if ea_sel == 1
    set seed `seed2'
    bysort `area_id': gen long M = _N
    quietly count if M < `m_hh'
    if r(N) > 0 di as txt "note: some areas have fewer than `m_hh' households; every household is taken there"
    gen double mm = min(`m_hh', M)
    gsample mm, wor strata(`area_id') generate(hh_sel)
    gen double hh_pi = mm / M
    gen double w_base = 1 / (ea_pi * hh_pi) if hh_sel == 1
    label variable hh_pi "Second-stage inclusion probability"
    label variable w_base "Design weight = 1 / (ea_pi x hh_pi)"
    quietly count if hh_sel
    di as text "Households selected: " r(N)
    capture frame drop _rtmx_ds
    frame create _rtmx_ds str80 stratum double(n_units n_selected n_reserve prob_min prob_max interval random_start)
    quietly levelsof `area_id', local(alev)
    foreach a of local alev {
        quietly count if `area_id' == `a'
        local U = r(N)
        quietly count if `area_id' == `a' & hh_sel
        frame post _rtmx_ds ("area `a'") (`U') (r(N)) (0) (`=min(`m_hh', `U') / `U'') (`=min(`m_hh', `U') / `U'') (.) (.)
    }
    rtmx_table, name(draw_summary) frame(_rtmx_ds)
    rtmx_setting, key(method) value("SRS of `m_hh' households per area (gsample)") source("UN 2008 para 108; Jann 2006")
    rtmx_setting, key(seed) value("`seed2'")
    quietly count
    rtmx_done
    keep if hh_sel == 1
    tempfile hhsample
    save "`hhsample'"
}

* ---- 5. The phone subsample of a baseline (the L2 practice) ----------------------------------
* n households per PSU drawn with equal probability from the baseline (a seeded random key, the n
* smallest keys selected), every other baseline household of the PSU kept as an ordered
* replacement; the phone household's probability multiplies the baseline's (UN 2008 section 6.3).
if "`data_baseline'" != "" {
    rtmx_start, workflow(sampling) step(draw) cmd("03_sample.do step 5: phone subsample, `n_phone' per PSU, every other household a replacement")
    use "`data_baseline'", clear
    isid `bl_id'
    set seed `seed3'
    gen double key = runiform()
    bysort `bl_psu' (key): gen long rank = _n
    bysort `bl_psu': gen long M = _N
    if "`n_phone'" == "all" gen double np = M
    else gen double np = min(`n_phone', M)
    gen byte ph_sel = (rank <= np)
    gen double ph_reserve = cond(ph_sel, 0, rank - np)
    gen double ph_pi = np / M
    label variable ph_sel "In the phone sample (seed `seed3')"
    label variable ph_reserve "Replacement rank within the PSU (0 = in the sample)"
    label variable ph_pi "Phone-subsample probability (n / baseline households in the PSU)"
    quietly count if ph_sel
    di as text "Phone sample: " r(N) " households; the others are ordered replacements in their PSU"
    capture frame drop _rtmx_sl
    frame put `bl_id' `bl_psu' key rank ph_sel ph_reserve ph_pi, into(_rtmx_sl)
    frame _rtmx_sl {
        gen str32 unit_id = string(`bl_id')
        gen str32 stratum = string(`bl_psu')
        rename (rank ph_sel ph_reserve ph_pi) (order selected reserve prob)
        gen double size = 1
        gen double cum_size = .
        gen double selection_number = .
        gen double weight = 1 / prob if selected
        gen double x = .
        gen double y = .
        rename order rank
        gen double order = rank
        drop `bl_id' `bl_psu'
        order unit_id stratum size order key cum_size selection_number selected reserve rank prob weight x y
    }
    rtmx_table, name(selection) frame(_rtmx_sl)
    rtmx_setting, key(method) value("SRS of `n_phone' per PSU with every other household as an ordered replacement") source("L2 program practice; UN 2008 paras 172, 178-179 on substitution")
    rtmx_setting, key(seed) value("`seed3'")
    quietly count
    rtmx_done
}
di as text _n "Done. Steps 3 to 5 left their frames in memory and in the export folder `export_dir'."
