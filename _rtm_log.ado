*! _rtm_log.ado  version 0.4.0  25oct2026  rtmtools
*! Run log for the live dashboard. Each event appends one JavaScript statement,
*!   RTM_RUNS.push({...});
*! to rtmtools_runs.js in the working directory (or the file in $RTM_DASHBOARD_FILE), which
*! rtmtools_dashboard.html reads and refreshes. Events: start, done (with every r() scalar, macro
*! and small matrix the command returned), error (with the return code), progress (a message).
*! Switched off by rtmtools_dashboard, off. Callers wrap every call in capture, so a logging
*! problem (a read-only folder, for example) never stops the analysis. Nothing leaves the machine.
*! Called before the dispatcher's return add, which empties the live r() it reads.
program define _rtm_log
    version 16
    gettoken what 0 : 0, parse(" ,")
    if "$RTM_DASHBOARD" == "off" exit
    syntax , [TOOL(string) CMD(string asis) RC(integer 0) MSG(string asis)]
    local file "$RTM_DASHBOARD_FILE"
    if `"`file'"' == "" local file "rtmtools_runs.js"
    local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
    local ts : di %tcCCYY-NN-DD!THH:MM:SS `now'
    if "`what'" == "start" global RTM_LOG_T0 = `now'
    local dur "null"
    if inlist("`what'", "done", "error") & "$RTM_LOG_T0" != "" local dur = string(($RTM_LOG_T0 <= `now') * (`now' - $RTM_LOG_T0) / 1000, "%12.1f")
    local ds = c(filename)
    local ds : subinstr local ds "\" "/", all
    if strpos("`ds'", "/") local ds = substr("`ds'", strrpos("`ds'", "/") + 1, .)
    _rtm_log_esc, in(`"`tool'"') out(tool_e)
    _rtm_log_esc, in(`"`cmd'"') out(cmd_e)
    _rtm_log_esc, in(`"`msg'"') out(msg_e)
    _rtm_log_esc, in(`"`ds'"') out(ds_e)
    local json `"{"ts":"`ts'","event":"`what'","tool":"`tool_e'","cmd":"`cmd_e'","dataset":"`ds_e'","N":`=c(N)',"rc":`rc',"seconds":`dur',"msg":"`msg_e'""'
    if "`what'" == "done" {
        local res ""
        local sc : r(scalars)
        foreach s of local sc {
            _rtm_log_num `=r(`s')', out(v_n)
            local res `"`res'"`s'":`v_n',"'
        }
        local mc : r(macros)
        foreach m of local mc {
            _rtm_log_esc, in(`"`r(`m')'"') out(v_e)
            local res `"`res'"`m'":"`v_e'","'
        }
        if `"`res'"' != "" local res = substr(`"`res'"', 1, length(`"`res'"') - 1)
        local json `"`json',"results":{`res'}"'
        local mats : r(matrices)
        local mj ""
        foreach M of local mats {
            tempname X
            matrix `X' = r(`M')
            local R = rowsof(`X')
            local C = colsof(`X')
            if `R' * `C' <= 1000 {
                local rn : rownames `X'
                local cn : colnames `X'
                local rj ""
                foreach r of local rn {
                    _rtm_log_esc, in(`"`r'"') out(r_e)
                    local rj `"`rj'"`r_e'","'
                }
                local cj ""
                foreach c of local cn {
                    _rtm_log_esc, in(`"`c'"') out(c_e)
                    local cj `"`cj'"`c_e'","'
                }
                local vj ""
                forvalues i = 1/`R' {
                    local row ""
                    forvalues j = 1/`C' {
                        _rtm_log_num `=el(`X', `i', `j')', out(v_n)
                        local row "`row'`v_n',"
                    }
                    local vj "`vj'[`=substr("`row'", 1, length("`row'") - 1)'],"
                }
                local mj `"`mj'"`M'":{"rows":[`=substr(`"`rj'"', 1, length(`"`rj'"') - 1)'],"cols":[`=substr(`"`cj'"', 1, length(`"`cj'"') - 1)'],"values":[`=substr("`vj'", 1, length("`vj'") - 1)']},"'
            }
        }
        if `"`mj'"' != "" local mj = substr(`"`mj'"', 1, length(`"`mj'"') - 1)
        local json `"`json',"matrices":{`mj'}"'
    }
    local json `"`json'}"'
    tempname fh
    quietly file open `fh' using `"`file'"', write text append
    file write `fh' `"RTM_RUNS.push(`json');"' _n
    file close `fh'
end

* escape a string for JSON (and for the compound quotes of the writer): \ " ' ` and control characters
program define _rtm_log_esc
    version 16
    syntax , [in(string asis)] out(name)
    local s `"`in'"'
    local s : subinstr local s `"\"' `"\\"', all
    local s : subinstr local s `"""' `"\""', all
    local s : subinstr local s `"'"' `"'"', all
    local s : subinstr local s "`" "`", all
    local s : subinstr local s "`=char(9)'" "\t", all
    local s : subinstr local s "`=char(10)'" "\n", all
    local s : subinstr local s "`=char(13)'" "", all
    c_local `out' `"`s'"'
end

* a number as JSON: null for missing, a leading zero before a decimal point
program define _rtm_log_num
    version 16
    gettoken v 0 : 0, parse(",")
    syntax , out(name)
    if missing(`v') {
        c_local `out' "null"
        exit
    }
    local s = string(`v', "%18.0g")
    if substr("`s'", 1, 1) == "." local s "0`s'"
    else if substr("`s'", 1, 2) == "-." local s "-0`=substr("`s'", 2, .)'"
    c_local `out' "`s'"
end
