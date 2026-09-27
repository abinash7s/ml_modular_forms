VerificationTest[
 Module[{rows,split,groups},rows=Table[<|"Group"->ToString[Ceiling[i/2]]|>,{i,80}];
 split=UnifiedStudy`MakeSplit[rows,42];groups=(Lookup[rows[[split[#]]],"Group"]&)/@{"Train","Validation","Test"};
 {Sort[Join@@Values[split]]===Range[80],Intersection[groups[[1]],groups[[2]]]=== {},
 Intersection[groups[[1]],groups[[3]]]=== {},Intersection[groups[[2]],groups[[3]]]=== {}}],
 {True,True,True,True},TestID->"Repeated powers cannot cross split boundaries"]
VerificationTest[
 Module[{rows=Table[<|"Group"->ToString[i]|>,{i,999}],sp},sp=UnifiedStudy`MakeSplit[rows,42];Length /@ Values[sp]],
 {749,150,100},TestID->"Integer CHL split sizes"]
