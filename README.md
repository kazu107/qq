# qq

Godot 4.6 系 / GDScript で実装しているリアルタイムカードタクティクスです。

## 必要環境

- Godot 4.6 系
  - 現在の検証実績: `Godot_v4.6.2-stable_win64`
- Windows PowerShell

## プロジェクト構成

- `project.godot`
  - Godot プロジェクト本体
- `src/`
  - ゲームロジック、autoload、UI スクリプト
- `scenes/`
  - 各画面 / テスト用シーン
- `data/`
  - カード、敵、遺物、イベント、ローカライズ JSON
- `assets/`
  - カード画像、立ち絵、効果音
- `tests/`
  - smoke test と検証スクリプト
- `docs/`
  - 仕様書と作業メモ

## セットアップ

1. このリポジトリを clone する
2. Godot で `project.godot` を開く
3. 必要なら main scene をそのまま `Boot` から起動する

`.godot/` は生成物なので clone 後に再生成されます。  
`.import` と `.uid` はプロジェクト整合性に使うので Git 管理対象です。

## 実行

- Godot エディタから `project.godot` を開いて再生
- または Godot CLI で headless 実行

## 検証

PowerShell から次を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File tests\validate_project.ps1 -GodotPath 'C:\Users\kazuu\Downloads\Godot_v4.6.2-stable_win64.exe'
```

検証内容:

- JSON 構文チェック
- scene / resource 参照チェック
- Variant 推論の静的スキャン
- headless editor load
- 各種 smoke test

## セーブ / リプレイ

- セーブ: `user://save.json`
- リプレイ出力: `user://replays`

これらはローカル実行データなので Git には含めません。
