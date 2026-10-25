{smcl}
{* *! version 0.5.0  25oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{vieweralsosee "rtmsample" "help rtmsample"}{...}
{vieweralsosee "shp2dta" "help shp2dta"}{...}
{vieweralsosee "geoinpoly" "help geoinpoly"}{...}
{viewerjumpto "Syntax" "rtmframe##syntax"}{...}
{viewerjumpto "Description" "rtmframe##description"}{...}
{viewerjumpto "list" "rtmframe##list"}{...}
{viewerjumpto "grid" "rtmframe##grid"}{...}
{viewerjumpto "replace" "rtmframe##replace"}{...}
{viewerjumpto "split" "rtmframe##split"}{...}
{viewerjumpto "Preparing the files" "rtmframe##files"}{...}
{viewerjumpto "Examples" "rtmframe##examples"}{...}
{viewerjumpto "Stored results" "rtmframe##results"}{...}
{viewerjumpto "Limits" "rtmframe##limits"}{...}
{viewerjumpto "References" "rtmframe##references"}{...}
{title:Title}

{phang}
{bf:rtmframe} {hline 2} Sampling frames of areas: checks on a list frame, grid frames from a population raster and boundaries, replacement cells and splits of large cells, without R


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmframe} {cmd:list} {ifin}{cmd:,} {opt id(varlist)}
[{opt size(varname)} {opt str:ata(varlist)} {opt ex:clude(varname)} {opt min:size(#)} {opt max:size(#)} {opt merge(name)} {opt sort(varlist)}
{opt per:sons(varname)} {opt males(varname)} {opt fem:ales(varname)} {opt replace}]

{p 8 16 2}
{cmd:rtmframe} {cmd:grid} {cmd:using} {it:boundaries.shp}{cmd:,} {opt ras:ter(file.asc)} {opt cell:size(#)}
[{opt str:ata(attribute)} {opt id(attribute)} {opt min:size(#)} {opt sav:ing(filename)} {opt savingp:ixels(filename)} {opt block:s(#)} {opt maxp:ixels(#)} {opt clear} {opt replace}]

{p 8 16 2}
{cmd:rtmframe} {cmd:replace}{cmd:,} {opt cell:s(numlist)}
[{opt adj:acency(queen|rook)} {opt sel:ected(varname)} {opt ex:clude(varname)} {opt ncand(#)} {opt gen:erate(prefix)} {opt sav:ing(filename)} {opt replace}]

{p 8 16 2}
{cmd:rtmframe} {cmd:split}{cmd:,} {opt cell:s(numlist)} {opt parts(#)} {opt pix:els(filename)}
[{opt sav:ing(filename)} {opt replace} {opt clear}]

{pstd}
Dialogs: {dialog rtmframe_list}, {dialog rtmframe_grid}, {dialog rtmframe_replace}, {dialog rtmframe_split};
or {bf:User > RTM tools > Frame} after {helpb rtmtools_setup}. No step uses R.


{marker description}{...}
{title:Description}

{pstd}
A sampling frame of areas is either a list (census enumeration areas with household counts,
villages, blocks) or, where no current list exists, a grid of cells laid over the territory with
the population of each cell summed from a gridded population raster (HFPS Vol. 2, Himelein et al.
2020, section 1.1, pp. 1-2; UN 2008, ch. 4). {cmd:rtmframe list} checks and flags a list frame;
{cmd:rtmframe grid} builds a grid frame; {cmd:rtmframe replace} proposes neighbouring cells for a
cell that cannot be surveyed; {cmd:rtmframe split} divides large cells before listing. The draws
from either frame are made with {helpb rtmsample} ({cmd:draw} for lists, {cmd:grid} for cells).
Every run is exported for the Excel display and the dashboard (see {helpb rtmtools_dashboard}).
The commands carry out the design the task team chose; they do not decide what a survey should
represent.


{marker list}{...}
{title:rtmframe list: checks on a list frame}

{pstd}
{opt id(varlist)} identifies the units. The command flags duplicate identifiers, missing or
non-positive measures of size ({opt size()}), units below {opt minsize(#)} (too small to sample on
their own) and above {opt maxsize(#)} (to be segmented before listing; {cmd:frame_segments} suggests
how many), excluded units ({opt exclude()} = 1), and, with {opt persons()}, {opt males()} and
{opt females()}, the population checks of Grosh and Mu{c n~}oz 1996 (pp. 80-81 of the PDF: persons per
household between 3 and 10, masculinity ratio between 80 and 120 percent, males plus females
equal to persons). {opt merge(name)} combines small units with the following units in
{opt sort()} order within strata until their sizes reach minsize(), the LSMS practice of appending
units under 30 households to a neighbour (Grosh and Mu{c n~}oz 1996, p. 81). The flags are the
variables {cmd:frame_ok}, {cmd:frame_dup}, {cmd:frame_badsize}, {cmd:frame_small}, {cmd:frame_large},
{cmd:frame_segments} and {cmd:frame_excl}. Source: UN 2008, section 4.1.2 (a frame must be complete,
accurate and up to date).


{marker grid}{...}
{title:rtmframe grid: a grid frame from a population raster and boundaries}

{pstd}
Inputs: the administrative boundaries as an ESRI shapefile ({cmd:using}) and the population
raster as an ESRI ASCII grid ({opt raster()}), both in the same projected coordinate system in
metres (see {it:Preparing the files}). The command lays a grid of square cells of {opt cellsize(#)}
metres over the raster from its south-west corner, reads every pixel as a point with its
population, assigns each pixel to the boundary polygon it falls in ({helpb geoinpoly}, Picard
2015, on the vertices read by {helpb shp2dta}), drops the pixels outside every polygon (counted
and reported with their population), and sums the pixels by cell. A cell whose pixels fall in
several polygons belongs to the polygon holding most of its population ({cmd:unit_share} says how
much; {cmd:parts} counts the polygons), and takes that polygon's {opt strata(attribute)} as its
stratum (the polygon's record as stratum without strata()). {opt id(attribute)} names the polygons
in the frame. Cells with no population inside the boundaries are dropped; cells below
{opt minsize(#)} are flagged ({cmd:small}). {opt blocks(#)} sums pixels into blocks of # x # before
the polygon step, for large rasters; {opt maxpixels(#)} (default 4,000,000) is the size above which
the command stops and asks for a coarser raster or blocks(). The frame replaces the data in memory
({opt clear} when the data have unsaved changes); {opt saving()} writes it, {opt savingpixels()}
writes the pixel table that {cmd:rtmframe split} needs.

{pstd}
The frame holds {cmd:cell_id}, {cmd:col}, {cmd:row}, {cmd:x}, {cmd:y} (the cell centre), {cmd:unit},
{cmd:unit_name}, {cmd:stratum}, {cmd:pop}, {cmd:npix}, {cmd:parts}, {cmd:unit_share} and {cmd:small},
and the grid's size and origin as characteristics. A cell's population is the population inside
the boundaries, exact at the raster's resolution; its area inside the boundaries is counted in
pixels ({cmd:npix}), not clipped as a GIS program would. The export carries the cells, a summary by
stratum and the boundary vertices, which the dashboard maps.


{marker replace}{...}
{title:rtmframe replace: replacement cells}

{pstd}
For each cell in {opt cells(numlist)} (values of {cmd:cell_id}), the cells of the same stratum that
are adjacent ({opt adjacency(queen)}, the default: sharing a side or a corner; {cmd:rook}: a side),
not already selected ({opt selected()} = 1), not excluded ({opt exclude()} = 1) and not themselves to
be replaced, ranked by the distance between cell centres and then by population; up to
{opt ncand(#)} (default 3) per cell. When no adjacent cell qualifies the ring two cells away is
tried and the candidates are flagged ({cmd:ring 2}). {opt generate(prefix)} writes {it:prefix}{cmd:_for}
(the cell a candidate can replace) and {it:prefix}{cmd:_rank}; {opt saving()} writes the candidate list.
Replacing a unit is a substitution, which UN 2008 (paras 172, 178-179) calls a biased procedure:
record which cell replaced which and say so in the report. The rules follow the Survey Solutions
toolbox's susogrdframe (adjacent, same stratum) for comparison.


{marker split}{...}
{title:rtmframe split: splitting large cells}

{pstd}
Each cell in {opt cells(numlist)} is divided into {opt parts(#)} x {opt parts(#)} sub-cells, and the
pixels of the pixel table {opt pixels(filename)} (written by {cmd:rtmframe grid, savingpixels()}) are
summed by sub-cell; the parts' populations add to the cell's. The parts are listed, saved with
{opt saving()}, exported, and with {opt clear} they replace the data in memory. Splitting a selected
cell before listing is the standard segment design of UN 2008 (paras 138-140, pp. 74-75): one
part is then chosen at random with equal probability ({cmd:rtmsample draw, n(1) strata(cell_id)})
and its selection probability multiplies the cell's.


{marker files}{...}
{title:Preparing the files}

{pstd}
Stata reads ESRI shapefiles (through {helpb shp2dta}) and plain-text rasters; it cannot read
GeoTIFF, GeoPackage or GeoJSON. Population rasters (WorldPop, GRID3, HRSL) come as GeoTIFF and
boundaries often as GeoPackage: convert them once per country in QGIS (free): for the raster,
Raster > Conversion > Translate (Convert Format), output format "Arc/Info ASCII Grid"; for the
boundaries, right-click the layer > Export > Save Features As > "ESRI Shapefile". Both must be in
the same projected coordinate system (metres), for example the country's UTM zone: reproject in
the same dialogs if needed. Attribute names in a shapefile are at most 10 characters. A cell
table prepared elsewhere (cell identifier, x, y, population, unit) can be used as a list frame
with {cmd:rtmframe list} and drawn from with {cmd:rtmsample grid}. The L2 programs have not used
grid frames; this route is for programs without a usable list frame.


{marker examples}{...}
{title:Examples}

{pstd}
The sample data are synthetic ({cmd:net get rtmtools}): {cmd:rtm_frame.dta} (400 enumeration areas
in 8 strata with census household counts), {cmd:rtm_boundaries.shp} (four regions over a 100 km
square, EPSG:32633) and {cmd:rtm_population.asc} (a 1 km population raster of the same square).

{phang2}{cmd:. use rtm_frame, clear}{p_end}
{phang2}{cmd:. rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) maxsize(250)}{p_end}
{phang2}{cmd:. rtmframe list, id(ea_id) size(ea_size_census) strata(stratum) minsize(80) merge(unit) sort(ea_id) replace}{p_end}

{pstd}A grid frame of 5 km cells, stratified by region, with the pixel table kept for splits{p_end}
{phang2}{cmd:. rtmframe grid using rtm_boundaries.shp, raster(rtm_population.asc) cellsize(5000) strata(regcode) id(region) minsize(500) saving(rtm_grid5.dta) savingpixels(rtm_pixels5.dta) clear replace}{p_end}

{pstd}A spatially spread draw of five cells per region with two ordered replacements{p_end}
{phang2}{cmd:. rtmsample grid, n(5) strata(stratum) pps(pop) xy(x y) reserve(2) seed(20261025) id(cell_id) generate(g)}{p_end}

{pstd}Replacement candidates for two selected cells; a 2 x 2 split of one of them{p_end}
{phang2}{cmd:. rtmframe replace, cells(45 212) selected(g_sel) ncand(3) generate(rp) saving(rtm_repl.dta) replace}{p_end}
{phang2}{cmd:. rtmframe split, cells(45) parts(2) pixels(rtm_pixels5.dta) saving(rtm_parts.dta) replace}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}{cmd:list}: {cmd:r(N)}, {cmd:r(N_ok)}, {cmd:r(n_dup)}, {cmd:r(n_badsize)}, {cmd:r(n_small)}, {cmd:r(n_large)}, {cmd:r(n_excluded)},
{cmd:r(n_hhsize_flag)}, {cmd:r(n_sexsum_flag)}, {cmd:r(n_masc_flag)}, {cmd:r(n_merged)}, {cmd:r(n_combined_units)}, {cmd:r(H)}, matrix {cmd:r(table)}.{p_end}
{pstd}{cmd:grid}: {cmd:r(N_cells)}, {cmd:r(H)}, {cmd:r(n_polygons)}, {cmd:r(n_empty)}, {cmd:r(n_straddle)}, {cmd:r(n_small)}, {cmd:r(pop_raster)},
{cmd:r(pop_inside)}, {cmd:r(pop_outside)}, {cmd:r(pixels_outside)}, {cmd:r(cellsize)}, {cmd:r(pixelsize)}, matrix {cmd:r(table)}.{p_end}
{pstd}{cmd:replace}: {cmd:r(n_cells)}, {cmd:r(n_with_candidates)}, {cmd:r(n_ring2)}, {cmd:r(adjacency)}.{p_end}
{pstd}{cmd:split}: {cmd:r(n_parts)}, {cmd:r(parts)}, {cmd:r(n_mismatch)}, {cmd:r(partsize)}.{p_end}
{pstd}All store {cmd:r(cmdline)} and record the command in the dataset's characteristics and notes.{p_end}


{marker limits}{...}
{title:Limits}

{pstd}
Grid frames need the one-time conversion of the input files described above; the command reads
nothing else. A cell's area inside the boundaries is counted in pixels, so a cell on a coastline
or a border is described by its population inside, not by a clipped polygon; cells with no pixel
centre inside any polygon are dropped and listed. The stratum of a straddling cell follows the
polygon with most of its population; no foundational document covers this choice, so it is stated
in the help and in the export. The spatially balanced (GRTS) draw of version 0.4.0 is replaced by
the serpentine systematic draw of {helpb rtmsample} {cmd:grid}; what is lost is stated there. Rasters
above {opt maxpixels()} need a coarser product or {opt blocks()}; the pixel-to-polygon step
({helpb geoinpoly}) takes minutes for a few hundred thousand points.


{marker references}{...}
{title:References}

{phang}Grosh, M., and J. Mu{c n~}oz. 1996. A Manual for Planning and Implementing the Living Standards Measurement Study Survey. LSMS Working Paper 126. World Bank.{p_end}
{phang}Himelein, K., S. Eckman, J. Kastelic, K. McGee, M. Wild, and N. Yoshida. 2020. High Frequency
Mobile Phone Surveys of Households to Assess the Impacts of COVID-19, Vol. 2: Guidelines on Sampling
Design. World Bank.{p_end}
{phang}Picard, R. 2015. GEOINPOLY: Stata module to match geographic locations to shapefile polygons. SSC.{p_end}
{phang}Crow, K. 2006 (revised 2015). SHP2DTA: Stata module to convert shape boundary files to Stata datasets. SSC.{p_end}
{phang}United Nations. 2008. Designing Household Survey Samples: Practical Guidelines. Studies in Methods, Series F No. 98. New York.{p_end}
{phang}Wild, M. 2021. Spatial Sampling Application (manual); n.d.-d, susogrdframe README. World Bank, GitHub michael-cw (for comparison).{p_end}


{title:Author}

{pstd}
rtmtools is developed for the Real-Time Monitoring Survey Handbook task team (World Bank).
Report problems with the output of {cmd:rtmtools_setup, check} and a do-file that reproduces them.
{p_end}
