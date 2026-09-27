(* Run through scripts/run_tests.wls; every mathematical assertion uses exact arithmetic. *)
VerificationTest[
  ValidationData`EtaProductCoefficients[{{1, 1}}, 8],
  {1, -1, -1, 0, 0, 1, 0, 1},
  TestID -> "Euler-product-zeros-preserved"]

VerificationTest[
  ValidationData`EtaProductCoefficients[{{1, -1}}, 8],
  {1, 1, 2, 3, 5, 7, 11, 15},
  TestID -> "Partition-coefficients"]

VerificationTest[
  ValidationData`EtaProductCoefficients[{{1, 3}, {1, 3}}, 12] ===
    ValidationData`EtaProductCoefficients[{{1, 6}}, 12],
  True, TestID -> "N1-duplicate-eta-factor"]

VerificationTest[
  Module[{rows}, rows = ValidationData`GenerateRows["chl", <|"Family" -> "CHL", "Level" -> 3,
    "Powers" -> {2, -2, 3/7}, "CoefficientCount" -> 8|>];
    {Lookup[rows, "Target"], ValidationData`ExactBaseline /@ rows}],
  {{12, -12, 18/7}, {12, -12, 18/7}}, TestID -> "CHL-physical-weight-not-log"]

VerificationTest[
  And @@ Table[Module[{r}, r = First[ValidationData`GenerateRows["chl", <|"Family" -> "CHL",
      "Level" -> n, "Powers" -> {5/3}, "CoefficientCount" -> 8|>]];
    ValidationData`ExactBaseline[r] === r["Target"]], {n, {1, 2, 3, 5, 7}}],
  True, TestID -> "CHL-exact-baseline-all-levels"]

VerificationTest[
  Module[{rows}, rows = ValidationData`GenerateRows["eta", <|"Family" -> "Eta",
      "Powers" -> {-1, -400, 3/2}, "CoefficientCount" -> 8|>];
    ValidationData`ExactBaseline /@ rows],
  {-1/2, -200, 3/4}, TestID -> "Eta-weight-is-half-exponent"]

VerificationTest[
  ValidationData`SeriesPowerCoefficients[{1, -24, -72, -96, -168}, 2],
  {1, -48, 432, 3264, 9456}, TestID -> "E2-squared-coefficients"]

VerificationTest[
  Module[{rows}, rows = ValidationData`GenerateRows["e2eta", <|"Family" -> "E2Eta",
      "Powers" -> {1/2, 100}, "CoefficientCount" -> 8|>];
    {Lookup[rows, "Target"], ValidationData`ExactBaseline /@ rows}],
  {{5/2, 102}, {5/2, 102}}, TestID -> "E2-eta-corrected-total-weight"]

VerificationTest[
  Module[{rows}, rows = ValidationData`GenerateRows["duplicates", <|"Family" -> "CHL", "Level" -> 3,
      "Powers" -> {2/3, 4/6, 7/5}, "CoefficientCount" -> 8|>];
    {Length[DeleteDuplicates[Lookup[rows, "ID"]]], Length[DeleteDuplicates[Lookup[rows, "Group"]]]}],
  {3, 2}, TestID -> "Duplicate-powers-share-split-group"]

VerificationTest[
  Module[{r}, r = First[ValidationData`GenerateRows["slice", <|"Family" -> "Eta", "Powers" -> {1},
      "CoefficientCount" -> 8, "Positions" -> {2, 3, 5}|>]];
    {r["Coefficients"], r["Positions"], MissingQ[ValidationData`ExactBaseline[r]]}],
  {{-1, 0, 1}, {2, 3, 5}, True}, TestID -> "Slice-retains-original-q-positions"]

VerificationTest[
  FailureQ[ValidationData`GenerateRows["invalid", <|"Family" -> "CHL", "Level" -> 3, "Powers" -> {1.5}|>]],
  True, TestID -> "Reject-inexact-data-grid"]

VerificationTest[
  ValidationData`ResolveDatasetSpec[<|"Family" -> "CHL", "Level" -> 3, "PowerRange" -> {-2, -4, -1}|>, "."]["Powers"],
  {-2, -3, -4}, TestID -> "Resolve-negative-integer-grid"]

VerificationTest[
  ValidationData`ResolveDatasetSpec[<|"Family" -> "E2Eta", "PowerHalfIntegerRange" -> {1, 4}|>, "."]["Powers"],
  {1/2, 1, 3/2, 2}, TestID -> "Resolve-exact-half-integer-grid"]
