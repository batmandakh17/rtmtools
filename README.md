# rtmtools

Stata tools, with dialog boxes under **User > RTM tools**, for the statistical design work
around a real-time monitoring phone panel, with a display-only Excel workbook and dashboard, and
a portable do-file package another program can adapt. Version 0.5.0 (25 October 2026): the four
workflows (weights, sampling, frames, listing support) in their four forms, without R.

Stata is the only computational engine. Every sampling and weighting statistic is computed by a
Stata command of the package or by the portable do-file of the same workflow; both write the same
export (one folder per run: `manifest.json`, `manifest.csv`, CSV tables, an Excel workbook). The
Excel workbook and the dashboard read that export and show it; neither computes a probability, a
weight, a factor or a fit statistic. Nothing in the package uses R: the grid frames read a text
raster and a shapefile with Stata commands, and the spatially balanced draw of earlier versions is
replaced by a serpentine systematic draw (what is lost is stated in `help rtmsample`).

## What is in the package

| Piece | Where | What it is |
|---|---|---|
| Stata commands and dialogs | the `.ado`, `.dlg`, `.sthlp` files | `rtmweight` (base, nonresponse, trim, calibrate, household, report), `rtmsample` (size, allocate, draw, grid, rdd), `rtmframe` (list, grid, replace, split), `rtmlist` (prepare, import), `rtmest`, `rtmtools_setup`, `rtmtools_dashboard` |
| Portable do-files | `portable_do_files/` | `00_setup.do`, `01_frame.do`, `02_listing.do`, `03_sample.do`, `04_weights.do` (a parameter block at the top, a comment above every step), `_export_helpers.do`, `ADAPTATION.md`, the template data and a second synthetic program (`adopt_test/`) for the portability test |
| Excel display | `rtm_display.xlsx` (template; `excel/build_display.py` builds it) | copied into every run folder and filled with that run's tables by Stata; its Weights, Sampling, Frame and Listing sheets show them with lookups, charts and coordinate maps only |
| Dashboard | `rtmtools_dashboard.html` | a self-contained page written into the export folder; reads the live index `rtm_exports.js` and refreshes every 3 seconds; can also open any export folder |
| Tests | `tests/` | `run_tests.do` (12 test files), `check_display.py` (formula inventory and displayed values of the workbook) |
| Sample data | `data/` | synthetic, made by `data/make_rtm_synthetic.do` (households, rounds, totals, a completed listing) and `data/make_rtm_spatial.py` (boundaries shapefile, population raster as an ESRI ASCII grid); no real household or place |

## Install

Stata 16 or later (`svycal`, used by calibration and the entropy-balancing method, is part of Stata 18).

From GitHub (the public repository `batmandakh17/rtmtools`):

```
. net install rtmtools, from("https://raw.githubusercontent.com/batmandakh17/rtmtools/main/") replace
. net get rtmtools, from("https://raw.githubusercontent.com/batmandakh17/rtmtools/main/")            // sample data into the current folder
. net get rtmtools_portable, from("https://raw.githubusercontent.com/batmandakh17/rtmtools/main/")   // portable do-files, template data and ADAPTATION.md
```

From a local copy of this folder: the same three lines with `from("/path/to/appendix_tools_stata")`.
To move an installed copy to a newer version: `ado update rtmtools, update`.

Then run the setup once:

```
. rtmtools_setup            // adds User > RTM tools for this session and checks the dependencies
. rtmtools_setup, profile   // also appends the menu to profile.do so it is there at every start
. rtmtools_setup, install   // installs the missing SSC commands (survwgt, ebalance, ipfraking, gsample, moremata, shp2dta, geoinpoly, sreweight)
```

## The weighting workflow in Stata

Open **User > RTM tools > Weights > ...**, fill in the dialog and click OK; the command appears
in the Results and Review windows, so a do-file can rerun it. Or type the commands:

```
. use rtm_baseline, clear
. merge 1:1 hhid using rtm_round1, keepusing(responded_r1 responded_r2) nogenerate
. rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)
. keep if phone == 1
. rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)
. rtmweight trim w1 if responded_r1, generate(w1t) rule(winsor) pct(98) id(hhid)
. rtmweight calibrate i.region i.urban [pw=w1t] if responded_r1, generate(w2) totalsfile(rtm_totals_long.dta)
. rtmweight report w0 w1 w1t w2 if responded_r1, notes by(region) id(hhid) units docx(weighting_note.docx)
```

The nonresponse step offers five methods as labeled choices, each with its source in the help:
`logit` or `probit` propensity in deciles (the guidelines' default), `classes` (weighting classes),
`ebalance` (entropy balancing with the base weights kept: raking to the baseline's weighted
moments, the L2 programs' round weights), `ebalance_nobase` (the L2PHL January 2026 form) and
`post` (cell post-stratification to census cells, the L2PHL form since March 2026). The
`household` step derives household weights from person weights (the L2PHL derivation).

```
. rtmweight nonresponse responded_r1, weight(w0) method(ebalance) covariates(urban i.educ head_age assets hhsize) generate(w1e)
. use rtm_persons, clear
. generate byte responded = 1
. rtmweight nonresponse responded, weight(indw) method(post) cells(region urban female age_grp) cellfile(rtm_totals_persons.dta) celltotal(N_persons) generate(indw_post)
. rtmweight household indw_post, hhid(hhid) generate(popw hhw) psuaverage(psu)
```

## The export, the Excel display and the dashboard

Every command writes its run into `rtm_exports/` in the working folder (or the folder set with
`rtmtools_dashboard, dir()`): a run folder with `manifest.json` and `manifest.csv` (what ran, when,
with which settings and the sources of their defaults, the key results), the CSV tables
(`weight_stages`, `response_classes`, `calibration_fit`, `weight_groups`, `flags`, `weight_units`),
and `rtm_display.xlsx`, the display workbook filled with those tables. Open the workbook: its
Weights sheet shows the run; its Notes sheet lists the only formulas used (IF, IFERROR, INDEX,
MATCH, COUNTIF, COUNTA) and states that nothing is recalculated.

```
. rtmtools_dashboard          // writes the page into the export folder and opens it in the browser
. do weights_round_12.do      // the page follows the runs
```

The dashboard shows the progress (which steps ran, when, with what settings) and the results
(weight stages, response by class, calibration fit, flags, with charts), every table and chart
naming the export file behind it. "Open an export folder" reads the runs of another folder, for
example the portable do-files' runs or a colleague's. Nothing is loaded from the network; the
exports carry identifiers only, never names or phone numbers. `rtmtools_dashboard, off` stops the
export for the session.

## The portable do-files (for another program)

`portable_do_files/` holds the four workflows as plain Stata do-files written to be read top to
bottom and copied by another program: `01_frame.do` (a list frame checked and merged, or a grid
frame from a shapefile and a population raster), `02_listing.do` (listing forms with segmentation,
then the completed listing checked into the household frame), `03_sample.do` (sample size,
allocation, systematic PPS draw of areas with certainty units, households per area, the phone
subsample of a baseline) and `04_weights.do` (the weighting chain). Each has a parameter block at
the very top (file paths, variable names, the method and its settings), a comment above every step
with its source, and no dependency on this project's data or on the installed package. They write
the same export as the commands, so the Excel workbook and the dashboard display them the same
way. `ADAPTATION.md` walks through which lines to change and why; `00_setup.do` installs the
community commands once. The portability test (`tests/test_portable.do`) adapts only the parameter
blocks to the second synthetic program in `adopt_test/` and checks that every run completes and
reproduces the commands.

Two ways to get them. The repository (Code > Download ZIP, or `git clone`) keeps the folder layout
the parameter blocks assume (`template/` beside the do-files):

```
. cd portable_do_files
. do 00_setup.do
. do 04_weights.do
```

`net get rtmtools_portable` (see Install) puts the do-files, the template data and the guide in the
current folder with no subfolders, and Stata lower-cases the names (`adaptation.md`): either make a
`template` folder there and move the `rtm_*` files into it, or drop `template/` from the paths in
the parameter block.

## Sampling, frames and listing

```
. rtmsample size, p(0.2) deff(1) attrition(0.015) rounds(24) firstloss(0.25) domains(4)
. use rtm_frame, clear
. rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) maxsize(250)
. rtmsample allocate, strata(region urban) n(100) size(ea_size_census) min(10) max(16) generate(n_ea)
. rtmsample draw, n(n_ea) strata(stratum) pps(ea_size_census) sort(region urban ea_id) reserve(2) seed(20261024) id(ea_id) generate(ea)
. keep if ea_sel
. rtmlist prepare, id(ea_id) expected(ea_size_census) strata(stratum) segmentsize(150) seed(3) saving(listing_forms.xlsx) replace
. rtmlist import using rtm_listing.dta, id(ea_id) expected(ea_size_census) saving(stage2_frame.dta) replace clear
. rtmsample draw, n(12) strata(area_id) seed(20261025) id(hh_seq) generate(hh)
```

The phone subsample of a baseline, every other household an ordered replacement (the L2 practice),
and a random digit dialling sample:

```
. use rtm_baseline, clear
. rtmsample draw, n(6) strata(psu) seed(20251027) reserve(all) id(hhid) generate(ph)
. rtmsample rdd, prefixes(61 62 77) n(300 300 400) digits(6) seed(5) clear
```

Grid frames where no list frame exists: the boundaries as an ESRI shapefile and the population
raster as an ESRI ASCII grid, both in one projected coordinate system (a one-time conversion in
QGIS from GeoPackage and GeoTIFF; `help rtmframe` gives the steps), then a spatially spread draw:

```
. rtmframe grid using rtm_boundaries.shp, raster(rtm_population.asc) cellsize(5000) strata(regcode) id(region) minsize(500) saving(rtm_grid5.dta) savingpixels(rtm_pixels5.dta) clear replace
. rtmsample grid, n(5) strata(stratum) pps(pop) xy(x y) reserve(2) seed(20261025) id(cell_id) generate(g)
. rtmframe replace, cells(45 212) selected(g_sel) ncand(3) saving(rtm_repl.dta) replace
. rtmframe split, cells(45) parts(2) pixels(rtm_pixels5.dta) saving(rtm_parts.dta) replace
```

The dashboard maps the selected cells and the boundaries from the exported coordinates.

## Status (25 October 2026)

Version 0.5.0 covers the four workflows (weights, sampling, frames, listing) in their four forms
(Stata command and dialog, portable do-file, Excel display sheet, dashboard tile) on the shared
export schema `rtm-export-1.0`, with no R anywhere. All test files pass on Stata 18. See `VALIDATION.md` (engine
correctness, display fidelity, the portability test, edge cases, privacy), `USABILITY.md` (the
home-team and adopting-team passes) and `OPEN_ITEMS.md` (questions for the handbook's author,
dependencies, what is untested). The dialogs passed static checks only; they have not yet been
opened in the Stata GUI.

## Tests

```
. cd tests
. do run_tests.do
```

`run_tests.do` runs every `test_*.do` and prints PASS or FAIL for each: hand calculations on a
tiny frame, the synthetic data, the ebalance equality, the svycal and ipfraking cross-check, the
UN 2008 systematic PPS example, the grid frame against the raster total, the listing checks, the
export schema, the portability test, edge cases, bad inputs, reproducibility and an install test.
`python3 tests/check_display.py run_folder` checks the Excel workbook of a run: every formula is
in the allowed list, the data sheets equal the CSV files, and (with Excel on the machine) every
displayed value equals the export.

## Reporting a problem

Send the output of `rtmtools_setup, check`, the command you ran (from the Review window) and,
if possible, a do-file on the sample data that reproduces the problem. For the portable
do-files, send the parameter block and the Results window from the step that failed.
