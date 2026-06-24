# ⚠️ Read-only mirror

이 저장소는 [bolta-io 의 private 모노레포](https://h6s.ai) 에서
`packages/h6s-action/` 디렉토리만 GitHub Actions 로 자동 동기화하는 **단방향 미러**입니다.

- 매 동기화는 `git push --force` 로 main 을 덮어씁니다 — 이 repo 의 커밋 히스토리는 보존되지 않습니다.
- **이 repo 에 직접 PR/이슈를 올리지 마세요.** 다음 동기화 때 사라집니다.
- 버그 리포트·기능 요청·기여는 [h6s.ai](https://h6s.ai) 또는 h6s@bolta.io 로 보내주세요.

이 repo 의 용도는 단 하나 — `uses: bolta-io/h6s-action@v2` 로 GitHub Actions 워크플로우에서
headless 의 거래 데이터를 수집할 수 있게 하는 것입니다.
