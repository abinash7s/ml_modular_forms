(* Use the shell launcher; all options arrive as validated environment values. *)
studyRoot=Environment["MODULAR_VALIDATION_ROOT"];
If[!StringQ[studyRoot],
 Print["Use bash run.sh (or bash run.sh --plan / --test / --smoke). This internal driver does not parse command-line flags."];
 Exit[2]];
studyRoot=ExpandFileName[studyRoot];
studyMode=Environment["MODULAR_VALIDATION_MODE"];
If[!StringQ[studyMode],Print["Launch through bash run.sh."];Exit[2]];
studyRoundsText=Environment["MODULAR_VALIDATION_ROUNDS"];
studyDefaults=Import[FileNameJoin[{studyRoot,"config","defaults.json"}],"RawJSON"];
studyRounds=If[StringQ[studyRoundsText],
 If[StringMatchQ[studyRoundsText,RegularExpression["[1-9][0-9]*"]],FromDigits[studyRoundsText],0],studyDefaults["Rounds"]];
studySuite=Environment["MODULAR_VALIDATION_SUITE"];If[!StringQ[studySuite],studySuite="all"];
studyOnly=Environment["MODULAR_VALIDATION_ONLY"];If[!StringQ[studyOnly],studyOnly=""];
If[!MemberQ[{"run","smoke","test"},studyMode]||!MemberQ[{"all","width-depth","chl","e2"},studySuite]||studyRounds<1,
 Print["Invalid options. Use bash run.sh --plan or bash run.sh --help."];Exit[2]];
Get[FileNameJoin[{studyRoot,"src","Data.wl"}]];
Get[FileNameJoin[{studyRoot,"src","Training.wl"}]];
Get[FileNameJoin[{studyRoot,"src","Study.wl"}]];
If[studyMode==="test",
 studyTestFiles=FileNames["*.wlt",FileNameJoin[{studyRoot,"tests"}]];
 If[studyTestFiles==={},Print["No MUnit test files found."];Exit[1]];
 studyTests=TestReport[studyTestFiles];
 studyTestResults=studyTests["Results"];
 If[!ListQ[studyTestResults]||studyTestResults==={},Print["No test results were returned."];Exit[1]];
 studyPassed=Count[(#["Outcome"]&)/@studyTestResults,"Success"];
 Print["Tests: ",studyPassed,"/",Length[studyTestResults]," passed."];
 studyBrief[value_] := Module[{s=ToString[value,InputForm]},
  If[StringLength[s]>1200,StringTake[s,1200]<>" ...",s]];
 Scan[Function[t,If[t["Outcome"]=!="Success",
  Print["FAILED: ",t["TestID"]," (",t["Outcome"],")"];
  Print["  Expected: ",studyBrief[t["ExpectedOutput"]]];
  Print["  Actual: ",studyBrief[t["ActualOutput"]]];
  Print["  Messages: ",studyBrief[t["ActualMessages"]]]]],studyTestResults];
 If[!TrueQ[studyTests["ReportSucceeded"]]&&studyTests["RuntimeFailures"]=!={},
  Print["Runtime failures: ",studyBrief[studyTests["RuntimeFailures"]]]];
 If[TrueQ[studyTests["ReportSucceeded"]],Exit[0],Exit[1]]
];
studyResult=UnifiedStudy`RunStudy[studyRoot,<|"Suite"->studySuite,"Only"->studyOnly,
 "WithE2"->(Environment["MODULAR_VALIDATION_WITH_E2"]==="true"),
 "Rounds"->studyRounds,"Smoke"->(studyMode==="smoke")|>];
If[FailureQ[studyResult]||studyResult===$Failed,Print[studyResult];Exit[1]];
Print[studyResult];Exit[0];
