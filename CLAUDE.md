# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Research code (Stata) for an impact-evaluation paper estimating the effect of the
2009 Honduras coup on GDP using synthetic control. It has two independent parts:

- **`Cunningham Excercises/`** — replications of Scott Cunningham's *Causal Inference:
  The Mixtape*. Completed and committed. Treat as a learning reference, not paper code.
  `Texas_Prisons/Do/Script.do` is the worked `synth` example the paper's SCM do-files
  are modeled on. For consultation only, not where work is done.
- **`Honduras Excercises/`** — the actual paper working folder, run in this order:
  `01b_PWT_data_cleaning.do` → `02b_PWT_data_analysis.do` → `03b_PWT_SCM_implementation.do`
  → `04_b_PWT_SCM_graphs.do` (note the inconsistent underscore in the last filename —
  it really is `04_b`, not `04b`). All four are written and run. `00_master.do`,
  `01a_cepal_data_cleaning.do` and `01c_factorshares_data_cleaning.do` are still empty
  stubs (CEPAL and factor-shares sources are unused so far; `01b`/PWT alone feeds
  everything downstream).

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
- `#delimit ;` is used for long `synth`/`twoway` calls copied in spirit from the Texas
  reference (`01b`, `02b`'s summary-label block). `03b` and `04_b` instead use `///`
  line continuation for their `synth`/`twoway` calls, even though those are just as
  long — the calls sit inside loops with surrounding `if`/`capture`/`preserve` logic,
  and toggling delimiters around that is more error-prone than it's worth. Match
  whichever style the file you're editing already uses.
- The MCP Stata session persists across tool calls within a conversation. A `preserve`
  left unbalanced by an interrupted/errored run can leak into the *next* run and throw
  `r(621)` ("already preserved") on an otherwise-correct script. Fix: run a throwaway
  do-file with a few `capture restore` lines followed by `clear all` before retrying.

## Paper folder layout and conventions

Under `Honduras Excercises/`:

- `do/` — scripts, numbered in run order (see above).
- `data/` built and raw datasets · `temp/` intermediate files (gitignored; includes
  per-model/per-sample `synth` `keep()` outputs consumed by later do-files — see
  below) · `log/` logs · `output/figures` and `output/tables` final exhibits ·
  `reports/` three hand-maintained LaTeX reports (build each with `pdflatex`,
  twice for the ToC), each `\input`/`\includegraphics`-ing tables/figures a
  specific do-file produces — check the matching one when adding a new
  table/figure someone should see in the writeup:
    - `PWT Data Analysis.tex` — `02b` sections 1–5 (summary stats, yearly
      averages, data coverage, SCM-eligible-country rosters).
    - `PWT Data Analysis (Modified Variables).tex` — `02b` section 6, the
      `log_*`/`diff_*` counterparts of the averages figures.
    - `results.tex` — `03b`/`04_b`'s SCM fit graphs, placebo/RMSPE exhibits
      and `scm_weights_*` tables; its model list is currently hardcoded via
      a `\foreach` (see `03b`/`04_b` notes below for the current model set).
  `reports/questions.txt` is the author's running research notes (Spanish),
  not built into any report.
- **`config.do`** (`do/config.do`, gitignored) defines `global root` = repo root
  (an absolute path containing spaces — see the `synth keep()` gotcha below). Every
  paper do-file `include`s it and derives its paths from `${root}`; the only `cd`
  allowed at top level is `cd "${root}"`. Do **not** copy the Cunningham script's
  hardcoded absolute `cd`.
- `.gitignore` excludes `*.dta *.gph *.log *.smcl config.do` and similar: **data and
  Stata outputs are not version-controlled**, except figures/tables under
  `output/` (`.pdf`/`.png`/`.tex`/`.csv` there ARE tracked — they're the exhibits).
- **Write comments, labels, and new variable names in English** (the user asked for
  this explicitly; it overrides any Spanish in older/reference code). Keep string
  literals that must match raw source data verbatim (e.g.
  `keep if sex == "Ambos sexos"` for CEPAL files).
- Every do-file follows the same section order (header banner → `/* Contents */` block
  with Purpose/Input/Output/Notes/Index → Paths → Globals → Housekeeping → The Data →
  numbered sections → The End with `timer off/list` + `cap log close`). `01b` is the
  cleanest reference for this skeleton.

## `01b_PWT_data_cleaning.do` — base panel

- **Base panel** = `data/pwt.dta` (Penn World Table 10.01, 185 countries, 1950–2023),
  keyed `countrycode`/`country`/`year`; `encode countrycode, gen(id)` + `xtset id year`.
  Output is `data/pwt_clean.dta`, the single input every downstream do-file reads.
- Builds three nested regional dummies used as SCM donor pools: `central_caribbean`,
  `latin_america` (⊇ `central_caribbean` + `south_america` + Mexico), `south_america`.
  Keep these three in `01b`, not rebuilt ad hoc downstream — `02b` and `03b`/`04_b`
  all just read them off `pwt_clean.dta`.
- **Sample restriction (section 5, the most consequential part of this file for
  everything downstream):** drops any country missing `rgdpo_pc`/`cap_pc`/`lab_pc`/`hc`
  for *any* year in 1993–2019 (Honduras is asserted safe). This shrinks the panel from
  185→144 countries (`central_caribbean` 27→12, `latin_america` 40→23,
  `south_america` 12→10). Reason: `synth` aborts the *entire* estimation (hard `r(198)`,
  not a soft per-donor exclusion) if any donor is missing even one of the single-year
  predictors used in `03b` (e.g. `cap_pc(2008)`) — see the gotchas section below. If
  you add a new single-year predictor in `03b`, either keep it inside 1993–2019 or
  widen this restriction to match; `03b`'s `mspeperiod(1993(1)2008)`/
  `resultsperiod(1993(1)2019)` are deliberately set to exactly this window.
- Merging external sources (remittances/CEPAL, minimum wage/ILO): clean each inside a
  `preserve … tempfile … restore` block, harmonise country names to PWT's exact
  spelling, `merge m:1 country year using \`tf'`, `drop if _merge == 2`, guard with
  `isid country year`. CEPALSTAT `.xlsx` sheets are long, imported with no `firstrow`
  (columns become `A B C …`) then renamed positionally. ILO minimum wage: keep
  `classif1_label == "Currency: 2021 PPP $"`.
- Known data quirks: Honduras' ILO minimum-wage series changes type at 2008 (national
  → sectoral manufacturing) with a large 2008→2009 jump; Cambodia's `minwage_ppp` is
  ~0.03–0.04 every year (ILO extract error). `remittances_real_pc` only covers 8
  Central American/Caribbean + Mexico countries — this is why `03b` disables its
  remittances-predictor model everywhere except that donor pool.

## `02b_PWT_data_analysis.do` — descriptive exhibits

Reads `pwt_clean.dta`, produces the descriptive content for two reports:

- Sections 1–5 (→ `reports/PWT Data Analysis.tex`): summary-statistics tables
  per sample (Honduras/CA&C/Latin America/World), yearly cross-country averages
  plotted against Honduras (one figure per variable + a combined grid), a
  per-country data-availability table, and a roster of SCM-eligible countries
  per donor pool (`output/tables/scm_countries.tex`) mirroring `03b`'s four
  samples.
- Section 6 (→ `reports/PWT Data Analysis (Modified Variables).tex`): the same
  Honduras-vs-regional-average plot recipe as section 3, applied to the
  `log_<var>`/`diff_<var>` transforms from `01b` section 6 instead of levels
  (`avg_log_<var>.pdf`/`avg_diff_<var>.pdf` + one combined grid per transform).
  Reuses section 2's `temp/yearly_averages.dta`, which already carries the
  log/diff columns alongside the levels.

## `03b_PWT_SCM_implementation.do` — fit the models

- Three model groups, each a predictor-list global per member plus one outcome
  variable: `global models` (level predictors: `naive`, `naive_yrs`, `factors`,
  `factors_gdp`, `factors_yrs`; depvar `rgdpo_pc`), `global models_log` (same
  five, `log_`-prefixed predictors; depvar `log_rgdpo_pc`), `global models_diff`
  (`naive_diff`, `factors_diff`, `factors_gdp_diff` only — **no `_yrs` variant**:
  a single-year `diff_<var>(year)` predictor risks being missing for any donor
  whose series doesn't extend one year before 1993, which — like any
  single-year predictor — would abort `synth` outright rather than just
  exclude that donor; the level/log `_yrs` variants are safe because `01b`
  section 5 guarantees those specific years are complete). `global samples` is
  the four donor pools (`world`, `latin_america`, `south_america`,
  `central_caribbean`, each with a `lbl_*` display name). A `factors_yrs_rem`
  (remittances) model is defined but commented out and excluded from
  `global models` — see the `01b` quirks note above for why.
- A local `modelgroups "models models_log models_diff"` paired with
  `depvar_models`/`depvar_models_log`/`depvar_models_diff` locals picks the
  right outcome variable per group. The loop nests
  `foreach s of global samples { foreach g of local modelgroups { foreach m of global `g' { synth `depvar_`g'' ... } } }`,
  fitting every sample × model combination against Honduras (`trunit`), saving
  both the `synth` dataset (`temp/synth_<sample>_<model>.dta`, via `keep()`)
  and the fit graph (`output/figures/synth_<sample>_<model>.gph`, via `fig` +
  `graph save`). Wrapped in `capture noisily` per combination so one failing
  cell doesn't kill the loop.
- Donor pool for a given sample = that sample's dummy (or, for `world`, no `counit()`
  restriction at all); Honduras is auto-excluded from its own donor pool by `synth`.
- Why four donor pools at all: the in-space-placebo p-value's floor is `1/(J+1)`, so a
  small, geographically-tight pool (Central America & the Caribbean) can't reach
  conventional significance no matter how good the fit — the author's notes put the
  achievable floor near p≈0.14 there, versus ≈0.05 for Latin America's ~20 units and
  ≈0.01 needing a global-South-sized pool. `world`/`latin_america` trade a looser
  "similar country" assumption for a lower achievable p-value; report all four.

## `04_b_PWT_SCM_graphs.do` — inference and reporting

Reuses `03b`'s `global samples`/`models`/`models_log`/`models_diff` (just the names —
the predictor lists live in `03b`) concatenated into `global models_all`, which every
section loops over. Wherever this file needs a model's outcome variable (rerunning
`synth`, or labelling a gap axis), it infers it from the model name's suffix
(`_log` → `log_rgdpo_pc`, `_diff` → `diff_rgdpo_pc`, else `rgdpo_pc`) rather than
repeating `03b`'s group/depvar locals. Seven sections, all implemented:

1. Per-combination gap plot (Honduras − synthetic over time), reading `03b`'s saved
   `.dta` — no `synth` rerun.
2. **The expensive one.** In-space placebo: for every sample × model, reruns `synth`
   once per non-Honduras pool member *as if it were treated* (donor pool = rest of the
   pool, Honduras included as a donor), saving pre/post-2009 RMSPE per unit
   (`temp/rmspe_<sample>_<model>.dta`) and stacked placebo gaps
   (`temp/placebo_gaps_<sample>_<model>.dta`). Data only, no graphing. Cost is
   O(pool size) `synth` calls per sample × model — World's ~143-country pool alone is
   ~1,859 calls, ~2,405 across all four samples × thirteen models. This has only been
   run for small slices during development; sections 3–7 need it run in full first.
3. Histogram of the post/pre RMSPE ratio per sample × model (Texas script's
   `histogram ratio, bin(20) frequency`).
4. One p-value table (rows = models, columns = samples): `p = rank/(J+1)` of
   Honduras' RMSPE ratio within its placebo distribution.
5/6. Combined overlay graphs (all pool members thin, Honduras thick) — section 6
   additionally drops units whose pre-treatment RMSPE exceeds 2× Honduras' own.
7. Donor-weight tables per sample (rows = country, columns = model, zero-weight cells
   excluded) — pulled straight from `03b`'s saved `_Co_Number`/`_W_Weight`, no rerun.
   The `longtable`'s column count is computed (`word count ${models_all}`), not
   hardcoded, so it tracks `models_all` automatically as models are added/removed.

## Stata/`synth` gotchas learned the hard way

- **`synth`'s `keep()` option cannot parse a path containing spaces** (the repo root
  does: `.../Economic Impacts of Coup/...`). Fix used throughout: `cd` into the
  target directory first and pass `keep()` a bare filename. Native Stata commands
  (`use`, `save`, `graph save`, `graph export`) handle quoted spaced paths fine —
  only `synth`'s own ado-parsed suboptions choke.
- **`unitnames()` must be a variable whose values are valid as Stata names/labels**
  (no periods, parentheses, commas). Full PWT country names break it (e.g. `Bolivia
  (Plurinational State of)`); `countrycode` (the ISO code) does not — use that.
- **A single-year predictor (e.g. `cap_pc(2008)`) missing for even one donor aborts
  the whole `synth` call** (hard `r(198)`, not a silent per-donor exclusion) — unlike
  a multi-year-averaged predictor with partial missingness, which `synth` just notes
  and continues past. This is why `01b` restricts the panel to countries complete
  over the exact window `03b`'s single-year predictors draw from.
- **`reshape wide var, j(x) string` concatenates stub + value with no separator**
  (`p` + `"world"` → `pworld`, not `p_world`; `_W_Weight` + `"naive"` →
  `_W_Weightnaive`). Both bit `04_b` during development — check the actual resulting
  variable names before referencing them.
