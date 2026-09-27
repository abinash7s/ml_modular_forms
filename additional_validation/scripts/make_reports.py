#!/usr/bin/env python3
"""Create paper tables and a depth/width appendix from recorded weight metrics.

Only Python's standard library is required. No model is fitted by this script.
Missing runs remain visibly missing; repeated exports are never counted as seeds.
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import shutil
import statistics
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

TABLES = {
    2: ("positive_integer", "Positive integer powers, all 30 coefficients",
        "positive integer powers, using coefficient positions 0 through 29"),
    3: ("negative_integer", "Negative integer powers, all 30 coefficients",
        "negative integer powers, using coefficient positions 0 through 29"),
    4: ("positive_rational", "Positive rational powers, all 30 coefficients",
        "the stored sample of positive rational powers, using coefficient positions 0 through 29"),
    5: ("negative_rational", "Negative rational powers, all 30 coefficients",
        "the stored sample of negative rational powers, using coefficient positions 0 through 29"),
    6: ("positive_slice", "Positive integer powers, fixed 15-coefficient slice",
        "positive integer powers, using the recorded fixed slice of 15 of the first 30 coefficient positions"),
    7: ("negative_slice", "Negative integer powers, fixed 15-coefficient slice",
        "negative integer powers, using the recorded fixed slice of 15 of the first 30 coefficient positions"),
}


def tex(value):
    """Escape untrusted CSV strings exactly once."""
    return ''.join({"\\": r"\textbackslash{}", "&": r"\&", "%": r"\%",
                    "$": r"\$", "#": r"\#", "_": r"\_", "{": r"\{",
                    "}": r"\}", "~": r"\textasciitilde{}", "^": r"\textasciicircum{}"}.get(c, c)
                   for c in str(value))


def number(value):
    if value is None or str(value).strip() in ("", "NA", "Missing", "None"):
        return None
    text = str(value).strip().replace("*^", "e")
    text = re.sub(r"`[0-9.]*", "", text)
    try:
        answer = float(text)
    except ValueError:
        return None
    return answer if math.isfinite(answer) else None


def fmt(value, precision=3):
    if value is None:
        return r"\text{---}"
    if value == 0:
        return "0"
    if abs(value) < 0.001 or abs(value) >= 10000:
        mantissa, exponent = f"{value:.{precision-1}e}".split("e")
        return rf"{mantissa}\times10^{{{int(exponent)}}}"
    places = max(0, precision - 1 - math.floor(math.log10(abs(value))))
    return f"{value:.{places}f}"


def mean_sd(rows, key):
    vals = [number(r.get(key)) for r in rows]
    vals = [v for v in vals if v is not None]
    if not vals:
        return None, None, 0
    return statistics.mean(vals), statistics.stdev(vals) if len(vals) > 1 else None, len(vals)


def cell(rows, key, spread=True):
    avg, sd, n = mean_sd(rows, key)
    if avg is None or n != len(rows):
        return r"---"
    if spread and sd is not None:
        return f"${fmt(avg)}\\pm{fmt(sd)}$"
    return f"${fmt(avg)}$"


def read_csv(path):
    with path.open(newline='', encoding='utf-8-sig') as handle:
        return list(csv.DictReader(handle))


def canonical(row):
    row = dict(row)
    aliases = {"RunID": "Signature", "Epochs": "Rounds", "Depth": "HiddenLayers", "Dset": "Dataset", "NorEta": "N",
               "Suite": "Study", "Table": "PaperTable", "TrainTargetMSE": "TrainLoss",
               "ValidationTargetMSE": "ValidationLoss", "WeightTestMAPE": "TestMAPE",
               "WeightTestRMSE": "TestRMSE", "TrainingLoss": "TrainLoss"}
    for old, new in aliases.items():
        if not row.get(new) and row.get(old):
            row[new] = row[old]
    cp = row.get("Checkpoint", "Best").lower()
    row["Checkpoint"] = "Final" if cp == "final" else "Best"
    for key in ("Dataset", "Model", "Optimizer", "Seed", "Study", "ExperimentID"):
        row.setdefault(key, "")
    row["Optimizer"] = {"Adam": "ADAM", "RMSPROP": "RMSProp"}.get(row["Optimizer"], row["Optimizer"])
    # Earlier studies wrote NRMSE but not their standardized-target MSE.
    # It is safe to infer loss only when the target transform explicitly confirms it.
    if row.get("TargetTransform", "").lower() in ("standardize", "standardizedweight", "standardized_weight"):
        for split in ("Train", "Validation"):
            nr = number(row.get(split + "NRMSE"))
            if not row.get(split + "Loss") and nr is not None:
                row[split + "Loss"] = str(nr * nr)
    return row


def is_depth(row):
    study = row.get("Study", "").lower().replace("-", "_")
    return study in ("depth_width", "width_depth", "minimal78", "validation78", "depthwidth") or (
        not row.get("PaperTable") and study not in ("chl", "paper_chl", "e2") and
        row.get("Dataset") in ("eta_negative", "chl_N3_positive_integer"))


def paper_table(row):
    val = number(row.get("PaperTable"))
    return int(val) if val is not None and int(val) in TABLES else None


def is_smoke(rows):
    return any(str(r.get("Smoke", "")).lower() in ("true", "1") for r in rows)


def run_key(row, checkpoint=True):
    signature = row.get("Signature")
    fields = ("Study", "ExperimentID", "Dataset", "Model", "Optimizer", "Seed", "Rounds",
              "Preprocessing", "TargetTransform")
    key = (signature,) if signature else tuple(row.get(k, "") for k in fields)
    return key + (row["Checkpoint"],) if checkpoint else key


def load_results(directory):
    """Load only direct, named exports. Never recursively mix unrelated studies."""
    directory = directory.resolve()
    manifests = []
    for name in ("experiment_manifest.csv", "manifest.csv", "run_settings.csv", "plan.csv"):
        if (directory / name).is_file():
            manifests.extend(canonical(r) for r in read_csv(directory / name))
    by_sig = {r.get("Signature"): r for r in manifests if r.get("Signature")}
    by_id = {r.get("ExperimentID"): r for r in manifests if r.get("ExperimentID")}
    loaded = {}
    found = []
    for name in ("metrics.csv", "metrics_best.csv", "metrics_final.csv"):
        path = directory / name
        if not path.is_file():
            continue
        found.append(name)
        for raw in read_csv(path):
            if "Checkpoint" not in raw:
                raw["Checkpoint"] = "Final" if "final" in name else "Best"
            row = canonical(raw)
            inherited = by_sig.get(row.get("Signature"), by_id.get(row.get("ExperimentID"), {}))
            row = canonical(dict(inherited, **{k: v for k, v in row.items() if v != ""}))
            key = run_key(row)
            if key in loaded:
                for metric in ("TrainLoss", "ValidationLoss", "TestMAPE", "TestRMSE"):
                    a, b = number(loaded[key].get(metric)), number(row.get(metric))
                    if a is not None and b is not None and not math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-12):
                        raise ValueError(f"Conflicting exports for {key}: {metric} differs")
                loaded[key].update({k: v for k, v in row.items() if v != ""})
            else:
                loaded[key] = row
    return list(loaded.values()), manifests, found


def validate_rows(rows, historical=False):
    seen = set()
    for row in rows:
        key = group_key(row) + (row.get("Seed", ""), row["Checkpoint"])
        if key in seen:
            raise ValueError("More than one run is present for the same configuration, seed and checkpoint: " + str(key))
        seen.add(key)
    if historical and any(number(r.get("Rounds")) != 1000 for r in rows):
        raise ValueError("--historical is reserved for the recorded 1000-round study")
    for index in TABLES:
        budgets = {r.get("Rounds") for r in rows if paper_table(r) == index}
        if len(budgets) > 1:
            raise ValueError(f"Paper table {index} contains mixed training budgets; generate separate reports")


def require_complete(rows, manifest):
    expected = {(r.get("ExperimentID"), r.get("Seed")) for r in manifest if r.get("ExperimentID") and r.get("Seed")}
    if not rows:
        raise ValueError("No completed fits are available; use --allow-partial to generate visibly empty table templates")
    for checkpoint in ("Best", "Final"):
        done = {(r.get("ExperimentID"), r.get("Seed")) for r in rows if r["Checkpoint"] == checkpoint}
        missing = expected - done
        if missing:
            raise ValueError(f"{len(missing)} planned {checkpoint} checkpoint rows are missing; use --allow-partial to report completed fits")


def model_shape(row):
    model = row.get("Model", "")
    if model in ("Net1", "Net2", "Net3"):
        return model
    depth, width = number(row.get("HiddenLayers")), number(row.get("Width"))
    if depth and width:
        return f"{int(depth)}x{int(width)}"
    if model.isdigit():
        return "1x" + model
    match = re.search(r"(?:D|depth)[_-]?(\d+).*?(?:W|width)[_-]?(\d+)", model, re.I)
    return f"{match[1]}x{match[2]}" if match else model


def model_tex(row):
    shape = model_shape(row)
    if re.fullmatch(r"\d+x\d+", shape):
        d, w = shape.split("x")
        return rf"${d}\times {w}$"
    return tex(shape)


def group_key(row):
    return (row["Dataset"], model_shape(row), row["Optimizer"], row.get("Preprocessing", ""),
            row.get("TargetTransform", ""), row.get("Rounds", ""), row.get("ExperimentID", ""))


def grouped(rows):
    out = defaultdict(list)
    for row in rows:
        out[group_key(row)].append(row)
    return out


def group_sort(item):
    k, rows = item
    p = number(rows[0].get("Parameters"))
    return (k[0], p if p is not None else float('inf'), k[2], k[1])


def table_block(headers, rows, caption, label, columns=None):
    columns = columns or "l" + "r" * (len(headers) - 1)
    body = [r"\begin{table}[!htbp]", r"\centering", r"\small",
            r"\setlength{\tabcolsep}{4pt}", r"\renewcommand{\arraystretch}{1.18}",
            r"\begin{tabular}{@{}" + columns + r"@{}}", r"\toprule",
            " & ".join(headers) + r" \\", r"\midrule"]
    body += [" & ".join(row) + r" \\" for row in rows]
    body += [r"\bottomrule", r"\end{tabular}", r"\caption{\textsf{" + caption + "}}",
             r"\label{" + label + "}", r"\end{table}", ""]
    return "\n".join(body)


def weight_label(row):
    n = row.get("N", "")
    if str(n).lower() in ("eta", "none", "0") or "eta" in row["Dataset"].lower() and "chl" not in row["Dataset"].lower():
        return r"$\eta$"
    parsed = number(n)
    if parsed is None:
        m = re.search(r"N[_-]?(\d+)", row["Dataset"])
        parsed = float(m[1]) if m else None
    return f"$N={int(parsed)}$" if parsed is not None else tex(row["Dataset"])


def make_paper_table(index, rows, manifest, checkpoint):
    selected = [r for r in rows if paper_table(r) == index and r["Checkpoint"] == checkpoint]
    expected = [r for r in manifest if paper_table(r) == index]
    by_experiment = defaultdict(list)
    for row in selected:
        by_experiment[(row["Dataset"], row["Optimizer"], row.get("ExperimentID", ""), row["Model"])].append(row)
    expected_keys = {(r["Dataset"], r["Optimizer"], r.get("ExperimentID", ""), r["Model"]) for r in expected}
    keys = sorted(expected_keys | set(by_experiment), key=lambda k: ("eta" not in k[0].lower(), k))
    if not keys:
        keys = [(f"chl_N{n}", "", "", "Net3") for n in (1, 2, 3, 5, 7)]
        if index in (2, 6):
            keys.insert(0, ("eta", "", "", "Net3"))
    show_optimizer = index in (4, 5) or len({k[1] for k in keys if k[1]}) > 1
    headers = ["Experiment"] + (["Optimizer"] if show_optimizer else []) + ["Training loss", "Val.\\ loss", "Test MAPE (\\%)", "Test RMSE"]
    out = []
    incomplete = False
    for key in keys:
        runs = by_experiment.get(key, [])
        representative = runs[0] if runs else next((r for r in expected if (r["Dataset"], r["Optimizer"], r.get("ExperimentID", ""), r["Model"]) == key), {"Dataset": key[0]})
        label = weight_label(representative)
        n = len({r.get("Seed", r.get("Signature")) for r in runs})
        if n != 3:
            incomplete = True
            label += rf" $[n={n}]$"
        out.append([label] + ([tex(key[1] or "---")] if show_optimizer else []) + [
            cell(runs, "TrainLoss", False), cell(runs, "ValidationLoss", False),
            cell(runs, "TestMAPE"), cell(runs, "TestRMSE")])
    cp = "the final checkpoint" if checkpoint == "Final" else "the checkpoint selected by validation loss"
    family_label = "CHL and eta" if index in (2, 6) else "CHL"
    cap = (f"{family_label} results for {TABLES[index][2]}, using {cp}. "
           "Test MAPE is the mean absolute percentage error of the signed modular weight; "
           "test RMSE is in weight units. Predictions are transformed back from the fitted target "
           "before either test metric is evaluated. Losses are means in the fitted target space, "
           "as defined in the experimental protocol. Test entries show means across training seeds "
           "on a fixed split, with sample standard deviations when at least two seeds are available; "
           "the full study uses three seeds per row. ")
    configs = expected or selected
    budgets = sorted({int(v) for r in configs if (v := number(r.get("Rounds"))) is not None})
    if budgets:
        cap += "Training budget: " + ", ".join(f"${v}$" for v in budgets) + " rounds. "
    sizes = sorted({int(n) for r in configs if (n := number(r.get("Rows"))) is not None})
    if len(sizes) == 1:
        cap += f"Each dataset contains ${sizes[0]}$ rows. "
    elif sizes:
        cap += "Dataset sizes are " + ", ".join(f"${n}$" for n in sizes) + " rows; exact ranges are recorded with the data. "
    if index in (4, 5) and sizes:
        cap += "Repeated rational powers are kept in the same data partition. "
    models = {r.get("Model") for r in configs if r.get("Model")}
    if models == {"Net3"}:
        cap += "All rows use Net3. "
    elif "NotebookEtaFull" in models:
        cap += "CHL rows use Net3; the eta row uses the notebook architecture with hidden widths $(512,256,256,128,128,64,32)$. "
    optimizers = sorted({r.get("Optimizer") for r in configs if r.get("Optimizer")})
    if len(optimizers) == 1:
        cap += "Optimizer: " + tex(optimizers[0]) + ". "
    elif optimizers:
        cap += "The recorded optimizer choices are " + ", ".join(tex(x) for x in optimizers) + ", as shown per row. "
    if incomplete:
        cap += "Bracketed $n$ states the completed seed count when it differs from three; dashes denote unavailable results. "
    cap += f"This table replaces manuscript Table~{index}; its percentages are not errors of logarithmic targets."
    return table_block(headers, out, cap, f"tab:chl-revised-{index}-{checkpoint.lower()}",
                       "l" + ("l" if show_optimizer else "") + "rrrr")


def dataset_title(name):
    return {"eta_negative": r"Negative eta powers", "chl_N3_positive_integer": r"Positive CHL powers, $N=3$"}.get(name, tex(name))


def depth_tables(rows, checkpoint):
    by_dataset = defaultdict(list)
    for row in rows:
        if is_depth(row) and row["Checkpoint"] == checkpoint:
            by_dataset[row["Dataset"]].append(row)
    blocks = []
    for ds, entries in sorted(by_dataset.items()):
        lines = []
        for key, runs in sorted(grouped(entries).items(), key=group_sort):
            n = len(runs)
            params = number(runs[0].get("Parameters"))
            lines.append([model_tex(runs[0]), tex(runs[0]["Optimizer"]), str(int(params)) if params is not None else "---",
                          str(n), cell(runs, "TrainLoss", False), cell(runs, "ValidationLoss", False),
                          cell(runs, "TestMAPE"), cell(runs, "TestRMSE")])
        cp = "Final" if checkpoint == "Final" else "Validation-selected"
        cap = (dataset_title(ds) + ". " + cp + " checkpoint. Uniform architectures are labelled by "
               "hidden-layer count $D$ and width $h$; Net1 and Net3 retain their original tapered shapes. "
               "$P$ is the number of trainable parameters and $n$ the number of completed training seeds. "
               "Training and validation loss are in the fitted target space. Test MAPE is on signed weights "
               "and is reported as a percentage; test RMSE is in weight units. Test entries are mean "
               "$\\pm$ sample standard deviation. A single completed seed has no estimated standard deviation.")
        budgets = sorted({int(v) for r in entries if (v := number(r.get("Rounds"))) is not None})
        if budgets:
            cap += " Training budget: " + ", ".join(f"${v}$" for v in budgets) + " rounds."
        label = "tab:depth-" + re.sub(r"[^a-zA-Z0-9]+", "-", ds) + "-" + checkpoint.lower()
        blocks.append(table_block([r"$D\times h$ / model", "Optimizer", "$P$", "$n$", "Train loss", "Val.\\ loss", "MAPE (\\%)", "RMSE"],
                                  lines, cap, label, "llrrrrrr"))
    return "\n".join(blocks)


def findings(rows):
    best = [r for r in rows if is_depth(r) and r["Checkpoint"] == "Best"]
    final = [r for r in rows if is_depth(r) and r["Checkpoint"] == "Final"]
    if not best and not final:
        return "No completed depth/width fits were found. Numerical conclusions will be generated after training.\n"
    by_dataset = defaultdict(list)
    for row in best:
        by_dataset[row["Dataset"]].append(row)
    text = []
    for ds, entries in sorted(by_dataset.items()):
        groups = grouped(entries)
        complete = {k: v for k, v in groups.items() if len(v) == 3 and all(number(r.get(m)) is not None for r in v for m in ("TestMAPE", "TestRMSE"))}
        text.append(r"\paragraph{" + dataset_title(ds) + ".}")
        if not complete:
            text.append("No architecture has three completed seeds with both finite test metrics; comparative findings are withheld.")
            continue
        winners = {metric: min(complete.items(), key=lambda item: mean_sd(item[1], metric)[0]) for metric in ("TestMAPE", "TestRMSE")}
        for metric, (key, rs) in winners.items():
            name = "MAPE" if metric == "TestMAPE" else "RMSE"
            value = cell(rs, metric)
            unit = r"\%" if metric == "TestMAPE" else ""
            text.append(f"Among completed three-seed configurations, the lowest mean validation-selected test {name} "
                        f"is obtained by {model_tex(rs[0])} with {tex(rs[0]['Optimizer'])}: {value}{unit}.")
        if winners["TestMAPE"][0] != winners["TestRMSE"][0]:
            text.append("The two metrics rank the best configurations differently. MAPE gives a larger relative importance to low-weight examples, whereas RMSE emphasizes large absolute errors.")
        else:
            text.append("The same configuration minimizes both reported mean test metrics within this grid.")
        primary = "ADAM" if ds == "eta_negative" else "RMSProp"
        for width in (16, 128):
            shallow = next((v for k, v in complete.items() if k[1] == f"1x{width}" and k[2] == primary), None)
            deep = next((v for k, v in complete.items() if k[1] == f"3x{width}" and k[2] == primary), None)
            if shallow and deep:
                text.append(f"At width ${width}$ with {tex(primary)}, changing from one to three hidden layers "
                            f"changes mean test MAPE from ${fmt(mean_sd(shallow, 'TestMAPE')[0])}\\%$ to "
                            f"${fmt(mean_sd(deep, 'TestMAPE')[0])}\\%$, and mean test RMSE from "
                            f"${fmt(mean_sd(shallow, 'TestRMSE')[0])}$ to ${fmt(mean_sd(deep, 'TestRMSE')[0])}$.")
        for architecture in ("1x128", "Net1" if ds == "eta_negative" else "Net3"):
            adam = next((v for k, v in complete.items() if k[1] == architecture and k[2] == "ADAM"), None)
            rms = next((v for k, v in complete.items() if k[1] == architecture and k[2] == "RMSProp"), None)
            if adam and rms:
                text.append(f"For {model_tex(adam[0])}, Adam and RMSProp respectively give mean test MAPE "
                            f"${fmt(mean_sd(adam, 'TestMAPE')[0])}\\%$ and ${fmt(mean_sd(rms, 'TestMAPE')[0])}\\%$, "
                            f"and mean test RMSE ${fmt(mean_sd(adam, 'TestRMSE')[0])}$ and ${fmt(mean_sd(rms, 'TestRMSE')[0])}$. "
                            "This comparison concerns the recorded optimizer settings, not independently tuned optimizer families.")
        text.append("Comparisons of different depths also change parameter count; they do not isolate depth at fixed capacity. Test rankings are descriptive and are not used to choose checkpoints or tune hyperparameters.")
    text.append(r"\paragraph{Training budget and checkpoint choice.}")
    best_groups, final_groups = grouped(best), grouped(final)
    comparisons = []
    for key in set(best_groups) & set(final_groups):
        b, f = mean_sd(best_groups[key], "TestRMSE")[0], mean_sd(final_groups[key], "TestRMSE")[0]
        if b is not None and f is not None and b > 0 and len(best_groups[key]) == len(final_groups[key]) == 3:
            comparisons.append((f/b, key, b, f, best_groups[key][0]))
    if comparisons:
        ratio, key, b, f, sample = max(comparisons)
        text.append("Both checkpoint conventions are tabulated. The largest ratio of final to validation-selected mean test RMSE among complete configurations is "
                    f"${fmt(ratio)}$, for {dataset_title(key[0])}, {model_tex(sample)}, {tex(key[2])} "
                    f"(${fmt(f)}$ versus ${fmt(b)}$). Validation selection does not guarantee lower error on every held-out test set.")
    text.append(r"\paragraph{Capacity and interpolation.}")
    trained = [number(r.get("TrainNRMSE")) for r in final]
    trained = [v for v in trained if v is not None]
    if trained:
        text.append(f"At the final checkpoint, ${sum(v <= .001 for v in trained)}$ of ${len(trained)}$ completed fits "
                    "have training NRMSE at most $10^{-3}$, with NRMSE normalized by the training-set standard deviation of the physical weight. "
                    "This threshold is a numerical convention for near interpolation. A double-descent claim would additionally require a reproducible test-error peak near a resolved interpolation transition and a subsequent decline. "
                    "Neither having more parameters than examples nor an isolated non-monotone error curve establishes that claim.")
    else:
        text.append("Training NRMSE was not exported, so this report makes no claim about an interpolation threshold or double descent.")
    return "\n\n".join(text) + "\n"


def protocol(rows):
    rounds = sorted({int(v) for r in rows if (v := number(r.get("Rounds"))) is not None})
    transforms = sorted({r.get("TargetTransform", "") for r in rows if r.get("TargetTransform")})
    budgets = ", ".join(str(x) for x in rounds) or "not yet recorded"
    trans = ", ".join(r"\texttt{" + tex(x) + "}" for x in transforms) or "specified in the run manifest"
    inputs = sorted({r.get("InputTransform", r.get("Preprocessing", "")) for r in rows
                     if r.get("InputTransform", r.get("Preprocessing", ""))})
    input_text = ", ".join(r"\texttt{" + tex(x) + "}" for x in inputs) or "specified in the run manifest"
    explanation = []
    if "LogAbsL2" in inputs:
        explanation.append(r"For \texttt{LogAbsL2}, coefficient magnitudes are logged and the resulting vector is normalized to unit Euclidean norm; exactly zero coefficients are mapped to zero while retaining their positions.")
    if "L2" in inputs:
        explanation.append(r"For \texttt{L2}, raw coefficient vectors are normalized to unit Euclidean norm.")
    if "StandardizedWeight" in transforms:
        explanation.append("Standardized weights use only the training-set mean and sample standard deviation; the same transformation is applied to validation and test data.")
    if "LogAbsPower" in transforms:
        explanation.append(r"For \texttt{LogAbsPower}, the fitted target is $\log|s|$, where $s$ is the power; a predicted value $z$ is decoded as $\widehat w=\operatorname{sgn}(s)K_0 e^z$, with the known weight $K_0$ of the parent form.")
    explanation_text = "\n".join(explanation)
    return rf"""All test metrics are evaluated after predictions have been returned to the signed physical weight $w$:
\begin{{align}}
 \mathrm{{MAPE}} &= \frac{{100}}{{n}}\sum_{{i=1}}^n
              \frac{{|\widehat w_i-w_i|}}{{|w_i|}},\\
 \mathrm{{RMSE}} &= \sqrt{{\frac1n\sum_{{i=1}}^n(\widehat w_i-w_i)^2}}.
\end{{align}}
The CHL datasets have nonzero weights. Thus their MAPE requires no omission of
zero targets and is not a percentage error of a logarithm. When a logarithmic
target is fitted, its transformation is inverted before these metrics are
computed, including the known sign and family-dependent conversion from power
to weight. Training and validation losses remain in the fitted target space;
their numerical values should not be compared across different target transformations.
Recorded input transformations: {input_text}. Recorded target transformations:
{trans}. Recorded training budgets: {budgets} rounds.
{explanation_text}
The final checkpoint and the checkpoint minimizing validation loss are reported
separately. Test errors play no part in checkpoint selection. Error bars are sample
standard deviations over training seeds on fixed data partitions, not confidence
intervals over alternative partitions or modular-form families.
"""


def extra_e2_tables(rows):
    entries = [r for r in rows if r.get("Study", "").lower() == "e2" and r["Checkpoint"] == "Best"]
    if not entries:
        return ""
    body = "\\section{Optional Eisenstein-series diagnostic}\n"
    for ds in sorted({r["Dataset"] for r in entries}):
        lines = []
        for _, rs in sorted(grouped([r for r in entries if r["Dataset"] == ds]).items(), key=group_sort):
            lines.append([model_tex(rs[0]), tex(rs[0]["Optimizer"]), tex(rs[0].get("InputTransform", rs[0].get("Preprocessing", ""))),
                          cell(rs, "TrainLoss", False), cell(rs, "ValidationLoss", False), cell(rs, "TestMAPE"), cell(rs, "TestRMSE")])
        body += table_block(["Model", "Optimizer", "Input", "Train loss", "Val.\\ loss", "MAPE (\\%)", "RMSE"], lines,
                            "Optional diagnostic for " + tex(ds) + ". Checkpoints are selected by validation loss. "
                            "MAPE and RMSE concern the physical quasimodular weight, with its weight shift included. "
                            "If zero-weight targets occur, relative errors are undefined for them; inspect the exported zero-target counts. "
                            "Training and validation losses refer to the fitted target. These results do not replace a manuscript row with a different dataset or coefficient range.",
                            "tab:e2-" + re.sub(r"[^a-zA-Z0-9]+", "-", ds), "lllrrrr")
    return body


def write_outputs(directory, output, rows, manifest, checkpoint, depth_only=False, historical=False):
    output.mkdir(parents=True, exist_ok=True)
    snippets = output / "snippets"
    snippets.mkdir(exist_ok=True)
    neural_ids = {run_key(r, False) for r in rows if is_depth(r)}
    n = len(neural_ids)
    smoke = is_smoke(rows + manifest)
    summary = (r"\section{Additional validation}" + "\n" + r"\label{app:additional-validation}" + "\n\n" +
               (r"\noindent\textbf{Compatibility check only. These short, single-seed runs test that the software executes. They provide no evidence for scientific comparisons of architectures, optimizers or prediction accuracy.}" + "\n\n" if smoke else "") +
               ("This report describes the earlier $1000$-round experiments. In particular, their CHL inputs were raw coefficient vectors normalized to unit Euclidean norm and their fitted targets were standardized physical weights. "
                "They are separate from the new default $10000$-round CHL protocol, which uses logarithmic inputs and targets. " if historical else "") +
               f"This study examines width, depth and optimizer dependence on two representative power families. "
               f"The planned depth/width study comprises $78$ seeded neural fits. This report contains ${n}$ distinct completed fits. " +
               ("The grid is incomplete; numerical summaries below use only completed runs. " if n != 78 else "") +
               "Uniform networks have one, three or six hidden ReLU layers; the original Net1 and Net3 are included as references. "
               "The wider and deeper architectures are compared on the same data splits and training budget within each study.\n\n" +
               protocol([r for r in rows if is_depth(r)]) + "\n" +
               ("Empirical rankings and scientific findings are intentionally omitted for this compatibility check.\n" if smoke else findings(rows)) + "\n" +
               (r"\clearpage" + "\n" + r"\subsection{Validation-selected checkpoints}" + "\n" + depth_tables(rows, "Best") + "\n" +
                r"\clearpage" + "\n" + r"\subsection{Final checkpoints}" + "\n" + depth_tables(rows, "Final") + "\n" if n else "") +
               r"\paragraph{Scope.}" + "\n" +
               "These experiments measure prediction within restricted power families. They do not establish extrapolation to new modular-form families or the necessity of neural networks. "
               "For full eta coefficient vectors, the weight is recovered exactly from $-a_1/(2a_0)$. "
               "For CHL eta products at $N>1$, the corresponding predictor is $-a_1/a_0$; at $N=1$ it is $-a_1/(2a_0)$. "
               "These identities are elementary baselines, not learned results, and apply when the required coefficients are retained.\n")
    (snippets / "depth_width_appendix.tex").write_text("% Requires amsmath and booktabs. No document preamble.\n" + summary, encoding="utf-8")
    if not depth_only:
        for index in TABLES:
            for cp in ("Best", "Final"):
                (snippets / f"chl_table_{index}_{cp.lower()}.tex").write_text(
                    make_paper_table(index, rows, manifest, cp), encoding="utf-8")
    preamble = r"""\documentclass[10pt]{article}
\usepackage[margin=0.65in]{geometry}
\usepackage{amsmath,amssymb,booktabs}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage{microtype}
\usepackage[hidelinks]{hyperref}
\setlength{\parindent}{0pt}
\setlength{\parskip}{0.45em}
\newcommand\capt[1]{\caption{\textsf{#1}}}
\title{TITLEPLACEHOLDER}
\author{}
\date{}
\begin{document}
\maketitle
"""
    title = "Compatibility check only: no scientific results" if smoke else ("Earlier 1000-round depth/width study" if historical else "Additional validation and CHL weight prediction")
    preamble = preamble.replace("TITLEPLACEHOLDER", title)
    body = r"\input{snippets/depth_width_appendix.tex}" + "\n"
    if not depth_only:
        body += "\\clearpage\n\\section{CHL tables}\n" + protocol([r for r in rows if paper_table(r)])
        body += ("The tables below use " + ("final" if checkpoint == "Final" else "validation-selected") +
                 " checkpoints. The alternate checkpoint tables are supplied as separate snippets. "
                 "These new weight errors must not be substituted for earlier log-target errors without updating the metric definition and captions.\n\\clearpage\n")
        for index in TABLES:
            body += f"\\subsection{{{TABLES[index][1]}}}\n\\input{{snippets/chl_table_{index}_{checkpoint.lower()}.tex}}\n"
            if index in (3, 5, 7):
                body += "\\clearpage\n"
        body += extra_e2_tables(rows)
    body += r"\end{document}" + "\n"
    (output / "report.tex").write_text(preamble + body, encoding="utf-8")
    # One row per checkpoint, preserving all available settings and linking signature.
    columns = ["Signature", "Checkpoint", "Study", "PaperTable", "ExperimentID", "Dataset", "N", "Model",
               "HiddenLayers", "Width", "Optimizer", "Seed", "Rounds", "Parameters", "Preprocessing", "InputTransform", "TargetTransform",
               "TrainLoss", "ValidationLoss", "TestMAPE", "TestRMSE", "TrainNRMSE", "BestValidationRound"]
    with (output / "run_index.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(sorted(rows, key=lambda r: (r.get("Study", ""), r["Dataset"], r["Model"], r["Optimizer"], r["Seed"], r["Checkpoint"])))
    notes = ["Generated from: " + str(directory.resolve()), "Distinct depth/width fits: " + str(n),
             "Checkpoint selected for CHL paper tables: " + checkpoint,
             "All test MAPE and RMSE columns are weight metrics; no log-target errors are substituted.",
             "Table snippets have no preamble. Load amsmath and booktabs in the manuscript.",
             "Compile report.tex from this directory with: pdflatex -halt-on-error report.tex (twice)."]
    if smoke:
        notes.insert(0, "COMPATIBILITY CHECK ONLY: short, single-seed runs; no empirical rankings or scientific conclusions.")
    missing = sum(any(number(r.get(k)) is None for k in ("TrainLoss", "ValidationLoss", "TestMAPE", "TestRMSE")) for r in rows)
    if missing:
        notes.append(f"WARNING: {missing} checkpoint rows lack one or more finite metrics. Dashes remain visible.")
    (output / "REPORT_STATUS.txt").write_text("\n".join(notes) + "\n", encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", required=True, type=Path, help="One results directory containing metrics exports and its manifest")
    parser.add_argument("--output", type=Path, help="Default: <results>/reports")
    parser.add_argument("--checkpoint", choices=("Best", "Final"), default="Best", help="Checkpoint used in CHL paper tables")
    parser.add_argument("--compile", action="store_true", help="Compile the standalone report twice with pdflatex")
    parser.add_argument("--depth-only", action="store_true", help="Omit CHL paper tables from standalone report")
    parser.add_argument("--historical", action="store_true", help="Explicitly label the earlier 1000-round raw-L2 study")
    parser.add_argument("--allow-partial", action="store_true", help="Emit visibly incomplete tables while some planned fits are missing")
    args = parser.parse_args(argv)
    if not args.results.is_dir():
        parser.error("--results must be an existing results directory")
    try:
        rows, manifest, files = load_results(args.results)
        validate_rows(rows, args.historical)
        if not args.allow_partial:
            require_complete(rows, manifest)
        output = (args.output or args.results / "reports").resolve()
        write_outputs(args.results, output, rows, manifest, args.checkpoint, args.depth_only, args.historical)
        if args.compile:
            executable = shutil.which("pdflatex")
            if not executable:
                print("TeX sources were generated. PDF compilation was skipped because pdflatex is not installed; compile report.tex with a TeX distribution or Overleaf.", file=sys.stderr)
                print(f"Report: {output / 'report.tex'}")
                return 0
            for _ in range(2):
                process = subprocess.run([executable, "-halt-on-error", "-interaction=nonstopmode", "report.tex"],
                                         cwd=output, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                (output / "compile.log").write_text(process.stdout, encoding="utf-8")
                if process.returncode:
                    raise RuntimeError("LaTeX failed; inspect " + str(output / "compile.log"))
        print(f"Read {len(rows)} checkpoint rows from {', '.join(files) or 'no completed metric exports'}. Report: {output / 'report.tex'}")
        return 0
    except (ValueError, RuntimeError, OSError) as error:
        print("Report generation failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
