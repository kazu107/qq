# qq

Godot 4.6 / GDScriptで実装しているリアルタイムカードタクティクスです。通常ラン、アリーナ、無限モードに加え、ブラウザ間のWebRTC対戦に対応しています。

## 必要環境

- Godot 4.6系（検証済み: `Godot_v4.6.2-stable_win64`）
- Windows PowerShell
- Node.js 24系（Web配信とシグナリングサーバー）

## セットアップ

1. リポジトリをcloneする。
2. `npm.cmd install`を実行する。
3. Godotで`project.godot`を開き、`Boot`メインシーンから起動する。

EOS SDK、Client Secret、LANポート開放は不要です。Web対戦はWeb版をHTTPSで開き、片方がルームを作成して6文字のコードを相手へ共有します。

## WebビルドとHeroku

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_web.ps1
powershell -ExecutionPolicy Bypass -File tools\serve_web.ps1
```

Herokuはルートの`package.json`と`Procfile`を検出し、`build/web`を配信しながら`/signal`でWebRTC接続を仲介します。詳細は`docs/ONLINE_MULTIPLAYER.md`と`docs/web_build.md`を参照してください。

## 構成

- `src/`: ゲームロジック、autoload、UIスクリプト。
- `scenes/`: 各画面とテスト用シーン。
- `data/`: カード、敵、遺物、イベント、ローカライズJSON。
- `assets/`: カード画像、立ち絵、効果音。
- `server/`: Heroku用静的配信・WebRTCシグナリングサーバー。
- `tests/`: smoke testと検証スクリプト。

## 検証

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate_project.ps1 `
  -GodotPath 'C:\Users\kazuu\Downloads\Godot_v4.6.2-stable_win64.exe'
```

JSON、scene/resource参照、Variant型推論、headless起動、ゲーム機能smoke、Web設定、シグナリングルームと中継を検証します。

## セーブ

- セーブ: `user://save.json`
- リプレイ: `user://replays`

Web版ではブラウザのIndexedDBへ保存されます。
