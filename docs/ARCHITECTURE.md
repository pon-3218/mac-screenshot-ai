# Architecture

Capture CodexはAppKitとSwiftUIで構成されたmacOSメニューバーアプリです。外部Swiftパッケージには依存していません。

## Components

- `CaptureCodexApp.swift`: アプリのライフサイクル、メニューバー、各ウィンドウの生成
- `AppModel.swift`: キャプチャ、会話、アプリ内完了表示、履歴を連携するメイン状態
- `CaptureService.swift`: macOSの対話型領域キャプチャとクリップボード書き込み
- `GlobalHotkeyMonitor.swift`: グローバルショートカットの監視と変更
- `CodexAppServerClient.swift`: ローカルの`codex app-server --stdio`とのJSON Lines通信
- `FloatingPanel.swift`: 質問、ストリーミング回答、追加質問UI
- `CompletionToast.swift`: 回答完了を示し、クリックで最後の回答を開くアプリ内表示
- `HistoryStore.swift`: JSON形式のローカル回答履歴
- `SettingsWindow.swift`: モデル、ショートカット、権限状態の設定UI

## Data flow

1. グローバルショートカットを検出する。
2. `/usr/sbin/screencapture -i`でユーザーが選択した領域を一時PNGへ保存する。
3. PNGをmacOSクリップボードへ書き込む。
4. 質問時にCodex App Serverを一時プロセスとして起動する。
5. 画像パスと質問を読み取り専用・ネットワークなしのスレッド設定でApp Serverへ渡す。
6. App Serverが返す差分をUIへ表示し、完了後に回答履歴とアプリ内完了表示を更新する。

Codex CLI自体のサービス通信と認証はCodex CLIが担当します。アプリはAPIキーを保持しません。
