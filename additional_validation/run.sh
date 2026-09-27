#!/usr/bin/env bash
set -euo pipefail
bundle_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
usage() {
  cat <<'USAGE'
Usage: bash run.sh [--run|--plan|--test|--smoke] [options]
Default: run all 78 width/depth and 96 manuscript-table fits, 10000 epochs each.
  --epochs N, --rounds N  Set epochs (also --epochs=N or --rounds=N)
  --suite all|width-depth|chl|e2  Select a suite
  --with-e2             Add nine E2 repair fits to the default run
  --only ID[,ID...]      Run specific experiment IDs; --plan --list lists them
  --list                Show experiment IDs in plan mode
  --no-pdf              Generate TeX without invoking pdflatex after training
  --help                Show this message
--plan never invokes Wolfram or writes results. --test does not train.
--smoke runs six five-epoch compatibility fits, saved separately.
USAGE
}
mode=run; mode_seen=false; suite=all; with_e2=false; only=""; show_list=false; compile_pdf=true
rounds="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["Rounds"])' "$bundle_root/config/defaults.json")"
rounds_seen=false
while (( $# )); do
 case "$1" in
  --run|--plan|--test|--smoke)
   if [[ "$mode_seen" == true ]]; then usage; exit 2; fi
   mode="${1#--}";mode_seen=true;shift ;;
  --rounds|--epochs)
   if (( $# < 2 )) || [[ "$rounds_seen" == true ]]; then usage;exit 2;fi
   rounds="$2";rounds_seen=true;shift 2 ;;
  --rounds=*|--epochs=*)
   if [[ "$rounds_seen" == true ]];then usage;exit 2;fi
   rounds="${1#*=}";rounds_seen=true;shift ;;
  --suite|--only)
   if (( $# < 2 ));then usage;exit 2;fi
   if [[ "$1" == --suite ]];then suite="$2";else only="$2";fi;shift 2 ;;
  --with-e2) with_e2=true;shift ;;
  --list) show_list=true;shift ;;
  --no-pdf) compile_pdf=false;shift ;;
  --help|-h) usage;exit 0 ;;
  *) usage;exit 2 ;;
 esac
done
if [[ ! "$rounds" =~ ^[1-9][0-9]*$ ]];then printf '%s\n' 'Epochs must be a positive integer.' >&2;exit 2;fi
if [[ "$mode" == smoke && "$rounds_seen" == true ]];then printf '%s\n' '--smoke always uses five epochs; omit the epoch option.' >&2;exit 2;fi
plan_args=(--suite "$suite" --rounds "$rounds")
if [[ "$with_e2" == true ]];then plan_args+=(--with-e2);fi
if [[ -n "$only" ]];then plan_args+=(--only "$only");fi
if [[ "$show_list" == true ]];then plan_args+=(--list);fi
if [[ "$mode" == plan ]];then exec python3 "$bundle_root/scripts/plan.py" "${plan_args[@]}";fi
if [[ "$show_list" == true ]];then printf '%s\n' '--list requires --plan.' >&2;exit 2;fi
python3 "$bundle_root/scripts/plan.py" "${plan_args[@]}" >/dev/null
if ! command -v wolframscript >/dev/null 2>&1;then printf '%s\n' 'wolframscript is required for this mode. --plan works without it.' >&2;exit 127;fi
export MODULAR_VALIDATION_ROOT="$bundle_root"
export MODULAR_VALIDATION_MODE="$mode"
export MODULAR_VALIDATION_SUITE="$suite"
export MODULAR_VALIDATION_ONLY="$only"
export MODULAR_VALIDATION_WITH_E2="$with_e2"
export MODULAR_VALIDATION_ROUNDS="$rounds"
result_marker="$(mktemp "${TMPDIR:-/tmp}/modular-results.XXXXXX")"
trap 'rm -f -- "$result_marker"' EXIT
export MODULAR_VALIDATION_OUTPUT_FILE="$result_marker"
status=0
wolframscript -file "$bundle_root/scripts/run.wls" || status=$?
if [[ "$mode" == test ]];then exit "$status";fi
if [[ -s "$result_marker" ]];then
 result_dir="$(cat "$result_marker")"
 report_args=(--results "$result_dir" --allow-partial)
 if [[ "$compile_pdf" == true ]];then report_args+=(--compile);fi
 python3 "$bundle_root/scripts/make_reports.py" "${report_args[@]}" || status=1
fi
exit "$status"
