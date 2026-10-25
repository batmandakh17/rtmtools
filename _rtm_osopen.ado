*! _rtm_osopen.ado  version 0.6.1  25oct2026  rtmtools
*! Opens a local file (a page, a workbook, a document) with the operating system's default
*! application: Windows through the shell's file handler, Mac through open, Linux through xdg-open.
*! Nothing is opened in batch mode (c(mode) == "batch") unless force is given; nothing leaves the
*! machine. The dashboard uses the same calls (rtmtools_dashboard).
program define _rtm_osopen
    version 16
    gettoken file 0 : 0
    syntax [, FORCE]
    if `"`file'"' == "" {
        di as err "_rtm_osopen: a file name is required"
        exit 100
    }
    capture confirm file `"`file'"'
    if _rc {
        di as err `"file not found: `file'"'
        exit 601
    }
    if "`c(mode)'" == "batch" & "`force'" == "" {
        di as text `"(batch mode: `file' written, not opened)"'
        exit
    }
    if "`c(os)'" == "Windows" {
        local winpath = subinstr(`"`file'"', "/", "\", .)
        capture winexec rundll32 url.dll,FileProtocolHandler "`winpath'"
    }
    else if strpos("`c(machine_type)'", "Mac") capture shell open "`file'"
    else capture shell xdg-open "`file'" > /dev/null 2>&1 &
end
