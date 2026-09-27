(* Exact Fourier coefficients. No floating-point series expansion or label-dependent input transform. *)
BeginPackage["ValidationData`"];
EtaProductCoefficients::usage = "EtaProductCoefficients[{{scale,exponent},...},count] gives exact coefficients after removing the leading q power, retaining all q positions including zeros.";
SeriesPowerCoefficients::usage = "SeriesPowerCoefficients[c,p] raises an exact unit-constant formal series to an exact rational power.";
GenerateRows::usage = "GenerateRows[id,spec] creates exact rows with physical-weight Target, Power, TargetFactor, log-absolute-power LatentTarget and all requested q positions.";
ResolveDatasetSpec::usage = "ResolveDatasetSpec[spec,root] expands exact PowerRange, PowerHalfIntegerRange or a bundled PowersFile to an explicit Powers list without generating coefficients.";
GetDataset::usage = "GetDataset[id,spec,root,dataDir] creates or loads a content-identified dataset and exports exact coefficient and metadata CSV files alongside its WXF cache.";
ExactBaseline::usage = "ExactBaseline[row] returns the physical weight from q^0 and q^1 when both are available; otherwise Missing.";
Begin["`Private`"];

$DataSchemaVersion = 1;
$DataSourceHash = IntegerString[FileHash[$InputFileName, "SHA256"], 16, 64];
exactRationalQ[x_] := IntegerQ[x] || Head[x] === Rational;
failure[tag_, message_] := Failure[tag, <|"MessageTemplate" -> message|>];
sigma[n_Integer?Positive] := sigma[n] = DivisorSigma[1, n];
exactString[x_] := ToString[x, InputForm];

EtaProductCoefficients[terms_List, count_Integer?Positive] := Module[{a, b, n, k},
  If[! AllTrue[terms, MatchQ[#, {_Integer?Positive, _?exactRationalQ}] &],
    Return[failure["ExactEtaInput", "Eta factors must be pairs of a positive integer scale and an exact rational exponent."]]];
  a = ConstantArray[0, count]; a[[1]] = 1;
  b = Table[-Total[Map[If[Mod[k, #[[1]]] == 0,
      #[[2]] #[[1]] sigma[k/#[[1]]], 0] &, terms]], {k, count - 1}];
  Do[a[[n + 1]] = Together[Sum[b[[k]] a[[n - k + 1]], {k, n}]/n], {n, count - 1}];
  a
];

SeriesPowerCoefficients[c_List, p_?exactRationalQ] := Module[{count = Length[c], b, a, n, k},
  If[count == 0 || First[c] =!= 1 || ! AllTrue[c, exactRationalQ],
    Return[failure["UnitSeries", "An exact nonempty coefficient list with constant coefficient one is required."]]];
  b = ConstantArray[0, count - 1]; a = ConstantArray[0, count]; a[[1]] = 1;
  Do[b[[n]] = Together[n c[[n + 1]] - Sum[b[[k]] c[[n - k + 1]], {k, n - 1}]], {n, count - 1}];
  Do[a[[n + 1]] = Together[p Sum[b[[k]] a[[n - k + 1]], {k, n}]/n], {n, count - 1}];
  a
];

convolve[a_List, b_List] := Table[
  Sum[a[[k + 1]] b[[n - k + 1]], {k, 0, n}],
  {n, 0, Min[Length[a], Length[b]] - 1}];

GenerateRows[id_String, spec_Association] := Module[
  {family, powers, count, positions, level, factor, e2, rows, p, coefficients, target, leading, metadata, i},
  family = Lookup[spec, "Family", Missing["Family"]];
  powers = Lookup[spec, "Powers", Missing["Powers"]];
  count = Lookup[spec, "CoefficientCount", 30];
  positions = Lookup[spec, "Positions", If[IntegerQ[count] && count > 0, Range[0, count - 1], {}]];
  level = Lookup[spec, "Level", 1];
  If[! MemberQ[{"Eta", "CHL", "E2Eta", "E2Power"}, family],
    Return[failure["Family", "Supported families are Eta, CHL, E2Eta and E2Power."]]];
  If[! ListQ[powers] || Length[powers] == 0 || ! AllTrue[powers, exactRationalQ] || MemberQ[powers, 0],
    Return[failure["Powers", "Powers must be a nonempty list of nonzero exact integers or rationals."]]];
  If[! IntegerQ[count] || count < 2 || ! ListQ[positions] || Length[positions] == 0 ||
      ! DuplicateFreeQ[positions] || ! AllTrue[positions, IntegerQ[#] && 0 <= # < count &],
    Return[failure["CoefficientPositions", "Provide at least two generated coefficients and distinct valid zero-based retained positions."]]];
  If[family === "CHL" && ! MemberQ[{1, 2, 3, 5, 7}, level],
    Return[failure["CHLLevel", "This benchmark supports CHL levels 1, 2, 3, 5 and 7."]]];
  factor = Switch[family, "Eta", 1/2, "CHL", 24/(level + 1), "E2Eta", 1, "E2Power", 2];
  If[MemberQ[{"E2Eta", "E2Power"}, family], e2 = Prepend[Table[-24 sigma[i], {i, count - 1}], 1]];
  rows = Table[
    p = powers[[i]];
    Switch[family,
      "Eta",
        coefficients = EtaProductCoefficients[{{1, p}}, count]; target = p/2; leading = p/24;
        metadata = <|"EtaExponent" -> p, "TargetDefinition" -> "eta exponent / 2",
          "MathematicalClass" -> "eta power with its inherited multiplier and cusp behavior"|>,
      "CHL",
        coefficients = EtaProductCoefficients[{{1, factor p}, {level, factor p}}, count];
        target = factor p; leading = p;
        metadata = <|"Level" -> level, "ParentWeight" -> factor,
          "TargetDefinition" -> "24 power/(N+1)",
          "MathematicalClass" -> If[IntegerQ[p], "integer power of a CHL eta product",
            "specified rational power of a CHL eta product; do not assume a standard scalar modular form"]|>,
      "E2Eta",
        (* p denotes the eta factor's weight. E2 contributes another two units. *)
        coefficients = 2 convolve[e2, EtaProductCoefficients[{{1, 2 p}}, count]];
        target = p + 2; leading = p/12;
        metadata = <|"EtaWeight" -> p, "EtaExponent" -> 2 p, "E2Prefactor" -> 2,
          "TargetDefinition" -> "eta weight + 2", "MathematicalClass" -> "E2 times an eta power; quasimodular with inherited multiplier"|>,
      "E2Power",
        coefficients = SeriesPowerCoefficients[e2, p]; target = 2 p; leading = 0;
        metadata = <|"TargetDefinition" -> "formal weight 2 power", "MathematicalClass" ->
          If[IntegerQ[p] && p > 0, "quasimodular form", "rational or fractional power of E2; not an ordinary holomorphic quasimodular form"]|>
    ];
    <|"ID" -> id <> "-" <> IntegerString[i, 10, 4], "Family" -> family,
      "Group" -> id <> "-power-" <> exactString[p], "Power" -> p, "TargetFactor" -> factor,
      "Target" -> target, "LatentTarget" -> If[MemberQ[{"Eta", "CHL"}, family], Log[Abs[p]], target],
      "Coefficients" -> coefficients[[positions + 1]], "Positions" -> positions,
      "Metadata" -> Join[metadata, <|"LeadingQPower" -> leading, "Power" -> p,
        "FullCoefficientCount" -> count, "RetainedCoefficientPositions" -> positions,
        "FullZeroCoefficientCount" -> Count[coefficients, 0]|>]|>,
    {i, Length[powers]}];
  rows
];

ExactBaseline[row_Association] := Module[{positions, loc0, loc1, a0, ratio, family, level},
  positions = row["Positions"];
  loc0 = FirstPosition[positions, 0]; loc1 = FirstPosition[positions, 1];
  If[MissingQ[loc0] || MissingQ[loc1], Return[Missing["RequiredCoefficientsAbsent"]]];
  a0 = Extract[row["Coefficients"], loc0];
  If[TrueQ[a0 == 0], Return[Missing["ZeroLeadingCoefficient"]]];
  ratio = Extract[row["Coefficients"], loc1]/a0; family = row["Family"];
  Switch[family,
    "Eta", -ratio/2,
    "CHL", level = row["Metadata"]["Level"]; -ratio/If[level == 1, 2, 1],
    "E2Eta", -ratio/2 - 10,
    "E2Power", -ratio/12,
    _, Missing["NoExactBaseline"]]
];

exportDataset[dataset_Association, prefix_String] := Module[{rows, positions, coefficients, metadata, paths, result},
  rows = dataset["Rows"]; positions = First[rows]["Positions"];
  coefficients = Prepend[
    Map[Join[{#["ID"], exactString[#["Power"]], exactString[#["Target"]]}, exactString /@ #["Coefficients"]] &, rows],
    Join[{"ID", "PowerExact", "WeightExact"}, ("q" <> ToString[#] &) /@ positions]];
  metadata = Prepend[Map[{
      #["ID"], #["Group"], #["Family"], exactString[#["Power"]], exactString[#["Target"]],
      exactString[#["TargetFactor"]], exactString[#["LatentTarget"]],
      exactString[#["Metadata"]["LeadingQPower"]], #["Metadata"]["FullZeroCoefficientCount"],
      #["Metadata"]["TargetDefinition"], #["Metadata"]["MathematicalClass"]} &, rows],
    {"ID", "Group", "Family", "PowerExact", "WeightExact", "TargetFactorExact", "LatentTargetExact",
      "LeadingQPowerExact", "FullZeroCoefficientCount", "TargetDefinition", "MathematicalClass"}];
  paths = <|"Cache" -> prefix <> ".wxf", "CoefficientsCSV" -> prefix <> "_coefficients.csv",
    "MetadataCSV" -> prefix <> "_metadata.csv"|>;
  result = Check[{
    Export[paths["CoefficientsCSV"], coefficients, "CSV"],
    Export[paths["MetadataCSV"], metadata, "CSV"],
    Export[paths["Cache"], dataset, "WXF"]}, $Failed];
  If[result === $Failed || MemberQ[result, $Failed],
    failure["DatasetExport", "Could not save all dataset outputs under " <> prefix], paths]
];

ResolveDatasetSpec[inputSpec_Association, root_String] := Module[{spec = inputSpec, powersFile, powers},
  If[! KeyExistsQ[spec, "Powers"] && KeyExistsQ[spec, "PowerRange"],
    powers = spec["PowerRange"];
    If[! ListQ[powers] || ! MemberQ[{2, 3}, Length[powers]] || ! AllTrue[powers, IntegerQ] ||
        (Length[powers] == 3 && Last[powers] == 0),
      Return[failure["PowerRange", "PowerRange must give two integer endpoints and optionally a nonzero integer step."]]];
    spec = Join[KeyDrop[spec, "PowerRange"], <|"Powers" -> Apply[Range, powers]|>]
  ];
  If[! KeyExistsQ[spec, "Powers"] && KeyExistsQ[spec, "PowerHalfIntegerRange"],
    powers = spec["PowerHalfIntegerRange"];
    If[! ListQ[powers] || ! MemberQ[{2, 3}, Length[powers]] || ! AllTrue[powers, IntegerQ] ||
        (Length[powers] == 3 && Last[powers] == 0),
      Return[failure["PowerHalfIntegerRange", "PowerHalfIntegerRange must give integer endpoints and optionally a nonzero integer step before dividing by two."]]];
    spec = Join[KeyDrop[spec, "PowerHalfIntegerRange"], <|"Powers" -> Apply[Range, powers]/2|>]
  ];
  If[! KeyExistsQ[spec, "Powers"] && KeyExistsQ[spec, "PowersFile"],
    powersFile = FileNameJoin[{root, spec["PowersFile"]}];
    If[! FileExistsQ[powersFile], powersFile = FileNameJoin[{root, "resources", spec["PowersFile"]}]];
    If[! FileExistsQ[powersFile], Return[failure["PowersFile", "Missing bundled power list: " <> powersFile]]];
    (* This is a trusted, bundled Wolfram Language data file containing one exact list. *)
    powers = Quiet[Check[Get[powersFile], $Failed]];
    If[powers === $Failed, Return[failure["PowersFile", "Cannot read bundled power list: " <> powersFile]]];
    spec = Join[KeyDrop[spec, "PowersFile"], <|"Powers" -> powers|>]
  ];
  powers = Lookup[spec, "Powers", Missing["Powers"]];
  If[! ListQ[powers] || Length[powers] == 0 || ! AllTrue[powers, exactRationalQ] || MemberQ[powers, 0],
    Return[failure["Powers", "Resolved powers must be a nonempty list of nonzero exact integers or rationals."]]];
  spec
];

GetDataset[id_String, inputSpec_Association, root_String, dataDir_String] := Module[
  {spec, datasetHash, prefix, cached, rows, dataset, files},
  If[! StringMatchQ[id, RegularExpression["[A-Za-z0-9_-]+"]],
    Return[failure["DatasetID", "Dataset identifiers may contain only letters, digits, hyphens and underscores."]]];
  spec = ResolveDatasetSpec[inputSpec, root]; If[FailureQ[spec], Return[spec]];
  datasetHash = IntegerString[Hash[{$DataSchemaVersion, $DataSourceHash, id, KeySort[spec]}, "SHA256"], 16, 64];
  If[! DirectoryQ[dataDir], CreateDirectory[dataDir, CreateIntermediateDirectories -> True]];
  prefix = FileNameJoin[{dataDir, id <> "_" <> StringTake[datasetHash, 16]}];
  If[FileExistsQ[prefix <> ".wxf"],
    cached = Quiet[Check[Import[prefix <> ".wxf", "WXF"], $Failed]];
    If[AssociationQ[cached] && Lookup[cached, "DatasetHash", ""] === datasetHash &&
        Lookup[cached, "SchemaVersion", -1] === $DataSchemaVersion && ListQ[Lookup[cached, "Rows", None]],
      files = <|"Cache" -> prefix <> ".wxf", "CoefficientsCSV" -> prefix <> "_coefficients.csv",
        "MetadataCSV" -> prefix <> "_metadata.csv"|>;
      If[! AllTrue[Values[files], FileExistsQ], files = exportDataset[cached, prefix]];
      If[FailureQ[files], Return[files]];
      Return[Join[cached, <|"Files" -> files|>]]
    ]
  ];
  rows = GenerateRows[id, spec]; If[FailureQ[rows], Return[rows]];
  dataset = <|"ID" -> id, "SchemaVersion" -> $DataSchemaVersion, "DatasetHash" -> datasetHash,
    "SourceHash" -> $DataSourceHash, "SourceHashDefinition" -> "SHA256 of src/Data.wl when loaded",
    "Spec" -> spec, "Powers" -> spec["Powers"], "Rows" -> rows,
    "CoefficientConvention" -> "q=exp(2 Pi I tau); leading fractional q power removed; exact positions and zeros retained",
    "DuplicatePowerCount" -> Length[rows] - Length[DeleteDuplicates[Lookup[rows, "Power"]]]|>;
  files = exportDataset[dataset, prefix]; If[FailureQ[files], Return[files]];
  Join[dataset, <|"Files" -> files|>]
];

End[];
EndPackage[];
