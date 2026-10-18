# Google・GitHubログインの設定

## 今回実装した範囲

- Web版ハブ右上 → ゲーム内のアカウントパネルを開きます。本人確認のみGoogle/GitHubの認証ウィンドウを使用します。
- Google / GitHubで本人確認 → 初回のみユーザー名入力 → 登録完了。
- ユーザー名は3〜20文字。日本語・英数字・`_`・`-`に対応します。全角半角を正規化し、大文字小文字だけ異なる名前は重複とします。予約名と制御文字は使用できません。
- 再ログインでは同じアカウントを復元します。セッションは14日間で失効し、ログアウトでも破棄します。
- PostgreSQLにアカウントとセッションを永続保存するため、Web dynoの再起動でユーザー登録が消えることはありません。
- 未設定・DB障害時もローカルプレイと既存Web対戦は利用できます。

**未実装:** アカウント連携・統合、登録後のユーザー名変更、ネイティブGodot版からのログイン。ランキング専用ランの投稿・検証は[ランキング仕様](RANKINGS.md)を参照してください。
通常のラン・メタ進行のクラウド保存と初回のゲスト引き継ぎは[クラウド保存仕様](CLOUD_SAVES.md)を参照してください。GoogleとGitHubは別アカウントです。

## 1. PostgreSQLを用意

永続的なPostgreSQLの接続URLを用意し、HerokuのConfig Varsへ`DATABASE_URL`として設定します。
Heroku Postgresまたは外部のPostgreSQLを使用できます。**DBは料金が発生する場合があるため、プランを確認してから利用者側で作成してください。この実装では自動契約しません。**

外部DBへの接続はTLS証明書を検証します。HerokuではOSのCAバンドルを使用します。
独自CAの場合は、信頼するPEM証明書をbase64化して`AUTH_DATABASE_CA_BASE64`に指定します。
接続文字列の`sslmode=no-verify`などでは検証を無効化しません。
非本番環境のlocalhost/127.0.0.1だけはTLSなしで接続できます。
DBの接続ユーザーには今回のテーブル・インデックスの作成権限が必要です。

## 2. Google OAuthクライアントを作成

1. [Google Cloud Console](https://console.cloud.google.com/)で対象プロジェクトを選択または作成します。
2. Google Auth PlatformのBranding / Audienceを設定します。一般公開する場合はExternalを選び、テスト中は自分をテストユーザーへ追加します。
3. ClientsでOAuthクライアントを作成し、アプリケーションの種類を**Web application**にします。
4. 承認済みリダイレクトURIに次の値を**完全一致**で登録します。

```text
https://masterqueue.kazu107.xyz/auth/google/callback
```

5. Client IDを`GOOGLE_CLIENT_ID`、Client Secretを`GOOGLE_CLIENT_SECRET`へ設定します。
6. 本公開前に、同意画面の公開状態・必要なドメイン確認・利用規約/プライバシーポリシーなど、コンソールに示される要件を確認します。

サーバーは`openid`だけを要求し、メール・プロフィール・Driveなどの権限は要求しません。
Googleの固定`sub`を識別子に使用し、IDトークンの署名・issuer・audience・有効期限・nonceを検証します。
手順の詳細は[Google OpenID Connect公式ドキュメント](https://developers.google.com/identity/openid-connect/openid-connect)を参照してください。

## 3. GitHub OAuth Appを作成

1. [GitHub Developer settings → OAuth Apps](https://github.com/settings/developers)でNew OAuth Appを作成します。今回はGitHub Appではなく**OAuth App**です。
2. Application nameを`QueueQuest`、Homepage URLを`https://masterqueue.kazu107.xyz/`にします。
3. Authorization callback URLを次の値にします。

```text
https://masterqueue.kazu107.xyz/auth/github/callback
```

4. Client IDと新しく生成したClient Secretを、それぞれ`GITHUB_CLIENT_ID`・`GITHUB_CLIENT_SECRET`へ設定します。

追加scopeは要求せず、ログイン後に公開ユーザー情報から固定の数値`id`を確認します。
リポジトリ操作や非公開メールの権限は不要です。
参考: [GitHub OAuth AppのWeb application flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)。

## 4. HerokuのConfig Varsを設定

Herokuダッシュボード → 対象アプリ → Settings → Reveal Config Varsで設定してください。
Secretをリポジトリ、GitHubの公開Variables、ゲームのJSON、PCK、スクリーンショットなどへ含めないでください。
GitHub ActionsのR2用Secretsとは別に、**Herokuの実行環境**への設定が必要です。

| キー | 値 |
| --- | --- |
| `PUBLIC_ORIGIN` | `https://masterqueue.kazu107.xyz`（パスなし） |
| `DATABASE_URL` | 用意したPostgreSQL接続URL |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Googleで発行した値 |
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | GitHubで発行した値 |
| `TRUST_PROXY` | `1`（Heroku router配下） |
| `AUTH_ENABLED` | 最後に`true`へ変更 |

片方のプロバイダーだけを設定して有効化することもできます。未設定のログイン方法は無効になります。
OAuthクライアントとDBの準備が終わるまでは`AUTH_ENABLED`を未設定または`false`にしてください。

### テーブル作成

`Procfile`のreleaseフェーズで、`AUTH_ENABLED=true`のときだけ追加マイグレーションを実行します。
**すでにデプロイ済みのアプリでConfig Varsだけ変更した場合、releaseコマンドは自動実行されません。** その場合はHeroku CLIで次を実行します。

```powershell
heroku run npm run migrate:accounts -a <アプリ名>
```

`ACCOUNT_SCHEMA_MIGRATION_OK`を確認してください。繰り返し実行できます。既存データを変更せず、`qq_accounts_*`の4テーブル、`qq_ranked_*`の3テーブル、クラウド保存2テーブル、ゲスト移行記録1テーブルとインデックスを作成します。
設定後のデプロイでは自動実行されます。失敗したreleaseは公開しません。
`AUTH_ENABLED=false`ならDB不要でスキップし、これまでどおりデプロイできます。

### 確認手順

1. `/api/account`を開いて`available: true`と、設定したproviderの`enabled: true`を確認します。Secretや接続URLは返しません。
2. ハブ右上のログインを押し、ポップアップを許可します。
3. GoogleまたはGitHubで本人確認し、初回ユーザー名を設定します。
4. 「ゲームに戻る」で元のゲームへ戻り、右上が「ログイン中」になることを確認します。
5. ログアウト → 再ログインで同じユーザー名を復元できることを確認します。
6. dyno再起動後にもアカウントが維持されること、ログイン前のローカルセーブが変わっていないことを確認します。

### GitHubの発行元の検証

GitHubのコールバックには`iss=https://github.com/login/oauth`が含まれます。発行元は`https://github.com`ではありません。
QQ-0.45.1から、この値を照合するよう修正しました。古いバージョンで認証直後に「ログインできませんでした」と表示された場合は、更新後に新しくログインを開始してください。以前のコールバックURLを再利用しないでください。
Config Varsの追加やSecretの再発行は、この修正だけなら不要です。発行元の検証を無効にする対応は行いません。
参考: [GitHub公式の認証メタデータとIssuer](https://docs.github.com/en/apps/github-authentication-discovery-endpoints)。

端末間でログインしてもセーブは共有されません。将来ランキングを追加する際には、クライアントが送ったスコアをそのまま信用せず、別途サーバー検証・不正対策が必要です。

## 開発・テスト

Node.js 24を使用します。`.env.example`は設定一覧であり、自動読み込みしません。
環境変数はPowerShellまたはホスティング側で指定します。`.env`はGit対象外です。
ローカルOAuthを試す場合は、非本番用のOAuthクライアントに`http://127.0.0.1:8060/auth/<provider>/callback`を別途登録してください。
本番クライアントのURIを安易に置き換えないでください。

```powershell
npm.cmd ci
npm.cmd test
```

DBなしでも静的配信・無効状態・バリデーション・Web対戦のテストが通り、実DBのテストだけ明示的にスキップします。
実DBテストには、**使い捨てのローカルDB `qq_auth_tests`**を用意します。このDB内のアカウントテーブルだけを初期化します。他のDB名や外部ホストは拒否します。

```powershell
$env:QQ_AUTH_TEST_DATABASE_URL='postgres://postgres:<テスト専用パスワード>@127.0.0.1:<ポート>/qq_auth_tests'
npm.cmd test
$env:QQ_NODE_MODULES='<Playwrightのnode_modulesフォルダ>'
node tools/web_account_review.mjs
```

Google/GitHubの実アカウント・本番Secretは使わず、ローカル模擬OAuthサーバーと実PostgreSQLで検証します。
Googleの署名/nonce/audience/issuer/期限不正、PKCE/state不正、再利用、セッション期限、CSRF、名前重複と同時登録をテストします。
開発者用の偽認証を本番ルートや環境変数に追加していません。

## 運用上の注意

- HTTPSの`__Host-`付きHttpOnly / SameSite=Lax cookieを使用し、生のセッション値はDBへ保存せずSHA-256だけを保存します。
- OAuth一時状態はDBに10分間保存し、ブラウザcookieと結び付けて一度だけ消費します。複数dynoでも同じDBを使えます。
- ログイン試行のレート制限はdyno内です。大規模運用時にはエッジ側や共有ストア側の制限も追加してください。
- 固定の`PUBLIC_ORIGIN`を使うので、別ホストにアクセスして認証することはできません。カスタムドメインを正規URLとして使ってください。
- DBの定期バックアップ・削除依頼対応・公開用のプライバシーポリシーは運営側で用意してください。アカウントの自己削除画面はまだありません。
- 外部アクセストークンは本人確認中だけメモリで使い、DB・ゲームセーブ・ログへ保存しません。
- Secretが漏れた場合はプロバイダー側で失効・再発行し、Herokuへ更新してください。

## 認証ボタンの素材

Googleのボタンには[公式のGアイコン](https://developers.google.com/static/identity/images/g-logo.png)を改変せず使用しています。
Google Sans Mediumの英語ラベル用サブセットはGoogle Fontsの公式配信から取得し、`server/accounts/public/GoogleSans-OFL.txt`にSIL OFLライセンスを同梱しています。
アカウント画面の素材は同一オリジンから配信し、外部フォントサービスへの実行時アクセスはありません。
Googleの商標素材は自前のゲームアートとは別扱いです。[Googleのボタン・ブランドガイドライン](https://developers.google.com/identity/branding-guidelines)に従って使用してください。
