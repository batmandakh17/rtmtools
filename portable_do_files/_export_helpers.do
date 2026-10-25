* _export_helpers.do  --  the export helpers of the rtmtools portable do-files, version 0.5.0 (25 October 2026)
* A copy of the package's rtmx.ado with its programs renamed rtmx_* so that the portable
* do-files depend on nothing but this file. Run it once at the top of a do-file:  run "_export_helpers.do"
* It defines: rtmx_start, rtmx_table, rtmx_setting, rtmx_message, rtmx_wstage, rtmx_done.
* Globals it reads: RTM_EXPORT ("off" disables), RTM_EXPORT_DIR (folder), RTM_EXPORT_TEMPLATE (the
* Excel display template to copy into each run), RTM_EXPORT_SOURCE ("dofile").
capture program drop rtmx rtmx_start rtmx_table rtmx_setting rtmx_message rtmx_wstage rtmx_done rtmx_dropframes rtmx_num
capture mata: mata drop rtmx_jsesc() rtmx_cmdclean() rtmxrtmx_frval_str() rtmx_frame_json()
*! _export_helpers.do  version 0.5.0  25oct2026  rtmtools portable do-files
*! The export of every run (schema rtm-export-1.0): one folder per run under the export folder
*! ($RTM_EXPORT_DIR, default rtm_exports in the working folder) with manifest.json, manifest.csv,
*! one CSV per table, the Excel display workbook filled from the same tables, and one line
*! appended to rtm_exports.js, the live index the dashboard reads. Called by the dispatchers:
*!   rtmx start, workflow(weights) step(nonresponse) cmd(`"..."')
*!   rtmx table, name(weight_stages) frame(_rtmx_ws)        (queued; the frame is dropped after writing)
*!   rtmx setting, key(method) value(logit) [source("HFPS Vol. 2 p. 10")]
*!   rtmx message, text("...")
*!   rtmx wstage, frame(_rtmx_ws) stage("...") var(w) [if] [in] [ntrimmed(#)]   (one weight_stages row)
*!   rtmx done [, rc(#)]       (reads the live r() first: call it before return add)
*! Switched off by rtmtools_dashboard, off ($RTM_EXPORT == "off"). Nothing leaves the machine.
*! Every call is wrapped in capture by the callers, so an export problem never stops the analysis.
program define rtmx
    version 16
    gettoken what 0 : 0, parse(" ,")
    if "`what'" == "" exit
    rtmx_`what' `0'
end

* ---- start: remember the run and empty the queues --------------------------------------------
program define rtmx_start
    version 16
    syntax , WORKflow(string) STEP(string) [CMD(string)]
    if "$RTM_EXPORT" == "off" exit
    capture frame drop _rtmx_settings
    capture frame drop _rtmx_messages
    capture frame drop _rtmx_tables
    frame create _rtmx_settings str64 key strL value str244 source
    frame create _rtmx_messages strL text
    frame create _rtmx_tables str32 name str32 frame
    global RTM_EXP_WORKFLOW "`workflow'"
    global RTM_EXP_STEP "`step'"
    global RTM_EXP_CMD `"`cmd'"'
    global RTM_EXP_T0 = clock("`c(current_date)' `c(current_time)'", "DMY hms")
    local ts : di %tcCCYY-NN-DD!THH:MM:SS $RTM_EXP_T0
    global RTM_EXP_STARTED "`ts'"
    global RTM_EXP_DATASET = c(filename)
    global RTM_EXP_N = c(N)
    global RTM_EXP_K = c(k)
end

program define rtmx_table
    version 16
    syntax , NAME(string) FRAME(name)
    if "$RTM_EXPORT" == "off" {
        capture frame drop `frame'
        exit
    }
    capture confirm frame _rtmx_tables
    if _rc {
        capture frame drop `frame'
        exit
    }
    frame post _rtmx_tables ("`name'") ("`frame'")
end

program define rtmx_setting
    version 16
    syntax , KEY(string) [VALUE(string) SOURCE(string)]
    if "$RTM_EXPORT" == "off" exit
    capture confirm frame _rtmx_settings
    if _rc exit
    frame post _rtmx_settings ("`key'") (`"`value'"') (`"`source'"')
end

program define rtmx_message
    version 16
    syntax , TEXT(string)
    if "$RTM_EXPORT" == "off" exit
    capture confirm frame _rtmx_messages
    if _rc exit
    frame post _rtmx_messages (`"`text'"')
end

* ---- one row of the weight_stages table (schema columns) ------------------------------------
* creates the frame if it does not exist; statistics over positive weights only, as in the reports
program define rtmx_wstage
    version 16
    syntax , FRAME(name) STAGE(string) VAR(varname numeric) [COND(string) NTRIMmed(integer -1)]
    if "$RTM_EXPORT" == "off" exit
    capture confirm frame `frame'
    if _rc {
        frame create `frame' str64 stage str32 variable double(n sum min p1 p5 p25 p50 p75 p95 p99 max mean cv kish_deff n_trimmed n_zero)
    }
    local sel "`cond'"
    local cond "`var' > 0 & !missing(`var')"
    if `"`sel'"' != "" local cond "`cond' & (`sel')"
    local zcond "`var' == 0"
    if `"`sel'"' != "" local zcond "`zcond' & (`sel')"
    quietly count if `zcond'
    local nz = r(N)
    quietly count if `cond'
    if r(N) == 0 {
        frame post `frame' ("`stage'") ("`var'") (0) (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) (cond(`ntrimmed' < 0, ., `ntrimmed')) (`nz')
        exit
    }
    quietly summarize `var' if `cond'
    local n = r(N)
    local sum = r(sum)
    local mean = r(mean)
    local min = r(min)
    local max = r(max)
    local cv = r(sd) / r(mean)
    _pctile `var' if `cond', percentiles(1 5 25 50 75 95 99)
    frame post `frame' ("`stage'") ("`var'") (`n') (`sum') (`min') (r(r1)) (r(r2)) (r(r3)) (r(r4)) (r(r5)) (r(r6)) (r(r7)) ///
        (`max') (`mean') (`cv') (1 + `cv'^2) (cond(`ntrimmed' < 0, ., `ntrimmed')) (`nz')
end

* ---- done: write the run ----------------------------------------------------------------------
program define rtmx_done
    version 16
    * the live r() of the command, read before anything else changes it
    local rsc : r(scalars)
    local rma : r(macros)
    foreach s of local rsc {
        local rv_`s' = r(`s')
    }
    foreach m of local rma {
        local rm_`m' `"`r(`m')'"'
    }
    syntax [, RC(integer 0)]
    if "$RTM_EXPORT" == "off" {
        rtmx_dropframes
        exit
    }
    capture confirm frame _rtmx_tables
    if _rc exit
    local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
    local finished : di %tcCCYY-NN-DD!THH:MM:SS `now'
    local status = cond(`rc' == 0, "done", "error")
    * ---- folder ----
    local dir "$RTM_EXPORT_DIR"
    if `"`dir'"' == "" local dir "rtm_exports"
    local dir : subinstr local dir "\" "/", all
    if !regexm(`"`dir'"', "^(/|[A-Za-z]:)") local dir `"`c(pwd)'/`dir'"'
    local dir : subinstr local dir "//" "/", all
    if substr(`"`dir'"', -1, 1) == "/" local dir = substr(`"`dir'"', 1, length(`"`dir'"') - 1)
    capture mkdir `"`dir'"'
    local stamp : di %tcCCYYNNDD!-HHMMSS `now'
    local wf "$RTM_EXP_WORKFLOW"
    local st "$RTM_EXP_STEP"
    local run "`stamp'_`wf'_$RTM_EXPORT_SOURCE"
    local rdir `"`dir'/`run'"'
    capture mkdir `"`rdir'"'
    * a second run in the same second: add a letter
    local letter 0
    while `letter' < 26 {
        capture confirm file `"`rdir'/manifest.json"'
        if _rc continue, break
        local ++letter
        local run "`stamp'`=char(96 + `letter')'_`wf'_$RTM_EXPORT_SOURCE"
        local rdir `"`dir'/`run'"'
        capture mkdir `"`rdir'"'
    }
    local toolversion "rtmtools portable do-files 0.5.0"
    local software "Stata `c(stata_version)' `c(flavor)', `c(machine_type)'"
    local ds "$RTM_EXP_DATASET"
    local ds : subinstr local ds "\" "/", all
    if strpos(`"`ds'"', "/") local ds = substr(`"`ds'"', strrpos(`"`ds'"', "/") + 1, .)
    local seconds = string(max(0, `now' - $RTM_EXP_T0) / 1000, "%12.1f")

    * ---- tables: CSV files, then their names for the manifest ----
    local tablist ""
    quietly frame _rtmx_tables: count
    local ntab = r(N)
    forvalues i = 1/`ntab' {
        local tn = _frval(_rtmx_tables, name, `i')
        local tf = _frval(_rtmx_tables, frame, `i')
        capture confirm frame `tf'
        if _rc continue
        quietly frame `tf': count
        if r(N) == 0 continue
        capture frame `tf': export delimited using `"`rdir'/`tn'.csv"', replace nolabel
        if _rc continue
        local tablist "`tablist' `tn'"
    }
    local tablist = trim("`tablist'")

    * ---- manifest.json ----
    mata: st_local("cmd_e", rtmx_jsesc(rtmx_cmdclean(st_global("RTM_EXP_CMD"))))
    mata: st_local("ds_e", rtmx_jsesc(st_local("ds")))
    mata: st_local("run_e", rtmx_jsesc(st_local("run")))
    local settings_j ""
    quietly frame _rtmx_settings: count
    local nset = r(N)
    forvalues i = 1/`nset' {
        local k = _frval(_rtmx_settings, key, `i')
        mata: st_local("v_e", rtmx_jsesc(rtmx_frval_str("_rtmx_settings", "value", `i')))
        mata: st_local("s_e", rtmx_jsesc(rtmx_frval_str("_rtmx_settings", "source", `i')))
        mata: st_local("k_e", rtmx_jsesc(st_local("k")))
        local settings_j `"`settings_j'"`k_e'":{"value":"`v_e'","source":"`s_e'"},"'
    }
    if `"`settings_j'"' != "" local settings_j = substr(`"`settings_j'"', 1, length(`"`settings_j'"') - 1)
    local summary_j ""
    foreach s of local rsc {
        rtmx_num `rv_`s'', out(v)
        local summary_j `"`summary_j'"`s'":`v',"'
    }
    foreach m of local rma {
        mata: st_local("v_e", rtmx_jsesc(st_local("rm_`m'")))
        local summary_j `"`summary_j'"`m'":"`v_e'","'
    }
    if `"`summary_j'"' != "" local summary_j = substr(`"`summary_j'"', 1, length(`"`summary_j'"') - 1)
    local tables_j ""
    foreach t of local tablist {
        local tables_j `"`tables_j'"`t'":"`t'.csv","'
    }
    if `"`tables_j'"' != "" local tables_j = substr(`"`tables_j'"', 1, length(`"`tables_j'"') - 1)
    local msg_j ""
    quietly frame _rtmx_messages: count
    local nmsg = r(N)
    forvalues i = 1/`nmsg' {
        mata: st_local("v_e", rtmx_jsesc(rtmx_frval_str("_rtmx_messages", "text", `i')))
        local msg_j `"`msg_j'"`v_e'","'
    }
    if `"`msg_j'"' != "" local msg_j = substr(`"`msg_j'"', 1, length(`"`msg_j'"') - 1)
    local privacy "Identifiers only: no names, addresses or phone numbers. Nothing leaves this computer."
    local json `"{"schema":"rtm-export-1.0","run_id":"`run_e'","source":"$RTM_EXPORT_SOURCE","tool_version":"`toolversion'","software":"`software'","workflow":"`wf'","step":"`st'","started":"$RTM_EXP_STARTED","finished":"`finished'","status":"`status'","rc":`rc',"seconds":`seconds',"input":{"file":"`ds_e'","rows":$RTM_EXP_N,"columns":$RTM_EXP_K},"command":"`cmd_e'","settings":{`settings_j'},"summary":{`summary_j'},"tables":{`tables_j'},"map":null,"messages":[`msg_j'],"privacy":"`privacy'"}"'
    tempname fh
    quietly file open `fh' using `"`rdir'/manifest.json"', write text replace
    file write `fh' `"`json'"' _n
    file close `fh'

    * ---- manifest.csv: key,value rows ----
    capture frame drop _rtmx_manifest
    frame create _rtmx_manifest str64 key strL value
    frame post _rtmx_manifest ("schema") ("rtm-export-1.0")
    frame post _rtmx_manifest ("run_id") ("`run'")
    frame post _rtmx_manifest ("source") ("$RTM_EXPORT_SOURCE")
    frame post _rtmx_manifest ("tool_version") ("`toolversion'")
    frame post _rtmx_manifest ("software") ("`software'")
    frame post _rtmx_manifest ("workflow") ("`wf'")
    frame post _rtmx_manifest ("step") ("`st'")
    frame post _rtmx_manifest ("started") ("$RTM_EXP_STARTED")
    frame post _rtmx_manifest ("finished") ("`finished'")
    frame post _rtmx_manifest ("status") ("`status'")
    frame post _rtmx_manifest ("rc") ("`rc'")
    frame post _rtmx_manifest ("seconds") ("`seconds'")
    frame post _rtmx_manifest ("input_file") (`"`ds'"')
    frame post _rtmx_manifest ("input_rows") ("$RTM_EXP_N")
    frame post _rtmx_manifest ("input_columns") ("$RTM_EXP_K")
    mata: st_local("cmd_c", rtmx_cmdclean(st_global("RTM_EXP_CMD")))
    frame post _rtmx_manifest ("command") (`"`cmd_c'"')
    forvalues i = 1/`nset' {
        local k = _frval(_rtmx_settings, key, `i')
        mata: st_local("v", rtmx_frval_str("_rtmx_settings", "value", `i'))
        mata: st_local("s", rtmx_frval_str("_rtmx_settings", "source", `i'))
        frame post _rtmx_manifest ("setting_`k'") (`"`v'"')
        if `"`s'"' != "" frame post _rtmx_manifest ("source_`k'") (`"`s'"')
    }
    foreach s of local rsc {
        frame post _rtmx_manifest ("summary_`s'") (string(`rv_`s'', "%18.0g"))
    }
    foreach m of local rma {
        frame post _rtmx_manifest ("summary_`m'") (`"`rm_`m''"')
    }
    foreach t of local tablist {
        frame post _rtmx_manifest ("table_`t'") ("`t'.csv")
    }
    forvalues i = 1/`nmsg' {
        mata: st_local("v", rtmx_frval_str("_rtmx_messages", "text", `i'))
        frame post _rtmx_manifest ("message_`i'") (`"`v'"')
    }
    frame post _rtmx_manifest ("privacy") ("`privacy'")
    capture frame _rtmx_manifest: export delimited using `"`rdir'/manifest.csv"', replace

    * ---- live index: manifest plus the tables (up to 2,000 rows each) as JSON ----
    local idx `"`dir'/rtm_exports.js"'
    capture confirm file `"`idx'"'
    if _rc {
        quietly file open `fh' using `"`idx'"', write text replace
        file write `fh' "// rtmtools export index: one RTM_EXPORTS.push({...}); per run, written by the commands" _n
        file close `fh'
    }
    local head = substr(`"`json'"', 1, length(`"`json'"') - 1)
    quietly file open `fh' using `"`idx'"', write text append
    file write `fh' `"RTM_EXPORTS.push(`head',"data":{"'
    file close `fh'
    local first 1
    forvalues i = 1/`ntab' {
        local tn = _frval(_rtmx_tables, name, `i')
        local tf = _frval(_rtmx_tables, frame, `i')
        if !`: list tn in tablist' continue
        quietly frame `tf': count
        local nr = r(N)
        quietly file open `fh' using `"`idx'"', write text append
        if !`first' file write `fh' ","
        file write `fh' `""`tn'":"'
        file close `fh'
        if `nr' > 2000 {
            quietly file open `fh' using `"`idx'"', write text append
            file write `fh' `"{"file":"`tn'.csv","rows":`nr'}"'
            file close `fh'
        }
        else {
            frame `tf': mata: rtmx_frame_json(`"`idx'"')
        }
        local first 0
    }
    quietly file open `fh' using `"`idx'"', write text append
    file write `fh' "}});" _n
    file close `fh'

    * ---- Excel display workbook: the template filled with the same tables ----
    local tpl "$RTM_EXPORT_TEMPLATE"
    capture confirm file `"`tpl'"'
    if !_rc {
        local xl `"`rdir'/rtm_display.xlsx"'
        capture copy `"`tpl'"' `"`xl'"', replace
        if !_rc {
            capture frame _rtmx_manifest: export excel using `"`xl'"', sheet("manifest", modify) firstrow(variables) nolabel
            forvalues i = 1/`ntab' {
                local tn = _frval(_rtmx_tables, name, `i')
                local tf = _frval(_rtmx_tables, frame, `i')
                if !`: list tn in tablist' continue
                capture frame `tf': export excel using `"`xl'"', sheet("`tn'", modify) firstrow(variables) nolabel
            }
        }
    }
    rtmx_dropframes
    global RTM_EXP_LAST `"`rdir'"'
    if `rc' == 0 di as text `"(run exported to `run'; dashboard and Excel display read it)"'
end

* drop every queued table frame and the queues
program define rtmx_dropframes
    version 16
    capture confirm frame _rtmx_tables
    if !_rc {
        quietly frame _rtmx_tables: count
        forvalues i = 1/`r(N)' {
            local tf = _frval(_rtmx_tables, frame, `i')
            capture frame drop `tf'
        }
    }
    foreach f in _rtmx_tables _rtmx_settings _rtmx_messages _rtmx_manifest {
        capture frame drop `f'
    }
end

* a number as JSON: null for missing, a leading zero before a decimal point
program define rtmx_num
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

version 16
mata:
// JSON escaping (backslash, double quote, apostrophe and backtick for Stata's quotes, control characters)
string scalar rtmx_jsesc(string scalar s)
{
    s = subinstr(s, "\", "\\")
    s = subinstr(s, char(34), "\" + char(34))
    s = subinstr(s, char(39), "'")
    s = subinstr(s, char(96), "`")
    s = subinstr(s, char(9), "\t")
    s = subinstr(s, char(10), "\n")
    s = subinstr(s, char(13), "")
    return(s)
}

// tidy the spacing the dispatchers leave around the subcommand
string scalar rtmx_cmdclean(string scalar s)
{
    s = subinstr(s, " ,", ",")
    while (strpos(s, "  ")) s = subinstr(s, "  ", " ")
    return(strtrim(s))
}

// a string value of a frame, row i (strL safe)
string scalar rtmx_frval_str(string scalar fr, string scalar var, real scalar i)
{
    string scalar cur, v
    cur = st_framecurrent()
    st_framecurrent(fr)
    v = st_sdata(i, var)
    st_framecurrent(cur)
    return(v)
}

// the current frame as a JSON object {"cols":[...],"rows":[[...],...]} appended to a file
void rtmx_frame_json(string scalar path)
{
    real scalar fh, i, j, N, K
    string rowvector vars
    string scalar line, v
    real scalar isstr, x
    N = st_nobs()
    K = st_nvar()
    vars = J(1, K, "")
    for (j = 1; j <= K; j++) vars[j] = st_varname(j)
    fh = fopen(path, "a")
    line = "{" + char(34) + "cols" + char(34) + ":["
    for (j = 1; j <= K; j++) {
        line = line + (j > 1 ? "," : "") + char(34) + rtmx_jsesc(vars[j]) + char(34)
    }
    line = line + "]," + char(34) + "rows" + char(34) + ":["
    fwrite(fh, line)
    for (i = 1; i <= N; i++) {
        line = (i > 1 ? ",[" : "[")
        for (j = 1; j <= K; j++) {
            isstr = st_isstrvar(j)
            if (isstr) {
                v = st_sdata(i, j)
                line = line + (j > 1 ? "," : "") + char(34) + rtmx_jsesc(v) + char(34)
            }
            else {
                x = st_data(i, j)
                if (x >= .) line = line + (j > 1 ? "," : "") + "null"
                else {
                    v = strofreal(x, "%18.0g")
                    if (substr(v, 1, 1) == ".") v = "0" + v
                    else if (substr(v, 1, 2) == "-.") v = "-0" + substr(v, 2, .)
                    line = line + (j > 1 ? "," : "") + v
                }
            }
        }
        fwrite(fh, line + "]")
    }
    fwrite(fh, "]}")
    fclose(fh)
}
end
