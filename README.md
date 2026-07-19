# Capture Codex

macOSの選択領域をキャプチャし、その画像についてCodexへ質問できるメニューバーアプリです。キャプチャ画像はクリップボードへコピーされ、回答完了後はアプリ内通知で知らせます。

> 非公式のオープンソースプロジェクトです。OpenAIによる公式製品、提携製品、推奨製品ではありません。

<p align="center">
  <a href="docs/assets/capture-codex-demo.mp4">
    <img src="docs/assets/capture-codex-demo.gif" alt="Capture Codexで会議資料をキャプチャし、質問して回答を確認するデモ" width="960" />
  </a>
</p>

<p align="center">
  <a href="docs/assets/capture-codex-demo.mp4">音付きデモを見る</a> · <a href="https://www.edge-grow.com/#/mac-tools">公式ページ</a>
</p>

## 主な機能

- 変更可能なグローバルショートカットによる選択領域キャプチャ
- PNG画像のクリップボードコピーとキャプチャ音
- 画面上部の質問パネルとストリーミング回答
- 同じキャプチャに対する追加質問
- モデルと推論レベルの変更
- 回答履歴、回答完了通知、クリックによる再表示
- 公開版の自動更新とメニューからの更新確認
- 画面収録・アクセシビリティ・通知設定への直接リンク

## 必要環境

- macOS 14以降
- Codex CLIがインストール済みで、利用可能なアカウントにログイン済みであること
- ソースからビルドする場合はXcode Command Line ToolsまたはXcode

アプリは次の順でCodex CLIを探します。

```text
/opt/homebrew/bin/codex
/usr/local/bin/codex
~/.local/bin/codex
~/.codex/bin/codex
```

## インストール

配布版は[最新の公証済みDMG](https://github.com/pon-3218/mac-screenshot-ai/releases/latest/download/Capture-Codex-macOS.dmg)を開き、`Capture Codex.app`をApplicationsへ移動します。

同じReleaseにある`.sha256`ファイルでダウンロードしたDMGのSHA-256を照合できます。

初回起動時に次の権限が必要です。

- 画面収録: 選択領域の画像を取得するため
- アクセシビリティ: グローバルショートカットを受け取るため
権限を変更した場合はアプリを再起動してください。

初回起動時には、権限設定と基本操作をまとめたオンボーディングが表示されます。完了後はMacへのログイン時に自動で起動し、メニューバーで待機します。自動起動は設定から変更できます。

## 使い方

1. 初期設定の`⌘⇧4`、または設定したショートカットを押します。
2. キャプチャする領域をドラッグします。
3. 画面上部の入力欄から質問または指示を送ります。
4. 回答の下にある入力欄から追加質問できます。

回答パネルは外側をクリックすると閉じます。メニューバーの「最後の回答を表示」または「履歴…」から再表示できます。

## プライバシー

質問時には、キャプチャ画像と入力文がローカルのCodex CLIを介してOpenAIのサービスへ送信されます。アプリ独自の解析、広告SDK、遠隔ログ収集はありません。詳細は[PRIVACY.md](PRIVACY.md)を参照してください。

## ソースからビルド

```bash
git clone https://github.com/pon-3218/mac-screenshot-ai.git
cd mac-screenshot-ai
make app
open "dist/Capture Codex.app"
```

ローカルビルドはad-hoc署名です。ダウンロード配布には使用せず、Developer ID署名とApple公証を行ってください。

```bash
make verify
make release-local
```

Developer ID署名、公証、DMG生成は[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)を参照してください。

## 開発

```bash
swift build
swift test
```

構成は[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、コントリビューション手順は[CONTRIBUTING.md](CONTRIBUTING.md)を参照してください。

脆弱性は公開Issueではなく、[Security Policy](SECURITY.md)に従って非公開で報告してください。通常の不具合や改善はIssue、変更提案はPull Requestを使用してください。

## 商標

CodexおよびOpenAIは、それぞれの権利者に帰属する名称または商標です。本プロジェクトでの使用は互換性を説明するためのものです。

## ライセンス

`LICENSE`を参照してください。
