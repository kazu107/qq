# 時間・状態管理を軸にした新規遺物案調査

- 調査日: 2026-07-12
- 対象: 現行のリアルタイムカード戦闘
- 提案数: 34案
- 主題: timeline停止・逆流・遅延、status残り時間、recast、interrupt、カード自動投入、active slot占有

## 結論

現行遺物は能力値、戦闘開始時シールド、勝利報酬が中心で、戦闘中のイベント列へ介入する遺物はほぼない。一方、現行エンジンには `scheduled_time`、`cooldown_remaining`、statusの秒数、interrupt可否、自動投入元と深度、active slot使用量が既に存在する。したがって、新規遺物は新しい戦闘資源を増やすより、既存の「残り秒数」と「占有状態」を条件・報酬・負債に変換する方が、このゲーム固有の判断を増やしやすい。

最初の実装候補は **凍結振り子、残響培養槽、三拍子リレー、破断スプリング、反響整流器、空席利息計、満員ベル、予約席タグ** の8個を推奨する。停止、status再付与、recast、interrupt、自動投入、slot管理を一通り検証でき、各軸の価値を個別に計測しやすいためである。

## 現行ゲームの基準

コードとデータから確認した基準は以下の通り。

| 項目 | 現行仕様 | 遺物設計への含意 |
| --- | --- | --- |
| 戦闘時間 | `battle_time` を秒で加算するリアルタイム制 | ターンではなく秒、残り時間、一定間隔で条件を記述する |
| active slot | 両陣営とも最大3。全93枚中、slot 1が55枚、slot 2が29枚、slot 3が9枚 | 1枠の増減は大きい。恒久的な4枠目には必ず負債が必要 |
| cast | 0.6〜16.8秒、平均約5.79秒 | hasteは0.8〜2.4秒、stopは1.0〜3.0秒程度を基本単位にする |
| recast | 8〜66秒、平均約36.45秒 | 単体短縮は3〜6秒、全体短縮は1〜3秒程度を基本単位にする |
| interrupt | 93枚中21枚がinterruptible。中断後は通常の全 `recast_time` に入る | 成功時報酬だけでなく、空振り保険や被interrupt時の反撃余地がある |
| timeline停止 | `stop` は対象の `scheduled_time` を毎秒1秒後ろへ送り、見かけ上cast残量を固定する | 戦闘時計そのものは止まらず、recast、status、shield減衰は進む |
| timeline逆流 | `reverse speed=1` は対象を毎秒2秒後ろへ送り、cast残量を毎秒1秒増やす | 複数flowは現状加算されるため、遺物側で重複禁止と上限が必要 |
| 単発delay/haste | 原則として最も早く発動する対象を選ぶ。hasteは現在時刻より前にはならない | 「最前列を守る・押す」が読みやすい基本対象になる |
| status | `weak`、`vulnerable`、`slow`、`bleed`。再付与は加算でなく残り時間と新規時間の大きい方 | 再付与で失われる秒数、自然消滅直前、cleanse時の残量を資源化できる |
| bleed | 6秒ごとに1ダメージ | tick間隔を動かす場合はduration消費や発動回数上限が必要 |
| 自動投入 | slot cost 0、通常recastなし、1効果あたり最大12枚。深度制限または無制限指定あり | 強化だけでなく専用slot、熱量、深度、発動回数で必ず制御する |
| 遺物 | 同一遺物は重複取得不可。現行効果は主に取得時、戦闘開始時、勝利時 | 戦闘内カウンタ、内部cooldown、イベント購読の共通基盤が必要 |

主な確認箇所は `src/core/battle/RealtimeBattleEngine.gd`、`src/core/runtime/UnitState.gd`、`src/core/runtime/ActiveCardInstance.gd`、`src/core/runtime/CardRuntimeState.gd`、`src/core/run/RelicService.gd`、`data/cards.json`、`data/relics.json`。

## Web調査ソースと抽出パターン

ここでの「参考」は効果のコピーではなく、発火条件、負債、上限、UIで予告可能な構造を指す。コミュニティWikiは更新差分があり得るため、個別数値ではなく確認できた設計パターンを参照した。

### Chrono Ark

- **CA-COUNT**: [行動カウント](https://wikiwiki.jp/chronoark_jp/%E8%A1%8C%E5%8B%95%E3%82%AB%E3%82%A6%E3%83%B3%E3%83%88)と[カウント](https://wikiwiki.jp/chronoark_jp/%E3%82%AB%E3%82%A6%E3%83%B3%E3%83%88)。非迅速行動で敵やCASTING LISTのカウントが進むため、「何を使うと時間が進むか」をプレイヤーが管理する。
- **CA-OVERLOAD**: [コスト](https://wikiwiki.jp/chronoark_jp/%E3%82%B3%E3%82%B9%E3%83%88)。通常スキル連打にはオーバーチャージによるコスト増、迅速には例外があり、速度獲得に明示的な負債を置く。
- **CA-FIXED**: [固定能力](https://wikiwiki.jp/chronoark_jp/%E5%9B%BA%E5%AE%9A%E8%83%BD%E5%8A%9B)。常時アクセス可能な能力をコスト増で相殺する。
- **CA-RELIC**: [遺物](https://wikiwiki.jp/chronoark_jp/%E9%81%BA%E7%89%A9)。4枠制、1ターン1回、N回使用ごと、特定ターン自動生成、追加slotといった発火頻度・占有・自動効果のパターンが多い。

### Across the Obelisk

- **ATO-STATUS**: [Glossary](https://ato.fandom.com/wiki/Glossary)と[Keywords/Effects](https://ato.fandom.com/wiki/Keywords/Effects)。多くのAura/Curseは開始時・終了時にchargeが減り、Fast/Slow/Chillが行動順へ影響する。Bufferのように1回だけ悪影響を防ぐ状態もある。
- **ATO-EQUIP**: [Equipment](https://ato.fandom.com/wiki/Equipment)。戦闘開始時、毎ターン、Nターンごと、1ターンN回まで、カード自動生成・自動castなど、装備側に明示的な周期と上限を持たせる。
- **ATO-CARD**: [Cards](https://ato.fandom.com/wiki/Cards)。Innateで初動を保証し、Vanishで強いカードを戦闘中の循環から外す。
- **公式概要**: [Paradox Interactive](https://www.paradoxinteractive.com/games/across-the-obelisk/about)。パーティ単位のデッキ構築と役割連携を前提にする。

### Astrea: Six-Sided Oracles

- **AST-DICE**: [Dice](https://astrea.wiki.gg/wiki/Dice)。Safe、Balanced、Risky、Hexなど、出力の強さを結果の不安定さ・自己不利益・一時的なデッキ汚染で相殺する。
- **AST-BLESS**: [Blessing](https://astrea.wiki.gg/wiki/Blessing)。Star Blessingは小さく安定、Black Hole Blessingは強力だが明確な欠点を伴う。N回ごとのカウンタを戦闘間で保持する例も多い。
- **AST-FIRST**: [Star Chart](https://astrea.wiki.gg/wiki/Star_Chart)。各ターン最初の1回だけ再利用するため、強さと予測可能性を両立する。
- **AST-REFRESH**: [Duality Degree](https://astrea.wiki.gg/wiki/Duality_Degree)と[Cautious's Card](https://astrea.wiki.gg/wiki/Cautious%27s_Card)。条件達成で使用済み能力をRefreshするが、条件回数やカテゴリを限定する。
- **AST-DRAWBACK**: [Daydreams Mask](https://astrea.wiki.gg/wiki/Daydreams_Mask)と[Artisan Staff](https://astrea.wiki.gg/wiki/Artisan_Staff)。追加ドローやSentinel強化を、戦闘開始時の不利益や毎ターンのドロー減少で相殺する。

### One Step From Eden

- **OSFE-CHRONO**: [Chrono](https://onestepfromeden.fandom.com/wiki/Chrono)。時間倍率がcastだけでなくMana Regen、Shuffle、Poisonなどのタイマーにも影響し、複数Chronoは加算せず上書きされる。
- **OSFE-SHUFFLE**: [Shuffle](https://onestepfromeden.fandom.com/wiki/Shuffle)。デッキ再装填は基礎2.5秒、反復で最大3秒まで遅くなり、Shieldも減る。一方でOn Shuffleの自動効果をまとめて発火する。
- **OSFE-SPELL**: [Spells](https://onestepfromeden.fandom.com/wiki/Spells)と[How to Play](https://onestepfromeden.fandom.com/wiki/How_to_Play)。ランダムに装填される2つのcast slotを即時判断し、slotに保持している間だけ得る効果もある。
- **OSFE-STATUS**: [Status Effects](https://onestepfromeden.fandom.com/wiki/Status_Effects)と[Poison](https://onestepfromeden.fandom.com/wiki/Poison)。Poisonは4秒後に発火して半減し、追加付与で量を増やす代わりにタイマーがリセットされる。
- **OSFE-AUTO**: [Artifacts](https://onestepfromeden.fandom.com/wiki/Artifacts)と[Trap Card](https://onestepfromeden.fandom.com/wiki/Trap_Card)。Shuffleなど予告可能な共通イベントからカードを自動castする。

### Vault of the Void

- **VOV-CORE**: [Nintendo公式紹介](https://www.nintendo.com/en-ca/store/products/vault-of-the-void-switch/)。不要カードを捨ててEnergyへ変換し、敵攻撃をThreatとして一旦保留して次ターン終了時に精算する。
- **VOV-ARTIFACT**: [Artifacts](https://vault-of-the-void.fandom.com/wiki/Artifacts)。最初の1回、第N回、閾値、カード種別、Spell cooldownリセット、Delay Block、効果自身では再発火しない、といった安全な自動発火の例が豊富。
- **VOV-CARD**: [Global Cards](https://vault-of-the-void.fandom.com/wiki/Global_Cards)。Purge、Overcharge、Delay Block、Recurにより、今の損失を次周期の資源へ移す。

## 新規遺物案

数値は現行データのcast/recastレンジを基準にした初期テスト値。`手動カード` は `is_auto_queued == false`、`プレイヤー起因` は敵AI・boss passive・敵遺物ではなくプレイヤーのカードまたは遺物が発生源であることを意味する。

### A. timeline停止・逆流・遅延

| # | 仮名 | 条件 | 具体効果 | シナジー | 安全弁 | 参考パターン |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 凍結振り子 | 各戦闘で初めて、敵のslot 2以上のカードが残り1.5秒以下になる | 敵timeline全体を2.0秒停止する | `interrupt_shot` の入力猶予、`stasis_field`、長い防御cast | 1戦闘1回。slot 1と自動投入は条件外。同系stopとは加算せず長い残量へ上書き | OSFE-CHRONOの非加算時間操作、VOV-ARTIFACTの初回・緊急発火 |
| 2 | 逆行歯車 | 敵効果により自分の1枚が累計4.0秒以上delayされた | 敵の最前列カードを1.5秒間、速度1で逆流させる | delay主体のbossへの反撃、重いカード、`time_flow_control` | 10秒の内部cooldown。1回のdelayイベントから1回だけ。遺物自身の逆流は再発火しない | CA-COUNTの相互カウント、AST-BLESSの閾値発火 |
| 3 | 借用秒針 | プレイヤー起因の効果で敵カードをdelayした | 実際に増えた秒数の40%を、自分の最前列カードへのhasteへ変換する。1回最大2.0秒 | `delay_step`、`timer_hook`、`hammer_feint` | 6秒の内部cooldown。対象がなければ蓄積しない。遺物由来delayは条件外 | VOV-COREの現在損失から次資源への変換、CA-COUNT |
| 4 | 観測者の懐中時計 | 自分のactive cardが0枚、敵が2枚以上の状態が2.0秒続く | 敵の全active cardを2.0秒delayする | 手を空けて敵の投入を見てから対応する制御型、Slow Mode | 戦闘開始直後は発火せず、自分が手動カードを1回解決後に有効。18秒の内部cooldown | VOV-COREのThreat可視化後の反応、CA-COUNTの待機判断 |
| 5 | 等時性アンカー | 敵起因のdelayが自分の同一カードへ入る | そのカードが投入時予定から受けられる累計delayを4.0秒に制限する。超過分は解決後、そのカードのrecastを同秒数だけ短縮する | `heavy_swing`、slot 3フィニッシャー、delay boss対策 | 短縮は最大6.0秒、recast残り1.0秒未満にはしない。プレイヤー自身の負債delayには無効 | ATO-STATUSのBuffer、VOV-CARDの遅延資源化 |
| 6 | パラドックス抵当証 | プレイヤーが敵へstopまたはreverseを付与した | そのflowのdurationを30%延長する。flow終了時、発生源runtimeがCOOLDOWNなら残りrecastへ+6.0秒、既にREADYなら次回recastへ+6.0秒 | `chronostasis`、`entropy_reversal`、`zero_hour` | 延長は1flow最大2.0秒。同じflowへ1回だけ。発生源不明の遺物flowは延長しない | AST-DRAWBACKの強効果＋明示的欠点、OSFE-SHUFFLEの反復負債 |
| 7 | 終端ベル | 同一の敵手動カードを、解決前にプレイヤー起因で3回delayした | interruptibleなら即interrupt。不可なら追加で3.0秒delayする | 小刻みな`timer_hook`、`delay_step`、全体delayの積み重ね | 各instance 1回、12秒の全体内部cooldown。自動投入と遺物delayは回数外 | AST-BLESS/VOV-ARTIFACTの第N回トリガー、CA-COUNTのCASTING LIST |

### B. status残り時間

| # | 仮名 | 条件 | 具体効果 | シナジー | 安全弁 | 参考パターン |
| --- | --- | --- | --- | --- | --- | --- |
| 8 | 残響培養槽 | 既に同じstatusを持つ対象へ再付与する | `overlap = min(現在残量, 新規duration)` とし、更新後を `max(現在残量, 新規duration) + min(4.0秒, overlap x 25%)` にする | `weak_shot`、`rupture_mark`、`rust_cloud`、status更新タイミング | 各status最大45秒。対象・statusごとに5秒の内部cooldown。永続statusには無効 | ATO-STATUSのcharge維持、OSFE-STATUSの再付与とtimer reset |
| 9 | 臨界病理計 | 敵statusが自然減少で残り0になる | `bleed` は消滅直前に1回tick、`weak/vulnerable/slow` は敵最前列を1.2秒delayしてから消える | 長時間status、`blood_chain`、期限ぎりぎりの攻め | 各付与instance 1回。cleanse・上書き消去では発火しない。4秒の全体内部cooldown | ATO-STATUSの開始時・終了時処理、VOV-ARTIFACTの状態減少トリガー |
| 10 | 半減期コンデンサ | 敵statusの残り時間が自然減少で6秒境界を下回る | 1charge獲得。6chargeで最長recastを4.0秒短縮してchargeを0にする | 複数status、長時間debuff、`over_reload` | 1フレーム最大1charge、1戦闘最大3回発火。再付与で境界を上へ戻しても同じ境界は再計上しない | AST-BLESSの保持カウンタ、VOV-ARTIFACTのN回ごと発火 |
| 11 | 防疫バッファ | 各戦闘で最初に自分へnegative statusが付く | そのstatusを6.0秒間「保留」する。保留中は効果・duration減少・tickがなく、終了後に本来のdurationで開始する | 6秒以内のcleanse、`purge_pulse`、`field_medic` | 1戦闘1回。保留中の同status再付与はdurationの大きい方だけ保持。保留自体は延長不可 | ATO-STATUSのBuffer、CA-RELICの最初のターンだけ防止 |
| 12 | 持続交換膜 | 自分のカードで自分のnegative statusをremoveする | `floor(除去時残量 / 6秒)` を換算値とし、Shieldを最大5、最長recastを同じ値だけ最大3.0秒短縮する | `purge_pulse`、`prism_guard`、`field_medic`、長時間debuffを敢えて受ける構成 | 8秒の内部cooldown。1回のcleanseでstatusが複数消えても合算上限はShield 5 / recast 3秒 | VOV-CARDのPurge変換、ATO-STATUSのDispel |
| 13 | 時毒蒸留器 | 敵の`bleed`残量が18秒以上 | bleed tick間隔を6.0秒から5.0秒へ短縮するが、tick時にdurationを追加で1.0秒消費する | `bleed_cut`、`rupture_mark`、`blood_moon_protocol`、短期決戦 | 追加消費で残量0以下になった場合は追加tickなし。tick頻度はこれ以上短縮されず、他の同系効果と非加算 | OSFE-STATUSのPoison加速、ATO-STATUSのDoT charge消費 |
| 14 | 赤方偏移標本 | 敵statusが自然消滅した瞬間、敵にactive cardがある | 敵最前列を1.2秒delayし、自分へShield 1 | status期限と敵castを合わせる制御、`stasis_field` | 4秒の内部cooldown。cleanse、interrupt、戦闘終了による消去は条件外 | ATO-STATUSの期限管理、VOV-ARTIFACTの減少時トリガー |
| 15 | 保留ラベル | プレイヤー起因で敵timelineがstop中 | 敵にある残り時間最小のnegative status 1個も同時にduration減少を停止する | `chronostasis`中に`vulnerable`や`bleed`を保持し、停止後の攻撃へ繋ぐ | 1statusにつき累計3.0秒まで。bleedのtick accumulatorは止めず、停止中にtick時刻へ達してもflow終了まで発火を保留。reverseでは停止しない | OSFE-CHRONOの広域timer倍率と非加算設計 |

### C. recast管理

| # | 仮名 | 条件 | 具体効果 | シナジー | 安全弁 | 参考パターン |
| --- | --- | --- | --- | --- | --- | --- |
| 16 | 三拍子リレー | 手動カードを3枚解決する | 自分の最長recastを6.0秒短縮する | 低castカード、`spark_jab`、`reload`、多カードloadout | 自動投入はカウント外。発生源カード自身は短縮対象外。1戦闘最大4回 | VOV-ARTIFACTの3回でSpell cooldown reset、AST-BLESSのN回カウンタ |
| 17 | 過熱ラチェット | READYになってから1.0秒以内のカードを投入する | そのcastを15%短縮するが、解決後のrecastを20%延長する | 短recastカード、連続入力、tempo型スターター | cast短縮後の最低0.5秒、recast増加は最大+8.0秒。自動投入は対象外 | CA-OVERLOAD、OSFE-SHUFFLEの即応と将来負債 |
| 18 | 冷却負債帳 | recast短縮が残量を超えて0未満へはみ出す | 超過分を最大6.0秒まで保存。次に別の手動カードがcooldownへ入る時、最大3.0秒を自動適用する | `reload`、`recirculate`、短recastと長recastの混成 | 同じカードへの戻し不可。適用後も最低1.0秒残す。保存値は戦闘終了で消える | VOV-CARDのDelay Block、Overchargeによる次周期への繰越 |
| 19 | 双極クラッチ | 1イベントでrecastを4.0秒以上短縮、またはactive cardを2.0秒以上hasteする | 前者なら自分の最前列を1.2秒haste、後者なら最長recastを1.2秒短縮する | `adrenaline_link`、`barrier_overdrive`、`phase_zip` | 遺物が発生させたhaste/recast短縮は遺物自身を発火させない。2秒の内部cooldown | VOV-ARTIFACTの「自身では再発火しない」、連鎖変換パターン |
| 20 | 異名四連符 | 直近の手動解決カードIDが4枚すべて異なる | 全cooldownを3.0秒短縮し、履歴を空にする | 幅広いloadout、同一カード連打ではないローテーション | 自動投入は履歴外。同IDを解決するとそのIDから履歴を再開始。1戦闘最大3回 | AST-BLESSのカテゴリ別カウンタ、CA-RELICのNスキル使用 |

### D. interrupt

| # | 仮名 | 条件 | 具体効果 | シナジー | 安全弁 | 参考パターン |
| --- | --- | --- | --- | --- | --- | --- |
| 21 | 破断スプリング | プレイヤーがinterruptに成功する | 中断対象のslot cost 1につき、自分の最前列を1.0秒hasteする | `interrupt_shot`、`meteor_crash`、重い敵カードへの対処 | haste最大3.0秒、6秒の内部cooldown。自動投入の中断は対象外 | CA-COUNTの発動阻止、VOV-ARTIFACTのHeavy種別報酬 |
| 22 | フェイルセーフ導火線 | interrupt効果が解決したが、有効対象が0枚 | そのinterruptカードのrecastを50%短縮する | 敵が直前に解決した場合の空振り保険、PvP読み合い | 各runtime 1戦闘1回。短縮後も最低6.0秒。そもそも敵active cardが0枚なら発火しない | AST-FIRST/VOV-ARTIFACTの初回限定安全弁 |
| 23 | 反撃予約票 | 自分の手動カードがinterruptされる | 敵の全active cardを2.0秒delayし、装備中の`interrupt_shot`のrecastを12.0秒短縮する | slot 2/3カード、counter-control | 15秒の内部cooldown。`interrupt_shot`未装備ならdelayのみ。短縮後も最低3.0秒 | ATO-STATUSの行動順反転、OSFE-CHRONOの緊急時間確保 |
| 24 | 不可侵封蝋 | 各戦闘で最初のslot 3手動カードが、投入後4.0秒間中断されず残る | 以後そのinstanceをnon-interruptibleにする | `execution`、`worldline_collapse`、`chronicle_sovereign` | 保護後はhasteを受けない。1戦闘1枚。4秒到達前は通常通り中断可能 | ATO-STATUSのBuffer、AST-DRAWBACKの強保護＋制約 |

### E. カード自動投入

| # | 仮名 | 条件 | 具体効果 | シナジー | 安全弁 | 参考パターン |
| --- | --- | --- | --- | --- | --- | --- |
| 25 | 封入式オートローダー | 手動カードを4枚解決する | loadoutに`quick_slash`があれば1枚をdelay 1.2秒で自動投入する。なければ最長recastを2.0秒短縮する | fastカード、`sequence_loader`、手動→自動のリズム | 1戦闘最大3回、`auto_depth=1`、この自動カードは他の遺物カウンタを進めない | CA-RELIC/AST-BLESS/VOV-ARTIFACTのN回発火、OSFE-AUTO |
| 26 | 緊急投入口 | 各戦闘で初めてHPが50%未満へ跨ぐ | loadoutに`quick_guard`があればcast 0.8秒・slot 0で自動投入。なければShield 6 | crisis構成、`crisis_drone_swarm`、回復までの猶予 | 1戦闘1回、`auto_depth=1`。同一update内の多段ダメージでも1回。死亡確定後は発火しない | OSFE-CHRONOの低HP緊急停止、VOV-ARTIFACTのEmergency効果 |
| 27 | 反響整流器 | 自動投入カードが解決する | 直接のsourceとなった手動カードがcooldown中なら、そのrecastを1.5秒短縮する | `sequence_loader`、`recursive_protocol`、`paradox_loop`、`drone_foundry` | source 1回のcooldownにつき最大3回。孫以降は最初の手動sourceへ遡らない。遺物由来自動投入は対象外 | VOV-ARTIFACTのSpell cooldown連動、OSFE-AUTOのイベント連鎖 |
| 28 | 廃熱プリンター | 自動投入カードが1枚解決するたび熱量+1 | 熱量3で次の自動投入をキャンセルし、代わりに最長recastを6.0秒短縮して熱量0 | 無制限`auto_turret`、recursive系をrecast構成へ接続 | キャンセルされたカードは効果・source triggerなし。1updateで複数queueする場合も決定的な投入順で判定 | VOV-ARTIFACTの自己再発火禁止、AST-DRAWBACKの強化とデッキ負債 |

### F. slot占有

| # | 仮名 | 条件 | 具体効果 | シナジー | 安全弁 | 参考パターン |
| --- | --- | --- | --- | --- | --- | --- |
| 29 | 隔離チャンバー | 遺物取得中は常時 | 自動投入専用のaux slotを1つ作る。自動投入は通常slot 0のままだがaux slotを占有し、aux内ではcastが20%短い | recursive/chainカードを速めつつ、画面上の自動カード洪水を抑える | aux占有中の追加自動投入は失敗し、待機列へ積まない。slot 3手動カードとは独立 | AST-BLESSの右端空slot追加、OSFE-SPELLのcast slot占有 |
| 30 | 第四の予備架 | 遺物取得中は常時 | `active_slot_max=4`。使用量が4の間、全自分active cardのcast進行が25%遅くなり、cooldown tickも20%遅くなる | slot 3＋slot 1、複数slot 2、過密運用 | 4枠目使用中はhaste上限を各instance 2.0秒/イベントに制限。遅延はstatusへ影響しない | AST-DRAWBACK、OSFE-SPELLのslot増加相当と保持コスト |
| 31 | 単座決闘鞘 | slot 2以上の手動カードを、他に自分active cardがない状態で投入する | そのカードのcastを15%短縮し、解決まで残りslotを予約して他の手動カードを投入不可にする | 大技を確実に早める単発構成、slot 3カード | 自動投入も予約中は失敗。対象はinterruptibleのまま。最低cast 1.0秒 | CA-FIXEDの常時利用とコスト増、OSFE-SPELLのslot保持による選択肢減少 |
| 32 | 空席利息計 | 戦闘開始後、空いている通常slot 1枠につき3.0秒経過する | 空席chargeを1得る、最大3。次の手動投入時、slot costまでchargeを消費し、1chargeにつき0.8秒haste | 待って大技を仕込む、敵timeline観測、slot 2/3カード | 戦闘開始から最初の手動解決までは蓄積速度半分。最大haste 2.4秒。自動投入は消費しない | VOV-COREの保留資源、CA-COUNTの待機判断 |
| 33 | 満員ベル | 通常slotが3/3から自然解決で3未満になる | Shield 4を得る。interruptで空いた場合はShield 2 | 複数の短いカード、slot 3大技、満員状態を意図的に作る | 4秒の内部cooldown。自動投入aux/slot 0は満員判定外。1updateで複数解決しても1回 | VOV-ARTIFACTの条件一致Block、AST-FIRSTの周期内初回 |
| 34 | 予約席タグ | 敵にinterruptibleなactive cardがあり、自分の空きが1slotだけ | interruptタグのないカードは最後の1slotを使えない。interruptカードをその予約slotへ投入するとcastを20%短縮 | `interrupt_shot`、`bulwark_cannon`、入力ミス防止とcounter構築 | 最大slotは増えない。予約は設定でON/OFF可能。敵対象が解決・中断された瞬間に解除 | OSFE-SPELLの2slot即時判断、AST-BLESSのempty slot利用、ATO-EQUIPの条件付き自動化 |

## 共通安全弁

全案に個別上限を付けても、実装層で次のルールを共有しないと組み合わせで無限化する。

1. **発生源を記録する**: `source_kind = card / relic / enemy_passive` と `source_relic_id` をイベントへ入れ、原則として遺物が生成したイベントは同じ遺物を再発火させない。
2. **同系flowを加算しない**: 同一遺物・同一side・同一modeのstop/reverseは、durationを長い方へ更新する。総合stopは連続4秒、reverseは連続3秒を初期上限とする。
3. **自動投入を二重に制限する**: 既存の1効果12枚上限に加え、遺物ごとの戦闘回数、`auto_depth`、1updateあたりの生成枚数を制限する。
4. **実効値で判定する**: delay、haste、recast短縮は要求値でなくclamp後の実際の変化量を条件カウンタへ入れる。0秒変化で発火させない。
5. **期限を可視化する**: 遺物iconのtooltipに戦闘内charge、内部cooldown、残り発動回数、予約slot状態を表示する。隠しcooldownにしない。
6. **PvPはhost authoritativeにする**: 遺物カウンタ、内部cooldown、保留status、aux slot、flow発生源をsnapshotとreconnect復元へ含める。乱数を使う案はhost RNGだけで決定する。
7. **replayへ残す**: `relic_trigger`、`relic_suppressed`、`auto_queue_cancelled`、`status_suspended` をbattle eventへ記録し、timeline before/afterと実効秒数を保存する。
8. **同時刻順を固定する**: status expiry、relic trigger、timeline flow、card resolveの順序を仕様化する。推奨は `cooldown/status tick -> status expiry relic -> timeline flow -> due card resolve -> resolve後 relic`。

## 実装優先順位

| 段階 | 遺物 | 目的 |
| --- | --- | --- |
| 1: 共通イベント基盤 | 三拍子リレー、破断スプリング、満員ベル | `card_resolved`、`interrupt_succeeded`、`slot_changed` と内部cooldownを実装・検証する |
| 2: 時間操作 | 凍結振り子、借用秒針、パラドックス抵当証 | flow非加算、実効delay/haste、発生源追跡を固める |
| 3: status残量 | 残響培養槽、半減期コンデンサ、持続交換膜 | status instance、境界通過、cleanse時残量を扱えるようにする |
| 4: 自動投入 | 緊急投入口、反響整流器、廃熱プリンター | source chain、depth、queue cancel、replay決定性を検証する |
| 5: slot構造 | 空席利息計、予約席タグ、隔離チャンバー、第四の予備架 | UI、入力可否、AI、LAN snapshotを含む構造変更を最後に行う |

最初のバランステストでは、遺物単体の勝率だけでなく、平均戦闘時間、1戦闘あたりstop/reverse秒数、実効delay/haste、interrupt成功率、自動投入枚数、3/3占有時間、recast短縮総秒数を記録する。時間操作はダメージ換算が見えにくいため、これらを取らずに報酬量だけで調整すると永続ロックか無価値のどちらかに寄りやすい。
