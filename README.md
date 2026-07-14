# qq

Godot 4.6 / GDScriptで実装しているリアルタイムカードタクティクスです。

## 必要環境

- Godot 4.6系（検証済み: `Godot_v4.6.2-stable_win64`）
- Windows PowerShell
- オンライン対戦を使う場合はEpic Online Services SDK 1.19.1.2

## セットアップ

1. リポジトリをcloneする。
2. Godotで`project.godot`を開く。
3. `Boot`メインシーンから起動する。

`.godot/`は生成物のためclone後に再生成される。`.import`と`.uid`はプロジェクト整合性に使用するためGit管理対象とする。

オンライン対戦を使うPCでは、EOS SDKとClient Secretをローカルへ設定する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup_eos.ps1 `
  -SdkPath 'C:\path\to\EOS-SDK-CSharp-53289219-Release-v1.19.1.2'
powershell -NoProfile -ExecutionPolicy Bypass -File tools\configure_eos_credentials.ps1
```

Client SecretとEOS公式ランタイムDLLはGitへ含めない。詳しい接続・検証手順は`docs/ONLINE_MULTIPLAYER.md`を参照する。

## 構成

- `src/`: ゲームロジック、autoload、UIスクリプト。
- `scenes/`: 各画面とテスト用シーン。
- `data/`: カード、敵、遺物、イベント、ローカライズJSON。
- `assets/`: カード画像、立ち絵、効果音。
- `tests/`: smoke testと検証スクリプト。
- `docs/`: 仕様書と運用手順。

## 検証

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate_project.ps1 `
  -GodotPath 'C:\Users\kazuu\Downloads\Godot_v4.6.2-stable_win64.exe'
```

JSON、scene/resource参照、Variant型推論、headless起動、各機能のsmoke test、LAN/オンライン回帰、ネットワークsoakを検証する。

## セーブ

- セーブ: `user://save.json`
- リプレイ: `user://replays`

これらはローカル実行データのためGitには含めない。
