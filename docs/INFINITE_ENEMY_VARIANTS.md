# 無限モードの強化個体

QQ-0.57.0 / infinite-16。第2周（ステップ29）以降だけ、既存の敵を対応する強化個体へ置き換えます。第1周・通常モード・アリーナの元の敵とカード編成は変更しません。ランキングは準備中を維持します。

## 基本方針

- 元のシルエット・装備・18ボーンのアニメーションを共有し、装甲・布・金属の縁取り・発光色を変更します。GLBは複製せず、マテリアルをキャッシュします。元の敵のマテリアルは変更しません。
- 強化個体の基礎HPは元の約110%（四捨五入）、攻撃は+1。高速型は速度も+1です。その上に、従来の無限モードの周回補正を適用します。
- 第2周のカードはGrade 2、第3周からは従来どおりGrade 3上限と超過周の追加補正を使います。敵専用8枚にはGrade 0〜5を用意しています。
- 通常戦闘の連戦数、危険地帯の増加数は維持します。危険地帯の敵の種類は周内のエリアに戻してから強化個体へ変換します。序盤エリアが第2周からすべて終盤の敵になることはありません。
- 既存セーブでは未撃破の敵を更新し、撃破済みの波・獲得済み報酬・記録済みスコアは保持します。
- 効率評価の基準時間は、元の敵の基準時間に追加HPの割合と既存の周回HP補正を掛けます。新しいIDが一律60秒扱いになることを避けます。

例: 第2周の疾風のスカウトはHP37・攻撃5・速度10です。通常のスカウト（HP21・攻撃2・速度8）を別物に置き換えるのではなく、加速予約と手数を強化する方向にしています。

## 敵別の編成

カードIDは `data/cards.json`・`data/boss_cards.json`・`data/enemy_cards.json` の定義に対応します。具体的な効果量と補正後の値は、敵情報画面・カードツールチップで確認できます。

| 強化個体 | 色・役割 | ロードアウト | 対処の要点 |
| --- | --- | --- | --- |
| 疾風のスカウト | 蒼・金／高速投入 | `quick_slash`, `ascendant_edge`, `haste_focus`, `reserve_tempo`, `quick_guard`, `reserve_swift_commit` | 短い攻撃を防ぎ、加速の準備を中断する |
| 熔炉のブルート | 赤銅・黒／重撃予約 | `heavy_swing`, `ascendant_edge`, `reserve_focus`, `weak_shot`, `ascendant_bulwark`, `reserve_heavy_commit` | 遅い大技の詠唱が狙い目 |
| 零式ディスラプター | 白・紫／遅延と再使用妨害 | `ascendant_clock`, `interrupt_shot`, `reserve_recast_jam`, `reserve_time_mine`, `ascendant_edge`, `quick_guard` | 長い詠唱を一度に並べすぎない |
| 金剛ガーディアン | 金・紺／シールド消費砲撃 | `guard`, `ascendant_bulwark`, `ascendant_siege`, `aegis_ram`, `barrier_conversion`, `reserve_shield` | 障壁を中断し、転換の再展開待ちを攻める |
| 紅刃レイダー | 紅・銀／出血連携 | `ascendant_brand`, `rupture_strike`, `regen_bloodwrap`, `reserve_status`, `ascendant_edge`, `quick_guard` | 裂傷の本命前に出血を解除する |
| 翡翠のメディック | 白・翡翠／再生と転換 | `ascendant_mend`, `regen_patch`, `life_conversion`, `reserve_siphon`, `ascendant_edge`, `quick_guard` | 回復の中断と転換切れへの集中攻撃 |
| 白銀クロノガード | 銀・青／遅延からの高速投入 | `ascendant_clock`, `stasis_field`, `reserve_swift_commit`, `adrenaline_link`, `ascendant_edge`, `regen_barrier` | 鈍化解除と短い攻撃を用意する |
| 真刻タイムキーパー | 黒・金・水色／障壁付きDPSチェック | `timekeeper_final_strike`, `timekeeper_amplify`, `timekeeper_time_mark`, `ascendant_bulwark` | 長い最終攻撃は従来どおり。障壁と再使用短縮を挟んで増幅を重ねるため、増幅の中断が重要 |
| 蒼刃ストーカー | 蒼・白／高速攻撃と自動ガード | `phase_lance`, `ascendant_edge`, `reserve_chain`, `reserve_swift_commit`, `adrenaline_link`, `quick_guard` | 高速投入の準備を止め、連鎖指令のガードを突破する |
| 白夜ヴォイド | 白・紫／転換要塞 | `mirror_aegis`, `ascendant_bulwark`, `ascendant_siege`, `barrier_conversion`, `reserve_shield_jam`, `purge_pulse` | 解除を見てから弱体化を重ねる |
| 残響のレヴナント | 青緑・金／反響と成長 | `ascendant_echo`, `paradox_loop`, `ascendant_brand`, `reserve_growth`, `rupture_strike`, `quick_guard` | 反響準備後の本命を中断する |
| 覚醒パラドックス | 黒・桃紫／反響と時間妨害 | `ascendant_echo`, `null_cascade`, `paradox_loop`, `ascendant_clock`, `entropy_reversal`, `ascendant_bulwark` | 反響の攻撃を止め、大技を妨害へ一斉にさらさない |
| 雷牙プレデター | 鋼・雷光／反動と自動ガード | `rift_volley`, `phase_lance`, `ascendant_brand`, `reserve_chain`, `reserve_recoil`, `adrenaline_link` | シールドを先に発動して反動を受け止め、出血を放置しない |
| 紅蓮コロッサス | 黒鉄・橙／装甲と砲撃 | `entropy_armor`, `ascendant_bulwark`, `ascendant_siege`, `ascendant_verdict`, `fortify`, `reserve_heavy_commit` | 終焉の宣告は中断可能 |
| 断罪アクシオム | 白・金・青／必殺技の予約 | `axiom_sever`, `ascendant_verdict`, `reserve_focus`, `rift_volley`, `ascendant_bulwark`, `ascendant_clock` | 小技は防ぎ、長い宣告へ中断を合わせる |
| 極光セラフ | 紫・金・薄緑／反響する光線 | `omega_ray`, `ascendant_verdict`, `ascendant_echo`, `reserve_focus`, `adrenaline_link`, `regen_emergency` | 強い光線と宣告の発動を優先して止める |
| 冥灯アーキテクト | 灰・緑／逆流中の再建 | `grave_protocol`, `zero_hour`, `ascendant_mend`, `ascendant_clock`, `reserve_heal_jam`, `mirror_aegis` | 回復を一枚に頼らず、再生炉の詠唱を止める |
| 真終エタニティ | 黒・白金・紫／反響・再生・時間操作 | `zero_hour`, `ascendant_verdict`, `ascendant_echo`, `grave_protocol`, `ascendant_clock`, `ascendant_mend`, `omega_ray` | 宣告か再建のどちらかを確実に止め、疲労にも備える |

## 敵専用カード

数値はキャラクターの攻撃力・周回補正・状態補正を加える前の基礎値です。敵専用カードは通常報酬、ショップ、アリーナ、プレイヤーのデッキには追加しません。すべて詠唱を中断できます。

| 名前 / ID | Grade 0 → 5の基礎効果 | 詠唱 / 基本再使用 / スロット |
| --- | --- | --- |
| 追撃の刃 / `ascendant_edge` | 5→15ダメージ。再使用8.4→7.4秒 | 2.4秒 / 8.4秒 / 1 |
| 王者の障壁 / `ascendant_bulwark` | シールド12→27、再使用中の一枚を2→3秒短縮 | 3秒 / 14.4秒 / 1 |
| 深紅の刻印 / `ascendant_brand` | 3→8ダメージ、出血18→28秒・基礎威力2→4 | 3秒 / 15.6秒 / 1 |
| 再生炉起動 / `ascendant_mend` | HP6→11回復、リジェネ12→22秒・3秒ごと2→4回復 | 3.6秒 / 21.6秒 / 1 |
| 時刻の裂け目 / `ascendant_clock` | 相手の全カードを2.4→3.9秒遅延、鈍化12→22秒 | 4.2秒 / 21.6秒 / 1 |
| 覚醒する反響 / `ascendant_echo` | 反響1回分、シールド4→9。再使用22.8→19.8秒 | 3.6秒 / 22.8秒 / 1 |
| 金剛の砲撃 / `ascendant_siege` | シールド8消費、14→24ダメージ。再使用15.6→14.1秒 | 3.6秒 / 15.6秒 / 2 |
| 終焉の宣告 / `ascendant_verdict` | 脆弱12→22秒を付与してから18→28ダメージ | 8.4秒 / 28.8秒 / 2 |

## 調整・確認

- 編成・色・戦術説明: `data/infinite_enemy_variants.json`
- 専用カードの基礎値とGrade: `data/enemy_cards.json`
- 周回補正: `RealtimeBattleEngine._build_scaled_enemy_def` / `_apply_enemy_card_scaling`
- モデル: 元の `assets/models/battle/*.glb` を共有。色替えは `BattleActor3D` の専用マテリアルキャッシュ。
- アート原本: `art_src/blender/characters/qq_ascended_enemies.blend`、`art_src/blender/cards/ascended_enemy_cards.blend`
- 画像再生成: `tools/build_blender_infinite_enemies.ps1`。独立したバックグラウンドBlenderのみを使います。
- 開発者の戦闘ラボから18体を選択できます。周回補正込みの比較には、バランス調整ラボで無限モード・強度2以上を指定してください。
- 自動検証: `tests/InfiniteEnemyVariantsSmoke.tscn`。18体のAI実行、第1/2/5周、敵情報との一致、マテリアル共有・復元、移行、専用カードのGradeとプレイヤー利用拒否を確認します。

既存デッキとの厳密な難易度は、実戦とバランス調整ラボで継続確認する前提です。新しい効果処理は増やさず、既存の反響・予約・再生・転換・シールド消費などを組み合わせています。
