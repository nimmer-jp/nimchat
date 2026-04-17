# Crown 向けメモ（nimchat 実装から）

このドキュメントは、`Crown` リポジトリ向けにそのまま渡せるように、`nimchat` 実装時の不足点と改善要件を Crown 専用でまとめたものです。

## このリポジトリで実際に入れた Crown 側修正

未完成フレームワーク前提で、`nimchat` 側では `crown` をローカルオーバーライドして修正を入れています。

- 修正対象ファイル:
  - `crown/core.nim`
  - `crown/client.nim`
  - `crown/client.js`

- 実施した `crown/core.nim` 修正:
  - `crownParamsWithCatch` の互換回避  
    Basolato 側 `Param` 生成との不整合があり、catch-all 合成処理を安全側に寄せるパッチを適用。
  - `client.js` 読み込み経路の修正  
    `staticRead("client.js")` ではなく `staticRead(clientJsPath)` に変更し、参照ミスを回避。
  - `pwa: false` 時の Service Worker 注入を停止  
    非PWA構成で不要な SW スクリプト注入が入らないように修正。
  - dev overlay の `frontend-error` 定期ポーリングを停止  
    `GET /__crown/dev/frontend-error` を 1 秒ごとに叩く実装を外し、開発時ログが常時汚れる問題を回避。

この修正は upstream 反映までの暫定措置です。Crown 本体に同等修正が入ったら、ローカルオーバーライドは削除できる状態を目標にします。

## 実装時に必要だったこと

## 1. ルーティングシグネチャの統一

- 期待する初期形: `proc page*(req: Request): string`
- `crown init` 後に旧シグネチャと混在すると、Route生成時に実装者側で調整が必要になる。

## 2. ローカル開発パス設定の明確化

- `Crown` と `Tiara` を同時ローカル開発する場合、`nim.cfg` の `--path` 設定が必須だった。
- 実際に必要だった設定例:
  - `--path:"."`
  - `--path:"../tiara/src"`
  - `--nimcache:"./nimcache"`

## 3. 互換レイヤーの明示

- Basolato とのバージョン差分で、そのまま `crown dev/check` できないケースがあった。
- 今回はプロジェクトローカルに `crown/core.nim` を置いて互換パッチで回避した。
- 互換対象を明記するか、`crown check` で差分検知ガイドを出せると運用しやすい。

## 3.1 Nim incremental コンパイル不具合の回避

- 環境: Nim 2.2.8
- `crown dev`（`--incremental:on`）で `=copy operator not found for type string` の内部エラーが発生した。
- 回避策として `crown.json` に `devIncremental: false` を設定したところ、コンパイルは成功した。
- 開発体験のため、Crown側でこの症状を検知した場合に `devIncremental: false` を提案するガイドがあるとよい。

## 3.2 dev overlay ポーリング由来のログノイズ

- `crown dev` 中に `DEBUG 200 OK GET /__crown/dev/frontend-error[]` が常時出る。
- 現状実装では dev overlay が 1 秒ごとにポーリングしており、実害はなくてもログ可読性が落ちる。
- 今回の `nimchat` では Crown core をローカルパッチし、該当ポーリングを無効化した。

## 4. IP取得ヘルパー

- IP制限実装時に `req.clientIp()` 相当の統一APIが欲しかった。
- `X-Forwarded-For` / `X-Real-IP` / socket 取得をフレームワークで吸収できると重複実装が減る。

## 5. JSONボディ受信ヘルパー

- `req.jsonBody()` 相当があれば、API実装時にフォームエンコード回避のための補助コードが不要になる。

## 改善要件（今回追加）

## A. ポート衝突時の自動インクリメント起動

- `crown.json` のポートが使用中でも `crown dev` を停止させず、`+1` で空きポート探索して起動する。
- 例: `5000` 使用中なら `5001` で自動起動。

## B. 起動情報の明示表示

- `crown dev` のログに以下を必ず表示:
  - 最終的な待受ポート
  - アクセスURL（例: `http://localhost:5001`）

## 受け入れ条件（提案）

- ポート衝突時に `crown dev` が失敗終了しない。
- ログに `requested port` と `actual port` の両方が出る。
- URLがクリック可能な形式（プレーンでも可）で表示される。

## 検証ポリシー（運用ルール）

`crown check` だけでは完成判定しない。最低限、以下を通す:

- `crown dev` で実際に起動できること
- ブラウザアクセスで初期ページが描画されること
- Console に構文エラーが出ないこと
- 必要API（本件では `/api/chat`）が実リクエストで疎通すること
