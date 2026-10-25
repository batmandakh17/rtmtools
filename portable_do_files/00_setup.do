********************************************************************************************
* 00_setup.do  --  one-time setup for the rtmtools portable do-files (version 0.5.0, 25 Oct 2026)
*
* Run this once on a new computer, from the portable_do_files folder:   do 00_setup.do
* It checks the Stata version and installs the community commands the do-files use. The
* installation is the only step that needs an internet connection; nothing else in these
* do-files reads from or writes to the network.
*
* Which do-file needs which command:
*   04_weights.do   method classes: survwgt (Winter 2002); method ebalance_nobase: ebalance
*                   (Hainmueller and Xu 2013); calibration: svycal (official, Stata 18) or, in
*                   an earlier Stata, ipfraking (Kolenikov 2014) run by hand
*   03_sample.do    gsample (Jann 2006) and moremata                       (later versions)
*   01_frame.do     geoinpoly (Picard 2015) for grid frames                 (later versions)
********************************************************************************************
version 16
di as text "Stata " c(stata_version) " (" c(flavor) ")"
if c(stata_version) < 16 {
    di as err "these do-files need Stata 16 or later"
    exit 9
}
capture which svycal
if _rc di as txt "note: svycal (Stata 18) is not available; calibration in 04_weights.do needs it (ipfraking is the alternative, run by hand)"
else di as text "svycal available: calibration can run"

* community commands, installed from SSC when missing (needs internet; asks nothing)
local missing ""
foreach dep in survwgt ebalance ipfraking gsample geoinpoly {
    capture which `dep'
    if _rc {
        di as text %-12s "`dep'" as err "missing"
        local missing "`missing' `dep'"
    }
    else di as text %-12s "`dep'" as result "installed"
}
capture mata: mata which mm_sample()
if _rc {
    di as text %-12s "moremata" as err "missing"
    local missing "`missing' moremata"
}
else di as text %-12s "moremata" as result "installed"
if "`missing'" != "" {
    di as text _n "Installing from SSC:`missing'"
    foreach dep of local missing {
        capture noisily ssc install `dep', replace
        if _rc di as err "could not install `dep' (no internet connection, or SSC unreachable); install it later with: ssc install `dep'"
    }
}
else di as text _n "Everything the do-files use is installed."
di as text "Next: open 04_weights.do, change the PARAMETERS block (see ADAPTATION.md), and run it."
