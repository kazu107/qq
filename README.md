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

## バージョン管理

ゲーム独自の `QQ-MAJOR.MINOR.PATCH` 形式を使用します。現在の番号と更新履歴は `data/version_history.json` を唯一の情報源とし、実装を変更するたびに番号と履歴を更新します。詳細は `docs/VERSIONING.md` を参照してください。

## 検証

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate_project.ps1 `
  -GodotPath 'C:\Users\kazuu\Downloads\Godot_v4.6.2-stable_win64.exe'
```

JSON、scene/resource参照、Variant型推論、headless起動、ゲーム機能smoke、Web設定、シグナリングルームと中継を検証します。

## 効果音

生成済みWAVはリポジトリに含まれるため、別PCで音声モデルを用意する必要はありません。生成環境では次のコマンドで共通SE、カード固有SE、遺物固有SEを再生成できます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\generate_sfx.ps1 -Force
node tools\validate_sfx.mjs
```

生成スクリプトは人声を避ける条件を全モデル音へ適用し、派生音の作成後に`tools\normalize_sfx.mjs`で全WAVを共通の音量基準へ自動調整します。

開発者モードを有効にすると、開発者パネルの`SE再生ラボ`から登録済みSEを検索・個別再生・連続再生できます。

## セーブ

- セーブ: `user://save.json`
- リプレイ: `user://replays`

Web版ではブラウザのIndexedDBへ保存されます。
