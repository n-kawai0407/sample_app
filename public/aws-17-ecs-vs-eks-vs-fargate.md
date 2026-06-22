---
title: "ECS / EKS / Fargate の選定フロー ── コンテナをどう動かす"
tags:
  - aws
  - ecs
  - eks
  - fargate
  - コンテナ
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: true
---

## はじめに：3つが並ぶと混乱する

ECS・EKS・Fargate。コンテナを動かすAWSの選択肢ですが、初学者は必ず混乱します。
理由は、**「オーケストレーターの種類」と「実行環境の種類」という別の軸が混ざっている**から。
まず2つの軸を分けて理解しましょう。

私も最初、「ECSとFargateってどっちを選ぶの？」と質問して、先輩に「それ、択一じゃないよ」と苦笑された記憶があります。この記事を読めば、その混乱は最初から避けられます。

## 2つの軸で整理する

### 軸①：オーケストレーター（コンテナを管理する仕組み）
- **ECS**（Elastic Container Service）：AWS独自。シンプルで学習コストが低い
- **EKS**（Elastic Kubernetes Service）：マネージドKubernetes。標準的で高機能だが複雑

### 軸②：実行環境（コンテナを動かす土台）
- **EC2**：自分でEC2を管理（コスト調整可だが運用あり）
- **Fargate**：サーバーレス。EC2を意識せず動かせる（運用が楽）

つまり **「ECS or EKS」×「EC2 or Fargate」** の組み合わせ。
Fargateは単独の製品ではなく、**ECS/EKSの"実行モード"**だと理解すると一気にクリアになります。

```
          実行環境 →   EC2              Fargate
オーケスト ↓
  ECS          ECS on EC2        ECS on Fargate
  EKS          EKS on EC2        EKS on Fargate
```

> 💼 「ECS vs Fargate」という比較自体が成立しません。正しくは「ECS/EKSという管理層」と「EC2/Fargateという土台」を**それぞれ選ぶ**。ここを最初に腹落ちさせるのが最大のコツです。

### 用語ミニ整理（混乱しがちな言葉）

| 用語 | ざっくりの意味 |
|---|---|
| コンテナ | アプリと依存を固めた実行単位（Dockerイメージから起動） |
| オーケストレーター | 大量のコンテナを「どこで何個・どう動かすか」管理する仕組み |
| タスク（ECS） | まとめて動かすコンテナ群の単位。定義は「タスク定義」 |
| サービス（ECS） | タスクを常時N個維持する仕組み（落ちたら再起動） |
| Pod（EKS/K8s） | ECSのタスクに相当するKubernetesの最小デプロイ単位 |

## 選定フロー

### Step 1：ECS か EKS か
```
Kubernetesの知見/標準化/マルチクラウド/豊富なエコシステムが必要？
├─ YES → EKS
└─ NO（AWSでシンプルに動かしたい）→ ECS
```
> 💼 「Kubernetesでなければならない理由」がないなら、ECSのほうが圧倒的に楽。多くの中小規模はECSで十分です。EKSは強力ですが、クラスタ運用・バージョンアップ・周辺エコシステムの学習コストが地味に重い。

### Step 2：EC2 か Fargate か
```
サーバー管理をなくしたい / 運用人員が少ない？
├─ YES → Fargate
└─ 細かいコスト調整・特殊要件（GPU/特定インスタンス/常時大量）→ EC2
```
> 💼 「コンテナは使いたいがサーバー管理は嫌」ならFargate一択級。常時大量稼働でコストを詰めたい、GPUが要る、といった事情があればEC2が有利になることも。

## それぞれの向き不向き

| 選択 | 向いているケース | 運用負荷 | コスト傾向 |
|---|---|---|---|
| ECS on Fargate | サーバー管理を避けたい、素早く始めたい（最も手軽） | 低 | 中（手間を金で買う） |
| ECS on EC2 | コストを細かく詰めたい、特殊なインスタンス要件・GPU | 中 | 高稼働率なら安い |
| EKS on Fargate | K8s標準は欲しいが運用は軽くしたい | 中 | 中 |
| EKS on EC2 | K8sをフル活用、大規模・高度な制御・エコシステム活用 | 高 | 高稼働率なら安い |

> 💡 上記コスト傾向は「考え方の目安」です。実際の料金は構成・稼働率・リージョン・割引（Savings Plans/スポット等）で変わるため、**最新は公式の料金ページと見積りツールで試算**してください。

## EC2 と Fargate、コストの考え方

ざっくり言うと――

- **Fargate**：使った分（vCPU・メモリ × 時間）だけ課金。空きキャパを抱えない。**稼働率が読めない・低い**ワークロードで割安になりやすい。
- **EC2**：インスタンス単位の課金。**高稼働でビッシリ詰める**なら単価で有利。さらにSavings Plansやスポットで大きく下げられる。

```
コンテナの詰め込み具合（稼働率）が…

  低い・変動する  ──────────────▶  高い・安定している
       ▲                                  ▲
    Fargate有利                        EC2有利
 （空きを抱えない）              （余剰なく詰めて単価で勝つ）
```

> 💼 現場の判断は「まずFargateで素早く動かす → トラフィックが安定してコストが無視できなくなったらEC2移行を検討」という順が定石。最初からEC2でコストを詰めにいくと、運用に手を取られて開発が止まりがちです。

## 迷ったときの第一候補

特に理由がなければ **「ECS on Fargate」** から始めるのが、運用負荷とスピードのバランスが良い。
Kubernetesの要件が明確になったらEKSへ、コストを詰める必要が出たらEC2へ——と段階的に検討すればOK。

### 選定チェックリスト

- [ ] Kubernetesの「標準化・エコシステム・マルチクラウド」の要件は本当にあるか？（なければECS）
- [ ] 社内にK8s運用の知見・人員はあるか？（なければEKSは重い）
- [ ] サーバー（OSパッチ・スケーリング）の管理を背負える体制か？（無理ならFargate）
- [ ] GPUや特殊インスタンス、極端な高稼働でコスト最適化が必要か？（あればEC2）
- [ ] まずは小さく早く出したいのか、最初から作り込むのか？

## 手を動かすイメージ：ECS on Fargate

ECSの最小の流れはこんな感じです（実際はVPC/サブネット/IAMロール等の前提が要ります）。

```bash
# 1. クラスタを作成
aws ecs create-cluster --cluster-name my-cluster

# 2. タスク定義を登録（イメージやCPU/メモリをJSONで定義したものを渡す）
aws ecs register-task-definition --cli-input-json file://taskdef.json

# 3. Fargateでサービスを起動（常時2タスク維持）
aws ecs create-service \
  --cluster my-cluster \
  --service-name my-service \
  --task-definition my-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-aaa],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
```

タスク定義（抜粋イメージ）はこんな構造です。

```json
{
  "family": "my-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [{
    "name": "web",
    "image": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/my-app:latest",
    "portMappings": [{ "containerPort": 80 }]
  }]
}
```

> 💼 ECS on Fargateは「クラスタ・タスク定義・サービス」の3点セットが分かれば回せます。EC2のように「ノードのスケーリングやパッチ」を気にしなくていいのが、最初の一歩としてラクなポイント。

## 周辺サービス・知っておくと差がつく点

- **App Runner**：「コンテナをとにかく簡単にWeb公開したい」だけなら、ECS/EKSより手前のApp Runnerが最短のことも。選択肢として頭の片隅に。
- **ECR**（Elastic Container Registry）：コンテナイメージの置き場。ECS/EKSとセットで使う前提。
- **Auto Scaling**：ECSサービスもタスク数を需要に応じて自動増減できる（Application Auto Scaling）。
- **ロードバランサー連携**：Web公開はALBと組み合わせるのが定番。ALBの動的ポートマッピングはECS on EC2で効く。
- **Fargate Spot**：中断OKなワークロードなら、Fargateでもスポット相当で安く動かせる選択肢がある（要件に注意）。

## 落とし穴・注意点

- **「とりあえずEKS」は重い**：流行に乗ってEKSを選ぶと、クラスタのバージョンアップ追従や周辺ツール管理が継続的に発生。**運用できる体制があるか**を必ず問う。
- **Fargateは細かい制御ができない場面がある**：ホストへの特権アクセスや特定のデバイス利用など、EC2前提の要件は通らないことがある。
- **コスト誤算**：低稼働ならFargateが安いが、常時フル稼働の大規模をFargateで回すと割高になりがち。逆もまた然り。稼働率で判断する。
- **ネットワークモード（awsvpc）**：FargateはENIを各タスクに割り当てる方式。サブネットのIP枯渇に注意（大量タスク時）。
- **イメージのpull元・権限**：ECRからのpull権限（タスク実行ロール）の設定漏れで起動失敗、はあるある。

## 想定FAQ

**Q. 結局、最初の1つは何を選べばいい？**
A. 迷ったら**ECS on Fargate**。運用負荷が最も低く、素早く本番に出せます。

**Q. EKSはどんなときに「正解」になる？**
A. 既にK8sの資産・知見がある、マルチクラウドで共通基盤にしたい、Helmやオペレーター等のエコシステムを活用したい――こうした明確な理由があるとき。

**Q. Fargateだけで全部やれる？**
A. 多くのWeb/APIワークロードはFargateで十分。GPUや特殊要件、極端なコスト最適化が要るときだけEC2を検討、で大体うまくいきます。

**Q. SAAではどう問われる？**
A. 傾向として「サーバー管理をなくしたい→Fargate」「Kubernetes標準が要件→EKS」「AWSでシンプルに→ECS」という対応で読み解けます。数字の暗記より、この対応関係を押さえるのが有効です。

## まとめ

- **2軸で考える**：オーケストレーター（ECS/EKS）× 実行環境（EC2/Fargate）
- Fargateは製品でなく**サーバーレスな実行モード**
- 迷ったら **ECS on Fargate**。K8s必須ならEKS、コスト最優先・特殊要件ならEC2
- コストは**稼働率で判断**：低稼働＝Fargate有利、高稼働＝EC2有利
- 「Kubernetesでなければならない理由」を問うのが選定のコツ

---

> 📩 「コンテナ・インフラの選定」をXとメルマガで発信中 👉 [リンク]
