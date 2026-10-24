*! _rtmsample_label.ado  version 0.3.0  24oct2026  rtmtools
*! A readable label per observation from one or more strata variables (value labels decoded)
program define _rtmsample_label
    version 16
    syntax [varlist(default=none)], touse(varname) generate(name)
    quietly gen str244 `generate' = ""
    if "`varlist'" == "" {
        quietly replace `generate' = "all" if `touse'
        exit
    }
    local k 0
    foreach v of local varlist {
        local ++k
        tempvar part
        capture confirm string variable `v'
        if !_rc quietly gen str244 `part' = `v'
        else {
            local vl : value label `v'
            if "`vl'" != "" quietly decode `v', gen(`part')
            else quietly gen str244 `part' = string(`v')
        }
        quietly replace `generate' = `generate' + cond(`k' > 1, " ", "") + `part' if `touse'
    }
end
