# Web対戦仕様

## 構成

- ブラウザ同士のゲーム通信はGodotの`WebRTCMultiplayerPeer`を使用する。
- HerokuのNodeプロセスは`build/web`を配信し、同じホストの`/signal`でWebSocketシグナリングを行う。
- ルームは6文字コードで、対戦人数を2・4・6・8人から選択する。選択人数ちょうどの参加者がそろい、全員が準備完了した場合だけ開始できる。
- 対戦参加者とは別に最大4人の観戦者が参加できる。観戦者は準備やカード操作を行わず、進行中の試合を読み取り専用で表示する。
- 複数人ではラウンドごとに重複しない組み合わせを作り、試合を順番に進行する。試合中でない対戦参加者も、その試合を自動的に観戦する。
- ホストはPeer ID 1、以降の参加者と観戦者には空いているPeer IDを順番に割り当てる。
- 既存のホスト権威型RPCを維持し、カード操作、戦闘スナップショット、アリーナ準備、報酬を同期する。
- シグナリング参加時にプロトコル版とカード/遺物データのSHA-256を照合する。

LAN探索、ENet、UPnP、EOS認証、Client Secretは使用しません。

## 対戦手順

1. 全員が同じ公開URLをブラウザで開く。
2. ハブの`Web対戦`を開く。
3. ホストがルームを作成し、表示されたコードを相手へ共有する。
4. ホストがロビーで対戦人数を2・4・6・8人から設定する。
5. 対戦参加者は同じコードで参加し、観戦者は`観戦者として参加`を有効にして参加する。
6. 設定人数の対戦参加者が全員準備を完了するとアリーナ準備へ進む。
7. 全対戦参加者が準備を完了すると最初の組み合わせの戦闘へ進む。
8. 戦闘画面では対戦する2人が`戦闘開始`を押し、3秒カウントダウン後に開始する。
9. ラウンド内の全組み合わせが終了すると、次の準備フェーズまたは規定勝利数到達による最終結果へ進む。

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

同一PCで複数のブラウザウィンドウを開き、1つで作成、残りで対戦参加または観戦参加して確認できます。
