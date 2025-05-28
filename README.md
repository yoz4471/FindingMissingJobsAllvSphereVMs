
# FindingMissingJobsAllvSphereVMs

## 概要

この PowerShell スクリプトは、Veeam ONE および Veeam Backup & Replication (VBR) の REST API を活用し、vSphere 仮想マシンのうち、バックアップジョブに割り当てられていない VM を特定します。

- PoweredOn 状態の VM 一覧を取得
- 有効な Veeam バックアップジョブ一覧を取得
- 各 VM がどのジョブにも紐づいていないか確認
- 結果を画面に出力

## 主な機能

- Veeam ONE および VBR へのログイン／ログアウト処理の自動化
- AES による資格情報の暗号化・復号処理
- バックアップジョブと VM の紐づけチェック
- 除外リストによる検出対象 VM のフィルタリング

## 前提条件

- PowerShell 5.1 以降
- Veeam ONE および Veeam Backup & Replication 環境が REST API 経由でアクセス可能
- API のエンドポイントポートが開放されていること
  - 例: `https://<VBRサーバ>:9419/api/`、`https://<VeeamONEサーバ>:1239/api/`

## 初回実行時の資格情報保存

初回実行時には、ユーザー名およびパスワードを聞かれ、それらは暗号化されてスクリプトと同じフォルダに `veeam_credential.json` として保存されます。

AES鍵も同様に `aes.key` として保存され、次回以降は自動で復号されます。

## 除外リスト（ExcludeList）の設定

スクリプト内では、特定の仮想マシンをチェック対象から除外するための **MoRef ID ベースの除外リスト** を定義できます。

### 設定場所

```powershell
$excludeList = @('vm-5255','vm-18001')
```

### 使用目的

- 一時的にバックアップジョブの割当チェックをスキップしたいVM
- テスト中・開発中で運用対象外のVM
- 手動バックアップ運用中など、ジョブに関連付けなくてもよいVM

### 注意事項

- MoRef ID（例: `vm-1001`）は、vSphere Client などから取得可能です
- 除外したい VM の ID を配列に追加してください
- 除外リストを空にするには：
  ```powershell
  $excludeList = @()
  ```

## 実行の流れ

1. AES鍵・資格情報の復元（または初回作成）
2. Veeam ONE にログインし、PoweredOn VM を取得
3. VBR にログインし、有効なバックアップジョブ一覧を取得
4. VM とジョブの紐づけを確認
5. 除外対象を除いた結果を出力
6. 各環境からログアウトして終了

## 実行結果のサンプル

```text
2025-05-28 18:00:00 PoweredOn VMs: 3
VMName:WebServer01, MoRef:vm-101
 Job Name: DailyBackup01, Job ID: 1234abcd-5678-efgh-ijkl-9876mnopqrst, LastJobStatus: Success
VMName:DBServer01, MoRef:vm-102
 Job Name: DBJob, Job ID: abcd1234-5678-ijkl-efgh-9876mnopqrst, LastJobStatus: Warning
VMName:FileServer01, MoRef:vm-103
 Job Name: FileBackupJob, Job ID: efgh1234-5678-abcd-ijkl-9876mnopqrst, LastJobStatus: Success
```
![Image](https://github.com/user-attachments/assets/9dbfd1fe-3cdb-4477-86e7-21b23c6a40c2)

## 免責事項

- 本スクリプトは業務用ではなく参考実装であり、商用環境で使用する場合は十分な検証を行ってください
- スクリプトの利用により発生するいかなる損害についても、作成者および 所属組織 は一切の責任を負いません

---

Author: Yoshinari Ozawa
