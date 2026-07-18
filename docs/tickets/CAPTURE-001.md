# CAPTURE-001 メニューバー表示とGitHub公開セキュリティを修正する

## 対象アプリ

Capture Codex

## 対象リポジトリ

`/Users/pon/dev/mac-screenshot-ai`

## 目的

インストール済みアプリへ確実にアクセスできる状態にし、公開リポジトリとDeveloper ID配布経路の主要なセキュリティ不足を解消する。

## 背景

アプリのプロセスは起動しているが、ユーザー環境ではメニューバー項目を確認できない。公開監査では、DMG生成用Python依存のハッシュ未固定、GitHub上の脆弱性報告設定と保護ルール不足、PRテンプレート不足が確認された。

## スコープ

- ステータス項目を明示的に可視化し、起動直後に利用可能な導線を保証する
- DMG生成依存を完全なハッシュロックでインストールする
- 最終DMG内のアプリ署名と構成を公開前に再検証する
- SECURITY、README、CHANGELOG、Issue/PRテンプレート、CIを整備する
- GitHubのPrivate vulnerability reporting、Dependabot、ブランチ・タグ・リリース環境保護を設定する

## やらないこと

- Capture Codexの質問・回答機能の仕様変更
- Mac App Store配布への移行
- UI全体の再設計

## 実装メモ

macOS 26ではノッチやメニューバー項目数により、起動中の`NSStatusItem`が見つけにくくなる。`isVisible`、`autosaveName`、初回起動導線を用いてアクセス不能を避ける。

## 完了条件

- インストール済みアプリ起動後にステータス項目または代替の設定導線へ到達できる
- リリース用Python依存が`--require-hashes`で失敗閉鎖する
- 最終DMG内のアプリを期待するBundle ID・Team ID・署名で再検証する
- 公開リポジトリの報告・PR導線とGitHub保護設定が有効になる

## 検証方法

- `swift build`
- `make verify`
- ローカルDMG生成とマウント後の署名検証
- `/Applications/Capture Codex.app`を起動し、メニューバー・設定導線を確認
- GitHub APIまたは設定画面で保護設定を確認

## 未確認事項

- ユーザー環境でメニューバー項目が見えない直接要因がノッチによるオーバーフローか、macOS 26の可視性状態かは未確認。両方に耐える実装にする。

## 検証結果

- 2026-07-18: `swift test` 2件、`swift build`、CI相当検証に成功
- 2026-07-18: `/Applications/Capture Codex.app` 0.1.6をDeveloper ID署名で起動
- 2026-07-18: 公開DMGのSHA-256、公証staple、Gatekeeper、Bundle ID、Team IDを再検証
- 2026-07-18: [v0.1.6](https://github.com/pon-3218/mac-screenshot-ai/releases/tag/v0.1.6)を公開
- 2026-07-18: Private vulnerability reporting、Dependabot、secret scanning、push protection、main保護、Immutable Releasesを有効化
