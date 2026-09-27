(* Parse all notebook input cells without evaluating them, then run the shared tests.
   No neural training is performed. Run from a terminal with:
   wolframscript -file check_notebooks.wls
*)
bundleRoot = DirectoryName[ExpandFileName[$InputFileName]];
notebookFiles = Sort[FileNames["*.nb", FileNameJoin[{bundleRoot, "notebooks"}]]];
If[Length[notebookFiles] != 4, Print["Expected four notebooks."]; Exit[1]];
syntaxFailures = {};
totalInputCells = 0;
Do[
  nbExpression = Quiet[Check[Get[file], $Failed]];
  If[Head[nbExpression] =!= Notebook,
    AppendTo[syntaxFailures, {FileNameTake[file], "Cannot read Notebook expression"}],
    inputBoxes = Cases[nbExpression, Cell[BoxData[b_], "Input", ___] :> b, Infinity];
    totalInputCells += Length[inputBoxes];
    Do[
      heldInput = Quiet[Check[ToExpression[inputBoxes[[i]], StandardForm, HoldComplete], $Failed]];
      If[Head[heldInput] =!= HoldComplete,
        AppendTo[syntaxFailures, {FileNameTake[file], "Input cell", i}]],
      {i, Length[inputBoxes]}]
  ], {file, notebookFiles}];
Print["Notebook input cells checked: ", totalInputCells];
If[syntaxFailures =!= {}, Print["Syntax failures: ", syntaxFailures]; Exit[1]];
Do[Get[FileNameJoin[{bundleRoot, "support", "src", file}]],
  {file, {"Data.wl", "Training.wl", "Study.wl"}}];
testReport = TestReport[FileNames["*.wlt", FileNameJoin[{bundleRoot, "support", "tests"}]]];
testResults = testReport["Results"];
If[!ListQ[testResults] || testResults === {}, Print["No test results returned."]; Exit[1]];
passed = Count[(#["Outcome"] &) /@ testResults, "Success"];
Print["Shared tests: ", passed, "/", Length[testResults], " passed."];
Scan[If[#["Outcome"] =!= "Success",
  Print["FAILED: ", #["TestID"], "; actual: ", Short[#["ActualOutput"], 3]]] &, testResults];
If[TrueQ[testReport["ReportSucceeded"]], Exit[0], Exit[1]];
