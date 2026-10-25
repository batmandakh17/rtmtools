{smcl}
{* *! version 0.5.0  25oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmweight" "help rtmweight"}{...}
{vieweralsosee "gsample" "help gsample"}{...}
{vieweralsosee "[PSS] power" "help power"}{...}
{viewerjumpto "Syntax" "rtmsample##syntax"}{...}
{viewerjumpto "Description" "rtmsample##description"}{...}
{viewerjumpto "size" "rtmsample##size"}{...}
{viewerjumpto "allocate" "rtmsample##allocate"}{...}
{viewerjumpto "draw" "rtmsample##draw"}{...}
{viewerjumpto "Examples" "rtmsample##examples"}{...}
{viewerjumpto "Stored results" "rtmsample##results"}{...}
{viewerjumpto "Limits" "rtmsample##limits"}{...}
{viewerjumpto "References" "rtmsample##references"}{...}
{title:Title}

{phang}
{bf:rtmsample} {hline 2} Sample size per domain, allocation across strata, and probability draws from a frame


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmsample} {cmd:size}{cmd:,} {c -(} {opt p(#)} {c |} {opt mean(#)} {opt sd(#)} {c )-}
[{opt marg:in(#)} {opt rel:margin(#)} {opt lev:el(#)} {opt deff(#)} {opt nonr:esponse(#)}
{opt share(#)} {opt hh:size(#)} {opt attr:ition(#)} {opt round:s(#)} {opt first:loss(#)} {opt dom:ains(#)}
{opt change(#)} {opt pow:er(#)} {opt ones:ided}]

{p 8 16 2}
{cmd:rtmsample} {cmd:allocate} {ifin}{cmd:,} {opt str:ata(varlist)} {opt n(#)}
[{opt size(varname)} {opt meth:od(proportional|equal|neyman|power)} {opt sd(varname)} {opt pow:er(#)}
{opt min(#)} {opt max(#)} {opt units(varname)} {opt gen:erate(newvar)} {opt replace} {opt noround}]

{p 8 16 2}
{cmd:rtmsample} {cmd:draw} {ifin}{cmd:,} {opt n(#|varname)} {opt gen:erate(stub)}
[{opt str:ata(varlist)} {opt meth:od(srs|systematic|pps|ppssys)} {opt pps(varname)} {opt sort(varlist)}
{opt reserve(#|varname|all)} {opt seed(#)} {opt id(varlist)} {opt replace}]

{p 8 16 2}
{cmd:rtmsample} {cmd:grid} {ifin}{cmd:,} {opt n(#|varname)} {opt gen:erate(prefix)} {opt xy(xvar yvar)}
[{opt str:ata(varlist)} {opt pps(varname)} {opt bands(#)} {opt band:width(#)} {opt reserve(#|all)} {opt seed(#)} {opt id(varlist)} {opt replace}]

{p 8 16 2}
{cmd:rtmsample} {cmd:rdd}{cmd:,} {opt pre:fixes(numlist)} {opt n(numlist)}
[{opt dig:its(#)} {opt seed(#)} {opt sav:ing(filename)} {opt replace} {opt clear}]

{pstd}
Dialogs: {dialog rtmsample_size}, {dialog rtmsample_allocate}, {dialog rtmsample_draw}, {dialog rtmsample_grid}; or
{bf:User > RTM tools > Sample} after {helpb rtmtools_setup}. {cmd:grid} runs R (spsurvey) in the
background; the other subcommands are Stata only. Page numbers below are those of the
PDF files of the cited documents; paragraph and formula numbers are the documents' own.


{marker description}{...}
{title:Description}

{pstd}
{cmd:rtmsample} covers the three steps of a sample design once the task team has decided what the
survey must measure and for which domains: how many households each domain needs
({cmd:size}), how a total is spread across strata ({cmd:allocate}), and the probability selection
of units from a frame with their inclusion probabilities and design weights ({cmd:draw}). The
size and allocation steps are arithmetic from the formulas of UN 2008 and HFPS Vol. 2, written out
below with their sources; the change-between-rounds case runs Stata's official {helpb power}
commands. The draws run through {helpb gsample} (Jann 2006) for simple random and PPS selection,
and through the systematic selection procedure of UN 2008 and Grosh and Mu{c n~}oz 1996 on the sorted
frame. The commands do not choose the design: the indicator, its precision, the domains, the
strata and the method are the task team's decisions (Chapter 1 and Section 2.7 of the handbook).


{marker size}{...}
{title:rtmsample size: sample size per domain}

{pstd}
For the {it:level} of an indicator (the default), the number of completed interviews in a simple
random sample is

{p 12 16 2}n_0 = z^2 p(1-p) / e^2 for a proportion p, or n_0 = z^2 s^2 / e^2 for a mean with
standard deviation s,

{pstd}
where z is the normal quantile for the confidence level ({opt level()}, default 95, z = 1.96) and e
is the margin of error, the half-width of the confidence interval: {opt margin(#)} gives it in the
indicator's units; {opt relmargin(#)} gives it as a fraction of the estimate (e = {it:relmargin} x
p), and is the default with 0.10, the 10 percent relative margin UN 2008 recommends (paras 37-38,
p. 48; para 66, p. 55; HFPS Vol. 2, section 2.1.1, p. 3, for the same formula). Then, following
UN 2008 formula 3.7 (para 59, p. 53):

{p 12 16 2}x {opt deff(#)}, the design effect (UN 2008 para 60: 2.0 unless a previous survey says
otherwise; a list-based phone sample without clustering is close to 1, HFPS Vol. 2 pp. 3-4);{p_end}
{p 12 16 2}/ ({opt share(#)} x {opt hhsize(#)}) to turn persons in the target group into households
when the indicator is person-level (UN 2008: p, the target group's share of the population, and
the average household size; both 1 for a household indicator);{p_end}
{p 12 16 2}x {opt nonresponse(#)}, the multiplier for anticipated nonresponse (UN 2008 paras 50-51
and 60: 1.1 for 10 percent);{p_end}
{p 12 16 2}x the attrition reserve for a panel of {opt rounds(#)} rounds with {opt attrition(#)}
per round: 1/(1-a)^R, or 1/((1-L)(1-a)^(R-1)) when {opt firstloss(#)} gives the share lost between
the baseline and round 1 (MPPS 2016, p. 45: 1,000 households over 24 rounds at 1.5 percent need
1,438 at the start, or 1,573 with a 10 percent first-round loss);{p_end}
{p 12 16 2}rounded up, x {opt domains(#)}, the number of domains that each need this reliability
(UN 2008 paras 39-40, p. 48; MPPS 2016 p. 45).

{pstd}
For a {it:change} between rounds or groups, {opt change(#)} (signed, in the indicator's units) with
{opt power(#)} (default 0.8) runs {cmd:power twoproportions} p, p+change or {cmd:power twomeans}
with sd, two-sided unless {opt onesided}; n_0 is the size of one group or round (HFPS Vol. 2,
section 2.1.2, p. 4, whose Table 1 this reproduces: 388 per group for a change of 10 points from
50 percent at 80 percent power, 519 at 90 percent), and the adjustments above follow.

{pstd}
Note on UN 2008's worked examples: paragraph 60 states a default design effect of 2.0, but the
reduced formula 3.8 (p. 53) carries 1.2, and the examples in paras 61-63 (1,170; 10,704; about
1,600 households) follow 1.2. {cmd:rtmsample size, deff(1.2)} reproduces them; with deff(2) the
same inputs give larger samples.


{marker allocate}{...}
{title:rtmsample allocate: allocation across strata}

{pstd}
The data in memory are either the frame units (areas or households, one row each) with the strata
variables, or a stratum table with one row per stratum. N_h is the sum of {opt size(varname)}
within the stratum (households in the census, for an area frame), or the number of rows when
size() is not given. {opt n(#)} is the total to allocate.

{phang}
{opt method(proportional)} (default): n_h = n N_h / N, a self-weighting sample within the strata
(UN 2008 paras 68-70, pp. 55-56; the starting point of the LSMS designs, Grosh and Mu{c n~}oz 1996
p. 78, step 2).

{phang}
{opt method(equal)}: n_h = n / H, for strata that are domains needing equal reliability (UN 2008
para 69, p. 56; para 41, p. 49).

{phang}
{opt method(neyman)}: n_h = n N_h S_h / sum_k N_k S_k, with S_h the within-stratum standard
deviation of the key indicator from {opt sd(varname)}: a variable constant within strata holding
S_h, or a unit-level variable whose standard deviation within each stratum is used (Neyman 1934;
Cochran 1977, section 5.5; HFPS Vol. 2, p. 5).

{phang}
{opt method(power)}: n_h = n N_h^q / sum_k N_k^q with q from {opt power(#)} (default 0.5), the
compromise between proportional (q = 1) and equal (q = 0) allocation of Bankier 1988.

{phang}
{opt min(#)} and {opt max(#)} hold strata at a bound and re-allocate the remainder among the others
in proportion to their unbounded allocation, repeated until no stratum crosses a bound; this is the
LSMS practice of raising small domains to 300-400 households and lowering others (Grosh and
Mu{c n~}oz 1996, pp. 78-79, step 3). A stratum can never receive more than its number of units.
{opt units(varname)} gives that number for a stratum table (otherwise the rows are counted).

{phang}
Rounding keeps the total: whole parts first, then the remaining units go to the strata with the
largest fractional parts; {opt noround} keeps the exact values. {opt generate(newvar)} writes n_h to
every row of the stratum, ready for {cmd:rtmsample draw, n(newvar)}.

{pstd}
The table shows, per stratum, N_h, its share, the exact and rounded n_h, N_h/n_h (the design
weight if n_h units are drawn with equal probability from N_h units) and n_h/N_h. UN 2008 para 75
(p. 57) asks for at least two units per stratum so that sampling errors can be estimated.


{marker draw}{...}
{title:rtmsample draw: probability selection from the frame}

{pstd}
The data in memory are the frame: one row per unit (areas at the first stage, households or
dwellings within selected areas at the second). {opt n(#|varname)} is the number to select in each
stratum of {opt strata(varlist)} (a variable constant within strata, for example the one written by
{cmd:rtmsample allocate}), or in the whole frame without strata. The command sets the random
number seed ({opt seed(#)}; when it is not given, a seed is drawn, reported and recorded, so that
the draw can be repeated exactly) and writes:

{p 12 16 2}{it:stub}{cmd:_sel}: 1 selected, 0 in the frame and not selected, missing outside {it:if}/{it:in};{p_end}
{p 12 16 2}{it:stub}{cmd:_pi}: the inclusion probability of every frame unit;{p_end}
{p 12 16 2}{it:stub}{cmd:_w}: the design weight 1/pi of the selected units, for {cmd:rtmweight base, probability()};{p_end}
{p 12 16 2}{it:stub}{cmd:_order}: the selection order within the stratum;{p_end}
{p 12 16 2}{it:stub}{cmd:_reserve}: the rank of a reserve unit (0 otherwise);{p_end}
{p 12 16 2}{it:stub}{cmd:_cert}: 1 for a unit taken with certainty (PPS methods).

{phang}
{opt method(srs)} (default without pps()): simple random sampling without replacement within
strata through {helpb gsample}; pi = n_h / N_h.

{phang}
{opt method(systematic)}: equal-probability systematic selection on the frame sorted by
{opt sort(varlist)} within strata (implicit stratification: UN 2008 paras 77-79, pp. 57-58;
Grosh and Mu{c n~}oz 1996 p. 84): interval I = N_h/n_h, random start in (0, I], every I-th unit;
pi = n_h / N_h.

{phang}
{opt method(ppssys)} (default with pps()): systematic selection with probability proportional to
the measure of size {opt pps(varname)} on the sorted frame, the first-stage procedure UN 2008
recommends (para 180, p. 83; paras 78 and 108, pp. 58 and 66) and Grosh and Mu{c n~}oz 1996 describe
step by step (pp. 81-83): cumulate the sizes, interval I = sum of sizes / n_h, random start in
(0, I], select the unit whose cumulative size first reaches each of start, start + I, start + 2I, ...;
pi = n_h x size / sum of sizes. A unit whose size reaches I would be selected more than once (UN 2008
para 101, p. 65, accepts this); the command takes such units with certainty (pi = 1), removes them
and repeats with the rest, so every unit is selected at most once. Sorting the frame geographically
before the draw is the implicit stratification both documents recommend; {opt sort()} does it
within strata, and without it the frame's current order is used.

{phang}
{opt method(pps)}: PPS without replacement by random systematic selection in {helpb gsample}
(Hartley and Rao 1962; Brewer and Hanif 1983, procedure 2): the same as ppssys after a random
ordering, so pi = n_h x size / sum of sizes as well, with the same certainty treatment.

{phang}
{opt reserve(#|varname|all)} draws, after the main sample and with the same method, that many further
units per stratum from those not selected, ranked in {it:stub}{cmd:_reserve} in the order they
should be used. They are pre-designated replacements (Grosh and Mu{c n~}oz 1996 pp. 93-94). UN 2008
warns that substituting a unit that cannot be interviewed is a biased procedure (paras 172, 178-179,
pp. 81-83); Capturing What Matters (p. 18) puts oversampling and replacements as the two options.
Reserve units have no inclusion probability or weight; if one is used, it inherits the role of the
unit it replaces, and the survey report should say so.

{phang}
{opt id(varlist)} is checked for duplicates; {opt replace} overwrites existing output variables.
Two-stage designs run the command twice: on the area frame, then on the listing of the selected
areas with {opt strata(area id)} and a fixed take; {cmd:rtmweight base, probability(pi_area pi_hh)}
combines the two probabilities (UN 2008 formula 3.16, p. 66).

{pstd}
The output table gives, per stratum, the units, the sum of sizes, the numbers selected, with
certainty and in reserve, the range of pi, the sum of the design weights (equal to the units under
equal probabilities) and the Horvitz-Thompson estimate of the stratum's size (exactly the stratum's
size under PPS), as checks.


{marker grid}{...}
{title:rtmsample grid: spatially spread draw from a grid frame (no R)}

{pstd}
The frame in memory holds cells or points with coordinates {opt xy(xvar yvar)} (a projected
system, metres), a measure of size (optional) and strata (optional), for example the cell frame
of {helpb rtmframe} {cmd:grid}, which carries them as {cmd:x} and {cmd:y} ({cmd:xy(x y)}). The command puts the units of each stratum in {it:serpentine
geographic order} (horizontal bands of the y coordinate, {opt bands(#)} of them or of height
{opt bandwidth(#)}, by default about the square root of the units; x ascending in one band and
descending in the next) and takes a systematic sample along that order: equal probabilities, or
probability proportional to {opt pps(varname)}. This is the geographic implicit stratification of
UN 2008 (paras 77-79: sort the frame geographically, select systematically) applied to cells; it
spreads the sample over the territory. {opt reserve(#|all)} marks the next units in the same order
as ordered replacements. The draw itself is {cmd:rtmsample draw} with {cmd:method(systematic)} or
{cmd:method(ppssys)} sorted by the serpentine key, so the inclusion probabilities, weights, order,
reserve ranks, seed and stored results are those of {cmd:rtmsample draw}.

{pstd}
{bf:What this is not.} It is not the GRTS design (Stevens and Olsen 2004; spsurvey, Dumelle et al.
2023), which version 0.4.0 ran through R. GRTS orders the units by a reverse hierarchical
address so that any contiguous subset of the ordered sample is itself spatially balanced (so
replacements taken in order keep the balance) and has a local neighbourhood variance estimator;
the serpentine order balances along the bands, keeps spread only approximately when units are
replaced, and leaves the variance to the ordinary design-based estimator with the implicit
stratification unrecognised (conservative). None of the L2 programs has used a grid frame or a
spatially balanced draw; the stand-in was chosen so that the package needs no R.


{marker rdd}{...}
{title:rtmsample rdd: random digit dialing sample}

{pstd}
Telephone numbers generated at random from operator prefixes, the frame of the phone surveys
without a baseline (L2Som; L2Arm and L2Geo from their second round): each prefix is a stratum of
the number space, {opt n(numlist)} numbers per prefix (one number for all, or one per prefix),
{opt digits(#)} random digits after the prefix (default 7), no number twice, and a recorded seed.
The selection probability of a number within its prefix is n / 10^digits and the design weight
its inverse; whether a number is active, a household, and eligible is learned by the call centre,
and every number's outcome must be kept for the response adjustment (HFPS Vol. 2 pp. 7-8). A
household reachable on several numbers needs {cmd:rtmweight base, multiplicity()} (HFPS Vol. 2
p. 21). The numbers replace the data in memory ({opt clear} when the data have unsaved changes)
and can be saved with {opt saving()}; they are never exported: the run's export holds the counts
per prefix only. Source: HFPS Vol. 2 pp. 7-8; Waksberg 1978.


{marker export}{...}
{title:The export}

{pstd}
Every subcommand writes its run into the export folder (see {helpb rtmtools_dashboard}): {cmd:size}
the {cmd:size} table (one row per domain and for the total); {cmd:allocate} the {cmd:allocation}
table (one row per stratum: units, size, share, planned, bounds, final, sampling fraction);
{cmd:draw} and {cmd:grid} the {cmd:draw_summary} table (one row per stratum) and the {cmd:selection}
table (one row per frame unit: identifier from {opt id()}, stratum, size, order, selected, reserve
rank, probability, weight, and the coordinates given with {opt xy()}, which the dashboard maps);
{cmd:rdd} the {cmd:draw_summary} table per prefix. The Excel workbook and the dashboard display them.


{marker examples}{...}
{title:Examples}

{pstd}Sample size: UN 2008's example B (unemployment, 10 percent of a labour force that is 65
percent of the population, 6 persons per household), and HFPS Vol. 2 Table 1{p_end}
{phang2}{cmd:. rtmsample size, p(0.1) share(0.65) hhsize(6) deff(1.2)}{p_end}
{phang2}{cmd:. rtmsample size, p(0.5) change(-0.10) power(0.8) deff(1) nonresponse(1)}{p_end}

{pstd}A phone panel: 500 completed interviews per domain in each of 24 rounds, 1.5 percent
attrition per round, 10 percent lost at the first call, two domains{p_end}
{phang2}{cmd:. rtmsample size, p(0.5) margin(0.044) deff(1) nonresponse(1) attrition(0.015) rounds(24) firstloss(0.10) domains(2)}{p_end}

{pstd}Allocation of 100 enumeration areas across the eight strata of the synthetic frame, in
proportion to households, with at least 10 and at most 16 per stratum{p_end}
{phang2}{cmd:. use rtm_frame, clear}{p_end}
{phang2}{cmd:. rtmsample allocate, strata(stratum) n(100) size(ea_size_census) min(10) max(16) generate(n_ea)}{p_end}

{pstd}First stage: systematic PPS within strata, sorted geographically, with two reserve areas per
stratum; then the second stage, 12 households in each selected area from the household list{p_end}
{phang2}{cmd:. rtmsample draw, n(n_ea) strata(stratum) pps(ea_size_census) sort(region urban ea_id) reserve(2) seed(20261024) generate(ea)}{p_end}
{phang2}{cmd:. keep if ea_sel == 1}{p_end}
{phang2}{cmd:. keep ea_id ea_pi}{p_end}
{phang2}{cmd:. merge 1:m ea_id using rtm_population, keep(match) nogenerate}{p_end}
{phang2}{cmd:. rtmsample draw, n(12) strata(ea_id) seed(20261025) generate(hh)}{p_end}
{phang2}{cmd:. rtmweight base if hh_sel == 1, probability(ea_pi hh_pi) generate(w_base)}{p_end}

{pstd}A spatially spread sample of grid cells: five per stratum with two ordered replacements, on a cell frame with coordinates x and y and population pop{p_end}
{phang2}{cmd:. rtmsample grid, n(5) strata(stratum) pps(pop) xy(x y) reserve(2) seed(20261025) id(cell_id) generate(g)}{p_end}

{pstd}A phone subsample from a baseline: six households per PSU, every other baseline household kept as an ordered replacement (the L2 practice){p_end}
{phang2}{cmd:. rtmsample draw, n(6) strata(psu) seed(20251027) reserve(all) id(hhid) generate(ph)}{p_end}

{pstd}A random digit dialing sample: 300, 300 and 400 numbers from three prefixes, six random digits{p_end}
{phang2}{cmd:. rtmsample rdd, prefixes(61 62 77) n(300 300 400) digits(6) seed(5) clear}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}{cmd:size}: {cmd:r(n_srs)}, {cmd:r(n_deff)}, {cmd:r(n_hh)}, {cmd:r(n_select)}, {cmd:r(n_panel)}
(per domain, unrounded), {cmd:r(n_domain)} (rounded up), {cmd:r(n_total)}, {cmd:r(f_attrition)},
{cmd:r(z)}, {cmd:r(e)}, the inputs, {cmd:r(kind)}, {cmd:r(case)}, {cmd:r(method)}, {cmd:r(cmdline)}.{p_end}
{pstd}{cmd:allocate}: matrix {cmd:r(alloc)} (N_h, share, exact, n_h, N_h/n_h, n_h/N_h by stratum),
{cmd:r(strata_labels)}, {cmd:r(n)}, {cmd:r(n_rounded)}, {cmd:r(N)}, {cmd:r(H)}, {cmd:r(n_bounded)},
{cmd:r(method)}, {cmd:r(cmdline)}.{p_end}
{pstd}{cmd:draw}: matrix {cmd:r(table)} (units, size, n, certainty, reserve, pi_min, pi_max, sum_w by
stratum), {cmd:r(N_frame)}, {cmd:r(n_selected)}, {cmd:r(n_reserve)}, {cmd:r(n_certainty)}, {cmd:r(H)},
{cmd:r(seed)}, {cmd:r(method)}, {cmd:r(cmdline)} (with the seed). The command and seed are recorded in
the dataset ({cmd:char _dta[rtm_draw]}, {cmd:char _dta[rtm_draw_seed]}, {cmd:notes}) and on
{it:stub}{cmd:_sel} ({cmd:char} {it:stub}{cmd:_sel[rtm_cmd]}); {cmd:allocate} with generate() records
likewise.{p_end}
{pstd}{cmd:grid}: matrix {cmd:r(table)} (units, n, reserve, pi_min, pi_max, sum_w by stratum), {cmd:r(n_selected)},
{cmd:r(n_reserve)}, {cmd:r(n_near)}, {cmd:r(H)}, {cmd:r(seed)}, {cmd:r(seltype)}, {cmd:r(cmdline)} (with the seed); recorded
like {cmd:draw}.{p_end}


{marker limits}{...}
{title:Limits}

{pstd}
The size formulas ignore the finite population correction (UN 2008 footnote 5, p. 53) and treat the
design effect as given; the change case uses the independent-samples formula, which is conservative
for a panel (HFPS Vol. 2, p. 4, item 5; MPPS 2016 p. 45, item 7). Allocation does not take costs into
account (optimum allocation with costs: UN 2008 footnote 7, p. 56). PPS methods need positive sizes
for every unit; units with zero size must be dropped or merged first (Grosh and Mu{c n~}oz 1996, p. 81:
areas under 30 households appended to a neighbour). {cmd:grid} needs R with sf and spsurvey; its
inclusion probabilities are spsurvey's, and with {opt aux()} they are approximations when a unit's
size would give a probability above 1.


{marker references}{...}
{title:References}

{phang}Bankier, M. D. 1988. Power allocations: determining sample sizes for subnational areas. The American Statistician 42(3): 174-177.{p_end}
{phang}Brewer, K. R. W., and M. Hanif. 1983. Sampling with Unequal Probabilities. New York: Springer.{p_end}
{phang}Cochran, W. G. 1977. Sampling Techniques. 3rd ed. New York: Wiley.{p_end}
{phang}Dabalen, A., A. Etang, J. Hoogeveen, E. Mushi, Y. Schipper, and J. von Engelhardt. 2016.
Mobile Phone Panel Surveys in Developing Countries: A Practical Guide for Microdata Collection.
World Bank. (MPPS 2016){p_end}
{phang}Dumelle, M., T. Kincaid, A. R. Olsen, and M. Weber. 2023. spsurvey: spatial sampling design
and analysis in R. Journal of Statistical Software 105(3): 1-29 (the GRTS design the serpentine
order stands in for).{p_end}
{phang}Stevens, D. L., and A. R. Olsen. 2004. Spatially balanced sampling of natural resources. Journal of the American Statistical Association 99(465): 262-278.{p_end}
{phang}Waksberg, J. 1978. Sampling methods for random digit dialing. Journal of the American Statistical Association 73(361): 40-46.{p_end}
{phang}Grosh, M., and J. Mu{c n~}oz. 1996. A Manual for Planning and Implementing the Living Standards Measurement Study Survey. LSMS Working Paper 126. World Bank.{p_end}
{phang}Hartley, H. O., and J. N. K. Rao. 1962. Sampling with unequal probabilities and without replacement. Annals of Mathematical Statistics 33: 350-374.{p_end}
{phang}Himelein, K., S. Eckman, J. Kastelic, K. McGee, M. Wild, and N. Yoshida. 2020. High Frequency
Mobile Phone Surveys of Households to Assess the Impacts of COVID-19, Vol. 2: Guidelines on Sampling
Design. World Bank. (HFPS Vol. 2){p_end}
{phang}Jann, B. 2006 (revised 2020). gsample: Stata module to draw a random sample. SSC S456716.{p_end}
{phang}Neyman, J. 1934. On the two different aspects of the representative method. Journal of the Royal Statistical Society 97(4): 558-625.{p_end}
{phang}Oseni, G., A. Palacios-Lopez, H. K. Mugera, and J. Durazo. 2021. Capturing What Matters: Essential Guidelines for Designing Household Surveys. 2nd ed. LSMS Guidebook. World Bank.{p_end}
{phang}StataCorp. Stata Power, Precision, and Sample-Size Reference Manual: [PSS] power twoproportions, [PSS] power twomeans.{p_end}
{phang}Stevens, D. L., and A. R. Olsen. 2004. Spatially balanced sampling of natural resources. Journal of the American Statistical Association 99(465): 262-278.{p_end}
{phang}United Nations. 2008. Designing Household Survey Samples: Practical Guidelines. Studies in Methods, Series F No. 98. New York. (UN 2008){p_end}


{title:Author}

{pstd}
rtmtools is developed for the Real-Time Monitoring Survey Handbook task team (World Bank).
Report problems with the output of {cmd:rtmtools_setup, check} and a do-file that reproduces them.
{p_end}
