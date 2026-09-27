# Additional validation

Wolfram Language scripts for the architecture study and the manuscript's CHL
Tables 2-7. This is a standalone replacement bundle: extract it into a new
folder. It needs neither the older bundle nor its `.mx` files.

This corrected release fixes the September 26 smoke-run postprocessing errors
and explicitly checks the numeric range of decoded weights and output metrics.
If you already have the 174-fit bundle, update its code using the instructions
in `UPDATE.md`; your `results/` directory can remain in place.

## Run

Requirements: a working `wolframscript` installation (developed against Wolfram
14.3), Python 3, and optionally `pdflatex` for PDFs. From this folder:

```bash
bash run.sh --plan       # no training and no files written
bash run.sh --test       # mathematical, decoding and split tests; no training
bash run.sh --smoke      # six small five-epoch compatibility fits
bash run.sh              # all 174 fits, 10,000 epochs per fit
```

The default is **78 width/depth fits plus 96 manuscript-table fits** (32 rows,
including two eta comparison rows, each repeated for three seeds). All CHL
test MAPE and RMSE values are on recovered weights. CHL training uses log-power
targets and log-magnitude coefficient inputs. The CHL part of the width/depth
study now uses this same protocol, so it is a new comparison; it does not reuse
the older raw-input, 1,000-round results.

Other useful commands:

```bash
bash run.sh --epochs 20000
bash run.sh --suite width-depth       # only 78 fits
bash run.sh --suite chl               # only 96 fits
bash run.sh --suite e2                # optional nine-fit Table 8 repair study
bash run.sh --with-e2                 # 174 + 9 fits
bash run.sh --plan --list             # list experiment IDs
bash run.sh --only table2_N3          # one paper-table row, three seeds
```

Repeating a command reuses completed matching fits. Changing the epoch budget
starts fresh seeded fits. Run one training process at a time. A failed fit is
reported explicitly; successful fits remain saved. No old result is presented
as a new result.

## Read the output

The script prints its result directory and records it in `results/LATEST.txt`.
After training it generates LaTeX tables and a report automatically. Without
`pdflatex`, the TeX files are still available. To regenerate reports:

```bash
python3 scripts/make_reports.py --results "$(cat results/LATEST.txt)" --compile --allow-partial
```

| File or directory | Purpose |
|---|---|
| `experiment_manifest.csv` | One row per planned fit, including all settings |
| `metrics_best.csv`, `metrics_final.csv` | Individual errors at validation-selected and final checkpoints |
| `run_index.csv` | Run settings and links to its saved predictions, network and loss histories |
| `predictions/`, `curves/`, `splits/` | Predictions in weight units, losses and exact data partitions |
| `reports/` | Generated TeX report, table snippets and PDF when available |
| `historical_1000_rounds/` | Your completed 78-fit results and their separate report |
| `docs/` | Source audit, changed conventions and the E2 explanation |
| `config/`, `resources/` | Experiment definitions and the notebook's exact rational-power lists |

In `run_index.csv`, `RunFile` is relative to this bundle's root; prediction and
curve paths are relative to the printed result directory.

`Best` always means lowest **validation MSE**, not lowest test error. Tables
include weight MAPE (%) and weight RMSE together; training and validation losses
are MSE in the declared training-target space. Every summary states its number
of completed seeds and identifies incomplete results.

The table generator writes ordinary `booktabs` tables using
`\caption{\textsf{...}}`, so the snippets do not require `\ra` or `\capt`.
See `docs/PROTOCOL.md` for corrections to the older notebook's captions.

## Verification status

The launchers, experiment grid, exact identities, report generation and TeX
compilation were checked in the delivery environment. The supplied Mac log confirms that the original 27 MUnit tests passed and all
six smoke networks trained before postprocessing failed. This release adds
regression tests for preprocessing replay, result saving, cache reuse and error
propagation. A Wolfram kernel was not available in the repair environment, so
the updated MUnit tests and smoke run must still be executed locally. The historical
report contains your actual uploaded results; new 10,000-epoch results are not
included.


## Data and saved results

This directory contains the validation code, a representative dataset in
[`sample_data/`](sample_data/), and compact results for the reported experiments.

The complete datasets, trained networks, individual predictions and training
histories are available separately:

[Download the complete validation results](https://github.com/abinash7s/ml_modular_forms/releases/download/additional-validation-v1/additional_validation_results.zip)

To restore these files, open a terminal in the repository root—the directory
containing `final.nb`—and run:

```bash
unzip "$HOME/Downloads/additional_validation_results.zip" -d .
```

Adjust the ZIP path if you downloaded it elsewhere. The archive restores the
`additional_validation/results/` directory, including its data and model caches.
The saved summaries and tables can be inspected without downloading the archive
or retraining the networks.
