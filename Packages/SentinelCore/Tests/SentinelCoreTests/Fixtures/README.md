# AX スナップショットのフィクスチャ

このディレクトリには、Xcode 内 Claude パネルの Accessibility ツリーを
`AXSnapshot` 形式（JSON）で保存したものを置きます。

- ファイルはアプリの **AX Inspector**（CLAUDE.md 第 10 章）でエクスポートしたものを使います。
- 実在のプロジェクト名・ファイルパス・個人情報が含まれていないことを確認してからコミットしてください（CLAUDE.md 第 8.2 / 14.4 章）。
- ここに置いた JSON は Linux 上の単体テスト（`DetectionEngineFixtureTests`）で
  状態判定ロジックの回帰検証に使われます。

現状の JSON は Xcode の実挙動を確認する前の**暫定サンプル**です。
実機ダンプが取れ次第、差し替えてください（CLAUDE.md 第 18 章）。
