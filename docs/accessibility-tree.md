# Xcode 内 Claude パネルの AX 構造メモ

> **状態: 未検証。** ここに書く内容は、アプリの AX Inspector（CLAUDE.md 第 10 章）で
> 実機のツリーをダンプして確認してから埋めます。推測でコードを書かないでください
> （CLAUDE.md 第 18 章）。

## 確認すべき項目（CLAUDE.md 第 18 章より）

- [ ] Claude パネルは独立した AX ウィンドウか、Xcode ウィンドウの子要素か
- [ ] 入力欄の AX role（`AXTextArea` / `AXTextField` など）と、`AXValue` の書き込み可否
- [ ] 制限到達メッセージが現れる要素の role と文言（`sessionLimited` / `weeklyLimited` の区別）
- [ ] 送信ボタンが AX 要素として露出しているか、`AXPress` が効くか
- [ ] ウィンドウが最小化・非アクティブでも AX ツリーを読めるか
- [ ] Xcode の Claude 連携に、Claude Code の `/config` 相当の自動継続設定が追加されていないか
      （追加されていれば本プロジェクトの前提が崩れる。着手前に必ず確認）

## ダンプの取り方

1. アプリのメニューから **Debug → AX Inspector** を開く
2. 対象の Xcode ウィンドウを選ぶ
3. **Export JSON** で `AXSnapshot` 形式を書き出す
4. 実在のプロジェクト名・パス・個人情報が含まれないことを確認する
5. `Packages/SentinelCore/Tests/SentinelCoreTests/Fixtures/` に置き、
   `DetectionEngineFixtureTests` に回帰ケースを追加する

## 既知の構造

（未記入）

## Xcode バージョン別の差異

| Xcode バージョン | 変化点 | 対応 |
|---|---|---|
| （未記入） | | |
