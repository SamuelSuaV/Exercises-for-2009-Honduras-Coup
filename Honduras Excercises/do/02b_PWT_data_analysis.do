********************************************************************************
********************************************************************************
*Authors: Andrés Ham
*Coder: Samuel Suárez
*Project: Economic Impacts of the 2009 Honduras Coup
*Data: pwt_clean.dta (output of 01b_PWT_data_cleaning.do)
*Stage: Data analysis -- PWT output panel

*Last checked: 09.09.2026

/*
********************************************************************************
*                                 Contents                                     *
********************************************************************************

Purpose
Analyses data characteristics, such as composition of honduras data vs average,
composition of missings and distribution of key variables.

Input
  - pwt_clean.dta   PWT 10.01 panel + constructed variables (from 01b)

Output
  - output/tables/summary_stats_hnd.tex   Summary statistics -- Honduras
  - output/tables/summary_stats_cac.tex   Summary statistics -- Central America & Caribbean
  - output/tables/summary_stats_lac.tex   Summary statistics -- Latin America
  - output/tables/summary_stats_wld.tex   Summary statistics -- World (full PWT panel)
    (one self-contained booktabs \begin{tabular}...\end{tabular} per sample,
    N/Mean/SD/Min/Median/Max; no \begin{table}/caption -- add those when \input-ing)
  - temp/yearly_averages.dta   Year x sample cross-country means of the summary-stat
    variables (long, keyed region/year); one block per sample; feeds section 3.
  - output/figures/avg_<var>.pdf   Section 3: Honduras vs the CA&C / SA / LA / World
    yearly average, one time-series plot per summary-stat variable (+ combined grid).
  - output/tables/data_coverage.tex / .csv   Section 4: per-country availability of
    the $sumvars variables -- year span (first-last, * = gappy, . = never observed).
  - output/tables/scm_countries.tex   Section 5: SCM-eligible countries per donor
    pool (world/latin_america/south_america/central_caribbean), post 01b sec.5
    coverage restriction.
  - output/figures/avg_log_<var>.pdf / avg_diff_<var>.pdf   Section 6: same
    recipe as section 3's figures, for the log_<var>/diff_<var> transforms
    from 01b sec.6 -- plus avg_log_combined.pdf / avg_diff_combined.pdf.
    Feed reports/PWT Data Analysis (Modified Variables).tex.

Notes
  - Section 1 summarises the key per-capita variables for four nested samples:
    Honduras, Central America & the Caribbean (central_caribbean), Latin America
    (latin_america), and the full PWT panel ("World"). One table per sample.
      rgdpo_pc             output-side real GDP p.c.        (constant 2021 USD)
      cap_pc               real capital stock p.c.          (constant 2021 USD)
      lab_pc               persons engaged / population     (ratio)
      hc                   human capital index              (PWT, unitless index)
      remittances_real_pc  family remittances p.c., CPI-U deflated (constant 2021 USD)
      minwage_ppp          monthly minimum wage             (constant 2021 PPP USD)
  - N is variable-specific (pairwise): human capital, remittances and the minimum
    wage are observed for far fewer country-years than GDP.
  - Full available period -- no year restriction.
  - Section 1 requires -estout- (esttab/estpost); install line commented below.
  - Section 2 saves temp/yearly_averages.dta: for each sample in {honduras,
    central_caribbean, south_america, latin_america, world} and each year, the
    cross-country mean of every $sumvars variable (mean vars keep their names;
    n_<var> counts contributing countries). Samples overlap: honduras is inside
    central_caribbean; latin_america = central_caribbean + south_america + Mexico
    (Mexico not broken out); world is every country. South America has no
    remittances data (CEPAL coverage), so that series is missing there.
  - Section 3 reads temp/yearly_averages.dta and draws one time-series plot per
    $sumvars variable: Honduras against the CA&C / SA / LA / World yearly average.
  - Section 4 reloads pwt_clean.dta and reports, per country, the first-last year
    each $sumvars variable is observed (built as a LaTeX longtable + CSV). Needs
    \usepackage{longtable,booktabs}. South America is derived as latin_america
    minus central_caribbean minus Mexico (no separate dummy in pwt_clean.dta).
  - Section 6 repeats section 3's plot recipe for $sumvars_log and $sumvars_diff
    (01b sec.6's log/first-difference transforms) instead of the level variables.
    collapse (section 2) drops variable labels, so titles are looked up from
    pwt_clean.dta directly. Feeds a separate report, "PWT Data Analysis
    (Modified Variables).tex".

Index
  1. Summary statistics
  2. Yearly averages per sample: honduras, central_caribbean, south_america,
     latin_america, world
  3. Comparison of averages -- Honduras vs each regional average, one plot per variable
  4. Missing values composition -- per-country availability (year span) of each variable
  5. SCM-eligible countries per donor pool (world/latin_america/south_america/
     central_caribbean), for the report
  6. Comparison of averages -- modified variables (log & first-difference), for
     the "Modified Variables" report

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
global remitt_raw   "${data}/remittances_cepal.xlsx"
global pop_raw      "${data}/pop_cepal.xlsx"
global minwage_raw  "${data}/minwage_ilostat.dta"
global pwt_clean    "${data}/pwt_clean.dta"
global sumstub      "${tables}/summary_stats"      // one table per sample: _hnd _cac _lac _wld
global yravg        "${temp}/yearly_averages.dta"  // year x region means (section 2 -> section 3)
global covtex       "${tables}/data_coverage.tex"  // section 4: availability by country (LaTeX longtable)
global covcsv       "${tables}/data_coverage.csv"  // section 4: same, as CSV
*For variables
global id           "id year"
global sumvars      "rgdpo_pc cap_pc lab_pc hc remittances_real_pc minwage_ppp"
global sumvars_log  ""
global sumvars_diff ""
foreach v of global sumvars {
    global sumvars_log  "$sumvars_log log_`v'"
    global sumvars_diff "$sumvars_diff diff_`v'"
}
*For parameters
global dofile       "2b"

*Row labels shared by every summary-statistics table
#delimit ;
global sumlabels
    rgdpo_pc            "Real GDP per capita"
    cap_pc              "Real capital stock per capita"
    lab_pc              "Employment / population"
    hc                  "Human capital index"
    remittances_real_pc "Real remittances per capita"
    minwage_ppp         "Real minimum wage (monthly)" ;
#delimit cr

************************************Programs************************************

*User packages (install once)
*ssc install estout
*ssc install schemepack

*Housekeeping
clear all
set more off
capture log close sublog
log using "${logs}/${dofile}_PWT_data_analysis.smcl", replace name(sublog)
*Timer
timer clear
timer on 1

********************************************************************************
********************************************************************************

**********************************The Data**************************************

use "${pwt_clean}", clear
xtset $id

***********************1. Summary Statistics ***********************************

* One table per sample, so each stays narrow enough for a portrait page. The four
* samples are nested: Honduras c central_caribbean c latin_america c World.
* Columns: N / Mean / SD / Min / Median / Max. N is variable-specific (pairwise),
* so human capital, remittances and the minimum wage show far fewer obs than GDP.

foreach s in hnd cac lac wld {

    * Sample selector and title
    if      "`s'" == "hnd" {
        local cond   `"country == "Honduras""'
        local stitle "Honduras"
    }
    else if "`s'" == "cac" {
        local cond   "central_caribbean"
        local stitle "Central America \& the Caribbean"
    }
    else if "`s'" == "lac" {
        local cond   "latin_america"
        local stitle "Latin America"
    }
    else if "`s'" == "wld" {
        local cond   "1"
        local stitle "World (full PWT panel)"
    }

    eststo clear
    eststo `s': estpost summarize $sumvars if `cond', detail

    local cells   `"count(fmt(%9.0fc)) mean(fmt(%12.2fc)) sd(fmt(%12.2fc)) min(fmt(%12.2fc)) p50(fmt(%12.2fc)) max(fmt(%12.2fc))"'
    local collab  `""N" "Mean" "SD" "Min" "Median" "Max""'

    * Preview to the log
    esttab `s', label nonumber noobs nomtitles ///
        cells("`cells'") collabels(`collab') ///
        title("Summary statistics -- `stitle'")

    * Export a self-contained booktabs \begin{tabular}...\end{tabular} (no
    * \begin{table}/\caption): the report wraps it in a float and adds the caption.
    esttab `s' using "${sumstub}_`s'.tex", replace ///
        booktabs label nonumber noobs nomtitles ///
        cells("`cells'") collabels(`collab') ///
        coeflabels($sumlabels) ///
        prehead("\begin{tabular}{l*{6}{r}}" "\toprule") ///
        postfoot("\bottomrule" "\end{tabular}")

    di as result `"Wrote ${sumstub}_`s'.tex"'
}

**************2. World, South America, Central America & Caribbean, Averages ***

* Year-by-year cross-country means of the summary-stat variables, one block of
* rows per sample. central_caribbean, latin_america and south_america come
* from 01b; honduras and world are built here. honduras is a subset of
* central_caribbean; world is every country.
*
* latin_america (23) = central_caribbean (12) + South America (10) + Mexico (1).
* Mexico is North America, so it sits in neither central_caribbean nor
* south_america; it is not broken out on its own -- it only feeds the
* latin_america and world averages. Counts are post-01b-sec.5 restriction
* (complete rgdpo_pc/cap_pc/lab_pc/hc, 1993-2019), so lower than the raw
* regional-dummy counts asserted in 01b.
*
* Saved long, keyed (region, year); mean variables keep their original names, a
* parallel n_* variable counts the contributing countries.

* --- Sample selectors not already in the data ---
gen byte honduras = country == "Honduras"
gen byte world    = 1

label var honduras "Honduras (=1)"
label var world    "World -- every PWT country (=1)"

* --- Checks: country counts and the Latin America split ---
egen _tag = tag(country)
count if _tag & honduras
assert r(N) == 1
count if _tag & south_america
assert r(N) == 10
count if _tag & central_caribbean
assert r(N) == 12
count if _tag & latin_america
assert r(N) == 23
count if _tag
assert r(N) == 144
* central_caribbean and south_america are disjoint subsets of latin_america;
* the single remaining latin_america country is Mexico
assert latin_america if central_caribbean
assert latin_america if south_america
assert !(central_caribbean & south_america)
count if _tag & latin_america & !central_caribbean & !south_america
assert r(N) == 1
drop _tag

* collapse stat lists: (mean) keeps the varname, (count) -> n_<varname>.
* Includes the log/diff transforms (01b sec.6) alongside the levels, so
* section 6 below can reuse this same yearly_averages.dta.
local meanlist ""
local countlist ""
foreach v in $sumvars $sumvars_log $sumvars_diff {
    local meanlist  "`meanlist' `v'"
    local countlist "`countlist' n_`v'=`v'"
}

* One collapsed dataset per sample, then stack them
local groups "honduras central_caribbean south_america latin_america world"

foreach g of local groups {
    preserve
        keep if `g' == 1
        collapse (mean) `meanlist' (count) `countlist', by(year)
        gen str20 region = "`g'"
        tempfile f_`g'
        save `f_`g''
    restore
}

preserve
    clear
    foreach g of local groups {
        append using `f_`g''
    }
    order region year $sumvars $sumvars_log $sumvars_diff
    sort  region year
    label var region "Sample the yearly means are taken over"
    label data "Yearly cross-country means of summary-stat variables (levels + log/diff transforms), by sample -- 02b sec.2"
    compress
    save "${yravg}", replace
restore

di as result `"Wrote ${yravg}"'

*******************3. Comparison of averages *********************************

* One time-series plot per summary-stat variable: Honduras (thick cranberry) next
* to each regional yearly average -- Central America & the Caribbean, South
* America, Latin America and the World. Dashed vertical line marks the 2009 coup.
* A region's line is only drawn if it has data for that variable (South America
* has no remittances), and the legend is built to match.
* Clean schemepack look (white_tableau); every year labelled on the x-axis,
* rotated 90 degrees so the ticks do not collide.

use "${yravg}", clear
sort region year

* Clean modern look (schemepack; install line commented above)
local sc "white_tableau"

* Per-region line options and legend text (regional means muted, Honduras bold)
local o_central_caribbean "lcolor(orange%75) lwidth(medthin)"
local o_south_america     "lcolor(teal%75) lwidth(medthin)"
local o_latin_america     "lcolor(navy%75) lwidth(medthin)"
local o_world             "lcolor(gs7%75) lwidth(medthin) lpattern(dash)"
local L_central_caribbean "Central America & Caribbean"
local L_south_america     "South America"
local L_latin_america     "Latin America"
local L_world             "World"

* Per-variable titles and y-axis units
local t_rgdpo_pc            "Real GDP per capita"
local u_rgdpo_pc            "Constant 2021 USD"
local t_cap_pc              "Real capital stock per capita"
local u_cap_pc              "Constant 2021 USD"
local t_lab_pc              "Employment-to-population ratio"
local u_lab_pc              "Persons engaged / population"
local t_hc                 "Human capital index"
local u_hc                 "PWT index (schooling & returns)"
local t_remittances_real_pc "Real remittances per capita"
local u_remittances_real_pc "Constant 2021 USD"
local t_minwage_ppp        "Real minimum wage, monthly"
local u_minwage_ppp        "Constant 2021 PPP USD"

foreach v of global sumvars {

    * Build the plot layers: regional averages first, Honduras drawn last (on top)
    local plot   `""'
    local legreg `""'
    local k = 0
    foreach r in central_caribbean south_america latin_america world {
        quietly count if region == "`r'" & !missing(`v')
        if r(N) > 0 {
            local ++k
            local plot   `"`plot' (line `v' year if region=="`r'", `o_`r'')"'
            local legreg `"`legreg' `k' "`L_`r''""'
        }
    }
    local ++k
    local plot `"`plot' (line `v' year if region=="honduras", lcolor(cranberry) lwidth(thick))"'
    local legend `"`k' "Honduras" `legreg'"'

    * Label every year on the x-axis (tilted so they do not overlap)
    twoway `plot', ///
        scheme(`sc') ///
        title("`t_`v''", size(medium)) ///
        subtitle("Honduras vs. regional yearly averages", size(small)) ///
        ytitle("`u_`v''", size(small)) ///
        ylabel(, angle(0) format(%12.0gc) labsize(small) grid glcolor(gs15) glwidth(vvthin)) ///
        xtitle("") ///
        xlabel(1950(1)2023, angle(90) labsize(tiny) tlength(*.6) nogrid) ///
        xline(2009, lcolor(gs9) lpattern(shortdash) lwidth(thin)) ///
        legend(order(`legend') rows(1) size(vsmall) region(lstyle(none)) position(6)) ///
        plotregion(lstyle(none)) ///
        name(g_`v', replace)
    graph export "${graphs}/avg_`v'.pdf", replace
    graph export "${graphs}/avg_`v'.png", replace width(2200)

    * Legend-free, stripped-down copy for the combined grid (decade ticks, tilted)
    twoway `plot', ///
        scheme(`sc') title("`t_`v''", size(medsmall)) ///
        ytitle("") ylabel(#4, angle(0) format(%12.0gc) labsize(vsmall) ///
                          grid glcolor(gs15) glwidth(vvthin)) ///
        xtitle("") xlabel(1950(10)2020, angle(90) labsize(vsmall) nogrid) ///
        xline(2009, lcolor(gs9) lpattern(shortdash) lwidth(thin)) ///
        plotregion(lstyle(none)) legend(off) name(gc_`v', replace) nodraw
}

* Combined overview grid
graph combine gc_rgdpo_pc gc_cap_pc gc_lab_pc gc_hc gc_remittances_real_pc gc_minwage_ppp, ///
    cols(2) scheme(`sc') xsize(9) ysize(11) imargin(medsmall) ///
    title("Honduras vs. regional averages, 1950-2023", size(medium)) ///
    note("Cranberry (thick) = Honduras; orange = Central America & Caribbean;" ///
         "teal = South America; navy = Latin America; grey dashed = World." ///
         "Dashed vertical line = 2009 coup. South America has no remittances data." ///
         "Panel y-axes: GDP, capital, remittances = constant 2021 USD; minimum wage = 2021 PPP USD;" ///
         "employment/population and human capital index are unitless.", size(vsmall)) ///
    name(g_combined, replace)
graph export "${graphs}/avg_combined.pdf", replace
graph export "${graphs}/avg_combined.png", replace width(2000)

di as result "Wrote ${graphs}/avg_*.pdf"

*******************4. Missing values composition ****************************

* Data-availability table: one row per country, one column per important variable.
* Each cell shows the span of years with non-missing data ("1960-2019"), a single
* year if only one is observed, a trailing "*" if that span has internal gaps, or
* "." if the country never has the variable. Written as a LaTeX longtable and CSV.

use "${pwt_clean}", clear
keep countrycode country year central_caribbean latin_america $sumvars

* Per country x variable: first year, last year, and count of non-missing years
foreach v of global sumvars {
    gen int _y = year if !missing(`v')
    bysort countrycode: egen `v'_a = min(_y)
    by countrycode: egen `v'_z = max(_y)
    by countrycode: egen `v'_n = count(_y)
    drop _y
}

* One row per country
bysort countrycode (year): keep if _n == 1
keep countrycode country central_caribbean latin_america *_a *_z *_n

* Region tag (South America = latin_america minus Central America/Caribbean minus Mexico)
gen str14 region = ""
replace region = "CA \& Carib." if central_caribbean
replace region = "Mexico"       if country == "Mexico"
replace region = "S. America"   if latin_america & region == ""

* Span string per variable
foreach v of global sumvars {
    gen str16 s_`v' = "."
    replace s_`v' = string(`v'_a) + "-" + string(`v'_z) if `v'_n > 0
    replace s_`v' = string(`v'_a)                        if `v'_n > 0 & `v'_a == `v'_z
    replace s_`v' = s_`v' + "*"                          if `v'_n > 0 & `v'_n < `v'_z - `v'_a + 1
}

* --- CSV (plain, no LaTeX escaping) ---
preserve
    replace region = subinstr(region, "\&", "&", .)
    foreach v of global sumvars {
        rename s_`v' `v'
    }
    keep country region $sumvars
    order country region $sumvars
    sort country
    export delimited using "${covcsv}", replace
restore
di as result `"Wrote ${covcsv}"'

* --- LaTeX longtable ---
sort country
count if s_rgdpo_pc != "."
local n_rgdpo_pc = r(N)
count if s_cap_pc != "."
local n_cap_pc = r(N)
count if s_lab_pc != "."
local n_lab_pc = r(N)
count if s_hc != "."
local n_hc = r(N)
count if s_remittances_real_pc != "."
local n_remittances_real_pc = r(N)
count if s_minwage_ppp != "."
local n_minwage_ppp = r(N)

local hd "Country & Region & GDP p.c.\ & Capital p.c.\ & Emp/pop & Human cap.\ & Remitt.\ p.c.\ & Min.\ wage"

file open _tex using "${covtex}", write replace
file write _tex "% Data-availability by country -- generated by 02b_PWT_data_analysis.do" _n
file write _tex "\begin{longtable}{ll*{6}{c}}" _n
file write _tex "\caption{Availability of the key variables by country. Each cell is the first--last year with non-missing data (a lone year if only one), with a trailing * if the series has internal gaps; a dot means the variable is never observed.\label{tab:coverage}}\\" _n
file write _tex "\toprule `hd' \\ \midrule" _n
file write _tex "\endfirsthead" _n
file write _tex "\multicolumn{8}{l}{\itshape\small Table \thetable{} (continued)}\\" _n
file write _tex "\toprule `hd' \\ \midrule" _n
file write _tex "\endhead" _n
file write _tex "\midrule \multicolumn{8}{r}{\small continued on next page}\\" _n
file write _tex "\endfoot" _n
file write _tex "\bottomrule" _n
file write _tex "\endlastfoot" _n

forvalues i = 1/`=_N' {
    local cty = subinstr(country[`i'], "&", "\&", .)
    local row = "`cty' & " + region[`i']
    foreach v of global sumvars {
        local row = "`row' & " + s_`v'[`i']
    }
    file write _tex "`row' \\" _n
}

file write _tex "\midrule" _n
file write _tex "\multicolumn{2}{l}{\itshape Countries with any data} & `n_rgdpo_pc' & `n_cap_pc' & `n_lab_pc' & `n_hc' & `n_remittances_real_pc' & `n_minwage_ppp' \\" _n
file write _tex "\end{longtable}" _n
file close _tex
di as result `"Wrote ${covtex}"'

* Log preview: Central America & the Caribbean
list country s_rgdpo_pc s_cap_pc s_lab_pc s_hc s_remittances_real_pc s_minwage_ppp ///
    if central_caribbean, noobs sep(0) abbrev(20)

*******************5. SCM-eligible countries per donor pool ******************

* Roster of countries in each 03b donor pool, post 01b sec.5 restriction
* (complete rgdpo_pc/cap_pc/lab_pc/hc, 1993-2019). Written as a LaTeX
* description list, one block per sample.

use "${pwt_clean}", clear
egen _tag = tag(country)
keep if _tag
drop _tag
gen byte world = 1

local scmsamples "world latin_america south_america central_caribbean"

file open _tex using "${tables}/scm_countries.tex", write replace
file write _tex "% SCM-eligible countries by donor pool -- 02b sec.5" _n
file write _tex "\begin{description}" _n
foreach s of local scmsamples {
    if      "`s'" == "world"             local stitle "World"
    else if "`s'" == "latin_america"     local stitle "Latin America"
    else if "`s'" == "south_america"     local stitle "South America"
    else if "`s'" == "central_caribbean" local stitle "Central America \& the Caribbean"

    count if `s' == 1
    local n = r(N)
    levelsof country if `s' == 1, clean sep(", ")
    file write _tex "\item[`stitle' (`n')] `r(levels)'" _n
}
file write _tex "\end{description}" _n
file close _tex
di as result "Wrote ${tables}/scm_countries.tex"

*************6. Comparison of averages -- modified variables ****************

* Same recipe as section 3 (Honduras vs. regional yearly averages, 2009 coup
* line), applied to the log/first-difference transforms instead of the level
* variables. File names inherit the log_/diff_ prefix already in the varname
* (avg_log_rgdpo_pc.pdf, avg_diff_rgdpo_pc.pdf, ...), plus one combined grid
* per transform (avg_log_combined.pdf, avg_diff_combined.pdf).

* Titles: collapse (section 2) drops variable labels, so look them up fresh
* off pwt_clean.dta into locals keyed by the full (log_/diff_) varname.
use "${pwt_clean}", clear
foreach v in $sumvars_log $sumvars_diff {
    local ttl_`v' : variable label `v'
}

use "${yravg}", clear
sort region year

local sc "white_tableau"
local o_central_caribbean "lcolor(orange%75) lwidth(medthin)"
local o_south_america     "lcolor(teal%75) lwidth(medthin)"
local o_latin_america     "lcolor(navy%75) lwidth(medthin)"
local o_world             "lcolor(gs7%75) lwidth(medthin) lpattern(dash)"
local L_central_caribbean "Central America & Caribbean"
local L_south_america     "South America"
local L_latin_america     "Latin America"
local L_world             "World"

foreach t in log diff {
    local combined ""
    foreach v of global sumvars_`t' {

        local plot   `""'
        local legreg `""'
        local k = 0
        foreach r in central_caribbean south_america latin_america world {
            quietly count if region == "`r'" & !missing(`v')
            if r(N) > 0 {
                local ++k
                local plot   `"`plot' (line `v' year if region=="`r'", `o_`r'')"'
                local legreg `"`legreg' `k' "`L_`r''""'
            }
        }
        local ++k
        local plot `"`plot' (line `v' year if region=="honduras", lcolor(cranberry) lwidth(thick))"'
        local legend `"`k' "Honduras" `legreg'"'

        twoway `plot', ///
            scheme(`sc') ///
            title("`ttl_`v''", size(medium)) ///
            subtitle("Honduras vs. regional yearly averages", size(small)) ///
            ytitle("", size(small)) ///
            ylabel(, angle(0) format(%12.2gc) labsize(small) grid glcolor(gs15) glwidth(vvthin)) ///
            xtitle("") ///
            xlabel(1950(1)2023, angle(90) labsize(tiny) tlength(*.6) nogrid) ///
            xline(2009, lcolor(gs9) lpattern(shortdash) lwidth(thin)) ///
            legend(order(`legend') rows(1) size(vsmall) region(lstyle(none)) position(6)) ///
            plotregion(lstyle(none)) ///
            name(g_`v', replace)
        graph export "${graphs}/avg_`v'.pdf", replace
        graph export "${graphs}/avg_`v'.png", replace width(2200)

        * Legend-free, stripped-down copy for the combined grid
        twoway `plot', ///
            scheme(`sc') title("`ttl_`v''", size(medsmall)) ///
            ytitle("") ylabel(#4, angle(0) format(%12.2gc) labsize(vsmall) ///
                              grid glcolor(gs15) glwidth(vvthin)) ///
            xtitle("") xlabel(1950(10)2020, angle(90) labsize(vsmall) nogrid) ///
            xline(2009, lcolor(gs9) lpattern(shortdash) lwidth(thin)) ///
            plotregion(lstyle(none)) legend(off) name(gc_`v', replace) nodraw

        local combined "`combined' gc_`v'"
    }

    if "`t'" == "log" local ttl_transform "Log"
    else              local ttl_transform "First difference"
    graph combine `combined', ///
        cols(2) scheme(`sc') xsize(9) ysize(11) imargin(medsmall) ///
        title("Honduras vs. regional averages -- `ttl_transform' transform, 1950-2023", size(medium)) ///
        note("Cranberry (thick) = Honduras; orange = Central America & Caribbean;" ///
             "teal = South America; navy = Latin America; grey dashed = World." ///
             "Dashed vertical line = 2009 coup.", size(vsmall)) ///
        name(g_combined_`t', replace)
    graph export "${graphs}/avg_`t'_combined.pdf", replace
    graph export "${graphs}/avg_`t'_combined.png", replace width(2000)

    di as result "Wrote ${graphs}/avg_`t'_*.pdf"
}

************************************The End*************************************

*Timer display
timer off 1
timer list 1

*Log end
cap log close sublog
