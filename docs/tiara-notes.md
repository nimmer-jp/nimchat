# Tiara 向けメモ（nimchat 実装から）

このドキュメントは、`Tiara` リポジトリ向けにそのまま渡せるように、`nimchat` 実装時の不足点と改善要件を Tiara 専用でまとめたものです。

## 実装時に必要だったこと

## 1. チャット向けプリミティブ

- 今回必要だった最小部品:
  - セッション一覧アイテム
  - チャットバブル
  - Composer（入力欄 + 送信行）
- これらが標準化されると、チャットUI実装のCSS手作業を大幅に削減できる。

## 2. `textarea` コンポーネント

- `Tiara.input` はあるが、メッセージ入力や複数IP入力で `textarea` が必須だった。
- 現状は生HTML + 手書きCSSで対応しているため、`Tiara.textarea` が必要。

## 2.1 `input` 属性マージ時の重複属性

- `Tiara.input(..., attrs=...)` で `id` など既存属性を再指定すると、属性が重複出力されるケースがあった。
- ブラウザは先頭属性を採用するため、後段の `getElementById` が想定IDを取れずランタイムエラーにつながる。
- 期待挙動:
  - `id`, `name`, `type` などは上書き（またはエラー）に統一
  - 重複属性をHTMLへ出力しない

## 3. 初回セットアップ系UIの小部品

- 「初回設定済み」「スキップ可」「バリデーションエラー」表示を実装するための部品が不足。
- あると助かる部品:
  - Info/Warning banner
  - Step/Setup card
  - Inline validation block

## 4. アプリUI向けレイアウトプリセット

- `Tiara.defaultStyles` は有用だが、サイドバー + メインパネルのアプリ構成は都度CSS作成が必要。
- `app-shell` 系プリセットがあると SaaS/チャットUI実装が高速化する。

## 改善要件（提案）

## A. `Tiara.textarea` 追加

- `name`, `label`, `placeholder`, `required`, `rows`, `attrs` を `input` と同様に扱えるAPI。
- `defaultStyles` と整合する標準クラスを提供。

## B. Chat UI コンポーネント群

- `chatSidebar`, `chatSessionItem`, `chatBubble`, `chatComposer` の最小セットを追加。
- 既存 `button`, `badge`, `input` と見た目/トークンを統一。

## C. セットアップ画面向け補助コンポーネント

- エラーメッセージ/ヘルプテキスト/ステータス表示を組みやすい小コンポーネント追加。

## 受け入れ条件（提案）

- `textarea` 導入で生HTMLの`<textarea>`実装が不要になる。
- チャット画面が「Tiaraコンポーネント中心 + 最小CSS」で構築できる。
- 初回設定画面のバリデーション表示をコンポーネントで統一できる。
