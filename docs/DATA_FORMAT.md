# DATA_FORMAT

## cards.json

配列形式。各要素は以下のキーを持つ。

- `id`
- `name`
- `description`
- `rarity`
- `tags`
- `loadout_cost`
- `recast_time`
- `cast_time`
- `active_slot_cost`
- `priority_modifier`
- `interruptible`
- `target_type`
- `effects`
- `upgrade_profile`

### Shield-cost effects

`consume_shield` declares shield paid immediately when a card is committed.

- `type`: `consume_shield`
- `amount`: required shield amount

The card cannot be committed when its owner has less shield than the total cost.

## enemies.json

配列形式。各要素は以下のキーを持つ。

- `id`
- `name`
- `max_hp`
- `attack`
- `defense`
- `speed`
- `cards`
- `role`
- `passive`

## starters.json

配列形式。各要素は以下のキーを持つ。

- `id`
- `name`
- `description`
- `max_hp`
- `attack`
- `defense`
- `speed`
- `cards`

## rewards.json

ラン進行で使う簡易報酬定義。

- `normal`
- `boss`

各項目は最低限 `gold`, `heal`, `rarity_pool` を持つ。

追加で以下の任意キーを持てる。

- `gold_per_area`
- `heal_per_area`
- `option_count`
- `guarantee_new`
- `rarity_pool_by_area`
