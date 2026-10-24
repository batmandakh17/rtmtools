{smcl}
{* *! version 0.1.0  24oct2026  rtmtools}{...}
{vieweralsosee "rtmtools" "help rtmtools"}{...}
{viewerjumpto "Syntax" "rtmtools_setup##syntax"}{...}
{viewerjumpto "Description" "rtmtools_setup##description"}{...}
{viewerjumpto "Options" "rtmtools_setup##options"}{...}
{title:Title}

{phang}
{bf:rtmtools_setup} {hline 2} Add the RTM tools menu, check and install dependencies, check R


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:rtmtools_setup} [{cmd:,} {opt prof:ile} {opt inst:all} {opt path(string)} {opt check} {opt nomenu} {opt nor} {opt menu:only}]


{marker description}{...}
{title:Description}

{pstd}
{cmd:rtmtools_setup} adds {bf:User > RTM tools} to Stata's menu for the current session, checks the
Stata version (16 or later; {helpb svycal} needs 18), reports which user-written commands the
package relies on are installed, and checks whether R and the R packages used by the
R-dependent steps are available. Nothing is sent anywhere; the only network use is
{opt install}, which downloads the missing commands from SSC.

{pstd}
Menu additions made with {cmd:window menu} last for the session. With {opt profile}, the setup
command appends one line to your {cmd:profile.do} (shown first, and confirmed in a dialog
when Stata runs with its windowed interface) so that the menu is there at every start.


{marker options}{...}
{title:Options}

{phang}{opt profile}: append the menu line to profile.do in your PERSONAL directory. The line written is {cmd:capture rtmtools_setup, menuonly}, under a marker comment; delete those two lines to undo.{p_end}
{phang}{opt menuonly}: add the menu and do nothing else, without output. This is what profile.do runs at every start.{p_end}
{phang}{opt install}: install the missing SSC commands ({cmd:survwgt}, {cmd:ipfraking}, {cmd:gsample}, {cmd:moremata}, {cmd:fhsae}, {cmd:sreweight}).{p_end}
{phang}{opt path(string)}: full path to Rscript, saved to {cmd:rtmtools_rscript.txt} in your PERSONAL directory, when R is not in a standard location (Windows: C:\Program Files\R\R-x.y.z\bin\Rscript.exe; Mac: /usr/local/bin, /opt/homebrew/bin or the R framework).{p_end}
{phang}{opt check}: run the checks only (with {opt nomenu}, no menu).{p_end}
{phang}{opt nor}: skip the R check.{p_end}

{pstd}
Which step needs what: {cmd:rtmweight nonresponse, method(classes)} needs survwgt; {cmd:rtmweight calibrate, engine(ipfraking)}
needs ipfraking; {cmd:engine(regenesees)} needs R with haven and ReGenesees. Everything else works with Stata alone.
