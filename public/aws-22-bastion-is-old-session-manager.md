---
title: "踏み台サーバーはもう古い？ Session Managerのススメ"
tags:
  - aws
  - ssm
  - セキュリティ
  - 踏み台
  - 運用
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: true
---

## はじめに：「踏み台サーバー」、まだ立ててませんか？

プライベートサブネットのEC2に接続するため、**踏み台サーバー（Bastion Host）**を立てる——
長らくこれが定番でした。SSHキーを管理し、22番ポートを開け、踏み台を経由して奥のサーバーへ。

でも今、現場では **「踏み台レス」** が主流になりつつあります。主役は **AWS Systems Manager Session Manager**。
なぜ踏み台が「古い」とまで言われるのか、何が置き換わるのか、そして「それでも踏み台が残るケース」までを、現役エンジニアの視点で一通り解説します。

この記事を読み終えると、次の3つが言えるようになります。

- なぜ「22番ポートを開けない」設計が今の常識なのか
- Session Managerに必要な前提（IAM・エージェント・到達性）を自分で組めるか
- 「踏み台が必要な例外ケース」を判断できるか

## 従来の踏み台サーバーの問題点

まず、これまでの定番構成を図にするとこうです。

```
[管理者PC] ──(SSH:22)──> [踏み台EC2 (Public Subnet)]
                                │
                                │ (SSH:22)
                                ▼
                         [アプリEC2 (Private Subnet)]
```

この構成、便利な反面、地味に重い負担を抱えています。

1. **22番ポートを開ける必要がある**（攻撃対象が増える）
   - インターネットに面したSSHポートは常にスキャン・総当たり攻撃の標的です。
   - 「踏み台だから0.0.0.0/0で開けておこう」が事故の入口になりがち。
2. **SSHキーの管理が面倒**（紛失・漏洩リスク、退職者の鍵失効）
   - 鍵をSlackやメールでやりとりしてしまうと、それ自体が漏洩経路に。
   - 退職者の公開鍵が`authorized_keys`に残り続ける、という典型的な放置も。
3. **踏み台自体の運用コスト**（パッチ、監視、可用性）
   - 踏み台もOSであり、定期パッチ・監視・場合によっては冗長化が要る。
   - 「踏み台が落ちていて本番に入れない」という本末転倒も起きます。
4. **誰が何をしたか追いにくい**（操作ログが残りにくい）
   - 共有鍵で入っていると「誰が叩いたコマンドか」が判別できません。

### Before（踏み台あり）の運用負荷を棚卸しすると

| 項目 | 踏み台あり | コメント |
| --- | --- | --- |
| インバウンドポート | 22番を開放 | 攻撃対象が増える |
| 認証 | SSHキー | 配布・失効・ローテが手作業 |
| 監査ログ | 別途仕込みが必要 | 標準では「誰が何を」が残らない |
| 可用性 | 踏み台のお守りが必要 | 落ちると本番に入れない |
| コスト | 踏み台分のEC2料金（目安） | 常時起動なら地味に積み上がる |

便利な反面、**セキュリティと運用の負担**が積み上がっているのが分かります。

## Session Manager が解決すること

Session Managerは、各インスタンスに常駐する**SSM Agent**が、SSMのエンドポイントへ**アウトバウンド方向**で接続を確立し、その経路を使ってシェルを開く仕組みです。
ポイントは「**インスタンス側からSSMへ出ていく**」点。だからインバウンド（22番）を一切開けずに済みます。

```
[管理者PC]
   │ aws ssm start-session / コンソール（IAMで認証）
   ▼
[ AWS Systems Manager ]  <──(アウトバウンド443)── [アプリEC2 (Private Subnet)]
                                                   └ SSM Agent 常駐
```

得られるメリットを整理すると：

- **22番ポートを開けなくていい**（インバウンド不要 → 攻撃対象が激減）
- **SSHキー不要**（IAM権限でアクセス制御。鍵の配布・失効・ローテから解放）
- **踏み台サーバー不要**（運用コストが消える）
- **操作ログが残る**（誰が・いつ・何をしたかをCloudTrail/S3/CloudWatch Logsに記録）
- **ブラウザやCLIから接続**できる（管理者PCにSSHクライアントすら不要）

### After（Session Manager）に置き換えた対応表

| 項目 | 踏み台あり | Session Manager |
| --- | --- | --- |
| インバウンドポート | 22番を開放 | **開けない（0個）** |
| 認証 | SSHキー | **IAMポリシー** |
| アクセス制御の粒度 | SG＋OSユーザー | IAM＋タグ条件で細かく制御可 |
| 監査ログ | 自前で仕込む | **標準でCloudTrail＋（任意で）操作ログ記録** |
| 踏み台の可用性管理 | 必要 | **不要** |

> 💼 「ポートを開けず、鍵も管理せず、ログも残る」。セキュリティ監査でも好まれ、現場の標準になりつつあります。

## 実際に使ってみる：CLIコマンド例

接続自体はこれだけです（プラグイン `session-manager-plugin` が入っている前提）。

```bash
# インスタンスID指定でシェルに入る
aws ssm start-session --target i-0123456789abcdef0

# 接続できるインスタンスの一覧（オンライン状態を確認）
aws ssm describe-instance-information \
  --query "InstanceInformationList[].{Id:InstanceId,Ping:PingStatus,Name:ComputerName}" \
  --output table
```

SSH自体をSession Manager経由でトンネルすることもできます（鍵運用を続けたいがポートは開けたくない、という移行期に便利）。`~/.ssh/config` に次を足すと、`ssh i-xxxx` がSSM経由で通ります。

```
# ~/.ssh/config
host i-* mi-*
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
```

ローカルポートフォワード（例：プライベートなRDSやWebの管理画面に踏み台レスで到達）も可能です。

```bash
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["mydb.xxxx.ap-northeast-1.rds.amazonaws.com"],"portNumber":["3306"],"localPortNumber":["13306"]}'
# → localhost:13306 経由でRDSへ接続できる
```

## 使うための前提（3点セット）

Session Managerが繋がらないときの原因は、ほぼこの3つのどれかです。順番に潰すと迷いません。

1. 対象EC2に **SSM Agent**が入っている（Amazon Linux 2/2023や新しめのAMIは標準搭載）
2. EC2に **SSM用のIAMロール**が付与されている（インスタンスプロファイル経由）
3. プライベートサブネットの場合、**SSMへの到達性**がある（VPCエンドポイント or NAT経由）

### IAMロール（最小構成の目安）

AWS管理ポリシー `AmazonSSMManagedInstanceCore` をインスタンスロールにアタッチするのが手軽な定番です。
Terraformで書くとこうなります（概念を示すサンプル。詳細は環境に合わせて調整してください）。

```hcl
resource "aws_iam_role" "ssm" {
  name = "ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ssm.name
}
```

### プライベートサブネットの到達性

NATゲートウェイ経由でも届きますが、**よりセキュアかつNATコストを避けたい**なら、最低限この3つのインターフェース型VPCエンドポイントを置くのが定番です。

- `com.amazonaws.<region>.ssm`
- `com.amazonaws.<region>.ssmmessages`
- `com.amazonaws.<region>.ec2messages`

```
[アプリEC2 (Private)] ──> [VPCエンドポイント: ssm / ssmmessages / ec2messages] ──> SSM
（NATゲートウェイもインターネットGWも不要で完結できる）
```

> 💼 現場のひとこと：`ssmmessages` を入れ忘れて「Agentは動いてるのにセッションが張れない」が定番のハマりどころ。3点セットで覚えておきましょう。

## つまずきやすいポイントFAQ

**Q. `start-session` で「Target not connected」と出ます。**
A. ほぼ到達性かIAMの問題です。`describe-instance-information` に出てこない＝SSMがインスタンスを認識できていない状態。まず①IAMロール、②`ssmmessages`を含むエンドポイント／NAT、③Agentの稼働、の順で確認します。

**Q. ログイン後のユーザーは誰になりますか？**
A. デフォルトでは `ssm-user`（sudo可）です。`su - ec2-user` で従来ユーザーに切り替えるか、ランドキュメントで挙動を変えられます。

**Q. 操作内容（コマンド履歴）まで残せますか？**
A. はい。セッションのログ出力先としてS3／CloudWatch Logsを指定でき、入力したコマンドの記録も可能です。監査要件があるなら最初から有効化しておくのが吉。

**Q. IAMで「このインスタンスだけ」に絞れますか？**
A. リソースやタグ条件付きのIAMポリシーで、`ssm:StartSession` を特定タグのインスタンスに限定できます。チーム別・環境別の権限分離はこれで実現します。

## 「踏み台が必要なケース」もまだある

万能ではないので、踏み台（あるいは別手段）が残る場面もあります。

- SSM Agentを入れられない機器・特殊環境（一部のアプライアンス等）
- SSM以外の特殊なプロトコル接続が前提のフロー
- オンプレ・他クラウドからの接続経路がSSMに乗っていない場合（※ハイブリッドアクティベーションで取り込む手はある）
- レガシーな運用フローやツールから移行しきれていない過渡期

とはいえ、**新規構築なら「まずSession Managerを検討」**が今の常識です。

## 移行チェックリスト

踏み台あり構成からの乗り換えは、次の順で進めると安全です。

```
□ 対象インスタンスにSSM用IAMロールを付与した
□ SSM Agentが稼働している（describe-instance-information に表示される）
□ プライベートなら ssm / ssmmessages / ec2messages のエンドポイントを用意した
□ aws ssm start-session でシェルに入れることを確認した
□ セッションログの出力先（S3 / CloudWatch Logs）を設定した
□ IAMで「誰がどのインスタンスに入れるか」を絞った
□ 上記が安定してから、踏み台のSGで22番を閉じる → 踏み台を削除
```

いきなり踏み台を消さず、**Session Managerで入れることを確認してから22番を閉じる**のが事故らないコツです。

## SAA/実務での位置づけ

- 試験で深くは問われない傾向ですが、「踏み台レスで安全に接続する」選択肢として知っておくと、セキュリティ系設問で強くなります。
- 実務では「なぜ22番を開けないのか」を自分の言葉で説明できると一目置かれます。
- 「SSH鍵運用 vs IAM＋Session Manager」の比較は、設計レビューで頻出の論点です。

## まとめ

- 従来の踏み台サーバーは **ポート開放・鍵管理・運用コスト・監査の弱さ**が負担
- **Session Manager**なら、ポートレス・鍵レス・ログ付きで安全に接続できる
- 前提は3点セット：**SSM Agent ＋ IAMロール ＋ （プライベートなら）VPCエンドポイント**
- 接続は `aws ssm start-session` の一行。ポートフォワードやSSHトンネルにも応用可
- 例外はあるが、新規構築は「まずSession Manager」が現代の標準

「古い常識をアップデートできる」ことを示すと、発信者としての信頼が上がります。

---

> 📩 「試験に出ないが現場で必須」の知識をXで毎日発信中 👉 [リンク]
