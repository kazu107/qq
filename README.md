# qq

Godot 4.6 / GDScriptで実装しているリアルタイムカードタクティクスです。

## 必要環境

- Godot 4.6系（検証済み: `Godot_v4.6.2-stable_win64`）
- Windows PowerShell
- LAN対戦はGodot標準のENetのみで動作し、EOS設定は不要

## セットアップ

1. リポジトリをcloneする。
2. Godotで`project.godot`を開く。
3. `Boot`メインシーンから起動する。EOS SDKやClient Secretの追加設定は必要ない。

`.godot/`は生成物のためclone後に再生成される。`.import`と`.uid`はプロジェクト整合性に使用するためGit管理対象とする。

オンライン対戦は一時停止中で、ハブの入口とEOS GDExtensionは無効化している。将来再開する場合の手順は`docs/ONLINE_MULTIPLAYER.md`に保存している。

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

JSON、scene/resource参照、Variant型推論、headless起動、各機能のsmoke test、オンライン停止状態、LAN対戦、ネットワークsoakを検証する。

## セーブ

- セーブ: `user://save.json`
- リプレイ: `user://replays`

これらはローカル実行データのためGitには含めない。
