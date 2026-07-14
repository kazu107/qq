# オンラインマルチプレイ仕様

> 現在は一時停止中。ハブのオンライン対戦入口、EOS自動起動、GD-EOS GDExtensionを無効化している。clone後の通常プレイとLAN対戦にEOS SDK、Client Secret、トークンは不要。以下は再実装時の資料として保存する。

## 構成

- 2人用のアリーナ対戦をEpic Online Services (EOS) P2P Relayで接続する。
- GodotのRPC層は`EOSMultiplayerPeer`を使用し、既存のLAN対戦と同じホスト権威モデルを維持する。
- `EOSP2P.RC_ForceRelays`を指定し、公開IP、ポート開放、UPnPを不要にする。
- ホストがEOS Lobbyを作成し、参加者はルームコードからLobbyを検索する。
- 準備、カウントダウン、カード操作、再接続、報酬処理はLAN版と共通の`NetworkManager`で処理する。

## 再有効化時のセットアップ

1. `addons/gd-eos/gd-eos.gdextension.disabled`を`gd-eos.gdextension`へ戻す。
2. `project.godot`の`EosService`を`src/autoload/EosService.gd`へ戻す。
3. `Game.ONLINE_MULTIPLAYER_ENABLED`を`true`にする。
4. 以下のEOS SDKとClient Secretを設定し、EOS専用テストを実行する。

EOS SDKを配置する。`-SdkPath`には展開したSDKのルートまたはその中の`SDK`フォルダを指定できる。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup_eos.ps1 `
  -SdkPath 'C:\Users\kazuu\Downloads\EOS-SDK-CSharp-53289219-Release-v1.19.1.2'
```

Client Secretをローカル設定へ入力する。入力値は画面に表示されず、`config/eos_credentials.local.cfg`へ保存される。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\configure_eos_credentials.ps1
```

次のファイルはライセンスと機密情報保護のためGitへ追加しない。

- `addons/gd-eos/bin/windows/EOSSDK-Win64-Shipping.dll`
- `addons/gd-eos/bin/windows/x64/xaudio2_9redist.dll`
- `config/eos_credentials.local.cfg`

GD-EOSのWindows用GDExtensionとMITライセンスはリポジトリに含める。別PCではclone後に上記2コマンドだけを実行する。

## 再有効化後のプレイ手順

1. ハブから「オンラインマルチプレイ」を開く。
2. EOS Connectが端末固有の匿名Device IDを自動作成する。Epicアカウントへのサインイン操作は不要。
3. ホストはルームコードを指定するか、空欄のままLobbyを作成する。
4. 参加者は同じルームコードを入力して参加する。
5. 両者が準備を完了すると戦闘へ進み、両者が戦闘開始を押した後にカウントダウンする。

Device IDはWindowsユーザープロファイル単位でEOS SDKが保持する。別PC同士では自動的に別ユーザーになる。同じWindowsユーザープロファイルで2プロセスを起動するとDevice IDが共有されるため、同一PCテストでは後述のDevAuthToolで`Player1`と`Player2`を使用する。

ルームコードそのものはLobby属性へ保存せず、SHA-256の照合値だけを公開属性に保存する。Lobbyは最大2人、ホスト移譲なし、RTCなしで作成する。

## 実EOS検証

通常の匿名Device ID接続、ロビー作成、Relayソケット起動、ロビー終了を1プロセスで確認する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate_eos_device.ps1 `
  -GodotPath 'C:\Users\kazuu\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' `
  -Root (Get-Location).Path
```

同一PCで実Relayを検証するには、DevAuthToolを起動する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\start_eos_dev_auth.ps1 `
  -SdkPath 'C:\Users\kazuu\Downloads\EOS-SDK-CSharp-53289219-Release-v1.19.1.2'
```

DevAuthToolでポートを`8081`にし、別々のEpicアカウントで`Player1`と`Player2`を作成してサインインする。その後、次を実行する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate_eos_network.ps1 `
  -GodotPath 'C:\Users\kazuu\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' `
  -Root (Get-Location).Path
```

このテストは実EOS Lobby、Relay接続、準備、戦闘開始、カードRPC、切断後の再接続、ラウンド報酬までを2プロセスで確認する。

通常の`tests/validate_project.ps1`はEOS専用テストを実行せず、オンライン機能が無効でLAN入口が利用できることを検査する。EOS専用テストは上記の再有効化を完了した後に個別実行する。

## セキュリティ

- Client SecretはGit、スクリーンショット、チャット、ログへ掲載しない。
- Client Secretが外部へ露出した場合はDeveloper Portalで再発行する。
- ホストがカード操作、所持品、購入、勝敗、報酬の正当性を検証し、クライアントの最終状態を信用しない。
- ルームコードは認証情報ではない。将来、不特定多数へ公開する場合はレート制限、通報、BAN、マッチメイク用バックエンドを追加する。

## 実装ファイル

- `src/autoload/EosService.gd`: EOS初期化、認証、Lobby検索、Relay Peer生成。
- `src/autoload/EosServiceDisabled.gd`: 現在の既定autoload。EOS依存なしでオンライン操作を拒否する。
- `src/autoload/NetworkManager.gd`: LAN/EOSの共通セッション管理とホスト権威同期。
- `addons/gd-eos/gd-eos.gdextension.disabled`: 現在停止中のGD-EOS GDExtension設定。
- `tools/setup_eos.ps1`: 公式EOSランタイムのローカル配置。
- `tests/eos_api_contract_smoke.gd`: GD-EOS API互換性検証。
- `tests/validate_eos_device.ps1`: 匿名Device IDと実EOS Lobbyの1プロセス検証。
- `tests/validate_eos_network.ps1`: 実Relayの2アカウント検証。
