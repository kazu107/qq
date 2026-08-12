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

## ローカル確認

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_web.ps1
powershell -ExecutionPolicy Bypass -File tools\serve_web.ps1
```

`localhost`と`127.0.0.1`では自動的に`build/web/index.pck`を使います。R2を明示的に試す場合は`?pack=remote`、ローカルPCKを強制する場合は`?pack=local`をURLへ追加します。

## ロールバック

問題のない過去の`releases/<git-commit>.json`と同じ内容を`releases/current.json`へ再配置すると、HTMLやHerokuを再デプロイせずにPCKを戻せます。Web対戦ではゲーム内容のハッシュを照合するため、異なる内容のクライアントは同じルームへ参加できません。
