# Web対戦仕様

## 構成

- ブラウザ同士のゲーム通信はGodotの`WebRTCMultiplayerPeer`を使用する。
- HerokuのNodeプロセスは`build/web`を配信し、同じホストの`/signal`でWebSocketシグナリングを行う。
- ルームは6文字コード・最大2人。ホストはPeer ID 1、ゲストはPeer ID 2。
- 既存のホスト権威型RPCを維持し、カード操作、戦闘スナップショット、アリーナ準備、報酬を同期する。
- シグナリング参加時にプロトコル版とカード/遺物データのSHA-256を照合する。

LAN探索、ENet、UPnP、EOS認証、Client Secretは使用しません。

## 対戦手順

1. 両者が同じ公開URLをブラウザで開く。
2. ハブの`Web対戦`を開く。
3. ホストがルームを作成し、表示されたコードを相手へ共有する。
4. ゲストが同じコードで参加する。
5. 両者が準備を完了するとアリーナ準備へ進む。
6. 戦闘画面では両者が`戦闘開始`を押し、3秒カウントダウン後に開始する。

## Heroku

GitHub連携の自動デプロイでは、リポジトリルートの以下を使用します。

- `package.json`: Node.js 24と`ws`依存関係。
- `Procfile`: `web: node server/server.js`。
- `build/web`: Gitに含めたGodot Webリリースビルド。
- `/health`: 稼働確認用JSON。
- `/signal`: WebRTCシグナリングWebSocket。

Heroku側で追加コマンドは不要です。デプロイ後に`https://<app-name>.herokuapp.com/health`が`{"ok":true,...}`を返すことを確認します。

## STUNとTURN

既定ではGoogleとCloudflareの公開STUNを使用します。多くの家庭回線ではP2P接続できますが、対称NATや厳しい企業ネットワークではTURNが必要です。その場合だけHeroku Config Varsへ設定します。

```text
TURN_URL=turns:relay.example.com:5349
TURN_USERNAME=...
TURN_CREDENTIAL=...
```

TURN認証情報はNodeサーバーから接続時だけ配布され、GitやWebビルドには埋め込みません。TURNを設定しない構成ではHerokuはシグナリングのみを担当するため、実際の対戦データはHerokuを経由しません。

## ローカル検証

```powershell
npm.cmd install
npm.cmd test
powershell -ExecutionPolicy Bypass -File tools\build_web.ps1
powershell -ExecutionPolicy Bypass -File tools\serve_web.ps1
```

同一PCで2つのブラウザウィンドウを開き、片方で作成、もう片方で参加して確認できます。
