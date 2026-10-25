*! rtmtools_setup.ado  version 0.5.0  25oct2026  rtmtools
*! One-time setup: adds the RTM tools entries to Stata's User menu for this session, can
*! append the same lines to profile.do (so that the menu is there at every start), checks the
*! Stata version and the user-written commands the package relies on, and installs the missing
*! ones from SSC on request. Nothing in the package uses R.
*!
*!   rtmtools_setup                      menu for this session + a check report
*!   rtmtools_setup, profile             also append the menu lines to profile.do (asks first in the GUI)
*!   rtmtools_setup, install             install missing SSC dependencies (needs internet)
*!   rtmtools_setup, check nomenu        check only
program define rtmtools_setup, rclass
    version 16
    syntax [, PROFile INSTall CHECK NOMENU MENUonly]
    if "`menuonly'" != "" {
        * the line profile.do runs at start-up: add the menu, nothing else, no output
        capture _rtmtools_menu
        exit _rc
    }
    _rtm_util version
    di as text "{bf:rtmtools} `r(pkgversion)' setup"

    * ---- Stata version ----
    di as text _n "Stata: " as result "`c(stata_version)' (`c(flavor)')" _c
    if c(stata_version) < 16 {
        di as err "  rtmtools needs Stata 16 or later"
        exit 9
    }
    capture which svycal
    if _rc di as txt "  svycal not available: rtmweight calibrate uses engine(ipfraking); method(ebalance) needs svycal"
    else di as text "  svycal available"

    * ---- menu ----
    if "`nomenu'" == "" {
        capture _rtmtools_menu
        if _rc di as txt "note: the menu could not be added in this session (Stata error " _rc "; menus need Stata's windowed interface)"
        else di as text "User menu: " as result "User > RTM tools" as text " added for this session"
    }
    if "`profile'" != "" {
        _rtmtools_profile
    }

    * ---- dependencies ----
    di as text _n "Stata commands used by the package:"
    local missing ""
    foreach dep in survwgt ebalance ipfraking gsample geoinpoly shp2dta sreweight {
        capture which `dep'
        if _rc {
            di as text %-12s "`dep'" as err "missing" as text "   (ssc install `dep')"
            local missing "`missing' `dep'"
        }
        else di as text %-12s "`dep'" as result "installed"
    }
    capture mata: mata which mm_sample()
    if _rc {
        di as text %-12s "moremata" as err "missing" as text "   (ssc install moremata; needed by gsample)"
        local missing "`missing' moremata"
    }
    else di as text %-12s "moremata" as result "installed"
    return local missing "`=trim("`missing'")'"
    if "`install'" != "" & "`missing'" != "" {
        di as text _n "Installing from SSC: `missing'"
        foreach dep of local missing {
            capture noisily ssc install `dep', replace
            if _rc di as err "could not install `dep' (no internet connection, or SSC unreachable)"
        }
    }
    else if "`missing'" != "" di as text "Run {stata rtmtools_setup, install} to install the missing commands (needs an internet connection)."
    di as text "Which steps need which command: rtmweight nonresponse method(classes) needs survwgt and method(ebalance_nobase) needs ebalance (ebalance also cross-checks method(ebalance)); rtmweight calibrate engine(ipfraking) needs ipfraking; rtmsample draw needs gsample and moremata; geoinpoly and shp2dta are for rtmframe grid; sreweight gives the bounded logit distance by hand."

    di as text _n "Done. Type {stata help rtmtools} for the package overview."
end

* ---- the User menu -----------------------------------------------------------------------------
program define _rtmtools_menu
    version 16
    window menu append submenu "stUser" "RTM tools"
    window menu append item "RTM tools" "Start here (guided steps)" "rtmtools_start"
    window menu append item "RTM tools" "Run from the input workbook..." "db rtminput"
    window menu append separator "RTM tools"
    window menu append submenu "RTM tools" "Weights"
    window menu append item "Weights" "Base (design) weights..." "db rtmweight_base"
    window menu append item "Weights" "Nonresponse and attrition adjustment..." "db rtmweight_nonresponse"
    window menu append item "Weights" "Calibrate to population totals..." "db rtmweight_calibrate"
    window menu append item "Weights" "Trim extreme weights..." "db rtmweight_trim"
    window menu append item "Weights" "Household weights from person weights..." "db rtmweight_household"
    window menu append item "Weights" "Weighting report..." "db rtmweight_report"
    window menu append submenu "RTM tools" "Frame"
    window menu append item "Frame" "Check a list frame of areas..." "db rtmframe_list"
    window menu append item "Frame" "Grid frame from boundaries and a population raster..." "db rtmframe_grid"
    window menu append item "Frame" "Replacement cells..." "db rtmframe_replace"
    window menu append item "Frame" "Split large cells..." "db rtmframe_split"
    window menu append submenu "RTM tools" "Sample"
    window menu append item "Sample" "Sample size per domain..." "db rtmsample_size"
    window menu append item "Sample" "Allocate the sample across strata..." "db rtmsample_allocate"
    window menu append item "Sample" "Draw a sample from the frame..." "db rtmsample_draw"
    window menu append item "Sample" "Spatially spread draw from a grid frame..." "db rtmsample_grid"
    window menu append item "Sample" "Random digit dialing sample..." "db rtmsample_rdd"
    window menu append submenu "RTM tools" "Listing"
    window menu append item "Listing" "Listing forms for the selected areas..." "db rtmlist_prepare"
    window menu append item "Listing" "Import the completed listing..." "db rtmlist_import"
    window menu append item "RTM tools" "Estimate with the design..." "db rtmest"
    window menu append separator "RTM tools"
    window menu append item "RTM tools" "Dashboard and export folder" "rtmtools_dashboard"
    window menu append item "RTM tools" "Check dependencies" "rtmtools_setup, check nomenu"
    window menu append item "RTM tools" "Help and about rtmtools" "help rtmtools"
    window menu refresh
    di as text `"Start here: {stata rtmtools_start:the guided steps} (User > RTM tools > Start here)"'
end

* ---- append the menu lines to profile.do -------------------------------------------------------
program define _rtmtools_profile
    version 16
    local pdir "`c(sysdir_personal)'"
    capture mkdir "`pdir'"
    local pfile "`pdir'profile.do"
    local marker "* rtmtools menu (added by rtmtools_setup)"
    capture confirm file "`pfile'"
    if !_rc {
        tempname fh
        local has 0
        file open `fh' using "`pfile'", read text
        file read `fh' line
        while r(eof) == 0 {
            if strpos(`"`line'"', "rtmtools_setup") local has 1
            file read `fh' line
        }
        file close `fh'
        if `has' {
            di as text "profile.do already starts the RTM tools menu (`pfile')"
            exit
        }
    }
    di as text "The following lines would be appended to `pfile' so that the menu appears at every start:"
    di as result `"  `marker'"'
    di as result `"  capture rtmtools_setup, menuonly"'
    capture window stopbox rusure "Append the RTM tools menu to profile.do?"
    if _rc {
        if "`c(mode)'" == "batch" di as txt "(batch mode: no dialog; appending because the profile option was given)"
        else {
            di as text "Not appended."
            exit
        }
    }
    tempname fh
    quietly file open `fh' using "`pfile'", write text append
    file write `fh' _n "`marker'" _n "capture rtmtools_setup, menuonly" _n
    file close `fh'
    di as text "Appended to `pfile'. The menu will be there at the next start of Stata."
end
