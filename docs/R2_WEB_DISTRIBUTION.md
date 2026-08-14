# Cloudflare R2 Web配信

Godot Web版は、役割を次のように分離して配信します。

- Heroku (`https://masterqueue.kazu107.xyz`): HTML、JavaScript、WASM、WebRTCシグナリング
- Cloudflare R2 (`https://qq.kazu107.xyz`): 大容量のPCK
- GitHub Actions: ソースからPCKを生成し、R2へアップロード

## R2オブジェクト

PCKは内容のSHA-256をキーにした不変オブジェクトとして保存します。

```text
objects/<sha256>.pck
releases/<git-commit>.json
releases/current.json
```

`current.json`だけを更新し、既存PCKは上書きしません。同じ内容のPCKは再利用されます。

## 最新3版とローカルアーカイブ

R2を最新3リリースに整理するときは、Windows側のアーカイブツールを使用します。GitHub ActionsはユーザーPCへ直接書き込めないため、公開ワークフローは安全のため旧版を自動削除しません。

```powershell
# 削除対象を確認するだけ
powershell -ExecutionPolicy Bypass -File tools\archive_r2_releases.ps1 `
  -ArchiveRoot "D:\qq-r2-archive" -DryRun

# 旧版をローカルへ保存する。R2からは削除しない
powershell -ExecutionPolicy Bypass -File tools\archive_r2_releases.ps1 `
  -ArchiveRoot "D:\qq-r2-archive"

# 保存済みPCKのサイズとSHA-256を検証後、R2を最新3版に整理する
powershell -ExecutionPolicy Bypass -File tools\archive_r2_releases.ps1 `
  -ArchiveRoot "D:\qq-r2-archive" -Prune
```

`R2_BUCKET_NAME`と`R2_ENDPOINT`（または`R2_ACCOUNT_ID`）を環境変数へ設定し、AWS CLIがR2認証情報を利用できる状態で実行します。AWSプロファイルを使う場合は`-Profile`を指定できます。

ローカルには次の構成で保存されます。

```text
archive-index.json
objects/<sha256>.pck
releases/<git-commit>.json
```

`-Prune`を指定しても、ローカルPCKのサイズとSHA-256が一致しない限りR2から削除しません。`current.json`と、それを含む最新3リリースが参照するPCKは常に保持します。同一PCKを複数リリースが参照している場合は1ファイルだけ保存し、保持中のリリースと共有されるPCKは削除しません。

## GitHub設定

Actions Secrets:

- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`

Actions Variables:

- `R2_ACCOUNT_ID`
- `R2_BUCKET_NAME`
- `R2_ENDPOINT`
- `R2_PUBLIC_BASE_URL`

ワークフローはR2のCORSを`https://masterqueue.kazu107.xyz`向けに自動設定します。このためAPIトークンにはバケット設定を変更できる`Admin Read & Write`権限が必要です。値はGitやログへ出力しません。

## 公開手順

`main`へゲーム内容をpushすると、`.github/workflows/publish-web-r2.yml`が次を実行します。

1. Godot 4.6.2をキャッシュまたは取得する。
2. `--export-pack`でPCKだけを生成する。
3. PCKのサイズとSHA-256を含むマニフェストを生成する。
4. PCK、コミット別マニフェスト、`current.json`の順にR2へアップロードする。
5. 公開URL、内容、Herokuオリジン向けCORSを検証する。

HerokuのGitHub自動デプロイは従来どおり利用します。R2公開処理が一時的に遅れても、`current.json`は直前の正常なPCKを示すため、公開中のゲームは継続して起動できます。

`build/web/index.pck`はGit管理およびHeroku slugから除外し、GitHub Actionsがソースから生成してR2へ直接配置します。ローカルのWebビルドでは同じパスへ生成できますが、Gitには追加されません。

## ローカル確認

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_web.ps1
powershell -ExecutionPolicy Bypass -File tools\serve_web.ps1
```

`localhost`と`127.0.0.1`では自動的に`build/web/index.pck`を使います。R2を明示的に試す場合は`?pack=remote`、ローカルPCKを強制する場合は`?pack=local`をURLへ追加します。

## ロールバック

問題のない過去の`releases/<git-commit>.json`と同じ内容を`releases/current.json`へ再配置すると、HTMLやHerokuを再デプロイせずにPCKを戻せます。Web対戦ではゲーム内容のハッシュを照合するため、異なる内容のクライアントは同じルームへ参加できません。
