#!/usr/bin/env python3
"""Read-only plan and configuration checks; no Wolfram kernel is required."""
import argparse
import collections
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def load_selection(suite="all", with_e2=False, only=""):
    defaults = json.loads((ROOT / "config/defaults.json").read_text())
    experiments = json.loads((ROOT / "config/experiments.json").read_text())
    datasets = json.loads((ROOT / "config/datasets.json").read_text())
    if defaults.get("CoefficientCount") != 30 or defaults.get("SplitFractions") != [0.75, 0.15, 0.10]:
        raise ValueError("This study fixes 30 generated coefficients and 75/15/10 group splits")
    if defaults.get("DefaultSuites") != ["width_depth", "chl"]:
        raise ValueError("Use --suite or --with-e2 to select suites; keep DefaultSuites unchanged")
    permitted = {"width_depth", "chl", "e2"} if with_e2 else {"width_depth", "chl"}
    if suite != "all":
        permitted = {"width_depth" if suite == "width-depth" else suite}
    selected = [e for e in experiments if e["Study"] in permitted]
    if only:
        requested = set(only.split(","))
        unknown = requested - {e["ExperimentID"] for e in selected}
        if unknown:
            raise ValueError("Unknown or excluded experiment IDs: " + ", ".join(sorted(unknown)))
        selected = [e for e in selected if e["ExperimentID"] in requested]
    if not selected:
        raise ValueError("No experiments selected")
    if len({e["ExperimentID"] for e in experiments}) != len(experiments):
        raise ValueError("Duplicate experiment IDs")
    if len(set(defaults["Seeds"])) != len(defaults["Seeds"]):
        raise ValueError("Duplicate seeds")
    for e in experiments:
        if e["Dataset"] not in datasets:
            raise ValueError("Dataset missing for " + e["ExperimentID"])
        positions = e["FeaturePositions"]
        if len(set(positions)) != len(positions) or not all(1 <= p <= 30 for p in positions):
            raise ValueError("Invalid feature positions for " + e["ExperimentID"])
        if e["TargetTransform"] == "LogAbsPower" and e["PowerSign"] not in (-1, 1):
            raise ValueError("Invalid decoding sign")
    return defaults, selected

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--suite", choices=["all", "width-depth", "chl", "e2"], default="all")
    p.add_argument("--with-e2", action="store_true")
    p.add_argument("--only", default="")
    p.add_argument("--rounds", "--epochs", type=int)
    p.add_argument("--list", action="store_true")
    args = p.parse_args()
    try:
        defaults, selected = load_selection(args.suite, args.with_e2, args.only)
        rounds = defaults["Rounds"] if args.rounds is None else args.rounds
        if rounds < 1:
            raise ValueError("Rounds must be positive")
    except (ValueError, KeyError) as e:
        p.error(str(e))
    counts = collections.Counter(e["Study"] for e in selected)
    seeds = defaults["Seeds"]
    print("Plan only: no generation, training, or result writing.")
    print(f"Epochs per fit: {rounds}; seeds: {seeds}; batch size: {defaults['BatchSize']}")
    for study, count in sorted(counts.items()):
        print(f"  {study}: {count} configurations x {len(seeds)} seeds = {count * len(seeds)} fits")
    print(f"Total: {len(selected) * len(seeds)} scheduled fits")
    print("CHL: log-absolute-coefficient inputs; log-absolute-power training; MAPE and RMSE on decoded weights.")
    print("Identical rational powers remain in the same split. All error percentages use absolute denominators.")
    if args.list:
        for e in selected:
            print(f"{e['ExperimentID']}: {e['Model']}, {e['Optimizer']}, {len(e['FeaturePositions'])} inputs")

if __name__ == "__main__":
    main()
