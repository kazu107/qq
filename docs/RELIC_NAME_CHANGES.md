# 遺物名の読みやすさ調整

2026-10-12 / QQ-0.34.1

日本語名が漢字のみで4文字以上だった34件を変更した。英語名、ID、効果、取得条件、画像、セーブ内の所持IDは変更していない。既に所持している遺物にも新しい名前が表示される。

| ID | 以前 | 新しい名前 |
| --- | --- | --- |
| `reactive_barrier` | 反応障壁 | 開幕バリア |
| `borrowed_second_hand` | 借用秒針 | 借りものの秒針 |
| `terminal_echo_ring` | 終端残響環 | 最後のこだまリング |
| `four_name_quartet` | 異名四連符 | 四つの連奏符 |
| `dead_heat_needle` | 同着偏針 | 同時発動の針 |
| `zero_hour_clapper` | 零時拍子木 | 十秒ごとの拍子木 |
| `overtake_signal` | 追越信号器 | 追い越しの信号 |
| `vacancy_interest_meter` | 空席利息計 | 空きスロット貯金箱 |
| `single_seat_duel_sheath` | 単座決闘鞘 | 一騎打ちの鞘 |
| `echo_rectifier` | 反響整流器 | こだまの充電器 |
| `resin_memory_block` | 樹脂記憶塊 | 記憶の樹脂 |
| `full_absorption_gauge` | 全吸収検針器 | 完全ガード計 |
| `evaporation_recovery_valve` | 蒸発回収弁 | シールド回収バルブ |
| `residual_pressure_detonator` | 残圧起爆栓 | 空っぽの加速栓 |
| `rupture_insurance_film` | 破断保険膜 | 中断保険フィルム |
| `bleed_pulsator` | 出血拍動子 | 血の加速器 |
| `slow_charge_accumulator` | 鈍化蓄勢子 | 鈍化チャージャー |
| `four_symptom_seal` | 四症候封印 | 四つの病の封印 |
| `symptom_transfer_paper` | 症候転写紙 | 病をうつす紙 |
| `critical_pathology_meter` | 臨界病理計 | 病の余波 |
| `grade_staircase` | 等級階段器 | グレードの階段 |
| `unpolished_motherboard` | 未研磨母板 | 粗削りの基板 |
| `overload_seal` | 過積載封印 | 詰め込みのお守り |
| `weight_ticket_punch` | 重量検札機 | 重いカードの検札機 |
| `grade_differential_wheel` | 等級差動輪 | グレード差の歯車 |
| `overcharge_confection_furnace` | 過給菓子炉 | オーバーチャージ窯 |
| `polarization_converter` | 偏光変換器 | 攻防スイッチ |
| `balanced_three_phase_unit` | 平衡三相器 | バランス調整器 |
| `seven_step_validator` | 七段検印機 | 七歩ごとの検印 |
| `depth_pressure_gauge` | 深度圧力計 | 深掘りメーター |
| `emergency_recovery_line` | 緊急回収索 | 緊急脱出ロープ |
| `defeat_wiring` | 敗北配線器 | 再起の配線 |
| `overtime_key` | 延長戦鍵 | 延長戦の鍵 |
| `loop_wear_wheel` | 周回摩耗輪 | 周回の歯車 |

変更元は`data/localization/ja.json`。メタ進行、ショップ、イベント、報酬、遺物ツールチップ、開発者アートラボは同じDatabaseの表示名を使用する。

`RelicNamesSmoke`で全86種の名前の重複・漢字だけの長い名前・アイコンツールチップ・ID・英語定義を検証する。日本語フォントも再生成し、`LocalizationSmoke`で文字欠けを確認する。

今回の確認: 関連Godotテスト10件、マップ/アリーナで3種類のブラウザ寸法における解除ボタンの実ホバー・装備解除/再装備、メタ進行で6種類の寸法のレイアウト検査を通過した。ネイティブテストは実セーブとは別のプロファイルで実行した。
