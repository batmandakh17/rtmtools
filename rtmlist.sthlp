{smcl}
{* *! version 0.5.0  25oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmsample" "help rtmsample"}{...}
{vieweralsosee "rtmframe" "help rtmframe"}{...}
{viewerjumpto "Syntax" "rtmlist##syntax"}{...}
{viewerjumpto "Description" "rtmlist##description"}{...}
{viewerjumpto "prepare" "rtmlist##prepare"}{...}
{viewerjumpto "import" "rtmlist##import"}{...}
{viewerjumpto "Examples" "rtmlist##examples"}{...}
{viewerjumpto "Stored results" "rtmlist##results"}{...}
{viewerjumpto "Limits" "rtmlist##limits"}{...}
{viewerjumpto "References" "rtmlist##references"}{...}
{title:Title}

{phang}
{bf:rtmlist} {hline 2} Listing support for the selected areas: listing forms with segmentation, and the completed listing checked and turned into the household frame


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmlist} {cmd:prepare} {ifin}{cmd:,} {opt id(varname)} {opt sav:ing(filename.xlsx)}
[{opt exp:ected(varname)} {opt str:ata(varlist)} {opt seg:mentsize(#)} {opt seed(#)} {opt listing:vars(names)} {opt replace}]

{p 8 16 2}
{cmd:rtmlist} {cmd:import} {cmd:using} {it:listing}{cmd:,} {opt id(varname)}
[{opt exp:ected(varname)} {opt area:var(name)} {opt struct:ure(name)} {opt house:hold(name)} {opt elig:ible(name)} {opt sheet(name)}
{opt ratio(# #)} {opt sav:ing(filename)} {opt replace} {opt clear}]

{pstd}
Dialogs: {dialog rtmlist_prepare}, {dialog rtmlist_import}; or {bf:User > RTM tools > Listing} after
{helpb rtmtools_setup}.


{marker description}{...}
{title:Description}

{pstd}
When the selected areas have no current list of households, the households are listed in the
field before the second stage of selection (UN 2008, paras 95-96, p. 63, and 108, p. 66). The
listing is the second-stage frame: a fixed number of households is then selected from it in the
office, by someone other than the lister (UN 2008, para 131, p. 72), with {helpb rtmsample}
{cmd:draw}. {cmd:rtmlist prepare} writes the listing forms (one sheet per area) and, for large
areas, fixes the segmentation; {cmd:rtmlist import} reads the completed listing, checks it against
the selected areas and builds the household frame. Every run is exported for the Excel display and
the dashboard ({helpb rtmtools_dashboard}); the exports carry area and structure numbers only.

{pstd}
Desk listing of buildings on satellite imagery (the Survey Solutions listing application) needs a
map service and an interactive tool and is not part of the package. Every recent L2 baseline
selected households by random walk rather than from a listing; a random walk has no selection
probability, so the package offers listing-based (or register-based) selection only.


{marker prepare}{...}
{title:rtmlist prepare: the listing forms and the segmentation}

{pstd}
The data in memory are the selected areas, one row per area, with the identifier {opt id()} and,
from the frame, the expected number of households {opt expected()}. The command writes an Excel
workbook ({opt saving()}) with an Instructions sheet, an Areas sheet (identifier, stratum,
expected households, segments, selected segment, segment probability, and columns for the
listed and eligible counts to fill in) and one listing sheet per area with the columns
{opt listingvars()}, by default {cmd:structure_no location_description n_households household_no eligible has_phone notes}.
The forms prescribe no names.

{pstd}
{opt segmentsize(#)}: an area whose expected count exceeds # households is divided into
round(expected / #) segments of roughly equal size, one of which is chosen at random with equal
probability ({opt seed()} recorded); only that segment is listed, and its probability (1 /
segments) multiplies the area's selection probability in the weights. This is the standard
segment design of UN 2008 (paras 138-140, pp. 74-75; segmentation as an office task, para 86,
p. 103); the segments themselves are drawn on the map by the team leader along natural
boundaries. The variables {cmd:list_segments}, {cmd:list_segment_selected} and
{cmd:list_segment_prob} are added to the areas.


{marker import}{...}
{title:rtmlist import: the completed listing}

{pstd}
{it:listing} is the completed listing as one table with one row per listed household: a Stata
file, a CSV file, or an Excel file ({opt sheet()} names the sheet; the first sheet otherwise). Its
columns are named by {opt areavar()}, {opt structure()}, {opt household()} and {opt eligible()}
(defaults {cmd:area_id}, {cmd:structure_no}, {cmd:household_no}, {cmd:eligible}). The data in memory are
the selected areas with {opt id()} (and the segment variables of {cmd:rtmlist prepare} if any).

{pstd}
Checks, printed and exported ({cmd:listing_checks}): selected areas not returned, listed
households in areas that were not selected (dropped), duplicate structure and household numbers
within an area (an error to resolve before the draw), missing or invalid eligibility, and, with
{opt expected()}, areas whose listed/expected ratio falls outside {opt ratio(low high)} (default
{cmd:0.5 2}; a labeled setting with no cited default). The per-area table ({cmd:listing_areas})
gives expected, listed, eligible, the ratio, the segments and the flag.

{pstd}
The household frame has one row per listed eligible household of a selected area: {cmd:area_id},
{cmd:hh_seq} (the household's number within the area's listing), the structure and household
numbers, the area's listed and eligible counts, the ratio and flag, and the segment probability.
It replaces the data in memory with {opt clear}, or is written with {opt saving()}. The draw is
then {cmd:rtmsample draw, n(#) strata(area_id)}: the household's probability is n / eligible
households in the area, times the segment probability where the area was segmented
({cmd:rtmweight base, probability()} multiplies the stage probabilities).


{marker examples}{...}
{title:Examples}

{pstd}
The sample data are synthetic ({cmd:net get rtmtools}): {cmd:rtm_frame.dta} with the 100 selected
areas ({cmd:ea_selected}), and {cmd:rtm_listing.dta} / {cmd:rtm_listing.xlsx}, a completed listing
of those areas with planted problems (one area not returned, one over-listed, one under-listed,
two duplicate rows, three households in an area that was not selected).

{phang2}{cmd:. use rtm_frame, clear}{p_end}
{phang2}{cmd:. keep if ea_selected}{p_end}
{phang2}{cmd:. rtmlist prepare, id(ea_id) expected(ea_size_census) strata(stratum) segmentsize(150) seed(3) saving(listing_forms.xlsx) replace}{p_end}
{phang2}{cmd:. rtmlist import using rtm_listing.dta, id(ea_id) expected(ea_size_census) saving(stage2_frame.dta) replace clear}{p_end}
{phang2}{cmd:. rtmsample draw, n(12) strata(area_id) seed(20261025) id(hh_seq) generate(hh)}{p_end}
{phang2}{cmd:. rtmweight base if hh_sel == 1, probability(ea_pi hh_pi segment_prob) generate(w_base)}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}{cmd:prepare}: {cmd:r(N_areas)}, {cmd:r(n_segmented)}, {cmd:r(seed)} (with segmentation), {cmd:r(saving)}, {cmd:r(listingvars)}, {cmd:r(cmdline)}.{p_end}
{pstd}{cmd:import}: {cmd:r(N_rows)}, {cmd:r(N_frame)}, {cmd:r(N_areas)}, {cmd:r(n_returned)}, {cmd:r(n_not_returned)}, {cmd:r(n_not_selected)},
{cmd:r(n_duplicates)}, {cmd:r(n_under)}, {cmd:r(n_over)}, {cmd:r(areas_not_returned)}, {cmd:r(cmdline)}.{p_end}


{marker limits}{...}
{title:Limits}

{pstd}
The workbook holds one sheet per area, at most 500 per run. The listing's layout is one table
(long); forms filled in sheet by sheet have to be stacked into that table first (a column per
field, one row per household), which the Areas sheet's columns help with. The ratio bounds and
the segment size are the task team's choices. No foundational document prescribes the listing
columns; the defaults avoid names and phone numbers on purpose, since the exports and the
dashboard must never carry them.


{marker references}{...}
{title:References}

{phang}Grosh, M., and J. Mu{c n~}oz. 1996. A Manual for Planning and Implementing the Living Standards Measurement Study Survey. LSMS Working Paper 126. World Bank.{p_end}
{phang}Himelein, K., S. Eckman, J. Kastelic, K. McGee, M. Wild, and N. Yoshida. 2020. High Frequency
Mobile Phone Surveys of Households to Assess the Impacts of COVID-19, Vol. 2: Guidelines on Sampling
Design. World Bank.{p_end}
{phang}United Nations. 2008. Designing Household Survey Samples: Practical Guidelines. Studies in Methods, Series F No. 98. New York.{p_end}


{title:Author}

{pstd}
rtmtools is developed for the Real-Time Monitoring Survey Handbook task team (World Bank).
Report problems with the output of {cmd:rtmtools_setup, check} and a do-file that reproduces them.
{p_end}
