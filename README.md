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

前提: **Crown 0.4.6 以上**（Basolato **0.15 / 0.16** 両対応は Crown 側の対応範囲）、**Nim 2.2.8**（`crown.nimble` の `requires` に合わせる）。このリポジトリでは Basolato を **`#v0.15.0`** に固定しています（`crown.nimble` を編集すれば 0.16 系タグに切り替え可能）。

1. 依存をインストールします。

**`nimble install` だけで** Basolato の `ducere` ビルドが **`system module needs: nimSubInt`** で落ちる場合があります。ログに `compiling nim package using .../pkgs2/nim-2.2.8-.../bin/nim` と出ていれば、**Nimble が管理する `bin/nim` が、同梱の 2.2.8 ソースツリーと一致していない**（例: 実体が古い 1.9.1 のまま）ことがあります。**Crown / Basolato の不具合ではありません。**

対処の優先度の目安:

1. **根本（同じ 2.2.8 を使い続ける）**: すでに **choosenim 等で正しい Nim 2.2.8** があるなら、その `bin/nim` で Nimble のコピーを上書きする。

```bash
# 例: choosenim のツールチェーン（`nim -v` が 2.2.8 であることを確認）
GOOD_NIM="$HOME/.choosenim/toolchains/nim-2.2.8/bin/nim"
for d in "$HOME/.nimble/nimbinaries/nim-2.2.8" "$HOME"/.nimble/pkgs2/nim-2.2.8-*; do
  [ -f "$d/bin/nim" ] && cp -f "$GOOD_NIM" "$d/bin/nim" && chmod u+x "$d/bin/nim"
done
```

その後、通常どおり `nimble install -y` でよいです。`nimbinaries` / `pkgs2` の **`bin/nim --version`** が **2.2.8** になっていることを確認してください。

2. **回避**: 毎回システムの Nim で依存だけビルドする。

```bash
nimble --useSystemNim install -y
```

3. **再ダウンロードだけでは直らないことがある**: `pkgs2` を消しても、Nimble が `nimbinaries` から同じ壊れたバイナリを戻す場合があります。そのときは **(1) の上書き**か **`--useSystemNim`** を使ってください。

2. **Crown**（`crown` CLI）は Nimble で入れます（未インストールなら）。

```bash
nimble install -y crown@0.4.6
```

（上記 (1) 未実施で `nimble` 用 Nim が壊れている場合は、`nimble --useSystemNim install -y crown@0.4.6` でも可。）

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

`nim.cfg` では `-d:httpbeast` のほか、**`pkgcache` の Basolato v0.15.0 を `--path` で先に通す**設定にしています。これが無いと、マシンに **別プロジェクト用の `basolato-0.16.x` が `~/.nimble/pkgs2` に残っている**だけで、`crown dev` が **0.16.1 を import** し、**`createResponse` / GC-safety** で落ちます。`nimble --useSystemNim install` は **ducere 用に 0.15 の pkgcache を使う**だけで、アプリ本体のコンパイル経路は別なので、この現象は **「Nimble のオプションを付けても直らない」ように見える**ことがあります。

### ビルドが止まるとき（参考）

- **`nimSubInt`（`nimble install` 時）**: **Nimble の `pkgs2` / `nimbinaries` 内 Nim** と lib の取り違え。上記「起動」の手順か `--useSystemNim`。
- **`createResponse` / GC-safety（`crown dev` 時）**: 多くは **Basolato 0.16.x が解決されている**ことが原因。`nim.cfg` の **`#v0.15.0` の `--path`** を確認するか、一時的に `pkgs2` の `basolato-0.16.*` を整理する。

> **補足**: `crown.nimble` というファイル名のため、Nimble 上のパッケージ名は `crown` と表示されます。依存の **フレームワーク Crown**（`requires "crown >= 0.4.6"`）と名前が重なって紛らわしい点だけご注意ください。

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
