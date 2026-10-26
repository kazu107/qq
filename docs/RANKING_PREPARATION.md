# ランキングの準備と開始

`qq_ranked_control.state` が `preparing` の間は、シーズンを作成・移行せず、
挑戦受付、ログ追記、確定、検証結果の公開を停止します。
閲覧、リリース時のマイグレーション、再起動、ルール改訂では解除されません。
通常・無限・アリーナのローカルプレイとアカウント保存は引き続き利用できます。

## 今回のリセット

2026-10-26のユーザー指示に基づくランキング限定の全削除です。
既存シーズン・挑戦・操作ログをローカルへ退避し、読み戻してSHA-256を照合した後、
同じスナップショットのままであることをDBトランザクション内でも確認します。
削除対象は `qq_ranked_commands`、`qq_ranked_runs`、`qq_ranked_seasons` のみです。
アカウント、認証情報、セッション、クラウド保存、ゲスト引き継ぎは削除しません。
削除前後で保護テーブルの件数と内容ハッシュが一致しない場合はロールバックします。

```powershell
node tools/ranking_maintenance.mjs reset-all-with-backup CONFIRM-RANKING-ONLY
```

退避先はGit管理外の `tools/.local/ranking-reset/*-all-seasons.json` です。
バックアップにはユーザーIDとランキング操作記録が含まれるので公開しないでください。
リセット後は `preparing`、次回番号1、新しい管理世代IDとなり、シーズンは未作成です。

## 将来の開始

**明示的な開始指示があるまで、以下の開始コマンドを実行しないでください。**

```powershell
node tools/ranking_maintenance.mjs inspect
node tools/ranking_maintenance.mjs start-season infinite-N GENERATION-UUID
```

`infinite-N` はその時点の `server/ranking/rules.json` と一致する改訂番号、
`GENERATION-UUID` は直前の `inspect` の値です。古い世代や異なる改訂では拒否します。
開始は原子的に行われ、同時実行や再送でシーズンが二重に増えることはありません。
開始後は、ゲーム内容の変更時に次の番号へ移行します。月替わりでは移行しません。
準備中もゲーム内容変更時にはルール改訂番号を増やしますが、シーズン番号は増えません。

停止のみ行う場合は `node tools/ranking_maintenance.mjs pause` です。
ランキングの準備状態はDBが管理するため、開始後にゲームを再配布する必要はありません。
