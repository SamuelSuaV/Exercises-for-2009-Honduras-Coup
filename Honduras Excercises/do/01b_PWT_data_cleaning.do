********************************************************************************
********************************************************************************
*Authors: Andrés Ham
*Coder: Samuel Suárez
*Project: Economic Impacts of the 2009 Honduras Coup
*Data: Penn World Table 10.01 (+ CEPAL remittances & population, ILO minimum wage)
*Stage: Data cleaning -- PWT base panel

*Last checked: 02.09.2026

/*
********************************************************************************
*                                 Contents                                     *
********************************************************************************

Purpose
Takes Penn World Table 10.01 as the base country-year panel and enriches it with:
two regional dummies, family remittances (level and per capita), the minimum wage
in constant 2021 PPP dollars, and real GDP per capita. Saves the enriched panel.

Input
  - pwt.dta                 Penn World Table 10.01 (185 countries, 1950-2023)
  - remittances_cepal.xlsx  CEPALSTAT, "Remesas familiares" (millions of USD)
  - pop_cepal.xlsx          CEPALSTAT/CELADE, "Poblacion total" (thousands of persons)
  - minwage_ilostat.dta     ILO/ILOSTAT, "Monthly minimum wage by currency"

Output
  - pwt_clean.dta           PWT panel + constructed variables

Notes
  - Merges are done on (country, year); CEPAL and ILO country names are
    harmonised to the PWT spelling before merging.
  - remittances_pc = remittances (mill. USD) / pop_cepal (thousands) * 1000  -> USD per capita
  - rgdpo_pc       = rgdpo (mill. 2021 USD) / pop (millions)                 -> 2021 USD per capita
  - Minimum wage: the "Currency: 2021 PPP $" slice is kept.
    NOTE for Honduras: the ILO series changes type in 2008 (national wage ->
    sectoral "manufacturing"), with a 2008->2009 jump that reflects the real
    Honduran minimum-wage hike; pre- and post-2008 are not the same concept.
  - central_caribbean and latin_america span the whole panel (=0 outside the
    region); latin_america contains central_caribbean.

Index
  1. Regional dummies (Central America & the Caribbean; Latin America)
  2. Family remittances, level and per capita (CEPAL)
  3. Minimum wage in constant 2021 PPP dollars (ILO)
  4. Real GDP per capita (PWT)
  5. Labels

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
global pwt_out      "${data}/pwt_clean.dta"
*For variables
global id           "id year"
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

* Checks: number of countries (not country-year rows) in each dummy
egen _tag = tag(country)
count if _tag & central_caribbean
assert r(N) == 27
count if _tag & latin_america
assert r(N) == 40
drop _tag
assert latin_america == 1 if central_caribbean == 1

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

* Remittances per capita: (mill. USD)/(thousand persons)*1000 = USD per capita
gen double remittances_pc = remittances / pop_cepal * 1000

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

********************4. Real GDP per capita (PWT) ***************************

* rgdpo in mill. 2021 USD (chained PPP); pop in millions -> 2021 USD per capita
gen double rgdpo_pc = rgdpo / pop

****************************5. Labels **********************************

label var central_caribbean "Central America & the Caribbean (=1)"
label var latin_america     "Latin America as a whole (=1)"
label var remittances       "Family remittances (millions of current USD, CEPAL)"
label var pop_cepal         "Total mid-year population (thousands of persons, CEPAL/CELADE)"
label var remittances_pc    "Family remittances per capita (current USD per capita)"
label var minwage_ppp       "Monthly minimum wage (constant 2021 PPP USD, ILO)"
label var rgdpo_pc          "Real GDP per capita (output-side, chained PPP, 2021 USD)"
label data "PWT 10.01 + regional dummies, remittances (CEPAL) and minimum wage (ILO) -- 01b"

************************************The End*************************************

compress
save "${pwt_out}", replace

*Timer display
timer off 1
timer list 1

*Log end
cap log close sublog
