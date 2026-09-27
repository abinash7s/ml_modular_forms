#!/usr/bin/env python3
"""Portable configuration and exact-mathematics checks; no Wolfram kernel or fits.

Run: python3 tests/check_bundle.py
These checks complement, rather than replace, scripts/run.wls --test / run.sh --test.
The independent finite-product calculation uses exact generalized binomials,
not a numerical fit or imported training results.
"""
from collections import Counter
import csv
from fractions import Fraction
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = json.loads((ROOT / "config/defaults.json").read_text())
EXPERIMENTS = json.loads((ROOT / "config/experiments.json").read_text())
DATASETS = json.loads((ROOT / "config/datasets.json").read_text())
SLICE = [2, 4, 5, 10, 13, 14, 15, 16, 18, 21, 22, 23, 25, 27, 29]


def powers_from_file(filename):
    text = (ROOT / "resources" / filename).read_text()
    text = re.sub(r"\(\*.*?\*\)", "", text, flags=re.S).strip()
    if not (text.startswith("{") and text.endswith("}")):
        raise ValueError("Expected one Wolfram list")
    tokens = [re.sub(r"[\s()]", "", token) for token in text[1:-1].split(",")]
    if any(not re.fullmatch(r"-?\d+(?:/\d+)?", token) for token in tokens):
        raise ValueError("Unexpected expression in bundled rational powers")
    return [Fraction(token) for token in tokens]


def powers_for(spec):
    if "PowersFile" in spec:
        return powers_from_file(spec["PowersFile"])
    values = spec.get("PowerRange", spec.get("PowerHalfIntegerRange"))
    start, stop, *step = values
    increment = step[0] if step else 1
    result = list(range(start, stop + (1 if increment > 0 else -1), increment))
    return [Fraction(v, 2 if "PowerHalfIntegerRange" in spec else 1) for v in result]


def multiply(a, b, count):
    result = [Fraction(0)] * count
    for i, ai in enumerate(a[:count]):
        if ai:
            for j, bj in enumerate(b[:count - i]):
                if bj:
                    result[i + j] += ai * bj
    return result


def finite_product(terms, count=30):
    """Directly multiply (1-q^(d*n))^r, using binomial coefficients."""
    series = [Fraction(1)] + [Fraction(0)] * (count - 1)
    for scale, exponent in terms:
        for degree in range(scale, count, scale):
            factor = [Fraction(0)] * count
            binomial = Fraction(1)
            factor[0] = 1
            for m in range(1, (count - 1) // degree + 1):
                binomial *= (exponent - m + 1) / m
                factor[m * degree] = (-1) ** m * binomial
            series = multiply(series, factor, count)
    return series


def logarithmic_derivative_series(terms, count=30):
    """Exact recurrence documented in Data.wl, independently compared to products."""
    a = [Fraction(1)] + [Fraction(0)] * (count - 1)
    b = [Fraction(0)] * count
    for k in range(1, count):
        for scale, exponent in terms:
            if k % scale == 0:
                n = k // scale
                sigma = sum(d for d in range(1, n + 1) if n % d == 0)
                b[k] -= exponent * scale * sigma
        a[k] = sum(b[j] * a[k - j] for j in range(1, k + 1)) / k
    return a


class ConfigurationChecks(unittest.TestCase):
    def test_default_fit_count_and_budget(self):
        self.assertEqual(DEFAULTS["Rounds"], 10000)
        self.assertEqual(DEFAULTS["Seeds"], [101, 102, 103])
        counts = Counter(e["Study"] for e in EXPERIMENTS)
        self.assertEqual(counts, {"width_depth": 26, "chl": 32, "e2": 3})
        self.assertEqual(3 * (counts["width_depth"] + counts["chl"]), 174)
        self.assertEqual(3 * counts["width_depth"], 78)
        self.assertEqual(3 * counts["chl"], 96)
        self.assertEqual(len({e["ExperimentID"] for e in EXPERIMENTS}), len(EXPERIMENTS))

    def test_manuscript_cases_and_optimizer_overrides(self):
        with (ROOT / "docs/chl_paper_case_map.csv").open(newline="") as handle:
            paper = {r["Case"]: r for r in csv.DictReader(handle)}
        actual = {e["ExperimentID"]: e for e in EXPERIMENTS if e["Study"] == "chl"}
        self.assertEqual(set(actual), set(paper))
        self.assertEqual(Counter(e["PaperTable"] for e in actual.values()),
                         {2: 6, 3: 5, 4: 5, 5: 5, 6: 6, 7: 5})
        for key, e in actual.items():
            with self.subTest(case=key):
                audited = paper[key]
                self.assertEqual(e["Optimizer"], audited["Optimizer"])
                self.assertEqual(e["MethodOptions"], json.loads(audited["MethodOptions"]))
                self.assertEqual(Fraction(str(e["WeightFactor"])), Fraction(audited["PhysicalWeightScale"]))
                self.assertEqual(e["PowerSign"], int(audited["Sign"]))
                self.assertEqual(e["InputTransform"], "LogAbsL2")
                self.assertEqual(e["TargetTransform"], "LogAbsPower")
                self.assertEqual(e["LearningRateSchedule"], "Automatic")
                self.assertEqual(e["FeaturePositions"], [int(p) for p in audited["CoefficientPositions"].split(";")])
                self.assertEqual(e["FeaturePositions"], SLICE if e["PaperTable"] in (6, 7) else list(range(1, 31)))
                spec = DATASETS[e["Dataset"]]
                powers = powers_for(spec)
                self.assertEqual(len(powers), int(audited["Rows"]))
                self.assertTrue(all(p * e["PowerSign"] > 0 for p in powers))
                if e["Family"] == "CHL":
                    self.assertEqual(Fraction(str(e["WeightFactor"])), Fraction(24, int(e["N"]) + 1))

    def test_original_rational_lists_and_duplicate_counts(self):
        for kind, unique, sign in (("positive", 1857, 1), ("negative", 1852, -1)):
            powers = powers_from_file(f"chl_rational_{kind}.wl")
            self.assertEqual(len(powers), 2000)
            self.assertEqual(len(set(powers)), unique)
            self.assertTrue(all(sign * p > 0 for p in powers))
            self.assertTrue(any(abs(p) < 1 for p in powers))

    def test_depth_grid_and_metric_compatible_chl_reference(self):
        for dataset in ("eta_negative", "chl_N3_positive_integer"):
            rows = [e for e in EXPERIMENTS if e["Study"] == "width_depth" and e["Dataset"] == dataset]
            self.assertEqual(len(rows), 13)
            deep = {tuple(e["LayerWidths"]) for e in rows if str(e["Model"]).startswith("Depth")}
            self.assertEqual(deep, {(16,) * 3, (128,) * 3, (16,) * 6, (128,) * 6})
        reference = next(e for e in EXPERIMENTS if e["ExperimentID"] == "wd_chl_N3_positive_integer_Net3_RMSProp")
        paper = next(e for e in EXPERIMENTS if e["ExperimentID"] == "table2_N3")
        for key in ("Dataset", "Model", "Optimizer", "InputTransform", "TargetTransform", "FeaturePositions", "WeightFactor", "PowerSign", "LearningRateSchedule", "MethodOptions"):
            self.assertEqual(reference[key], paper[key])

    def test_plan_never_calls_wolfram_or_writes_results(self):
        # Execute a copy, so even a regression cannot alter user results.
        with tempfile.TemporaryDirectory(prefix="modular-plan-check-") as temp:
            root = Path(temp)
            shutil.copytree(ROOT / "config", root / "config")
            (root / "scripts").mkdir()
            shutil.copy2(ROOT / "scripts/plan.py", root / "scripts/plan.py")
            shutil.copy2(ROOT / "run.sh", root / "run.sh")
            (root / "bin").mkdir()
            marker = root / "WOLFRAM_WAS_CALLED"
            stub = root / "bin/wolframscript"
            stub.write_text('#!/bin/sh\ntouch "$PLAN_CHECK_MARKER"\nexit 99\n')
            stub.chmod(0o755)
            env = dict(os.environ, PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
                       PLAN_CHECK_MARKER=str(marker))
            for arguments, count in (([], 174), (["--suite", "width-depth"], 78),
                                     (["--suite", "chl"], 96), (["--with-e2"], 183)):
                proc = subprocess.run(["bash", str(root / "run.sh"), "--plan", *arguments],
                                      cwd=root, env=env, text=True, capture_output=True, timeout=20)
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertIn(f"Total: {count} scheduled fits", proc.stdout)
                self.assertFalse(marker.exists(), "--plan invoked Wolfram")
                self.assertFalse((root / "results").exists(), "--plan wrote results")


class ExactMathematicsChecks(unittest.TestCase):
    def test_all_chl_levels_against_finite_products(self):
        for level in (1, 2, 3, 5, 7):
            for power in (Fraction(2), Fraction(-2), Fraction(3, 7), Fraction(-5, 3)):
                with self.subTest(level=level, power=power):
                    weight = Fraction(24, level + 1) * power
                    terms = [(1, weight), (level, weight)]
                    product = finite_product(terms)
                    self.assertEqual(product, logarithmic_derivative_series(terms))
                    self.assertEqual(-product[1] / (2 if level == 1 else 1), weight)
                    self.assertEqual(sum(Fraction(d) * r / 24 for d, r in terms), power)

    def test_eta_zero_positions_and_partition_sequence(self):
        self.assertEqual(finite_product([(1, Fraction(1))], 8), [1, -1, -1, 0, 0, 1, 0, 1])
        self.assertEqual(finite_product([(1, Fraction(-1))], 8), [1, 1, 2, 3, 5, 7, 11, 15])

    def test_e2_eta_total_weight_and_ratio(self):
        e2 = [Fraction(1)] + [Fraction(-24 * sum(d for d in range(1, n + 1) if n % d == 0)) for n in range(1, 30)]
        self.assertEqual(multiply(e2, e2, 5), [1, -48, 432, 3264, 9456])
        for eta_weight in (Fraction(1, 2), Fraction(7, 2), Fraction(100)):
            coefficients = [2 * x for x in multiply(e2, finite_product([(1, 2 * eta_weight)]), 30)]
            self.assertEqual(-coefficients[1] / (2 * coefficients[0]) - 10, eta_weight + 2)

    def test_log_decoding_is_signed_physical_weight(self):
        # Includes negative powers and |power|<1, for which the latent target is negative.
        for level in (1, 2, 3, 5, 7):
            for power in (-1000, -0.125, 0.125, 1000):
                factor = 24 / (level + 1)
                decoded = math.copysign(factor * math.exp(math.log(abs(power))), power)
                self.assertAlmostEqual(decoded / (factor * power), 1, places=12)


class ReportContractChecks(unittest.TestCase):
    def test_table_schema_and_metric_captions(self):
        module_spec = importlib.util.spec_from_file_location("validation_reports_check", ROOT / "scripts/make_reports.py")
        reports = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(reports)
        manifest = [dict(e, Model=str(e["Model"])) for e in EXPERIMENTS if e["Study"] == "chl"]
        for table in range(2, 8):
            tex = reports.make_paper_table(table, [], manifest, "Best")
            self.assertIn("Test MAPE", tex)
            self.assertIn("Test RMSE", tex)
            self.assertIn(r"\caption{\textsf{", tex)
            self.assertIn("signed modular weight", tex)
            self.assertIn("transformed back", tex)
            self.assertIn("[n=0]", tex)
            self.assertIn("unavailable", tex.lower())
            self.assertIn(r"\begin{tabular}", tex)


if __name__ == "__main__":
    unittest.main(verbosity=2)
