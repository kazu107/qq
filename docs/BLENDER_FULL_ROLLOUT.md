# Blenderアート全面展開

更新: 2026-10-10 / QQ-0.32.0

## 完成範囲

`data/art_coverage.json`の対象282成果物に不足はありません。

| 区分 | 完成数 | ゲーム用形式 |
| --- | ---: | --- |
| 通常カード / 疲労 | 93 / 1 | 512px PNG、固有の構図と場面 |
| 遺物 | 86 | 512px透過PNG、台座なし |
| キャラクター / ポートレート | 25 / 25 | GLB、1024px PNG |
| 状態 / 共通UI / 効果 | 4 / 13 / 12 | 96px / 64px / 64px PNG |
| マップ / 操作部品 | 9 / 10 | 96px PNG / 従来のUI寸法 |
| 背景 / フィールド / エンブレム | 2 / 1 / 1 | 1920x1080 PNG / GLB / 256px透過PNG |

第一弾のカード6枚・遺物4個・bleed・attack、既存モデルは維持し、残りを追加しました。カードと遺物は共有部品を利用しますが、各IDに編集可能な独立Blendを保存しています。モデルは共通18ボーン・5ソケット・18アニメーションクリップへ接続しています。

SVGのQueueQuestワードマーク、マーク、統一ロード画面のアニメーションは維持します。動的な文字・HPプレート・VFX・陣営台座・欠損時フォールバックはコード表示のままです。フォント、SE、第三者プラグイン文書はBlender置換の対象ではありません。

## 再生成と証跡

各バッチの作業内容とコマンド:

- `BLENDER_BATCH04_ENEMIES.md`: 敵12モデル・Scoutを含む13画像。
- `BLENDER_CARD_BATCHES.md`: カード87枚・疲労1枚、C01からC13の固有場面。
- `BLENDER_RELIC_BATCHES.md`: 台座なし遺物82個、機構キット。
- `BLENDER_UI_BATCH.md`: 状態3・共通UI12・効果12・マップ9・操作部品10。
- `BLENDER_ENVIRONMENT_BATCH.md`: 地形、背景、Qエンブレム。

全バッチはライブBlender MCPを触らない別プロセスで制作します。原本、生成スクリプト、実レンダー、縮小出力のハッシュを記録します。カード88原本、遺物82原本、敵バッチ、UIバッチ、環境原本を別プロセスで再読み込みして検証済みです。

```powershell
python tools/finalize_blender_assets.py
```

このインポーターは、ハッシュ、寸法、ID、透過、原本の存在を検証してから制作台帳・キャラクター参照・網羅レポートを更新します。未完成を完成扱いにはしません。カード・遺物の再実行では完成済みの全88 / 82件がスキップされ、再生成0件を確認しました。

## ゲームへの統合

開発者モードのパネルから「アート確認ラボ」を開けます。カテゴリ・名前/ID検索、24件のページ分割、24/48/96/168px比較、モデルアニメーション、3Dフィールド、原本パスと出力ハッシュを確認できます。大型モデルは境界に応じてカメラを合わせ、プレビューは入力フォーカスを捕捉して閉じた後に戻します。小さい画面では内部スクロールし、閉じるボタンを常に残します。

フィールドGLBと背景2枚は起動時にキャッシュします。Webの全カード・遺物画像は従来の必要時読み込みを維持し、ラボは最大24件、4サムネイルごとにフレームを譲ります。モデルを全件同時描画する構成ではありません。

## 検証

関連する21本のGodotテストが成功しました。

- 制作: ArtProvenanceSmoke、BlenderFullArtSmoke、CardArtSmoke、RelicExpansionSmoke、StarterArtSmoke、EnemyBatch04Smoke。
- 表示・動作: ArtLabSmoke、CardLayoutSmoke、BattleStage3DSmoke、BattleStageCacheSmoke、BattleAnimationSystemSmoke、BattleAnimationLabSmoke、FatigueSmoke、UiIconBatchSmoke。
- 統合: StartupCacheSmoke、BrandingSmoke、LocalizationSmoke、SettingsSmoke、MapFacilitySmoke、HubVersionSmoke、WebExportSmoke。

`tools/web_blender_art_review.mjs`で1440x900、960x600、900x1200のラボ、疲労・大型ボス・フィールドのプレビュー、開始デッキ・マップ・アリーナ・戦闘・ラン結果を実ブラウザ表示で確認しました。範囲外レイアウトとスクリプトエラーは0件です。確認画像は`tools/.local/blender-web-review/`、機械結果は同フォルダの`report.json`です。

カード全画像と遺物の実寸コンタクトシートは`art_src/blender/cards/qa/`と`art_src/blender/relics/qa/`へ保存しています。

本番Web出力の統一ロード画面は`web_boot_loader_review.mjs`の11ケース（進捗、完了フェード、SVG動作、小画面、失敗表示など）、R2メタデータ・保存/削除方針は8件のNodeテストが成功しました。

## 容量と配布

- カード94 PNG: 21.91MiB。遺物86 PNG: 10.56MiB。ポートレート25 PNG: 29.25MiB。
- 25モデル・共有アニメーション・フィールドの27 GLB: 37.27MiB。
- フィールド: 69,284三角形、19メッシュ、53描画面、約3.94MB。
- 本番Web PCK: 63,897,824 bytes、約60.94MiB。変更前の約85.81MiBから縮小。
- `art_src/.gdignore`でBlend原本・QA画像をGodotインポートとPCKから除外。中間レンダーは`tools/.local/`へ保存。
- PCKはGitへ追加せず、既存GitHub ActionsでR2へ公開します。Herokuは既存の自動デプロイを使用します。

本書のローカル検証と公開環境での配信確認は別の検証段階です。

### 公開と互換性確認

QQ-0.32.0（`2c7bad9`）のR2公開、Herokuページ更新、公開PCKのHTTP 200、ハブ表示、ブラウザエラー0件を確認しました。Linuxの公開PCKとローカルPCKはインポート環境によりバイト数・ハッシュが異なるため、それぞれの配信マニフェストを正とします。

この照合で、WindowsのCRLFとGitチェックアウトのLF、Web出力から元GLBが除外されることが対戦用ハッシュを変える問題を発見しました。QQ-0.32.1で改行だけを正規化し、Webのモデルには制作台帳の元GLBハッシュを使います。ローカルに元GLBがある場合は従来通り実ファイルを検証します。`ContentHashSmoke`がLF/CRLF/CR、原本と台帳の一致、複合ハッシュ、キャッシュ、効果の変更を検証します。`ResponsiveDisplaySmoke`も追加で成功しました。
