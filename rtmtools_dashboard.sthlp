{smcl}
{* *! version 0.4.0  24oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmtools_setup" "help rtmtools_setup"}{...}
{viewerjumpto "Syntax" "rtmtools_dashboard##syntax"}{...}
{viewerjumpto "Description" "rtmtools_dashboard##description"}{...}
{viewerjumpto "Options" "rtmtools_dashboard##options"}{...}
{viewerjumpto "What the page shows" "rtmtools_dashboard##page"}{...}
{viewerjumpto "The run log" "rtmtools_dashboard##log"}{...}
{title:Title}

{phang}
{bf:rtmtools_dashboard} {hline 2} Live dashboard of the rtmtools runs: progress, results, charts and the commands to reproduce them


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmtools_dashboard} [{cmd:,} {opt file(path)} {opt off} {opt on} {opt clear} {opt nob:rowser}]

{pstd}
Also under {bf:User > RTM tools > Live dashboard of the runs}.


{marker description}{...}
{title:Description}

{pstd}
Every rtmtools command ({cmd:rtmweight}, {cmd:rtmsample}, {cmd:rtmframe}, {cmd:rtmest}) writes
its start, its progress, its results or its error to a run log, {cmd:rtmtools_runs.js}, in the
working directory. {cmd:rtmtools_dashboard} writes a web page next to that log,
{cmd:rtmtools_dashboard.html}, and opens it in the browser. The page reads the log and refreshes
itself every three seconds, so it follows a do-file while it runs: which step of each workflow is
done, running or failed, the key results of every run with charts, every returned result and
matrix, and the commands in order, ready to copy into a do-file.

{pstd}
The page is self-contained: it loads nothing but the two local files and sends nothing anywhere.
The log holds commands, settings and summary results (counts, sums, rates, seeds, the returned
matrices), never the data.


{marker options}{...}
{title:Options}

{phang}{opt file(path)} uses that run log instead of {cmd:rtmtools_runs.js} in the working
directory, for this call and for the commands that follow in the session (the setting is kept
in the global macro {cmd:RTM_DASHBOARD_FILE}). The page is written in the log's folder.{p_end}
{phang}{opt off} stops the logging for the rest of the session; {opt on} resumes it. Logging is on by
default.{p_end}
{phang}{opt clear} deletes the run log, to start a dashboard for a new piece of work.{p_end}
{phang}{opt nobrowser} writes the page without opening it (for do-files and batch runs).{p_end}


{marker page}{...}
{title:What the page shows}

{phang}{bf:Workflow progress}: the steps of each workflow (frame, sample design, weights,
estimation) with the state of their latest run: done with its time, running, failed with the
return code, or not run yet.{p_end}
{phang}{bf:Runs, newest first}: a card per run with its status, duration, the dataset in memory,
the key results of that tool (for example the response rate and the adjustment factors of
{cmd:rtmweight nonresponse}, the gap to the totals and the g-weights of {cmd:rtmweight calibrate},
the seed and the units selected of {cmd:rtmsample draw}), a chart from the returned matrix (the
adjustment factor by propensity group, the units selected by stratum, the estimates with their
confidence intervals), the command, and under "all results" every returned scalar, macro and
matrix. The filter chips limit the list to one workflow or to the failed runs.{p_end}
{phang}{bf:Commands to reproduce}: the commands of the completed runs in order, to copy or to
download as a do-file. Together with the seeds they record, they rerun the work exactly.{p_end}

{pstd}
A run that started but logged no result shows as "stopped": the command ended with an error that
was not caught (the dispatchers catch and log errors, so this is rare), or it is still running.


{marker log}{...}
{title:The run log}

{pstd}
{cmd:rtmtools_runs.js} is a text file with one JavaScript statement per event,
{cmd:RTM_RUNS.push({c -(}...{c )-});}, holding a JSON object: time, event (start, progress, done,
error), tool, command, dataset and observations in memory, seconds, return code, and for a
completed run every scalar and macro in {cmd:r()} and every returned matrix of up to 1,000 cells.
It is appended to, never rewritten; delete it ({opt clear}) to start afresh. A problem writing it
(a read-only folder, for example) is ignored, so the analysis never stops because of the log.
In batch runs that must not log, set {cmd:global RTM_DASHBOARD "off"} at the top of the do-file.


{title:Examples}

{phang2}{cmd:. cd "C:\surveys\panel_2026"}{p_end}
{phang2}{cmd:. rtmtools_dashboard}{p_end}
{phang2}{cmd:. do weights_round_12.do}{p_end}
{pstd}The page opens in the browser and fills up as the do-file runs.{p_end}

{phang2}{cmd:. rtmtools_dashboard, clear}{p_end}
{pstd}Starts a new log in the same folder.{p_end}


{title:Stored results}

{pstd}{cmd:r(html)}: the page written; {cmd:r(log)}: the run log it reads.{p_end}
