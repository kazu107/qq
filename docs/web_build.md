# Web版のビルドと公開

このプロジェクトはGodot 4.6.2のWebエクスポートに対応しています。Web版では通常ラン、アリーナ、無限モード、開発者モード、WebRTC対戦を利用できます。

## 初回準備

1. Godot 4.6.2を起動します。
2. `エディター > エクスポートテンプレートの管理`を開きます。
3. Godot 4.6.2用のエクスポートテンプレートをインストールします。

エクスポートテンプレートは各PCに一度だけ必要です。容量が大きいためGitには含めません。

## ビルド

プロジェクトのルートで次を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_web.ps1
```

Godotの場所を明示する場合は次のようにします。

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_web.ps1 -GodotPath "C:\path\to\Godot_v4.6.2-stable_win64_console.exe"
```

成功すると`build/web/index.html`と必要な関連ファイルが生成されます。

## ローカル確認

Web版は`index.html`を直接開かず、Nodeサーバー経由で起動します。初回だけ`npm.cmd install`を実行してください。

```powershell
powershell -ExecutionPolicy Bypass -File tools/serve_web.ps1
```

ブラウザで`http://127.0.0.1:8060/`を開きます。

## 公開

Herokuではリポジトリルートの`Procfile`により、Godot WebビルドとWebRTCシグナリングを同じHTTPSホストで提供します。GitHubへのpush後に自動デプロイされます。

セーブデータはブラウザのIndexedDBに保存されます。プライベートブラウズ、Cookieやサイトデータの削除、一部の埋め込みiframeでは保持されない場合があります。

Web対戦はP2PのWebRTCを使い、Herokuは接続確立用のWebSocketシグナリングだけを担当します。厳しいNAT環境向けのTURN設定は`docs/ONLINE_MULTIPLAYER.md`を参照してください。

参考: [Godot公式 Webエクスポート](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
