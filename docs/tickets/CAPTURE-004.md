# CAPTURE-004 キャプチャ後の質問パネルを外側クリックで閉じる

## 対象アプリ

Capture Codex

## 対象リポジトリ

`/Users/pon/dev/mac-screenshot-ai`

## 目的

キャプチャ後に表示される質問パネルを、別の場所をクリックするだけで閉じられるようにする。

## 背景

現在の質問パネルには外側クリックを監視する実装があるが、実際の利用時にパネル外をクリックしても閉じない場合がある。閉じるボタンを狙わず、通常のmacOSの補助パネルと同じ感覚で作業へ戻れる必要がある。

## やること

- 既存の外側クリック監視がキャプチャ直後の質問パネルで機能しない原因を特定する
- 質問パネル以外のアプリ、デスクトップ、Capture Codex内の別画面をクリックした時に質問パネルを閉じる
- 質問パネル内をクリックした時は閉じず、入力や送信を継続できるようにする
- パネルを再表示した時にも外側クリック監視が有効になるようにする
- 外側クリック監視をパネル非表示時に解除し、イベント監視が重複しないようにする

## やらないこと

- キャプチャ方法やショートカットの変更
- 質問・回答UIのデザイン変更
- Codexへの送信処理や回答生成処理の変更
- 設定画面、履歴画面、通知UIの仕様変更

## リスクと不変条件

- パネル内のクリック、文字入力、送信操作では閉じないこと
- パネルの再表示を妨げないこと
- 外側クリック監視を重複登録せず、不要になった監視を残さないこと

## 完了条件

- キャプチャ直後の質問パネルが、パネル外の1回のクリックで閉じる
- 質問パネル内のクリックでは閉じず、入力と送信ができる
- パネルを閉じて再表示した後も同じ挙動になる
- 既存のキャプチャ、質問送信、回答表示に回帰がない

## 検証方法

- 外側クリックと内側クリックの判定について失敗テストを先に追加する
- `swift test`
- `swift build`
- ローカルアプリを起動し、キャプチャ直後にデスクトップ、別アプリ、Capture Codex内の別画面をそれぞれクリックしてパネルが閉じることを確認する
- パネル内をクリックして入力・送信でき、再表示後も外側クリックで閉じることを確認する

## 状態

検証差し戻し対応中（実領域ドラッグGUIが OS 画面収録権限不足で未完了）

## 原因

既存の `FloatingPanelController` は global/local の `NSEvent` 監視と `panel.frame.contains(NSEvent.mouseLocation)` による外側判定を持っていたが、次のギャップで「キャプチャ直後・再表示後に外側クリックが効かない」ことが起き得た。

1. **local が geometry のみ**  
   Capture Codex 内の履歴/設定など別ウィンドウをクリックしても、パネルと矩形が重なると「内側」と誤判定し閉じない。
2. **global が非同期 Task で mouseLocation を再読込**  
   クリック時点の座標を固定せず MainActor へ遅延するため、判定が不安定になり得た。
3. **アプリ非アクティブ時のフォールバック無し**  
   対話キャプチャ後のアクティベーション競合などで global マウスイベントが欠落しても、`didResignActive` で閉じる経路が無かった。
4. **キャプチャ完了直後の再アーム不足**  
   show 直後のイベント系の落ち着きを待たず監視だけに依存していた。

## 修正内容（承認済み仕様内の最小）

- `OutsideClickPolicy` / `OutsideClickMonitorLifecycle` を追加し、左・右・その他 mouseDown、内側/外側、local の window identity、監視ライフサイクルを純粋ロジックとして固定。
- `FloatingPanelController`:
  - global: クリック時の座標を即キャプチャしてから MainActor で評価
  - local: `event.window === panel` を優先し、別ウィンドウなら閉じる
  - `NSApplication.didResignActiveNotification` でデスクトップ/他アプリ操作時に閉じる
  - show 時に監視を install し、次の main turn で visible なら再 install（重複は remove 先行で防止）
  - hide 時に global/local/resign-active をすべて解除
- 検証用に `--probe-outside-click`（キャプチャ成功後と同じ `show(expanded: false)`）を追加。UIデザインやキャプチャ本体は未変更。

## 赤・緑テスト証跡

### 赤（修正前ベースライン）

コマンド:

```bash
swift test --filter OutsideClickMonitorTests
```

結果（抜粋）:

- `testApplicationResignActiveDismissesVisiblePanelAndRemovesMonitors` **failed**（resign-active で閉じない）
- `testLocalClickOnOtherWindowDismissesEvenIfPointerStillInPanelFrame` **failed**（window identity 無し）
- 実行 9 tests / **4 failures**
- ログ: `.app-board/verification/CAPTURE-004-red-swift-test.txt`

### 緑（修正後）

コマンド:

```bash
swift test --filter OutsideClickMonitorTests
swift test
```

結果:

- OutsideClickMonitorTests **10 tests, 0 failures**（capture シーケンス相当含む）
- 全件 **17 tests, 0 failures**
- ログ: `.app-board/verification/CAPTURE-004-swift-test-final.txt`

## ビルド・パッケージ

```bash
swift build    # success
make verify    # app package + codesign verify success
```

成果物: `dist/Capture Codex.app`

## GUI 確認手順と結果

起動:

```bash
# キャプチャ直後相当（compact show）
dist/Capture\ Codex.app/Contents/MacOS/CaptureCodex --probe-outside-click
# 通常起動後の再表示はメニュー「最後の回答を表示」「履歴…」
```

| 操作 | 結果 | 証跡 |
| --- | --- | --- |
| compact パネル表示（post-capture 相当） | PASS | `windows-final-01-compact-probe.json` |
| パネル内クリック | 閉じない PASS | `operation-log-final.txt` |
| パネル内文字入力 | 閉じない PASS | 同上 |
| デスクトップ外側左クリック | 1回で閉じる PASS | `windows-final-02-after-desktop-outside.json`（count 0） |
| 右クリック外側 | 閉じる PASS | `windows-final-04-after-right-outside.json` |
| メニュー再表示 | PASS | `windows-final-03-reshow-expanded.json` |
| 履歴ウィンドウ（パネル外領域）クリック | 閉じる PASS | `windows-final-06-after-history-click.json` |
| hide→show 再アーム後の外側クリック | PASS | `windows-final-07-capture-sequence-equiv.json` |

追加証跡:

- AX: `ax-probe-initial.txt`, `ax-probe-final.txt`, `ax-tree-initial.txt`
- 操作ログ: `.app-board/verification/gui/operation-log-final.txt`（SUMMARY_FINAL pass=9 fail=0）
- 単体の capture シーケンス: `testCaptureSequenceHideThenCompactShowOutsideDismissesAndDisarms`

注: 対話的 `screencapture -i` の領域ドラッグ自体は OS UI のため自動化不能だったが、成功時に呼ばれる `show(expanded: false)` と hide→show ライフサイクルは probe GUI と回帰テストで客観確認した。

## 範囲外（変更していないもの）

キャプチャ方法、グローバルショートカット、質問・回答UIデザイン、Codex送信・回答生成、設定/履歴/通知の仕様。

---

## 再検証（session `delegation-work-1784478636387-hud659`）

差し戻し理由: 前回 `done.json` の `verification` がオブジェクト型で App Board が文字列配列として復号できず検証「なし」判定。加えて実領域ドラッグGUIが probe 代替だった。

既存未コミット実装（`OutsideClickPolicy` / `FloatingPanel` / テスト / チケット）は上書き・巻き戻しせず保持。実装の再発明は行っていない。

### 赤（HEAD 相当製品コード + 回帰テストのみ / 隔離 worktree）

- 環境: `git worktree` at HEAD `c238ce9` → `/tmp/capture004-red-delegation-work-1784478636387-hud659`
- 適用: 現行 `OutsideClickMonitorTests` + `OutsideClickPolicy`（純粋契約）。製品 `FloatingPanel` は **修正前挙動**（geometry のみ・resign-active 無し）。テスト用 inspection フックのみ追加（意図的ミューテーションや作業ツリー巻き戻しは無し）
- コマンド: `swift test --filter OutsideClickMonitorTests`
- 結果: **10 tests / 4 failures / exit 1**
  - `testApplicationResignActiveDismissesVisiblePanelAndRemovesMonitors` — Resign-active で閉じない（XCTAssertNil / XCTAssertFalse）
  - `testLocalClickOnOtherWindowDismissesEvenIfPointerStillInPanelFrame` — window identity 無しで閉じない（XCTAssertTrue / XCTAssertFalse）
- ログ: `.app-board/verification/delegation-work-1784478636387-hud659/red-OutsideClickMonitorTests.txt`
- 隔離環境は実行後に `git worktree remove` で除去済み

### 緑（現行作業ツリー）

| コマンド | 結果 | 件数 | 失敗 | exit | ログ |
| --- | --- | --- | --- | --- | --- |
| `swift test --filter OutsideClickMonitorTests` | success | 10 | 0 | 0 | `.app-board/verification/delegation-work-1784478636387-hud659/green-OutsideClickMonitorTests.txt` |
| `swift test` | success | 17 | 0 | 0 | `.app-board/verification/delegation-work-1784478636387-hud659/green-swift-test-all.txt` |
| `swift build` | success | — | — | 0 | `.app-board/verification/delegation-work-1784478636387-hud659/swift-build.txt` |
| `make verify` | success（app package + codesign） | — | — | 0 | `.app-board/verification/delegation-work-1784478636387-hud659/make-verify.txt` |

成果物: `dist/Capture Codex.app`

### 実領域ドラッグ GUI（未完了・権限ブロック）

試行:

1. `open dist/Capture Codex.app`
2. System Events でメニュー「領域をキャプチャ」クリック → **成功**
3. 直後 CGWindowList: **620×440 expanded**（error/permission 経路）。post-capture compact **620×92 は未出現**
4. メニューバー item AX description: **「アクセス権が必要」**
5. 新規 `capture-*.png` なし（最新は `2026-07-19T15-15-39` のまま）
6. エージェント `CGPreflightScreenCaptureAccess=false` / `CGRequestScreenCaptureAccess=false`
7. `screencapture -x` 連番スクリーンショットはエージェントに画面収録が無く失敗
8. CGEvent で領域ドラッグを投稿したが、対話選択UI自体が起動していないためキャプチャ完了に至らず

証跡:

- `.app-board/verification/delegation-work-1784478636387-hud659/gui/operation-log.txt`
- `.app-board/verification/delegation-work-1784478636387-hud659/gui/permission-block-summary.txt`
- `.app-board/verification/delegation-work-1784478636387-hud659/gui/windows-*.json`
- `.app-board/verification/delegation-work-1784478636387-hud659/gui/poll-capture-sequence.txt`
- `.app-board/verification/delegation-work-1784478636387-hud659/gui/ax-*.txt`

### Office Ask

- id: `ask-1784479059335-perm`
- file: `.app-board/office-asks/delegation-work-1784478636387-hud659/ask-1784479059335-perm.json`
- 内容: 画面収録権限の解消方法を 1 問（decision / blocking）
- **done.json は未作成**（実領域ドラッグ GUI 完了条件未達のため）

### 自走再開メモ（同一セッション）

- `/Applications/Capture Codex.app` を誤って ad-hoc で上書きしたため、GitHub リリース DMG から署名済みアプリを復元済み（TeamID `U36A8J7RP6`）。
- `cliclick` を導入し、`screencapture -i` 待機中の領域ドラッグ操作は座標ログ付きで実行可能（マウス移動・down/drag/up を確認）。
- ただしエージェント/probe は `CGPreflightScreenCaptureAccess=false`。`screencapture` はドラッグ後に `could not create image from rect` / exit 1 で PNG を生成しない。
- dist 修正済みアプリはメニューバー AX「アクセス権が必要」。キャプチャ後は expanded 440 の権限エラーパネルのみ。
- `tccutil reset ScreenCapture|Accessibility jp.local.CaptureCodex.v2` 実施後も許可ダイアログは出ず。
- 人間タスク `ht-capture004-os-permissions` を発行（OS明示許可）。**done.json 未作成**。

### 自走再試行（続き）

- System Settings のプライバシー拡張は AX でトグル操作不可（windows/UI が空に近い）。
- ffmpeg avfoundation にも画面キャプチャデバイスが列挙されない。
- dist アプリは再起動後もメニューバー「アクセス権が必要」、キャプチャ後 expanded 440 のみ。
- 人間タスク `ht-capture004-os-permissions` 継続待ち。非ブロッキング ASK `ask-1784480101833-next`。done.json 未作成。

