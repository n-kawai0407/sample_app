---
title: "CloudFront、CDN以外の「現場の使いどころ」"
emoji: "🌍"
type: "tech"
topics: ["aws", "cloudfront", "cdn", "パフォーマンス", "saa"]
published: false
---

## はじめに：CloudFrontは「ただのCDN」ではない

SAAでCloudFrontは「コンテンツ配信ネットワーク（CDN）、エッジでキャッシュして高速配信」と習います。
正しいのですが、現場のCloudFrontは**それ以外の役割でも大活躍**しています。

実際、私が関わるプロジェクトでCloudFrontを置く理由は、半分以上が「高速化」ではなく「**オリジン保護・セキュリティ・HTTPS終端・エッジ処理**」のためです。
「CDN」の枠を超えた使いどころを知ると、設計の引き出しが一気に増えます。この記事ではその全体像を、構成図とコード例つきで整理します。

## おさらい：CDNとしての基本

世界中のエッジロケーションにコンテンツをキャッシュし、**ユーザーに近い場所から配信**します。

```
[東京のユーザー] ─> [東京エッジ(キャッシュ)] ─┐
[ロンドンのユーザー] ─> [ロンドンエッジ(キャッシュ)] ─┼─> [オリジン(S3/ALB)]
[NYのユーザー] ─> [NYエッジ(キャッシュ)] ─┘   ※キャッシュヒット時はここまで来ない
```

得られる効果は3つ。

- **低レイテンシ**：物理的に近いエッジから返す
- **オリジン負荷軽減**：キャッシュヒット分はオリジンに届かない
- **転送コスト最適化**：オリジンからの転送（目安では割高）をエッジが肩代わり

ここまでは教科書通り。本題はここからです。

## CDN以外の「現場の使いどころ」

### ① 静的サイトの公開（S3 + CloudFront）

S3の静的コンテンツをCloudFront経由で配信。HTTPS化・独自ドメイン・キャッシュが効きます。
SPA（React/Vue）・LP・ドキュメントサイトの定番構成です。

SPAでよくあるのが「直リンクで404になる」問題。これはCloudFrontのカスタムエラーレスポンスで`index.html`へ返すと解決します。

```
カスタムエラーレスポンス設定（目安）
  HTTPエラーコード 403/404 → レスポンスページパス /index.html → HTTP 200 を返す
```

### ② オリジンの保護（直接アクセスを防ぐ）

**OAC（Origin Access Control）**でS3への直接アクセスを禁止し、CloudFront経由のみ許可します。
S3バケットを**完全非公開のまま**安全に配信できるのがポイント。

> 補足：以前は **OAI（Origin Access Identity）** が使われていましたが、現在の推奨は **OAC** です。新規はOACで組むのが定石（記事や古い手順書はOAIのままのことがあるので注意）。

OAC利用時のS3バケットポリシー（概念サンプル）：

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipalReadOnly",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::my-static-site/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::111122223333:distribution/EXXXXXXXXXXXXX"
      }
    }
  }]
}
```

→ S3は「CloudFrontのこのディストリビューションからしか読めない」状態になります。

### ③ セキュリティの最前線（WAF / Shield 連携）

CloudFrontの前段でAWS WAFを適用し、**エッジで攻撃をブロック**。Shieldと併せてDDoS対策にも。

- SQLインジェクション・XSSなどはAWS Managed Rulesで一括対応
- レートベースルールで「同一IPから一定時間に多すぎるリクエスト」を遮断
- Shield Standardは自動適用、より強い保護が要るならShield Advanced（有料、要件次第）

→ オリジンに届く前に、エッジで弾く。アプリ側の負荷も減ります。

### ④ HTTPS終端・証明書管理

ACM（AWS Certificate Manager）の無料証明書でHTTPS化を一元管理できます。
注意点として、**CloudFrontに紐づけるACM証明書はバージニア北部（us-east-1）で発行する**必要があります（リージョンの落とし穴。ALB用とは別物）。

加えて、`Redirect HTTP to HTTPS` を有効化し、TLSの最低バージョンやHTTP/2・HTTP/3もここで一元設定できます。

### ⑤ エッジでの処理（CloudFront Functions / Lambda@Edge）

リダイレクト、ヘッダ書き換え、簡易認証、A/Bテストなどを**エッジで実行**できます。
2つの選択肢があり、用途で使い分けます。

| | CloudFront Functions | Lambda@Edge |
| --- | --- | --- |
| 言語 | JavaScript | Node.js / Python |
| 実行できる箇所 | Viewer Request/Response | Viewer・Origin の Request/Response |
| 実行時間 | 超短時間（サブミリ秒級） | より長い処理が可能 |
| 用途 | ヘッダ操作・URL書換・簡易認証 | 外部呼び出し・重めの加工 |
| コスト感（目安） | 安価・高頻度向き | 相対的に高め |

軽いヘッダ操作・リダイレクトは**まずCloudFront Functions**、外部APIアクセスや本格的な処理が要るならLambda@Edge、が選び方の目安です。

セキュリティヘッダを付与するCloudFront Functionsの例：

```javascript
function handler(event) {
  var response = event.response;
  var headers = response.headers;
  headers['strict-transport-security'] = { value: 'max-age=63072000; includeSubdomains' };
  headers['x-content-type-options']   = { value: 'nosniff' };
  headers['x-frame-options']          = { value: 'DENY' };
  return response;
}
```

### ⑥ 動的コンテンツの高速化

キャッシュできない動的APIでも、ユーザーは近くのエッジに接続し、そこからAWSのバックボーン（高速ネットワーク）でオリジンへ抜けます。
インターネットを延々と経由するより、レイテンシとパケットロスが安定するのが効きます。キャッシュ「させない」設定（キャッシュポリシーでTTL=0相当）にしても、ネットワーク最適化の恩恵は受けられます。

## 設計でのよくある組み合わせ

現場で頻出の「全部入り」構成です。

```
[ユーザー]
    │  (HTTPS / HTTP3)
[CloudFront] ── WAF（攻撃をエッジでブロック）
    │           ACM（HTTPS終端, us-east-1の証明書）
    │           CloudFront Functions（ヘッダ操作・リダイレクト）
    │
    ├─ パス /static/* → S3（OACで保護・完全非公開）
    └─ パス /api/*    → ALB → アプリ（EC2/ECS）
```

ポイントは**ビヘイビア（Cache Behavior）でパスごとにオリジンを振り分ける**こと。`/static/*`はS3、`/api/*`はALB、と1つのドメインで束ねられます。

> 💼 現場のひとこと：CloudFrontを単なる高速化でなく、「**ドメインの入口を一本化し、そこにセキュリティとオリジン保護を集約する層**」として置くのが定石です。入口が1つなら、守る場所も1つで済みます。

## Before / After：CloudFrontを「入口の守り」にする

| 観点 | Before（CloudFrontなし or 高速化目的のみ） | After（入口の守りとして活用） |
| --- | --- | --- |
| S3公開 | バケットを公開（事故りやすい） | OACで完全非公開、CloudFront経由のみ |
| 攻撃対策 | アプリ/ALBで都度対処 | WAFでエッジ遮断、オリジンに届く前に弾く |
| HTTPS | サーバごとに証明書管理 | ACMで一元管理・自動更新 |
| ドメイン | サービスごとにバラバラ | 1ドメインにパスで集約 |

## つまずきポイント FAQ

**Q. 設定を変えたのに反映されません。**
A. キャッシュが残っている可能性大。`CreateInvalidation` でパスを無効化します。
```bash
aws cloudfront create-invalidation --distribution-id EXXXXXXXXXXXXX --paths "/*"
```
ただし無効化は乱発するとコスト・反映遅延の要因に。ファイル名にハッシュを付ける（`app.abc123.js`）運用が王道です。

**Q. ACM証明書がCloudFrontで選べません。**
A. ほぼ確実にリージョン違い。**us-east-1で発行**し直してください。

**Q. OACにしたらS3が403になりました。**
A. バケットポリシーの更新漏れか、`AWS:SourceArn`のディストリビューションIDが合っていないケースが多いです。

**Q. ベストプラクティスでないので公開したくないS3を、どうしても直接アクセスから守りたい。**
A. OACでバケットを非公開化し、「パブリックアクセスブロック」を全部ONにしたうえでCloudFront経由のみ許可、が安全側の定番です。

## SAAでの問われ方（傾向）

- 「世界中に低レイテンシで配信」→ CloudFront
- 「S3を非公開にしたまま配信」→ CloudFront + OAC
- 「エッジで攻撃をブロック」→ CloudFront + WAF
- 「動的コンテンツも高速化したい」→ CloudFront（キャッシュ設定・オリジン振り分けの調整）
- 「エッジで軽い処理（リダイレクト/ヘッダ）」→ CloudFront Functions

## まとめ

- CloudFrontは「CDN」だけでなく、**オリジン保護・セキュリティ層・エッジ処理・HTTPS終端**でも活躍する
- S3静的サイト＋OAC、WAF連携、ACMによるHTTPS一元管理は現場の定番
- エッジ処理はCloudFront FunctionsとLambda@Edgeを用途で使い分ける
- ACMはus-east-1、OACは新規の推奨、キャッシュはバージョニング——細部の落とし穴に注意
- 「高速化のためだけ」と思っていると設計の幅を狭める

CloudFrontを「配信の入口にして守りの最前線」と捉えると、一段深い設計ができます。

---

> 📩 「サービスの現場活用」をXとメルマガで発信中 👉 [リンク]
