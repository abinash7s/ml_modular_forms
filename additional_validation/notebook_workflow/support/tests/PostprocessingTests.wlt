(* Regression tests for fitting, evaluation, and cache finalization.
   The test driver loads src/Training.wl first. These tests never call NetTrain. *)

VerificationTest[
 Module[{rows, fitted, applied, prep, expectedMean},
  rows = (<|"Coefficients" -> #|> &) /@ {{1, 0, 2}, {1, 0, 8}, {1, 0, 100}, {1, 0, 1000}};
  fitted = UnifiedTraining`Private`fitInputs[rows, {1, 2},
    <|"InputTransform" -> "SignedLogStandardized"|>];
  If[FailureQ[fitted], Return[False]];
  prep = fitted["Preprocessor"];
  applied = UnifiedTraining`Private`applyInputs[rows, prep];
  expectedMean = Mean[UnifiedTraining`TransformInputs[
    Lookup[rows[[{1, 2}]], "Coefficients"], "SignedLogStandardized"]];
  AssociationQ[prep] && KeyExistsQ[prep, "Mean"] && KeyExistsQ[prep, "Scale"] &&
   Dimensions[applied] === {4, 3} && MatrixQ[applied, NumberQ] &&
   Max[Abs[Flatten[applied - fitted["Matrix"]]]] < 10^-12 &&
   Max[Abs[prep["Mean"] - expectedMean]] < 10^-12 &&
   prep["Scale"][[{1, 2}]] === {1., 1.} &&
   Max[Abs[Flatten[applied[[All, {1, 2}]]]]] < 10^-12
 ], True, TestID -> "Signed-log-fitted-preprocessor-roundtrip-and-constant-columns"]

VerificationTest[
 Module[{rows, split, run, fakeNet, calls = 0, result},
  rows = Table[<|"ID" -> ToString[i], "Target" -> i,
      "Coefficients" -> {1, i, i^2}|>, {i, 4}];
  split = <|"Train" -> {1, 2}, "Validation" -> {3}, "Test" -> {4}|>;
  fakeNet[x_, ___] := (calls++; ConstantArray[{0.}, Length[x]]);
  run = <|"FinalNet" -> fakeNet, "Settings" -> <|"WorkingPrecision" -> "Real64"|>,
    "Preprocessor" -> <|"Mode" -> "SignedLogStandardized", "Dimension" -> 3|>,
    "TargetTransform" -> <|"Type" -> "Weight"|>, "TrainingTargetSD" -> 1.|>;
  result = UnifiedTraining`EvaluateRun[run, rows, split, "Final"];
  {FailureQ[result], calls}
 ], {True, 0}, TestID -> "Missing-input-scaling-fails-before-network-call"]

VerificationTest[
 Module[{rows, split, run, fakeNet, calls = 0, result},
  rows = Table[<|"ID" -> ToString[i], "Target" -> i,
      "Coefficients" -> {1, i}|>, {i, 4}];
  split = <|"Train" -> {1, 2}, "Validation" -> {3}, "Test" -> {4}|>;
  fakeNet[x_, ___] := (calls++; If[calls == 1, ConstantArray[{0.}, Length[x]], $Failed]);
  run = <|"FinalNet" -> fakeNet, "Settings" -> <|"WorkingPrecision" -> "Real64"|>,
    "Preprocessor" -> <|"Mode" -> "L2", "Dimension" -> 2|>,
    "TargetTransform" -> <|"Type" -> "Weight"|>, "TrainingTargetSD" -> 1.|>;
  result = UnifiedTraining`EvaluateRun[run, rows, split, "Final"];
  {FailureQ[result], calls}
 ], {True, 2}, TestID -> "Validation-prediction-failure-escapes-evaluation-loop"]

VerificationTest[
 Module[{rows, split, run, fakeNet, result},
  rows = Table[<|"ID" -> ToString[i], "Target" -> i,
      "Coefficients" -> {1, i}|>, {i, 4}];
  split = <|"Train" -> {1, 2}, "Validation" -> {3}, "Test" -> {4}|>;
  fakeNet[x_, ___] := {{0.}};
  run = <|"FinalNet" -> fakeNet, "Settings" -> <|"WorkingPrecision" -> "Real64"|>,
    "Preprocessor" -> <|"Mode" -> "L2", "Dimension" -> 2|>,
    "TargetTransform" -> <|"Type" -> "Weight"|>, "TrainingTargetSD" -> 1.|>;
  result = UnifiedTraining`EvaluateRun[run, rows, split, "Final"];
  FailureQ[result]
 ], True, TestID -> "Wrong-prediction-count-is-a-failure"]

VerificationTest[
 Module[{rows, split, run, fakeNet, result},
  rows = Table[<|"ID" -> ToString[i], "Target" -> i, "Power" -> i,
      "Coefficients" -> {1, i}|>, {i, 4}];
  split = <|"Train" -> {1, 2}, "Validation" -> {3}, "Test" -> {4}|>;
  fakeNet[x_, ___] := ConstantArray[{1000.}, Length[x]];
  run = <|"FinalNet" -> fakeNet, "Settings" -> <|"WorkingPrecision" -> "Real64"|>,
    "Preprocessor" -> <|"Mode" -> "L2", "Dimension" -> 2|>,
    "TargetTransform" -> <|"Type" -> "LogAbsPower", "WeightFactor" -> 1, "PowerSign" -> 1|>,
    "TrainingTargetSD" -> 1.|>;
  result = UnifiedTraining`EvaluateRun[run, rows, split, "Final"];
  FailureQ[result]
 ], True, TestID -> "Weight-decoding-overflow-is-not-partial-success"]

VerificationTest[
 Module[{rows, split, directory, trainCalls = 0, evalCalls = 0, first, second, result},
  rows = Table[<|"ID" -> ToString[i], "Target" -> i,
      "Coefficients" -> {1, i}|>, {i, 4}];
  split = <|"Train" -> {1, 2}, "Validation" -> {3}, "Test" -> {4}|>;
  directory = CreateDirectory[FileNameJoin[{$TemporaryDirectory, CreateUUID["validation-cache-test-"]}]];
  result = Block[{UnifiedTraining`Private`trainCore, UnifiedTraining`EvaluateRun},
    UnifiedTraining`Private`trainCore[r_List, s_Association, c_Association] :=
      (trainCalls++; <|"Status" -> "Trained", "Settings" -> c|>);
    UnifiedTraining`EvaluateRun[r_Association, data_List, s_Association, cp_String] :=
      (evalCalls++; <|"Checkpoint" -> cp, "Metrics" -> <|"Test" -> <|"RMSE" -> 0.|>|>,
        "Predictions" -> {}|>);
    first = UnifiedTraining`TrainRun[rows, split, <|"Model" -> 1|>, directory];
    second = UnifiedTraining`TrainRun[rows, split, <|"Model" -> 1|>, directory];
    {AssociationQ[first] && Lookup[first, "Status", ""] === "Complete" &&
       StringQ[Lookup[first, "Signature", Missing[]]] && KeyExistsQ[first, "SourceHash"] &&
       KeyExistsQ[first, "SchemaVersion"] && KeyExistsQ[first, "Metrics"] && KeyExistsQ[first, "Predictions"],
     first === second, trainCalls, evalCalls,
     Length[FileNames["*.wxf", directory]], Length[FileNames["*.trained.wxf", directory]]}
  ];
  DeleteDirectory[directory, DeleteContents -> True]; result
 ], {True, True, 1, 2, 1, 0}, TestID -> "Completed-run-is-saved-and-reloaded-without-training"]

VerificationTest[
 Module[{rows, split, directory, trainCalls = 0, evalCalls = 0, failNow = True,
   first, second, savedAfterFailure, result},
  rows = Table[<|"ID" -> ToString[i], "Target" -> i,
      "Coefficients" -> {1, i}|>, {i, 4}];
  split = <|"Train" -> {1, 2}, "Validation" -> {3}, "Test" -> {4}|>;
  directory = CreateDirectory[FileNameJoin[{$TemporaryDirectory, CreateUUID["validation-retry-test-"]}]];
  result = Block[{UnifiedTraining`Private`trainCore, UnifiedTraining`EvaluateRun},
    UnifiedTraining`Private`trainCore[r_List, s_Association, c_Association] :=
      (trainCalls++; <|"Status" -> "Trained", "Settings" -> c|>);
    UnifiedTraining`EvaluateRun[r_Association, data_List, s_Association, cp_String] :=
      (evalCalls++; If[failNow,
        Failure["InjectedEvaluationFailure", <|"MessageTemplate" -> "Deliberate regression-test failure."|>],
        <|"Checkpoint" -> cp, "Metrics" -> <|"Test" -> <|"RMSE" -> 0.|>|>, "Predictions" -> {}|>]);
    first = UnifiedTraining`TrainRun[rows, split, <|"Model" -> 1|>, directory];
    savedAfterFailure = {Length[FileNames["*.trained.wxf", directory]],
      Length[FileNames["*.failure.wxf", directory]], Length[FileNames["*.wxf", directory]]};
    failNow = False;
    second = UnifiedTraining`TrainRun[rows, split, <|"Model" -> 1|>, directory];
    {FailureQ[first], savedAfterFailure,
     AssociationQ[second] && Lookup[second, "Status", ""] === "Complete",
     trainCalls, evalCalls, Length[FileNames["*.wxf", directory]],
     Length[FileNames["*.trained.wxf", directory]], Length[FileNames["*.failure.wxf", directory]]}
  ];
  DeleteDirectory[directory, DeleteContents -> True]; result
 ], {True, {1, 1, 2}, True, 1, 3, 1, 0, 0},
 TestID -> "Evaluation-failure-preserves-trained-cache-and-retry-does-not-train"]
