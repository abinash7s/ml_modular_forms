(* The test driver loads src/Training.wl before this file. No neural training is required. *)
VerificationTest[UnifiedTraining`ParameterCount[30,"Net1"],51473,TestID->"Net1-count"]
VerificationTest[UnifiedTraining`ParameterCount[30,"Net3"],133745,TestID->"Net3-count"]
VerificationTest[UnifiedTraining`ParameterCount[30,"Depth3Width128"],37121,TestID->"Deep-count"]
VerificationTest[UnifiedTraining`ParameterCount[30,"Depth6Width16"],1873,TestID->"Compact-count"]
VerificationTest[UnifiedTraining`ParameterCount[15,"Net3"],129905,TestID->"Slice-count"]

VerificationTest[
 UnifiedTraining`DecodeTargets[{Log[2],Log[5]},<|"Type"->"LogAbsPower","PowerSign"->-1,"WeightFactor"->6|>],
 {-12,-30},TestID->"Negative-CHL-physical-weight-decode"]

VerificationTest[
 With[{p=UnifiedTraining`DecodeTargets[{Log[11]},<|"Type"->"LogAbsPower","PowerSign"->1,"WeightFactor"->6|>]},
  100 First[Abs[(p-{60})/{60}]]],
 10,TestID->"Weight-MAPE-is-not-log-target-MAPE"]

VerificationTest[
 Max[Abs[First[UnifiedTraining`TransformInputs[{{1,0,-10,100}},"LogAbsL2"]]-N[{0,0,1/Sqrt[5],2/Sqrt[5]}]]]<10^-12,
 True,TestID->"Explicit-zero-position-preserving-log"]

VerificationTest[
 With[{r=UnifiedTraining`EncodeTargets[
  {<|"Target"->2|>,<|"Target"->4|>,<|"Target"->1000|>},{1,2},<|"TargetTransform"->"StandardizedWeight"|>]},
  Abs[r["Transform"]["Mean"]-3]<10^-12&&Abs[r["Transform"]["Scale"]-Sqrt[2]]<10^-12],
 True,TestID->"Target-scaling-fits-training-only"]

VerificationTest[
 FailureQ[UnifiedTraining`EncodeTargets[
  {<|"Target"->8,"Power"->1|>,<|"Target"->14,"Power"->2|>},{1,2},
  <|"TargetTransform"->"LogAbsPower","WeightFactor"->6,"PowerSign"->1|>]],
 True,TestID->"Log-power-does-not-hide-additive-weight-shift"]

VerificationTest[
 With[{m=UnifiedTraining`Private`physicalMetrics[{0.,2.},{1.,3.},{0.,0.},{0.,0.},1.]},
  MissingQ[m["MAPE"]]&&m["ZeroTargetCount"]==1&&Abs[m["MAPENonzero"]-50]<10^-12],
 True,TestID->"Zero-target-MAPE-explicit"]

VerificationTest[
 With[{m=UnifiedTraining`Private`physicalMetrics[{1.,1.},{1.*^200,1.*^200},{0.,0.},{0.,0.},1.]},
  AssociationQ[m]&&NumberQ[m["RMSE"]]&&Abs[m["RMSE"]/10.^200-1.]<10^-12],
 True,TestID->"RMSE-avoids-unnecessary-square-overflow"]

VerificationTest[
 Module[{transform=<|"Type"->"LogAbsPower","PowerSign"->1,"WeightFactor"->1|>,inRange},
  inRange=UnifiedTraining`DecodeTargets[{N[Log[2],30]},transform];
  {FailureQ[UnifiedTraining`DecodeTargets[{1000.},transform]],
   FailureQ[UnifiedTraining`DecodeTargets[{N[1000,30]},transform]],
   FailureQ[UnifiedTraining`DecodeTargets[{700.},Join[transform,<|"WeightFactor"->10^6|>]]],
   VectorQ[inRange,NumberQ]&&Abs[First[inRange]-2]<10^-12}],
 {True,True,True,True},TestID->"Decoded-weights-have-explicit-Real64-output-range"]

VerificationTest[
 FailureQ[UnifiedTraining`Private`physicalMetrics[
  {0.001},{N[10^307,30]},{0.},{0.},1.]],
 True,TestID->"Promoted-metrics-outside-Real64-range-are-rejected"]
