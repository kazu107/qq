# Godot版 リアルタイム・カードタクティクス Codex実装仕様書 v1.0

## 0. この仕様書の目的
この文書は、Codex CLIにGodot版のリアルタイムカードバトルゲームを段階的に実装させるための実装仕様書である。

対象ゲームは、以下の特徴を持つ。

- リアルタイム進行
- カードごとのリキャスト時間
- カードごとの発動時間
- 発動予定タイムライン / リアルタイム・マスターキュー
- 同時展開スロット
- Slow Mode
- ローグライト進行
- ラン中成長
- 永続成長

Codexに「全部作って」と一括依頼するのではなく、本書に沿ってフェーズ単位で実装させる。

---

## 1. 採用技術
### 1.1 エンジン
- Godot 4.6 系

### 1.2 言語
- GDScript

### 1.3 画面
- 2D UI中心
- 16:9
- 初期解像度: 1920x1080

### 1.4 対象プラットフォーム
- MVP: Windows PC
- 将来: Web / Linux / macOS は検討

### 1.5 実装方針
- Godotシーンとロジックを分離する
- ルール計算は `src/core/` に置く
- UIノードは状態を直接所有しない
- データは `.tres` より先に `.json` で扱う
- MVPでは全データを `res://data/*.json` に置く
- 後でResource化してもよい

---

## 2. ゲーム概要
### 2.1 ジャンル
リアルタイム・カードタクティクス / ローグライト

### 2.2 一言コンセプト
**カードをいつ場に出すか、どの発動を遅らせるか、どの大技を通すかで戦うリアルタイム戦術カードバトル。**

### 2.3 コア体験
プレイヤーは、リアルタイムで進行する戦闘中にカードを場へ投入する。  
カードは即時発動するのではなく、カードごとの `cast_time` 後に発動する。  
発動後は `recast_time` の間、再使用できない。

場に出ているカードは、発動予定時刻に基づいてタイムラインへ並ぶ。  
一部カードは、自分や敵の発動予定時刻を早めたり遅らせたりできる。

プレイヤーは以下を判断する。

- 今カードを出すべきか
- 大技の発動を待つべきか
- 敵の大技を遅延 / 中断するべきか
- 防御を即時に出すべきか
- Slow Modeを使って判断するべきか

---

## 3. MVP範囲
### 3.1 MVPで作るもの
- 1vs1リアルタイム戦闘
- カード15〜20枚
- 敵3〜4体
- ボス1体
- activeSlotMax = 3
- Slow Mode
- タイムライン表示
- 戦闘ログ
- 簡易ローグライト進行
- ノードマップ
- 戦闘報酬
- 鍛冶屋
- ショップ
- セーブ / ロード

### 3.2 MVPで作らないもの
- オンライン対戦
- 多人数戦闘
- 複雑なアニメーション
- 3D演出
- 分岐強化
- 複数セーブスロット
- 高度なカード生成
- フルボイス

---

## 4. プロジェクト構成
### 4.1 Godotフォルダ構成
```text
res://
  project.godot
  README.md
  docs/
    GAME_SPEC.md
    CODEX_TASKS.md
    DATA_FORMAT.md
  data/
    cards.json
    enemies.json
    relics.json
    rewards.json
    starters.json
    meta_progress.json
  scenes/
    boot/
      Boot.tscn
    title/
      Title.tscn
    hub/
      Hub.tscn
    run_setup/
      RunSetup.tscn
    map/
      Map.tscn
    battle/
      Battle.tscn
    reward/
      Reward.tscn
    facility/
      Facility.tscn
    result/
      RunResult.tscn
  src/
    autoload/
      Game.gd
      Database.gd
      SaveManager.gd
      SceneRouter.gd
      AudioManager.gd
    core/
      definitions/
        CardDef.gd
        EnemyDef.gd
        RelicDef.gd
      runtime/
        BattleState.gd
        UnitState.gd
        CardRuntimeState.gd
        ActiveCardInstance.gd
        TimelineEntry.gd
        RunState.gd
      battle/
        RealtimeBattleEngine.gd
        TimelineResolver.gd
        CardEffectResolver.gd
        DamageResolver.gd
        EnemyAI.gd
        SlowModeController.gd
      run/
        MapGenerator.gd
        RewardResolver.gd
        ForgeService.gd
        ShopService.gd
        RunSummaryResolver.gd
      save/
        SaveData.gd
        ReplayData.gd
        BattleEventRecord.gd
    ui/
      battle/
        BattleScreen.gd
        CardButton.gd
        CardHandPanel.gd
        ActiveSlotPanel.gd
        TimelinePanel.gd
        UnitPanel.gd
        LogPanel.gd
      map/
        MapScreen.gd
        MapNodeButton.gd
      common/
        Tooltip.gd
        ConfirmDialog.gd
  assets/
    art/
    icons/
    fonts/
    audio/
  tests/
    test_timeline_resolver.gd
    test_battle_engine.gd
    test_card_effects.gd
    test_save_load.gd
```

### 4.2 Autoload
以下をProject Settings > Autoloadに登録する。

- `Game.gd`
- `Database.gd`
- `SaveManager.gd`
- `SceneRouter.gd`
- `AudioManager.gd`

---

## 5. 主要シーン
### 5.1 Boot.tscn
役割:
- データ読み込み
- セーブ読み込み
- 初期化
- Titleへ遷移

### 5.2 Title.tscn
UI:
- New Game
- Continue
- Settings
- Quit

### 5.3 Hub.tscn
UI:
- Run Start
- Meta Progress
- Card Library
- Settings

### 5.4 RunSetup.tscn
UI:
- 初期ロードアウト選択
- カード一覧
- スタートボタン

### 5.5 Map.tscn
UI:
- ノードマップ
- 現在HP
- 通貨
- 所持カード概要
- 次ノード選択

### 5.6 Battle.tscn
最重要シーン。  
中央に戦場、左右に情報パネル、下部にタイムラインを置く。

構成:
- 左: 敵情報
- 中央: 戦場 / アクティブカード
- 右: プレイヤー情報 / カード一覧
- 下: タイムライン / ログ

### 5.7 Reward.tscn
UI:
- カード報酬3択
- 通貨
- 回復
- スキップ

### 5.8 Facility.tscn
種類:
- Shop
- Forge
- Heal
- Event

### 5.9 RunResult.tscn
UI:
- 到達エリア
- 撃破数
- 獲得ポイント
- Hubへ戻る

---

## 6. 戦闘仕様
### 6.1 基本ルール
- 1vs1
- リアルタイム進行
- プレイヤーと敵はロードアウトを持つ
- カードはReady状態なら使用可能
- 使用後、発動準備に入り、一定時間後に発動
- 発動後、リキャスト待ちになる

### 6.2 カード状態
```text
READY
  ↓ use
PREPARING
  ↓ cast_time elapsed
RESOLVING
  ↓ effect done
COOLDOWN
  ↓ recast_time elapsed
READY
```

追加状態:
- DISABLED: 封技や特殊効果で一時使用不可
- INTERRUPTED: 中断された状態

### 6.3 戦闘の時間
- BattleEngineは `_process(delta)` ではなく、`update(delta)` を持つ
- BattleScreenが毎フレーム `battle_engine.update(delta * time_scale)` を呼ぶ
- Slow Mode中は `time_scale = 0.3`
- デバッグPause中は `time_scale = 0.0`

### 6.4 activeSlot
同時に場へ出せるカード数を制限する。

- `active_slot_max = 3`
- 軽量カード: slot 1
- 中量カード: slot 1
- 重量カード: slot 2
- 超重量カード: slot 3

カード使用時に、空きスロットが足りない場合は使用不可。

### 6.5 タイムライン
カードを出したとき、以下を計算する。

```text
scheduled_time = battle_time + cast_time + delay_modifier - haste_modifier
sort_key = scheduled_time - priority_modifier
```

発動順は `sort_key` の小さい順。  
同値時は以下で決定。

1. priority_modifier が高い方
2. 使用者の速度が高い方
3. instance_id が小さい方

### 6.6 発動処理
BattleEngineは毎フレーム、タイムライン先頭の `scheduled_time <= battle_time` になったカードを解決する。

処理順:
1. TimelineEntryを取り出す
2. CardEffectResolverで効果解決
3. ログを記録
4. ActiveSlotから除去
5. カードをCooldownへ移行
6. 勝敗判定

### 6.7 Slow Mode
- Space長押しで有効
- 時間速度を30%にする
- UIは通常通り操作可能
- MVPではゲージ制にしない
- 将来、スローゲージや永続成長で拡張可能

---

## 7. カードパラメータ
### 7.1 CardDef
カード定義はJSONで管理する。

必須フィールド:
```json
{
  "id": "quick_slash",
  "name": "クイックスラッシュ",
  "rarity": "common",
  "tags": ["attack", "fast"],
  "loadout_cost": 2,
  "recast_time": 2.0,
  "cast_time": 0.3,
  "active_slot_cost": 1,
  "priority_modifier": 0.1,
  "interruptible": false,
  "target_type": "enemy",
  "effects": []
}
```

### 7.2 主なフィールド
- id
- name
- description
- rarity
- tags
- loadout_cost
- recast_time
- cast_time
- active_slot_cost
- priority_modifier
- interruptible
- target_type
- effects
- upgrade_profile

### 7.3 Effect
```json
{
  "type": "deal_damage",
  "amount": 6,
  "duration": 0,
  "status": "none",
  "target": "enemy"
}
```

EffectType:
- deal_damage
- gain_shield
- heal
- apply_status
- remove_status
- delay_enemy_active_card
- haste_own_active_card
- reduce_recast
- interrupt_card
- modify_attack
- modify_defense
- modify_speed

---

## 8. MVPカード一覧
### 8.1 Common
#### quick_slash
- recast 2.0
- cast 0.3
- slot 1
- 効果: 4ダメージ

#### strike
- recast 3.0
- cast 0.6
- slot 1
- 効果: 6ダメージ

#### guard
- recast 3.0
- cast 0.2
- slot 1
- 効果: シールド8

#### heavy_swing
- recast 7.0
- cast 2.2
- slot 2
- interruptible true
- 効果: 14ダメージ

#### delay_step
- recast 6.0
- cast 0.5
- slot 1
- 効果: 敵アクティブカード1枚のscheduled_time +1.0秒

#### haste_focus
- recast 5.0
- cast 0.4
- slot 1
- 効果: 自アクティブカード1枚のscheduled_time -0.6秒

#### weak_shot
- recast 5.0
- cast 0.6
- slot 1
- 効果: 2ダメージ + 弱体付与

#### bleed_cut
- recast 5.0
- cast 0.7
- slot 1
- 効果: 4ダメージ + 出血付与

#### quick_guard
- recast 4.0
- cast 0.1
- slot 1
- 効果: シールド5

#### reload
- recast 8.0
- cast 0.5
- slot 1
- 効果: カード1枚の残りリキャストを1.0秒短縮

### 8.2 Rare
#### assault
- recast 6.0
- cast 0.8
- slot 1
- 効果: 10ダメージ

#### barrier_deploy
- recast 9.0
- cast 1.5
- slot 2
- 効果: シールド18 + 防御+1

#### interrupt_shot
- recast 9.0
- cast 0.4
- slot 1
- 効果: interruptibleな敵カード1枚を中断

#### time_buy
- recast 8.0
- cast 0.7
- slot 1
- 効果: 敵アクティブカード全体のscheduled_time +0.5秒

#### recirculate
- recast 10.0
- cast 0.8
- slot 1
- 効果: 直前に使ったカードのリキャストを2.0秒短縮

### 8.3 Epic
#### execution
- recast 14.0
- cast 2.5
- slot 3
- interruptible true
- 効果: 24ダメージ。敵HP50%以下なら+10

#### fortify
- recast 14.0
- cast 2.8
- slot 3
- 効果: シールド30 + 防御+3

#### time_flow_control
- recast 15.0
- cast 1.0
- slot 2
- 効果: 自アクティブカード1枚を-1.0秒、敵アクティブカード1枚を+1.0秒

#### blood_chain
- recast 12.0
- cast 1.8
- slot 2
- 効果: 12ダメージ。出血相手に追加12

#### over_reload
- recast 16.0
- cast 1.2
- slot 2
- 効果: 全カードの残りリキャストを1.0秒短縮

---

## 9. ステータス・状態異常
### 9.1 UnitState
- hp
- max_hp
- shield
- attack
- defense
- speed
- statuses
- active_slots
- card_runtime_states

### 9.2 ダメージ計算
```text
raw = card_power + attacker.attack
mitigated = max(1, raw - defender.defense)
shield_absorb = min(defender.shield, mitigated)
hp_damage = mitigated - shield_absorb
```

### 9.3 状態異常
#### bleed
- 1秒ごとに1ダメージ
- duration中継続

#### weak
- 攻撃-2

#### slow
- cast_time補正 +10%

#### vulnerable
- 受けるダメージ+3

---

## 10. 敵AI
### 10.1 基本方針
敵AIは高度な探索をしない。  
カードごとにスコアを付け、使用可能でスロットが空いていれば使用する。

### 10.2 AI更新
- `think_interval = 0.4秒`
- 0.4秒ごとに行動判断
- 使用可能カードを評価
- 最もスコアが高いカードを使う

### 10.3 評価要素
- プレイヤーHPが低い → 攻撃評価上昇
- 敵HPが低い → 防御評価上昇
- プレイヤーが大技準備中 → interrupt / delay評価上昇
- 敵のアクティブカードが多い → haste評価上昇
- プレイヤーに出血がある → 追撃評価上昇

---

## 11. 敵一覧
### 11.1 scout
- HP 35
- 攻撃 2
- 防御 0
- 速度 8
- カード: quick_slash, quick_slash, haste_focus, guard
- 役割: 高速型

### 11.2 brute
- HP 55
- 攻撃 5
- 防御 1
- 速度 3
- カード: heavy_swing, strike, weak_shot, guard
- 役割: 重量攻撃型

### 11.3 disruptor
- HP 42
- 攻撃 2
- 防御 1
- 速度 6
- カード: delay_step, interrupt_shot, quick_slash, guard
- 役割: 妨害型

### 11.4 guardian
- HP 65
- 攻撃 3
- 防御 4
- 速度 3
- カード: guard, barrier_deploy, strike, fortify
- 役割: 防御型

### 11.5 boss_timekeeper
- HP 120
- 攻撃 6
- 防御 3
- 速度 6
- カード: delay_step, time_buy, time_flow_control, assault, guard, over_reload
- パッシブ: 10秒ごとに敵アクティブカード1枚を+0.8秒遅延
- 役割: タイムライン支配型ボス

---

## 12. ローグライト進行
### 12.1 ラン構造
- 3エリア
- 各エリアに複数ノード
- 最終エリアにボス

### 12.2 ノード
- normal_battle
- elite_battle
- shop
- forge
- heal
- event
- hazard
- boss

### 12.3 戦闘報酬
通常戦:
- カード3択
- 通貨
- 小回復
- スキップ

強敵:
- Rareカード
- 遺物
- 強化

ボス:
- 大量通貨
- 永続成長ポイント
- Epic候補

### 12.4 危険地帯
- 3〜5連戦
- 途中撤退可能
- クリア済み報酬は保持
- 深いほど高報酬

---

## 13. カード強化
### 13.1 強化段階
- Tier0
- Tier1
- Tier2
- Tier3

### 13.2 強化内容
リアルタイム版の強化は以下を中心にする。

- damage +
- shield +
- recast_time短縮
- cast_time短縮
- delay量増加
- haste量増加
- interrupt条件改善

### 13.3 鍛冶屋
- 候補3枚提示
- 1枚を1段階強化
- Tier3は候補外

---

## 14. UI仕様
### 14.1 Battle UI
中央:
- プレイヤー
- 敵
- アクティブカード表示
- 発動バー

左:
- 敵ステータス
- 敵カードリキャスト
- 敵アクティブスロット

右:
- プレイヤーステータス
- プレイヤーカード一覧
- 自アクティブスロット

下:
- タイムライン
- ログ

### 14.2 カードボタン
表示:
- カード名
- recast残り
- cast時間
- slotCost
- 使用可否

### 14.3 タイムライン
表示:
- 発動予定順
- 残り時間
- カード所有者
- 遅延 / 加速の変化

---

## 15. セーブ・ロード
### 15.1 SaveData
- current_run
- meta_progress
- settings

### 15.2 RunState
- seed
- current_area
- map_state
- player_hp
- player_cards
- card_upgrades
- relics
- gold

### 15.3 保存場所
- `user://save.json`

---

## 16. リプレイ・ログ
### 16.1 BattleEventRecord
- time
- event_type
- actor_id
- card_id
- target_id
- result
- hp_delta
- shield_delta
- timeline_before
- timeline_after

### 16.2 目的
- バグ再現
- バランス調整
- Codexによるテスト生成

---

## 17. Codex実装フェーズ
### Phase 0: プロジェクト初期化
Codexにやらせる内容:
- フォルダ構成作成
- README作成
- data雛形作成
- Autoload雛形作成

完了条件:
- Godotでプロジェクトが開く
- エラーなし

### Phase 1: データ読み込み
内容:
- Database.gd
- cards.json読み込み
- enemies.json読み込み
- CardDef生成

完了条件:
- 起動時にカード一覧をロードできる
- 不正データ時にエラー表示

### Phase 2: 戦闘コア
内容:
- BattleState
- UnitState
- CardRuntimeState
- ActiveCardInstance
- TimelineResolver
- RealtimeBattleEngine

完了条件:
- CLIまたはGodot上で quick_slash が発動し、cooldownに入る
- scheduled_time順で解決される

### Phase 3: カード効果
内容:
- DamageResolver
- CardEffectResolver
- 状態異常
- shield / hp処理

完了条件:
- 攻撃、防御、遅延、加速、中断が動く

### Phase 4: Battle UI
内容:
- Battle.tscn
- CardButton
- TimelinePanel
- UnitPanel
- LogPanel

完了条件:
- カードをクリックして場に出せる
- タイムラインが更新される
- 発動後にログが出る

### Phase 5: 敵AI
内容:
- EnemyAI
- think_interval
- 敵カード使用

完了条件:
- scoutが自動でカードを出す
- 1vs1戦闘が最後まで進む

### Phase 6: ローグライト進行
内容:
- MapGenerator
- RewardResolver
- RunState
- Reward画面
- Forge / Shop

完了条件:
- 戦闘後に報酬を選べる
- ノードを進める

### Phase 7: Save / Load
内容:
- SaveManager
- save.json
- Continue

完了条件:
- ラン途中で保存・復帰できる

### Phase 8: 調整・デバッグ
内容:
- DebugBattleLauncher
- seed固定
- battle log出力

完了条件:
- 任意敵と即戦闘できる
- ログがJSONで出力できる

---

## 18. 最初にCodexへ渡すプロンプト
```text
あなたはGodot 4.6 / GDScriptに詳しいゲーム開発エージェントです。
このリポジトリは、リアルタイム・カードタクティクスのGodotプロジェクトです。
以下の方針を厳守してください。

- Godot 4.6想定
- GDScriptで実装
- 2D UI中心
- ロジックとUIを分離
- BattleEngineはUIに依存しない
- まずMVPを作る
- 変更前に既存ファイルを確認
- 1回の作業でやりすぎない
- 実装後にGodotで構文エラーが出ないようにする

最初のタスクとして、以下を実行してください。

1. README.md を作成
2. docs/GAME_SPEC.md, docs/CODEX_TASKS.md, docs/DATA_FORMAT.md を作成
3. data/cards.json と data/enemies.json の初期データを作成
4. src/autoload/Database.gd を作成
5. src/autoload/Game.gd を作成
6. src/core/definitions/CardDef.gd を作成
7. src/core/definitions/EnemyDef.gd を作成
8. Godotで読み込めるように型付きGDScriptで実装
9. Database.gd に cards.json / enemies.json を読み込む関数を作成
10. 読み込んだ件数をprintできる簡易確認関数を作成

受け入れ条件:
- Godotエディタで構文エラーがない
- Database.load_all() を呼ぶとカードと敵が読み込まれる
- 不正JSON時に分かりやすいエラーを出す
- 今回はBattle実装には入らない
```

---

## 19. Codex運用ルール
### 19.1 必ず守ること
- 1回の依頼で複数フェーズを混ぜない
- Godotプロジェクトを開ける状態を常に保つ
- 実装後は必ず差分確認
- 動いたらコミット

### 19.2 依頼の書き方
毎回以下を書く。

- 目的
- 対象ファイル
- 実装範囲
- 受け入れ条件
- 今回やらないこと

### 19.3 コミット粒度
- Phase単位では大きすぎる
- Task単位でコミット
- 例: `feat: add card database loader`

---

## 20. 必要な追加ファイル
Codexに作らせるべきファイル:

- README.md
- docs/GAME_SPEC.md
- docs/CODEX_TASKS.md
- docs/DATA_FORMAT.md
- .gitignore
- data/cards.json
- data/enemies.json
- data/starters.json
- data/rewards.json
- data/meta_progress.json
- tests/README.md

---

## 21. 最終方針
このGodot版は、ターン制版の単純移植ではなく、リアルタイム戦闘に特化した派生版として実装する。

最初に作るべきものは、ローグライト全体ではなく、以下である。

1. データ読み込み
2. 1vs1戦闘コア
3. タイムライン表示
4. カード使用UI
5. 敵AI
6. 戦闘後報酬

この順で作れば、Codex CLIに任せても破綻しにくい。

