{smcl}
{* *! version 0.6.1  25oct2026  rtmtools}{...}
{vieweralsosee "rtminput" "help rtminput"}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{viewerjumpto "Before you start" "rtmtools_start##before"}{...}
{viewerjumpto "The steps" "rtmtools_start##steps"}{...}
{viewerjumpto "Later rounds" "rtmtools_start##rounds"}{...}
{viewerjumpto "If something goes wrong" "rtmtools_start##wrong"}{...}
{title:Start here: sampling and weights from one workbook, step by step}

{pstd}
Each numbered step below is a link: click it and Stata runs that step. You type nothing. Every
step writes a plain-language summary and opens it; the files it makes go into the folder
{bf:rtm_outputs} inside your project folder. Every number comes from the handbook's
documented commands ({helpb rtmsample}, {helpb rtmframe}, {helpb rtmweight}), and the method
choices are yours, made on the workbook's Design sheet. Nothing leaves your computer.


{marker before}{...}
{title:Before you start}

{pstd}You need, as files on your computer:{p_end}
{phang2}1. A list of the areas (enumeration areas, villages, blocks) with the number of households in each and the stratum each belongs to. This goes on the workbook's {bf:Frame} sheet.{p_end}
{phang2}2. Population totals by the groups you will calibrate to (region, urban/rural, sex by age), if you calibrate. This goes on the {bf:Totals} sheet.{p_end}
{phang2}3. For the weights of a round: the baseline file (one row per household, with its weight,
stratum and PSU) and the round's file (one row per household called, with 1 = interviewed), as
Stata, CSV or Excel files. Their names go on the {bf:Files} sheet; the data stay in the
files.{p_end}

{pstd}Then choose the project folder, where the workbook and the outputs will live:
{stata "rtmtools_start, folder":show the current folder}. To change it, use the menu
{bf:File > Change Working Directory...} and pick the folder.{p_end}


{marker steps}{...}
{title:The steps}

{pstd}{bf:Step 1. Get the workbook.}
{stata "rtminput, template replace":Write rtm_inputs.xlsx into the project folder}, then
{stata `"rtmtools_start, open("rtm_inputs.xlsx")"':open it in Excel}.
Its {bf:Start here} sheet asks four questions and tells you which sheets to fill. Fill the
{bf:Design} sheet from its dropdowns (every row has a plain question and the source of its default),
paste your areas into {bf:Frame}, your totals into {bf:Totals}, and name your data files on
{bf:Files}. Save it under the same name. (The workbook comes filled with a synthetic example, so
you can run every step once before replacing anything.){p_end}

{pstd}{bf:Step 2. Check the workbook.}
{stata "rtminput using rtm_inputs.xlsx, check":Check every sheet}.
The summary that opens lists every problem with its sheet, row and column; the same list is in a
copy of the workbook ({bf:rtm_inputs_checked.xlsx}, sheet Checks). Fix the problems in your
workbook and check again until it says 0 errors.{p_end}

{pstd}{bf:Step 3. Draw the sample.}
{stata "rtminput using rtm_inputs.xlsx, sampling":Run the sampling}.
This sizes the sample, checks the area frame, allocates the areas across strata, draws them,
draws the households (if you gave a household list) and the phone sample (if you gave a baseline),
as the Design sheet says. The summary that opens says what was drawn, how many, and where the
files are ({bf:rtm_outputs/rtm_sample_areas.dta}, {bf:rtm_sample_households.dta},
{bf:rtm_sample_phone.dta}).{p_end}

{pstd}{bf:Step 4. Weight a round.}
{stata "rtminput using rtm_inputs.xlsx, weights round(1)":Compute the weights of round 1}.
This takes the baseline and the round's file named on the Files sheet, adjusts the weights for the
households that could not be interviewed (by the method on the Design sheet), trims and calibrates
them if asked, and writes the weighting report (Word and Excel) and the data with the weights
({bf:rtm_outputs/rtm_weights_round1.dta}).{p_end}

{pstd}{bf:Step 5. Look at the results.}
{stata "rtmtools_start, summary":Open the latest summary} (it opens by itself after each step), or
{stata "rtmtools_dashboard":open the dashboard}, which follows every step with its tables and
charts, or open the folder {bf:rtm_outputs}. Every step also writes the exact commands it ran into
a do-file there, so a colleague can repeat it.{p_end}


{marker rounds}{...}
{title:Later rounds}

{pstd}Add a row for the new round on the {bf:Files} sheet (role {bf:round}, the file's path, the
column holding 1 = interviewed, and the round number), then run the weights for it:
{stata "rtminput using rtm_inputs.xlsx, weights round(2)":round 2},
{stata "rtminput using rtm_inputs.xlsx, weights round(3)":round 3},
{stata "rtminput using rtm_inputs.xlsx, weights round(4)":round 4},
{stata "rtminput using rtm_inputs.xlsx, weights round(5)":round 5},
{stata "rtminput using rtm_inputs.xlsx, weights round(6)":round 6};
for another round number use the dialog {stata "db rtminput":Run from the input workbook...}.{p_end}


{marker wrong}{...}
{title:If something goes wrong}

{phang2}{bf:The check lists errors.} Each line names the sheet, the Excel row and the column. The
usual ones: a repeated area_id, a missing household count, a stratum on the Frame sheet that is not
on the Strata sheet, a Design value that is not one of the dropdown's choices, a file path that does
not exist, a variable name that is not in the file. Fix the cell and check again.{p_end}
{phang2}{bf:A step stops with a message.} The message names what is wrong in plain words and the
Stata error behind it. The commands that ran before the stop are in
{bf:rtm_outputs/rtm_input_..._commands.do}.{p_end}
{phang2}{bf:The dropdowns are missing} (the workbook was saved by another program): the allowed values are in each row's note and in {helpb rtminput##design:help rtminput}.{p_end}
{phang2}{bf:You want to see what a step did, line by line.} Open the commands do-file in {bf:rtm_outputs}: each line is one documented command, with a comment above it naming the step.{p_end}
{phang2}{bf:You know Stata and want more control.} The dialogs under {bf:User > RTM tools} run each command with every option; {helpb rtmtools} lists them.{p_end}


{title:Also see}

{psee}{helpb rtminput} (every Design key), {helpb rtmtools} (the package), {helpb rtmtools_dashboard}{p_end}
