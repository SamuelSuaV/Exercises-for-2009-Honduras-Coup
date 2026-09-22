********************************************************************************
********************************************************************************
*Authors: Andrés Ham
*Coder: Samuel Suárez
*Project: Economic Impacts of the 2009 Honduras Coup
*Data: Penn World Table 10.01 (+ CEPAL remittances & population, ILO minimum wage, US CPI-U)
*Stage: Data cleaning -- PWT base panel

*Last checked: 02.09.2026

/*
********************************************************************************
*                                 Contents                                     *
********************************************************************************

Purpose
Takes Penn World Table 10.01 as the base country-year panel and enriches it with:
three regional dummies, family remittances (nominal and in constant 2021 USD, level
and per capita), the minimum wage in constant 2021 PPP dollars, per-capita
real aggregates (GDP, capital stock, employment), and log/first-difference
transforms of the six variables of interest. Saves the enriched panel.

Input
  - pwt.dta                 Penn World Table 10.01 (185 countries, 1950-2023)
  - remittances_cepal.xlsx  CEPALSTAT, "Remesas familiares" (millions of USD)
  - pop_cepal.xlsx          CEPALSTAT/CELADE, "Poblacion total" (thousands of persons)
  - minwage_ilostat.dta     ILO/ILOSTAT, "Monthly minimum wage by currency"
  - cpi_us_worldbank.csv    World Bank FP.CPI.TOTL = US CPI-U, all items, annual
                            average (index, 2010 = 100; 1960-2024)

Output
  - pwt_clean.dta           PWT panel + constructed variables, incl. log_<var>/
                            diff_<var> for every $sumvars variable

Notes
  - Merges are done on (country, year), except the US CPI-U which merges on year
    only; CEPAL and ILO country names are harmonised to the PWT spelling first.
  - remittances_pc      = remittances (mill. current USD) / pop_cepal (thousands)
                          * 1000                                -> current USD per capita
  - US CPI-U is rebased to 2021 = 100 before merging;
    remittances_real    = remittances / (cpi_us / 100)          -> mill. constant 2021 USD
    remittances_real_pc = remittances_real / pop_cepal * 1000   -> constant 2021 USD per capita
    remittances_real_pc is the series comparable to rgdpo_pc; the nominal
    remittances_pc is kept for reference only.
  - rgdpo_pc = rgdpo (mill. 2021 USD) / pop (millions)  -> constant 2021 USD per capita
    cap_pc   = rnna  (mill. 2021 USD) / pop (millions)  -> constant 2021 USD per capita
    lab_pc   = emp   (millions)       / pop (millions)  -> persons engaged / population
    (cap_pc is real by construction; lab_pc is a ratio, nothing to deflate)
  - Minimum wage: the "Currency: 2021 PPP $" slice is kept.
    NOTE for Honduras: the ILO series changes type in 2008 (national wage ->
    sectoral "manufacturing"), with a 2008->2009 jump that reflects the real
    Honduran minimum-wage hike; pre- and post-2008 are not the same concept.
  - central_caribbean, latin_america and south_america span the whole panel
    (=0 outside the region); latin_america contains both of the others.
  - Section 5 drops countries (Honduras excluded from risk) that aren't
    complete on rgdpo_pc/cap_pc/lab_pc/hc over 1993-2019, so every remaining
    country is a valid SCM donor for every 03b model (see 03b for why).
  - Section 6 adds log_<var> and diff_<var> for every $sumvars variable ($sumvars
    is the same six-variable list 02b/03b use). diff_<var> = D.<var>, the
    year-over-year change; D. respects xtset gaps, so it's missing unless year
    and year-1 both exist for that country. Feeds 02b's "modified variables"
    report.

Index
  1. Regional dummies (Central America & the Caribbean; Latin America; South America)
  2. Family remittances -- nominal and constant 2021 USD, level and per capita
     (CEPAL remittances & population; US CPI-U deflator)
  3. Minimum wage in constant 2021 PPP dollars (ILO)
  4. Per-capita real aggregates: GDP, capital stock, employment (PWT)
  5. Sample restriction: complete SCM-window coverage
  6. Log and first-difference transforms of variables of interest
  7. Labels

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
global cpi_raw      "${data}/cpi_us_worldbank.csv"
global pwt_clean    "${data}/pwt_clean.dta"
*For variables
global id           "id year"
global sumvars      "rgdpo_pc cap_pc lab_pc hc remittances_real_pc minwage_ppp"
*For parameters
global dofile       "1b"

************************************Programs************************************

*Housekeeping
clear all
set more off
capture log close sublog
log using "${logs}/${dofile}_PWT_data_cleaning.smcl", replace name(sublog)
*Timer
timer clear
timer on 1

********************************************************************************
********************************************************************************

**********************************The Data**************************************

use "${pwt}", clear
encode countrycode, gen(id)
xtset $id
des

***********************1. Regional dummies ***********************************

* Central America (7) + Caribbean (20)
gen byte central_caribbean = 0

foreach c in "Belize" "Costa Rica" "El Salvador" "Guatemala" "Honduras"              /// No se puede poner # delimit ; ?
             "Nicaragua" "Panama" "Antigua and Barbuda" "Aruba" "Bahamas"           ///
             "Barbados" "British Virgin Islands" "Cayman Islands" "Curaçao"          ///
             "Dominica" "Dominican Republic" "Grenada" "Haiti" "Jamaica"             ///
             "Montserrat" "Saint Kitts and Nevis" "Saint Lucia"                     ///
             "Sint Maarten (Dutch part)" "St. Vincent and the Grenadines"           ///
             "Trinidad and Tobago" "Anguilla" "Turks and Caicos Islands" {
    replace central_caribbean = 1 if country == "`c'"
}

* Latin America as a whole = Central America & the Caribbean + Mexico + South America
gen byte latin_america = central_caribbean
foreach c in "Mexico" "Argentina" "Bolivia (Plurinational State of)" "Brazil"        ///
             "Chile" "Colombia" "Ecuador" "Guyana" "Paraguay" "Peru" "Suriname"     ///
             "Uruguay" "Venezuela (Bolivarian Republic of)" {
    replace latin_america = 1 if country == "`c'"
}

* South America (subset of latin_america, disjoint from central_caribbean)
gen byte south_america = 0
foreach c in "Argentina" "Bolivia (Plurinational State of)" "Brazil" "Chile"        ///
             "Colombia" "Ecuador" "Guyana" "Paraguay" "Peru" "Suriname"            ///
             "Uruguay" "Venezuela (Bolivarian Republic of)" {
    replace south_america = 1 if country == "`c'"
}

* Checks: number of countries (not country-year rows) in each dummy
egen _tag = tag(country)
count if _tag & central_caribbean
assert r(N) == 27
count if _tag & latin_america
assert r(N) == 40
count if _tag & south_america
assert r(N) == 12
drop _tag
assert latin_america == 1 if central_caribbean == 1
assert latin_america == 1 if south_america == 1
assert !(central_caribbean & south_america)

*******************2. Family remittances, level and per capita (CEPAL) ******

* --- Remittances (millions of current USD) ---
preserve
    import excel "${remitt_raw}", sheet("datos") clear
    drop in 1
    keep B C D
    rename (B C D) (country year remittances)
    destring year remittances, replace
    * Harmonise CEPAL names -> PWT
    replace country = "Mexico"             if country == "México"
    replace country = "Panama"             if country == "Panamá"
    replace country = "Dominican Republic" if country == "República Dominicana"
    isid country year
    tempfile remitt
    save `remitt'
restore
merge m:1 country year using `remitt'
drop if _merge == 2
drop _merge

* --- CEPAL/CELADE population, only countries with remittances (thousands of persons) ---
preserve
    import excel "${pop_raw}", sheet("datos") clear
    drop in 1
    keep B C D E
    rename (B C D E) (country sex year pop_cepal)
    keep if sex == "Ambos sexos"
    drop sex
    destring year pop_cepal, replace
    replace country = "Mexico"             if country == "México"
    replace country = "Panama"             if country == "Panamá"
    replace country = "Dominican Republic" if country == "República Dominicana"
    keep if inlist(country, "Costa Rica", "El Salvador", "Guatemala", "Honduras",   ///
                            "Mexico", "Nicaragua", "Panama", "Dominican Republic")
    isid country year
    tempfile pop
    save `pop'
restore
merge m:1 country year using `pop'
drop if _merge == 2
drop _merge

* --- US CPI-U (all items, annual average), rebased to 2021 = 100 ---
preserve
    import delimited "${cpi_raw}", varnames(1) clear
    destring year cpi_us, replace
    * Rebase the index so 2021 = 100 -> dividing by it deflates to constant 2021 USD
    summarize cpi_us if year == 2021, meanonly
    assert r(N) == 1
    replace cpi_us = 100 * cpi_us / r(mean)
    isid year
    tempfile cpi
    save `cpi'
restore
merge m:1 year using `cpi'
drop if _merge == 2
drop _merge

* Remittances per capita.
*  - remittances_pc      : nominal, (mill. current USD)/(thousand persons)*1000
*  - remittances_real    : mill. constant 2021 USD (deflated by US CPI-U)
*  - remittances_real_pc : constant 2021 USD per capita -- comparable to rgdpo_pc
gen double remittances_pc      = remittances / pop_cepal * 1000
gen double remittances_real    = remittances / (cpi_us / 100)
gen double remittances_real_pc = remittances_real / pop_cepal * 1000

***************3. Minimum wage in constant 2021 PPP dollars (ILO) ***********

preserve
    use "${minwage_raw}", clear
    keep if classif1_label == "Currency: 2021 PPP $"
    destring time, gen(year)
    drop if missing(obs_value)
    rename obs_value minwage_ppp
    * Name equality between ILO and PWT
    replace ref_area_label = "Bolivia (Plurinational State of)" if ref_area_label == "Bolivia, Plurinational State of"
    replace ref_area_label = "Cabo Verde"                       if ref_area_label == "Cape Verde"
    replace ref_area_label = "D.R. of the Congo"                if ref_area_label == "Congo, Democratic Republic of the"
    replace ref_area_label = "China, Hong Kong SAR"             if ref_area_label == "Hong Kong, China"
    replace ref_area_label = "Iran (Islamic Republic of)"       if ref_area_label == "Iran, Islamic Republic of"
    replace ref_area_label = "Lao People's DR"                  if ref_area_label == "Lao People's Democratic Republic"
    replace ref_area_label = "U.R. of Tanzania: Mainland"       if ref_area_label == "Tanzania, United Republic of"
    replace ref_area_label = "United Kingdom"                   if ref_area_label == "United Kingdom of Great Britain and Northern Ireland"
    replace ref_area_label = "United States"                    if ref_area_label == "United States of America"
    replace ref_area_label = "St. Vincent and the Grenadines"   if ref_area_label == "Saint Vincent and the Grenadines"
    rename ref_area_label country
    keep country year minwage_ppp
    isid country year
    tempfile minwage
    save `minwage'
restore
merge m:1 country year using `minwage'
drop if _merge == 2
drop _merge

********************4. Per-capita real aggregates (PWT) ******************

* rgdpo, rnna in mill. constant 2021 USD; pop, emp in millions
gen double rgdpo_pc = rgdpo / pop        // output-side real GDP,  constant 2021 USD p.c.
gen double cap_pc   = rnna  / pop        // real capital stock,    constant 2021 USD p.c.
gen double lab_pc   = emp   / pop        // persons engaged per capita (emp/pop ratio)

*************5. Sample restriction: complete SCM-window coverage ***********

* A single missing year in any of these four breaks any SCM model that
* touches it (synth aborts outright, not just drops the donor) -- keep only
* countries complete on all four over 1993-2019.
gen byte _ok_yr = !missing(rgdpo_pc, cap_pc, lab_pc, hc) if inrange(year, 1993, 2019)
bysort country: egen byte _complete = min(_ok_yr)
assert _complete == 1 if country == "Honduras"
drop if _complete != 1
drop _ok_yr _complete

*******6. Log and first-difference transforms of variables of interest*******

* Two derived series per $sumvars variable, feeding 02b's "modified variables"
* report: log_<var> = log(<var>); diff_<var> = D.<var>, the year-over-year
* change (D. respects xtset gaps -- missing unless year and year-1 both exist
* for that country). All six $sumvars variables are >0 whenever observed, so
* log_<var> is never undefined. Section 5's bysort left the data sorted by
* country, not id/year -- D. needs the panel re-sorted first.
sort $id
foreach v of global sumvars {
    gen double log_`v'  = log(`v')
    gen double diff_`v' = D.`v'
}

****************************7. Labels **********************************

label var central_caribbean   "Central America & the Caribbean (=1)"
label var latin_america       "Latin America as a whole (=1)"
label var south_america       "South America (=1)"
label var remittances         "Family remittances (millions of current USD, CEPAL)"
label var pop_cepal           "Total mid-year population (thousands of persons, CEPAL/CELADE)"
label var cpi_us              "US CPI-U, all items, annual avg (rebased 2021 = 100; World Bank/BLS)"
label var remittances_pc      "Family remittances per capita (current USD)"
label var remittances_real    "Family remittances (millions of constant 2021 USD, CPI-U deflated)"
label var remittances_real_pc "Family remittances per capita (constant 2021 USD, CPI-U deflated)"
label var minwage_ppp         "Monthly minimum wage (constant 2021 PPP USD, ILO)"
label var rgdpo_pc            "Real GDP per capita (output-side, chained PPP, 2021 USD)"
label var cap_pc              "Real capital stock per capita (constant 2021 national prices, 2021 USD)"
label var lab_pc              "Persons engaged per capita (employment / population)"
label var log_rgdpo_pc             "Log of real GDP per capita"
label var log_cap_pc               "Log of real capital stock per capita"
label var log_lab_pc               "Log of employment-to-population ratio"
label var log_hc                   "Log of human capital index"
label var log_remittances_real_pc  "Log of real remittances per capita"
label var log_minwage_ppp          "Log of real minimum wage (monthly)"
label var diff_rgdpo_pc            "Change in real GDP per capita from previous year"
label var diff_cap_pc              "Change in real capital stock per capita from previous year"
label var diff_lab_pc              "Change in employment-to-population ratio from previous year"
label var diff_hc                  "Change in human capital index from previous year"
label var diff_remittances_real_pc "Change in real remittances per capita from previous year"
label var diff_minwage_ppp         "Change in real minimum wage (monthly) from previous year"
label data "PWT 10.01 + regional dummies, remittances nominal & real (CEPAL, US CPI-U), minimum wage (ILO), log & first-difference transforms -- 01b"

************************************The End*************************************

compress
save "${pwt_clean}", replace

*Timer display
timer off 1
timer list 1

*Log end
cap log close sublog
