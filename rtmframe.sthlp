{smcl}
{* *! version 0.3.0  24oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmsample" "help rtmsample"}{...}
{vieweralsosee "rtmtools_setup" "help rtmtools_setup"}{...}
{viewerjumpto "Syntax" "rtmframe##syntax"}{...}
{viewerjumpto "Description" "rtmframe##description"}{...}
{viewerjumpto "list" "rtmframe##list"}{...}
{viewerjumpto "grid" "rtmframe##grid"}{...}
{viewerjumpto "replace" "rtmframe##replace"}{...}
{viewerjumpto "split" "rtmframe##split"}{...}
{viewerjumpto "Examples" "rtmframe##examples"}{...}
{viewerjumpto "Stored results" "rtmframe##results"}{...}
{viewerjumpto "Limits" "rtmframe##limits"}{...}
{viewerjumpto "References" "rtmframe##references"}{...}
{title:Title}

{phang}
{bf:rtmframe} {hline 2} Sampling frames of areas: checks on a list frame, and grid frames from boundaries and population rasters, with replacement cells and splits


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmframe} {cmd:list} {ifin}{cmd:,} {opt id(varlist)}
[{opt size(varname)} {opt str:ata(varlist)} {opt ex:clude(varname)} {opt min:size(#)} {opt max:size(#)}
{opt merge(newvar)} {opt sort(varlist)} {opt per:sons(varname)} {opt males(varname)} {opt fem:ales(varname)} {opt replace}]

{p 8 16 2}
{cmd:rtmframe} {cmd:grid} {cmd:using} {it:boundaries_file}{cmd:,} {c -(} {opt cell:size(#)} {c |} {opt ncell:s(#)} {c )-}
[{opt raster(file)} {opt points(file)} {opt pointw:eight(name)} {opt str:ata(name)} {opt groups(#)}
{opt min:pop(#)} {opt keep:empty} {opt crs(#)} {opt seed(#)} {opt l:ayer(name)} {opt sav:ing(file)} {opt map(file)} {opt clear}]

{p 8 16 2}
{cmd:rtmframe} {cmd:replace} {cmd:using} {it:grid_file}{cmd:,} {opt cell:s(numlist)}
[{opt ex:clude(numlist)} {opt sel:ected(varname)} {opt adj:acency(queen|rook)} {opt id(name)} {opt l:ayer(name)} {opt sav:ing(file)} {opt clear}]

{p 8 16 2}
{cmd:rtmframe} {cmd:split} {cmd:using} {it:grid_file}{cmd:,} {opt cell:s(numlist)}
[{opt parts(2|3|4)} {opt raster(file)} {opt id(name)} {opt l:ayer(name)} {opt sav:ing(file)} {opt clear}]

{pstd}
Dialogs: {dialog rtmframe_list}, {dialog rtmframe_grid}, {dialog rtmframe_replace}, {dialog rtmframe_split};
or {bf:User > RTM tools > Frame} after {helpb rtmtools_setup}. {cmd:grid}, {cmd:replace} and {cmd:split}
run R (packages sf and terra) in the background; {cmd:list} is Stata only. Page numbers below are
those of the PDF files of the cited documents.


{marker description}{...}
{title:Description}

{pstd}
A sampling frame must be complete, accurate and up to date (UN 2008, section 4.1.2, p. 88), and
most household surveys select areas first (census enumeration areas) from a list frame, then
households within them. {cmd:rtmframe list} checks such a list and prepares it for
{helpb rtmsample}: identifiers, measures of size, units too small to sample or too large to list,
exclusions, and the consistency of population counts. Where no usable list exists, or it is out
of date, the guidelines point to grid-based and other geospatial frames (Capturing What Matters
2021, p. 17); {cmd:rtmframe grid} builds one from boundary files and a population raster, as the
Survey Solutions spatial sampling applications do (Wild 2021; the susospatsample and
susorastoframe READMEs), {cmd:rtmframe replace} lists replacement cells for an area that cannot
be surveyed (the susogrdframe rule), and {cmd:rtmframe split} cuts large cells into segments. The
spatially balanced draw from a grid frame is {helpb rtmsample##grid:rtmsample grid}.


{marker list}{...}
{title:rtmframe list: checks on a list frame}

{pstd}
The data in memory are the frame, one row per area. {opt id(varlist)} identifies the unit;
{opt size(varname)} is its measure of size (households or population from the census);
{opt strata(varlist)} the strata for the summary table. The command writes flags that start
with {cmd:frame_}: {cmd:frame_dup} (identifier not unique), {cmd:frame_badsize} (size missing or
not positive), {cmd:frame_small} (below {opt minsize(#)}), {cmd:frame_large} (above
{opt maxsize(#)}) with {cmd:frame_segments} = size / maxsize rounded (at least 2), {cmd:frame_excl}
({opt exclude(varname)} equal to 1) and {cmd:frame_ok} (unique, positive size, not excluded).
Grosh and Mu{c n~}oz 1996 (p. 81) append areas under 30 households to a neighbour and segment
areas over 300 (p. 84); UN 2008 para 177 (p. 82) divides an area into segments equal to its
current count over its original size, rounded.

{phang}
{opt merge(newvar)} combines small units with the following units in the {opt sort()} order
within the stratum until each combined unit reaches {opt minsize()} (a last unit still below it
joins the previous one): {it:newvar} holds the identifier of the first unit of each combined unit
and {it:newvar}{cmd:_size} its size. Sort the frame geographically first, so that combined units
are neighbours (Grosh and Mu{c n~}oz 1996, p. 81: sequential codes usually follow geography).

{phang}
{opt persons(varname)}, {opt males(varname)} and {opt females(varname)} run the consistency
checks of Grosh and Mu{c n~}oz 1996 (pp. 80-81): persons per household between 3 and 10, males
plus females equal to persons, masculinity ratio between 80 and 120 percent. {opt replace}
overwrites the flag variables.


{marker grid}{...}
{title:rtmframe grid: a grid frame from boundaries and a raster}

{pstd}
{it:boundaries_file} is a vector file sf can read (GeoPackage, shapefile, GeoJSON; {opt layer()}
picks a layer of a GeoPackage). The command lays a square grid of {opt cellsize(#)} metres (or
about {opt ncells(#)} cells) over the boundaries, clips every cell to them, assigns each cell to
the boundary feature with the largest overlap (its {opt strata(name)} value becomes the stratum;
all boundary attributes are carried as {cmd:b_}{it:name}), and measures each cell's size from
{opt raster(file)} (a GeoTIFF of population or buildings: the sum inside the cell, with boundary
raster cells counted by the fraction covered, {cmd:terra::extract(exact = TRUE)}) or from
{opt points(file)} (points inside the cell, counted or weighted by {opt pointweight(name)}). Cells
with no population are dropped unless {opt keepempty}; {opt minpop(#)} raises the threshold.
{opt groups(#)} forms homogeneous groups of cells by k-means on log(1 + size) (the grouping
susorastoframe offers), numbered from the smallest; {opt seed(#)} fixes it. Geographic
coordinates are projected to the UTM zone of the centroid unless {opt crs(#)} gives an EPSG code.

{pstd}
The frame replaces the data in memory ({opt clear} is required when the data have changed), one
row per cell: {cmd:cell_id}, {cmd:stratum}, {cmd:pop}, {cmd:area_km2}, projected {cmd:x} {cmd:y},
{cmd:lon} {cmd:lat} and the bounding box in WGS84, {cmd:feature}, {cmd:group}, and the boundary
attributes. {opt saving(file)} writes the cells and the boundaries to a GeoPackage (layers
{cmd:cells} and {cmd:boundaries}) for {cmd:rtmsample grid}, {cmd:rtmframe replace}, maps and the
field application; {opt map(file)} writes a PNG map of the cells shaded by size.


{marker replace}{...}
{title:rtmframe replace: replacement cells}

{pstd}
For each cell in {opt cells(numlist)} of {it:grid_file} (the GeoPackage written by
{cmd:rtmframe grid}), the cells adjacent to it in the same stratum, not in {opt exclude(numlist)}
and not flagged 1 in {opt selected(varname)} of the frame in memory, ranked by the distance
between centroids, with their measure of size, centroid and bounding box: the rule of the
Survey Solutions grid replacement application. {opt adjacency(queen)} (default) counts cells
sharing an edge or a corner, {opt adjacency(rook)} an edge only. The list replaces the data in
memory; {opt saving(file)} writes the candidates and the cells to replace to a GeoPackage. UN
2008 (paras 172 and 178, pp. 81-82) calls substituting an area a biased procedure: use it only
for areas that truly cannot be surveyed, and record every replacement in the report.


{marker split}{...}
{title:rtmframe split: segments of large cells}

{pstd}
Cuts each cell in {opt cells(numlist)} into {opt parts(#)} x {opt parts(#)} sub-cells (2, 3 or 4,
as in susogrdframe), clipped to the cell, with the measure of size of each part from
{opt raster(file)}, their centroids and bounding boxes. Select one part at random, with
probability proportional to its size, list it, and carry the selection probability into the
area's weight (UN 2008 para 177, p. 82; Grosh and Mu{c n~}oz 1996, p. 84). {opt saving(file)}
writes the parts to a GeoPackage.


{marker examples}{...}
{title:Examples}

{pstd}Checks on the synthetic area frame: sizes under 80 combined with neighbours, over 250
flagged for segmentation{p_end}
{phang2}{cmd:. use rtm_frame, clear}{p_end}
{phang2}{cmd:. rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) maxsize(250) merge(unit) sort(ea_id)}{p_end}

{pstd}A grid frame of 10 km cells over the synthetic boundaries, sized by the population raster,
stratified by region, with three size groups; then a spatially balanced sample of five cells per
region with two ordered replacements each{p_end}
{phang2}{cmd:. rtmframe grid using rtm_boundaries.gpkg, raster(rtm_population.tif) cellsize(10000) strata(region) groups(3) saving(rtm_grid.gpkg) map(rtm_grid.png) clear}{p_end}
{phang2}{cmd:. rtmsample grid using rtm_grid.gpkg, n(5) strata(stratum) nover(2) seed(20261024) generate(g)}{p_end}

{pstd}Cell 45 cannot be surveyed: its adjacent cells in the same stratum, excluding the ones already
selected; and cell 60 is too large to list: its 2 x 2 segments{p_end}
{phang2}{cmd:. rtmframe replace using rtm_grid.gpkg, cells(45) selected(g_sel) saving(replacements.gpkg) clear}{p_end}
{phang2}{cmd:. rtmframe split using rtm_grid.gpkg, cells(60) parts(2) raster(rtm_population.tif) clear}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}{cmd:list}: matrix {cmd:r(table)} (units, usable, size total, min, median, max by stratum),
{cmd:r(N)}, {cmd:r(N_ok)}, {cmd:r(n_dup)}, {cmd:r(n_badsize)}, {cmd:r(n_small)}, {cmd:r(n_large)},
{cmd:r(n_excluded)}, {cmd:r(n_hhsize_flag)}, {cmd:r(n_sexsum_flag)}, {cmd:r(n_masc_flag)}, {cmd:r(n_merged)},
{cmd:r(n_combined_units)}, {cmd:r(H)}, {cmd:r(cmdline)}.{p_end}
{pstd}{cmd:grid}: matrix {cmd:r(table)} (cells, size total, min, median, max, area by stratum),
{cmd:r(N_cells)}, {cmd:r(dropped)}, {cmd:r(pop_total)}, {cmd:r(pop_boundaries)} (the raster or points total
inside the boundaries), {cmd:r(cellsize)}, {cmd:r(epsg)}, {cmd:r(H)}, {cmd:r(groups)}, {cmd:r(gpkg)},
{cmd:r(versions)}, {cmd:r(cmdline)}.{p_end}
{pstd}{cmd:replace}: {cmd:r(N_cells)}, {cmd:r(N_candidates)}, {cmd:r(adjacency)}, {cmd:r(cmdline)}.
{cmd:split}: {cmd:r(N_parts)}, {cmd:r(parts)}, {cmd:r(cmdline)}.{p_end}
{pstd}The commands record themselves in the dataset's notes and characteristics ({cmd:char _dta[rtm_frame]}).{p_end}


{marker limits}{...}
{title:Limits}

{pstd}
The grid commands need R with sf and terra ({helpb rtmtools_setup} checks them) and read only
local files. The stratum of a cell is the feature with the largest overlap, so a cell on a
boundary belongs to one stratum and its population from the other side is counted with it;
smaller cells reduce this. Raster sums are population counts only if the raster holds counts
per raster cell (for a density raster, convert to counts first). Replacement candidates are
adjacent cells; a stratum with no adjacent cell left gives an empty list. The commands do not
decide the cell size, the strata or whether to replace an area.


{marker references}{...}
{title:References}

{phang}Grosh, M., and J. Mu{c n~}oz. 1996. A Manual for Planning and Implementing the Living Standards Measurement Study Survey. LSMS Working Paper 126. World Bank.{p_end}
{phang}Oseni, G., A. Palacios-Lopez, H. K. Mugera, and J. Durazo. 2021. Capturing What Matters: Essential Guidelines for Designing Household Surveys. 2nd ed. LSMS Guidebook. World Bank.{p_end}
{phang}Pebesma, E. 2018. Simple features for R: standardized support for spatial vector data. The R Journal 10(1): 439-446. (sf){p_end}
{phang}Hijmans, R. J. 2024. terra: Spatial Data Analysis. R package. (terra){p_end}
{phang}United Nations. 2008. Designing Household Survey Samples: Practical Guidelines. Studies in Methods, Series F No. 98. New York. (UN 2008){p_end}
{phang}Wild, M. 2021. Spatial Sampling Application (manual). World Bank. Wild, M. n.d. READMEs of susospatsample, susorastoframe and susogrdframe (GitHub michael-cw).{p_end}


{title:Author}

{pstd}
rtmtools is developed for the Real-Time Monitoring Survey Handbook task team (World Bank).
Report problems with the output of {cmd:rtmtools_setup, check} and a do-file that reproduces them.
{p_end}
