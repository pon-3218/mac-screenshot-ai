# Contributing

IssueやPull Requestを歓迎します。変更は小さく保ち、目的と確認方法を説明してください。

## 開発環境

- macOS 14以降
- Xcode Command Line ToolsまたはXcode
- Swift 6.1以降
- 実際のAI応答を確認する場合はCodex CLI

## 確認手順

```bash
swift build
make verify
```

UI変更では、ライト・ダーク表示、キーボードフォーカス、権限未許可、回答待機、エラー、長文回答を確認してください。

## Pull Request

- 1つのPull Requestでは1つの目的に絞ってください。
- 新しい外部依存は、必要性とライセンスを説明してください。
- ユーザーデータの送信範囲を変える変更では、`PRIVACY.md`も更新してください。
- モデル名やCodex App Serverプロトコルに関する変更は、利用したCodex CLIのバージョンを記載してください。
