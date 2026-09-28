# Machine learning automorphic forms for black holes

Code and data accompanying [the paper](https://arxiv.org/abs/2505.05549).
The Wolfram Language notebook generates coefficient datasets and trains neural
networks to infer weights or related labels from them. The paper describes the
mathematics, experiments and results; this README explains where to find their
implementation and data.

## Where to start

- **Explore the original calculations:** open [`final.nb`](final.nb) in Mathematica.
- **Inspect the additional experiments:** see
  [`additional_validation/README.md`](additional_validation/README.md).
  Its supplied CSVs and plots can be read without running Mathematica.
- **Run the additional experiments:** use the commands in that directory's README.
  The additional validation study compares network width, depth and optimizer
using 26 configurations across two representative datasets. Each configuration
is trained with three random seeds, giving 78 training runs in total.
The folder also contains 96 separate training runs reproducing the
manuscript's CHL configurations.

## Repository contents

| Path | Contents |
|---|---|
| [`final.nb`](final.nb) | Original coefficient generators, preprocessing, networks, training and evaluation |
| [`CSV/`](CSV/) | Three headerless, preprocessed examples; the last column is the target |
| [`data2/`](data2/) | CHL coefficient caches and an additional eta cache, in Wolfram `.mx` format |
| [`mxtxt/`](mxtxt/) | Eta/CHL/theta coefficient caches, theta-product text datasets, progress logs and a saved network |
| [`data_jacobi/`](data_jacobi/) | Additional theta CSV exports; their generating cells are not identified in `final.nb` |
| [`additional_validation/`](additional_validation/) | Scripts, configuration, training data, fixed splits and recorded outputs for the additional study |

The original `.mx` files require Wolfram Language and may depend on the system
that created them. CSVs provide directly inspectable examples;
`additional_validation` also includes `.wxf` files for portable Wolfram expressions.

## Guide to the paper and notebook

Table numbers below refer to the manuscript's original Tables 1–12. This maps
experiment families to source sections and files, rather than certifying an
exact archived run for every table row.

| Paper | Find in `final.nb` | Associated files |
|---|---|---|
| Table 1: eta powers | **Modular forms from powers of Δ**; negative, positive and random-slice subsections | `mxtxt/dnexactw200.mx`; `CSV/dnexactw200norm30.csv` is the 400-row, 30-feature negative-eta example |
| Tables 2–5: CHL powers | **CHL models** → **Data generation**, **Init for ML**, and positive/negative power sections | `data2/coeffDataN…cnum29…mx`: `maxpow`, `minpow`, `randomPositive` and `randomNegative` distinguish the families |
| Tables 6–7: integer-power coefficient subsets | Random-slice experiments in **CHL models**, including the eta comparison | Reuse the corresponding integer-power caches in `data2/` |
| Table 8: E2-based series and Kloosterman/Bessel calculations | **Mock modular forms**; direct coefficient and Kloosterman-sum subsections | Generators and training cells in `final.nb` |
| Tables 9–10: individual theta powers and quotients | Search for `theta1`–`theta4` and `theta1byΔ`–`theta4byΔ` | `mxtxt/t1k…`, `t2l…`, `t3m…`, `t4n…` and `tΔ…` caches |
| Tables 11–12: theta products and quotients | Product generators and mixed-sign exponent sections | `mxtxt/t1t2…`, `t3t4…`, `tall…`, `jacobi-klmn*.txt` and `jacobibyΔ-klmn*.txt` |

Each experiment's cells generate or load coefficients, preprocess features,
attach labels, partition the examples, train a network and evaluate held-out
predictions. Eta/CHL caches store series coefficients; theta generators use the
additive argument of `EllipticTheta`.

Check each block's target definition when interpreting its errors. In particular,
the original CHL cells normalize logarithmic coefficient magnitudes and predict
`Log[Abs[power]]`; the additional study uses normalized raw coefficients and
physical-weight targets. These results are not directly interchangeable. The
direct E2-based cells store the generator parameter `w`, rather than the total
quasimodular weight `w + 2`.

## Using the original notebook

The notebook is an exploratory record rather than a single-command reproduction script. 
Avoid evaluating the entire notebook at once.
Work on a copy:

1. Start a fresh kernel and evaluate the required **Common functions** definitions.
2. Choose one experiment section and load its cache or run its generator.
3. Check paths against `mxtxt/` and `data2/`; some cells assume files are
   beside the notebook. For random CHL powers, evaluate **Stored random powers**
   before the corresponding generators.
4. Evaluate that experiment's preprocessing, model and evaluation cells together.

Historical splits and initial 
weights were not fully recorded, so a rerun need not recover the published
numbers. Use `additional_validation` for the study with explicit settings and
saved splits; it does not rerun all twelve original tables.

## Citation and license

```bibtex
@article{Jejjala:2025hgv,
    author = "Jejjala, Vishnu and Nampuri, Suresh and Nxumalo, Dumisani and Roy, Pratik and Swain, Abinash",
    title = "{Machine learning automorphic forms for black holes}",
    eprint = "2505.05549",
    archivePrefix = "arXiv",
    primaryClass = "hep-th",
    month = "5",
    year = "2025"
}
```

Code is distributed under the [MIT license](LICENSE).
