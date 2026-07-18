# Distribution

## Development archive

```bash
make release-local
```

`dist/releases/<version>/`へad-hoc署名のZIPとSHA-256ファイルを生成します。これは開発確認用であり、一般配布には使用しません。

## Public distribution outside the Mac App Store

Apple Developer ProgramのDeveloper ID Application証明書と、公証用のnotarytoolプロファイルが必要です。

証明書をKeychainへ追加した後、利用可能な署名IDを確認します。

```bash
security find-identity -v -p codesigning
```

公証資格情報はKeychainへ保存します。アプリ固有パスワードをコマンド履歴へ直接残さないでください。

```bash
xcrun notarytool store-credentials "capture-codex-notary" \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID"
```

Universal BinaryのDeveloper ID署名、公証、DMG作成、staple、SHA-256生成を実行します。
DMGはアプリとApplicationsフォルダを左右に配置したドラッグインストール形式で生成します。

ローカルでDMG生成を確認する場合は、専用の仮想環境へ固定バージョンの`dmgbuild`をインストールします。

```bash
python3 -m venv .release-venv
.release-venv/bin/pip install --require-hashes -r scripts/requirements-release.txt
make verify
DMGBUILD_PYTHON="$PWD/.release-venv/bin/python" \
  ./scripts/create-dmg.sh \
  "dist/Capture Codex.app" \
  "Capture Codex" \
  "/tmp/Capture-Codex-preview.dmg"
```

```bash
SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
NOTARY_PROFILE="capture-codex-notary" \
make release-notarized
```

出力先:

```text
dist/releases/<version>/Capture-Codex-<version>-macOS.dmg
dist/releases/<version>/Capture-Codex-<version>-macOS.dmg.sha256
```

## Verification

```bash
./scripts/verify-app.sh "dist/Capture Codex.app"
xcrun stapler validate "dist/releases/<version>/Capture-Codex-<version>-macOS.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 \
  "dist/releases/<version>/Capture-Codex-<version>-macOS.dmg"
```

## GitHub release secrets

`.github/workflows/release.yml`を使う場合、次のRepository secretsを設定します。

- `DEVELOPER_ID_CERTIFICATE_P12`: Developer ID Application証明書のP12をBase64化した値
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: P12のパスワード
- `DEVELOPER_ID_APPLICATION`: `Developer ID Application: ...`形式の署名ID
- `APPLE_ID`: 公証に使用するApple ID
- `APPLE_TEAM_ID`: Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: Apple IDのアプリ固有パスワード

タグ名と`Info.plist`のバージョンを一致させてください。例: `v0.1.6`。
