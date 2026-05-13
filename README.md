# `bolta-io/h6s-action` — H6S Platform GitHub Action

홈택스·은행·카드 거래내역을 GitHub Actions 워크플로우에서 한 step 으로 수집한다. 결과는 CSV(기본) 또는 JSON/JSONL/Markdown/YAML 로 파일에 저장되고, 다음 step 에서 `outputs.path` 로 받아 PR·Artifact·알림 등 원하는 후속 액션에 자유롭게 연결할 수 있다.

내부적으로 [`@h6s-ai/cli`](https://www.npmjs.com/package/@h6s-ai/cli) 의 `h6s fetch` 매크로를 호출한다 — credential 자동 매칭 + data-job 비동기 폴링 + 결과 저장까지 CLI 가 담당.

## 빠른 시작

```yaml
name: 거래내역 매월 수집
on:
  schedule: [{ cron: '0 0 1 * *' }]   # 매월 1일 00:00 UTC (한국 시간 09:00)
  workflow_dispatch: {}
jobs:
  fetch:
    runs-on: ubuntu-latest
    permissions: { contents: write, pull-requests: write }
    steps:
      - uses: actions/checkout@v6

      - id: prev-month
        run: echo "value=$(date -u -d '1 month ago' +%Y-%m)" >> "$GITHUB_OUTPUT"

      - id: fetch
        uses: bolta-io/h6s-action@v0
        with:
          api-key: ${{ secrets.H6S_API_KEY }}
          schema: bank.transactions.cb.v1
          provider: ibk_bank
          month: ${{ steps.prev-month.outputs.value }}
          output-path: ./data/bank/

      - uses: peter-evans/create-pull-request@v6
        with:
          title: '거래내역 ${{ steps.fetch.outputs.summary }}'
          branch: data/bank-${{ steps.fetch.outputs.job-id }}
          add-paths: data/
```

## 버전 핀

내부에서 호출하는 `@h6s-ai/cli` 가 아직 0.x 라 액션 버전도 0.x 를 따라간다. rolling 메이저 태그는 **`@v0`**, 정확한 버전 태그는 `@v0.4.x` 형태로 푸시된다. CLI 가 1.0 으로 graduate 하는 시점에 `@v1` 태그가 함께 등장하고 README/examples 도 업데이트된다.

## 인증

`H6S_API_KEY` 1개로 끝. 콘솔(https://h6s.ai) → API Key 발급 → repository secret `H6S_API_KEY` 에 등록 → 위 예시처럼 `${{ secrets.H6S_API_KEY }}` 전달.

## 입력 (`inputs`)

| 입력 | 필수 | 기본 | 설명 |
|---|---|---|---|
| `api-key` | ✓ | — | H6S Open API key |
| `schema` | ✓ | — | 수집 대상 schema id (예: `bank.transactions.cb.v1`) |
| `provider` | ✓ | — | providerCode (예: `ibk_bank`, `kb_bank`, `hometax`). 콘솔에 등록된 credential 중 이 provider 에 매칭되는 1개가 자동 선택 |
| `month` | | | `YYYY-MM`. 1일~말일을 dateRangeStart/End 로 사용 |
| `from` | | | `YYYY-MM-DD` |
| `to` | | | `YYYY-MM-DD` |
| `params` | | | schema request 필드 JSON (multiline) |
| `output-format` | | `csv` | `csv`\|`json`\|`jsonl`\|`markdown`\|`yaml` |
| `output-path` | | `./out/` | 디렉터리 또는 파일 경로 |
| `cli-version` | | (액션 동기) | `@h6s-ai/cli` 버전 핀 |
| `timeout` | | `30m` | data-job 폴링 한도 |
| `node-version` | | `20` | 내부 setup-node 가 호출될 때 |
| `skip-node-setup` | | `false` | 이미 setup-node 한 경우 |

### 의도적으로 공개 인풋에서 뺀 항목

- **`credential-id`** — UUID 를 워크플로우 yaml 에 직접 박는 UX 부담이 큼. `provider` 만 주면 백엔드 `CredentialMatcher` 가 매칭되는 PROVIDER_BOUND credential 또는 공동인증서를 자동 선택하므로 직접 지정할 일이 없다.
- **`base-url`** — 내부 sandbox/local 디버깅용 URL. 외부 인풋으로 노출하지 않음. 사내에서 sandbox 테스트가 필요하면 호출 워크플로우의 `env:` 블록에 `H6S_API_BASE_URL` 을 직접 세팅하면 composite step 으로 그대로 상속된다.
- **`profile`** — 다중 환경 프로필. CI 는 `api-key` 직접 주입이라 의미 없음. 필요 시 `env: H6S_PROFILE`.
- **`cache`** — GH runner 는 매번 클린이라 항상 `off` 로 고정.

## 출력 (`outputs`)

| 출력 | 형식 | 용도 |
|---|---|---|
| `path` | 절대 경로 | 다음 step 의 파일 경로 (PR/Artifact/Upload) |
| `count` | 정수 | 레코드 수 |
| `job-id` | UUID | data-job 식별자. 콘솔에서 같은 잡 확인 가능 |
| `summary` | 한 줄 텍스트 | `"bank.transactions.cb.v1: 47건 (2026-03)"` |

## 사용 패턴 (cookbook)

- [examples/monthly-bank-collect.yml](./examples/monthly-bank-collect.yml) — 매월 1일 전월 거래내역 + PR 생성 (plain-text accounting 표준)
- [examples/weekly-multi-schema.yml](./examples/weekly-multi-schema.yml) — `strategy.matrix` 로 은행/세금계산서/현금영수증 병렬 수집
- [examples/notify-on-fetch.yml](./examples/notify-on-fetch.yml) — 수집 후 Slack 알림
- [examples/upload-artifact.yml](./examples/upload-artifact.yml) — 결과를 GH Artifact 로 보존
- [examples/ai-ledger-trigger.yml](./examples/ai-ledger-trigger.yml) — 수집 후 Claude Code Action 으로 전표 자동 작성
- [examples/multi-provider-matrix.yml](./examples/multi-provider-matrix.yml) — 여러 기관(provider) 병렬 수집 (마이크로 그랜트·피지컬 스폰서십 분리 계좌)

## 동작 흐름

1. `actions/setup-node` 로 Node 20 준비 (이미 했다면 `skip-node-setup: true`)
2. `npm install -g @h6s-ai/cli@<버전>`
3. `h6s fetch <schema> --no-wait` 로 data-job 제출 → JOB_ID 캡처
4. `h6s data-jobs get <JOB_ID> --wait --timeout <timeout>` 로 완료 대기
5. `h6s data-jobs results <JOB_ID>` 로 결과 저장
   - `csv` 인 경우: 서버측 다운로드 (UTF-8 BOM + 한국어 헤더, 회계사 인계용)
   - 그 외: CLI 가 클라이언트 측 직렬화
6. `outputs` 4종 + `$GITHUB_STEP_SUMMARY` 기록

## 라이선스

[Apache License 2.0](./LICENSE).
