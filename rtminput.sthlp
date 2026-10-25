{smcl}
{* *! version 0.6.0  25oct2026}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmsample" "help rtmsample"}{...}
{vieweralsosee "rtmframe" "help rtmframe"}{...}
{vieweralsosee "rtmlist" "help rtmlist"}{...}
{vieweralsosee "rtmweight" "help rtmweight"}{...}
{viewerjumpto "Syntax" "rtminput##syntax"}{...}
{viewerjumpto "Description" "rtminput##description"}{...}
{viewerjumpto "The workbook" "rtminput##workbook"}{...}
{viewerjumpto "Design keys" "rtminput##design"}{...}
{viewerjumpto "What the runs do" "rtminput##runs"}{...}
{viewerjumpto "Examples" "rtminput##examples"}{...}
{viewerjumpto "Stored results" "rtminput##results"}{...}
{viewerjumpto "Limits" "rtminput##limits"}{...}
{title:Title}

{phang}
{bf:rtminput} {hline 2} One input workbook for a program: check it, and run the sampling or the weighting workflow from it


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtminput} {cmd:using} {it:filename}{cmd:,} {cmd:check} [{cmd:nofiles}]

{p 8 16 2}
{cmd:rtminput} {cmd:using} {it:filename}{cmd:,} {cmd:sampling} [{opt outdir(folder)}]

{p 8 16 2}
{cmd:rtminput} {cmd:using} {it:filename}{cmd:,} {cmd:weights} {opt round(#)} [{opt outdir(folder)}]

{p 8 16 2}
{cmd:rtminput}{cmd:,} {cmd:template} [{cmd:replace}]

{pstd}
{it:filename} is the input workbook ({cmd:rtm_inputs.xlsx}) or a folder holding the same sheets as
CSV files ({cmd:design.csv}, {cmd:strata.csv}, {cmd:frame.csv}, {cmd:totals.csv}, {cmd:cells.csv},
{cmd:prefixes.csv}, {cmd:files.csv}). {cmd:rtmtools input} is the same command.
Dialog: {bf:User > RTM tools > Run from the input workbook...}


{marker description}{...}
{title:Description}

{pstd}
A program that wants to set up the sampling and the weighting of a real-time monitoring survey
fills one workbook instead of naming files and variables in every dialog. The {bf:Design} sheet
holds the method choices as key/value rows, with the allowed values and the source of each
default in its note column; {bf:Strata}, {bf:Frame}, {bf:Totals}, {bf:Cells} and {bf:Prefixes}
hold the aggregate inputs; {bf:Files} points to the household-level data files (baseline, round
files, household list, completed listing) and names their key variables. The data stay in those
files: the workbook carries no household.

{pstd}
{cmd:rtminput, check} reads every sheet, validates it (required columns, duplicates, types,
references between sheets, allowed Design values, files that exist and hold the named variables)
and writes the problems into a {bf:Checks} sheet of a copy of the workbook
({it:name}{cmd:_checked.xlsx}; the original is never changed), and into the export for the
dashboard and the display workbook.

{pstd}
{cmd:rtminput, sampling} and {cmd:rtminput, weights round(#)} stop if the inputs have errors and
otherwise run the package's commands with the workbook's choices, in the order of the handbook's
workflow (below). Every command run is printed and written to a do-file in the output folder
({cmd:rtm_input_sampling_commands.do}, {cmd:rtm_input_weights_round#_commands.do}), so the run can be
read, repeated and adapted; and every command writes its own run folder in the export, as it does
when typed. {cmd:rtminput} adds no statistical step of its own.

{pstd}
{cmd:rtminput, template} copies the shipped template, filled with the package's synthetic example,
into the current folder.


{marker workbook}{...}
{title:The workbook (schema rtm-input-1.0)}

{pstd}Sheet names and the heading row must stay as they are; required columns are shaded in the template.{p_end}

{p2colset 5 20 22 2}{...}
{p2col:{bf:Design}}one row per setting: {cmd:key}, {cmd:value}, {cmd:note}. Blank value = the default. Rows whose key starts with {cmd:#} are headings.{p_end}
{p2col:{bf:Strata}}one row per stratum: {cmd:stratum_id} (required), {cmd:label}, {cmd:population_hh}, {cmd:population_persons}.{p_end}
{p2col:{bf:Frame}}one row per area: {cmd:area_id}, {cmd:stratum_id}, {cmd:size_hh} (required); {cmd:size_persons}, {cmd:x}, {cmd:y} (projected coordinates, for {cmd:stage1 grid}), {cmd:exclude} (0/1) and any columns named in {cmd:sort_vars} optional.{p_end}
{p2col:{bf:Totals}}one row per category for calibration: {cmd:variable}, {cmd:level}, {cmd:total}, the layout {helpb rtmweight} {cmd:calibrate} reads with {cmd:totalsfile()}.{p_end}
{p2col:{bf:Cells}}one row per census cell for {cmd:nonresponse post}: the cell variables, then {cmd:total}.{p_end}
{p2col:{bf:Prefixes}}one row per operator prefix for random digit dialing: {cmd:prefix}, {cmd:n_numbers}, {cmd:digits} (the same on every row).{p_end}
{p2col:{bf:Files}}one row per data file: {cmd:role} ({cmd:baseline}, {cmd:round}, {cmd:household_list}, {cmd:listing}), {cmd:path} (relative to the workbook's folder or absolute; .dta, .csv or .xlsx), and the names of its variables: {cmd:id}; for a round {cmd:response} and {cmd:round} (the number); for the baseline {cmd:psu}, {cmd:strata}, {cmd:weight} or {cmd:probabilities}, {cmd:phone}; for a household list or listing {cmd:area_id} (the column matching Frame {cmd:area_id}).{p_end}
{p2colreset}{...}


{marker design}{...}
{title:Design keys}

{pstd}The value in brackets is the default when the row is blank; the source of each default is in the template's note column and in the command's help.{p_end}

{p2colset 5 26 28 2}{...}
{p2col:{cmd:project}, {cmd:seed}, {cmd:output_dir}}the program's name; the seed every draw uses (blank: Stata draws one and records it); the output folder [{cmd:rtm_outputs}].{p_end}
{p2col:{cmd:target}}{cmd:level} | {cmd:change} [level]: what the sample size is set for ({helpb rtmsample} {cmd:size}).{p_end}
{p2col:{cmd:p}, {cmd:relmargin}, {cmd:margin}, {cmd:change}, {cmd:power}, {cmd:deff}, {cmd:nonresponse_mult}, {cmd:attrition}, {cmd:rounds}, {cmd:firstloss}, {cmd:domains}}the sample-size inputs; the size step runs only when {cmd:p} or {cmd:change} is given.{p_end}
{p2col:{cmd:minsize}, {cmd:maxsize}}flags of the frame check ({helpb rtmframe} {cmd:list}) [0 = none].{p_end}
{p2col:{cmd:n_areas}}areas to select in total (required for sampling).{p_end}
{p2col:{cmd:allocation}, {cmd:power_q}, {cmd:min_areas}, {cmd:max_areas}}{cmd:proportional} | {cmd:equal} | {cmd:neyman} | {cmd:power} [proportional], the power exponent, the bounds per stratum ({helpb rtmsample} {cmd:allocate}).{p_end}
{p2col:{cmd:stage1}, {cmd:sort_vars}, {cmd:reserve_areas}}{cmd:ppssys} | {cmd:pps} | {cmd:systematic} | {cmd:srs} | {cmd:grid} [ppssys]; the Frame columns giving the geographic order [stratum_id area_id]; reserves per stratum, a number or {cmd:all} [2] ({helpb rtmsample} {cmd:draw}, {cmd:grid}).{p_end}
{p2col:{cmd:households_per_area}}households per selected area from the {cmd:household_list} or {cmd:listing} file [blank = no second stage].{p_end}
{p2col:{cmd:segment_size}}households per listing segment [150]: without a household list, the listing forms for the selected areas are written after the first stage ({helpb rtmlist} {cmd:prepare}), areas above this size in segments with one chosen per area; a returned {cmd:listing} file is checked against them ({cmd:rtmlist import}) before the household draw.{p_end}
{p2col:{cmd:phone_per_psu}}households per PSU in the phone subsample of the baseline, every other household an ordered replacement [blank = none].{p_end}
{p2col:{cmd:rdd}}{cmd:yes} | {cmd:no} [no]: numbers from the Prefixes sheet ({helpb rtmsample} {cmd:rdd}); the numbers are saved, never exported.{p_end}
{p2col:{cmd:base_weight}}{cmd:baseline} | {cmd:probabilities} [baseline] ({helpb rtmweight} {cmd:base}).{p_end}
{p2col:{cmd:nonresponse}, {cmd:covariates}, {cmd:classes}, {cmd:cells}, {cmd:ngroups}, {cmd:moments}}{cmd:propensity} | {cmd:probit} | {cmd:classes} | {cmd:ebalance} | {cmd:ebalance_nobase} | {cmd:post} | {cmd:none} [propensity, the guidelines' default: a logit response propensity in deciles]; what each method needs ({helpb rtmweight} {cmd:nonresponse}).{p_end}
{p2col:{cmd:trim}, {cmd:trim_pct}, {cmd:trim_cap}, {cmd:trim_capmult}}{cmd:none} | {cmd:winsor} | {cmd:cap} [none] ({helpb rtmweight} {cmd:trim}).{p_end}
{p2col:{cmd:calibrate}, {cmd:cal_vars}, {cmd:cal_ll}, {cmd:cal_ul}}{cmd:none} | {cmd:rake} | {cmd:regress} | {cmd:post} [none]; the categorical variables to calibrate on [every variable on the Totals sheet]; bounds ({helpb rtmweight} {cmd:calibrate}).{p_end}
{p2col:{cmd:report_by}, {cmd:report_files}}the by-group of the report; {cmd:yes} | {cmd:no} [yes] for the Word note and Excel report ({helpb rtmweight} {cmd:report}).{p_end}
{p2colreset}{...}


{marker runs}{...}
{title:What the runs do}

{pstd}{bf:sampling} (outputs in {cmd:output_dir}):{p_end}
{phang2}1. {cmd:rtmsample size} with the size keys, if {cmd:p} or {cmd:change} is given (a table in the export only).{p_end}
{phang2}2. The Frame sheet saved as {cmd:rtm_input_frame.dta} (with the Strata labels merged), then {cmd:rtmframe list} with {cmd:minsize}, {cmd:maxsize} and {cmd:exclude}; units it flags are left out of the draw.{p_end}
{phang2}3. {cmd:rtmsample allocate} of {cmd:n_areas} across {cmd:stratum_id} by {cmd:allocation} with the bounds.{p_end}
{phang2}4. {cmd:rtmsample draw} (or {cmd:grid}) by {cmd:stage1}, sorted by {cmd:sort_vars}, with {cmd:reserve_areas} and the seed; saved as {cmd:rtm_sample_areas.dta} (selection, probability, weight, reserve rank, certainty).{p_end}
{phang2}5. Without a {cmd:household_list} file: the listing forms for the selected areas ({cmd:rtmlist prepare}, segments of {cmd:segment_size}), saved as {cmd:rtm_listing_forms.xlsx} and {cmd:rtm_sample_areas_selected.dta}.{p_end}
{phang2}6. If {cmd:households_per_area} is set: the selected areas merged with the {cmd:household_list} file, or the completed {cmd:listing} read and checked with {cmd:rtmlist import}; then {cmd:rtmsample draw} within areas and {cmd:rtmweight base} from the two (or three, with segments) stage probabilities; saved as {cmd:rtm_sample_households.dta}.{p_end}
{phang2}7. If {cmd:phone_per_psu} is set: {cmd:rtmsample draw} within the baseline's PSUs with {cmd:reserve(all)}, and {cmd:rtmweight base} redistributing the baseline weight to the phone sample within strata; saved as {cmd:rtm_sample_phone.dta}.{p_end}
{phang2}8. If {cmd:rdd} is yes: {cmd:rtmsample rdd} from the Prefixes sheet; saved as {cmd:rtm_rdd_numbers.dta}.{p_end}

{pstd}{bf:weights round(#)}:{p_end}
{phang2}1. The baseline merged with the round file on {cmd:id}; a household absent from the round file counts as not interviewed.{p_end}
{phang2}2. {cmd:rtmweight base}: the baseline weight redistributed to the phone sample within strata, or 1 / product of the probabilities; the file is then restricted to the phone sample.{p_end}
{phang2}3. {cmd:rtmweight nonresponse} by {cmd:nonresponse} with its covariates, classes or cells (the Cells sheet saved as a cell file).{p_end}
{phang2}4. {cmd:rtmweight trim} by {cmd:trim}, respondents only.{p_end}
{phang2}5. {cmd:rtmweight calibrate} to the Totals sheet (saved as a totals file) by {cmd:calibrate}, respondents only.{p_end}
{phang2}6. {cmd:rtmweight report} of the four weights, with the Word note and the Excel report in the output folder; the data saved as {cmd:rtm_weights_round#.dta} with {cmd:w0}, {cmd:w1}, {cmd:w1t}, {cmd:w2}.{p_end}

{pstd}Steps the Design sheet turns off ({cmd:none}, blank) are recorded in the commands do-file as a note and the weight is carried forward unchanged.{p_end}


{marker examples}{...}
{title:Examples}

{pstd}The template, filled with the synthetic example (the sample data must be in the same folder: {cmd:net get rtmtools}):{p_end}
{phang2}{cmd:. rtminput, template}{p_end}
{phang2}{cmd:. rtminput using rtm_inputs.xlsx, check}{p_end}
{phang2}{cmd:. rtminput using rtm_inputs.xlsx, sampling}{p_end}
{phang2}{cmd:. rtminput using rtm_inputs.xlsx, weights round(1)}{p_end}
{phang2}{cmd:. do rtm_outputs/rtm_input_weights_round1_commands.do}{p_end}

{pstd}The same inputs as a folder of CSV files:{p_end}
{phang2}{cmd:. rtminput using inputs_csv/, check}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}{cmd:check}: {cmd:r(n_errors)}, {cmd:r(n_warnings)}, {cmd:r(checked)} (the copy with the Checks sheet), {cmd:r(sheets)} (the sheets found).
{cmd:sampling} and {cmd:weights}: {cmd:r(outdir)}, {cmd:r(commands)} (the do-file of the commands run), {cmd:r(n_warnings)}; the commands' own results are in their export folders.{p_end}


{marker limits}{...}
{title:Limits}

{pstd}The workbook covers the choices a program must make; rare options of the commands (variance
strata, bounds on balancing, person-level weights and household weights from them, grid frames from
rasters) are run by command or dialog. Random walk at the second stage is not a draw; a program
using it enters its second-stage probability itself. The Frame sheet is read whole into Stata
(fine for tens of thousands of areas); household-level files are never read into the workbook.
Variables named on the Files sheet are checked in .dta files only; .csv and .xlsx files are
converted on the run. Nothing is recommended: the defaults are the cited ones of each command.{p_end}


{title:Sources of the defaults}

{pstd}As in the commands: Himelein et al. (2020) {it:HFPS Vol. 2} for the propensity adjustment, the subsampling factor and the trimming percentile; UN (2008) {it:Designing Household Survey Samples} for sizes, allocation, systematic PPS and reserves; Deville and Särndal (1992) for calibration; Hainmueller (2012) for entropy balancing; the L2 programs' do-files for the balancing and post-stratification forms, labeled as program practice.{p_end}


{title:Also see}

{psee}{helpb rtmtools}, {helpb rtmsample}, {helpb rtmframe}, {helpb rtmlist}, {helpb rtmweight}, {helpb rtmtools_dashboard}{p_end}
