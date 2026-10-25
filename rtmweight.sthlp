{smcl}
{* *! version 0.5.0  25oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmest" "help rtmest"}{...}
{vieweralsosee "[SVY] svycal" "help svycal"}{...}
{vieweralsosee "[SVY] svyset" "help svyset"}{...}
{viewerjumpto "Syntax" "rtmweight##syntax"}{...}
{viewerjumpto "Description" "rtmweight##description"}{...}
{viewerjumpto "base" "rtmweight##base"}{...}
{viewerjumpto "nonresponse" "rtmweight##nonresponse"}{...}
{viewerjumpto "calibrate" "rtmweight##calibrate"}{...}
{viewerjumpto "trim" "rtmweight##trim"}{...}
{viewerjumpto "household" "rtmweight##household"}{...}
{viewerjumpto "report" "rtmweight##report"}{...}
{viewerjumpto "Export" "rtmweight##export"}{...}
{viewerjumpto "Examples" "rtmweight##examples"}{...}
{viewerjumpto "Stored results" "rtmweight##results"}{...}
{viewerjumpto "Limits" "rtmweight##limits"}{...}
{viewerjumpto "References" "rtmweight##references"}{...}
{title:Title}

{phang}
{bf:rtmweight} {hline 2} Survey weights for a real-time monitoring phone panel: base weights, nonresponse and attrition
adjustment (five labeled methods), calibration, trimming, household weights from person weights, and a weighting report; every run exported for the Excel display and the dashboard


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmweight} {cmd:base} {ifin}{cmd:,} {opt gen:erate(newvar)}
{c -(} {opt prob:ability(varlist)} {c |} {opt base:weight(varname)} [{opt sub:sample(varname)} {opt by(varlist)}] {c )-}
[{opt mult:iplicity(varname)} {opt replace}]

{p 8 16 2}
{cmd:rtmweight} {cmd:nonresponse} {it:respvar} {ifin}{cmd:,} {opt weight(varname)} {opt gen:erate(newvar)}
[{opt meth:od(logit|probit|classes|ebalance|ebalance_nobase|post)} {opt cov:ariates(varlist)} {opt class:es(varlist)}
{opt cells(varlist)} {opt cellf:ile(filename)} {opt cellt:otal(varname)} {opt by(varlist)} {opt ng:roups(#)} {opt mom:ents(1|2|3)}
{opt min:cell(#)} {opt weightedmodel} {opt nocross:check} {opt replace} {opt noi:sily}]

{p 8 16 2}
{cmd:rtmweight} {cmd:calibrate} {it:varlist} {ifin} {cmd:[pw=}{it:varname}{cmd:]}{cmd:,} {opt gen:erate(newvar)}
{c -(} {opt tot:als(spec)} {c |} {opt totalsf:ile(filename)} {c )-}
[{opt meth:od(rake|regress|post)} {opt eng:ine(stata|ipfraking)} {opt ll(#)} {opt ul(#)}
{opt iter:ate(#)} {opt tol:erance(#)} {opt force} {opt replace}]

{p 8 16 2}
{cmd:rtmweight} {cmd:trim} {it:varname} {ifin}{cmd:,} {opt gen:erate(newvar)} {opt rule(winsor|cap)}
[{opt pct(#)} {opt low:pct(#)} {opt cap(#)} {opt capm:ult(#)} {opt by(varlist)} {opt norescale} {opt id(varname)} {opt replace}]

{p 8 16 2}
{cmd:rtmweight} {cmd:household} {it:personweight} {ifin}{cmd:,} {opt hh:id(varname)} {opt gen:erate(popw hhw)}
[{opt psu:average(varname)} {opt str:ata(varname)} {opt tot:als(spec)} {opt totalsf:ile(filename)} {opt replace}]

{p 8 16 2}
{cmd:rtmweight} {cmd:report} {it:varlist} {ifin}
[{cmd:,} {opt tot:als(spec)} {opt by(varname)} {opt ex:cel(filename)} {opt docx(filename)} {opt gr:aph} {opt note:s} {opt id(varname)} {opt units}]

{pstd}
Dialogs: {dialog rtmweight_base}, {dialog rtmweight_nonresponse}, {dialog rtmweight_calibrate},
{dialog rtmweight_trim}, {dialog rtmweight_household}, {dialog rtmweight_report}; or {bf:User > RTM tools > Weights} after {helpb rtmtools_setup}.
No step uses R.


{marker description}{...}
{title:Description}

{pstd}
{cmd:rtmweight} builds the weights of a phone panel round in the order the guidelines recommend
(Himelein et al. 2020, pp. 10-11): design (base) weights, then the sample-based adjustment for
nonresponse or attrition, then trimming, then calibration to population totals, with a report
of every step. Each step writes a new weight variable, so every stage stays in the data
(UN 2008, p. 115), records its command and software version in the dataset's notes and
characteristics, and leaves its results in {cmd:r()}. Every statistical step runs through an
official Stata command or an established user-written one; the arithmetic steps follow the
formulas cited below. The commands carry out the design the task team chose; they do not
decide what a survey should represent.

{pstd}
Where a method default is a judgment, the source is cited and the alternative is a labeled
option. Where the foundational documents are silent (bounds on calibration weights), the
option is off unless the user sets it.


{marker base}{...}
{title:rtmweight base: design (base) weights}

{pstd}
Two ways to build the base weight, and one optional adjustment:

{phang}
{opt probability(varlist)} gives the inclusion probability of each sampling stage (for example
the EA's and the household's). The weight is the inverse of their product (UN 2008, section 6.3,
pp. 122-123: base weight = 1/p, with p the product of the stage probabilities). Each
probability must lie in (0, 1].

{phang}
{opt baseweight(varname)} takes the weights of the baseline survey the panel was drawn from.
With {opt subsample(varname)} (1 = in the phone sample, 0 = not), the baseline weights are
redistributed to the subsampled households so that their sum equals the baseline weight total,
within the {opt by(varlist)} groups if given (usually the strata). This is the "sums of weights
as cell totals" adjustment of Himelein et al. 2020 (pp. 10-11, 21) and the ratio adjustment
that preserves the original sum of weights in Ambel et al. 2021 (p. 10). A by() group with
baseline households but no subsampled household stops the command.

{phang}
{opt multiplicity(varname)} divides the weight by the number of phone numbers through which the
household could have been selected (Himelein et al. 2020, p. 11), a whole number of 1 or more.

{phang}
{opt generate(newvar)} names the weight; {opt replace} overwrites an existing variable.


{marker nonresponse}{...}
{title:rtmweight nonresponse: nonresponse and attrition adjustment}

{pstd}
{it:respvar} is 1 for the eligible sample members who were interviewed and 0 for those who were
not; every observation in the sample (after {it:if}/{it:in}) must be 0 or 1. Ineligible units are
excluded by the user beforehand. The command adjusts {opt weight(varname)}, the base weight
or the previous round's weight, and writes {opt generate(newvar)}: respondents carry the
adjusted weight, nonrespondents get 0. For a panel, run it once per round, adjusting the
previous round's weight for that round's attrition (Broccolini, Seitz and Azevedo 2017, pp. 7-11:
the L2T panel re-estimated attrition each round against the round before); keep each round's
weight as its own variable (cross-sectional and panel weight sets, Himelein et al. 2020, p. 11).

{phang}
{opt method(classes)} with {opt classes(varlist)}: weighting-class adjustment through
{helpb survwgt} {cmd:nonresponse} (Winter 2002): within each class the respondents' weights are
scaled so that they add to the base weights of all sample members in the class (UN 2008,
section 6.5, pp. 130-132; Himelein et al. 2020, p. 10). The command checks survwgt's result
against the formula. {opt mincell(#)} stops with a list when a class has fewer respondents;
collapse such classes first (for example with {helpb wgtcellcollapse} from the ipfraking package,
or by merging categories).

{phang}
{opt method(logit)} (the default when covariates() is given) or {opt method(probit)} with
{opt covariates(varlist)}: response-propensity adjustment. A logit or probit of {it:respvar} on
the covariates (factor variables allowed), the predicted propensity split into {opt ngroups(#)}
quantile groups (default 10, deciles), and each respondent's weight multiplied by 1 / (mean
propensity of its group). This is the recipe of Dabalen et al. 2016 (Box 2.2, p. 49), Himelein
et al. 2020 (Annex A2.3.1, p. 23, after Himelein 2014) and the L2T panel (Broccolini, Seitz and
Azevedo 2017, pp. 7-11, which used a probit with area, region, household size, dependency ratio,
a welfare indicator and the head's sex). Grouping the propensities protects against extreme
adjustments (Himelein et al. 2020, p. 10). The model is unweighted, as in Box 2.2;
{opt weightedmodel} fits it with the weights. {opt by(varlist)} fits separate models within
groups (for example regions). Covariates should be known for respondents and nonrespondents
alike (baseline characteristics; paradata only if they also relate to the outcomes, Himelein
et al. 2020, p. 12). Ambel et al. 2021 (p. 22) found non-contact, not refusal, to drive the
bias in four African phone surveys; the output shows response rates by group so that both
can be seen.

{phang}
{opt method(ebalance)} with {opt covariates(varlist)}: entropy balancing with the base weights
kept (Hainmueller 2012; Hainmueller and Xu 2013). The respondents' weights are raked so that
their weighted means of the covariates (and, with {opt moments(2)} or {opt moments(3)}, the
weighted means of x^2 and x^3 of the continuous covariates, that is their variances and
skewness) equal the weighted means of the whole eligible sample, the baseline's. Factor
variables ({cmd:i.var}) become indicators. The weights are computed by official {helpb svycal}
{cmd:rake} (the generalized raking of Deville, S{c a:}rndal and Sautory 1993), which gives the same
weights as {helpb ebalance}'s two-group form with {cmd:basewt()} and {cmd:wttreat} (verified on the
package's synthetic data: largest relative difference 4e-8); when ebalance is installed, the
command runs it as a cross-check and reports the difference ({cmd:r(ebalance_maxreldiff)};
{opt nocrosscheck} skips it). This is the method the L2 programs document for their rounds
(L2T 2023-, L2KGZ, L2Arm, L2Geo); it is program practice, not a guideline default. The output
lists every constraint with its target and achieved value. If the respondents cannot match
every moment the command stops: drop a covariate, use moments(1), or collapse categories.

{phang}
{opt method(ebalance_nobase)} with {opt covariates(varlist)}: the form of the L2PHL script of
January 2026 (program practice). {helpb ebalance} (SSC, required) balances the respondents to the
{it:unweighted} means of the whole sample with base weight 1, and the resulting factor is
multiplied into {opt weight()} afterwards. The design-weighted means after the multiplication are
not targeted, so this is not the same as method(ebalance); on the synthetic data the two sets
of weights differ by about 6 percent (CV of their ratio) although both hit the target means.
The output lists the unweighted targets and achieved means.

{phang}
{opt method(post)} with {opt cells(varlist)}, {opt cellfile(filename)} and {opt celltotal(varname)}
(default {cmd:total}): cell post-stratification to population totals, each round, the form of the
L2PHL scripts since March 2026 (program practice; the method is post-stratification, UN 2008,
section 6.6, pp. 134-135; Himelein et al. 2020, pp. 10-11). {it:cellfile} is a Stata dataset with
one row per cell: the cell variables and the total. The factor of a cell is its total divided by
the sum of the respondents' base weights in the cell, so the adjusted weights of each cell add
to the cell's total. A respondent in a cell without a total stops the command; a cell in the
file without a respondent is reported ({cmd:r(population_uncovered)}, {cmd:r(n_cells_empty)}): its
population is not represented. With the sample's own cell totals instead of population totals,
method(classes) is the same operation.

{pstd}
The output reports the unweighted and weighted response rates, the sum of weights before and
after (for classes they are equal; for propensity groups nearly so), the adjustment factors,
and a table by class, propensity group or cell ({cmd:r(groups)}). A factor below 1 marks a group
whose respondents are over-represented. The guidelines' sequence puts this sample-based
adjustment first and calibration second (Himelein et al. 2020, p. 10); the L2 programs that
balance each round to the baseline do the adjustment and the calibration in one step, and
rescale to strata population afterwards ({cmd:rtmweight calibrate, method(post)} on the strata).


{marker calibrate}{...}
{title:rtmweight calibrate: calibration to population totals}

{pstd}
Calibration adjusts the weights so that weighted totals of the calibration variables match
known population totals (Deville and S{c a:}rndal 1992). It is the last weighting step, after the
sample-based adjustment and any trimming (Himelein et al. 2020, pp. 10-11; Ambel et al. 2021,
p. 11), and it serves mostly to correct coverage, with a precision gain as a by-product
(Himelein et al. 2020, Annex A2.1, p. 21). Use totals from the census or from the frame survey,
of the same population and reference year (UN 2008, section 6.6).

{phang}
{it:varlist}: categorical calibration variables, written as {cmd:i.var} or bare names; with
{opt method(regress)}, {cmd:c.var} adds a continuous variable whose population total is given
as {cmd:1.var=total}. Interactions are not supported: build one combined variable first.

{phang}
{opt totals(spec)}: the population totals as {it:level}{cmd:.}{it:variable}{cmd:=}{it:total}
pairs for every category of every calibration variable, for example
{cmd:totals(1.region=14781 2.region=15345 3.region=14898 4.region=14807 0.urban=31458 1.urban=28373)},
or the name of a matrix in the format {helpb svycal} accepts (column names {cmd:_cons}
{cmd:1.region} ...). The categories of each variable must add to the same population size
(within 0.5%), every category present in the sample needs a total, and no total may name a
category absent from the sample; the command stops otherwise. The population size {cmd:_cons}
is taken from the totals. With {opt engine(ipfraking)}, {opt totals()} may instead name control
matrices in {helpb ipfraking}'s format.

{phang}
{opt totalsfile(filename)}: a Stata dataset with the variables {cmd:variable} (string),
{cmd:level} (numeric) and {cmd:total}, one row per category.

{phang}
{opt method(rake)} (default): raking-ratio calibration to the margins (Deville, S{c a:}rndal and
Sautory 1993; Himelein et al. 2020, Annex A2.2, p. 22). {opt method(regress)}: linear (GREG)
calibration; with {opt ll(#)} and {opt ul(#)} the weight ratios are truncated to that range
(truncated linear calibration). {opt method(post)}: post-stratification to the cells of one
variable (UN 2008, pp. 134-135; Himelein et al. 2020, Annex A2.1).

{phang}
{opt engine(stata)} (default) uses official {helpb svycal} (Stata 18). The command also records the
calibration model and totals in the dataset ({cmd:char _dta[rtm_cal_svyset]}) so that
{helpb rtmest} declares it with {cmd:svyset ..., rake()} or {cmd:regress()} and the variance of
later estimates accounts for the calibration ([SVY] svyset, Stata 15.1 or later).

{phang}
{opt engine(ipfraking)} uses {helpb ipfraking} (Kolenikov 2014, 2019) for raking; {opt ll()} and
{opt ul()} become its {cmd:trimlorel()} and {cmd:trimhirel()} limits on the adjustment factor,
applied during the iterations (approximate bounds; the totals may then not be met exactly, and
the output says so). The control matrices are built from the pairs.

{phang}
{opt iterate(#)}, {opt tolerance(#)} and {opt force} are passed to svycal regress or ipfraking.
The bounded logit distance (Deville, S{c a:}rndal and Sautory 1993) is available in Stata through
{helpb sreweight} (Pacifico 2014, SSC), run by hand on the same totals; trimming that preserves
the calibration constraints is not offered: trim before calibrating, as the guidelines order
the steps. No step of this command uses R.

{pstd}
No foundational document gives bounds on calibration weights, so bounds are off unless set.
If the totals cannot be met within the bounds, the engines return the best approximation
(svycal: with {opt force}; ipfraking: with a warning), and the command's table of
target against achieved totals shows the gap. The output also gives the range of the g-weights
(calibrated weight / input weight) and Kish's 1 + CV^2 before and after.


{marker trim}{...}
{title:rtmweight trim: trimming extreme weights}

{pstd}
Trimming reduces the variance that a few very large weights add, at the cost of a small bias
(UN 2008, section 6.8, pp. 136-138, which asks that trimming be justified by the mean squared
error). It is applied before calibration (Himelein et al. 2020, p. 11; Ambel et al. 2021, p. 11).
After trimming, the weights are rescaled within {opt by()} groups so that their sum equals the
original sum (UN 2008, p. 137) unless {opt norescale} is given.

{phang}
{opt rule(winsor)}: weights above the {opt pct(#)} percentile are set to that percentile's value
(default 98: Himelein et al. 2020, p. 11, replace the weights in the 99th and 100th percentiles
with the highest value of the 98th); {opt lowpct(#)} also raises weights below that lower
percentile (Ambel et al. 2021, p. 11, trimmed at the 2nd and 98th percentiles).

{phang}
{opt rule(cap)}: weights above {opt cap(#)}, or above {opt capmult(#)} times the median, are set to
that bound (UN 2008, pp. 136-138: a stratum-specific upper bound).

{pstd}
The output counts the weights changed and gives Kish's 1 + CV^2 before and after. With
{opt id(varname)}, the export's {cmd:flags} table names every unit whose weight was changed.


{marker household}{...}
{title:rtmweight household: household weights from person weights}

{pstd}
The L2PHL scripts weight persons (cell post-stratification by stratum, sex and age group) and
derive the household weights from them. This step reproduces that derivation as a labeled
choice; no foundational document prescribes it, and the help says what it changes. The data in
memory are the person-level file (one row per member) with the household identifier
{opt hhid(varname)} and the person weight {it:personweight}. {opt generate(popw hhw)} names two
new variables: the {it:population weight} of the household, the sum of its members' person
weights (the persons the household stands for), and the {it:household weight}, their mean.
{opt psuaverage(varname)} replaces the household weight by its mean over the households of the
PSU (one value per PSU, as in L2PHL). {opt strata(varname)} with {opt totals(spec)}
({it:level}{cmd:.}{it:strata}{cmd:=}{it:total} pairs) or {opt totalsfile(filename)} (rows with
{cmd:variable} equal to the strata name) rescales the household weights so that they add to the
census household totals of each stratum. After the PSU average or the rescaling, the population
weight no longer equals the household weight times household size; the output shows the range
of that ratio and both weights are kept.


{marker report}{...}
{title:rtmweight report: the weighting report}

{pstd}
{it:varlist} lists the weight variables in the order of the steps. The report gives, for each
weight, N, sum, mean, min, median, max, CV and Kish's 1 + CV^2 (the design effect from
unequal weights; Kish 1992; UN 2008, p. 136); the adjustment factors between consecutive
stages and their sum ratios; with {opt totals(spec)}, the totals of the last weight against the
targets; with {opt by(varname)}, the last weight by group; with {opt graph}, the weight densities
by stage; with {opt notes}, the rtmweight steps recorded in the dataset. {opt excel(filename)}
writes the tables with {helpb putexcel}; {opt docx(filename)} writes a Word method note with
{helpb putdocx_intro:putdocx} that lists every recorded step, its command, its software stamp and its source,
ready for the survey report (UN 2008, ch. 5; CWM 2021, section 8.2). With {opt units} (and
{opt id(varname)} for the identifier), the export also gets a {cmd:weight_units} table with every
weight stage per unit (identifiers only; up to 200,000 units).


{marker export}{...}
{title:The export: Excel display and dashboard}

{pstd}
Every subcommand writes its run into a folder under the export folder ({cmd:rtm_exports} in the
working folder, or the folder set with {helpb rtmtools_dashboard}{cmd:, dir()}): {cmd:manifest.json}
and {cmd:manifest.csv} (what ran, when, with which settings and their sources, the key results of
{cmd:r()}), one CSV per table ({cmd:weight_stages}: N, sum, percentiles, mean, CV and Kish's
1 + CV^2 of every weight stage; {cmd:response_classes}; {cmd:calibration_fit}; {cmd:weight_groups};
{cmd:flags}; {cmd:weight_units}), the Excel workbook {cmd:rtm_display.xlsx} (the package's display
template with the same tables filled in: its sheets show them with lookups and charts and
compute nothing), and one line in {cmd:rtm_exports.js}, the index the dashboard page reads.
Identifiers only are exported, never names, addresses or phone numbers, and nothing leaves the
computer. {cmd:rtmtools_dashboard, off} switches the export off for the session.


{marker examples}{...}
{title:Examples}

{pstd}
The sample data are synthetic (no real household). Get them with {cmd:net get rtmtools} into
the current folder. {cmd:rtm_baseline.dta} is a two-stage baseline sample (100 EAs, 12
households each) with exact design weights; {cmd:rtm_round1.dta} holds the phone panel with
round-1 and round-2 response indicators; {cmd:rtm_totals_long.dta} holds population totals by
region and by urban/rural.

{phang2}{cmd:. use rtm_baseline, clear}{p_end}
{phang2}{cmd:. merge 1:1 hhid using rtm_round1, keepusing(responded_r1 responded_r2 skipmeal_r1) nogenerate}{p_end}

{pstd}Base weights: the baseline weights redistributed to the phone owners within strata (run on the
full baseline, before dropping the households without a phone){p_end}
{phang2}{cmd:. rtmweight base, baseweight(w_base) subsample(phone) by(stratum) generate(w0)}{p_end}
{phang2}{cmd:. keep if phone == 1}{p_end}

{pstd}Round-1 nonresponse: a logit propensity in deciles{p_end}
{phang2}{cmd:. rtmweight nonresponse responded_r1, weight(w0) method(logit) covariates(urban i.educ head_age assets hhsize) generate(w1)}{p_end}

{pstd}The same with weighting classes{p_end}
{phang2}{cmd:. rtmweight nonresponse responded_r1, weight(w0) method(classes) classes(region urban) generate(w1c)}{p_end}

{pstd}Trim the respondents' weights at the 98th percentile, then calibrate to region and urban totals{p_end}
{phang2}{cmd:. rtmweight trim w1 if responded_r1, generate(w1t) rule(winsor) pct(98)}{p_end}
{phang2}{cmd:. rtmweight calibrate i.region i.urban [pw=w1t] if responded_r1, generate(w2) totalsfile(rtm_totals_long.dta)}{p_end}

{pstd}The same totals typed, with bounded linear calibration{p_end}
{phang2}{cmd:. rtmweight calibrate i.region i.urban [pw=w1t] if responded_r1, generate(w2r) method(regress) ll(0.7) ul(1.5) totals(1.region=14781 2.region=15345 3.region=14898 4.region=14807 0.urban=31458 1.urban=28373)}{p_end}

{pstd}Entropy balancing to the baseline's weighted means (the L2 programs' round weights), with the ebalance cross-check{p_end}
{phang2}{cmd:. rtmweight nonresponse responded_r1, weight(w0) method(ebalance) covariates(urban i.educ head_age assets hhsize) generate(w1e)}{p_end}

{pstd}The L2PHL forms: balancing without base weights, and cell post-stratification of persons to census cells, then household weights{p_end}
{phang2}{cmd:. rtmweight nonresponse responded_r1, weight(w0) method(ebalance_nobase) covariates(hhsize i.region) generate(w1n)}{p_end}
{phang2}{cmd:. use rtm_persons, clear}{p_end}
{phang2}{cmd:. generate byte responded = 1}{p_end}
{phang2}{cmd:. rtmweight nonresponse responded, weight(indw) method(post) cells(region urban female age_grp) cellfile(rtm_totals_persons.dta) celltotal(N_persons) generate(indw_post)}{p_end}
{phang2}{cmd:. rtmweight household indw_post, hhid(hhid) generate(popw hhw) psuaverage(psu)}{p_end}

{pstd}Round 2: adjust the round-1 weight for attrition among round-1 respondents{p_end}
{phang2}{cmd:. rtmweight nonresponse responded_r2 if responded_r1, weight(w2) method(logit) covariates(urban i.educ head_age hhsize) generate(w3)}{p_end}

{pstd}Report{p_end}
{phang2}{cmd:. rtmweight report w0 w1 w1t w2 if responded_r1, totals(1.region=14781 2.region=15345 3.region=14898 4.region=14807 0.urban=31458 1.urban=28373) by(region) graph notes excel(weights.xlsx) docx(weighting_note.docx)}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
All subcommands store {cmd:r(cmdline)}, {cmd:r(generate)} and the weight summary {cmd:r(N)},
{cmd:r(sum)}, {cmd:r(cv)}, {cmd:r(kish)}, and write the command and a stamp (package version,
Stata version, date) to {cmd:char _dta[rtm_}{it:step}{cmd:]}, {cmd:char _dta[rtm_}{it:step}{cmd:_stamp]}
and {cmd:notes}. Each generated weight also carries its own command and stamp as variable
characteristics ({cmd:char} {it:newvar}{cmd:[rtm_cmd]}, {cmd:[rtm_stamp]}, {cmd:[rtm_step]}), which
{cmd:rtmweight report} lists for the weights in its {it:varlist}; {cmd:char list} shows them.

{pstd}{cmd:base}: {cmd:r(factor_min)}, {cmd:r(factor_max)}, {cmd:r(sum_baseline)} (with subsample()), {cmd:r(mode)}.{p_end}
{pstd}{cmd:nonresponse}: {cmd:r(N_sample)}, {cmd:r(N_resp)}, {cmd:r(rr_unweighted)}, {cmd:r(rr_weighted)}, {cmd:r(sum_base)},
{cmd:r(sum_adj)}, {cmd:r(factor_min)}, {cmd:r(factor_p50)}, {cmd:r(factor_max)}, {cmd:r(converged)} and {cmd:r(pseudo_r2)}
(propensity), {cmd:r(max_rel_diff)}, {cmd:r(n_constraints)} and {cmd:r(ebalance_maxreldiff)} (ebalance),
{cmd:r(population_uncovered)} and {cmd:r(n_cells_empty)} (post), {cmd:r(method)}, matrix {cmd:r(groups)} (sample size, respondents, response rate and factor by group).{p_end}
{pstd}{cmd:household}: {cmd:r(N_hh)}, {cmd:r(sum_pop)}, {cmd:r(sum_hh)}, {cmd:r(ratio_min)}, {cmd:r(ratio_max)}, {cmd:r(kish_hh)}, {cmd:r(cv_hh)}.{p_end}
{pstd}{cmd:calibrate}: {cmd:r(N_pop)}, {cmd:r(g_min)}, {cmd:r(g_p50)}, {cmd:r(g_max)}, {cmd:r(max_rel_diff)}, {cmd:r(kish_before)},
{cmd:r(kish_after)}, {cmd:r(sum_before)}, {cmd:r(sum_after)}, {cmd:r(converged)} (ipfraking), {cmd:r(method)}, {cmd:r(engine)},
{cmd:r(calvars)}; and {cmd:char _dta[rtm_cal_svyset]} for rtmest.{p_end}
{pstd}{cmd:trim}: {cmd:r(n_trimmed_high)}, {cmd:r(n_trimmed_low)}, {cmd:r(kish_before)}, {cmd:r(kish_after)}, {cmd:r(rule)}.{p_end}
{pstd}{cmd:report}: matrices {cmd:r(summary)}, {cmd:r(factors)}, {cmd:r(totals)}; {cmd:r(max_rel_diff)}; {cmd:r(steps)}.{p_end}


{marker limits}{...}
{title:Limits}

{pstd}
The commands do not decide the design: which covariates predict response, which totals to
calibrate to, and whether to trim are the task team's choices, to be recorded in the survey
report. The propensity method cannot remove bias from nonresponse related to the outcomes
beyond what the covariates capture (Gourlay et al. 2026, p. 24, found it reduced bias at the
household level more than at the individual level). Bounds and trimming trade bias for variance
without a cited default. {cmd:svycal} is part of Stata 18; on Stata 16 and 17, use
{opt engine(ipfraking)} for calibration and method(classes), (probit) or (ebalance_nobase) for the
adjustment, and rtmest then treats the calibrated weights as fixed. Interactions among
calibration variables need a combined variable. The entropy-balancing methods and the cell
post-stratification are the L2 programs' practice, offered as labeled choices; the guidelines'
default remains the propensity adjustment followed by calibration.


{marker references}{...}
{title:References}

{phang}Ambel, A., K. McGee, and A. Tsegay. 2021. Reducing Bias in Phone Survey Samples:
Effectiveness of Reweighting Techniques Using Face-to-Face Surveys as Frames in Four African
Countries. Policy Research Working Paper 9676. World Bank.{p_end}
{phang}Broccolini, C., W. Seitz, and J. P. Azevedo. 2017. Listening to Tajikistan: Household Survey. Background, Implementation, and Methods. World Bank.{p_end}
{phang}Dabalen, A., A. Etang, J. Hoogeveen, E. Mushi, Y. Schipper, and J. von Engelhardt. 2016.
Mobile Phone Panel Surveys in Developing Countries: A Practical Guide for Microdata Collection.
World Bank.{p_end}
{phang}Deville, J.-C., and C.-E. S{c a:}rndal. 1992. Calibration estimators in survey sampling. Journal of the American Statistical Association 87: 376-382.{p_end}
{phang}Deville, J.-C., C.-E. S{c a:}rndal, and O. Sautory. 1993. Generalized raking procedures in survey sampling. Journal of the American Statistical Association 88: 1013-1020.{p_end}
{phang}Gourlay, S., A. Ambel, P. Wollburg, I. Yacoubou Djima, A. Palacios-Lopez, T. Kilic, and K.
McGee. 2026. Six Years of High-Frequency Phone Surveys: Lessons from Sub-Saharan Africa. Policy
Research Working Paper 11435. World Bank.{p_end}
{phang}Hainmueller, J. 2012. Entropy balancing for causal effects: A multivariate reweighting method to produce balanced samples in observational studies. Political Analysis 20(1): 25-46.{p_end}
{phang}Hainmueller, J., and Y. Xu. 2013. ebalance: A Stata package for entropy balancing. Journal of Statistical Software 54(7).{p_end}
{phang}Himelein, K. 2014. Weight calculations for panel surveys with subsampling and split-off tracking. Statistics and Public Policy 1(1): 40-45.{p_end}
{phang}Himelein, K., S. Eckman, J. Kastelic, K. McGee, M. Wild, and N. Yoshida. 2020. High Frequency
Mobile Phone Surveys of Households to Assess the Impacts of COVID-19, Vol. 2: Guidelines on Sampling
Design. World Bank.{p_end}
{phang}Kish, L. 1992. Weighting for unequal Pi. Journal of Official Statistics 8: 183-200.{p_end}
{phang}Kolenikov, S. 2014. Calibrating survey data using iterative proportional fitting (raking).
Stata Journal 14(1): 22-59. 2019. Updates to the ipfraking ecosystem. Stata Journal 19(1):
143-184.{p_end}
{phang}Oseni, G., A. Palacios-Lopez, H. K. Mugera, and J. Durazo. 2021. Capturing What Matters:
Essential Guidelines for Designing Household Surveys. 2nd ed. LSMS Guidebook. World Bank. (CWM
2021){p_end}
{phang}United Nations. 2008. Designing Household Survey Samples: Practical Guidelines. Studies in Methods, Series F No. 98. New York. (UN 2008){p_end}
{phang}Pacifico, D. 2014. sreweight: A Stata command to reweight survey data to external totals. Stata Journal 14(1): 4-21.{p_end}
{phang}Winter, N. 2002 (revised 2018). SURVWGT: Stata module to create and manipulate survey weights. SSC S427503.{p_end}


{title:Author}

{pstd}
rtmtools is developed for the Real-Time Monitoring Survey Handbook task team (World Bank).
Report problems with the output of {cmd:rtmtools_setup, check} and a do-file that reproduces them.
{p_end}
