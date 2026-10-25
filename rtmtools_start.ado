*! rtmtools_start.ado  version 0.6.1  25oct2026  rtmtools
*! The guided route for someone who does not know Stata: rtmtools_start opens the Start-here page
*! (help rtmtools_start), whose numbered steps are links that run the commands.
*!   rtmtools_start                    the page
*!   rtmtools_start, open(file)        open a file (the workbook, a summary) with the operating system
*!   rtmtools_start, summary           open the most recent run summary written by rtminput
*!   rtmtools_start, folder            show the current folder, where the workbook and the outputs live
program define rtmtools_start
    version 16
    syntax [, OPEN(string) SUMmary FOLDER]
    if `"`open'"' != "" {
        _rtm_osopen `"`open'"'
        exit
    }
    if "`summary'" != "" {
        local f "$RTMTOOLS_LAST_SUMMARY"
        capture confirm file `"`f'"'
        if _rc {
            * the newest summary in rtm_outputs of the current folder: the names end in a time stamp
            local list : dir "rtm_outputs" files "rtm_summary_*.html"
            local list : list sort list
            local f : word `: word count `list'' of `list'
            local f = subinstr(`"`f'"', `"""', "", .)
            if "`f'" != "" local f "rtm_outputs/`f'"
        }
        if "`f'" == "" {
            di as text "no run summary yet: run a check, a sampling or a weights step first (help rtmtools_start)"
            exit
        }
        di as text `"opening `f'"'
        _rtm_osopen `"`f'"'
        exit
    }
    if "`folder'" != "" {
        di as text `"Current folder: {bf:`c(pwd)'}"'
        di as text `"This is where the input workbook is looked for and rtm_outputs/ is written. To change it: File > Change Working Directory..., or type {bf:cd "the folder"}."'
        exit
    }
    help rtmtools_start
end
