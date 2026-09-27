BeginPackage["UnifiedTraining`"];
BuildModel::usage = "BuildModel[d,spec] constructs an uninitialized dense regression network.";
ParameterCount::usage = "ParameterCount[d,spec] counts dense weights and biases.";
TransformInputs::usage = "TransformInputs[matrix,mode] transforms coefficient rows with explicit zero handling.";
EncodeTargets::usage = "EncodeTargets[rows,trainingIndices,cfg] fits a target transform on training rows only.";
DecodeTargets::usage = "DecodeTargets[latent,transform] returns physical weights, without rounding or clipping.";
EvaluateRun::usage = "EvaluateRun[run,rows,split,checkpoint] evaluates physical-weight and training-space errors.";
TrainRun::usage = "TrainRun[rows,split,cfg,cacheDir] trains or resumes a complete fingerprint-matched run.";
Begin["`Private`"];

$SourcePath = $InputFileName;
$SchemaVersion = "unified-validation-2026-09-26-v3";
finiteRealQ[z_] := NumberQ[z] && FreeQ[z, Indeterminate | ComplexInfinity | DirectedInfinity[_]] && TrueQ[Im[z] == 0];
finiteVectorQ[z_] := VectorQ[z, finiteRealQ];
failure[tag_, message_, extra_: <||>] := Failure[tag, Join[<|"MessageTemplate" -> message|>, extra]];
defaults = <|"Rounds" -> 10000, "BatchSize" -> 64, "LearningRate" -> 0.001,
 "LearningRateSchedule" -> "Constant", "Initializer" -> "Kaiming", "InputTransform" -> "L2",
 "TargetTransform" -> "StandardizedWeight", "PowerSign" -> 1, "WeightFactor" -> 1,
 "Seed" -> 101, "InitializationSeed" -> 10101, "TrainingSeed" -> 20101,
 "TargetDevice" -> "CPU", "WorkingPrecision" -> "Real64", "Optimizer" -> "ADAM"|>;

modelDefinition[spec_] := Which[
 IntegerQ[spec] && spec > 0, {{spec}, {Ramp}},
 ListQ[spec] && AllTrue[spec, IntegerQ[#] && # > 0 &], {spec, ConstantArray[Ramp, Length[spec]]},
 AssociationQ[spec] && IntegerQ[Lookup[spec,"Depth",0]] && Lookup[spec,"Depth",0] > 0 &&
  IntegerQ[Lookup[spec,"Width",0]] && Lookup[spec,"Width",0] > 0,
  {ConstantArray[spec["Width"], spec["Depth"]], ConstantArray[Ramp, spec["Depth"]]},
 StringQ[spec] && StringMatchQ[spec,RegularExpression["Depth[1-9][0-9]*Width[1-9][0-9]*"]],
  With[{numbers=ToExpression /@ StringCases[spec,DigitCharacter..]},
   {ConstantArray[numbers[[2]],numbers[[1]]],ConstantArray[Ramp,numbers[[1]]]}],
 True, Switch[spec,
  "Linear", {{}, {}},
  "Net1", {{256,128,64,32,8,4}, {Ramp,LogisticSigmoid,Ramp,Ramp,Ramp,Ramp}},
  "Net1NoSigmoid", {{256,128,64,32,8,4}, ConstantArray[Ramp,6]},
  "Net2", {{256,256,128,128,64,32,8,4},
   {Ramp, Function[x,x (1+Erf[x/Sqrt[2]])/2], Ramp, Function[x,x (1+Erf[x/Sqrt[2]])/2],
    Ramp, Function[x,x (1+Erf[x/Sqrt[2]])/2], Ramp,Ramp}},
  "Net3", {{256,256,128,128,64,32,8}, ConstantArray[Ramp,7]},
  "EtaPaperLarge", {{512,256,256,128,128,64,32}, ConstantArray[Ramp,7]},
  "E2Original", {{256,128,64},{Ramp,LogisticSigmoid,Ramp}},
  _, failure["UnknownModel", "Unrecognized model specification.", <|"Specification" -> spec|>]]];

BuildModel[d_Integer?Positive, spec_] := Module[{definition=modelDefinition[spec], layers},
 If[FailureQ[definition], Return[definition]];
 layers=Flatten[MapThread[{LinearLayer[#1],ElementwiseLayer[#2]}&,definition],1];
 NetChain[Append[layers,LinearLayer[1]],"Input"->d]
];
ParameterCount[d_Integer?Positive,spec_] := Module[{definition=modelDefinition[spec],sizes},
 If[FailureQ[definition], Return[definition]];
 sizes=Join[{d},First[definition],{1}]; Total[(Most[sizes]+1) Rest[sizes]]
];

(* Normalize before conversion to machine precision: exact coefficients can be huge.
   Zeros retain their coefficient positions. LogAbsL2 maps exactly zero to zero;
   this convention is deliberately recorded and does not replace log by log1p. *)
normalizeRow[row_List] := Module[{a=N[row,80], norm},
 If[!finiteVectorQ[a], Return[failure["NonfiniteCoefficients","A coefficient is nonfinite."]]];
 norm=Sqrt[Total[a^2]];
 If[TrueQ[norm==0], Return[ConstantArray[0.,Length[row]]]];
 Quiet[N[a/norm,MachinePrecision],General::munfl]
];
TransformInputs[m_List,mode_String] := Module[{z},
 z=Switch[mode,
  "L2", normalizeRow /@ m,
  "LogAbsL2", normalizeRow /@ Map[If[TrueQ[#==0],0,Log[Abs[N[#,80]]]]&,m,{2}],
  "SignedLogStandardized", If[AnyTrue[m,TrueQ[First[#]==0]&],
    Return[failure["LeadingCoefficient","SignedLogStandardized requires a nonzero first coefficient."]]];
   N[Map[Sign[#] Log[1+Abs[N[#,80]]]& ,(#/First[#])& /@ m,{2}],MachinePrecision],
  _, Return[failure["InputTransform","Unknown input transform.",<|"Mode"->mode|>]]];
 If[!MatrixQ[z,finiteRealQ], Return[failure["NonfiniteInputs","The transformed inputs are not a finite real matrix."]]];
 z
];
selectInputs[rows_List,positions_] := Module[{m=Lookup[rows,"Coefficients"]},
 If[positions===All,m,m[[All,positions]]]
];
fitInputs[rows_List,tr_List,cfg_Association] := Module[{z,mean,scale,prep,positions},
 positions=Lookup[cfg,"FeaturePositions",All];
 z=TransformInputs[selectInputs[rows,positions],cfg["InputTransform"]];
 If[FailureQ[z],Return[z]];
 prep=<|"Mode"->cfg["InputTransform"],"ZeroLogConvention"->"Exact zero maps to zero; coefficient positions are retained",
   "FeaturePositions"->positions,"FeatureOrder"->"Select coefficients, then transform, then normalize",
   "Positions"->If[positions===All,Lookup[First[rows],"Positions",Range[0,Length[First[z]]-1]],
     Lookup[First[rows],"Positions",Range[0,Length[First[Lookup[rows,"Coefficients"]]]-1]][[positions]]],
   "Dimension"->Length[First[z]]|>;
 If[cfg["InputTransform"]==="SignedLogStandardized",
  mean=Mean[z[[tr]]];scale=StandardDeviation[z[[tr]]];scale=Replace[scale,x_/;TrueQ[x==0]:>1.,{1}];
  AssociateTo[prep,{"Mean"->mean,"Scale"->scale}];z=((#-mean)/scale)&/@z];
 If[!MatrixQ[z,finiteRealQ],Return[failure["NonfiniteInputs","Standardized inputs are not a finite real matrix."]]];
 <|"Matrix"->z,"Preprocessor"->prep|>
];
applyInputs[rows_List,prep_Association] := Module[{z},
 z=TransformInputs[selectInputs[rows,Lookup[prep,"FeaturePositions",All]],prep["Mode"]];If[FailureQ[z],Return[z]];
 If[prep["Mode"]==="SignedLogStandardized",
  If[!AllTrue[{"Mean","Scale"},KeyExistsQ[prep,#]&] ||
    !finiteVectorQ[prep["Mean"]] || !finiteVectorQ[prep["Scale"]] ||
    Length[prep["Mean"]]!=Length[First[z]] || Length[prep["Scale"]]!=Length[First[z]] ||
    !AllTrue[prep["Scale"],TrueQ[#>0]&],
   Return[failure["InvalidPreprocessor","Saved signed-log preprocessing requires finite mean and positive scale vectors matching the input dimension."]]];
  z=((#-prep["Mean"])/prep["Scale"])&/@z];
 If[!MatrixQ[z,finiteRealQ],Return[failure["NonfiniteInputs","Prediction inputs are not a finite real matrix."]]];z
];

EncodeTargets[rows_List,tr_List,input_Association] := Module[
 {cfg=Join[defaults,input],y,values,mu,sd,powers,factor,sgn,transform},
 y=N[Lookup[rows,"Target"],MachinePrecision];
 If[!finiteVectorQ[y],Return[failure["Targets","Physical targets must be finite real numbers."]]];
 Switch[cfg["TargetTransform"],
  "StandardizedWeight",mu=Mean[y[[tr]]];sd=StandardDeviation[y[[tr]]];If[!TrueQ[sd>0],sd=1.];
   values=(y-mu)/sd;transform=<|"Type"->"StandardizedWeight","Mean"->mu,"Scale"->sd|>,
  "Weight",values=y;transform=<|"Type"->"Weight"|>,
  "LogAbsPower",powers=Lookup[rows,"Power",Missing["Power"]];factor=cfg["WeightFactor"];sgn=cfg["PowerSign"];
   If[!VectorQ[powers,finiteRealQ]||AnyTrue[powers,TrueQ[#==0]&]||!finiteRealQ[factor]||!TrueQ[factor>0]||!MemberQ[{-1,1},sgn],
    Return[failure["PowerTargets","LogAbsPower requires nonzero real powers, positive WeightFactor, and PowerSign equal to +1 or -1."]]];
   If[!AllTrue[powers,TrueQ[Sign[#]==sgn]&]||Max[Abs[N[factor powers,MachinePrecision]-y]]>10^-9 Max[1.,Max[Abs[y]]],
    Return[failure["WeightRelation","Targets must equal WeightFactor times the signed power; a logarithmic power target cannot represent an additive weight offset."]]];
   values=N[Log[Abs[powers]],MachinePrecision];
   transform=<|"Type"->"LogAbsPower","WeightFactor"->factor,"PowerSign"->sgn|>,
  _,Return[failure["TargetTransform","Unknown target transform."]]];
 If[!finiteVectorQ[values],Return[failure["EncodedTargets","Encoded targets are not finite real numbers."]]];
 <|"Values"->values,"Transform"->transform,"TrainingTargetSD"->Replace[StandardDeviation[y[[tr]]],0|0.->1.]|>
];
DecodeTargets[z_List,t_Association] := Module[{p},
 p=Quiet[Switch[t["Type"],
  "StandardizedWeight",t["Mean"]+t["Scale"] z,
  "Weight",z,
  "LogAbsPower",t["PowerSign"] t["WeightFactor"] Exp[z],
  _,Return[failure["TargetTransform","Cannot decode an unknown target transform."]]],{General::ovfl,General::munfl}];
 If[!finiteVectorQ[p],Return[failure["NonfiniteDecodedPrediction","Decoded physical weights overflowed or were nonfinite. No predictions were clipped.",
  <|"NonfinitePredictionCount"->Count[p,x_/;!finiteRealQ[x]],"TargetTransform"->t|>]]];
 (* Wolfram can promote Exp[1000.] to a finite arbitrary-precision number.
    The CSV/Python report path requires outputs within the Real64 range. *)
 If[AnyTrue[p,TrueQ[Abs[#]>$MaxMachineNumber]&],
  Return[failure["DecodedPredictionOutsideReal64Range","A decoded physical weight exceeds the Real64 output range. No predictions were clipped.",
   <|"TargetTransform"->t|>]]];
 If[t["Type"]==="LogAbsPower"&&AnyTrue[p,TrueQ[#==0]&],
  Return[failure["UnderflowDecodedPrediction","A logarithmic prediction underflowed to zero. No predictions were clipped.",<|"TargetTransform"->t|>]]];p
];
encodeWithTransform[rows_List,t_Association] := Switch[t["Type"],
 "StandardizedWeight",(N[Lookup[rows,"Target"]]-t["Mean"])/t["Scale"],
 "Weight",N[Lookup[rows,"Target"]],
 "LogAbsPower",N[Log[Abs[Lookup[rows,"Power"]]]]];

initializer[name_] := Switch[name,"Kaiming"|"Xavier",{name,"Distribution"->"Normal"},"Orthogonal",name,
 _,failure["Initializer","Unknown initialization method."]];
optimizer[cfg_Association] := Module[{method,overrides},
 method=Switch[cfg["Optimizer"],
  "ADAM",{"ADAM","Beta1"->0.9,"Beta2"->0.999,"Epsilon"->10^-5,"L2Regularization"->None},
  "RMSProp",{"RMSProp","Beta"->0.95,"Momentum"->0.9,"Epsilon"->10^-6,"L2Regularization"->None},
  "SGD",{"SGD","Momentum"->0.93,"L2Regularization"->None},
  _,Return[failure["Optimizer","Optimizer must be ADAM, RMSProp, or SGD."]]];
 overrides=Lookup[cfg,"MethodOptions",<||>];
 If[!AssociationQ[overrides],Return[failure["MethodOptions","MethodOptions must be an association."]]];
 method=Prepend[Normal[Join[Association[Rest[method]],overrides]],First[method]];
 Switch[cfg["LearningRateSchedule"],
  "Constant",Append[method,"LearningRateSchedule"->Function[{batch,total},1]],
  "Automatic"|Automatic,method,
  _,failure["Schedule","LearningRateSchedule must be Constant or Automatic."]]
];
initializedArrays[net_,spec_] := Table[<|"Layer"->i,
 "Weights"->Normal[NetExtract[net,{i,"Weights"}]],"Biases"->Normal[NetExtract[net,{i,"Biases"}]]|>,
 {i,1,2 Length[First[modelDefinition[spec]]]+1,2}];
hashString[expr_] := IntegerString[Hash[expr,"SHA256"],16,64];
atomicWXF[path_,expr_] := Module[{tmp=path<>".partial",saved},
 saved=Check[Export[tmp,expr,"WXF"],$Failed];If[saved===$Failed,Return[$Failed]];
 Check[RenameFile[tmp,path,OverwriteTarget->True],$Failed]
];
validateInput[rows_,split_,cfg_] := Module[{indices,lens,positions},
 If[!ListQ[rows]||rows==={}||!AllTrue[rows,AssociationQ[#]&&KeyExistsQ[#,"ID"]&&KeyExistsQ[#,"Target"]&&KeyExistsQ[#,"Coefficients"]&],
  Return[failure["Rows","Rows require ID, Target and Coefficients."]]];
 lens=Length/@Lookup[rows,"Coefficients"];
 If[Min[lens]<1||Length[DeleteDuplicates[lens]]!=1,Return[failure["Dimension","All coefficient rows must have the same positive length."]]];
 positions=Lookup[cfg,"FeaturePositions",All];
 If[positions=!=All&&(!ListQ[positions]||positions==={}||!DuplicateFreeQ[positions]||
  !AllTrue[positions,IntegerQ[#]&&1<=#<=First[lens]&]),
  Return[failure["FeaturePositions","FeaturePositions must be All or distinct valid 1-based coefficient positions."]]];
 If[!AssociationQ[split]||!And@@(KeyExistsQ[split,#]&&ListQ[split[#]]&/@{"Train","Validation","Test"}),
  Return[failure["Split","Train, Validation and Test index lists are required."]]];
 indices=Join@@Lookup[split,{"Train","Validation","Test"}];
 If[Length[split["Train"]]<2||split["Validation"]==={}||split["Test"]==={}||!DuplicateFreeQ[indices]||
  !AllTrue[indices,IntegerQ[#]&&1<=#<=Length[rows]&],
  Return[failure["Split","Require disjoint valid indices, at least two training rows and nonempty validation/test sets."]]];
 If[!IntegerQ[cfg["Rounds"]]||cfg["Rounds"]<1||!IntegerQ[cfg["BatchSize"]]||cfg["BatchSize"]<1||
  !IntegerQ[cfg["InitializationSeed"]]||!IntegerQ[cfg["TrainingSeed"]]||!KeyExistsQ[cfg,"Model"]||
  !(cfg["LearningRate"]===Automatic||finiteRealQ[cfg["LearningRate"]]&&TrueQ[cfg["LearningRate"]>0]),
  Return[failure["Settings","Invalid round budget, batch size, seeds, learning rate, or missing Model."]]];
 True
];

trainCore[rows_List,split_Association,cfg_Association] := Module[
 {tr=split["Train"],va=split["Validation"],input,target,x,latent,net,initial,arrays,method,init,
  seconds,answer,final,best,res,completed},
 Print["Training ",Lookup[cfg,"Dataset",""]," / ",cfg["Model"]," / ",cfg["Optimizer"]," / seed ",cfg["Seed"]," / rounds ",cfg["Rounds"]];
 input=fitInputs[rows,tr,cfg];If[FailureQ[input],Return[input]];x=input["Matrix"];
 target=EncodeTargets[rows,tr,cfg];If[FailureQ[target],Return[target]];latent=target["Values"];
 net=BuildModel[Length[First[x]],cfg["Model"]];If[FailureQ[net],Return[net]];
 init=initializer[cfg["Initializer"]];If[FailureQ[init],Return[init]];
 initial=Check[NetInitialize[net,All,Method->init,RandomSeeding->cfg["InitializationSeed"]],$Failed];
 If[initial===$Failed,Return[failure["Initialization","NetInitialize failed.",<|"Settings"->cfg|>]]];
 arrays=Check[initializedArrays[initial,cfg["Model"]],$Failed];
 If[arrays===$Failed,Return[failure["InitialArrays","Could not record initialized arrays."]]];
 method=optimizer[cfg];If[FailureQ[method],Return[method]];
 {seconds,answer}=AbsoluteTiming[Check[NetTrain[initial,Thread[x[[tr]]->List/@latent[[tr]]],
  {"FinalNet","TrainedNet","ResultsObject","BatchPermutation"},
  ValidationSet->{Thread[x[[va]]->List/@latent[[va]]],"Interval"->1},
  LossFunction->MeanSquaredLossLayer[],Method->method,LearningRate->cfg["LearningRate"],
  BatchSize->cfg["BatchSize"],MaxTrainingRounds->cfg["Rounds"],TrainingStoppingCriterion->None,
  RandomSeeding->cfg["TrainingSeed"],TargetDevice->cfg["TargetDevice"],WorkingPrecision->cfg["WorkingPrecision"],
  TrainingProgressReporting->None],$Failed]];
 If[answer===$Failed||!ListQ[answer]||Length[answer]!=4,Return[failure["NetTrainFailed","NetTrain did not return a complete run.",<|"Settings"->cfg|>]]];
 {final,best,res}=Take[answer,3];completed=Check[res["TotalRounds"],$Failed];
 If[!NumberQ[completed]||!TrueQ[completed>=cfg["Rounds"]],
  Return[failure["IncompleteBudget","Training ended before the requested budget.",<|"RequestedRounds"->cfg["Rounds"],"CompletedRounds"->completed|>]]];
 <|"Status"->"Trained","Settings"->cfg,"Preprocessor"->input["Preprocessor"],"TargetTransform"->target["Transform"],
  "TrainingTargetSD"->target["TrainingTargetSD"],"FinalNet"->final,"BestNet"->best,
  "InitialArraysHash"->hashString[arrays],"BatchPermutationHash"->hashString[answer[[4]]],
  "Parameters"->ParameterCount[Length[First[x]],cfg["Model"]],"InputDimension"->Length[First[x]],
  "TrainCount"->Length[tr],"ValidationCount"->Length[va],"TestCount"->Length[split["Test"]],"Seconds"->seconds,
  "TotalRounds"->completed,"TotalBatches"->res["TotalBatches"],"StopReason"->res["ReasonTrainingStopped"],
  "BestValidationRound"->res["BestValidationRound"],"RoundLossList"->res["RoundLossList"],
  "RoundPositions"->res["RoundPositions"],"ValidationLossList"->res["ValidationLossList"],
  "ValidationPositions"->res["ValidationPositions"],"Version"->$Version,"SystemID"->$SystemID|>
];

physicalMetrics[y_List,p_List,latent_List,latentTarget_List,sd_] := Module[{err=p-y,nonzero,nzero,result,scale,rmse,mae},
 nonzero=Flatten[Position[y,x_/;!TrueQ[x==0],{1},Heads->False]];nzero=Length[y]-Length[nonzero];
 scale=Max[Abs[err]];rmse=If[TrueQ[scale==0],0.,scale Sqrt[Mean[(err/scale)^2]]];
 mae=If[TrueQ[scale==0],0.,scale Mean[Abs[err/scale]]];
 result=<|"Loss"->Mean[(latent-latentTarget)^2],"RMSE"->rmse,"MAE"->mae,
  "NRMSE"->rmse/sd,
  "MAPE"->If[nzero==0,100 Mean[Abs[err/y]],Missing["UndefinedAtZeroTarget"]],
  "MAPENonzero"->If[nonzero==={},Missing["NoNonzeroTargets"],100 Mean[Abs[err[[nonzero]]/y[[nonzero]]]]],
  "MAPEN"->Length[nonzero],"ZeroTargetCount"->nzero,"NonfinitePredictionCount"->0,"Count"->Length[y]|>;
 If[!AllTrue[DeleteCases[Values[result],_Missing],finiteRealQ[#]&&TrueQ[Abs[#]<=$MaxMachineNumber]&],
  Return[failure["NonfiniteMetric","An error metric is nonfinite or exceeds the Real64 output range. No errors were clipped.",<|"Metrics"->result|>]]];result
];
EvaluateRun[run_Association,rows_List,split_Association,checkpoint_String] := Module[
 {net,metrics=<||>,predictions={},idx,x,y,latent,p,encoded,part,precision,loopResult},
 If[!MemberQ[{"Final","Best"},checkpoint],Return[failure["Checkpoint","Checkpoint must be Final or Best."]]];
 net=run[checkpoint<>"Net"];precision=run["Settings"]["WorkingPrecision"];
 loopResult=Do[idx=split[part];x=applyInputs[rows[[idx]],run["Preprocessor"]];If[FailureQ[x],Return[x]];
  If[Dimensions[x]=!={Length[idx],run["Preprocessor"]["Dimension"]},
   Return[failure["InputDimension","Prediction inputs do not match the saved input dimension.",<|"Split"->part,"Checkpoint"->checkpoint|>]]];
  y=N[Lookup[rows[[idx]],"Target"]];encoded=encodeWithTransform[rows[[idx]],run["TargetTransform"]];
  latent=Check[net[x,WorkingPrecision->precision],$Failed];
  If[latent===$Failed||!ListQ[latent],
   Return[failure["NonfiniteLatentPrediction","The network did not return a prediction list.",<|"Split"->part,"Checkpoint"->checkpoint|>]]];
  latent=Flatten[latent];
  If[!finiteVectorQ[latent]||Length[latent]!=Length[y],
   Return[failure["NonfiniteLatentPrediction","The network returned nonfinite or incorrectly sized predictions.",<|"Split"->part,"Checkpoint"->checkpoint|>]]];
  p=DecodeTargets[latent,run["TargetTransform"]];If[FailureQ[p],Return[failure["EvaluationFailed","Physical weight decoding failed; trained networks remain cached.",
    <|"Split"->part,"Checkpoint"->checkpoint,"Cause"->p|>]]];
  AssociateTo[metrics,part->physicalMetrics[y,p,latent,encoded,run["TrainingTargetSD"]]];
  If[FailureQ[metrics[part]],Return[metrics[part]]];
  predictions=Join[predictions,MapThread[<|"ID"->#1,"Split"->part,"Target"->#2,"Prediction"->#3,
    "LatentTarget"->#4,"LatentPrediction"->#5,"AbsoluteError"->Abs[#3-#2],
    "AbsoluteRelativeErrorPercent"->If[TrueQ[#2==0],Missing["UndefinedAtZeroTarget"],100 Abs[(#3-#2)/#2]]|>&,
    {Lookup[rows[[idx]],"ID"],y,p,encoded,latent}]],{part,{"Train","Validation","Test"}}];
 (* Return inside Do exits the loop; explicitly propagate its failure here. *)
 If[FailureQ[loopResult],Return[loopResult]];
 <|"Checkpoint"->checkpoint,"Metrics"->metrics,"Predictions"->predictions|>
];

TrainRun[rows_List,split_Association,input_Association,dir_String] := Module[
 {cfg=Join[defaults,input],valid,sourceHash,signature,path,trainedPath,failurePath,run,old,evals,cp,loopResult},
 valid=validateInput[rows,split,cfg];If[FailureQ[valid],Return[valid]];
 sourceHash=If[FileExistsQ[$SourcePath],IntegerString[FileHash[$SourcePath,"SHA256"],16,64],$SchemaVersion];
 signature=hashString[{$SchemaVersion,sourceHash,cfg,split,rows,$Version,$SystemID}];
 If[!DirectoryQ[dir],CreateDirectory[dir,CreateIntermediateDirectories->True]];
 path=FileNameJoin[{dir,signature<>".wxf"}];trainedPath=FileNameJoin[{dir,signature<>".trained.wxf"}];
 failurePath=FileNameJoin[{dir,signature<>".failure.wxf"}];
 If[FileExistsQ[path],old=Quiet[Check[Import[path,"WXF"],$Failed]];
  If[AssociationQ[old]&&Lookup[old,"Signature",""]===signature&&Lookup[old,"Status",""]==="Complete",Return[old]]];
 run=If[FileExistsQ[trainedPath],Quiet[Check[Import[trainedPath,"WXF"],$Failed]],$Failed];
 If[!AssociationQ[run]||Lookup[run,"Signature",""] =!= signature||Lookup[run,"Status",""] =!= "Trained",
  run=trainCore[rows,split,cfg];
  If[FailureQ[run],atomicWXF[failurePath,<|"Signature"->signature,"Settings"->cfg,"Failure"->run|>];Return[run]];
  AssociateTo[run,{"Signature"->signature,"SourceHash"->sourceHash,"SchemaVersion"->$SchemaVersion}];
  If[atomicWXF[trainedPath,run]===$Failed,Return[failure["SaveFailed","Cannot save the completed training state.",<|"Path"->trainedPath|>]]]];
 evals=<||>;
 loopResult=Do[AssociateTo[evals,cp->EvaluateRun[run,rows,split,cp]];
  If[FailureQ[evals[cp]],atomicWXF[failurePath,<|"Signature"->signature,"Settings"->cfg,"Failure"->evals[cp],"TrainedCache"->trainedPath|>];Return[evals[cp]]],{cp,{"Final","Best"}}];
 If[FailureQ[loopResult],Return[loopResult]];
 AssociateTo[run,{"Status"->"Complete","Metrics"->AssociationMap[evals[#]["Metrics"]&,{"Final","Best"}],
  "Predictions"->AssociationMap[evals[#]["Predictions"]&,{"Final","Best"}]}];
 If[atomicWXF[path,run]===$Failed,Return[failure["SaveFailed","Cannot save the evaluated run.",<|"Path"->path|>]]];
 If[FileExistsQ[trainedPath],DeleteFile[trainedPath]];
 If[FileExistsQ[failurePath],DeleteFile[failurePath]];
 run
];

End[];
EndPackage[];
