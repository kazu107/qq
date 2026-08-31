# Blender高精細3D自前化 制作計画

策定日: 2026-09-01

対象台帳: `docs/ART_ASSET_INVENTORY.md`

対象Blender: 5.2.1 LTS

この文書は、現在ゲームで使われている視覚資産をBlender製の自前素材へ置き換えるための制作順、共通部品、派生関係、出力規格、検証ゲートを定義します。現在の画像は構図と意味を読み取るための参考とし、そのまま立体化したり、画像をテクスチャとして貼り直したりはしません。

## 1. 監査結果と基本方針

| 区分 | 監査数 | 現状 | Blender化の方針 |
| --- | ---: | --- | --- |
| カード | 93 | 512px画像のみ。装置ジオラマ風だが編集原本なし | 共通ジオラマ13種へ部品を追加し、2048px静止画から512pxへ縮小 |
| 遺物 | 86 | 真鍮機械と台座で比較的統一。編集原本なし | 台座1式と機構キット11種を共有し、固有のトップパーツだけ作る |
| キャラクター | 25 | ポートレートのみ。ゲーム内固有GLBは2体 | 共通18ボーンと交換装備を維持し、6基本体型と派生体型から25体を組み立てる |
| 状態 | 4 | 平面アイコン | 同じ外周リングを使う立体メダリオン4種にする |
| 共通UI | 13基本IDとカード効果ID | GDScriptで矩形・円を生成 | Blenderの立体ピクトグラムを正投影レンダーし、小サイズ用に単純化 |
| マップ | 9 | GDScriptで生成 | 同じ台座、視点、線幅相当でミニチュア9種を作る |
| UI操作部品 | スイッチ、チェック、スライダー | GDScriptで生成 | 同じ機械パネルから各状態をレンダーしてアトラス化 |
| ブランド・Web | 4 | Godot標準ロゴと標準スプラッシュ | Blender原本の独自エンブレムと起動ジオラマへ交換 |
| 戦闘3D | キャラ2、共有アニメーション1 | 低ポリ縦切りと18クリップ | 高精細原本を保持し、Web向け軽量GLBへベイク |
| 背景・戦闘フィールド | コード生成 | 基本メッシュとCanvas描画 | モジュール式フィールドと背景レンダーへ段階移行 |

最終アート方向は「工業的なクロノ・ファンタジー」とします。黒鉄、青みのある鋼、古い真鍮、白いセラミック、革、ガラス、液体、控えめなシアン・琥珀・赤の発光を共通語彙にします。カードは意味が一目で分かる実験装置ジオラマ、遺物は博物館展示物、人物は同じ世界の装甲・機械兵として統一します。

## 2. 高精細原本とゲーム用成果物を分離する

| 用途 | Blender原本 | ゲームへ入れる成果物 | 容量方針 |
| --- | --- | --- | --- |
| カード・遺物・状態・UI・マップ | 高精細メッシュ、Geometry Nodes、Cycles用材質 | PNGのみ | 高精細メッシュは`art_src/.gdignore`内に置き、PCKへ入れない |
| ポートレート | 戦闘用キャラの高精細原本と専用照明 | 1024px PNG | 戦闘モデルと同じ顔・装備を使い、別デザインを作らない |
| 戦闘キャラ | Sculpt/高精細ハードサーフェス、ベイク元 | 共有部品GLB、軽量ボディGLB、1Kから2Kテクスチャ | 通常18kから35k三角、ボス45kから70k三角を目安にする |
| 戦闘フィールド | 高精細環境原本 | 低中ポリGLB、共有マテリアル | MultiMesh化できる草、岩、小物は個別複製しない |
| Webスプラッシュ | 高精細シーン | 800x600 PNG | Blender原本のみ高精細に保つ |

カードや遺物を「3Dで作る」場合も、ゲーム中に3Dモデルを読み込む必要はありません。Blenderで高精細に制作・照明・レンダーし、ゲームには現在と同じ512x512画像だけを入れます。これによりPCK容量とWeb読み込み時間をほぼ増やさずに品質を上げられます。

## 3. 制作原本の構成

| 原本 | 役割 |
| --- | --- |
| `art_src/blender/library/qq_materials.blend` | 黒鉄、鋼、真鍮、白セラミック、革、布、ガラス、液体、発光のマスター材質 |
| `art_src/blender/library/qq_mechanical_parts.blend` | ボルト、歯車、パイプ、ケーブル、コイル、ゲージ、バルブ、レール、台座 |
| `art_src/blender/library/qq_character_parts.blend` | 6基本体型、派生Shape Key、10武器、5実体オフハンド、8頭部、7背面装備 |
| `art_src/blender/library/qq_medical_parts.blend` | 注射器、ポンプ、カプセル、ナノマシン容器、人工肋骨、補修アーム |
| `art_src/blender/library/qq_chrono_parts.blend` | 時計、針、目盛り、振り子、時間レール、停止ゲート、逆転ギア |
| `art_src/blender/library/qq_energy_parts.blend` | バッテリー、リアクター、シールド発生器、プリズム、オーブ、電極 |
| `art_src/blender/library/qq_render_rigs.blend` | カード、遺物、ポートレート、UI用の固定カメラと照明 |
| `art_src/blender/characters/qq_characters.blend` | 25体をリンク部品で組み立てるコレクション群 |
| `art_src/blender/cards/card_dioramas_*.blend` | 13基礎シーンと93カードの派生コレクション |
| `art_src/blender/relics/relic_sets_*.blend` | 11機構キットと86遺物の派生コレクション |
| `art_src/blender/ui/qq_ui_icons.blend` | 状態、共通UI、カード効果、マップ、操作部品、ブランド |
| `art_src/blender/environment/qq_battlefield.blend` | 戦闘床、草、岩、花、柱、樽、背景構造物 |

各完成物を別ファイルへ複製せず、Blender Asset BrowserのリンクコレクションとLibrary Overrideを使います。変更が全派生へ反映される部品と、各ID固有の部品を分けます。

## 4. 既存3Dから引き継ぐ規格

現在の`battle_vertical_slice.blend`はBalancedとScout、85オブジェクト、79メッシュ、35材質、4,102頂点、4,322ポリゴンです。高精細化の際はデザイン確認用の基準として残し、完成版へ直接継ぎ足し続けるのではなく、共通部品ライブラリへ分解して再構築します。基本体型は`BODY_LIGHT`、`BODY_MEDIUM`、`BODY_HEAVY`、`BODY_ARCANE`、`BODY_MECH`、`BODY_BOSS`の6種とし、表中の`HEAVY`、`TALL`、`BEAST`、`DRONE`等は同じ基本体型のShape Key、プロポーション、外装差分です。

現在の`battle_animation_library.blend`は次の18ボーンと18アニメーションを持つため、この命名と階層を変更しません。

`root`, `hips`, `spine`, `chest`, `neck`, `head`, `left_upper_arm`, `left_forearm`, `left_hand`, `right_upper_arm`, `right_forearm`, `right_hand`, `left_upper_leg`, `left_lower_leg`, `left_foot`, `right_upper_leg`, `right_lower_leg`, `right_foot`

`attack_arcane`, `attack_heavy`, `attack_melee`, `attack_ranged`, `block`, `cast`, `defeat`, `heal`, `hit`, `idle`, `interrupt`, `ready_arcane`, `ready_guard`, `ready_melee`, `ready_ranged`, `shield`, `status`, `victory`

交換部品は現在の分類をそのまま高精細化します。

| 種別 | 共有部品 |
| --- | --- |
| 武器 | `blade`, `rapier`, `greatsword`, `hammer`, `staff`, `blaster`, `cannon`, `claws`, `scythe`, `spear` |
| オフハンド | `shield`, `tower_shield`, `buckler`, `orb`, `blade` |
| 頭部 | `visor`, `fin`, `crest`, `horns`, `halo`, `fortress`, `antenna`, `crown` |
| 背面 | `power_pack`, `thrusters`, `reactor`, `ammo_pack`, `chrono_ring`, `spikes`, `wings` |

武器、オフハンド、頭部、背面をキャラクターごとに作り直しません。各キャラクターでは共有部品へ紋章、損傷、補助装甲、色、発光形状を追加します。

## 5. 制作順とゲート

| 段階 | 制作内容 | 完了条件 |
| --- | --- | --- |
| 0 | 命名、フォルダ、マスター材質、単位、原点、カメラ、照明、出力スクリプト | 空シーンから同じ画像を再生成できる |
| 1 | 共通機械部品、台座、10武器、5オフハンド、8頭部、7背面、6体型 | 部品一覧レンダーとソケット検証が通る |
| 2 | 縦切りとしてBalanced、Scout、カード6枚、遺物6個、状態1個、UI1個を完成 | Godot実機とWebで画質、視認性、容量を承認できる |
| 3 | 7スターターと18敵・ボス、同一モデルから25ポートレート | 18クリップ、全ソケット、全プロフィール、全ポートレートが通る |
| 4 | 遺物11キットから86個 | 48pxで識別、ID重複なし、全ツールチップで表示 |
| 5 | カード13ジオラマから93枚 | 74pxから168pxで主効果を判別、カード名やUI文字は画像へ焼かない |
| 6 | 状態4、共通UI、カード効果、マップ9、操作部品 | 24pxから96pxの全サイズでシルエットが崩れない |
| 7 | 戦闘フィールド、全画面背景、結果背景、独自ロゴ、Webスプラッシュ | 16:9、16:10、4:3とWebで切れない |
| 8 | 全置換、キャッシュ、PCK、権利台帳、退行テスト | 旧画像を参照する通常経路が0件、全31段階検証とWeb検証が成功 |

一度に全179個のカード・遺物を作り切らず、1バッチ10から16個でレンダー、Godot確認、修正、承認を行います。未承認の見た目を大量展開しません。

## 6. キャラクター25体の派生計画

| ID | 体型の元 | 共有部品 | 固有追加 |
| --- | --- | --- | --- |
| `balanced` | `BODY_MEDIUM`、既存モデルを再設計 | blade、shield、visor、power_pack | 青白セラミック胸甲、菱形コア、標準品質基準 |
| `tempo` | `BODY_LIGHT`、Scout脚部を再利用 | rapier、buckler、fin、thrusters | 流線型脚甲、軽い肩、ライムの速度灯 |
| `fortress` | `BODY_HEAVY` | hammer、tower_shield、fortress、reactor | 厚い胸郭、城壁状肩甲、広い足 |
| `vanguard` | `BODY_MEDIUM` | greatsword、horns、thrusters | 赤い突撃装甲、前傾胸甲、片肩大型装甲 |
| `aegis` | `BODY_HEAVY` | hammer、tower_shield、crest、reactor | 金色縁、丸い防壁装甲、シールド導管 |
| `chrono` | `BODY_ARCANE` | staff、orb、halo、chrono_ring | 紫の細身外套装甲、浮遊リング、時計文字盤 |
| `turret` | `BODY_MECH` | blaster、buckler、antenna、ammo_pack | 黄黒整備装甲、弾倉、腰部工具、展開式小砲 |
| `scout` | `BODY_LIGHT`、既存モデルを再設計 | rapier、offhand blade、fin、thrusters | フード、マスク、スカーフ、矢筒、非対称肩甲 |
| `brute` | `BODY_HEAVY` | hammer、horns、power_pack | 露出した太い腕、溶接装甲、赤茶の損傷面 |
| `disruptor` | `BODY_ARCANE` | staff、orb、antenna、reactor | 非対称コイル、妨害波アンテナ、紫黄発光 |
| `guardian` | `BODY_HEAVY` | cannon、tower_shield、fortress、reactor | 軍用角形装甲、シールド配電盤、砲身支持腕 |
| `raider` | `BODY_MEDIUM`、Vanguardを派生 | greatsword、offhand blade、horns、thrusters | 傷ついた赤装甲、布巻き、略奪品ベルト |
| `medic_drone` | `BODY_DRONE` | blaster、orb、halo、power_pack | 人型骨格へ追従する浮遊医療胴、3本補修アーム |
| `chronoguard` | `BODY_ARCANE_HEAVY` | staff、shield、halo、chrono_ring | 時計騎士兜、リング状肩甲、盾の目盛り |
| `boss_timekeeper` | `BODY_BOSS_ARCANE` | staff、orb、crown、chrono_ring | 多重時計輪、長い外套板、巨大振り子コア |
| `phase_stalker` | `BODY_LIGHT` | claws、horns、thrusters | 黒い分割装甲、位相の隙間、細長い鉤爪 |
| `void_bastion` | `BODY_HEAVY`、Guardianを派生 | cannon、tower_shield、fortress、reactor | 紫黒の一体化防壁、空洞コア、発光亀裂 |
| `echo_revenant` | `BODY_ARCANE` | scythe、orb、horns、spikes | 破損外套板、反響リング、骨格風胸部 |
| `boss_paradox_core` | `BODY_BOSS_ARCANE` | staff、orb、crown、wings | 胸部パラドックス球、非対称翼、多重腕の錯視部品 |
| `rift_predator` | `BODY_LIGHT_BEAST`、Phase Stalkerを派生 | claws、offhand blade、horns、spikes | 前傾脚、捕食者の頭部、裂けた位相膜 |
| `entropy_colossus` | `BODY_HEAVY` | hammer、tower_shield、fortress、reactor | 岩塊状の厚い装甲、熱変色、崩落する外板 |
| `boss_axiom_breaker` | `BODY_BOSS_HEAVY` | greatsword、orb、crown、wings | 白金の断罪装甲、巨大剣レール、幾何学翼 |
| `omega_seraph` | `BODY_ARCANE` | spear、orb、halo、wings | 白いセラミック、金の関節、6枚の機械翼 |
| `grave_architect` | `BODY_ARCANE_TALL` | scythe、orb、antenna、spikes | 建築物状肩、墓標パネル、設計投影器 |
| `boss_eternity_zero` | `BODY_BOSS_ARCANE` | scythe、orb、crown、wings | 黒白の虚無装甲、停止した多重輪、長い刃翼 |

ポートレート25枚は上記モデルの専用カメラレンダーです。ゲーム内3Dとポートレートで顔、兜、武器、色を別々に作りません。

## 7. 遺物86個の共通キットと追加部品

### R01 装甲・武具展示キット

- `iron_plating`: 重装胸甲と留め具を展示台へ追加。
- `tempered_edge`: blade共有部品を短く再構成し、焼き入れ色を追加。
- `kinetic_boots`: BODY_LIGHTの足甲と小型推進器を左右一組で展示。
- `war_banner`: 共通支柱へ破れ布、金属紋章、床固定具を追加。
- `omega_crown`: crown共有部品へ黒金の多重棘と赤い中心石を追加。
- `titanium_rib`: 胸部リブ部品を切り出し、青い補強帯を追加。

### R02 コア・バッテリー・熱機関キット

- `auxiliary_core`: 八角コア、外周リング、青い中心セル。
- `reactive_barrier`: shield発生器を小型化し、開閉花弁を追加。
- `aegis_matrix`: shieldの六角層と回転する中央ディスク。
- `phase_capacitor`: 円筒セル、絶縁帯、位相窓。
- `echo_coil`: 銅線コイル、反響ベル、磁気ヨーク。
- `entropy_battery`: 透明円筒、橙色液体、冷却管。
- `eternity_engine`: chrono_ringとリアクターを同軸接続。
- `barrier_seed`: 小型シールド核を花弁状ケースへ収める。
- `overclock_key`: 共通キー軸へ発光アンプルと歯車歯を追加。
- `prism_furnace`: 炉体へプリズム窓、攻撃・盾・時間の3導管を追加。
- `echo_rectifier`: echo_coilへ真空管、整流器、青い電弧を追加。
- `waste_heat_printer`: 炉体へ紙送りローラー、熱セル、排気管を追加。
- `resin_memory_block`: 透明樹脂キューブ内へ積層回路を封入。

### R03 時計・タイムライン機構キット

- `chrono_shard`: 破片状水晶、半円時計枠、巻き上げ軸。
- `paradox_prism`: プリズムへ交差する時間リングを追加。
- `stasis_clock`: 球面時計、停止針、固定クランプ。
- `chrono_metronome`: 振り子、目盛り、青いタイミング灯。
- `triplet_relay`: 同じリレーを3本並べ、連動軸を共有。
- `borrowed_second_hand`: 大小2本の針、貸借を示す噛み合いギア。
- `terminal_echo_ring`: 二重リングと遅延して追従する副針。
- `four_name_quartet`: 4方向端子と中央回転子。
- `dead_heat_needle`: 赤青の2目盛りが同一点へ接近する計器。
- `silent_three_second_timer`: 3室砂時計と消音カバー。
- `delay_return_gear`: 逆回転する副歯車と戻りバネ。
- `zero_hour_clapper`: 3つの発動点を持つレール式クラッパー。
- `terminal_bell`: ベル、3段カウンター、割り込みハンマー。
- `paradox_mortgage`: 時計機構へ契約紙ロールと負債カウンターを追加。
- `reversal_turbine`: 逆向き羽根、青赤の流路、方向計。

### R04 観測・航法・信号キット

- `surge_gimbal`: 3軸ジンバルと速度針。
- `rift_compass`: 亀裂入り方位盤と浮遊針。
- `signal_lens`: 真鍮望遠鏡、青いレンズ、焦点ノブ。
- `archive_compass`: 方位盤へ折り畳み地図、インク瓶、索引針を追加。
- `overtake_signal`: 赤青2灯、切替レバー、追い越し矢印。

### R05 経済・報酬キット

- `salvage_magnet`: U字磁石、金属片、回収トレイ。
- `war_cache`: 補給箱、金セル、封印帯。
- `scavenger_contract`: 巻物筒、契約印、回収フック。
- `bounty_drone`: 小型ドローン頭部、硬貨投入口、追跡レンズ。
- `memorial_fund_coil`: 硬貨受けと銅コイルを直結。
- `carryover_price_tag`: 機械式値札、鎖、ラウンド目盛り。

### R06 医療・生体機構キット

- `repair_nanites`: 透明アンプルと微小修復アーム群。
- `pulse_injector`: 注射筒、脈動セル、圧力計。
- `blood_pump`: 人工心臓、赤い管、真鍮ポンプ。
- `emergency_foam`: 加圧ボンベ、白い泡、破裂弁。
- `armor_garden`: 装甲花弁、成長セル、補修根管。
- `twilight_pacemaker`: 赤青2室心臓、切替弁、HP境界計。
- `bleed_pulsator`: 血液アンプル、拍動コイル、タイムライン針。

### R07 スロット・ロードアウト・Gradeキット

- `loadout_harness`: 胸部ハーネス、カード留め具、荷重計。
- `full_slot_bell`: 3セル表示器と中央ベル。
- `vacancy_interest_meter`: 空セル3本、蓄積ゲージ、利息針。
- `fourth_reserve_rack`: 4本目だけ異なる色の縦ラック。
- `single_seat_duel_sheath`: 単一大型カード用鞘と封鎖バー。
- `reserved_seat_tag`: 最終スロットへ掛ける予約札と割り込み印。
- `isolation_chamber`: 独立した補助スロットと透明隔壁。
- `grade_staircase`: 0から3の高さを持つ4段台とカード受け。
- `unpolished_motherboard`: 未研磨基板、ベースカード端子、低速警告灯。
- `overload_seal`: 過積載バッグ留め具、赤い封印、2段余剰計。
- `empty_rack_bus`: 空きラックを結ぶバスバーと追加ソケット。
- `full_load_latch`: 上限ぴったりで閉じる大型ラッチ。
- `weight_ticket_punch`: 5重量のパンチ器と小型カード排出口。
- `grade_differential_wheel`: Grade差を示す同心4輪。

### R08 シールド圧力・消費キット

- `full_absorption_gauge`: shield面と吸収100%計器。
- `evaporation_recovery_valve`: 蒸気逃がし弁、3段トークン槽。
- `residual_pressure_detonator`: 圧力缶、ゼロ針、起爆子。
- `rupture_insurance_film`: 破れた透明膜、返金印、再使用ダイヤル。
- `compression_caliper`: shield厚を測る大型ノギスと圧縮弁。

### R09 状態・病理キット

- `slow_charge_accumulator`: slowメダリオン、蓄積セル、効果増幅針。
- `four_symptom_seal`: 4状態メダリオンを囲む封印枠。
- `quarantine_buffer`: 隔離カプセル、6秒時計、遮断弁。
- `symptom_transfer_paper`: 状態を吸う紙ロール、転写ローラー、敵側排出口。
- `critical_pathology_meter`: 4状態槽、終了針、最終反応ランプ。

### R10 カード刻印・変換炉キット

- `solar_pinion`: 太陽歯車、刻印カード受け、cast/recast二針。
- `overcharge_confection_furnace`: 小型炉、40%増幅室、60秒安全弁。
- `polarization_converter`: 赤攻撃側と青盾側を結ぶ回転プリズム。
- `balanced_three_phase_unit`: slot、cast、recastの3相端子と中央カード受け。

### R11 進行・危険地帯・アリーナキット

- `seven_step_validator`: 7段階の階段計と4つの節目灯。
- `depth_pressure_gauge`: 波数付き圧力計、追加スロット管、cast負荷弁。
- `emergency_recovery_line`: 救命管、1HP灯、強制撤退レバー。
- `defeat_wiring`: 敗北赤線から次戦4スロットへ接続する配線盤。
- `overtime_key`: 勝利数と敗北許容量を同時に進める二重キー。
- `loop_wear_wheel`: 28目盛り輪、摩耗溝、再使用短縮ギア。

## 8. カード93枚の共通ジオラマと追加部品

カード用に同じ部品を作り直さないため、各ジオラマは先に完成した人物・遺物ライブラリを次のようにリンクします。

| カード基礎シーン | 直接再利用する部品 |
| --- | --- |
| C01、C02、C03 | 人物用の10武器、5オフハンド、盾発生器、標的用の共通装甲板 |
| C04、C05 | R03の時計・針・レール・歯車、R02のセル・冷却管 |
| C06、C07 | R06の医療部品、R09の状態メダリオン・槽・転写機構 |
| C08 | TurretとMedic Droneのアーム、ammo_pack、カード搬送レール |
| C09 | R02のリアクター、R08の圧力機構、R10の変換プリズム |
| C10 | R07のラック・カード受け、R10の刻印・Grade機構 |
| C11 | R03の逆転機構、R04のジンバル・レンズ、共通プリズム |
| C12 | 人物用のhalo、crown、wings、spear、R01の展示台 |
| C13 | C01からC12の完成部品を組み合わせ、固有の大型フレームだけ追加 |

### C01 近接試験台

- `quick_slash`: blade、青い短い斬線、薄い標的板。
- `strike`: blade、正面打撃、単一のへこんだ標的板。
- `heavy_swing`: hammer、重い振り子軌道、砕けた床固定具。
- `bleed_cut`: 鋸歯blade、赤い導管、切断された装甲片。
- `execution`: 上下プレス刃、低HP赤灯、固定標的。
- `rupture_strike`: 油圧blade、ひび割れ装甲、赤い破断線。
- `self_tuning_edge`: bladeへ研磨アームと自己調整ダイヤルを追加。
- `axiom_sever`: 分割greatsword、幾何学標的、切断された規則線。
- `spark_jab`: 電極blade、短いピストン、再使用スパーク。
- `hammer_feint`: hammerと囮軌道、遅延した副打撃標識。
- `recycler_claw`: claws、回収トレイ、再使用へ戻る歯車。
- `execution_matrix`: 複数刃、割り込み格子、中央標的。

### C02 射撃・砲撃レンジ

- `weak_shot`: blaster、黄色の弱体弾、力が抜けた標的腕。
- `assault`: 大型blaster、前進する射撃台、破城標的。
- `interrupt_shot`: cannon、発動線を切る横向き衝撃子。
- `tripwire`: 床ワイヤー、slow灯、倒れる訓練人形。
- `meteor_crash`: 上方投射筒、落下弾、赤い着弾円。
- `auto_turret`: turret共有部品、回転台、無限給弾帯。
- `bulwark_cannon`: tower_shieldとcannonを直結する給電管。
- `marking_dart`: 細いdart、vulnerable標的マーク、照準器。

### C03 シールド・防壁試験室

- `guard`: shield、単一発生器、正面の六角面。
- `quick_guard`: buckler、手首発生器、短い展開軌道。
- `barrier_deploy`: 三脚発生器、横長防壁、床アンカー。
- `fortify`: 多層壁、補強梁、閉鎖ゲート。
- `bastion_drive`: 車輪付き防壁、前進レール、押し出し機構。
- `mirror_aegis`: 鏡面shield、反射光、複製された小盾。
- `entropy_armor`: 分割装甲球、崩壊片、強化用コイル。
- `prism_guard`: プリズムshield、状態除去光、二色の排出粒子。

### C04 タイムラインレール

- `delay_step`: 赤い重り、右へずれるカード台、遅延目盛り。
- `haste_focus`: 青い牽引ハンドル、左へ進む台、集中レンズ。
- `time_buy`: 時計レバー、敵側の追加レール、購入済み時間セル。
- `time_flow_control`: 青赤の並列レール、中央切替器。
- `stasis_field`: 透明ドーム、停止ボタン、slow霧。
- `chronostasis`: 閉じた停止ゲート、固定針、凍結したカード台。
- `entropy_reversal`: 逆回転コンベア、反転矢印、赤い戻り光。
- `zero_hour`: 大時計、逆流分岐、0秒発動位置。
- `timer_hook`: フック付きカード台、敵を右へ引く鎖、自分を左へ引く滑車。
- `chrono_blackout`: 暗転時計、逆流レール、slow遮光板。
- `epoch_breaker`: 砕けた時計ギア、hammer、停止した針。
- `absolute_zero`: 冷却槽、停止ゲート、凍結レール。

### C05 再使用ワークベンチ

- `reload`: 回転弾倉、カードカートリッジ、再装填レバー。
- `recirculate`: 円形スプール、戻り管、青い再使用針。
- `over_reload`: 多連弾倉、過回転モーター、長い冷却管。
- `overclock_routine`: 制御盤、cast/recast二系統、赤い限界灯。
- `grit_reload`: 手回し機構、汚れた工具、shield補助セル。

### C06 医療・補修ベイ

- `repair_burst`: 補修アーム、hex shield、緑の医療セル。
- `purge_pulse`: 円形洗浄ゲート、4状態の排出容器、回復灯。
- `brace_patch`: 装甲片を押さえる両手、接着材、短いshield波。
- `field_medic`: medic_drone小型部品、治療台、状態回収トレイ。
- `phoenix_circuit`: 翼状補修アーム、再点火コア、成長回路。
- `deus_ex_machina`: 大型医療オートマトン、全状態排出、再使用・自動投入ライン。

### C07 状態・血液ラボ

- `blood_chain`: 血液ポンプ、赤い鎖状導管、連続反応槽。
- `blood_siphon`: 敵側赤槽から自分側緑槽へ流れるポンプ。
- `rust_cloud`: 腐食缶、弱体・slowノズル、錆びた標的。
- `rupture_mark`: ひび割れ標的、bleed/vulnerable二重印。
- `blood_moon_protocol`: 赤い円盤、bleed槽、vulnerable照射器。

### C08 自動化・ドローン工場

- `sequence_loader`: コンベア、カード台、武器を順に組むアーム。
- `crisis_drone_swarm`: 同じ小型ドローンを5体、HP境界センサー。
- `drone_foundry`: 組立アーム、shield部品、量産出口。
- `tactical_mirror`: 2つのカード台、鏡、再使用調整機構。
- `recursive_protocol`: 自分へ戻るコンベア、増幅歯車、連続投入口。

### C09 エネルギー・シールド変換器

- `adrenaline_link`: 2本の活性セル、haste/recast二方向導管。
- `aegis_ram`: shieldセルからramへ直結する太い導管。
- `barrier_overdrive`: shield消費槽、hasteタービン、再使用弁。
- `capacitor_step`: 靴型踏板、shieldセル、左向き加速レール。
- `reactor_leech`: shield槽から攻撃・回復へ分岐する吸引管。
- `recursive_battery`: batteryを小型shieldへ循環させる自己給電輪。
- `quantum_exchange`: 青shield側と赤attack側の変換プリズム、緑回復管。

### C10 アーカイブ・再帰マトリクス

- `paradox_loop`: 無限形レール、自己増幅ノード、カード台。
- `grave_protocol`: 保存カプセル、shield/heal槽、自動再投入アーム。
- `final_archive`: 最終カード棚、3種強化端子、自動搬送路。
- `golden_ratio`: 黄金比コンパス、成長目盛り、cast/recast二針。

### C11 位相・重力・裂け目チャンバー

- `phase_lance`: 3枚の位相ゲートを貫くlanceとvulnerable標的。
- `null_cascade`: 奥へ連続するゲート、damage光、遅延する影。
- `rift_volley`: riftを通る複数弾、敵側のずれたカード台。
- `phase_zip`: 短い位相通路、haste線、再使用出口。
- `gravity_snare`: 重力球、停止レール、敵を右へ引く場。
- `singularity_guard`: 小型特異点を囲むshield、停止ゲート。
- `worldline_collapse`: 複数レールが1つのriftへ崩れ込む構図。
- `event_horizon`: 黒い中心球、引き延ばされた標的、slow外周輪。

### C12 天体・オメガ祭壇

- `omega_ray`: 円形太陽砲、細い白金beam、vulnerable印。
- `solar_verdict`: 太陽歯車、上から降りるblade、赤い判決標的。
- `citadel_prime`: 小型城塞、巨大shield、緑の回復室。
- `seraph_array`: 翼状ドローン列、shield面、hasteレール。
- `omega_sanctuary`: 白金カプセル、heal/shield二重層、停止時計。
- `crown_of_thorns`: thorn crown、shield面、赤いbleed棘。

### C13 大型伝説・指揮ジオラマ

- 量産ドローンはC08を参照し、ここでは固有大型編成だけを扱う。
- `atlas_protocol`: 巨大支柱、shieldコア、全カードへ伸びる強化配線。
- `ragnarok_engine`: 戦争輪、攻撃炉、自動投入コンベア。
- `infinity_arsenal`: weapon共有部品10種を奥へ反復配置し、中央に強化炉。
- `tempest_choir`: 複数ドローン、弱体放射、haste指揮レール。
- `last_bastion`: tower_shield、cannon、ramを一体化した最終壁。
- `dominion_pulse`: プレイヤーと敵の2像、攻撃・速度4導管、中央shield核。
- `chronicle_sovereign`: アーカイブ玉座、5強化端子、自動投入ゲート。

## 9. 小型アイコン、マップ、ブランド、背景

| 対象 | Blender共通形状 | 個別差分 |
| --- | --- | --- |
| 状態4種 | 同じ円形メダリオン、厚み、外周 | bleedは滴、slowは時計、vulnerableは割れ盾、weakは折れた剣 |
| 共通UI 13種 | 同じ斜め正投影、黒鉄ベース、明るい象徴物 | attack、speed、shield、hp、gold、step、time、relic、card_owned、card_equipped、settings、version_history、card |
| カード効果 | 共通UIのattack/shield/hp/speed/timeを再利用 | shield_spend、delay、haste、recast、interrupt、cleanse、empower、auto_queue、timeline_stop、timeline_reverse、status、effect |
| マップ9種 | 同じ六角台座と正投影カメラ | normal_battle、elite_battle、boss、shop、forge、heal、event、hazard、lock |
| UI操作部品 | 同じ機械パネル、つまみ、溝 | CheckButton、CheckBox、HSliderの通常・選択・反転・無効状態 |
| 独自ロゴ | chrono_ring、カード台、盾の3要素を単純化 | 16px用、128px用、単色版、立体スプラッシュ版 |
| 全画面背景 | 戦闘フィールドの遠景部品を再利用 | 青側、金側、赤い中央炉、暗いグリッド床 |
| ラン結果背景 | chrono_ringと階段を再利用 | 評価バーへ視線を集める中央スポット |
| 戦闘フィールド | 床タイル、草、岩、花、柱、樽、レーン | エリアごとの色、破損、危険地帯部品 |

`art_src/blender/previews/battle_vertical_slice.png`は新しい縦切りBlendから再生成します。`build/web/index.icon.png`、`build/web/index.apple-touch-icon.png`、`build/web/index.png`は独自ロゴとスプラッシュからWeb出力時に再生成します。`addons/gd-eos/doc/logo.png`はゲーム資産ではなく上流プラグイン文書の第三者ロゴなので、形を模倣した自作版へ交換せず、出典を維持したままゲーム配布物から除外します。

コード生成フォールバックは、通常表示が全てBlender成果物へ移行した後もデバッグ用として残します。フォールバックを削除して欠損時にクラッシュさせる設計にはしません。

## 10. レンダー規格

| 出力 | 原本レンダー | 最終出力 | 規則 |
| --- | --- | --- | --- |
| カード | 2048x2048 Cycles、透明または統一暗背景 | 512x512 RGBA | 外周8%安全域、文字・カード名・枠なし、主効果を中央60%へ置く |
| 遺物 | 2048x2048 Cycles、透明 | 512x512 RGBA | 同じ台座、35度前後の視点、1物体、名前なし |
| ポートレート | 2048x2048 Cycles | 1024x1024 RGB | 同じ焦点距離、頭と上半身、左右反転禁止、陣営別リムライト |
| 状態・UI・マップ | 512x512正投影 | 96x96または64x64 RGBA | 24px確認用の別レンダーを必ず生成 |
| Webスプラッシュ | 2400x1800 | 800x600 RGBA | 中央60%安全域、ゲーム名はGodot UI側で重ねる案を優先 |

レンダーは同じカラーマネジメント、露出、焦点距離、世界色、影の濃さを固定します。Cyclesのノイズ除去後に高品質縮小し、512pxへ直接低サンプルでレンダーしません。

## 11. 自動化と検証

| 検証 | 条件 |
| --- | --- |
| ID網羅 | cards 93、relics 86、portraits 25、status 4がデータIDと完全一致 |
| 再現性 | 空の一時フォルダからBlenderバッチで同じ出力名とmanifestを生成 |
| 見た目 | カテゴリごとのコンタクトシート、24px/48px/74px/168px実寸比較 |
| 3D構造 | 18ボーン、5ソケット、Transform適用、法線、UV、材質名、三角形数を検査 |
| アニメーション | 18クリップ、release/impact等のマーカー、構え、盾、遠隔、魔法を全25体で確認 |
| 容量 | 高精細BlendをPCKへ含めず、共有GLBで新規3Dランタイム増加を35MiB以内に抑える |
| Godot | Card UI、Startup Cache、3Dモデル、Animation Lab、Localizationのsmokeを実行 |
| Web | Web出力、R2 PCK、Heroku、初回ロード時間、メモリ使用量を確認 |
| 権利 | `data/art_provenance.json`へ作者、Blender版、制作日、外部入力、ライセンス、SHA-256を記録 |

各バッチでは、Blender生成、原寸コンタクトシート、Godot実画面、該当smoke、Web出力の順で確認します。承認前に旧画像を削除せず、1 IDずつ差し替え可能にします。

## 12. 最初に制作する縦切りバッチ

最初の実制作では、全系統を一度に検証できる次の14点だけを完成させます。

| 種類 | ID | 選定理由 |
| --- | --- | --- |
| キャラ | `balanced`, `scout` | 既存Blender原本とGLBがあり、18ボーン互換を比較できる |
| カード | `quick_slash`, `guard`, `delay_step`, `repair_burst`, `auto_turret`, `event_horizon` | 近接、盾、時間、医療、自動化、裂け目の6基礎シーンを検証できる |
| 遺物 | `iron_plating`, `auxiliary_core`, `chrono_shard`, `salvage_magnet` | 装甲、コア、時計、経済の主要キットを検証できる |
| 状態 | `bleed` | 24pxの立体メダリオン視認性を確認できる |
| UI | `attack` | カード面とステータス欄の両方で小サイズを確認できる |

このバッチでアート方向、レンダー時間、512pxの読みやすさ、Web容量、キャラクターの動作を承認してから、キャラクター25体、遺物86個、カード93枚の順で量産します。
