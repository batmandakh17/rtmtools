# rtmtools

Stata tools, with dialog boxes under **User > RTM tools**, for the statistical design work
around a real-time monitoring phone panel, with a display-only Excel workbook and dashboard, and
a portable do-file package another program can adapt. Version 0.5.0 (25 October 2026).

Stata is the only computational engine. Every sampling and weighting statistic is computed by a
Stata command of the package or by the portable do-file of the same workflow; both write the same
export (one folder per run: `manifest.json`, `manifest.csv`, CSV tables, an Excel workbook). The
Excel workbook and the dashboard read that export and show it; neither computes a probability, a
weight, a factor or a fit statistic. No R anywhere in the weighting workflow (the grid-frame and
spatially balanced steps of earlier versions still call R until they are rebuilt without it).

## What is in the package

| Piece | Where | What it is |
|---|---|---|
| Stata commands and dialogs | the `.ado`, `.dlg`, `.sthlp` files | `rtmweight` (base, nonresponse, trim, calibrate, household, report), `rtmsample`, `rtmframe`, `rtmest`, `rtmtools_setup`, `rtmtools_dashboard` |
| Portable do-files | `portable_do_files/` | `00_setup.do`, `04_weights.do` (parameter block at the top, a comment above every step), `_export_helpers.do`, `ADAPTATION.md`, the template data and a second synthetic program (`adopt_test/`) for the portability test |
| Excel display | `rtm_display.xlsx` (template; `excel/build_display.py` builds it) | copied into every run folder and filled with that run's tables by Stata; its Weights sheet shows them with lookups and charts only |
| Dashboard | `rtmtools_dashboard.html` | a self-contained page written into the export folder; reads the live index `rtm_exports.js` and refreshes every 3 seconds; can also open any export folder |
| Tests | `tests/` | `run_tests.do` (12 test files), `check_display.py` (formula inventory and displayed values of the workbook) |
| Sample data | `data/` | synthetic, made by `data/make_rtm_synthetic.do`; no real household |

## Install

Stata 16 or later (`svycal`, used by calibration and the entropy-balancing method, is part of Stata 18).

From GitHub (the public repository `batmandakh17/rtmtools`):

```
. net install rtmtools, from("https://raw.githubusercontent.com/batmandakh17/rtmtools/main/") replace
. net get rtmtools, from("https://raw.githubusercontent.com/batmandakh17/rtmtools/main/")   // sample data and the portable do-files into the current folder
```

From a local copy of this folder: the same two lines with `from("/path/to/appendix_tools_stata")`.
To move an installed copy to a newer version: `ado update rtmtools, update`.

Then run the setup once:

```
. rtmtools_setup            // adds User > RTM tools for this session and checks the dependencies
. rtmtools_setup, profile   // also appends the menu to profile.do so it is there at every start
. rtmtools_setup, install   // installs the missing SSC commands (survwgt, ebalance, ipfraking, gsample, moremata, geoinpoly, sreweight)
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

`portable_do_files/04_weights.do` does the same weighting workflow in plain Stata, written to be
read top to bottom: a parameter block at the very top (file paths, variable names, strata and PSU,
the method and its settings, trimming, calibration, totals), a comment above every step with its
source, and no dependency on this project's data. It writes the same export as the commands, so
the Excel workbook and the dashboard display it the same way. `ADAPTATION.md` walks through which
lines to change and why; `00_setup.do` installs the community commands once. The portability
test (`tests/test_portable.do`) adapts only the parameter block to the second synthetic program
in `adopt_test/` (other variable names, three strata, PSUs of unequal size, another totals
layout) and checks that the run completes and the weights add to the totals.

```
. cd portable_do_files
. do 00_setup.do
. do 04_weights.do
```

## Sample design and frames (earlier versions, unchanged)

```
. rtmsample size, p(0.2) deff(1) attrition(0.015) rounds(24) firstloss(0.25) domains(4)
. use rtm_frame, clear
. rtmsample allocate, strata(region urban) n(100) size(ea_size_census) min(10) max(16) generate(n_ea)
. rtmsample draw, n(n_ea) strata(stratum) pps(ea_size_census) sort(region urban ea_id) reserve(2) seed(20261024) generate(ea)
. rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) maxsize(250)
```

The grid-frame and spatially balanced steps (`rtmframe grid|replace|split`, `rtmsample grid`)
are the R-backed steps of version 0.4.0; they are to be rebuilt without R in the next steps of
the build and are not part of the display and portable packages yet.

## Status (25 October 2026)

Version 0.5.0 is Step 2 of the build plan: the weighting workflow in its four forms (Stata
command and dialog, portable do-file, Excel display sheet, dashboard tile) on the shared export
schema `rtm-export-1.0`. All twelve test files pass on Stata 18. See `VALIDATION.md` (engine
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
export schema, the portability test, edge cases, bad inputs, reproducibility and an install test.
`python3 tests/check_display.py run_folder` checks the Excel workbook of a run: every formula is
in the allowed list, the data sheets equal the CSV files, and (with Excel on the machine) every
displayed value equals the export.

## Reporting a problem

Send the output of `rtmtools_setup, check`, the command you ran (from the Review window) and,
if possible, a do-file on the sample data that reproduces the problem. For the portable
do-files, send the parameter block and the Results window from the step that failed.
