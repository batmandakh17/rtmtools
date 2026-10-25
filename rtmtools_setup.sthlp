{smcl}
{* *! version 0.5.0  25oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{viewerjumpto "Syntax" "rtmtools_setup##syntax"}{...}
{viewerjumpto "Description" "rtmtools_setup##description"}{...}
{viewerjumpto "Options" "rtmtools_setup##options"}{...}
{viewerjumpto "Dependencies" "rtmtools_setup##deps"}{...}
{title:Title}

{phang}
{bf:rtmtools_setup} {hline 2} The User menu, the dependency check and the installation of the community commands rtmtools uses


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmtools_setup} [{cmd:,} {opt prof:ile} {opt inst:all} {opt check} {opt nomenu} {opt menu:only}]


{marker description}{...}
{title:Description}

{pstd}
{cmd:rtmtools_setup} adds the {bf:User > RTM tools} menu (Weights, Frame, Sample, Listing, the
estimation dialog, the dashboard, this check and the help) to Stata's windowed interface for the
session, checks the Stata version and the community commands the package relies on, and installs
the missing ones from SSC on request. Nothing in the package uses R.


{marker options}{...}
{title:Options}

{phang}
{opt profile} also appends two lines to {cmd:profile.do} in your PERSONAL directory so that the
menu is there at every start of Stata ({cmd:capture rtmtools_setup, menuonly}). The lines are
shown first and, in the windowed interface, confirmed in a dialog.

{phang}
{opt install} installs the missing community commands from SSC ({cmd:ssc install}); this is the
only step of the package that uses the internet.

{phang}
{opt check} is the default action together with the menu; {opt nomenu} runs the check without
touching the menu (for batch runs); {opt menuonly} adds the menu and prints nothing (the form
profile.do uses).


{marker deps}{...}
{title:Dependencies}

{pstd}
Stata 16 or later. {cmd:svycal} (part of Stata 18) is used by {cmd:rtmweight calibrate}'s default
engine and by {cmd:rtmweight nonresponse, method(ebalance)}; on Stata 16 and 17 the alternatives
are {cmd:engine(ipfraking)} and the other adjustment methods. Community commands, all from SSC:

{p2colset 5 20 22 2}{...}
{p2col:{cmd:survwgt}}{cmd:rtmweight nonresponse, method(classes)} (Winter 2002){p_end}
{p2col:{cmd:ebalance}}{cmd:rtmweight nonresponse, method(ebalance_nobase)} and the cross-check of {cmd:method(ebalance)} (Hainmueller and Xu 2013){p_end}
{p2col:{cmd:ipfraking}}{cmd:rtmweight calibrate, engine(ipfraking)} and {cmd:wgtcellcollapse} (Kolenikov 2014){p_end}
{p2col:{cmd:gsample}}{cmd:rtmsample draw} (with {cmd:moremata}) (Jann 2006){p_end}
{p2col:{cmd:shp2dta}}{cmd:rtmframe grid}: the boundaries shapefile (Crow 2006){p_end}
{p2col:{cmd:geoinpoly}}{cmd:rtmframe grid}: pixels in polygons (Picard 2015){p_end}
{p2col:{cmd:sreweight}}the bounded logit calibration distance, run by hand (Pacifico 2014){p_end}
{p2colreset}{...}

{pstd}
The check prints each command as installed or missing with the install line. {cmd:r(missing)}
lists the missing ones.
