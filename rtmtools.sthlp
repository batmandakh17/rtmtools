{smcl}
{* *! version 0.2.0  24oct2026  rtmtools}{...}
{vieweralsosee "rtmweight" "help rtmweight"}{...}
{vieweralsosee "rtmsample" "help rtmsample"}{...}
{vieweralsosee "rtmest" "help rtmest"}{...}
{vieweralsosee "rtmtools_setup" "help rtmtools_setup"}{...}
{title:Title}

{phang}
{bf:rtmtools} {hline 2} Stata tools for the design and weighting of real-time monitoring phone surveys


{title:Description}

{pstd}
{cmd:rtmtools} gives task teams and survey firms Stata commands, with dialog boxes under
{bf:User > RTM tools}, for the statistical design work around a phone panel. Version 0.2.0
covers:

{phang2}{helpb rtmweight}: base weights, nonresponse and attrition adjustment, trimming, calibration to population totals, and a weighting report (Excel and Word).{p_end}
{phang2}{helpb rtmest}: design-based estimates (means, proportions, totals, ratios) by domain with standard errors, design effects and coefficients of variation, with the calibration in the variance.{p_end}
{phang2}{helpb rtmsample}: sample size per domain (level or change, with design effect, nonresponse and attrition reserve), allocation across strata, and probability draws from a frame (simple random, systematic, PPS) with inclusion probabilities, design weights, reserve units and a recorded seed.{p_end}
{phang2}{helpb rtmtools_setup}: the menu, dependency checks and the R check.{p_end}

{pstd}
Planned for later versions: frames from lists and from rasters or grids ({cmd:rtmframe}), with
spatially balanced draws, listing support ({cmd:rtmlist}) and Fay-Herriot small-area estimates
({cmd:rtmsae}).

{pstd}
Principles: every statistical step runs through an official Stata command ({helpb svycal},
{helpb svyset}, {helpb svy}, {helpb power}) or an established user-written one ({helpb survwgt},
{helpb ipfraking}, {helpb gsample}), or arithmetic from a cited formula with hand-calculated tests;
R is used only where Stata has no equivalent (the ReGenesees calibration features) and runs
in the background, optional; every method default cites a source in the help file; data stay
on your machine; every command writes its settings and version stamp to the dataset's notes
and {cmd:r()}, and the dialogs write the full command to the Review window.


{title:Getting started}

{phang2}{cmd:. rtmtools_setup}{p_end}
{phang2}{cmd:. rtmtools_setup, profile}      {it:(menu at every start)}{p_end}
{phang2}{cmd:. net get rtmtools}            {it:(sample data into the current folder)}{p_end}
{phang2}{cmd:. help rtmweight}{p_end}

{pstd}
Minimum Stata version: 16; {cmd:rtmweight calibrate} with its default engine needs {helpb svycal}
(Stata 18); on 16 and 17 use {cmd:engine(ipfraking)} or {cmd:engine(regenesees)}.


{title:Method sources}

{pstd}
Himelein et al. 2020 (High Frequency Mobile Phone Surveys of Households to Assess the Impacts
of COVID-19, Vol. 2: Guidelines on Sampling Design); Dabalen et al. 2016 (Mobile Phone Panel
Surveys in Developing Countries); Broccolini, Seitz and Azevedo 2017 (Listening to Tajikistan:
methods report); Ambel, McGee and Tsegay 2021 (Reducing Bias in Phone Survey Samples);
United Nations 2008 (Designing Household Survey Samples); Grosh and Mu{c n~}oz 1996 (LSMS
manual); Oseni et al. 2021 (Capturing What Matters); the Stata Survey Data Reference Manual;
Kolenikov 2014, 2019 (ipfraking); Zardetto 2015 (ReGenesees).
