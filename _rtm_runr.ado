*! _rtm_runr.ado  version 0.1.0  24oct2026  rtmtools
*! The R bridge: find Rscript, run one of the package's R scripts in the background with a
*! file of arguments, and read its status file. Data travel as .dta files (haven). Nothing is
*! sent anywhere: Rscript runs on this machine.
*!
*! syntax: _rtm_runr, script(name.R) args(filename) status(filename) [quietly]
*!         _rtm_runr find [, path(string) save]      -> r(rscript) (empty if not found)
program define _rtm_runr, rclass
    version 16
    gettoken first : 0, parse(" ,")
    if "`first'" == "find" {
        gettoken first 0 : 0, parse(" ,")
        _rtm_runr_find `0'
        return add
        exit
    }
    syntax, SCRipt(string) ARGS(string) STATus(string) [QUIetly]
    _rtm_runr_find
    local rscript "`r(rscript)'"
    if "`rscript'" == "" {
        di as err "R was not found. This step needs R; the Stata-only steps work without it."
        di as err "Install R from https://cran.r-project.org and, if Rscript is not in a standard location,"
        di as err `"run {bf:rtmtools_setup, path("...path to Rscript...")} once."'
        exit 199
    }
    quietly findfile `script'
    local scriptpath "`r(fn)'"
    capture erase "`status'"
    if "`quietly'" == "" di as txt "running R (`script') ..."
    capture _rtm_export message, text("running R: `script'")
    if "`c(os)'" == "Windows" {
        shell "`rscript'" --vanilla "`scriptpath'" "`args'"
    }
    else {
        shell "`rscript'" --vanilla "`scriptpath'" "`args'" > /dev/null 2>&1
    }
    capture confirm file "`status'"
    if _rc {
        di as err "R did not produce a status file; Rscript may have failed to start."
        di as err `"Rscript used: `rscript'. Run {bf:rtmtools_setup, check} to test the R installation."'
        exit 199
    }
    tempname fh
    file open `fh' using "`status'", read text
    file read `fh' line
    local st `"`line'"'
    local msg ""
    file read `fh' line
    while r(eof) == 0 {
        local msg `"`msg'`line' "'
        file read `fh' line
    }
    file close `fh'
    * R messages may contain quotes and parentheses: keep them in compound quotes throughout
    local msg = strtrim(`"`msg'"')
    return local status `"`st'"'
    return local message `"`msg'"'
    if `"`st'"' != "ok" {
        di as err `"R reported an error: `msg'"'
        exit 199
    }
    if "`quietly'" == "" & `"`msg'"' != "" di as txt `"`msg'"'
end

* ---- locate Rscript: saved setting, then standard places --------------------------------------
program define _rtm_runr_find, rclass
    version 16
    syntax [, PATH(string) SAVE]
    local setfile "`c(sysdir_personal)'rtmtools_rscript.txt"
    if "`path'" != "" {
        capture confirm file "`path'"
        if _rc {
            di as err `"Rscript not found at "`path'""'
            exit 601
        }
        if "`save'" != "" {
            capture mkdir "`c(sysdir_personal)'"
            tempname fh
            quietly file open `fh' using "`setfile'", write text replace
            file write `fh' "`path'" _n
            file close `fh'
            di as txt `"Rscript path saved to `setfile'"'
        }
        return local rscript "`path'"
        exit
    }
    local found ""
    * saved setting
    capture confirm file "`setfile'"
    if !_rc {
        tempname fh
        file open `fh' using "`setfile'", read text
        file read `fh' line
        file close `fh'
        capture confirm file "`line'"
        if !_rc local found "`line'"
    }
    * standard locations (an exit inside a foreach does not leave the program, so a flag is used)
    if "`found'" == "" & "`c(os)'" == "Windows" {
        local cands : dir "C:\Program Files\R" dirs "R-*", respectcase
        local best ""
        foreach d of local cands {
            local best "`d'"
        }
        if "`best'" != "" {
            local cand "C:\Program Files\R\`best'\bin\Rscript.exe"
            capture confirm file "`cand'"
            if !_rc local found "`cand'"
        }
    }
    else if "`found'" == "" {
        foreach cand in "/usr/local/bin/Rscript" "/opt/homebrew/bin/Rscript" "/Library/Frameworks/R.framework/Resources/bin/Rscript" "/usr/bin/Rscript" {
            capture confirm file "`cand'"
            if !_rc & "`found'" == "" local found "`cand'"
        }
    }
    return local rscript "`found'"
end
