*! rtmweight_report.ado  version 0.1.0  24oct2026  rtmtools
*! Weighting report: the weight variables of each stage side by side, the step-to-step
*! adjustment factors, Kish's design effect from unequal weights (1 + CV^2), optional checks
*! of calibrated totals against targets, graphs, and export to Excel (putexcel) and to a Word
*! method note (putdocx) that lists every recorded rtmweight step and its source.
*! Documentation guidance: UN 2008 ch. 5 (store each weight stage separately, record
*! deviations); CWM 2021 section 8.2 (document the calculation of weights); HFPS Vol. 2 p. 12.
program define rtmweight_report, rclass
    version 16
    syntax varlist(numeric min=1) [if] [in] [, TOTals(string) BY(varname) EXcel(string) DOCX(string) GRaph NOTEs]
    marksample touse, novarlist
    local K : word count `varlist'

    * ---- summary table ----
    tempname S
    matrix `S' = J(`K', 9, .)
    local i 0
    local rnames ""
    foreach w of local varlist {
        local ++i
        _rtm_util wsum `w' if `touse'
        if r(N) > 0 {
            matrix `S'[`i', 1] = r(N)
            matrix `S'[`i', 2] = r(sum)
            matrix `S'[`i', 3] = r(mean)
            matrix `S'[`i', 4] = r(min)
            matrix `S'[`i', 5] = r(p50)
            matrix `S'[`i', 6] = r(max)
            matrix `S'[`i', 7] = r(cv)
            matrix `S'[`i', 8] = r(kish)
        }
        matrix `S'[`i', 9] = r(nneg)
        local rnames "`rnames' `w'"
    }
    matrix rownames `S' = `rnames'
    matrix colnames `S' = N sum mean min p50 max cv kish n_negative
    di as text _n "Weighting report: " as result "`K'" as text " weight variable(s), " _c
    quietly count if `touse'
    di as result r(N) as text " observations in the sample"
    _rtm_util whead
    foreach w of local varlist {
        local lab : variable label `w'
        _rtm_util wline `w' if `touse', label("`w'")
    }
    di as text "{hline 100}"
    di as text "N counts positive weights; CV is the coefficient of variation; 1+CV2 is Kish's design effect from unequal weights."

    * ---- step-to-step factors ----
    tempname F
    if `K' > 1 {
        matrix `F' = J(`K' - 1, 5, .)
        local fnames ""
        di as text _n "Adjustment factors between consecutive stages (later weight / earlier weight, where both are positive)"
        di as text %-30s "step" %8s "N" %10s "min" %10s "median" %10s "max" %10s "sum ratio"
        forvalues j = 2/`K' {
            local a : word `=`j'-1' of `varlist'
            local b : word `j' of `varlist'
            tempvar f
            quietly gen double `f' = `b' / `a' if `touse' & `a' > 0 & `b' > 0
            quietly summarize `f', detail
            local N = r(N)
            quietly summarize `a' if `touse' & `a' > 0 & `b' > 0
            local sa = r(sum)
            quietly summarize `b' if `touse' & `a' > 0 & `b' > 0
            local sb = r(sum)
            quietly summarize `f', detail
            matrix `F'[`j'-1, 1] = r(N)
            matrix `F'[`j'-1, 2] = r(min)
            matrix `F'[`j'-1, 3] = r(p50)
            matrix `F'[`j'-1, 4] = r(max)
            matrix `F'[`j'-1, 5] = `sb' / `sa'
            local fnames "`fnames' `a'_to_`b'"
            di as text %-30s "`a' to `b'" as result %8.0fc r(N) %10.4f r(min) %10.4f r(p50) %10.4f r(max) %10.4f `sb' / `sa'
            drop `f'
        }
        matrix rownames `F' = `fnames'
        matrix colnames `F' = N min p50 max sum_ratio
        return matrix factors = `F', copy
    }

    * ---- calibrated totals against targets (last weight) ----
    local last : word `K' of `varlist'
    if "`totals'" != "" {
        tempname T
        local nrow = wordcount("`totals'")
        matrix `T' = J(`nrow', 3, .)
        local tn ""
        local i 0
        local maxrel 0
        di as text _n "Totals with {bf:`last'} against targets"
        di as text %-18s "category" %14s "target" %14s "achieved" %10s "rel.diff"
        foreach tok of local totals {
            local ++i
            if !regexm("`tok'", "^([0-9]+)\.([A-Za-z_][A-Za-z0-9_]*)=([0-9.eE+-]+)$") {
                di as err `"cannot read the total "`tok'"; write totals as level.variable=number"'
                exit 198
            }
            local lev = regexs(1)
            local var = regexs(2)
            local val = regexs(3)
            quietly summarize `last' if `touse' & `var' == `lev'
            local ach = r(sum)
            local rd = (`ach' - `val') / `val'
            if abs(`rd') > `maxrel' local maxrel = abs(`rd')
            matrix `T'[`i', 1] = `val'
            matrix `T'[`i', 2] = `ach'
            matrix `T'[`i', 3] = `rd'
            local tn "`tn' `var'_`lev'"
            di as text %-18s "`var' == `lev'" as result %14.1fc `val' %14.1fc `ach' %10.5f `rd'
        }
        matrix rownames `T' = `tn'
        matrix colnames `T' = target achieved rel_diff
        return matrix totals = `T', copy
        return scalar max_rel_diff = `maxrel'
    }

    * ---- by-group: sums and Kish of the last weight ----
    if "`by'" != "" {
        di as text _n "{bf:`last'} by `by'"
        di as text %-16s "`by'" %8s "N" %14s "sum" %10s "min" %10s "max" %8s "1+CV2"
        quietly levelsof `by' if `touse', local(lv)
        foreach l of local lv {
            _rtm_util wsum `last' if `touse' & `by' == `l'
            if r(N) > 0 di as text %-16s "`l'" as result %8.0fc r(N) %14.1fc r(sum) %10.3f r(min) %10.3f r(max) %8.3f r(kish)
        }
    }

    * ---- graph ----
    if "`graph'" != "" {
        local plots ""
        local i 0
        foreach w of local varlist {
            local ++i
            local plots "`plots' (kdensity `w' if `touse' & `w' > 0, lwidth(medium))"
        }
        local leg ""
        local i 0
        foreach w of local varlist {
            local ++i
            local leg `"`leg' `i' "`w'""'
        }
        twoway `plots', legend(order(`leg') rows(1)) xtitle("weight") ytitle("density") ///
            title("Weight distributions by stage", size(medium)) name(rtmweight_report, replace)
    }

    * ---- recorded steps ----
    local steps ""
    foreach s in base nonresponse calibrate trim {
        local c : char _dta[rtm_`s']
        if `"`c'"' != "" {
            local st : char _dta[rtm_`s'_stamp]
            local steps `"`steps' `s'"'
            local cmd_`s' `"`c'"'
            local stamp_`s' `"`st'"'
        }
    }
    * each weight made by rtmweight carries its own command (variable characteristics); the
    * dataset-level step record is the fallback for weights made before version 0.1.0's record
    local nvrec 0
    foreach w of local varlist {
        local vc : char `w'[rtm_cmd]
        if `"`vc'"' != "" local ++nvrec
    }
    if "`notes'" != "" | "`docx'" != "" {
        di as text _n "Recorded weighting steps for these weights:"
        if `nvrec' > 0 {
            foreach w of local varlist {
                local vc : char `w'[rtm_cmd]
                local vs : char `w'[rtm_stamp]
                local vstep : char `w'[rtm_step]
                if `"`vc'"' != "" di as text "  `w' (`vstep'): " as result `"`vc'"' as text " (`vs')"
                else di as text "  `w': no rtmweight record"
            }
        }
        else {
            foreach s of local steps {
                di as text "  `s': " as result `"`cmd_`s''"' as text " (`stamp_`s'')"
            }
            if "`steps'" == "" di as text "  none recorded (the weights were not made by rtmweight in this dataset)"
        }
    }

    * ---- Excel ----
    if "`excel'" != "" {
        quietly putexcel set "`excel'", replace
        quietly putexcel A1 = "rtmtools weighting report, `c(current_date)'"
        quietly putexcel A3 = matrix(`S'), names
        local r = 3 + `K' + 3
        if `K' > 1 {
            quietly putexcel A`r' = "Adjustment factors between stages"
            quietly putexcel A`=`r'+1' = matrix(`F'), names
            local r = `r' + `K' + 3
        }
        if "`totals'" != "" {
            quietly putexcel A`r' = "Totals with `last' against targets"
            quietly putexcel A`=`r'+1' = matrix(`T'), names
        }
        di as text _n `"Excel report written: {browse "`excel'"}"'
    }

    * ---- Word method note ----
    if "`docx'" != "" {
        quietly putdocx clear
        quietly putdocx begin
        quietly putdocx paragraph, style(Title)
        quietly putdocx text ("Weighting method note")
        quietly putdocx paragraph
        quietly putdocx text ("Produced by rtmtools (rtmweight report) on `c(current_date)' with Stata `c(stata_version)'. ")
        quietly putdocx text ("Weight variables, in order: `varlist'.")
        quietly putdocx paragraph, style(Heading1)
        quietly putdocx text ("Steps and their sources")
        local src_base "Design weights: inverse of the product of the stage inclusion probabilities (UN 2008, Designing Household Survey Samples, section 6.3), or baseline weights with a subsampling factor that preserves the baseline weight totals (Himelein et al. 2020, HFPS Vol. 2, pp. 10-11; Ambel et al. 2021, p. 10)."
        local src_nonresponse "Nonresponse and attrition adjustment: weighting classes (UN 2008, section 6.5; Himelein et al. 2020, p. 10) or response-propensity groups (Broccolini, Seitz and Azevedo 2017, pp. 7-11; Himelein et al. 2020, Annex A2.3.1; Dabalen et al. 2016, Box 2.2)."
        local src_trim "Trimming: winsorizing at a percentile (Himelein et al. 2020, p. 11; Ambel et al. 2021, p. 11) or capping with rescaling to the original total (UN 2008, section 6.8)."
        local src_calibrate "Calibration to population totals: raking or linear calibration (Deville and Sarndal 1992; Deville, Sarndal and Sautory 1993) through Stata's svycal, ipfraking (Kolenikov 2014) or ReGenesees (Zardetto 2015); applied after the sample-based adjustments (Himelein et al. 2020, pp. 10-11; UN 2008, section 6.6)."
        if `nvrec' > 0 {
            foreach w of local varlist {
                local vc : char `w'[rtm_cmd]
                local vs : char `w'[rtm_stamp]
                local vstep : char `w'[rtm_step]
                if `"`vc'"' != "" {
                    quietly putdocx paragraph
                    quietly putdocx text ("`w' (`vstep'): "), bold
                    quietly putdocx text (`"`vc' (`vs')"')
                    quietly putdocx paragraph
                    quietly putdocx text ("`src_`vstep''"), italic
                }
            }
        }
        else {
            foreach s in base nonresponse trim calibrate {
                if `: list s in steps' {
                    quietly putdocx paragraph
                    quietly putdocx text ("`s': "), bold
                    quietly putdocx text (`"`cmd_`s'' (`stamp_`s'')"')
                    quietly putdocx paragraph
                    quietly putdocx text ("`src_`s''"), italic
                }
            }
        }
        quietly putdocx paragraph, style(Heading1)
        quietly putdocx text ("Weight summary")
        quietly putdocx table W = matrix(`S'), rownames colnames nformat(%12.3g)
        if `K' > 1 {
            quietly putdocx paragraph, style(Heading1)
            quietly putdocx text ("Adjustment factors between stages")
            quietly putdocx table F = matrix(`F'), rownames colnames nformat(%12.4g)
        }
        if "`totals'" != "" {
            quietly putdocx paragraph, style(Heading1)
            quietly putdocx text ("Calibrated totals against targets (`last')")
            quietly putdocx table T = matrix(`T'), rownames colnames nformat(%14.4g)
        }
        quietly putdocx paragraph, style(Heading1)
        quietly putdocx text ("References")
        foreach ref in "Ambel, A., K. McGee, and A. Tsegay. 2021. Reducing Bias in Phone Survey Samples. Policy Research Working Paper 9676. World Bank." ///
            "Broccolini, C., W. Seitz, and J. P. Azevedo. 2017. Listening to Tajikistan: Household Survey. Background, Implementation, and Methods. World Bank." ///
            "Dabalen, A., et al. 2016. Mobile Phone Panel Surveys in Developing Countries. World Bank." ///
            "Deville, J.-C., and C.-E. Sarndal. 1992. Calibration Estimators in Survey Sampling. JASA 87: 376-382." ///
            "Himelein, K., et al. 2020. High Frequency Mobile Phone Surveys of Households to Assess the Impacts of COVID-19, Vol. 2: Guidelines on Sampling Design. World Bank." ///
            "Kolenikov, S. 2014. Calibrating Survey Data Using Iterative Proportional Fitting (Raking). Stata Journal 14(1): 22-59." ///
            "United Nations. 2008. Designing Household Survey Samples: Practical Guidelines. Studies in Methods F/98." ///
            "Zardetto, D. 2015. ReGenesees: An Advanced R System for Calibration, Estimation and Sampling Error Assessment in Complex Sample Surveys. Journal of Official Statistics 31(2): 177-203." {
            quietly putdocx paragraph
            quietly putdocx text ("`ref'")
        }
        quietly putdocx save "`docx'", replace
        di as text `"Word method note written: {browse "`docx'"}"'
    }

    return matrix summary = `S'
    return local weights "`varlist'"
    return local steps "`steps'"
end
