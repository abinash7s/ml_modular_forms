# Modular forms: Mathematica notebooks

Unzip the complete folder, then open the files in `notebooks/` with Mathematica.
Keep `support/` and `example_results/` beside that directory. No installation or
Python setup is needed to use the notebooks.

| Notebook | Purpose |
|---|---|
| `01_Data_and_Definitions.nb` | Exact eta, CHL and E2 coefficients, conventions, examples and dataset export. |
| `02_Training_and_Validation.nb` | Editable architecture and settings, one fit, custom networks, and the 174-fit study. |
| `03_Results_and_Tables.nb` | Existing results, comparisons, plots and LaTeX tables; no retraining required. |
| `04_Jacobi_and_Theta_Functions.nb` | Additive theta expansions, eta quotients, Taylor/Laurent coefficients and multiplicative modes. |

Start with notebook 3 to inspect the completed results, or notebook 1 to explore
the coefficient definitions. Evaluate each notebook from its setup section in
order. Notebooks have separate variable contexts; none depends on another
notebook having already been evaluated.

Notebook 2 has separate switches for the example, a custom network and the full
study. All are initially `False`. A short example uses five epochs when
`quickExample = True`; scientific runs default to 10,000 epochs. The standard
study uses seeds 101, 102 and 103: 78 width/depth fits and 96 manuscript-table
fits. The optional E2 suite is separate.

Edit the visible definitions and settings in the notebooks. Shared data,
training and study functions are in the three small files under `support/src/`.
The configuration files retain the previous study settings. Notebook 2 creates
a separate working copy for each study configuration, so the supplied presets
remain available.

New data, model files and reports are written under `generated/`. Notebook 3
initially reads `example_results/`, containing the supplied 174-run summary
tables. These are existing results, not fits performed while making this
bundle. Model weights, per-example predictions, loss curves and coefficient
caches are not included. The data-cache paths in `data_manifest.csv` have been
made relative; they refer to the corresponding archived files, not files
included here.

The notebooks retain the repository conventions q = exp(2 pi i tau), theta
nome Q = exp(pi i tau), and additive theta argument u = pi z. Target definitions
and retained coefficient positions are stated alongside each generator.
CHL MAPE and RMSE use decoded physical weights. Best and Final checkpoints
are reported separately.

Optional local checks, from this folder:

```bash
wolframscript -file check_notebooks.wls
```

This parses notebook input cells without running them and runs the shared
non-training tests. The data and Jacobi notebooks also contain small exact
checks next to their definitions.

Source conventions were checked against repository commit
`3159005815d40e6542432e2d7969f980f56e9f01`:
https://github.com/abinash7s/ml_modular_forms

The files were checked with an independent Wolfram-language parser and exact
coefficient checks. A Wolfram kernel and notebook front end were unavailable
during assembly, so local Mathematica execution and display remain to be
verified. The shared training core is unchanged from the supplied workflow.
