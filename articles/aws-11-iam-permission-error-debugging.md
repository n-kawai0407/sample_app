---
title: "IAM権限エラーのデバッグ手順 ── 「Access Denied」の歩き方"
emoji: "🔐"
type: "tech"
topics: ["aws", "iam", "セキュリティ", "トラブルシューティング", "saa"]
published: false
---

## はじめに：AWSで一番よく見るエラー、それが権限エラー

`Access Denied` `not authorized to perform` ──
AWSを触っていれば必ず出会う、最もありふれたエラー。でも初学者はここで固まります。
**「どこを見れば原因が分かるのか」**の地図があれば、もう怖くありません。

この記事は、私が現場で実際に使っている「診断の順番」をそのまま手順化したものです。
適当に試行錯誤すると30分溶けます。**順番に切り分ければ5分**です。

## まず理解：権限が通る条件

AWSの権限は「**明示的な許可があり、かつ明示的な拒否がない**」とき初めて通ります。

- デフォルトは**すべて拒否**（暗黙のDeny）
- 許可（Allow）を与えて初めて使える
- ただし**明示的なDenyは何より優先**される（Allowがあっても拒否が勝つ）

この原則を頭に入れて、診断に入ります。

### 評価ロジックを図で

```
リクエスト
   │
   ▼
明示的なDenyがある？ ──── YES ──▶ ❌ 拒否（最優先・覆らない）
   │ NO
   ▼
明示的なAllowがある？ ──── NO ───▶ ❌ 拒否（暗黙のDeny）
   │ YES
   ▼
SCP / Permissions Boundary / セッションポリシーで絞られていない？
   │ NO（絞られていない）
   ▼
✅ 許可
```

つまり「Allowを足したのに通らない」ときは、**どこかにDenyがあるか、上限（SCP/境界）で削られている**のどちらかです。

## IAMポリシーの読み方（最小サンプル）

ポリシーは「誰に・何を・どのリソースに・許可/拒否」の4点で読みます。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ]
    }
  ]
}
```

ここでハマりやすいのが **ARNの粒度**：
- `s3:ListBucket`（バケット一覧）はバケット本体 `arn:aws:s3:::my-bucket` に対する権限
- `s3:GetObject`（オブジェクト取得）はオブジェクト `arn:aws:s3:::my-bucket/*` に対する権限

この2つを混同して「`/*` だけ書いてList系が落ちる」のは定番の事故です。

## デバッグ手順（上から順に）

### Step 1. エラーメッセージを正確に読む
`User: arn:aws:iam::xxx:user/alice is not authorized to perform: s3:GetObject on resource: ...`
→ **誰が（principal）・何を（action）・どのリソースに**が全部書いてある。まずここを読む。

メッセージにはヒントが多く、「explicit deny in an identity-based policy」「with an explicit deny in a service control policy」のように、**どこのDenyで落ちたか**まで書いてくれることがあります。ここを読み飛ばさない。

### Step 2. そのプリンシパルの権限を確認
- ユーザー/ロールにアタッチされたポリシーに、その**Action**が許可されているか
- リソース（ARN）の範囲は合っているか（`*` でなく特定リソースに絞られていないか）

```bash
# ユーザーにアタッチされた管理ポリシー一覧
aws iam list-attached-user-policies --user-name alice

# インラインポリシーの一覧と中身
aws iam list-user-policies --user-name alice
aws iam get-user-policy --user-name alice --policy-name my-inline
```

ロールの場合は `list-attached-role-policies` / `get-role-policy` に読み替えます。

### Step 3. 明示的なDenyを探す
- ポリシーに `Effect: Deny` がないか
- **SCP（Organizations）** で組織レベルに禁止されていないか（マルチアカウントの盲点）
- アクセス許可の境界（Permissions Boundary）で上限が絞られていないか

明示的なDenyの典型例（「本番リージョン以外を全部禁止」など）：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyOutsideTokyo",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": { "aws:RequestedRegion": "ap-northeast-1" }
      }
    }
  ]
}
```

このようなガードレールがSCPに入っていると、**個人のIAMで何をAllowしても通りません**。マルチアカウント環境では真っ先に疑うべき箇所です。

### Step 4. リソース側のポリシーを確認
- S3バケットポリシー、KMSキーポリシーなど**リソース側**で拒否/許可していないか
- クロスアカウントなら**両側**（呼ぶ側のIAM＋呼ばれる側のリソースポリシー）が必要

```bash
# S3バケットポリシーを確認
aws s3api get-bucket-policy --bucket my-bucket

# KMSキーポリシーを確認
aws kms get-key-policy --key-id <key-id> --policy-name default
```

### Step 5. ロールの引き受け（AssumeRole）を確認
- ロールを使う場合、**信頼ポリシー（Trust Policy）**でそのプリンシパルがAssumeを許可されているか
> 💼 「ポリシーは正しいのにロールを引き受けられない」の犯人は、たいてい信頼ポリシーです。

信頼ポリシーは「誰がこのロールを引き受けてよいか」を定義します。EC2にロールを渡すなら例えばこう：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

クロスアカウントなら `Principal` に相手アカウントのARNを書きます。**Assumeする側のIAMに `sts:AssumeRole` 許可**＋**Assumeされるロールの信頼ポリシー**、この両輪が揃って初めて通ります。

## 強力な武器：IAM Policy Simulator と CLI

AWSには **IAM Policy Simulator** があり、「このユーザーはこのアクションを実行できるか」を実際に試さずに検証できる。
原因の切り分けに非常に有効。CloudTrailでエラーになったAPIコールの詳細を追うのも有効。

CLIからもシミュレートできます：

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/alice \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/file.txt
```

結果の `EvalDecision` が `allowed` か `explicitDeny` か `implicitDeny` かで、**どの種類の拒否か**が一発で分かります。

CloudTrailで実際に落ちたコールを追う（直近のAccessDeniedを探す）：

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetObject \
  --max-results 5
```

`errorCode: AccessDenied` のイベントには、誰がどのリソースに何をしようとしたかが残っています。

## よくある原因トップ5

1. Actionの綴り/範囲が足りない（`s3:GetObject` はあるが `s3:ListBucket` がない 等）
2. リソースARNが実際の対象と一致していない（バケット本体 vs `/*` の取り違え）
3. KMSキーへの権限漏れ（暗号化S3/RDSで多発）
4. 信頼ポリシーの設定漏れ（クロスアカウント/ロール）
5. SCPやPermissions Boundaryによる上限制限

### 番外編：見落としがちな落とし穴

- **キャッシュされた認証情報**：CLIが古いクレデンシャル/プロファイルを使っている。`aws sts get-caller-identity` で「今、誰として実行しているか」を必ず確認。
- **リージョン違い**：別リージョンのリソースを見にいって「無い＝権限が無いように見える」ケース。
- **MFA必須条件**：`Condition` に `aws:MultiFactorAuthPresent` が入っていて、MFA無しのセッションが弾かれる。
- **VPCエンドポイントポリシー**：S3などへVPCエンドポイント経由でアクセスする場合、エンドポイント側のポリシーでも絞られうる。

> 💬 現場のひとこと：「まず自分が誰か」を `aws sts get-caller-identity` で確認するだけで、原因の3割は片付きます。

## 診断チェックリスト

- [ ] `aws sts get-caller-identity` で実行プリンシパルを確認した
- [ ] エラーメッセージの principal / action / resource を読んだ
- [ ] メッセージに「どこのDenyか」のヒントが無いか見た
- [ ] アイデンティティ側のポリシーにそのActionとARNがあるか確認した
- [ ] 明示的なDeny / SCP / Permissions Boundary を疑った
- [ ] リソース側ポリシー（S3バケット、KMS等）を確認した
- [ ] ロール利用なら信頼ポリシーと `sts:AssumeRole` の両輪を確認した
- [ ] Policy Simulator か CloudTrail で裏を取った

## よくある質問（FAQ）

**Q. Allowを足したのにまだ落ちる。なぜ？**
A. どこかに明示的Denyがあるか、SCP/Permissions Boundaryで上限が削られています。Step 3を重点的に。

**Q. ルートユーザーなら何でもできる？**
A. アイデンティティ権限は無制限に近いですが、**SCPはルートユーザーにも効きます**。組織のガードレールは越えられません。

**Q. クロスアカウントで「両側」と言うのが分からない。**
A. 「呼ぶ側のIAMに `sts:AssumeRole`（または対象サービスのAction）」＋「呼ばれる側のロール/リソースポリシーで相手アカウントを許可」。片方だけでは通りません。

**Q. 試験（SAA）には出る？**
A. 評価ロジック（明示Denyが最優先、デフォルト拒否）や信頼ポリシーの概念は出題傾向として頻出です。ただし本記事の「デバッグ手順」そのものは現場知識。傾向として押さえておくと損はありません。

## まとめ

- 権限は「**Allowがあり、Denyがない**」で通る。デフォルトは全拒否
- エラーメッセージの**誰が・何を・どこに**を起点に、IAM → Deny/SCP → リソースポリシー → 信頼ポリシーの順で追う
- **Policy Simulator** と **CloudTrail** が頼れる武器
- 困ったらまず `aws sts get-caller-identity` で「今、誰か」を確認

権限エラーは「慣れ」で必ず速くなります。手順を持っておくと、現場で一目置かれます。

---

> 📩 「試験に出ないが現場で必須」の知識をXで毎日発信中 👉 [リンク]
