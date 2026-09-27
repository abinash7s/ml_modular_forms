BeginPackage["UnifiedStudy`", {"ValidationData`", "UnifiedTraining`"}];
MakeSplit::usage = "MakeSplit[rows,seed] keeps repeated exact powers in one seeded train/validation/test partition.";
RunStudy::usage = "RunStudy[root,options] runs the selected study and exports readable settings, predictions, losses and weight metrics.";
Begin["`Private`"];
stop[tag_,msg_] := Throw[Failure[tag,<|"MessageTemplate"->msg|>],"UnifiedStudyFailure"];
must[x_] := If[FailureQ[x] || x===$Failed,Throw[x,"UnifiedStudyFailure"],x];
ensure[p_] := If[!DirectoryQ[p],CreateDirectory[p,CreateIntermediateDirectories->True]];
textValue[x_String] := x;
textValue[x_] := ToString[x,InputForm];
failureSummary[x_] := Which[
 FailureQ[x],ToString[x[[1]],OutputForm]<> ": " <>
  ToString[Lookup[x[[2]],"MessageTemplate","Run failed; inspect the saved failure record."],OutputForm],
 x===$Failed,"Evaluation returned $Failed.",
 AssociationQ[x],"Unexpected run status: "<>ToString[Lookup[x,"Status","missing"],OutputForm],
 True,"Unexpected run result: "<>ToString[Short[x,2],OutputForm]
];
csvValue[x_?NumberQ] := x;
csvValue[x_String] := x;
csvValue[x_] := textValue[x];
writeTable[path_,rows_List] := Module[{keys,table,tmp},
 ensure[DirectoryName[path]];
 keys=DeleteDuplicates[Flatten[Keys /@ rows]];
 table=Prepend[(csvValue /@ Lookup[#,keys,""])& /@ rows,keys];
 tmp=path<>".partial"; must[Export[tmp,table,"CSV"]];
 must[RenameFile[tmp,path,OverwriteTarget->True]]; path
];
save[path_,x_] := Module[{tmp=path<>".partial"},ensure[DirectoryName[path]];
 must[Export[tmp,x,"WXF"]];must[RenameFile[tmp,path,OverwriteTarget->True]];path];
sourceHash[root_] := Module[{files},
 files=Sort[Join[FileNames["*.wl",FileNameJoin[{root,"src"}]],
   FileNames["*.json",FileNameJoin[{root,"config"}]],FileNames["*.wl",FileNameJoin[{root,"resources"}]]]];
 IntegerString[Hash[({FileNameTake[#],FileHash[#,"SHA256"]}& /@ files),"SHA256"],16,64]
];
MakeSplit[rows_List,seed_Integer] := Module[{groups,n,nt,nv,order},
 groups=GatherBy[Range[Length[rows]],rows[[#]]["Group"]&];n=Length[groups];
 If[n<20,Return[Failure["SplitSize",<|"MessageTemplate"->"At least 20 distinct power groups are required."|>]]];
 nt=Floor[3n/4];nv=Round[3n/20];
 order=BlockRandom[SeedRandom[seed];RandomSample[Range[n]]];
 <|"Train"->Sort[Flatten[groups[[Take[order,nt]]]]],
   "Validation"->Sort[Flatten[groups[[Take[order,{nt+1,nt+nv}]]]]],
   "Test"->Sort[Flatten[groups[[Drop[order,nt+nv]]]]]|>
];
settings[defaults_,experiment_,seed_,hash_,rounds_] := Join[
 KeyTake[defaults,{"BatchSize","LearningRate","Initializer","TargetDevice","WorkingPrecision","ZeroCoefficientLogPolicy"}],
 experiment,<|"Seed"->seed,"SplitSeed"->defaults["SplitSeed"],
 "InitializationSeed"->10000+seed,"TrainingSeed"->20000+seed,"Rounds"->rounds,"SourceHash"->hash|>];
selectExperiments[all_,options_] := Module[{suite=options["Suite"],selected,only},
 selected=Select[all,Switch[suite,"all",MemberQ[If[TrueQ[options["WithE2"]],{"width_depth","chl","e2"},{"width_depth","chl"}],#["Study"]],
   "width-depth",#["Study"]==="width_depth","chl",#["Study"]==="chl","e2",#["Study"]==="e2",_,False]&];
 only=Lookup[options,"Only",""];
 If[StringQ[only]&&only=!="",selected=Select[selected,MemberQ[StringSplit[only,","],#["ExperimentID"]]&]];
 If[selected==={},stop["EmptySelection","No experiments match the requested suite/IDs."]];selected
];
resolveSpec[spec_,root_,smoke_] := Module[{s=spec,powers},
 powers=Which[KeyExistsQ[s,"Powers"],s["Powers"],
  KeyExistsQ[s,"PowerRange"],Range@@s["PowerRange"],
  KeyExistsQ[s,"PowerHalfIntegerRange"],(Range@@s["PowerHalfIntegerRange"])/2,
  KeyExistsQ[s,"PowersFile"],Get[FileNameJoin[{root,"resources",s["PowersFile"]}]],True,$Failed];
 If[!ListQ[powers],stop["Powers","Could not resolve an exact power list."]];
 If[TrueQ[smoke],powers=powers[[DeleteDuplicates[Round[Subdivide[1,Length[powers],Min[63,Length[powers]-1]]]]]]];
 Join[KeyDrop[s,{"PowerRange","PowerHalfIntegerRange","PowersFile"}],<|"Powers"->powers,"CoefficientCount"->30|>]
];
splitRecords[rows_,split_] := Flatten[Table[Table[
 <|"Index"->i,"ID"->rows[[i]]["ID"],"Group"->rows[[i]]["Group"],"PowerExact"->textValue[rows[[i]]["Power"]],
 "WeightExact"->textValue[rows[[i]]["Target"]],"Split"->part|>,{i,split[part]}],{part,{"Train","Validation","Test"}}],1];
flatMetrics[run_,checkpoint_] := Module[{cfg=run["Settings"],m=run["Metrics"][checkpoint],widths,meta},
 widths=Lookup[cfg,"LayerWidths",{}];
 meta=Join[KeyTake[cfg,{"ExperimentID","Study","PaperTable","Dataset","Family","N","Model","Optimizer","Seed","Rounds",
   "InputTransform","TargetTransform","WeightFactor","PowerSign","PowerFamily","LearningRateSchedule","LearningRate","MethodOptions",
   "FeaturePositions","InitializationSeed","TrainingSeed","SplitSeed","BatchSize","Initializer","TargetDevice","WorkingPrecision","Role","Smoke"}],
  KeyTake[run,{"Signature","Parameters","TrainCount","ValidationCount","TestCount","Seconds","BestValidationRound","TotalRounds",
   "InitialArraysHash","BatchPermutationHash","Version","SystemID"}],
  <|"Checkpoint"->checkpoint,"HiddenLayers"->Length[widths],"LayerWidths"->widths,
   "Width"->If[Length[DeleteDuplicates[widths]]==1,First[widths],"varies"],
   "ParameterSampleRatio"->N[run["Parameters"]/run["TrainCount"]],"Status"->"Complete"|>];
 Join[meta,Association@@Flatten[KeyValueMap[Function[{part,metrics},KeyValueMap[(part<>#1)->#2&,metrics]],m]]]
];
exportRun[run_,out_,cacheRelative_] := Module[{sig=run["Signature"],r,records=<||>,part,pred,rows},
 Do[r=Join[flatMetrics[run,part],<|"RunFile"->(cacheRelative<>"/"<>sig<>".wxf"),
   "PredictionsFile"->("predictions/"<>sig<>"_"<>part<>".csv"),
   "TrainingCurveFile"->("curves/"<>sig<>"_training.csv"),"ValidationCurveFile"->("curves/"<>sig<>"_validation.csv")|>];
  AssociateTo[records,part->r];pred=run["Predictions"][part];
  writeTable[FileNameJoin[{out,"predictions",sig<>"_"<>part<>".csv"}],pred],{part,{"Final","Best"}}];
 rows=MapThread[<|"Batch"->#1,"OnlineTrainingLoss"->#2|>&,{run["RoundPositions"],run["RoundLossList"]}];
 writeTable[FileNameJoin[{out,"curves",sig<>"_training.csv"}],rows];
 rows=MapThread[<|"Batch"->#1,"ValidationLoss"->#2|>&,{run["ValidationPositions"],run["ValidationLossList"]}];
 writeTable[FileNameJoin[{out,"curves",sig<>"_validation.csv"}],rows];
 records
];
baselineRows[dataset_,split_] := Module[{rows=dataset["Rows"],pred,records={},i,y,ids},
 pred=ValidationData`ExactBaseline /@ rows;
 If[!AllTrue[pred,NumberQ],Return[{}]];
 Do[ids=split[part];y=Lookup[rows[[ids]],"Target"];
  AppendTo[records,<|"Dataset"->dataset["ID"],"Baseline"->"Exact coefficient ratio using q0 and q1",
    "Split"->part,"Count"->Length[ids],"RMSE"->N[Sqrt[Mean[(pred[[ids]]-y)^2]]],
    "MAPE"->If[MemberQ[y,0],Missing["ZeroTarget"],N[100 Mean[Abs[(pred[[ids]]-y)/y]]]],
    "InputScope"->"Uses full exact q0 and q1; not an equal-input baseline for the 15-coefficient slice"|>],
  {part,{"Train","Validation","Test"}}];records
];
RunStudy[root_String,options_Association] := Catch[Module[
 {defaults,experiments,specs,selected,smoke,rounds,seeds,hash,jobs,out,outputID,data=<||>,splits=<||>,
  dataset,ds,spec,rows,split,manifest={},st,ids,job,run,records,finalRows={},bestRows={},failures={},
  cacheRelative,cacheDir,i,baselines={},dataManifest={},n,m,failed,runResult,outputMarker},
 defaults=Import[FileNameJoin[{root,"config","defaults.json"}],"RawJSON"];
 experiments=Import[FileNameJoin[{root,"config","experiments.json"}],"RawJSON"];
 specs=Import[FileNameJoin[{root,"config","datasets.json"}],"RawJSON"];
 If[!AssociationQ[defaults]||!ListQ[experiments]||!AssociationQ[specs],stop["Config","Invalid study configuration files."]];
 If[defaults["CoefficientCount"]=!=30 || defaults["SplitFractions"]=!={0.75,0.15,0.10},
  stop["Protocol","This study fixes 30 generated coefficients and 75/15/10 group splits."]];
 selected=selectExperiments[experiments,options];smoke=TrueQ[options["Smoke"]];
 rounds=If[smoke,5,options["Rounds"]];seeds=If[smoke,{First[defaults["Seeds"]]},defaults["Seeds"]];
 If[smoke,selected=Select[experiments,MemberQ[
   {"wd_eta_negative_128_ADAM","table2_N3","table3_N3","table4_N7","table6_N3","e2_signedlog_compact"},#["ExperimentID"]]&];
  selected=(Join[#,<|"Model"->8,"LayerWidths"->{8},"Smoke"->True|>]&)/@selected];
 hash=sourceHash[root];
 jobs=Flatten[Table[settings[defaults,e,seed,hash,rounds],{e,selected},{seed,seeds}],1];
 outputID=StringTake[IntegerString[Hash[{hash,jobs,$Version,$SystemID},"SHA256"],16,64],16];
 out=FileNameJoin[{root,"results",If[smoke,"smoke","rounds-"<>ToString[rounds]],outputID}];
 ensure[out];ensure[FileNameJoin[{root,"results"}]];
 must[Export[FileNameJoin[{root,"results","LATEST.txt"}],out,"Text"]];
 outputMarker=Environment["MODULAR_VALIDATION_OUTPUT_FILE"];
 If[StringQ[outputMarker]&&outputMarker=!="",must[Export[outputMarker,out,"Text"]]];
 save[FileNameJoin[{out,"configuration.wxf"}],<|"Defaults"->defaults,"Options"->options,"Experiments"->selected,
   "Rounds"->rounds,"SourceHash"->hash,"Version"->$Version,"SystemID"->$SystemID,"Smoke"->smoke|>];
 Print["Scheduled ",Length[jobs]," fits at ",rounds," rounds. Results: ",out];
 Print["All reported MAPE/RMSE values use decoded modular weights. Training loss uses the declared target transform."];
 cacheRelative="results/cache/"<>StringTake[hash,16];cacheDir=FileNameJoin[{root,cacheRelative}];
 ids=DeleteDuplicates[Lookup[selected,"Dataset"]];
 Do[Print["Preparing exact data: ",ds];spec=resolveSpec[specs[ds],root,smoke];
  dataset=must[ValidationData`GetDataset[ds,spec,root,FileNameJoin[{root,"results","data_cache"}]]];
  rows=dataset["Rows"];split=must[MakeSplit[rows,defaults["SplitSeed"]]];
  AssociateTo[data,ds->dataset];AssociateTo[splits,ds->split];
  writeTable[FileNameJoin[{out,"splits",ds<>".csv"}],splitRecords[rows,split]];
  AppendTo[dataManifest,Join[<|"Dataset"->ds,"Rows"->Length[rows],"DistinctPowers"->Length[DeleteDuplicates[Lookup[rows,"Power"]]],
   "DuplicatePowerCount"->dataset["DuplicatePowerCount"],"PowerMin"->Min[Lookup[rows,"Power"]],"PowerMax"->Max[Lookup[rows,"Power"]]|>,dataset["Files"]]];
  baselines=Join[baselines,baselineRows[dataset,split]],{ds,ids}];
 writeTable[FileNameJoin[{out,"data_manifest.csv"}],dataManifest];writeTable[FileNameJoin[{out,"analytic_baselines.csv"}],baselines];
 Do[ds=job["Dataset"];rows=data[ds]["Rows"];split=splits[ds];
  AppendTo[manifest,Join[job,<|"HiddenLayers"->Length[job["LayerWidths"]],
   "Width"->If[Length[DeleteDuplicates[job["LayerWidths"]]]==1,First[job["LayerWidths"]],"varies"],
   "Parameters"->UnifiedTraining`ParameterCount[Length[job["FeaturePositions"]],job["Model"]],
   "Rows"->Length[rows],"PowerMin"->Min[Lookup[rows,"Power"]],"PowerMax"->Max[Lookup[rows,"Power"]],
   "TrainCount"->Length[split["Train"]],"ValidationCount"->Length[split["Validation"]],"TestCount"->Length[split["Test"]]|>]],{job,jobs}];
 writeTable[FileNameJoin[{out,"experiment_manifest.csv"}],manifest];
 Do[job=jobs[[i]];ds=job["Dataset"];
  Print["Fit ",i,"/",Length[jobs],": ",job["ExperimentID"]," / seed ",job["Seed"]];
  run=UnifiedTraining`TrainRun[data[ds]["Rows"],splits[ds],job,cacheDir];
  If[FailureQ[run]||run===$Failed||!AssociationQ[run]||Lookup[run,"Status",""]=!="Complete",
   AppendTo[failures,Join[KeyTake[job,{"ExperimentID","Dataset","Model","Optimizer","Seed","Rounds"}],<|"Failure"->failureSummary[run]|>]];
   writeTable[FileNameJoin[{out,"failures.csv"}],failures];Print["FAILED: ",failureSummary[run]],
   records=exportRun[run,out,cacheRelative];AppendTo[finalRows,records["Final"]];AppendTo[bestRows,records["Best"]];
   writeTable[FileNameJoin[{out,"metrics_final.csv"}],finalRows];writeTable[FileNameJoin[{out,"metrics_best.csv"}],bestRows];
   writeTable[FileNameJoin[{out,"run_index.csv"}],Flatten[Transpose[{finalRows,bestRows}],1]]],{i,Length[jobs]}];
 writeTable[FileNameJoin[{out,"failures.csv"}],failures];
 save[FileNameJoin[{out,"completion.wxf"}],<|"Scheduled"->Length[jobs],"Completed"->Length[bestRows],"Failed"->Length[failures],"Smoke"->smoke|>];
 Print["Finished: ",Length[bestRows],"/",Length[jobs]," completed; ",Length[failures]," failed. Results: ",out];
 If[failures=!={},Failure["StudyIncomplete",<|"MessageTemplate"->"Some fits failed; see failures.csv. Successful fits are saved.","OutputDirectory"->out|>],
  <|"Status"->"Complete","OutputDirectory"->out,"CompletedFits"->Length[bestRows]|>]
],"UnifiedStudyFailure"];
End[];EndPackage[];
