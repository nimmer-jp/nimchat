# nimchat

Nim + nimble で作った、Crown / Tiara ベースのローカルLLM向けチャットアプリです。

## 構成

- 初回セットアップ画面
  - ローカルLLM接続先 URL を設定
  - モデル名 (任意) を設定
  - IP制限を設定（またはスキップ）
- チャット画面
  - 左側: セッション切り替えサイドバー
  - 右側: チャットバブル表示 + 送信フォーム
- API
  - `POST /api/chat` がローカルLLMへ中継

## 起動

このプロジェクトはローカルの `../crown` と `../tiara` を `nim.cfg` 経由で参照します。

```bash
../crown/crown dev
```

または整合チェック:

```bash
../crown/crown check
```

## 補足

- 初回設定は `localStorage` に保存されます（キー: `nimchat.setup.v1`）。
- セッション履歴は `localStorage` に保存されます。
- Nim 2.2.8 では `crown dev` の `--incremental:on` で `=copy operator not found for type string` の内部エラーが出る場合があります。  
  このプロジェクトは `crown.json` に `devIncremental: false` を設定して回避しています。
- Crown 向けの改善メモは `docs/crown-notes.md` にまとめています。
- Tiara 向けの改善メモは `docs/tiara-notes.md` にまとめています。
