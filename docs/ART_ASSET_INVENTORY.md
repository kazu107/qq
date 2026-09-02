# 画像・アイコン資産台帳と自前化計画

最終監査日: 2026-09-03

この文書は、ゲーム本体、Web出力、3D制作、開発用ファイルに含まれる視覚資産を、将来すべて自前の素材へ置き換えるための基準としてまとめたものです。`.import`、フォント、SE、動画、コードだけで構成される通常のパネルや文字装飾はファイル数に含めません。ただし、コードから画像として生成されるアイコン、フォールバック、背景は別表に含めます。

Blenderでの高精細3D制作順、共通部品、全カード・遺物・人物の派生関係は`docs/BLENDER_ART_PRODUCTION_PLAN.md`を参照してください。

## 1. 監査結果

| 区分 | 数 | 現在の形式 | 容量・仕様 | 主な用途 |
| --- | ---: | --- | --- | --- |
| カード画像 | 93 | PNG RGBA | 全て512x512、35.11 MiB | 戦闘、タイムライン、報酬、図鑑、ロードアウト、デバッグ |
| 遺物画像 | 86 | PNG RGBA | 全て512x512、30.26 MiB | バナー、報酬、イベント、アリーナ、ツールチップ |
| キャラクター・敵画像 | 25 | PNG RGB | 21枚が1254x1254、4枚が1024x1024、60.90 MiB | ラン開始、戦闘、アリーナ |
| 状態アイコン | 4 | PNG RGBA | 全て96x96、21.51 KiB | 戦闘中の状態表示とツールチップ |
| Blender製UIアイコン | 1 | PNG RGBA | 64x64、5.69 KiB | 攻撃力、カード効果 |
| アプリ用原本 | 1 | SVG | 128x128相当 | Windows/Godotアプリアイコン、Webアイコン生成元 |
| Web出力画像 | 3 | PNG RGBA | 128x128、180x180、800x600 | favicon、Apple touch icon、起動スプラッシュ |
| 3Dランタイム資産 | 3 | GLB | 合計2.57 MiB | プレイヤー、敵、共有アニメーション |
| Blender制作原本 | 3 | Blend | 合計1.76 MiB | キャラ、静止画、アニメーションの再生成 |
| 開発・文書専用画像 | 5 | PNG RGBA | 合計1.42 MiB | Blender確認画像、コンタクトシート、GD-EOS文書ロゴ |

- Git管理対象の視覚ファイルは合計224個です。内訳はPNG 217、SVG 1、GLB 3、Blend 3です。
- ゲーム固有の2Dアートは209 PNGで、`icon.svg`を含めた容量は126.30 MiBです。
- 第一弾14点は個別のSHA-256を制作証跡へ記録し、同一出力の取り違えがないことを確認しています。
- カード、遺物、ポートレート、状態アイコンは現在のデータIDと1対1で揃っています。
- Webでは容量を抑えるため、起動時の全画像展開は行わず、必要時にGodotのインポート済みテクスチャを読み込みます。ネイティブ版は起動時キャッシュ対象です。

## 2. ファイル資産の参照関係

| 資産 | 保存場所 | 読み込み元 | 欠損時 |
| --- | --- | --- | --- |
| カード | `assets/icons/cards/{card_id}.png` | `CardButton.gd`、`CardIconPicker.gd` | ID由来の256x256模様を生成 |
| 遺物 | `assets/icons/relics/{relic_id}.png` | `RelicIcon.gd`、`RelicIconRow.gd` | ID由来の128x128四角模様を生成 |
| ポートレート | `assets/portraits/{starter_or_enemy_id}.png` | `UnitPanel.gd`、`ArenaScreen.gd` | IDと陣営色由来の320x320人物プレースホルダーを生成。開始デッキ選択では3Dモデルへ移行済み |
| 状態 | `assets/icons/status/{status_id}.png` | `UnitPanel.gd` | ID由来の96x96単色四角を生成 |
| アプリアイコン | `icon.svg` | `project.godot`の`config/icon` | Godot側の既定処理 |
| Web画像 | `build/web/index*.png` | `build/web/index.html` | Web再出力時に再生成 |
| 3Dモデル | `assets/models/battle/*.glb` | `data/battle_visuals.json`、`BattleActor3D.gd`、`StarterModelPreview.gd` | 戦闘と開始デッキ選択で使用。共通のプロシージャル人型へフォールバック |

`build/web/index.icon.png`、`build/web/index.apple-touch-icon.png`、`build/web/index.png`はビルド成果物です。直接編集せず、アプリ原本とWebスプラッシュ設定を変更してから`tools/build_web.ps1`で再生成します。

## 3. 現在の生成元・権利記録

| 区分 | 現状 | 自前化に向けた判断 |
| --- | --- | --- |
| カード | 6枚はBlender原本と再生成スクリプトが揃う。残り87枚は`tools/generate_card_icons.py`または既存PNG | 第一弾を基準にシリーズ単位でBlender化する |
| 遺物 | 4個はBlender原本と再生成スクリプトが揃う。残り82個は取り込み済みPNGのみ | 第一弾の台座・機構キットを再利用して優先的に展開する |
| ポートレート | PNGのみで、編集可能な原本や生成手順は未収録 | 権利証跡と再現性が不足。自前化の優先度は高い |
| 状態アイコン | `bleed`はBlender原本あり。残り3個はPNGのみ | 同じ立体メダリオンへ展開する |
| 共通UI・マップアイコン | `attack`はBlender PNGを優先しコード生成へフォールバック。残りはGDScript生成 | 第一弾と同じ正投影・材質体系へ段階移行する |
| 3D | `.blend`、生成Python、GLB、manifestが揃う | 現時点で最も再現性が高い。今後もBlendを原本、GLBを成果物とする |
| アプリ・Webブランド | 現在はGodot標準ロゴと標準スプラッシュ | 独自ブランドではないため最優先で交換する |
| GD-EOSロゴ | プラグイン文書用の第三者ロゴ。Web出力から除外済み | ゲーム内では使わない。プラグイン文書を配布する間は出典を維持する |

「自前」の判定には、見た目が独自であるだけでなく、編集可能な原本、作者、制作日、使用ツール、第三者素材、ライセンス、書き出しハッシュを記録できることを含めます。

## 4. コード生成される画像・アイコン

### 4.1 共通ステータスアイコン

`src/ui/common/StatIconFactory.gd`が64x64 RGBAを生成してキャッシュします。`assets/icons/ui/{id}.png`が存在するIDはBlender製PNGを優先します。

| ID | 見た目・意味 | 主な使用場所 | 状態 |
| --- | --- | --- | --- |
| `attack` | 剣・攻撃力 | 戦闘、開始デッキ、イベント | Blender製PNG、コード生成フォールバック |
| `speed` | 二重シェブロン・速度 | 戦闘、開始デッキ、イベント、アリーナ報酬 | 専用生成 |
| `shield` | シールド | 戦闘、アリーナ報酬 | 専用生成 |
| `hp` | ハート・HP | ランバナー、報酬、イベント、サマリー | 専用生成 |
| `gold` | 金塊・ゴールド | ランバナー、ショップ、売却、報酬、サマリー | 専用生成 |
| `step` | 階段・進行 | ランバナー、アリーナ報酬の既定値 | 専用生成 |
| `time` | 時計・戦闘時間 | マップの戦闘サマリー | 専用生成 |
| `relic` | 菱形の遺物記号 | ランバナー、報酬、サマリー | 専用生成 |
| `card_owned` | 重なったカード・所持数 | マップ、アリーナ、報酬 | 専用生成 |
| `card_equipped` | カードと装備印・装備数 | マップ、アリーナ、特別報酬 | 専用生成 |
| `settings` | 歯車 | ハブ右上 | 専用生成 |
| `version_history` | 履歴書類 | ハブ右上 | 専用生成 |
| `card` | カード一般・ロードアウト | 施設の選択肢 | 専用絵がなく、IDハッシュ色の汎用四角を使用 |

`card`は実際に使用中ですが専用分岐がないため、共通UIの自前化時に必ず専用アイコンを作ります。未知のIDも同じ汎用四角へフォールバックします。

### 4.2 カード効果アイコン

`src/ui/common/CardEffectIconFactory.gd`がカード面の効果サマリー用に64x64 RGBAを生成してキャッシュします。攻撃、シールド、HP、速度、時間は`StatIconFactory.gd`を共有し、状態付与は`assets/icons/status/{status_id}.png`を共有します。

| ID | 意味 | 状態 |
| --- | --- | --- |
| `shield_spend` | シールド消費 | 専用生成 |
| `delay` / `haste` | タイムライン遅延・加速 | 専用生成 |
| `recast` | 再使用短縮 | 専用生成 |
| `interrupt` | カード中断 | 専用生成 |
| `cleanse` | 状態解除 | 専用生成 |
| `empower` | 戦闘中カード強化 | 専用生成 |
| `auto_queue` | カード自動投入 | 専用生成 |
| `timeline_stop` / `timeline_reverse` | タイムライン停止・逆流 | 専用生成 |
| `status:{id}` | 個別の状態付与 | 既存状態PNGを共有 |
| `status` / `effect` | 不明な状態・効果 | 専用フォールバック |

### 4.3 マップアイコン

`src/ui/map/MapNodeButton.gd`が96x96 RGBAを生成します。表示時は種類アイコン42x42、ロック52x52です。

| ID | 意味 |
| --- | --- |
| `normal_battle` | 通常戦闘 |
| `elite_battle` | エリート戦闘 |
| `boss` | ボス |
| `shop` | ショップ |
| `forge` | 鍛冶屋 |
| `heal` | 回復施設 |
| `event` | イベント |
| `hazard` | 危険地帯 |
| `lock` | 未解放ノードの錠前 |

### 4.4 UIテーマ画像

`src/autoload/UiTheme.gd`が次の小型テクスチャを起動時に生成します。

| 種類 | 状態数 | サイズ | 用途 |
| --- | ---: | --- | --- |
| CheckButtonスイッチ | 6スロット、4種類の見た目 | 48x26 | ON、OFF、左右反転、無効 |
| CheckBox | 4 | 24x24 | ON、OFF、ON無効、OFF無効 |
| HSliderつまみ | 2 | 22x22 | 通常、ハイライト |

### 4.5 背景・3D・フォールバック

| 対象 | 実装 | 内容 |
| --- | --- | --- |
| 全画面背景 | `AtmosphereBackground.gd` | グラデーション、発光円、斜め面、グリッド、ビネットをCanvas描画 |
| ラン結果背景 | `RunResultScreen.gd` | `GradientTexture2D`を実行時生成 |
| 戦闘フィールド | `BattleStage3D.gd` | 地面、タイル、草、岩、花、柱、樽、レーン、発射物、命中VFXをメッシュ生成 |
| 共通3Dキャラ | `CommonBattleHumanoid3D.gd` | 人型、装備、盾、武器、背面装備を基本メッシュから生成 |
| 3D台座 | `BattleActor3D.gd` | 陣営色の円形台座を生成 |
| カード欠損 | `CardButton.gd` | 256x256の色付き幾何学模様 |
| 遺物欠損 | `RelicIcon.gd` | 128x128の色付き四角模様 |
| ポートレート欠損 | `UnitPanel.gd` | 320x320の簡易人物模様 |
| 状態欠損 | `UnitPanel.gd` | 96x96の単色四角 |
| 不明UIアイコン | `StatIconFactory.gd` | 64x64のIDハッシュ色四角 |

## 5. 自前素材の入稿仕様

| 区分 | 推奨原本 | ゲーム用出力 | 必須条件 |
| --- | --- | --- | --- |
| カード | 1024x1024以上のレイヤー付き原本 | 512x512 PNG、sRGB、RGBA | 名前、種類、効果が絵だけで判別できる固有構図。文字やレア枠は焼き込まない。外周8%をUI安全域にする |
| 遺物 | 1024x1024以上のレイヤー付き原本 | 512x512 PNG、sRGB、RGBA | 1個の物体を中央に置き、48px表示でも輪郭が判別できる。名前は画像へ入れない |
| ポートレート | 1536x1536以上 | 1024x1024 PNG、sRGB | 頭部と上半身を中央60%に収め、左右のトリミングに耐える。全25枚の画角と光源を統一する |
| 状態 | SVGまたは256x256レイヤー付き原本 | 96x96 PNG、RGBA | 24px表示でも識別できる単純なシルエット。背景透明、色覚差に依存しない形にする |
| 共通UI | SVG | 必要なら64x64 PNG、RGBA | 2px相当以上の線幅、単色でも識別可能、全13 IDを同じグリッドで作る |
| マップ | SVG | 96x96 PNG、RGBA | 全9種を同じ視点・線幅・余白で作る。ロックは完全透過背景 |
| アプリロゴ | SVG | Godot用SVG、128/180px Web出力 | 16pxでも識別可能。Godotロゴを含めない。単色版も用意する |
| Webスプラッシュ | 1600x1200以上 | 800x600 PNG、RGBA | 16:9画面内で中央表示しても切れない。ゲーム名とロゴの安全域を中央60%にする |
| 3D | Blend | GLB | 共通18ボーン、実寸、適用済みTransform、マテリアル名、LOD方針、ライセンス記録を維持する |

レイヤー付き原本の形式はSVG、Krita、Blenderを優先します。PSDを使う場合も、代替ツールで開ける確認用PNGを併記します。

## 6. 推奨する差し替え順

1. `P0`: `icon.svg`とWebスプラッシュを独自ロゴへ交換します。現在はGodot標準画像がそのまま公開されています。
2. `P1`: ポートレート25枚、遺物86枚、状態4枚を原本と権利記録付きで作り直します。現状は再現可能な制作元がありません。
3. `P2`: 共通UI 13種、マップ9種、CheckButton、CheckBox、Sliderを同一の自作アイコン体系へ統一します。
4. `P3`: カード93枚をシリーズ単位で差し替えます。既存コード生成版は再生成可能なので、移行中の代替として維持できます。
5. `P4`: プロシージャル背景、戦闘フィールド、小物、残り23体分の固有3Dモデルを自作原本へ拡張します。

1回の差し替えは1カテゴリまたは10から20点に限定し、ID一致、画像サイズ、重複、Godot起動、該当画面、Web/PCKを確認してから確定します。

## 7. 制作証跡の保存形式

今後は各素材について、次の情報を`data/art_provenance.json`相当の台帳へ追加することを推奨します。

| 項目 | 内容 |
| --- | --- |
| `asset_id` | データと一致する不変ID |
| `category` | card、relic、portrait、status、ui、map、brand、3d |
| `runtime_path` | ゲームが読む成果物パス |
| `source_path` | SVG、Krita、Blendなどの編集原本 |
| `author` | 制作者名 |
| `created_at` | 制作日 |
| `tool` | Blender、Kritaなど |
| `model_or_service` | 画像生成を使った場合のサービスとモデル |
| `brief_or_prompt_hash` | 制作指示またはプロンプトの保存先・ハッシュ |
| `third_party_inputs` | 写真、ブラシ、フォント、テクスチャなどの出典 |
| `license` | 自作、購入、CC0などの利用条件 |
| `export_sha256` | ゲーム用成果物の検証ハッシュ |
| `replacement_status` | current、planned、in_progress、approved |

第一弾で承認済みのIDは、カード`quick_slash`、`guard`、`delay_step`、`repair_burst`、`auto_turret`、`event_horizon`、遺物`iron_plating`、`auxiliary_core`、`chrono_shard`、`salvage_magnet`、状態`bleed`、UI`attack`、3D`balanced`、`scout`です。詳細は`data/art_provenance.json`、生成統計は各`*.manifest.json`を参照します。

## 8. 全カード画像

全93枚が512x512 RGBAです。レア度内訳はCommon 21、Rare 29、Epic 23、Legendary 20です。

| ID | 日本語名 | レア度 | タグ | パス |
| --- | --- | --- | --- | --- |
| `quick_slash` | クイックスラッシュ | `common` | `attack, fast` | `assets/icons/cards/quick_slash.png` |
| `strike` | ストライク | `common` | `attack` | `assets/icons/cards/strike.png` |
| `guard` | ガード | `common` | `shield` | `assets/icons/cards/guard.png` |
| `heavy_swing` | ヘビースイング | `common` | `attack, heavy` | `assets/icons/cards/heavy_swing.png` |
| `delay_step` | ディレイステップ | `common` | `control, delay` | `assets/icons/cards/delay_step.png` |
| `haste_focus` | ヘイストフォーカス | `common` | `support, haste` | `assets/icons/cards/haste_focus.png` |
| `weak_shot` | ウィークショット | `common` | `attack, debuff` | `assets/icons/cards/weak_shot.png` |
| `bleed_cut` | ブリードカット | `common` | `attack, bleed` | `assets/icons/cards/bleed_cut.png` |
| `quick_guard` | クイックガード | `common` | `shield, fast` | `assets/icons/cards/quick_guard.png` |
| `reload` | リロード | `common` | `support, cooldown` | `assets/icons/cards/reload.png` |
| `assault` | アサルト | `rare` | `attack` | `assets/icons/cards/assault.png` |
| `barrier_deploy` | バリア展開 | `rare` | `shield, buff` | `assets/icons/cards/barrier_deploy.png` |
| `interrupt_shot` | インタラプトショット | `rare` | `control, interrupt` | `assets/icons/cards/interrupt_shot.png` |
| `time_buy` | タイムバイ | `rare` | `control, delay` | `assets/icons/cards/time_buy.png` |
| `recirculate` | リサーキュレート | `rare` | `support, cooldown` | `assets/icons/cards/recirculate.png` |
| `execution` | エグゼキューション | `epic` | `attack, finisher` | `assets/icons/cards/execution.png` |
| `fortify` | フォーティファイ | `epic` | `shield, buff` | `assets/icons/cards/fortify.png` |
| `time_flow_control` | タイムフロー制御 | `epic` | `control, haste, delay` | `assets/icons/cards/time_flow_control.png` |
| `blood_chain` | ブラッドチェイン | `epic` | `attack, bleed` | `assets/icons/cards/blood_chain.png` |
| `over_reload` | オーバーリロード | `epic` | `support, cooldown` | `assets/icons/cards/over_reload.png` |
| `repair_burst` | リペアバースト | `common` | `shield, heal` | `assets/icons/cards/repair_burst.png` |
| `tripwire` | トリップワイヤー | `common` | `attack, control` | `assets/icons/cards/tripwire.png` |
| `stasis_field` | ステイシスフィールド | `rare` | `control, slow, delay` | `assets/icons/cards/stasis_field.png` |
| `rupture_strike` | ラプチャーストライク | `rare` | `attack, bleed` | `assets/icons/cards/rupture_strike.png` |
| `bastion_drive` | バスティオンドライブ | `rare` | `shield, buff` | `assets/icons/cards/bastion_drive.png` |
| `adrenaline_link` | アドレナリンリンク | `rare` | `support, haste, cooldown` | `assets/icons/cards/adrenaline_link.png` |
| `purge_pulse` | パージパルス | `rare` | `support, cleanse, heal` | `assets/icons/cards/purge_pulse.png` |
| `meteor_crash` | メテオクラッシュ | `epic` | `attack, finisher, interrupt` | `assets/icons/cards/meteor_crash.png` |
| `self_tuning_edge` | 自己調整エッジ | `rare` | `attack, buff, special` | `assets/icons/cards/self_tuning_edge.png` |
| `overclock_routine` | オーバークロック手順 | `rare` | `support, buff, special` | `assets/icons/cards/overclock_routine.png` |
| `sequence_loader` | シーケンスローダー | `rare` | `attack, chain, special` | `assets/icons/cards/sequence_loader.png` |
| `recursive_protocol` | 再帰プロトコル | `epic` | `attack, chain, special` | `assets/icons/cards/recursive_protocol.png` |
| `chronostasis` | クロノステイシス | `epic` | `control, time, special` | `assets/icons/cards/chronostasis.png` |
| `entropy_reversal` | エントロピー反転 | `epic` | `control, time, special` | `assets/icons/cards/entropy_reversal.png` |
| `auto_turret` | オートタレット | `rare` | `attack, chain, special` | `assets/icons/cards/auto_turret.png` |
| `crisis_drone_swarm` | クライシスドローンスウォーム | `epic` | `shield, chain, special` | `assets/icons/cards/crisis_drone_swarm.png` |
| `phase_lance` | フェイズランス | `rare` | `attack, debuff, phase` | `assets/icons/cards/phase_lance.png` |
| `mirror_aegis` | ミラーイージス | `rare` | `shield, chain, phase` | `assets/icons/cards/mirror_aegis.png` |
| `null_cascade` | ヌルカスケード | `epic` | `attack, control, phase` | `assets/icons/cards/null_cascade.png` |
| `paradox_loop` | パラドックスループ | `epic` | `attack, chain, special, phase` | `assets/icons/cards/paradox_loop.png` |
| `rift_volley` | リフトボレー | `rare` | `attack, control, rift` | `assets/icons/cards/rift_volley.png` |
| `entropy_armor` | エントロピーアーマー | `rare` | `shield, empower, rift` | `assets/icons/cards/entropy_armor.png` |
| `axiom_sever` | アクシオムセヴァー | `epic` | `attack, interrupt, rift` | `assets/icons/cards/axiom_sever.png` |
| `omega_ray` | オメガレイ | `epic` | `attack, debuff, omega` | `assets/icons/cards/omega_ray.png` |
| `grave_protocol` | グレイヴプロトコル | `epic` | `shield, heal, chain, omega` | `assets/icons/cards/grave_protocol.png` |
| `zero_hour` | ゼロアワー | `epic` | `attack, control, timeline, omega` | `assets/icons/cards/zero_hour.png` |
| `aegis_ram` | イージスラム | `common` | `attack, shield, shield_spend` | `assets/icons/cards/aegis_ram.png` |
| `barrier_overdrive` | バリアオーバードライブ | `rare` | `shield, shield_spend, haste, cooldown` | `assets/icons/cards/barrier_overdrive.png` |
| `bulwark_cannon` | ブルワークキャノン | `epic` | `attack, shield, shield_spend, interrupt, finisher` | `assets/icons/cards/bulwark_cannon.png` |
| `spark_jab` | スパークジャブ | `common` | `attack, fast, cooldown` | `assets/icons/cards/spark_jab.png` |
| `brace_patch` | ブレイスパッチ | `common` | `shield, heal, fast` | `assets/icons/cards/brace_patch.png` |
| `marking_dart` | マーキングダート | `common` | `attack, debuff, fast` | `assets/icons/cards/marking_dart.png` |
| `timer_hook` | タイマーフック | `common` | `control, delay, haste` | `assets/icons/cards/timer_hook.png` |
| `blood_siphon` | ブラッドサイフォン | `common` | `attack, heal, bleed` | `assets/icons/cards/blood_siphon.png` |
| `capacitor_step` | キャパシタステップ | `common` | `shield, haste, support` | `assets/icons/cards/capacitor_step.png` |
| `grit_reload` | グリットリロード | `common` | `cooldown, shield, support` | `assets/icons/cards/grit_reload.png` |
| `rust_cloud` | ラストクラウド | `common` | `debuff, slow, control` | `assets/icons/cards/rust_cloud.png` |
| `hammer_feint` | ハンマーフェイント | `rare` | `attack, control, delay` | `assets/icons/cards/hammer_feint.png` |
| `prism_guard` | プリズムガード | `rare` | `shield, cleanse, support` | `assets/icons/cards/prism_guard.png` |
| `rupture_mark` | ラプチャーマーク | `rare` | `debuff, bleed, attack` | `assets/icons/cards/rupture_mark.png` |
| `phase_zip` | フェイズジップ | `rare` | `haste, cooldown, time` | `assets/icons/cards/phase_zip.png` |
| `recycler_claw` | リサイクラークロー | `rare` | `attack, cooldown` | `assets/icons/cards/recycler_claw.png` |
| `reactor_leech` | リアクターリーチ | `rare` | `shield_spend, attack, heal` | `assets/icons/cards/reactor_leech.png` |
| `drone_foundry` | ドローン鋳造所 | `rare` | `chain, support, shield` | `assets/icons/cards/drone_foundry.png` |
| `tactical_mirror` | タクティカルミラー | `rare` | `chain, special, cooldown` | `assets/icons/cards/tactical_mirror.png` |
| `gravity_snare` | グラビティスネア | `rare` | `control, time, delay` | `assets/icons/cards/gravity_snare.png` |
| `field_medic` | フィールドメディック | `rare` | `heal, cleanse, support` | `assets/icons/cards/field_medic.png` |
| `singularity_guard` | シンギュラリティガード | `epic` | `shield, time, control` | `assets/icons/cards/singularity_guard.png` |
| `blood_moon_protocol` | ブラッドムーンプロトコル | `epic` | `attack, bleed, debuff` | `assets/icons/cards/blood_moon_protocol.png` |
| `chrono_blackout` | クロノブラックアウト | `epic` | `time, control, special` | `assets/icons/cards/chrono_blackout.png` |
| `recursive_battery` | 再帰バッテリー | `epic` | `shield, chain, special` | `assets/icons/cards/recursive_battery.png` |
| `execution_matrix` | エグゼキューションマトリクス | `epic` | `attack, finisher, interrupt` | `assets/icons/cards/execution_matrix.png` |
| `final_archive` | ファイナルアーカイブ | `epic` | `special, buff, chain, shield` | `assets/icons/cards/final_archive.png` |
| `solar_verdict` | ソーラーヴァーディクト | `legendary` | `attack, finisher, debuff` | `assets/icons/cards/solar_verdict.png` |
| `citadel_prime` | シタデルプライム | `legendary` | `shield, heal, cleanse` | `assets/icons/cards/citadel_prime.png` |
| `epoch_breaker` | エポックブレイカー | `legendary` | `attack, control, delay, interrupt` | `assets/icons/cards/epoch_breaker.png` |
| `phoenix_circuit` | フェニックスサーキット | `legendary` | `heal, cleanse, growth, support` | `assets/icons/cards/phoenix_circuit.png` |
| `atlas_protocol` | アトラスプロトコル | `legendary` | `support, growth, shield, cooldown` | `assets/icons/cards/atlas_protocol.png` |
| `worldline_collapse` | ワールドラインコラプス | `legendary` | `special, control, reverse, attack, delay` | `assets/icons/cards/worldline_collapse.png` |
| `seraph_array` | セラフアレイ | `legendary` | `shield, chain, haste, support` | `assets/icons/cards/seraph_array.png` |
| `ragnarok_engine` | ラグナロクエンジン | `legendary` | `attack, chain, growth, finisher` | `assets/icons/cards/ragnarok_engine.png` |
| `absolute_zero` | アブソリュートゼロ | `legendary` | `control, stop, debuff, delay` | `assets/icons/cards/absolute_zero.png` |
| `quantum_exchange` | クォンタムエクスチェンジ | `legendary` | `shield_spend, attack, heal, cooldown` | `assets/icons/cards/quantum_exchange.png` |
| `crown_of_thorns` | クラウンオブソーンズ | `legendary` | `shield, attack, bleed, status` | `assets/icons/cards/crown_of_thorns.png` |
| `infinity_arsenal` | インフィニティアーセナル | `legendary` | `chain, attack, shield, growth` | `assets/icons/cards/infinity_arsenal.png` |
| `omega_sanctuary` | オメガサンクチュアリ | `legendary` | `heal, shield, cleanse, stop` | `assets/icons/cards/omega_sanctuary.png` |
| `event_horizon` | イベントホライズン | `legendary` | `attack, control, delay, debuff` | `assets/icons/cards/event_horizon.png` |
| `deus_ex_machina` | デウスエクスマキナ | `legendary` | `heal, cleanse, cooldown, chain` | `assets/icons/cards/deus_ex_machina.png` |
| `golden_ratio` | ゴールデンレシオ | `legendary` | `attack, growth, fast, special` | `assets/icons/cards/golden_ratio.png` |
| `tempest_choir` | テンペストクワイア | `legendary` | `chain, attack, debuff, haste` | `assets/icons/cards/tempest_choir.png` |
| `last_bastion` | ラストバスティオン | `legendary` | `shield_spend, shield, attack, interrupt` | `assets/icons/cards/last_bastion.png` |
| `dominion_pulse` | ドミニオンパルス | `legendary` | `buff, debuff, support, shield` | `assets/icons/cards/dominion_pulse.png` |
| `chronicle_sovereign` | クロニクルソヴリン | `legendary` | `special, growth, cooldown, chain, support` | `assets/icons/cards/chronicle_sovereign.png` |

## 9. 全遺物画像

全86枚が512x512 RGBAです。

| ID | 日本語名 | パス |
| --- | --- | --- |
| `iron_plating` | 鉄装甲 | `assets/icons/relics/iron_plating.png` |
| `tempered_edge` | 焼入れ刃 | `assets/icons/relics/tempered_edge.png` |
| `kinetic_boots` | キネティックブーツ | `assets/icons/relics/kinetic_boots.png` |
| `auxiliary_core` | 補助コア | `assets/icons/relics/auxiliary_core.png` |
| `reactive_barrier` | 反応障壁 | `assets/icons/relics/reactive_barrier.png` |
| `chrono_shard` | クロノシャード | `assets/icons/relics/chrono_shard.png` |
| `salvage_magnet` | サルベージマグネット | `assets/icons/relics/salvage_magnet.png` |
| `repair_nanites` | リペアナノマシン | `assets/icons/relics/repair_nanites.png` |
| `war_banner` | 戦旗 | `assets/icons/relics/war_banner.png` |
| `aegis_matrix` | イージスマトリクス | `assets/icons/relics/aegis_matrix.png` |
| `surge_gimbal` | サージジンバル | `assets/icons/relics/surge_gimbal.png` |
| `phase_capacitor` | フェイズキャパシタ | `assets/icons/relics/phase_capacitor.png` |
| `echo_coil` | エコーコイル | `assets/icons/relics/echo_coil.png` |
| `paradox_prism` | パラドックスプリズム | `assets/icons/relics/paradox_prism.png` |
| `rift_compass` | リフトコンパス | `assets/icons/relics/rift_compass.png` |
| `entropy_battery` | エントロピーバッテリー | `assets/icons/relics/entropy_battery.png` |
| `omega_crown` | オメガクラウン | `assets/icons/relics/omega_crown.png` |
| `eternity_engine` | エタニティエンジン | `assets/icons/relics/eternity_engine.png` |
| `titanium_rib` | チタンリブ | `assets/icons/relics/titanium_rib.png` |
| `loadout_harness` | ロードアウトハーネス | `assets/icons/relics/loadout_harness.png` |
| `war_cache` | ウォーキャッシュ | `assets/icons/relics/war_cache.png` |
| `signal_lens` | シグナルレンズ | `assets/icons/relics/signal_lens.png` |
| `pulse_injector` | パルスインジェクター | `assets/icons/relics/pulse_injector.png` |
| `barrier_seed` | バリアシード | `assets/icons/relics/barrier_seed.png` |
| `stasis_clock` | ステイシスクロック | `assets/icons/relics/stasis_clock.png` |
| `blood_pump` | ブラッドポンプ | `assets/icons/relics/blood_pump.png` |
| `scavenger_contract` | スカベンジャー契約 | `assets/icons/relics/scavenger_contract.png` |
| `emergency_foam` | 緊急フォーム | `assets/icons/relics/emergency_foam.png` |
| `overclock_key` | オーバークロックキー | `assets/icons/relics/overclock_key.png` |
| `chrono_metronome` | クロノメトロノーム | `assets/icons/relics/chrono_metronome.png` |
| `armor_garden` | アーマーガーデン | `assets/icons/relics/armor_garden.png` |
| `bounty_drone` | バウンティドローン | `assets/icons/relics/bounty_drone.png` |
| `prism_furnace` | プリズムファーネス | `assets/icons/relics/prism_furnace.png` |
| `archive_compass` | アーカイブコンパス | `assets/icons/relics/archive_compass.png` |
| `triplet_relay` | 三拍子リレー | `assets/icons/relics/triplet_relay.png` |
| `borrowed_second_hand` | 借用秒針 | `assets/icons/relics/borrowed_second_hand.png` |
| `terminal_echo_ring` | 終端残響環 | `assets/icons/relics/terminal_echo_ring.png` |
| `four_name_quartet` | 異名四連符 | `assets/icons/relics/four_name_quartet.png` |
| `dead_heat_needle` | 同着偏針 | `assets/icons/relics/dead_heat_needle.png` |
| `silent_three_second_timer` | 無音の三秒計 | `assets/icons/relics/silent_three_second_timer.png` |
| `delay_return_gear` | 遅延返し歯 | `assets/icons/relics/delay_return_gear.png` |
| `zero_hour_clapper` | 零時拍子木 | `assets/icons/relics/zero_hour_clapper.png` |
| `terminal_bell` | 終端ベル | `assets/icons/relics/terminal_bell.png` |
| `paradox_mortgage` | パラドックス抵当証 | `assets/icons/relics/paradox_mortgage.png` |
| `overtake_signal` | 追越信号器 | `assets/icons/relics/overtake_signal.png` |
| `reversal_turbine` | 反転タービン | `assets/icons/relics/reversal_turbine.png` |
| `full_slot_bell` | 満員ベル | `assets/icons/relics/full_slot_bell.png` |
| `vacancy_interest_meter` | 空席利息計 | `assets/icons/relics/vacancy_interest_meter.png` |
| `fourth_reserve_rack` | 第四の予備架 | `assets/icons/relics/fourth_reserve_rack.png` |
| `single_seat_duel_sheath` | 単座決闘鞘 | `assets/icons/relics/single_seat_duel_sheath.png` |
| `reserved_seat_tag` | 予約席タグ | `assets/icons/relics/reserved_seat_tag.png` |
| `echo_rectifier` | 反響整流器 | `assets/icons/relics/echo_rectifier.png` |
| `waste_heat_printer` | 廃熱プリンター | `assets/icons/relics/waste_heat_printer.png` |
| `isolation_chamber` | 隔離チャンバー | `assets/icons/relics/isolation_chamber.png` |
| `resin_memory_block` | 樹脂記憶塊 | `assets/icons/relics/resin_memory_block.png` |
| `full_absorption_gauge` | 全吸収検針器 | `assets/icons/relics/full_absorption_gauge.png` |
| `evaporation_recovery_valve` | 蒸発回収弁 | `assets/icons/relics/evaporation_recovery_valve.png` |
| `residual_pressure_detonator` | 残圧起爆栓 | `assets/icons/relics/residual_pressure_detonator.png` |
| `rupture_insurance_film` | 破断保険膜 | `assets/icons/relics/rupture_insurance_film.png` |
| `compression_caliper` | 圧縮キャリパー | `assets/icons/relics/compression_caliper.png` |
| `twilight_pacemaker` | 薄明ペースメーカー | `assets/icons/relics/twilight_pacemaker.png` |
| `bleed_pulsator` | 出血拍動子 | `assets/icons/relics/bleed_pulsator.png` |
| `slow_charge_accumulator` | 鈍化蓄勢子 | `assets/icons/relics/slow_charge_accumulator.png` |
| `four_symptom_seal` | 四症候封印 | `assets/icons/relics/four_symptom_seal.png` |
| `quarantine_buffer` | 防疫バッファ | `assets/icons/relics/quarantine_buffer.png` |
| `symptom_transfer_paper` | 症候転写紙 | `assets/icons/relics/symptom_transfer_paper.png` |
| `critical_pathology_meter` | 臨界病理計 | `assets/icons/relics/critical_pathology_meter.png` |
| `grade_staircase` | 等級階段器 | `assets/icons/relics/grade_staircase.png` |
| `unpolished_motherboard` | 未研磨母板 | `assets/icons/relics/unpolished_motherboard.png` |
| `overload_seal` | 過積載封印 | `assets/icons/relics/overload_seal.png` |
| `empty_rack_bus` | 空架式バス | `assets/icons/relics/empty_rack_bus.png` |
| `full_load_latch` | 満載ラッチ | `assets/icons/relics/full_load_latch.png` |
| `weight_ticket_punch` | 重量検札機 | `assets/icons/relics/weight_ticket_punch.png` |
| `grade_differential_wheel` | 等級差動輪 | `assets/icons/relics/grade_differential_wheel.png` |
| `solar_pinion` | 日輪ピニオン | `assets/icons/relics/solar_pinion.png` |
| `overcharge_confection_furnace` | 過給菓子炉 | `assets/icons/relics/overcharge_confection_furnace.png` |
| `polarization_converter` | 偏光変換器 | `assets/icons/relics/polarization_converter.png` |
| `balanced_three_phase_unit` | 平衡三相器 | `assets/icons/relics/balanced_three_phase_unit.png` |
| `memorial_fund_coil` | 記念基金コイル | `assets/icons/relics/memorial_fund_coil.png` |
| `seven_step_validator` | 七段検印機 | `assets/icons/relics/seven_step_validator.png` |
| `depth_pressure_gauge` | 深度圧力計 | `assets/icons/relics/depth_pressure_gauge.png` |
| `emergency_recovery_line` | 緊急回収索 | `assets/icons/relics/emergency_recovery_line.png` |
| `carryover_price_tag` | 持越し値札 | `assets/icons/relics/carryover_price_tag.png` |
| `defeat_wiring` | 敗北配線器 | `assets/icons/relics/defeat_wiring.png` |
| `overtime_key` | 延長戦鍵 | `assets/icons/relics/overtime_key.png` |
| `loop_wear_wheel` | 周回摩耗輪 | `assets/icons/relics/loop_wear_wheel.png` |

## 10. 全ポートレート

| ID | 区分 | 日本語名 | 現在のサイズ | パス |
| --- | --- | --- | --- | --- |
| `balanced` | スターター | バランスフレーム | 1254x1254 | `assets/portraits/balanced.png` |
| `tempo` | スターター | テンポフレーム | 1254x1254 | `assets/portraits/tempo.png` |
| `fortress` | スターター | フォートレスフレーム | 1254x1254 | `assets/portraits/fortress.png` |
| `vanguard` | スターター | ヴァンガードフレーム | 1024x1024 | `assets/portraits/vanguard.png` |
| `aegis` | スターター | イージスフレーム | 1024x1024 | `assets/portraits/aegis.png` |
| `chrono` | スターター | クロノフレーム | 1024x1024 | `assets/portraits/chrono.png` |
| `turret` | スターター | タレットフレーム | 1024x1024 | `assets/portraits/turret.png` |
| `scout` | 敵 | スカウト | 1254x1254 | `assets/portraits/scout.png` |
| `brute` | 敵 | ブルート | 1254x1254 | `assets/portraits/brute.png` |
| `disruptor` | 敵 | ディスラプター | 1254x1254 | `assets/portraits/disruptor.png` |
| `guardian` | 敵 | ガーディアン | 1254x1254 | `assets/portraits/guardian.png` |
| `raider` | 敵 | レイダー | 1254x1254 | `assets/portraits/raider.png` |
| `medic_drone` | 敵 | メディックドローン | 1254x1254 | `assets/portraits/medic_drone.png` |
| `chronoguard` | 敵 | クロノガード | 1254x1254 | `assets/portraits/chronoguard.png` |
| `boss_timekeeper` | ボス | タイムキーパー | 1254x1254 | `assets/portraits/boss_timekeeper.png` |
| `phase_stalker` | 敵 | フェイズストーカー | 1254x1254 | `assets/portraits/phase_stalker.png` |
| `void_bastion` | 敵 | ヴォイドバスティオン | 1254x1254 | `assets/portraits/void_bastion.png` |
| `echo_revenant` | 敵 | エコーレヴナント | 1254x1254 | `assets/portraits/echo_revenant.png` |
| `boss_paradox_core` | ボス | パラドックス・コア | 1254x1254 | `assets/portraits/boss_paradox_core.png` |
| `rift_predator` | 敵 | リフトプレデター | 1254x1254 | `assets/portraits/rift_predator.png` |
| `entropy_colossus` | 敵 | エントロピーコロッサス | 1254x1254 | `assets/portraits/entropy_colossus.png` |
| `boss_axiom_breaker` | ボス | アクシオムブレイカー | 1254x1254 | `assets/portraits/boss_axiom_breaker.png` |
| `omega_seraph` | 敵 | オメガセラフ | 1254x1254 | `assets/portraits/omega_seraph.png` |
| `grave_architect` | 敵 | グレイヴアーキテクト | 1254x1254 | `assets/portraits/grave_architect.png` |
| `boss_eternity_zero` | ボス | エタニティ・ゼロ | 1254x1254 | `assets/portraits/boss_eternity_zero.png` |

## 11. 状態、ブランド、Web、開発用画像

### 11.1 状態アイコン

| ID | 日本語名 | サイズ | パス |
| --- | --- | --- | --- |
| `bleed` | 出血 | 96x96 RGBA | `assets/icons/status/bleed.png` |
| `slow` | 鈍化 | 96x96 RGBA | `assets/icons/status/slow.png` |
| `vulnerable` | 脆弱 | 96x96 RGBA | `assets/icons/status/vulnerable.png` |
| `weak` | 弱体 | 96x96 RGBA | `assets/icons/status/weak.png` |

### 11.2 ブランドとWeb出力

| ファイル | サイズ | 用途 | 自前化時の扱い |
| --- | --- | --- | --- |
| `icon.svg` | 128x128相当 | アプリの原本アイコン | 現在はGodot標準ロゴ。独自SVGへ交換 |
| `build/web/index.icon.png` | 128x128 | favicon | Web再出力で自動生成 |
| `build/web/index.apple-touch-icon.png` | 180x180 | iOSホーム画面 | Web再出力で自動生成 |
| `build/web/index.png` | 800x600 | Web起動スプラッシュ | 現在は「GODOT Game engine」標準画像。独自スプラッシュへ交換 |

### 11.3 3Dと開発専用

| ファイル | 用途 | ランタイム |
| --- | --- | --- |
| `assets/models/battle/balanced.glb` | バランスフレーム固有モデル | 使用 |
| `assets/models/battle/scout.glb` | スカウト固有モデル | 使用 |
| `assets/models/battle/battle_animation_library.glb` | 共有18ボーン・18クリップのアニメーション供給 | 使用 |
| `art_src/blender/battle_vertical_slice.blend` | バランス、スカウト、戦闘縦切り制作原本 | 不使用、制作原本 |
| `art_src/blender/art_vertical_slice.blend` | カード6、遺物4、状態1、UI1の制作原本 | 不使用、制作原本 |
| `art_src/blender/battle_animation_library.blend` | 共有アニメーション制作原本 | 不使用、制作原本 |
| `art_src/blender/previews/battle_vertical_slice.png` | 3D検証用レンダー、1200x760 | 不使用、開発用 |
| `art_src/blender/previews/art_vertical_slice_*.png` | カード、遺物、小型アイコンの縮小コンタクトシート | 不使用、開発用 |
| `art_src/blender/*.manifest.json` | Blender版、生成元、形状統計、SHA-256 | 不使用、制作証跡 |
| `addons/gd-eos/doc/logo.png` | GD-EOSプラグイン文書ロゴ、221x256 | 不使用、Web出力から除外 |

`art_src/blender/battle_animation_library.blend1`はローカルのBlenderバックアップで、`.gitignore`対象です。正式な原本には数えず、必要な変更は`.blend`へ保存します。

## 12. 更新チェックリスト

新しいカード、遺物、スターター、敵、状態、UIアイコンを追加したときは、次を同じコミットで確認します。

- データIDとファイル名が完全一致している。
- 正方形、カラーモード、透過、推奨サイズを満たしている。
- 同一ハッシュや誤った使い回しがない。
- 日本語名と英語名がローカライズデータにある。
- 編集原本と制作証跡が保存されている。
- ネイティブ起動、対象画面、Web/PCKで欠損フォールバックが出ない。
- Web成果物を直接修正せず、原本から再出力している。
- この台帳の件数と一覧を更新している。
