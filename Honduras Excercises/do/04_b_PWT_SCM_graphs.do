********************************************************************************
********************************************************************************
*Authors: Andrés Ham
*Coder: Samuel Suárez
*Project: Economic Impacts of the 2009 Honduras Coup
*Data: pwt_clean.dta (output of 01b_PWT_data_cleaning.do)
*Stage: SCM graphing 

*Last checked: 09.09.2026

/*
********************************************************************************
*                                 Contents                                     *
********************************************************************************

Purpose
Create visual and tabular outputs for the each SCM model in each sample.

Input
  - data from all models

Output
  - output/figures/gap_<sample>_<model>.pdf/.png   Section 1: Honduras - synthetic
    gap over time, one plot per sample x model (Texas script's gap48 plot).
  - temp/rmspe_<sample>_<model>.dta   Section 2: pre/post-2009 RMSPE per unit
    (id, pre_rmspe, post_rmspe), Honduras included.
  - temp/placebo_gaps_<sample>_<model>.dta   Section 2: stacked placebo gaps
    (id, year, gap), one row per placebo unit-year -- feeds sections 6/7.
  - output/figures/placebo_<sample>_<model>.pdf/.png   Section 5: in-space
    placebo overlay, all pool members (all thin, Honduras thick).
  - output/figures/placebo_ex_<sample>_<model>.pdf/.png   Section 6: same,
    excluding units whose pre-treatment RMSPE > 2x Honduras'.
  - output/figures/rmspe_hist_<sample>_<model>.pdf/.png   Section 3: histogram
    of post/pre RMSPE ratio across every unit (Texas script's `histogram
    ratio, bin(20) frequency`), one per sample x model.
  - output/tables/pvalues.tex/.csv   Section 4: one table, rows = models,
    columns = samples, cells = in-space placebo p-value (rank/(J+1)).
  - output/tables/scm_weights_<sample>.tex/.csv   Section 7: one table per
    sample, rows = donor countries with positive weight in >=1 model,
    columns = models.

Notes
  - Section 1 reads 03b's temp/synth_<sample>_<model>.dta (keep() output); it
    doesn't rerun synth. globals "models"/"models_log"/"models_diff" here are
    just the converging names, not the predictor lists (those live in 03b);
    "models_all" is their concatenation and is what every section loops over.
  - A model's outcome variable is inferred from its name suffix (_log ->
    log_rgdpo_pc, _diff -> diff_rgdpo_pc, else rgdpo_pc) -- same convention
    03b uses to pick synth's depvar. Needed wherever this file reruns synth
    (section 2) or labels a gap axis in the model's own units (sections 1, 5, 6).
  - Section 2 reruns synth once per non-Honduras pool member per model (a
    donor pool's own pool minus itself, Honduras included as a donor) --
    O(pool size) synth calls per sample x model. World's pool is ~143
    countries, so World x 13 models is ~1859 synth calls; expect this section
    to take a long time to run in full. It only computes/saves data (RMSPE +
    gaps); sections 5/6 do the graphing.
  - Section 7's weights come straight from 03b's saved _Co_Number/_W_Weight
    (no synth rerun); _Co_Number shares the id value label, decoded to the
    ISO code.
  - reshape wide with j(...) string concatenates stub+value with NO
    separator (e.g. "p"+"world" -> "pworld", "_W_Weight"+"naive" ->
    "_W_Weightnaive") -- not "p_world". Both sections rely on this.

Index
  1. Gap in predicted error graphs
  2. Pre-Post RMSPE
  3. Generate Pre-Post RMSPE histograms
  4. P-Values per model per sample tables
  5. All placeboes in same picture
  6. All placeboes excluding outliers (pre-RMSPE > 2x Honduras')
  7. SCM weights composition tables

********************************************************************************
*/

*************************************Paths**************************************

*Load machine-specific paths (defines ${root}); not versioned
if "${root}" == "" {
    capture include "config.do"
    if _rc capture include "Honduras Excercises/do/config.do"
    if _rc include "do/config.do"
}

cd "${root}"

global hond    "${root}/Honduras Excercises"
global data    "${hond}/data"
global temp    "${hond}/temp"
global logs    "${hond}/log"
global output  "${hond}/output"
global graphs  "${hond}/output/figures"
global tables  "${hond}/output/tables"

************************************Globals*************************************

*For data
global pwt          "${data}/pwt.dta"
global pwt_clean    "${data}/pwt_clean.dta"
*For variables
global id           "id year"
global sumvars      "rgdpo_pc cap_pc lab_pc hc remittances_real_pc minwage_ppp"
*For SCM samples (donor-pool dummies + display labels)
global samples                "world latin_america south_america central_caribbean"
global lbl_world               "World"
global lbl_latin_america       "Latin America"
global lbl_south_america       "South America"
global lbl_central_caribbean   "Central America & the Caribbean"
global models                 "naive naive_yrs factors factors_gdp factors_yrs"
global models_log             "naive_log naive_yrs_log factors_log factors_gdp_log factors_yrs_log"
global models_diff            "naive_diff factors_diff factors_gdp_diff"
global models_all             "$models $models_log $models_diff"
*For parameters
global dofile       "4b"

************************************Programs************************************

*User packages (install once)
*ssc install synth

*Housekeeping
clear all
set more off
capture log close sublog
log using "${logs}/${dofile}_PWT_SCM_graphs.smcl", replace name(sublog)
*Timer
timer clear
timer on 1

********************************************************************************
********************************************************************************

**********************************The Data**************************************

use "${pwt_clean}", clear
xtset $id
confirm variable $sumvars

*****************************1. Gap in predicted error graphs ***************

foreach s of global samples {
    foreach m of global models_all {
        if      regexm("`m'", "_log$")  local depvar "log_rgdpo_pc"
        else if regexm("`m'", "_diff$") local depvar "diff_rgdpo_pc"
        else                             local depvar "rgdpo_pc"

        use "${temp}/synth_`s'_`m'.dta", clear
        keep _Y_treated _Y_synthetic _time
        drop if missing(_time)
        rename _time year
        gen gap = _Y_treated - _Y_synthetic
        sort year

        twoway (line gap year, lpattern(solid) lwidth(thin) lcolor(navy)),        ///
            yline(0, lpattern(shortdash) lcolor(black))                          ///
            xline(2009, lpattern(shortdash) lcolor(black))                       ///
            xtitle("") ylabel(, angle(0))                                        ///
            ytitle("Gap in predicted `depvar' (Honduras - synthetic)", size(small)) ///
            title("${lbl_`s'}: `m'", size(medium)) legend(off)
        graph export "${graphs}/gap_`s'_`m'.pdf", replace
        graph export "${graphs}/gap_`s'_`m'.png", replace width(2000)
    }
}

*****************************2. Pre-Post RMSPE ******************************

* In-space placebo: within each sample's pool, run synth treating every
* non-Honduras member as if it were treated (donor pool = rest of the pool,
* Honduras included as a donor). Saves each unit's pre/post-2009 RMSPE
* (temp/rmspe_<sample>_<model>.dta, Honduras included) and the stacked
* placebo gaps (temp/placebo_gaps_<sample>_<model>.dta) -- data only, no
* graphing here; sections 5/6 do that.

use "${pwt_clean}", clear
qui levelsof id if country == "Honduras", local(trunit) clean

cd "${temp}"   // keep() can't parse a path with spaces

foreach s of global samples {
    if "`s'" == "world" local pool_cond "1"
    else                 local pool_cond "`s' == 1"
    qui levelsof id if `pool_cond', local(pool) clean
    local placebos : list pool - trunit

    foreach m of global models_all {
        if      regexm("`m'", "_log$")  local depvar "log_rgdpo_pc"
        else if regexm("`m'", "_diff$") local depvar "diff_rgdpo_pc"
        else                             local depvar "rgdpo_pc"

        di as result _n "=== Placebo: ${lbl_`s'} / `m' ==="

        * Honduras' own pre/post RMSPE (from 03b's saved gap)
        preserve
            use synth_`s'_`m'.dta, clear
            keep _Y_treated _Y_synthetic _time
            drop if missing(_time)
            rename _time year
            gen double hnd_gap2 = (_Y_treated - _Y_synthetic)^2
            qui summarize hnd_gap2 if year < 2009
            local hnd_pre = sqrt(r(mean))
            qui summarize hnd_gap2 if year >= 2009
            local hnd_post = sqrt(r(mean))
        restore

        tempname ph
        postfile `ph' long id double pre_rmspe post_rmspe using rmspe_`s'_`m'.dta, replace
        post `ph' (`trunit') (`hnd_pre') (`hnd_post')

        local first 1
        foreach p of local placebos {
            local donors : list pool - p
            di as text "  placebo unit: `p'"
            capture noisily synth `depvar' ${`m'}                        ///
                , trunit(`p') trperiod(2009) unitnames(countrycode)      ///
                  mspeperiod(1993(1)2008) resultsperiod(1993(1)2019)     ///
                  counit(`donors') keep(ph_`s'_`m'_`p'.dta) replace
            if _rc {
                di as error "    -> failed (rc=`=_rc'), skipping"
                continue
            }

            preserve
                use ph_`s'_`m'_`p'.dta, clear
                keep _Y_treated _Y_synthetic _time
                drop if missing(_time)
                rename _time year
                gen double gap = _Y_treated - _Y_synthetic
                gen double gap2 = gap^2
                qui summarize gap2 if year < 2009
                local pre = sqrt(r(mean))
                qui summarize gap2 if year >= 2009
                local post = sqrt(r(mean))
                post `ph' (`p') (`pre') (`post')

                gen long id = `p'
                keep id year gap
                if `first' {
                    save placebo_gaps_`s'_`m'.dta, replace
                    local first 0
                }
                else {
                    append using placebo_gaps_`s'_`m'.dta
                    save placebo_gaps_`s'_`m'.dta, replace
                }
            restore
            erase ph_`s'_`m'_`p'.dta
        }
        postclose `ph'
    }
}

cd "${root}"

*****************************3. Generate Pre-Post RMSPE histograms ***********

* Post/pre RMSPE ratio distribution across Honduras + every placebo (Texas
* script's `histogram ratio, bin(20) frequency`), one per sample x model.
* Honduras' own ratio is marked with a vertical line.

use "${pwt_clean}", clear
qui levelsof id if country == "Honduras", local(trunit) clean

foreach s of global samples {
    foreach m of global models_all {
        use "${temp}/rmspe_`s'_`m'.dta", clear
        gen double ratio = post_rmspe / pre_rmspe
        qui summarize ratio if id == `trunit'
        local hnd_ratio = r(mean)

        histogram ratio, bin(20) frequency fcolor(gs13) lcolor(black)  ///
            xline(`hnd_ratio', lcolor(cranberry) lwidth(medthick))     ///
            xtitle("Post/pre RMSPE ratio") ytitle("Frequency")         ///
            title("${lbl_`s'}: `m'", size(medium))                    ///
            note("Cranberry line = Honduras (`=string(`hnd_ratio', "%9.2f")')", size(vsmall))
        graph export "${graphs}/rmspe_hist_`s'_`m'.pdf", replace
        graph export "${graphs}/rmspe_hist_`s'_`m'.png", replace width(2000)
    }
}

*****************************4. P-Values per model per sample tables *********

* p = rank(Honduras' post/pre RMSPE ratio, descending) / (J+1) within each
* sample x model's placebo distribution (CLAUDE.md in-space-placebo
* inference). One table: rows = models, columns = samples.

use "${pwt_clean}", clear
qui levelsof id if country == "Honduras", local(trunit) clean

tempname pf
tempfile pvals
postfile `pf' str20 sample str20 model double p using `pvals', replace

foreach s of global samples {
    foreach m of global models_all {
        use "${temp}/rmspe_`s'_`m'.dta", clear
        gen double ratio = post_rmspe / pre_rmspe
        qui count
        local J = r(N) - 1
        gsort -ratio
        gen rank = _n
        qui summarize rank if id == `trunit'
        local p = r(mean) / (`J' + 1)
        post `pf' ("`s'") ("`m'") (`p')
    }
}
postclose `pf'

use `pvals', clear
reshape wide p, i(model) j(sample) string

* Row order = global models_all order
gen byte _order = .
local i = 0
foreach m of global models_all {
    local ++i
    replace _order = `i' if model == "`m'"
}
sort _order
drop _order

local lbl_cc_tex = subinstr("${lbl_central_caribbean}", "&", "\&", .)

file open _tex using "${tables}/pvalues.tex", write replace
file write _tex "% In-space placebo p-values (rank / (J+1)) -- 04b sec.4" _n
file write _tex "\begin{tabular}{l*{4}{c}}" _n
file write _tex "\toprule" _n
file write _tex "Model & ${lbl_world} & ${lbl_latin_america} & ${lbl_south_america} & `lbl_cc_tex' \\" _n
file write _tex "\midrule" _n
forvalues i = 1/`=_N' {
    local mdisp = subinstr(model[`i'], "_", "\_", .)
    local row "`mdisp'"
    foreach s of global samples {
        local row `"`row' & `=string(p`s'[`i'], "%9.3f")'"'
    }
    file write _tex "`row' \\" _n
}
file write _tex "\bottomrule" _n
file write _tex "\end{tabular}" _n
file close _tex
di as result "Wrote ${tables}/pvalues.tex"

export delimited using "${tables}/pvalues.csv", replace

*****************************5. All placeboes in same picture ****************

* Combined overlay per sample x model: all pool members' gaps (thin gray)
* against Honduras' own gap (thick cranberry). Reads section 2's saved data.

foreach s of global samples {
    foreach m of global models_all {
        if      regexm("`m'", "_log$")  local depvar "log_rgdpo_pc"
        else if regexm("`m'", "_diff$") local depvar "diff_rgdpo_pc"
        else                             local depvar "rgdpo_pc"

        preserve
            use "${temp}/synth_`s'_`m'.dta", clear
            keep _Y_treated _Y_synthetic _time
            drop if missing(_time)
            rename _time year
            gen double hnd_gap = _Y_treated - _Y_synthetic
            keep year hnd_gap
            tempfile hndgap
            save `hndgap'
        restore

        use "${temp}/placebo_gaps_`s'_`m'.dta", clear
        merge m:1 year using `hndgap', nogenerate
        reshape wide gap, i(year) j(id)
        sort year

        local plot ""
        foreach v of varlist gap* {
            local plot `"`plot' (line `v' year, lcolor(gs10%70) lwidth(thin))"'
        }

        twoway `plot' (line hnd_gap year, lcolor(cranberry) lwidth(thick)), ///
            legend(off)                                                    ///
            yline(0, lpattern(shortdash) lcolor(black))                    ///
            xline(2009, lpattern(shortdash) lcolor(black))                 ///
            xtitle("") ylabel(, angle(0))                                  ///
            ytitle("Gap in predicted `depvar' (thin = placebo, thick = Honduras)", size(small)) ///
            title("${lbl_`s'}: `m'", size(medium))
        graph export "${graphs}/placebo_`s'_`m'.pdf", replace
        graph export "${graphs}/placebo_`s'_`m'.png", replace width(2000)
    }
}

**********6. All placeboes excluding outliers (pre-RMSPE > 2x Honduras') ******

* Same overlay, dropping pool members whose pre-treatment RMSPE exceeds 2x
* Honduras' own (poor pre-treatment fit makes their post-period gap
* uninformative) -- standard robustness check (Abadie et al.).

use "${pwt_clean}", clear
qui levelsof id if country == "Honduras", local(trunit) clean

foreach s of global samples {
    foreach m of global models_all {
        if      regexm("`m'", "_log$")  local depvar "log_rgdpo_pc"
        else if regexm("`m'", "_diff$") local depvar "diff_rgdpo_pc"
        else                             local depvar "rgdpo_pc"

        use "${temp}/rmspe_`s'_`m'.dta", clear
        qui summarize pre_rmspe if id == `trunit'
        local hnd_pre = r(mean)
        levelsof id if pre_rmspe <= 2 * `hnd_pre', local(keepids) clean

        preserve
            use "${temp}/synth_`s'_`m'.dta", clear
            keep _Y_treated _Y_synthetic _time
            drop if missing(_time)
            rename _time year
            gen double hnd_gap = _Y_treated - _Y_synthetic
            keep year hnd_gap
            tempfile hndgap
            save `hndgap'
        restore

        use "${temp}/placebo_gaps_`s'_`m'.dta", clear
        gen byte _keep = 0
        foreach id2 of local keepids {
            replace _keep = 1 if id == `id2'
        }
        qui count if !_keep
        di as text "  ${lbl_`s'}/`m': excluding `r(N)' outlier unit-years"
        keep if _keep
        drop _keep
        merge m:1 year using `hndgap', nogenerate
        reshape wide gap, i(year) j(id)
        sort year

        local plot ""
        foreach v of varlist gap* {
            local plot `"`plot' (line `v' year, lcolor(gs10%70) lwidth(thin))"'
        }

        twoway `plot' (line hnd_gap year, lcolor(cranberry) lwidth(thick)), ///
            legend(off)                                                    ///
            yline(0, lpattern(shortdash) lcolor(black))                    ///
            xline(2009, lpattern(shortdash) lcolor(black))                 ///
            xtitle("") ylabel(, angle(0))                                  ///
            ytitle("Gap in predicted `depvar' (thin = placebo, thick = Honduras)", size(small)) ///
            title("${lbl_`s'}: `m' (outliers excluded)", size(medium))
        graph export "${graphs}/placebo_ex_`s'_`m'.pdf", replace
        graph export "${graphs}/placebo_ex_`s'_`m'.png", replace width(2000)
    }
}

*****************************7. SCM weights composition tables ***************

* Donor weights (03b's saved _Co_Number/_W_Weight, positive only), one table
* per sample: rows = donor country (ISO code), columns = models.

foreach s of global samples {
    clear
    tempfile stacked
    save `stacked', emptyok replace

    foreach m of global models_all {
        use "${temp}/synth_`s'_`m'.dta", clear
        keep if !missing(_Co_Number) & _W_Weight > 0
        keep _Co_Number _W_Weight
        rename _Co_Number id
        gen str20 model = "`m'"
        append using `stacked'
        save `stacked', replace
    }

    use `stacked', clear
    decode id, gen(unit)
    drop id
    reshape wide _W_Weight, i(unit) j(model) string
    foreach m of global models_all {
        rename _W_Weight`m' `m'
    }
    order unit ${models_all}
    sort unit

    local lbl_tex = subinstr("${lbl_`s'}", "&", "\&", .)
    local nmodels : word count ${models_all}

    * longtable, not tabular -- World runs to 100+ rows and won't fit one page
    file open _tex using "${tables}/scm_weights_`s'.tex", write replace
    file write _tex "% SCM donor weights (>0), by model -- 04b sec.7 -- ${lbl_`s'}" _n
    file write _tex "\begin{longtable}{l*{`nmodels'}{c}}" _n
    file write _tex "\caption{SCM donor weights (>0) -- `lbl_tex'}\label{tab:weights-`s'}\\" _n
    file write _tex "\toprule" _n
    local hdr "Country"
    foreach m of global models_all {
        local mdisp = subinstr("`m'", "_", "\_", .)
        local hdr "`hdr' & `mdisp'"
    }
    file write _tex "`hdr' \\" _n
    file write _tex "\midrule" _n
    forvalues i = 1/`=_N' {
        local row = unit[`i']
        foreach m of global models_all {
            local w = `m'[`i']
            if `w' == . local cell "--"
            else         local cell = string(`w', "%9.3f")
            local row "`row' & `cell'"
        }
        file write _tex "`row' \\" _n
    }
    file write _tex "\bottomrule" _n
    file write _tex "\end{longtable}" _n
    file close _tex
    di as result "Wrote ${tables}/scm_weights_`s'.tex"

    export delimited using "${tables}/scm_weights_`s'.csv", replace
}

************************************The End*************************************

*Timer display
timer off 1
timer list 1

*Log end
cap log close sublog