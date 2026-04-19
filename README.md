# nimchat

Nim + Crown + Tiara で作った、ローカルLLM向けの軽量チャットアプリです。

![nimchat スクリーンショット](./screenshot.png)

## 特徴

- **初回セットアップ画面**: 接続先URL / モデル名 / IP制限 を設定（IP制限はスキップ可）
- **チャット画面**: 左サイドバーでセッション切り替え、右ペインでチャットバブル表示
- **ローカル保存**: 設定と会話履歴は `localStorage` に保存
- **設定リセット**: サイドバーの「設定をリセット」で `localStorage` を消去して初期状態へ
- **API中継**: `POST /api/chat` が OpenAI 互換エンドポイントへ中継

## 起動

1. このリポジトリの依存（Basolato / Tiara）をインストールします。

```bash
nimble install -y
```

2. **Crown**（`crown` CLI と `import crown/core` 用ライブラリ）は別途 Nimble で入れます（Crown 公式の `crown init` と同様、`crown.nimble` 名の都合でフレームワーク本体はここでは宣言しません）。

```bash
nimble install -y https://github.com/nimmer-jp/crown#head
```

3. 開発サーバー:

```bash
crown dev
```

本番ビルド:

```bash
crown build
./.crown/main
```

Tiara を Git の `main` 追従にしているため、古いキャッシュでビルドエラーになる場合は `~/.nimble/pkgcache` 内の `githubcom_nimmerjptiara_#main` を削除してから `nimble install -y` をやり直してください。

`nim.cfg` では Basolato v0.15 系を `$home/.nimble/pkgcache/...` から先に読み込みます（Nim 2.2.8 と Basolato 0.16 系の組み合わせで出るコンパイルエラーを避けるため）。

デフォルトは `http://127.0.0.1:8080` で起動します。

## ローカルLLM の例: Bonsai モデルを mlx_lm で動かす

`mlx_lm` で OpenAI 互換サーバーを立てる例:

```bash
python3 -m mlx_lm server \
  --model prism-ml/Ternary-Bonsai-8B-mlx-2bit \
  --port 8082
```

nimchat の初回セットアップでは次のように入力します。

| 項目 | 値 |
| --- | --- |
| 接続先 URL | `http://127.0.0.1:8082/v1/chat/completions` |
| モデル名 | **空欄のまま** か `prism-ml/Ternary-Bonsai-8B-mlx-2bit` |
| IP制限 | スキップでOK |

> ⚠️ `mlx_lm` は リクエスト body に `model` があると、その名前で HuggingFace から再取得を試みます。  
> 起動時に指定したモデル以外の短縮名（例: `bonsai` や `local-model`）を入れると
> `Repository Not Found` エラーになるので、**モデル名欄は空にする**のが安全です。

## API

### `POST /api/chat`

フォームパラメータ:

| 名前 | 必須 | 説明 |
| --- | --- | --- |
| `endpoint` | ✓ | 中継先の OpenAI 互換URL |
| `prompt` | ✓ | ユーザー入力 |
| `model` |   | 省略すると LLM サーバーの既定モデルが使われる |
| `historyJson` |   | 直近20件までの `{role, content}` 配列 (JSON文字列) |
| `ipRestrictionEnabled` |   | `true`/`false` |
| `allowedIps` |   | カンマ区切りの許可IP |
| `clientIp` |   | 検証対象のクライアントIP |

上流エラー時はステータスコードと応答本文の抜粋を `error` フィールドに含めて返します。

## localStorage キー

| キー | 用途 |
| --- | --- |
| `nimchat.setup.v1` | 接続設定 |
| `nimchat.sessions.v1` | 会話セッションの配列 |
| `nimchat.active-session.v1` | アクティブセッションID |

サイドバーの「設定をリセット」ボタンで上記すべてを削除します。

## 補足

- Nim 2.2.8 では `crown dev` の incremental コンパイルで内部エラーが出ることがあるため、`crown.json` に `"devIncremental": false` を設定しています。
