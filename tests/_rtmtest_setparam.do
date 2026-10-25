* _rtmtest_setparam.do -- test helper: replaces the value of a parameter line "local name value // comment"
* in a copy of a portable do-file (run by test_portable.do)
capture program drop _rtmtest_setparam
program define _rtmtest_setparam
    * replaces the value of a parameter line "local name   value   // comment" in the do-file copy
    args infile outfile name value
    tempname fi fo
    file open `fi' using "`infile'", read text
    file open `fo' using "`outfile'", write text replace
    file read `fi' line
    while r(eof) == 0 {
        if regexm(`"`line'"', "^local `name' ") {
            local cmt ""
            if strpos(`"`line'"', "//") local cmt = substr(`"`line'"', strpos(`"`line'"', "//"), .)
            file write `fo' `"local `name' `value'   `cmt'"' _n
        }
        else file write `fo' `"`macval(line)'"' _n
        file read `fi' line
    }
    file close `fi'
    file close `fo'
end
