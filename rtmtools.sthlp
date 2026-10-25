{smcl}
{* *! version 0.5.0  24oct2026  rtmtools}{...}
{vieweralsosee "rtmweight" "help rtmweight"}{...}
{vieweralsosee "rtmsample" "help rtmsample"}{...}
{vieweralsosee "rtmframe" "help rtmframe"}{...}
{vieweralsosee "rtmest" "help rtmest"}{...}
{vieweralsosee "rtmtools_setup" "help rtmtools_setup"}{...}
{title:Title}

{phang}
{bf:rtmtools} {hline 2} Stata tools for the design and weighting of real-time monitoring phone surveys


{title:Description}

{pstd}
{cmd:rtmtools} gives task teams and survey firms Stata commands, with dialog boxes under
{bf:User > RTM tools}, for the statistical design work around a phone panel. Version 0.5.0
covers:

{phang2}{helpb rtmweight}: base weights; nonresponse and attrition adjustment by weighting classes, logit or probit propensity, entropy balancing with or without base weights, or cell post-stratification (every choice labeled with its source, including the L2 programs\' practice); trimming; calibration to population totals; household weights from person weights; and a weighting report (Excel and Word). No step uses R.{p_end}
{phang2}{helpb rtmest}: design-based estimates (means, proportions, totals, ratios) by domain with standard errors, design effects and coefficients of variation, with the calibration in the variance.{p_end}
{phang2}{helpb rtmsample}: sample size per domain (level or change, with design effect, nonresponse and attrition reserve), allocation across strata, probability draws from a frame (simple random, systematic, PPS) with inclusion probabilities, design weights, reserve units and a recorded seed, the phone subsample of a baseline with every other household as an ordered replacement, a spatially spread draw from a grid frame (serpentine systematic selection) and random digit dialing samples.{p_end}
{phang2}{helpb rtmframe}: checks on a list frame of areas; grid frames from a population raster (ESRI ASCII grid) and boundaries (shapefile), with replacement cells and splits of large cells; no R.{p_end}
{phang2}{helpb rtmtools_dashboard}: every run is exported (manifest, CSV tables, an Excel display workbook) into the export folder, and a self-contained page shows the progress and results of the runs, refreshed while a do-file runs; the workbook and the page read the export and compute nothing. A portable do-file version of the weighting workflow ({cmd:portable_do_files/04_weights.do} with {cmd:ADAPTATION.md}) can be copied and adapted by another program.{p_end}
{phang2}{helpb rtmtools_setup}: the menu and the dependency checks.{p_end}

{pstd}
{phang}{helpb rtmlist}: listing support: listing forms for the selected areas with segmentation of large areas, and the completed listing checked into the household frame.{p_end}

{pstd}
Planned for later versions: Fay-Herriot small-area estimates
({cmd:rtmsae}).

{pstd}
Principles: every statistical step runs through an official Stata command ({helpb svycal},
{helpb svyset}, {helpb svy}, {helpb power}) or an established user-written one ({helpb survwgt},
{helpb ipfraking}, {helpb gsample}), or arithmetic from a cited formula with hand-calculated tests;
no weighting step uses R (the grid frames and spatially balanced draws still do until they
are rebuilt without it); every method default cites a source in the help file; data stay
on your machine; every command writes its settings and version stamp to the dataset's notes
and {cmd:r()}, and the dialogs write the full command to the Review window.


{title:Getting started}

{phang2}{cmd:. rtmtools_setup}{p_end}
{phang2}{cmd:. rtmtools_setup, profile}      {it:(menu at every start)}{p_end}
{phang2}{cmd:. net get rtmtools}            {it:(sample data into the current folder)}{p_end}
{phang2}{cmd:. net get rtmtools_portable}   {it:(portable do-files, template data and ADAPTATION.md)}{p_end}
{phang2}{cmd:. rtmtools_dashboard}        {it:(the live dashboard in the browser)}{p_end}
{phang2}{cmd:. help rtmweight}{p_end}

{pstd}
Minimum Stata version: 16; {cmd:rtmweight calibrate} with its default engine needs {helpb svycal}
(Stata 18); on 16 and 17 use {cmd:engine(ipfraking)}.


{title:Method sources}

{pstd}
Himelein et al. 2020 (High Frequency Mobile Phone Surveys of Households to Assess the Impacts
of COVID-19, Vol. 2: Guidelines on Sampling Design); Dabalen et al. 2016 (Mobile Phone Panel
Surveys in Developing Countries); Broccolini, Seitz and Azevedo 2017 (Listening to Tajikistan:
methods report); Ambel, McGee and Tsegay 2021 (Reducing Bias in Phone Survey Samples);
United Nations 2008 (Designing Household Survey Samples); Grosh and Mu{c n~}oz 1996 (LSMS
manual); Oseni et al. 2021 (Capturing What Matters); the Stata Survey Data Reference Manual;
Kolenikov 2014, 2019 (ipfraking); Hainmueller 2012 and Hainmueller and Xu 2013 (entropy balancing).
