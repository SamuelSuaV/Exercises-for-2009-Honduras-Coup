********************************************************************************
********************************************************************************
*Authors: Andrés Ham
*Coder: Samuel Suárez
*Project: Economic Impacts of the 2009 Honduras Coup
*Data: pwt_clean.dta (output of 01b_PWT_data_cleaning.do)
*Stage: SCM implementation -- synthetic control models

*Last checked: 09.09.2026

/*
********************************************************************************
*                                 Contents                                     *
********************************************************************************

Purpose
Define candidate SCM predictor sets and run synth for Honduras against four
donor pools, saving each model x sample result.

Input
  - pwt_clean.dta   PWT 10.01 panel + constructed variables (from 01b)

Output
  - temp/synth_<sample>_<model>.dta      Saved synth result per converging combo.
  - output/figures/synth_<sample>_<model>.gph   Synth fig per converging combo
    (equivalent of the Cunningham Texas script's graph save Graph ..., replace).
  - output/figures/synth_<sample>_<model>.pdf/.png   Same fig, exported for the
    reports (.gph is gitignored/Stata-only; .pdf/.png are the tracked exhibits).

Notes
  - Models are predictor-list globals; global "models" names them, reached via
    ${`m'}. Samples are donor-pool dummies; global "samples" names them,
    reached via ${lbl_`s'} for the display label.
  - Three model groups, one depvar each: "models" (level, depvar rgdpo_pc),
    "models_log" (depvar log_rgdpo_pc) and "models_diff" (depvar diff_rgdpo_pc).
    models_diff has no _yrs variant (single-year diff predictors risk being
    missing for countries whose series doesn't extend a year before 1993,
    which -- like any single-year predictor -- would abort synth outright
    rather than just exclude that donor; models/models_log's _yrs variants
    only use level/log single-year predictors, which 01b sec.5 guarantees
    complete over 1993-2019).
  - mspeperiod(1993-2008), resultsperiod(1993-2019), matching 01b sec.5's
    coverage restriction: every remaining country is complete on
    rgdpo_pc/cap_pc/lab_pc/hc over exactly that window. factors_yrs' hc(1980)
    is the one predictor outside it (unlikely but possible residual failure).
  - factors_yrs_rem (remittances) is commented out under "1." -- coverage is
    too sparse (8 CA&C/Mexico countries) to fix via 01b's restriction without
    gutting every other donor pool; capture noisily still guards the loop.
  - cd's into temp/ for keep() -- breaks on spaces in the repo path.
  - Section 3 (RMSPE ranking / placebo inference) not yet implemented.

Index
  1. Model definition
  2. SCM implementation (loop over samples x models)

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
*For parameters
global dofile       "3b"

************************************Programs************************************

*User packages (install once)
*ssc install synth

*Housekeeping
clear all
set more off
capture log close sublog
log using "${logs}/${dofile}_PWT_SCM_implementation.smcl", replace name(sublog)
*Timer
timer clear
timer on 1

********************************************************************************
********************************************************************************

**********************************The Data**************************************

use "${pwt_clean}", clear
xtset $id
confirm variable $sumvars

***********************1. SCM model definition ***********************************


* Models w.o altered vars
global naive             "rgdpo_pc"                                             // avg. GDP p.c. only
global naive_yrs         "rgdpo_pc rgdpo_pc(2007) rgdpo_pc(1999) rgdpo_pc(1995)" // + specific years
global factors           "cap_pc lab_pc hc"                                     // production-function factors
global factors_gdp       "rgdpo_pc cap_pc lab_pc hc"                            // factors + GDP p.c.
global factors_yrs       "rgdpo_pc rgdpo_pc(2007) rgdpo_pc(1999) rgdpo_pc(1995) cap_pc(2008) lab_pc lab_pc(1999) lab_pc(2005) lab_pc(2007) hc hc(2000)"

* Models with log
global naive_log         "log_rgdpo_pc"                                             // avg. GDP p.c. only
global naive_yrs_log     "log_rgdpo_pc log_rgdpo_pc(2007) log_rgdpo_pc(1999) log_rgdpo_pc(1995)" // + specific years
global factors_log       "log_cap_pc log_lab_pc log_hc"                                     // production-function factors
global factors_gdp_log    "log_rgdpo_pc log_cap_pc log_lab_pc log_hc"                            // factors + GDP p.c.
global factors_yrs_log    "log_rgdpo_pc log_rgdpo_pc(2007) log_rgdpo_pc(1999) log_rgdpo_pc(1995) log_rgdpo_pc(2004) log_cap_pc(2008) log_lab_pc log_lab_pc(1999) log_lab_pc(2005) log_lab_pc(2007) log_hc log_hc(2000)"

* Models with diff
global naive_diff        "diff_rgdpo_pc"                                             // avg. GDP p.c. only
global factors_diff      "diff_cap_pc diff_lab_pc diff_hc"                                     // production-function factors
global factors_gdp_diff  "diff_rgdpo_pc diff_cap_pc diff_lab_pc diff_hc"                            // factors + GDP p.c.


* global factors_yrs_rem "rgdpo_pc cap_pc(2008) lab_pc lab_pc(1999) lab_pc(2005) lab_pc(2007) hc hc(1980) remittances_real_pc remittances_real_pc(2007) remittances_real_pc(2008)"
* -- remittances_real_pc only covers 8 CA&C/Mexico countries (01b sec.2), too
* sparse for the World/Latin America/South America donor pools; excluded from
* "models" below.

global models "naive naive_yrs factors factors_gdp factors_yrs"
global models_log "naive_log naive_yrs_log factors_log factors_gdp_log factors_yrs_log"
global models_diff "naive_diff factors_diff factors_gdp_diff"

*****************************2. SCM implementation *******************************

* Honduras' numeric panel id -- treated unit (trunit) for every sample
qui levelsof id if country == "Honduras", local(trunit) clean

* Model group -> outcome variable (see Notes above)
local modelgroups        "models models_log models_diff"
local depvar_models      "rgdpo_pc"
local depvar_models_log  "log_rgdpo_pc"
local depvar_models_diff "diff_rgdpo_pc"

cd "${temp}"

foreach s of global samples {

    if "`s'" == "world" {
        local counit_opt ""
    }
    else {
        qui levelsof id if `s' == 1 & id != `trunit', local(donors) clean
        local counit_opt "counit(`donors')"
    }

    di as result _n "=== Sample: ${lbl_`s'} ==="

    foreach g of local modelgroups {
        foreach m of global `g' {
            di as text "  Model: `m'"
            capture noisily synth `depvar_`g'' ${`m'}                    ///
                , trunit(`trunit') trperiod(2009) unitnames(countrycode) ///
                  mspeperiod(1993(1)2008) resultsperiod(1993(1)2019)     ///
                  `counit_opt'                                           ///
                  keep(synth_`s'_`m'.dta) replace fig
            if _rc {
                di as error "  -> failed (rc=`=_rc'), skipping `s'/`m'"
            }
            else {
                graph save Graph "${graphs}/synth_`s'_`m'.gph", replace
                graph export "${graphs}/synth_`s'_`m'.pdf", replace
                graph export "${graphs}/synth_`s'_`m'.png", replace width(2000)
            }
        }
    }
}

cd "${root}"

*****************************3. SCM RMSE pre *******************************

* Not yet implemented 

************************************The End*************************************

*Timer display
timer off 1
timer list 1

*Log end
cap log close sublog
