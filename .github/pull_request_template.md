## 概要

<!-- 何を・なぜ変更したか。関連 Issue があれば #番号 で参照 -->

## 変更点

-

## 動作確認

<!-- 実施したものにチェック -->

- [ ] `Scripts/test-core.sh`（または CI）で `SentinelCore` のテストが通る
- [ ] `App/` を変更した場合、ホストの macOS で `xcodebuild` が通ることを確認した
- [ ] `docs/site/` を変更した場合、EN / JA の両方を更新した
- [ ] 破壊的挙動（自動送信まわり）に関わる変更はない／あれば安全策を確認した

## チェックリスト

- [ ] コミットメッセージは Conventional Commits 形式（英語）
- [ ] UI 文言・識別子・コメントは英語、ドキュメントは日本語（CLAUDE.md 第 2 章）
- [ ] `SentinelCore` に `AppKit` / `ApplicationServices` / `SwiftUI` を import していない
- [ ] チャット本文・ソースコードをログや Webhook に送出していない
