# `bolta-io/h6s-action` — headless GitHub Action

홈택스·은행 입출금내역과 카드 거래내역을 GitHub Actions 워크플로우에서 한 step 으로 수집한다. 결과는 CSV(기본) 또는 JSON/JSONL/Markdown/YAML 로 파일에 저장되고, 다음 step 에서 `outputs.path` 로 받아 PR·Artifact·알림 등 원하는 후속 액션에 자유롭게 연결할 수 있다.

## 빠른 시작

```yaml
name: 입출금내역 매월 수집
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
          provider: CB_IBK
          month: ${{ steps.prev-month.outputs.value }}
          output-path: ./data/bank/

      - uses: peter-evans/create-pull-request@v6
        with:
          title: '입출금내역 ${{ steps.fetch.outputs.summary }}'
          branch: data/bank-${{ steps.fetch.outputs.job-id }}
          add-paths: data/
```

## 인증

`H6S_API_KEY` 1개로 끝. 콘솔(https://h6s.ai) → API Key 발급 → repository secret `H6S_API_KEY` 에 등록 → 위 예시처럼 `${{ secrets.H6S_API_KEY }}` 전달.

## 무엇을 자동화할 수 있나

### 매월/매주 입출금내역을 repo 에 자동 PR
은행 입출금내역을 정기적으로 수집해 plain-text accounting (beancount/hledger) 저장소에 PR 로 올린다.
- schema: `bank.transactions.cb.v1` · provider: `CB_IBK` 등
- 결과: PR → `data/bank/*.csv`
- 예제: [monthly-bank-collect.yml](./examples/monthly-bank-collect.yml)

### 한 워크플로우에서 은행 + 홈택스 다종 수집
은행 입출금내역 + 매출/매입 세금계산서 + 매출/매입 현금영수증을 matrix 로 병렬 수집 → 한 PR.
- schema: `bank.transactions.cb.v1` + `hometax.tax-invoices.{sales,purchase}.v1` + `hometax.cash-receipts.{sales,purchase}.v1`
- 결과: 단일 PR → `data/bank/`, `data/hometax/{sales,purchase,...}/`
- 예제: [weekly-multi-schema.yml](./examples/weekly-multi-schema.yml)

### 여러 은행 계좌를 병렬로 수집
본 계좌 + 분리 계좌(다른 기관) 를 `matrix.provider` 로 한 번에. provider 만 주면 콘솔에 등록된 credential 중 매칭되는 것이 자동 선택된다.
- 예: `CB_IBK` + `CB_KB` + `CB_SHINHAN`
- 예제: [multi-provider-matrix.yml](./examples/multi-provider-matrix.yml)

### 법인카드 승인내역을 정기 수집 — 지출 모니터링
법인카드 승인 시점 거래(매입 처리 전 단계 포함)를 주기적으로 수집해 지출을 추적한다.
- schema: `card.approvals.corp.v1` · provider: `CCD_SHINHAN` 등 `CCD_*`
- 결과: PR 또는 Artifact → `data/card/*.csv`
- 예제: [card-approvals-monitor.yml](./examples/card-approvals-monitor.yml)

### 수집 결과를 Slack/Discord 로 알림
`outputs.summary` 와 `outputs.count` 를 메시지에 끼워 성공/실패 한 줄 보고.
- 예제: [notify-on-fetch.yml](./examples/notify-on-fetch.yml)

### Repo 에 commit 하지 않고 Artifact 만 보존
감사·재실행·로컬 다운로드 용도. `actions/upload-artifact@v4` 와 결합.
- 예제: [upload-artifact.yml](./examples/upload-artifact.yml)

### 수집 → AI 가 ledger 전표 자동 작성 → PR
Claude Code Action 이 수집된 CSV 를 읽고 beancount 저널에 전표를 추가. 적자 검증까지 통과한 PR 생성.
- 예제: [ai-ledger-trigger.yml](./examples/ai-ledger-trigger.yml)

## 스펙 카탈로그 / LLM 가이드

`schema` / `provider` / `params` 에 어떤 값을 넣어야 하는지는 한 곳에서 본다. 사람도, AI 어시스턴트(Claude Code/Cursor)도 동일 진입점.

| 용도 | URL / 명령 |
|---|---|
| LLM 진입 (간결) | https://h6s.ai/llms.txt |
| LLM 합본 (모든 schema · request 필드 · 에러코드) | https://h6s.ai/llms-full.txt |
| OpenAPI / Swagger UI | https://api.h6s.ai/swagger-ui.html |
| CLI — provider 카탈로그 | `npx @h6s-ai/cli providers list` |
| CLI — schema 카탈로그 + request 필드 | `npx @h6s-ai/cli schemas list` / `npx @h6s-ai/cli schemas get <id>` |
| 콘솔 웹 | https://h6s.ai/console → Schemas / Credentials |

자주 쓰는 값:

- **provider**: `CB_IBK` (기업), `CB_KB` (국민), `CB_SHINHAN` (신한), `HOMETAX` (홈택스), `CCD_SHINHAN` (신한카드) 등 13개 `CCD_*` 법인카드
- **schema**: `bank.transactions.cb.v1` (은행 입출금내역), `hometax.tax-invoices.{sales,purchase}.v1` (세금계산서 매출/매입), `hometax.cash-receipts.{sales,purchase}.v1` (현금영수증 매출/매입), `card.cards.corp.v1` (법인카드 보유카드), `card.approvals.corp.v1` (법인카드 승인내역)

> AI 에이전트가 워크플로우를 자동 생성한다면 `https://h6s.ai/llms-full.txt` 한 URL 만 fetch 한다. schema id, request 필드(필수/선택/타입), 에러 코드까지 한 번에 들어오고, 아래 `params` 입력값(JSON) 도 거기서 그대로 매핑한다.

## 입력 (`inputs`)

| 입력 | 필수 | 기본 | 설명 |
|---|---|---|---|
| `api-key` | ✓ | — | headless Open API key |
| `schema` | ✓ | — | 수집 대상 schema id (예: `bank.transactions.cb.v1`). 전체 목록: https://h6s.ai/llms-full.txt |
| `provider` | ✓ | — | providerCode (예: `CB_IBK`, `CB_KB`, `HOMETAX`). 콘솔에 등록된 credential 중 이 provider 에 매칭되는 1개가 자동 선택. 전체 목록: https://h6s.ai/llms-full.txt |
| `month` | | | `YYYY-MM`. 1일~말일을 dateRangeStart/End 로 사용 |
| `from` | | | `YYYY-MM-DD` |
| `to` | | | `YYYY-MM-DD` |
| `params` | | | schema request 필드 JSON (multiline). 각 schema 의 필수/선택 필드는 https://h6s.ai/llms-full.txt 의 schema 섹션 참고 |
| `output-format` | | `csv` | `csv`\|`json`\|`jsonl`\|`markdown`\|`yaml` |
| `output-path` | | `./out/` | 디렉터리 또는 파일 경로 |
| `cli-version` | | (액션 동기) | 액션 태그는 `@v0` (rolling 메이저) / `@v0.4.x` (정확한 버전 핀). 이 입력으로 특정 cli 버전을 강제할 수 있다 |
| `timeout` | | `30m` | data-job 폴링 한도 |
| `node-version` | | `20` | 내부 setup-node 가 호출될 때 |
| `skip-node-setup` | | `false` | 이미 setup-node 한 경우 |

## 출력 (`outputs`)

| 출력 | 형식 | 용도 |
|---|---|---|
| `path` | 절대 경로 | 다음 step 의 파일 경로 (PR/Artifact/Upload) |
| `count` | 정수 | 레코드 수 |
| `job-id` | UUID | data-job 식별자. 콘솔에서 같은 잡 확인 가능 |
| `summary` | 한 줄 텍스트 | `"bank.transactions.cb.v1: 47건 (2026-03)"` |

## 라이선스

[Apache License 2.0](./LICENSE).
