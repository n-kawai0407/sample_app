---
title: "CloudFront、CDN以外の「現場の使いどころ」"
tags:
  - aws
  - cloudfront
  - cdn
  - パフォーマンス
  - saa
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: true
---

## はじめに：CloudFrontは「ただのCDN」ではない

SAAでCloudFrontは「コンテンツ配信ネットワーク（CDN）、エッジでキャッシュして高速配信」と習います。
正しいのですが、現場のCloudFrontは**それ以外の役割でも大活躍**しています。
「CDN」の枠を超えた使いどころを知ると、設計の引き出しが増えます。

## おさらい：CDNとしての基本

世界中のエッジロケーションにコンテンツをキャッシュし、**ユーザーに近い場所から配信**。
→ 低レイテンシ・オリジン負荷軽減・転送コスト最適化。

## CDN以外の「現場の使いどころ」

### ① 静的サイトの公開（S3 + CloudFront）
S3の静的ホスティングをCloudFront経由で配信。HTTPS化・独自ドメイン・キャッシュが効く。
→ SPA/LP/ドキュメントサイトの定番構成。

### ② オリジンの保護（直接アクセスを防ぐ）
**OAC（Origin Access Control）**でS3への直接アクセスを禁止し、CloudFront経由のみ許可。
→ S3バケットを非公開にしたまま安全に配信できる。

### ③ セキュリティの最前線（WAF / Shield 連携）
CloudFrontの前段でAWS WAFを適用し、エッジで攻撃をブロック。Shieldと併せてDDoS対策にも。
→ オリジンに届く前に、エッジで弾く。

### ④ HTTPS終端・証明書管理
ACM（AWS Certificate Manager）の無料証明書でHTTPS化を一元管理。

### ⑤ エッジでの処理（CloudFront Functions / Lambda@Edge）
リダイレクト、ヘッダ書き換え、認証、A/Bテストなどを**エッジで実行**。
→ オリジンに行かずに軽い処理を完結。

### ⑥ 動的コンテンツの高速化
キャッシュできない動的APIでも、AWSの高速ネットワーク経由でレイテンシを改善。

## 設計でのよくある組み合わせ

```
[ユーザー]
    │
[CloudFront] ── WAF（攻撃をブロック）
    │           ACM（HTTPS）
    ├─ 静的 → S3（OACで保護、非公開）
    └─ 動的 → ALB → アプリ
```

> 💼 現場では「CloudFrontを単なる高速化でなく、**セキュリティとオリジン保護の層**として置く」のが定石です。

## SAAでの問われ方

- 「世界中に低レイテンシで配信」→ CloudFront
- 「S3を非公開にしたまま配信」→ CloudFront + OAC
- 「エッジで攻撃をブロック」→ CloudFront + WAF
- 「動的コンテンツも高速化」→ CloudFront（キャッシュ設定の調整）

## まとめ

- CloudFrontは「CDN」だけでなく、**オリジン保護・セキュリティ層・エッジ処理・HTTPS終端**でも活躍
- S3静的サイト、OACによる保護、WAF連携は現場の定番
- 「高速化のためだけ」と思っていると設計の幅を狭める

CloudFrontを「配信の入口にして守りの最前線」と捉えると、一段深い設計ができます。

---

> 📩 「サービスの現場活用」をXとメルマガで発信中 👉 [リンク]
