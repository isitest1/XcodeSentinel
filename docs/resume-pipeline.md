# 再開パイプライン（M3）

判定と再開実行は分離します（CLAUDE.md 第 4.2 章）。方針を決めるのは
`SentinelCore.ResumeOrchestrator`、実際に AX を操作するのはホストの
`App/Automation/ResumeController` です。

## 構成要素

| レイヤ | 型 | 役割 |
|---|---|---|
| SentinelCore | `DetectionEngine` | AX スナップショット → `SessionState` |
| SentinelCore | `SafetyPolicy` | 1 日上限・クールダウン・停止ごとのリトライ上限・Dry-run |
| SentinelCore | `ResumeScheduler` | 優先度キュー・同時実行上限・投入間隔・Quiet Hours・`notBefore` 保留 |
| SentinelCore | `ResetTimeParser` | リセット時刻 → 再試行時刻 |
| SentinelCore | **`ResumeOrchestrator`** | 上記を結線し、副作用を持たない `OrchestratorEffect` を返す |
| App (macOS) | `ResumeCoordinator` | effect を実行（通知・タイマー・再開送信の呼び出し） |
| App (macOS) | `ResumeController` | 入力欄への書き込み・送信・`.working` 遷移確認（AX） |

## 1 サイクルの流れ

```
検出 → orchestrator.ingest(observation) → [OrchestratorEffect]
                                          ├─ notify(...)            → ローカル通知 / Webhook
                                          ├─ recheck(target, at)    → 対象のポーリングタイマー再設定
                                          └─（eligible なら）Scheduler に enqueue

任意のタイミング → orchestrator.pump()   → [performResume] または [recheckQueue(at)]
performResume 実行後 → orchestrator.recordSendOutcome(outcome)
                                          ├─ sent/dryRun → 15 秒後に再確認（.working になったか）
                                          └─ 失敗       → notify(resumeFailedNeedsAttention)
```

## 状態ごとの扱い

| `SessionState` | ingest の結果 |
|---|---|
| `working` / `idle` / `completed` | リカバリ扱い（stall カウンタと unknown 連続数をクリア）、キューから除去、通常間隔で再確認 |
| `unknown` | 連続数を +1。3 連続で監視一時停止 + 通知。未満なら 60 秒後に再確認 |
| `awaitingApproval` / `awaitingUserAnswer` / `errored` | **通知のみ**。キューに入れない |
| `awaitingContinue` | `SafetyPolicy` 判定 → OK ならキュー投入（`notBefore` なし） |
| `sessionLimited` | 通知（再開予定時刻付き）+ キュー投入（`notBefore` = リセット +60s、または検出 +5h5m） |
| `weeklyLimited` | 通知 + キュー投入（`notBefore` = リセット +60s、または検出 +6h）。再確認は 30 分間隔 |

## 守っていること（CLAUDE.md 第 7.2 / 17 章）

- 1 停止につき自動再開は既定 1 回、同理由の再発で 2 回目まで、3 回目で停止して通知
- `awaitingApproval` / `awaitingUserAnswer` / `unknown` では自動送信しない
- 制限到達時に短間隔リトライ連打をしない（`notBefore` と状態別ポーリング間隔）
- Dry-run では実送信せず「何を送るはずだったか」だけを扱う
- 通知本文に対象名・状態・時刻以外を含めない
