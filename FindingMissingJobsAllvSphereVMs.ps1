##############################################################
# VeeamONE & VBR REST API Call Sample
# Description: Sample
# Version: 0.2
# Auther: yoshinari.ozawa@veeam.com
# The information on this website is provided for informational purposes only and should not be construed as legal, financial, or other professional advice
# We are not responsible for any damages or losses arising from the use of this website or its content.
##############################################################

# 実行ポリシーを変更
Set-ExecutionPolicy Bypass -Scope Process -Force

# SSL/TLS証明書の検証を無効化
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}


<#
.SYNOPSIS
  メインの処理実行

.NOTES
  
#>

try {
    # REST API Call 
    $return_vmList = GetAllvSphereVMs
    $jobList = GetVBRAllJobs

    Write-Host ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " PoweredOn VMs:" + $return_vmList.Count) -ForegroundColor Red

    # 除外VMリスト（MoRef）を作成
    $excludeList = @( 'vm-5255','vm-18001')

    # $return_vmList から除外リストに含まれる MoRef を除外
    # $return_vmList のループ内で MoRef を使って jobList の VirtualMachines から一致する objectId を探す
    $return_vmList | Where-Object { $excludeList -notcontains $_.MoRef } | ForEach-Object {
        $moRef = $_.MoRef  # ループ中の MoRef を取得

        # MoRef と一致する objectId を持つジョブを探す
        $matchingJobNames = $jobList | Where-Object {
            # 各ジョブの VirtualMachines 配列内をループして MoRef と一致する objectId を探す
            $_.VirtualMachines | Where-Object { $_.objectId -eq $moRef }
        } | Select-Object -ExpandProperty JobName


        # カンマ区切りで連結
        $matchingJobNamesString = $matchingJobNames -join ", "

        Write-Host "VMName: $($_.VMName), MoRef: $moRef" -NoNewline


        # 一致するジョブがあれば表示
        if ($matchingJobNames.Count -gt 0) {
            if ($matchingJobNames.Count -eq 1) {
                Write-Host " Only one job, Protected by $matchingJobNamesString　" -ForegroundColor Yellow
            } else {
                Write-Host " Protected by $matchingJobNamesString" -ForegroundColor Green
            }
        } else {
            Write-Host " Not Protected." -ForegroundColor Magenta
        }
    }


    # 画面を残しておくためにキー入力を待機
    # Read-Host "Press Enter to exit..."

}
catch {
    Write-Host "エラーが発生しました: $_"
}
finally {
    # @TODO logout
}



<#
.SYNOPSIS
  RestAPIにログインする

.NOTES
 access_tokenを取得
#>
function loginToken {

    param(
        [string]$endpoint,
        [hashtable]$headers,
        [string]$username,
        [string]$password
    )

    $body = @{
        grant_type ="password"
        username = $username
        password = $password
    }

    # フォームデータをURLエンコード形式に変換
    $encodedBody = ($body.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
    
    # REST APIエンドポイントへのリクエスト
    $response = Invoke-RestMethod -Uri $endpoint -Headers $headers -Body $encodedBody -Method Post

    return $response.access_token

}


<#
.SYNOPSIS
    VeeamONEサーバからvSphereVM情報を取得する

.NOTES
    VeeamONEのVirtualInfrastructure設定にvCenter or ESXiの登録が終わっていること

#>
function GetAllvSphereVMs{

    # VeeamONE REST API の設定
    $veeamOneRestApiUrl = "https://192.168.1.154:1239/api/"

    # Tokenエンドポイント、VMSエンドポイント
    $tokenEndpoint = "token"

    $apiEndpoint = "v2.2/vSphere/vms"

    # 認証情報を設定（ユーザー名とパスワード）検証のためコードに直書きしているだけ
    $username = "VBR123-1\Administrator"
    $password = "xxxxxxxxxxxxxxx"


    # 認証用のヘッダー（基本認証の設定）
    $headers = @{
        "Content-Type" = "application/x-www-form-urlencoded"
    }


    # レスポンスからアクセストークンを取得
    ##$token = $response.access_token
    $token = loginToken -endpoint "$veeamOneRestApiUrl$tokenEndpoint" -headers $headers -username $username -password $password

    # トークンが正常に取得できた場合
    if ($token) {
        Write-Output "アクセストークンが正常に取得されました。"
    
        # APIリクエストのヘッダーを設定（アクセストークンをAuthorizationヘッダーに設定）
        $headers = @{
            "Authorization" = "Bearer $token"
        }

        #必要に応じてクエリパラメータを追加してください
        $veeamOneRestApiUrl = "$veeamOneRestApiUrl"+"$apiEndpoint"

        # APIからVM情報を取得
        $vmResponse = Invoke-RestMethod -Uri "$veeamOneRestApiUrl" -Method Get -Headers $headers
    

        # VM情報の表示
        if ($vmResponse) {
            # VM情報を構造体（PSCustomObject）に変換
            $vmList = $vmResponse.items | ForEach-Object {

                [PSCustomObject]@{
                    VMId               = $_.vmid
                    VMName             = $_.name
                    PowerState         = $_.powerState
                    CpuCount           = $_.cpuCount
                    MemorySizeMb       = $_.memorySizeMb
                    MoRef              = $_.moRef
                    GuestIpAddresses   = $_.guestIpAddresses
                    GuestOs            = $_.guestOs
                    VirtualDiskCount   = $_.virtualDiskCount
                    VirtualDisks       = $_.virtualDisks

                }
            }

            # 変数に格納
            # PowerState が 'PoweredOn' のものだけ
            $extract_vmList = $vmList | Where-Object { $_.PowerState -eq 'PoweredOn' }  | Select-Object  VMId,VMName,PowerState, MoRef

            return $extract_vmList

        } else {
            Write-Output "VM情報が取得できませんでした。"
        }

    } else {
        Write-Output "アクセストークンの取得に失敗しました。"
    }
}


<#
.SYNOPSIS
    VBRサーバから全ジョブ設定を取得する

.NOTES
    

#>
function GetVBRAllJobs{
    # VeeamONE REST API の設定
    $vbrRestApiUrl = "https://192.168.1.154:9419/api/"

    # Tokenエンドポイント、VMSエンドポイント
    $authEndpoint = "oauth2/token"
    $apiEndpoint = "v1/jobs"
    
    # 認証情報を設定（ユーザー名とパスワード）検証のためコードに直書きしているだけ
    $username = "VBR123-1\Administrator"
    $password = "xxxxxxxxxxxxxxx"


    # 認証用のヘッダー（基本認証の設定）
    $headers = @{
        "x-api-version" = "1.2-rev1"
    }

    # レスポンスからアクセストークンを取得
    $token = loginToken -endpoint "$vbrRestApiUrl$authEndpoint" -headers $headers -username $username -password $password

    # トークンが正常に取得できた場合
    if ($token) {
        Write-Output "アクセストークンが正常に取得されました。"
    
        # APIリクエストのヘッダーを設定（アクセストークンをAuthorizationヘッダーに設定）
        $headers = @{
            "Authorization" = "Bearer $token"
            "x-api-version" = "1.2-rev0"
        }

        #必要に応じてクエリパラメータを追加してください
        $vbrRestApiUrl = "$vbrRestApiUrl$apiEndpoint"

        #Write-Host($vbrRestApiUrl)

        # APIからJob情報を取得
        $jobResponse = Invoke-RestMethod -Uri "$vbrRestApiUrl" -Method Get -Headers $headers

        # job情報の表示
        if ($jobResponse) {
            # APIレスポンスからjob情報を構造体に変換
            $jobList = $jobResponse.data | ForEach-Object {
                [PSCustomObject]@{
                    JobId           = $_.id
                    JobName         = $_.name
                    JobDescription  = $_.description
                    IsDisabled      = $_.isDisabled
                    JobType         = $_.type
                    RunAutomatically = $_.schedule.runAutomatically
                    DailyScheduleEnabled = $_.schedule.daily.isEnabled
                    ScheduleDailyLocalTime       = $_.schedule.daily.localTime
                    BackupRepositoryId = $_.storage.backupRepositoryId
                    RetentionType   = $_.storage.retentionPolicy.type
                    RetentionQuantity = $_.storage.retentionPolicy.quantity
                    VirtualMachines = $_.virtualMachines.includes
                }
            }

            # 構造体を表形式で表示
            # 条件式 JobTypがBackup IsDisabledがfalse
            $extractionList =  $jobList | Where-Object { $_.JobType -eq 'Backup' -and $_.IsDisabled -eq $false} | Select-Object JobName, IsDisabled, JobType, VirtualMachines,RunAutomatically, ScheduleDailyLocalTime, BackupRepositoryId, RetentionType, RetentionQuantity

            return $extractionList

        } else {
            Write-Output "job情報が取得できませんでした。"
        }

    } else {
        Write-Output "アクセストークンの取得に失敗しました。"
    }

}