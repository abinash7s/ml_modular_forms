# September 26 postprocessing fix

The supplied log shows 27 successful unit tests and six completed five-epoch
training calls. The failures occurred after training, while recording settings
and evaluating/exporting results. They are implementation errors in the bundle.

## Update from inside your existing additional_validation folder

Save the corrected ZIP in Downloads, then run:

```bash
unzip -o "$HOME/Downloads/modular_forms_validation_10000_fixed2.zip" -d ..
bash run.sh --test && bash run.sh --smoke
```

The ZIP contains an `additional_validation/` directory. The command above
updates code and documentation in that directory; it contains no `results/`
files and does not delete your existing results or data cache. If your ZIP is
saved elsewhere, replace only its path in the first command.

The smoke run should end with `Finished: 6/6 completed; 0 failed.` It is a
compatibility check, not a scientific result. Once it succeeds, run:

```bash
bash run.sh
```

The defaults remain 174 fits at 10,000 epochs, with CHL MAPE and RMSE evaluated
on decoded weights. The E2 nine-fit suite remains optional.

## Additional correction after the 33/34 test report

Wolfram can represent `Exp[1000.]` as a finite arbitrary-precision number.
The original overflow regression incorrectly assumed it would be nonfinite.
The decoder now explicitly rejects physical predictions beyond
`$MaxMachineNumber`, because the CSV/Python reporting path uses Real64. The
same range check applies to exported metrics. Values are never clipped; the
fit is marked failed and its trained state is retained. Arbitrary-precision
coefficient generation and normalization remain supported.

The existing overflow test is retained and two direct range tests have been
added, bringing the suite to 36 tests. Mock cache tests no longer print
misleading training messages. No `NetTrain` runs take place in `--test`.

## Earlier corrections

- All three invalid multi-rule `AssociateTo` calls now receive a single list
  of rules. This fixes saved run signatures, completion status, and the E2
  preprocessor's missing mean and scale vectors.
- Saved signed-log preprocessing is checked before network prediction.
- Prediction failures propagate out of the split/checkpoint loops. A failed
  evaluation cannot be marked complete, and its trained cache is retained.
- Unit-test output and failure messages are concise; network arrays are no
  longer printed in `failures.csv`.
- Regression tests cover the paths omitted by the original test suite.

The corrected code uses a new cache identity. It reuses the unchanged exact
data cache, but does not silently accept malformed run records produced by the
old version. Your six short smoke fits will run again. Old files stay available;
no manual deletion is required. Repeating runs under this corrected version
reuses its completed matching fits.

## Verification limit

The corrected sources were statically parsed and every `AssociateTo` call was
checked for valid arity. Portable checks and report tests were run. The repair
environment has no Wolfram kernel, so a successful corrected native smoke run
is not claimed here.
