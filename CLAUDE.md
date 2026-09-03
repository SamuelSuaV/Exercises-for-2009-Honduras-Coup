# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Research code (Stata) for an impact-evaluation paper estimating the effect of the
2009 Honduras coup on GDP using synthetic control. It has two independent parts:

- **`Cunningham Excercises/`** — replications of Scott Cunningham's *Causal Inference:
  The Mixtape*. Completed and committed. Treat as a learning reference, not paper code.
  `Texas_Prisons/Do/Script.do` is the worked `synth` example whose conventions the
  paper follows. For consultation only, not where work is done.
- **`Honduras Excercises/`** — the actual paper working folder. Raw data has been
  collected in `data/`; `do/01b_PWT_data_cleaning.do` is written and runs.
  `00_master.do`, `01a_cepal_data_cleaning.do`, `01c_factorshares_data_cleaning.do`
  and all downstream estimation/inference do-files are still empty stubs.

## Running Stata code

- A Stata MCP server is available: run do-files with the `stata-mcp` tools rather
  than shelling out. There is no build/lint/test system — this is research code.
- Run individual steps directly during development. `stata-mcp` calls should set the
  working directory to `Honduras Excercises/do/` so each do-file's
  `include "config.do"` resolves.
- Paper entry point (once written): `Honduras Excercises/do/00_master.do` orchestrates
  the numbered do-files in order.
- Required user packages: `synth`, `mat2txt` (both `ssc install`), and `kountry`
  (country-name → ISO if a future do-file needs code-based merges). Install lines are
  left commented in scripts.
- `#delimit ;` is used for long `synth` and `twoway` calls; watch for the matching
  `#delimit cr`. `01b` uses no `#delimit`.

## Paper folder layout and conventions

Under `Honduras Excercises/`:

- `do/` — scripts. Naming: `00_master`, then `01a/01b/01c_*_data_cleaning` for the
  three raw sources (`cepal`, `PWT` = Penn World Table, `factorshares`), then
  downstream estimation/inference do-files.
- `data/` built and raw datasets · `temp/` intermediate files · `log/` logs ·
  `output/figures` and `output/tables` final exhibits · `claude_code/` scratch space.
- **`config.do`** (`do/config.do`, gitignored) defines `global root` = repo root.
  Every paper do-file `include`s it and derives its paths from `${root}`; the only
  `cd` allowed is `cd "${root}"`. Do **not** copy the Cunningham script's hardcoded
  absolute `cd`.
- `.gitignore` excludes `*.dta *.gph *.log *.smcl config.do` and similar: **data and
  Stata outputs are not version-controlled.** Only code is tracked.
- **Write comments, labels, and new variable names in English** (the user asked for
  this explicitly; it overrides any Spanish in older/reference code). Keep string
  literals that must match raw source data verbatim (e.g.
  `keep if sex == "Ambos sexos"` for CEPAL files).

## Data-cleaning do-file conventions (established by `01b`)

The `01a/01b/01c` cleaners follow the house style of Andrés Ham's "Getting Growth
Accounting Right" project. `01b_PWT_data_cleaning.do` is the reference:

- **Section order**: header banner (Authors/Coder/Project/Data/Stage/Last checked) →
  `/* Contents */` block (Purpose, Input, Output, Notes, Index) → Paths → Globals
  (data-file, variable-list, parameter) → Housekeeping (plain: `clear all`,
  `set more off`, `capture log close`, `log using ...smcl`, `timer on 1`) → The Data →
  numbered sections → The End (`compress`, `save`, `timer off/list`, `cap log close`).
- **Base panel** = `data/pwt.dta` (Penn World Table 10.01, 185 countries, 1950–2023),
  keyed `countrycode`/`country`/`year`; `encode countrycode, gen(id)` + `xtset id year`.
  `01b` output is `data/pwt_clean.dta`.
- **Merging external sources**: clean each source inside a `preserve … tempfile …
  restore` block, harmonise its country names to PWT's exact `country` spelling
  (e.g. `México`→`Mexico`; ILO `United States of America`→`United States`), then
  `merge m:1 country year using \`tf'` and `drop if _merge == 2`. Guard each tempfile
  with `isid country year`.
- **CEPALSTAT `.xlsx`**: sheets `datos/metadatos/fuentes/notas/creditos`; `datos` is
  long. Import with no `firstrow` (columns become `A B C …`), `drop in 1`, rename
  positionally, `destring`. `pop_cepal.xlsx` has a `Sexo` column — keep `"Ambos sexos"`.
- **ILO `minwage_ilostat.dta`**: long with a currency dimension; keep
  `classif1_label == "Currency: 2021 PPP $"`.
- **Known data quirks**: Honduras' ILO minimum-wage series changes type at 2008
  (national → sectoral manufacturing) with a large 2008→2009 jump; Cambodia's
  `minwage_ppp` is ~0.03–0.04 every year (error in the ILO extract). CEPAL
  `minwage_real_cepal.xlsx` is a broken export (Argentina only) and is unused.

## Synthetic-control methodology (from the Texas reference)

- Fit `synth` on the outcome with a mix of **selected lagged-outcome years** and
  **covariate predictors** as matching variables. Leaving a covariate without a year
  averages it over the pre-period; specifying `var(year)` targets that year.
- Treatment unit is Honduras (`trunit`), treatment period is 2009 (`trperiod`);
  `mspeperiod` sets the fit window, `resultsperiod` the plotted window.
- Inference is **in-space placebo**: loop `synth` over every donor unit as if
  treated, save `_Y_treated`/`_Y_synthetic`, compute each unit's pre- and
  post-treatment RMSPE, rank by post/pre RMSPE ratio, and report p = rank / (J+1).
  Also produce the combined placebo gap plot (all donors thin, Honduras thick).
- Donor-pool size caps the attainable p-value (author's notes: Central America →
  min p ≈ 0.14; Latin America ≈ 20 units → p ≈ 0.05; global South needed for ≈ 0.01).
  This drives the choice of donor pool. `01b` builds `central_caribbean` and
  `latin_america` dummies to support donor-pool selection.
