{smcl}
{* *! version 0.1.0  24oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmweight" "help rtmweight"}{...}
{vieweralsosee "[SVY] svyset" "help svyset"}{...}
{vieweralsosee "[SVY] svy estimation" "help svy_estimation"}{...}
{vieweralsosee "[SVY] estat" "help svy_estat"}{...}
{viewerjumpto "Syntax" "rtmest##syntax"}{...}
{viewerjumpto "Description" "rtmest##description"}{...}
{viewerjumpto "Options" "rtmest##options"}{...}
{viewerjumpto "Examples" "rtmest##examples"}{...}
{viewerjumpto "Stored results" "rtmest##results"}{...}
{title:Title}

{phang}
{bf:rtmest} {hline 2} Design-based estimates with the panel's weights: means, proportions, totals and ratios by domain, with standard errors, design effects and coefficients of variation


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmest} {varlist} {ifin}{cmd:,} {opt weight(varname)}
[{opt str:ata(varname)} {opt psu(varname)} {opt fpc(varname)} {opt single:unit(method)} {opt vce(vcetype)}
{opt over(varname)} {opt subpop(varname)} {opt stat(mean|proportion|total|ratio)} {opt ratio(num den)}
{opt cv:flag(#)} {opt level(#)} {opt cal:ibration(spec)} {opt nocal:ibration} {opt ex:cel(filename)} {opt nosvy:set}]

{pstd}
Dialog: {dialog rtmest}; or {bf:User > RTM tools > Estimate with the design...} after {helpb rtmtools_setup}.


{marker description}{...}
{title:Description}

{pstd}
{cmd:rtmest} declares the survey design with {helpb svyset} (strata, primary sampling units,
optional finite population correction, and the calibration recorded by {helpb rtmweight}
{cmd:calibrate}), then estimates the statistic for each variable in {it:varlist}, overall or by
domain, with {helpb svy}. It reports the estimate, its standard error, the confidence interval,
the design effect ({cmd:estat effects}) and the coefficient of variation ({cmd:estat cv}), and flags
estimates whose CV reaches {opt cvflag()} percent. Variance estimation is Taylor linearization
unless {opt vce()} says otherwise. The design file needs the weight, the strata and the PSU
codes (UN 2008, pp. 152-153; Grosh and Mu{c n~}oz 1996, p. 166); households that moved keep
their original codes (Dabalen et al. 2016, p. 50).

{pstd}
When the dataset carries a calibration recorded by {cmd:rtmweight calibrate} with the Stata
engine ({cmd:char _dta[rtm_cal_svyset]}), it is declared in {cmd:svyset} with {cmd:rake()} or
{cmd:regress()}, so that the standard errors account for the calibration ([SVY] svyset; Stata
15.1 or later). The record is used only when {opt weight()} is the calibrated weight or the weight
it was computed from; any other weight (for example one trimmed after calibration) is treated as
fixed, with a note. {opt nocalibration} treats the weights as fixed in every case; {opt calibration(spec)}
declares another specification.


{marker options}{...}
{title:Options}

{phang}{opt weight(varname)} is the final weight (required; the option's full name is
{cmd:weightvar()}, which error messages use). It must be positive for every observation in the
estimation sample, so restrict to the respondents with {it:if}.{p_end}
{phang}{opt strata(varname)} and {opt psu(varname)}: the stratum and primary-sampling-unit codes. Without psu(), observations are the sampling units.{p_end}
{phang}{opt fpc(varname)}: finite population correction, as in svyset. Usually ignored in household surveys (Grosh and Mu{c n~}oz 1996, p. 71).{p_end}
{phang}{opt singleunit(method)}: how strata with one sampling unit are handled: {cmd:missing}
(default, as in Stata: missing standard errors), {cmd:certainty}, {cmd:scaled} or {cmd:centered}. UN
2008 (p. 57, p. 157) asks for at least two units per stratum or the collapsing of strata; the
command reports singleton strata.{p_end}
{phang}{opt vce(vcetype)}: {cmd:linearized} (default), {cmd:bootstrap}, {cmd:brr}, {cmd:jackknife}
or {cmd:sdr}; replication methods need replicate weights set with svyset beforehand (use
{opt nosvyset}).{p_end}
{phang}{opt over(varname)}: domains.{p_end}
{phang}{opt subpop(varname)}: subpopulation indicator (1 = in), the right way to restrict a design-based estimate.{p_end}
{phang}{opt stat()}: {cmd:mean} (default), {cmd:proportion}, {cmd:total} or {cmd:ratio} with {opt ratio(numerator denominator)}.{p_end}
{phang}{opt cvflag(#)}: flag estimates with CV at or above # percent (default 30, a common publication threshold; a judgment, not a cited rule).{p_end}
{phang}{opt level(#)}: confidence level.{p_end}
{phang}{opt excel(filename)}: writes the table with putexcel.{p_end}
{phang}{opt nosvyset}: use the design already declared with svyset (for replicate weights or multistage designs).{p_end}


{marker examples}{...}
{title:Examples}

{phang2}{cmd:. use rtm_baseline, clear}{p_end}
{phang2}{cmd:. merge 1:1 hhid using rtm_round1, keepusing(responded_r1 skipmeal_r1 worked_r1) nogenerate}{p_end}
{phang2}{cmd:. rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)}{p_end}
{phang2}{cmd:. keep if phone == 1}{p_end}
{phang2}{cmd:. rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)}{p_end}
{phang2}{cmd:. rtmweight calibrate i.region i.urban [pw=w1] if responded_r1, generate(w2) totalsfile(rtm_totals_long.dta)}{p_end}

{pstd}Means by urban/rural, with the calibration in the variance{p_end}
{phang2}{cmd:. rtmest skipmeal_r1 worked_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) over(urban) cvflag(20)}{p_end}

{pstd}Proportions, a total, a ratio{p_end}
{phang2}{cmd:. rtmest skipmeal_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) stat(proportion)}{p_end}
{phang2}{cmd:. rtmest hhsize if responded_r1, weight(w2) strata(stratum) psu(psu) stat(total) singleunit(centered) excel(totals.xlsx)}{p_end}
{phang2}{cmd:. rtmest skipmeal_r1 if responded_r1, weight(w2) strata(stratum) psu(psu) stat(ratio) ratio(skipmeal_r1 worked_r1)}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:r(table)}: a matrix with one row per outcome and domain and the columns {cmd:estimate},
{cmd:se}, {cmd:ci_low}, {cmd:ci_high}, {cmd:deff}, {cmd:cv}; {cmd:r(svyset)}: the svyset command used;
{cmd:r(n_singleton_strata)}; {cmd:r(stat)}; {cmd:r(cmdline)}. The command is also recorded in
{cmd:char _dta[rtm_est]} and the dataset notes.


{title:References}

{phang}Dabalen, A., et al. 2016. Mobile Phone Panel Surveys in Developing Countries. World Bank.{p_end}
{phang}Grosh, M., and J. Mu{c n~}oz. 1996. A Manual for Planning and Implementing the Living Standards Measurement Study Survey. LSMS Working Paper 126. World Bank.{p_end}
{phang}United Nations. 2008. Designing Household Survey Samples: Practical Guidelines. Studies in Methods, Series F No. 98.{p_end}
{phang}StataCorp. Stata Survey Data Reference Manual: [SVY] svyset, [SVY] svy estimation, [SVY] estat, [SVY] variance estimation.{p_end}
