{smcl}
{* *! version 0.5.0  25oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmweight" "help rtmweight"}{...}
{viewerjumpto "Syntax" "rtmtools_dashboard##syntax"}{...}
{viewerjumpto "Description" "rtmtools_dashboard##description"}{...}
{viewerjumpto "The export" "rtmtools_dashboard##export"}{...}
{viewerjumpto "Options" "rtmtools_dashboard##options"}{...}
{viewerjumpto "Remarks" "rtmtools_dashboard##remarks"}{...}
{title:Title}

{phang}
{bf:rtmtools_dashboard} {hline 2} The export folder of the rtmtools runs, the Excel display and the dashboard page


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmtools_dashboard} [{cmd:,} {opt dir(path)} {opt off} {opt on} {opt clear} {opt nob:rowser}]


{marker description}{...}
{title:Description}

{pstd}
Every rtmtools command writes its run into the export folder ({cmd:rtm_exports} in the working
folder unless {opt dir()} sets another): one folder per run with {cmd:manifest.json} and
{cmd:manifest.csv} (what ran, when, on which file, with which settings and the sources of their
defaults, and the key results), one CSV per table, the Excel workbook {cmd:rtm_display.xlsx} that
shows those tables, and one line appended to the live index {cmd:rtm_exports.js}.
{cmd:rtmtools_dashboard} writes the dashboard page {cmd:rtmtools_dashboard.html} into the export
folder and opens it in the browser. The page reads the live index, shows the progress (which
steps ran, when, with what settings) and the results (weight stages, response by class,
calibration fit, flags, with charts), and refreshes itself every three seconds, so it follows
a do-file as it runs. It computes nothing: every number is read from the export files, and
every table and chart names the file behind it.

{pstd}
The page and the workbook load nothing from the network, and the commands send nothing out.
The exports carry identifiers only, never names, addresses or phone numbers.


{marker export}{...}
{title:The export (schema rtm-export-1.0)}

{pstd}
Run folder name: {it:timestamp}{cmd:_}{it:workflow}{cmd:_ado} (or {cmd:_dofile} for the portable
do-files). Files: {cmd:manifest.json}, {cmd:manifest.csv} (key,value rows), the tables, {cmd:rtm_display.xlsx}.
Tables and their columns:

{p2colset 5 24 26 2}{...}
{p2col:{cmd:weight_stages}}stage, variable, n, sum, min, p1, p5, p25, p50, p75, p95, p99, max, mean, cv, kish_deff, n_trimmed, n_zero{p_end}
{p2col:{cmd:weight_groups}}stage, variable, group_var, group, n, sum, mean, cv{p_end}
{p2col:{cmd:response_classes}}class_var, class, n_sample, n_respondents, response_rate, factor{p_end}
{p2col:{cmd:calibration_fit}}constraint, target, before, after, diff, rel_diff, converged, iterations{p_end}
{p2col:{cmd:weight_units}}unit_id, stratum, psu, one column per weight stage, flag (with {cmd:rtmweight report, units}){p_end}
{p2col:{cmd:flags}}table, unit_id, stage, value, reason{p_end}
{p2col:{cmd:size}, {cmd:allocation}, {cmd:selection}, {cmd:draw_summary}, {cmd:frame_units}, {cmd:frame_summary}, {cmd:boundaries}, {cmd:listing_areas}, {cmd:listing_checks}}the
sampling, frame and listing tables (written when those workflows are rebuilt on this schema){p_end}
{p2colreset}{...}

{pstd}
Conventions: UTF-8, comma, one header row, decimal point, ISO dates, missing empty, 0/1 for
logical values. {cmd:manifest.json} holds {cmd:schema}, {cmd:run_id}, {cmd:source}, {cmd:tool_version},
{cmd:software}, {cmd:workflow}, {cmd:step}, {cmd:started}, {cmd:finished}, {cmd:status}, {cmd:rc}, {cmd:seconds},
{cmd:input} (file, rows, columns), {cmd:command}, {cmd:settings} (value and source per setting),
{cmd:summary} (the command's {cmd:r()} results), {cmd:tables}, {cmd:map}, {cmd:messages}, {cmd:privacy}.
A later version of the schema adds tables or columns and never renames or removes one.


{marker options}{...}
{title:Options}

{phang}
{opt dir(path)} sets the export folder for this session (relative to the working folder, or
absolute); the commands write there from now on.

{phang}
{opt off} stops the export for the session; {opt on} resumes it. In batch runs that must not
export, set {cmd:global RTM_EXPORT "off"} at the top of the do-file.

{phang}
{opt clear} deletes the live index; the run folders are kept.

{phang}
{opt nobrowser} writes the page without opening the browser (the file name is shown).


{marker remarks}{...}
{title:Remarks}

{pstd}
The page is opened through the operating system's default browser (macOS {cmd:open}, Windows
{cmd:rundll32}, Linux {cmd:xdg-open}), never through Stata's viewer. To look at an export folder
from another computer, or at the runs of the portable do-files, open the page and use
{bf:Open an export folder}: it reads the run folders directly (any browser).

{pstd}
The Excel workbook in each run folder is the package's display template filled with that run's
tables: its Weights sheet shows the manifest, the key numbers, the weight stages, the response
by class, the calibration fit and the flagged units, with charts, through lookups and
references only (the Notes sheet lists the formulas used; {cmd:tests/check_display.py} verifies
that nothing else is in the workbook and that every displayed value equals the export).

{pstd}
{cmd:r(dir)} and {cmd:r(html)} return the export folder and the page.
