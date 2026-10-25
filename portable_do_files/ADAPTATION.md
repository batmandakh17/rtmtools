# Adapting the portable do-files to your program

The do-files in this folder compute the weights of a phone-panel round (and, in later versions, build frames, support listing and draw samples) with official Stata commands and a few community commands. They were written to be copied by another task team: every setting sits in one block at the top of the do-file, every step is explained above its code, and nothing below the block names a file or a variable of the program they came from.

This guide walks through `04_weights.do`. Nothing in it is a survey-design recommendation: the do-file carries out the design and the method you choose, and the sources of the defaults are cited in the file.

## 1. What you need

| You need | Why | Parameter |
|---|---|---|
| A baseline household file, one row per household, with a unique household id | the start of every weight | `data_baseline`, `id` |
| In it: a baseline weight (or the stage inclusion probabilities), the stratum, the PSU | base weights, by-groups of the report | `w_base` (or `prob_vars`), `strata`, `psu` |
| In it: a 0/1 variable marking the phone sample (the households called), if the phone sample is a subsample of the baseline | the subsampling factor | `phone` (leave `""` when the whole baseline is called) |
| A round file, one row per sampled household, with a 0/1 response indicator | the nonresponse adjustment | `data_round`, `responded`, `round_vars` |
| Baseline covariates of the response (for the propensity and balancing methods) or class or cell variables | the adjustment method | `covariates`, `classes`, `cells` |
| Population totals, one row per category (`variable`, `level`, `total`), only if you calibrate | calibration | `totals_file` |
| Cell totals (the cell variables plus a total), only for `method post` | cell post-stratification | `cell_file`, `cell_total` |

Stata 16 or later; `svycal` (Stata 18) for the `ebalance` method and for calibration. Run `00_setup.do` once: it installs `survwgt`, `ebalance`, `ipfraking`, `gsample`, `moremata` and `geoinpoly` from SSC when they are missing (the only step that uses the internet).

## 2. The parameter block, line by line

Open `04_weights.do`. Everything you change is between the lines `PARAMETERS: change these lines only` and the row of `=` signs.

**Files.** Paths are relative to the folder you run the do-file from (`cd` there first) or absolute. `export_dir` is where every run is written; the dashboard and the Excel workbook read it. Leave `helpers` and `template_xlsx` as they are: they name the two files shipped next to the do-file.

**Variables.**
- `id`: must be unique in both files (`isid` checks it).
- `strata`, `psu`: your stratum and cluster variables, whatever their names.
- `w_base`: the baseline weight. If your baseline has none, set `w_base ""` and give the inclusion probabilities in `prob_vars` (for example `"p_ea p_hh"`); the base weight is then their inverse product (UN 2008, section 6.3).
- `phone`: the 0/1 variable marking the households in the phone sample. The weights of the phone households are rescaled within each stratum to the baseline's weight total (HFPS Vol. 2, pp. 10–11 and 21). Set it to `""` if every baseline household is in the phone sample.
- `responded`: 0/1, interviewed this round or not. Everyone in the round file is "eligible"; households you do not consider eligible (dead, moved abroad) should not be in the file.
- `round_vars`: the variables to take from the round file (at least `responded`).

**Step 2, the adjustment method (`method`).** Choose one; the help of the Stata command `rtmweight` and the sources below describe each.

| `method` | What it does | Needs | Source |
|---|---|---|---|
| `logit` (default), `probit` | response-propensity model on `covariates`, propensities cut into `ngroups` groups, factor = 1 / mean propensity of the group | `covariates` | HFPS Vol. 2 p. 10 and Annex A2.3.1; L2T 2017 pp. 7–11; MPPS 2016 Box 2.2 |
| `classes` | weighting classes: factor = sum of base weights in the class / sum over its respondents | `classes`; `survwgt` | UN 2008 section 6.5 |
| `ebalance` | entropy balancing with the base weights kept: the respondents' weighted moments of `covariates` match the sample's (raking by `svycal`) | `covariates`, `moments`; `svycal` | Hainmueller 2012; L2 program practice (L2T 2023–, L2KGZ, L2Arm, L2Geo) |
| `ebalance_nobase` | the L2PHL January 2026 form: `ebalance` without base weights against unweighted sample means, factor multiplied into the base weight | `covariates`; `ebalance` | program practice |
| `post` | cell post-stratification to population totals of `cells` from `cell_file` | `cells`, `cell_file`, `cell_total` | UN 2008 section 6.6; L2PHL since March 2026 |

`covariates` takes Stata's factor-variable notation (`i.educ` for a categorical variable). For `ebalance`, `moments 2` adds the variances and `3` the skewness of the continuous covariates to the constraints; more constraints can fail to converge (the do-file stops with a message: drop a covariate or go back to `moments 1`).

**Step 3, trimming (`trim`).** `none` (default), `winsor` (weights above the `trim_pct` percentile set to it; HFPS Vol. 2 p. 11 uses 98), or `cap` (an absolute bound `trim_cap`, or `trim_capmult` times the median; UN 2008 section 6.8). The trimmed weights are rescaled to the original total. The guidelines trim before calibrating, which is the order of the do-file.

**Step 4, calibration (`calibrate`).** `none` (default), `rake` (multiplicative distance), `regress` (linear, with optional bounds `cal_ll`, `cal_ul` on the weight ratio), or `post` (one variable). `cal_vars` are categorical variables; `totals_file` must have a total for every category that occurs among the respondents, and the totals of every variable must add to the same population (checked). Bounds have no cited default; leave them at `.` unless you have a reason.

**Names of the new variables.** `w0` (base weight of the phone sample), `w1` (after the adjustment), `w1t` (after trimming), `w2` (after calibration). When a step is off, the next variable is a copy of the previous one, so `w2` is always the final weight.

## 3. A worked adaptation

The folder `adopt_test/` holds a second synthetic program: `adopt_baseline.dta` (household id `hh_id`, stratum `zone` with three values, PSU `ea`, baseline weight `wt0`, phone variable `has_mobile`, covariates `town`, `schooling` with four codes, `members`, `age_head`, `wealth`), `adopt_round1.dta` (response `done_r1`) and `adopt_totals_long.dta` (totals for `zone` and `town`). To run the weights of that program, the parameter block becomes:

```stata
local data_baseline  "adopt_test/adopt_baseline.dta"
local data_round     "adopt_test/adopt_round1.dta"
local totals_file    "adopt_test/adopt_totals_long.dta"
local cell_file      ""
local export_dir     "rtm_exports_adopt"
local id             hh_id
local strata         zone
local psu            ea
local w_base         wt0
local prob_vars      ""
local phone          has_mobile
local responded      done_r1
local round_vars     "done_r1"
local method         ebalance
local covariates     "town i.schooling members age_head wealth"
local classes        "zone town"
local cells          ""
local trim           winsor
local trim_pct       98
local calibrate      rake
local cal_vars       "zone town"
```

Everything else stays. The run then writes the same export as before (manifest, `weight_stages.csv`, `response_classes.csv`, `calibration_fit.csv`, `weight_groups.csv`, the Excel workbook), which the dashboard and the workbook display without knowing which program produced it. This is exactly the portability test in `tests/test_portable.do`.

## 4. Running it and reading the results

```stata
cd "the portable_do_files folder"
do 00_setup.do          // once
do 04_weights.do
```

The Results window prints each step's summary. The runs are in `export_dir`: one folder per step with `manifest.json` (what ran, when, with which settings and sources, the key results), `manifest.csv` (the same, flat), the CSV tables, and `rtm_display.xlsx` (the Excel display of that step; open it, nothing to set up). The dashboard: run `rtmtools_dashboard` in Stata if the package is installed, or open `rtmtools_dashboard.html` from the package in a browser and use "Open an export folder" to point it at `export_dir`.

## 5. Common messages

| Message | Cause | What to do |
|---|---|---|
| `parameter data_baseline: file ... not found` | path wrong or not run from the folder | `cd` to the folder, or give an absolute path |
| `variable hhid not found` (from `isid` or `merge`) | the id name differs | set `id` |
| `assertion is false` after `bysort strata: egen ... sumsel` | a stratum has no phone household | the stratum cannot be represented; merge strata or set `phone ""` |
| `method classes ... assertion is false` on `nr > 0` | a class has no respondent | fewer class variables, or collapse classes |
| `the balancing did not converge` or `svycal ... convergence not achieved` | too many constraints for the respondents | drop a covariate, use `moments 1`, collapse categories |
| `method ebalance_nobase needs the SSC command ebalance` | not installed | `do 00_setup.do` |
| `assertion is false` on the totals (`Nv - Npop`) | the totals of two calibration variables add to different populations | use totals from one population and year |
| `a total for a category absent from the sample cannot be reached` | a category in the totals file has no respondent | collapse the category in both the data and the totals |

## 6. The portability checklist (what the test does)

1. Copy the folder. 2. Run `00_setup.do`. 3. Put your baseline, round and totals files where the parameters point. 4. Change only the parameter block. 5. Run `04_weights.do` and read the Results window to the end. 6. Open `rtm_display.xlsx` of the last run and check that the weights are positive, that the sums match your totals (calibration) or the baseline (adjustment), and that the response rates are the ones you expect. 7. Keep the run folders with the data: they are the record of how the weights were made.

## 7. When your design is outside the do-file

- **No baseline, a random-digit-dialing sample:** there is no baseline weight to adjust. Set `w_base ""` and `prob_vars` to the selection probability implied by your number generation, or start from equal weights and rely on calibration (`calibrate post` or `rake` to census margins); the nonresponse step then needs `method post` or `classes` with cells from the questionnaire. Document the choice.
- **Several phone numbers per household:** divide the base weight by the number of numbers before step 2 (HFPS Vol. 2 p. 21); add one line after step 1 or use the Stata command `rtmweight base, multiplicity()`.
- **Panel weights for change between rounds:** run the do-file with `data_round` set to the later round and `responded` to its indicator, restricted to the households that responded in the earlier round (`keep if` after the merge), and start from the earlier round's final weight (`w_base`).
- **Person-level weights and household weights from them** (the L2PHL form): the Stata command `rtmweight household` does it; a portable version follows in a later release.
