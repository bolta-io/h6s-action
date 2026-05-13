#!/usr/bin/env bash
# h6s-action 의 본체. action.yml 의 composite step 이 호출.
#
# 흐름:
#   1) @h6s-ai/cli 설치 (cli-version 또는 action 동기 버전)
#   2) h6s fetch <schema> --no-wait → job 제출, JOB_ID 캡처
#   3) h6s data-jobs get <id> --wait → 폴링 + 최종 메타 (status/succeededRecordCount) 캡처
#   4) h6s data-jobs results <id> → 파일 저장 (csv 는 서버측 다운로드, 그 외는 stdout 리다이렉트)
#   5) outputs/summary 기록
set -euo pipefail

: "${H6S_API_KEY:?H6S_API_KEY 가 설정되지 않았습니다 (action input api-key)}"
: "${INPUT_SCHEMA:?schema 입력이 비어 있습니다}"
: "${INPUT_PROVIDER:?provider 입력이 비어 있습니다 (예: ibk_bank, kb_bank, hometax)}"

# ---- CLI 버전 결정 -----------------------------------------------------------
if [ -n "${INPUT_CLI_VERSION:-}" ]; then
  CLI_VER="$INPUT_CLI_VERSION"
else
  CLI_VER="$(node -p "require('${ACTION_PATH}/package.json').version")"
fi
echo "::group::@h6s-ai/cli@${CLI_VER} 설치"
npm install -g "@h6s-ai/cli@${CLI_VER}"
h6s --version || true
echo "::endgroup::"

# ---- 공통 인자 ---------------------------------------------------------------
COMMON_ARGS=(--quiet --no-color)
FETCH_ARGS=(fetch "$INPUT_SCHEMA" --no-wait --cache off --output json "${COMMON_ARGS[@]}"
            --provider "$INPUT_PROVIDER")
[ -n "${INPUT_MONTH:-}" ] && FETCH_ARGS+=(--month "$INPUT_MONTH")
[ -n "${INPUT_FROM:-}" ]  && FETCH_ARGS+=(--from "$INPUT_FROM")
[ -n "${INPUT_TO:-}" ]    && FETCH_ARGS+=(--to "$INPUT_TO")

if [ -n "${INPUT_PARAMS:-}" ]; then
  PARAMS_FILE="$(mktemp)"
  printf '%s' "$INPUT_PARAMS" > "$PARAMS_FILE"
  FETCH_ARGS+=(--params "@${PARAMS_FILE}")
fi

# ---- 1) Job 제출 -------------------------------------------------------------
echo "::group::data-job 제출"
JOB_JSON="$(h6s "${FETCH_ARGS[@]}")"
echo "$JOB_JSON"
JOB_ID="$(printf '%s' "$JOB_JSON" | node -e "
let d=''; process.stdin.on('data',c=>d+=c).on('end',()=>{
  try { process.stdout.write(JSON.parse(d).id ?? ''); } catch { process.exit(1); }
})")"
echo "::endgroup::"

if [ -z "$JOB_ID" ]; then
  echo "::error::job 제출 응답에서 id 를 찾지 못했습니다. CLI 출력: $JOB_JSON" >&2
  exit 1
fi

# ---- 2) Poll 완료 ------------------------------------------------------------
echo "::group::data-job 폴링 (id=${JOB_ID}, timeout=${INPUT_TIMEOUT})"
FINAL_JSON="$(h6s data-jobs get "$JOB_ID" --wait --timeout "$INPUT_TIMEOUT" --output json "${COMMON_ARGS[@]}")"
echo "$FINAL_JSON"
echo "::endgroup::"

STATUS="$(printf '%s' "$FINAL_JSON" | node -e "
let d=''; process.stdin.on('data',c=>d+=c).on('end',()=>{
  try { process.stdout.write(JSON.parse(d).status ?? ''); } catch { process.exit(1); }
})")"
COUNT="$(printf '%s' "$FINAL_JSON" | node -e "
let d=''; process.stdin.on('data',c=>d+=c).on('end',()=>{
  try { process.stdout.write(String(JSON.parse(d).succeededRecordCount ?? 0)); } catch { process.exit(1); }
})")"

if [ "$STATUS" != "SUCCEEDED" ]; then
  echo "::error::data-job 실패 (status=${STATUS})" >&2
  exit 1
fi

# ---- 3) 결과 저장 ------------------------------------------------------------
OUTPUT_PATH="${INPUT_OUTPUT_PATH:-./out/}"
FORMAT="${INPUT_OUTPUT_FORMAT:-csv}"

# 디렉터리 판정: 끝이 / 또는 \ 이거나 이미 존재하는 디렉터리
is_dir() {
  case "$1" in */|*\\) return 0 ;; esac
  [ -d "$1" ]
}

ext_for() {
  case "$1" in
    csv) echo csv ;;
    json) echo json ;;
    jsonl) echo jsonl ;;
    markdown) echo md ;;
    yaml) echo yaml ;;
    *) echo "$1" ;;
  esac
}

if is_dir "$OUTPUT_PATH"; then
  mkdir -p "$OUTPUT_PATH"
  EXT="$(ext_for "$FORMAT")"
  SAVED_PATH="${OUTPUT_PATH%/}/h6s_${INPUT_SCHEMA//\//-}_${JOB_ID:0:8}.${EXT}"
else
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  SAVED_PATH="$OUTPUT_PATH"
fi

echo "::group::결과 저장 (${SAVED_PATH})"
if [ "$FORMAT" = "csv" ]; then
  # 서버측 CSV (UTF-8 BOM + 한국어 헤더, 엑셀 인계용)
  h6s data-jobs results "$JOB_ID" --csv --save "$SAVED_PATH" "${COMMON_ARGS[@]}"
else
  h6s data-jobs results "$JOB_ID" --output "$FORMAT" "${COMMON_ARGS[@]}" > "$SAVED_PATH"
fi
ls -la "$SAVED_PATH"
echo "::endgroup::"

# 절대 경로로 변환
ABS_SAVED_PATH="$(cd "$(dirname "$SAVED_PATH")" && pwd)/$(basename "$SAVED_PATH")"

# ---- 4) outputs + summary ----------------------------------------------------
DATE_RANGE=""
if [ -n "${INPUT_MONTH:-}" ]; then
  DATE_RANGE="$INPUT_MONTH"
elif [ -n "${INPUT_FROM:-}" ] && [ -n "${INPUT_TO:-}" ]; then
  DATE_RANGE="${INPUT_FROM} ~ ${INPUT_TO}"
fi

SUMMARY="${INPUT_SCHEMA}: ${COUNT}건"
[ -n "$DATE_RANGE" ] && SUMMARY="${SUMMARY} (${DATE_RANGE})"

{
  echo "path=${ABS_SAVED_PATH}"
  echo "count=${COUNT}"
  echo "job-id=${JOB_ID}"
  echo "summary=${SUMMARY}"
} >> "$GITHUB_OUTPUT"

{
  echo "## H6S Fetch 결과"
  echo ""
  echo "| 항목 | 값 |"
  echo "|---|---|"
  echo "| Schema | \`${INPUT_SCHEMA}\` |"
  [ -n "${INPUT_PROVIDER:-}" ] && echo "| Provider | \`${INPUT_PROVIDER}\` |"
  [ -n "$DATE_RANGE" ] && echo "| 기간 | ${DATE_RANGE} |"
  echo "| 레코드 수 | ${COUNT} |"
  echo "| Job ID | \`${JOB_ID}\` |"
  echo "| 저장 경로 | \`${ABS_SAVED_PATH}\` |"
} >> "$GITHUB_STEP_SUMMARY"
