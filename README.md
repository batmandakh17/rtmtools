# rtmtools

Stata tools, with dialog boxes under **User > RTM tools**, for the statistical design work
around a real-time monitoring phone panel. Version 0.4.0 covers three workflows: the weights
of a round (`rtmweight`: base weights, nonresponse and attrition adjustment, trimming,
calibration, report) with design-based estimation (`rtmest`); the sample design
(`rtmsample`: sample size per domain, allocation across strata, probability draws from a frame
with inclusion probabilities, design weights and reserve units, spatially balanced draws from a
grid frame); and frames of areas (`rtmframe`: checks on a list frame, grid frames from boundary
files and a population raster, replacement cells, splits of large cells). Listing support and
small-area estimation follow in later versions (see `PROPOSAL.md`).

Users are task team members and survey firm staff who know Stata. R is not required for the
list-frame, weighting, estimation and list-based sampling steps. The steps that use it run in the
background and are optional: the ReGenesees calibration features, the grid frames (sf, terra)
and the spatially balanced draws (spsurvey).

## Install

Stata 16 or later (the default calibration engine, `svycal`, is part of Stata 18).

From a local copy of this folder:

```
. net install rtmtools, from("/path/to/rtmtools") replace
. net get rtmtools, from("/path/to/rtmtools")        // sample data into the current folder
```

From GitHub (the public repository `batmandakh17/rtmtools`):

```
. net install rtmtools, from("https://raw.githubusercontent.com/batmandakh17/rtmtools/main/") replace
. net get rtmtools, from("https://raw.githubusercontent.com/batmandakh17/rtmtools/main/")
```

Then run the setup once:

```
. rtmtools_setup            // adds User > RTM tools for this session, checks dependencies and R
. rtmtools_setup, profile   // also appends the menu to profile.do so it is there at every start
. rtmtools_setup, install   // installs the missing SSC commands (survwgt, ipfraking, gsample, moremata, fhsae, sreweight)
```

## Optional R setup

R is needed for `rtmweight calibrate, engine(regenesees)` (logit distance, exact bounds,
constrained trimming, cluster-constant weights), for `rtmframe grid`, `rtmframe replace` and
`rtmframe split` (sf, terra) and for `rtmsample grid` (spsurvey). Install R from
https://cran.r-project.org, then in R:

```
install.packages(c("haven", "remotes", "sf", "terra", "spsurvey"))
remotes::install_github("DiegoZardetto/ReGenesees")
```

`rtmtools_setup, check` reports what it finds. If Rscript is not in a standard location,
save its path once: `rtmtools_setup, path("C:\Program Files\R\R-4.4.1\bin\Rscript.exe")`.

## Use

Open **User > RTM tools > Weights > ...**, fill in the dialog and click OK; the command appears
in the Results and Review windows, so a do-file can rerun it. Or type the commands:

```
. use rtm_baseline, clear
. merge 1:1 hhid using rtm_round1, keepusing(responded_r1 skipmeal_r1 worked_r1) nogenerate
. rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
. keep if phone == 1
. rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)
. rtmweight trim w1 if responded_r1, generate(w1t) rule(winsor) pct(98)
. rtmweight calibrate i.region i.urban [pw=w1t] if responded_r1, generate(w2) totalsfile(rtm_totals_long.dta)
. rtmweight report w0 w1 w1t w2 if responded_r1, notes docx(weighting_note.docx)
. rtmest skipmeal_r1 worked_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) over(urban)
```

Sample design, from **User > RTM tools > Sample > ...** or typed:

```
. rtmsample size, p(0.2) deff(1) attrition(0.015) rounds(24) firstloss(0.25) domains(4)
. use rtm_frame, clear
. rtmsample allocate, strata(region urban) n(100) size(ea_size_census) min(10) max(16) generate(n_ea)
. rtmsample draw, n(n_ea) strata(stratum) pps(ea_size_census) sort(region urban ea_id) reserve(2) seed(20261024) generate(ea)
. keep if ea_sel == 1
. keep ea_id ea_pi stratum
. merge 1:m ea_id using rtm_population, keep(match) nogenerate
. rtmsample draw, n(12) strata(ea_id) seed(20261025) generate(hh)
. rtmweight base if hh_sel == 1, probability(ea_pi hh_pi) generate(w_base)
```

Frames, from **User > RTM tools > Frame > ...** or typed (the grid steps need R):

```
. use rtm_frame, clear
. rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) maxsize(250) merge(unit) sort(ea_id)
. rtmframe grid using rtm_boundaries.gpkg, raster(rtm_population.tif) cellsize(10000) strata(region) saving(rtm_grid.gpkg) clear
. rtmsample grid using rtm_grid.gpkg, n(5) strata(stratum) nover(2) seed(20261024) generate(g)
. rtmframe replace using rtm_grid.gpkg, cells(45) selected(g_sel) clear
. rtmframe split using rtm_grid.gpkg, cells(60) parts(2) raster(rtm_population.tif) clear
```

## Live dashboard

Every command logs its start, progress, results and errors to `rtmtools_runs.js` in the working
folder. `rtmtools_dashboard` (also under **User > RTM tools**) writes a self-contained page next to
it and opens it in the browser; the page refreshes itself every few seconds while a do-file runs,
showing the progress of each workflow, the results and charts of every run, and the commands to
reproduce them. It reads only the two local files. `rtmtools_dashboard, off` stops the logging,
`clear` starts a new log.

```
. rtmtools_dashboard
. do weights_round_12.do
```

`help rtmtools`, `help rtmweight`, `help rtmsample`, `help rtmframe`, `help rtmest` and
`help rtmtools_dashboard` describe every option, its cited default and its limits.

## Status (24 October 2026)

Version 0.4.0 holds the weighting and estimation workflow (Step 2 of the build plan, 24 October
2026), the sample design workflow (`rtmsample`) and the frame workflow (`rtmframe` with
`rtmsample grid`), the last two added the same day after the author's go-ahead, and the live
dashboard of the runs. All eleven test files pass on Stata 18 with R 4.3.1, ReGenesees 2.5, sf 1.0.15, terra 1.7.71 and spsurvey 5.5.1.
The dialogs passed static checks only; they have not yet been opened in the Stata GUI. See `VALIDATION.md` (what was
checked and the figures), `USABILITY.md` (the new-user passes and the fixes they led to) and
`OPEN_ITEMS.md` (questions for the handbook's author, dependencies, what is untested).

## Tests

```
. cd tests
. do run_tests.do
```

`run_tests.do` runs every `test_*.do` and prints PASS or FAIL for each (hand calculations on a
tiny frame, the synthetic data, cross-checks between svycal, ipfraking and ReGenesees, the R
bridge, edge cases, bad inputs, reproducibility and an install test). The R tests are skipped
with a note when R or ReGenesees is missing. `tests/crosscheck_engines.do` prints the
cross-engine and cross-language figures quoted in `VALIDATION.md` without asserting them.

## Sample data

Everything under `data/` is synthetic, generated by `data/make_rtm_synthetic.do` with a fixed
seed; no real household is represented.

## Reporting a problem

Send the output of `rtmtools_setup, check`, the command you ran (from the Review window) and,
if possible, a do-file on the sample data that reproduces the problem.
