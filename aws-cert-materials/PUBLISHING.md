# 記事公開ガイド（Zenn / Qiita / note）

正本（`aws-cert-materials/articles/*.md`）から、各プラットフォーム向けの公開用ファイルを
**ビルドスクリプトで自動生成**して公開します。

```
aws-cert-materials/articles/NN-xxx.md   ← 正本（ここだけ編集する）
        │  ruby scripts/build_publish_articles.rb
        ├─→ articles/aws-NN-xxx.md       ← Zenn 用（リポジトリ連携で公開）
        ├─→ public/aws-NN-xxx.md         ← Qiita 用（Qiita CLI / Actions で公開）
        └─→ note/aws-NN-xxx.md           ← note 用（手動コピペ）
```

## 0. 生成（共通）

記事を追加・修正したら、まずビルドして公開用ファイルを更新します。

```bash
ruby scripts/build_publish_articles.rb
git add articles public note && git commit -m "公開用ファイルを再生成"
```

> ビルド時の安全策：**Zenn は `published: false`（下書き）**、**Qiita は `ignorePublish: true`（公開対象外）** で生成されます。
> 一斉公開を防ぐためです。公開したい記事だけ、後述の手順でフラグを切り替えてください。

---

## 1. Zenn（GitHub 連携：最も手軽）

Zenn はリポジトリ直下の `articles/` を読み込み、**push するだけで自動デプロイ**されます。

### 初回セットアップ
1. [Zenn](https://zenn.dev) にログイン →「GitHubからのデプロイ」を有効化
2. このリポジトリ（`n-kawai0407/sample_app`）を連携
3. デプロイ対象ブランチを確認（既定はデフォルトブランチ。`master` に統一すると分かりやすい）

### 公開フロー
1. 公開したい記事 `articles/aws-NN-xxx.md` の frontmatter を
   `published: false` → **`published: true`** に変更
2. デプロイ対象ブランチ（`master` など）へ push
3. 数十秒で Zenn に反映

> 💡 スラッグは `aws-NN-xxx`（12〜50字, 英小文字/数字/ハイフン）で生成済み。公開後はスラッグ＝URL になるので、変更すると URL が変わります。

---

## 2. Qiita（Qiita CLI + GitHub Actions：自動投稿）

`public/` 配下の記事を Qiita CLI で投稿します。GitHub Actions を同梱済み（`.github/workflows/publish-qiita.yml`）。

### 初回セットアップ
1. Qiita の **設定 > アプリケーション** で個人用アクセストークンを発行
   （スコープ：`read_qiita` と `write_qiita`）
2. GitHub の **Settings > Secrets and variables > Actions** に
   `QIITA_TOKEN` という名前でトークンを登録

### 公開フロー
1. 公開したい記事 `public/aws-NN-xxx.md` の frontmatter を
   `ignorePublish: true` → **`ignorePublish: false`** に変更
2. `master` へ push（または Actions タブから手動実行 `workflow_dispatch`）
3. Actions が走り、Qiita に投稿。投稿後は frontmatter に `id` が払い出されるので、その差分をコミット

### ローカルから投稿したい場合（任意）
```bash
npm install @qiita/qiita-cli --global   # 初回のみ
qiita login                             # トークンで認証
qiita preview                           # ローカルプレビュー
qiita publish aws-NN-xxx                # 個別公開（ignorePublish: false が必要）
```

> ⚠️ **Rails の `public/` との共存について**：Qiita CLI は記事を `public/` に置く仕様です。
> 本リポジトリには Rails の静的ファイル（`404.html` 等）も `public/` にありますが、記事は `aws-*.md` という別名のため**ファイル名は衝突しません**。
> 気になる場合は Qiita 用に専用リポジトリを切る運用も可能です（その場合は `public/`・`qiita.config.json`・ワークフローをそちらへ移します）。

---

## 3. note（手動コピペ）

note には公式 API・Git 連携がないため、**手動コピペ**になります。
`note/aws-NN-xxx.md` は frontmatter を除き、タイトルを `# 見出し` にした貼り付け用テキストです。

### 公開フロー
1. note で新規記事を作成
2. `note/aws-NN-xxx.md` の本文をコピーして貼り付け
3. 1行目の `# タイトル` は note のタイトル欄へ、本文は本文欄へ
4. 見出し・リスト・太字などの Markdown 記法は note 側の表示に合わせて微調整
5. 末尾の `[リンク]` プレースホルダを実際の URL に置換

> 💡 note は「読み物・体験談」が伸びやすい媒体。技術詳細は薄め、ストーリーを厚めに調整すると効果的です。

---

## 公開戦略（重要）：一斉公開しない

> 26 本を一度に公開すると、スパム的に見え、各プラットフォームのアルゴリズム評価にも悪影響です。
> ブランド構築フェーズでは **週末に 1 本ずつドリップ公開**するのが鉄則。
> だからこそ、生成物は既定で「未公開（下書き / ignorePublish）」にしてあります。

### 推奨ローテーション例（1記事を 3 媒体で使い回す）
- **Zenn / Qiita**：技術深掘り記事を中心に（信頼構築）
- **note**：キャリア・共感系を中心に（拡散・認知）
- 同じ記事でも、媒体ごとに導入文や CTA を少し変えると効果的

### 公開前チェックリスト
- [ ] `[リンク]` プレースホルダを実 URL に置換したか
- [ ] タイトル・タグ（topics）は媒体に最適化したか
- [ ] （Zenn）`published: true` にしたか
- [ ] （Qiita）`ignorePublish: false` にしたか／`QIITA_TOKEN` を登録済みか
- [ ] 図表を入れたい箇所（編集メモ参照）に画像を追加したか
