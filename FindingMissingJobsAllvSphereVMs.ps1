##############################################################
# FindingMissingJobsAllvSphereVMs
# Description: Please use this as a sample of VeeamONE & VBR REST API Call.
# Version: 0.3
# Auther: yoshinari.ozawa
# The information on this website is for informational purposes only and should not be construed as professional advice.
# Veeam and the authors are not liable for any damages or losses resulting from the use of this program or its contents.
##############################################################

#Set-ExecutionPolicy Bypass -Scope Process -Force

# 実行ポリシー制限のある環境でも .ps1 スクリプトを安全に実行するための処理
if (-not $env:REEXECUTION_FLAG) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -NoLogo -File `"$scriptPath`""
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables["REEXECUTION_FLAG"] = "1"
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit
}


# 便宜上SSL/TLS証明書の検証を無効化
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}


<#
.SYNOPSIS
  RestAPIにログインしトークン等を取得する
  ※便宜上VeeamONEとVBRのIDパスワードは同一としている
.NOTES
 access_tokenを取得
#>

function LoginToken {
    param(
        [string]$endpoint,
        [hashtable]$headers,
        [string]$username,
        [string]$password
    )

    $body = @{
        grant_type = "password"
        username   = $username
        password   = $password
    }

    # フォームデータをURLエンコード形式に変換
    $encodedBody = ($body.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"

    # REST APIエンドポイントへのリクエスト
    $response = Invoke-RestMethod -Uri $endpoint -Headers $headers -Body $encodedBody -Method Post

    # 必要な項目をハッシュテーブルにまとめて返す
    $auth_result = @{
        access_token = $response.access_token   #APIに対してアクセスするために使う「認証トークン」
        token_type   = $response.token_type     #トークンの種類
        refresh_token = $response.refresh_token #access_token が失効した後に、再ログインせずに新しいアクセストークンを取得するためのトークン
        expires_in   = $response.expires_in     #access_token の有効期限（秒数）
        issued       = $response." .issued"     #このトークンが発行された時刻（ISO 8601形式） VeeamONE REST APIには存在しない項目(VBRのみ)
        expires      = $response." .expires"    #このトークンの有効期限（日時）　VeeamONE REST APIには存在しない項目(VBRのみ)
    }

    return $auth_result
}


<#
.SYNOPSIS
  RestAPIからログアウトする

.NOTES
 
#>
function LogoutAll {

    #VeeamONE側のLogout処理
    try{

        # VeeamONE REST APIの設定
        $veeamOneRestApiUrl = "https://192.168.1.154:1239/api/"

        # エンドポイント
        $apiEndpoint = "revoke"

        $veeamOneRestApiUrl = "$veeamOneRestApiUrl"+"$apiEndpoint"

        # ヘッダー設定
        $one_headers = @{
            "Authorization"   = "Bearer $($script:one_token.access_token)"
            "Content-Type" = "application/x-www-form-urlencoded"
        }

        $veeamCredentials = GetVeeamCredentials

        $one_body = @{
            token = $($script:one_token.access_token)
            UserSid = $veeamCredentials.Username #Useridが必要
        }
        
        # フォームデータをURLエンコード形式に変換
        $encodedBody = ($one_body.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"


        # REST APIエンドポイントへのリクエスト
        $res = Invoke-WebRequest -Uri $veeamOneRestApiUrl -Headers $one_headers -Body $encodedBody -Method Post

        if ($res.StatusCode -eq 200) {
            Write-Host "--VBR RESTAPIからLogout成功"
        } else {
            Write-Host "--ステータスコード: $($res.StatusCode)"
        }

    }
    catch{
        Write-Host "VeeamONE Logout でエラーが発生しました: $_"
    }


    #VBR側のLogout処理
    try{

        # VBR REST APIの設定
        $vbrRestApiUrl = "https://192.168.1.154:9419/api/"

        # Tokenエンドポイント、VMSエンドポイント
        $authEndpoint = "oauth2/logout"

        $vbrRestApiUrl = "$vbrRestApiUrl"+"$authEndpoint"

        # ヘッダー設定
        $headers = @{
            "Authorization" = "Bearer $($script:vbr_token.access_token)"
            "x-api-version" = "1.2-rev1"
        }

        # REST APIエンドポイントへのリクエスト
        $res = Invoke-WebRequest -Uri $vbrRestApiUrl -Headers $headers -Method Post

        if ($res.StatusCode -eq 200) {
            Write-Host "--VeeamONE RESTAPIからLogout成功"
        } else {
            Write-Host "--ステータスコード: $($res.StatusCode)"
        }
    }
    catch{
        Write-Host "VBR Logout でエラーが発生しました: $_"
    }
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

    $veeamCredentials = GetVeeamCredentials

    # 認証用のヘッダー（基本認証の設定）
    $headers = @{
        "Content-Type" = "application/x-www-form-urlencoded"
    }


    # レスポンスからアクセストークンを取得
    ##$token = $response.access_token
    $script:one_token = LoginToken -endpoint "$veeamOneRestApiUrl$tokenEndpoint" -headers $headers -username $veeamCredentials.Username -password $veeamCredentials.Password

    # トークンが正常に取得できた場合
    if ($one_token.access_token) {
        Write-Host "--VeeamONE RESTAPIアクセストークンが正常に取得されました。"

        $return_token = $one_token.access_token
        # APIリクエストのヘッダーを設定（アクセストークンをAuthorizationヘッダーに設定）
        $headers = @{
            "Authorization" = "Bearer $return_token"
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
            Write-Host "VM情報が取得できませんでした。"
        }

    } else {
        Write-Host "VeeamONE RESTAPIアクセストークンの取得に失敗しました。"
    }
}


<#
.SYNOPSIS
    VBRサーバから全ジョブ設定を取得する

.NOTES
    
#>
function GetVBRAllJobsSettings{
    # VBR REST APIの設定
    $vbrRestApiUrl = "https://192.168.1.154:9419/api/"

    # Tokenエンドポイント、VMSエンドポイント
    $authEndpoint = "oauth2/token"
    $apiEndpoint = "v1/jobs"
    
    $veeamCredentials = GetVeeamCredentials

    # 認証用のヘッダー（基本認証の設定）
    $headers = @{
        "x-api-version" = "1.2-rev1"
    }

    # レスポンスからアクセストークンを取得
    $script:vbr_token = LoginToken -endpoint "$vbrRestApiUrl$authEndpoint" -headers $headers -username $veeamCredentials.Username -password $veeamCredentials.Password

    # トークンが正常に取得できた場合
    if ($vbr_token.access_token) {
        Write-Host "--VBR RESTAPIアクセストークンが正常に取得されました。"

        $return_token = $vbr_token.access_token
        

        # APIリクエストのヘッダーを設定（アクセストークンをAuthorizationヘッダーに設定）
        $headers = @{
            "Authorization" = "Bearer $return_token"
            "x-api-version" = "1.2-rev0"
        }


        #必要に応じてクエリパラメータを追加してください
        $vbrRestApiUrl = "$vbrRestApiUrl$apiEndpoint"

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
            $extractionList =  $jobList | Where-Object { $_.JobType -eq 'Backup' -and $_.IsDisabled -eq $false} | Select-Object JobId, JobName, IsDisabled, JobType, VirtualMachines,RunAutomatically, ScheduleDailyLocalTime, BackupRepositoryId, RetentionType, RetentionQuantity

            return $extractionList

        } else {
            Write-Host "job情報が取得できませんでした。"
        }

    } else {
        Write-Host "VBR RESTAPIアクセストークンの取得に失敗しました。"
    }

}



<#
.SYNOPSIS
    取得トークンの有効期限を判定する @TODO

.NOTES


#>
function CheckTokenExpire{
    param(
        [string]$tokenType,
        [string]$token
    )


}

<#
.SYNOPSIS
    ジョブIDから直近のバックアップステータスを取得する

.NOTES
    JobID,jobType
    https://helpcenter.veeam.com/docs/backup/vbr_rest/reference/vbr-rest-v1-2-rev1.html?ver=120#tag/Jobs/operation/GetAllJobsStates

#>
function GetVBRJobStatus{

    param(
        [string]$jobId
    )

    # VBR REST APIの設定
    $vbrRestApiUrl = "https://192.168.1.154:9419/api/"

    # エンドポイント
    $apiEndpoint = "v1/jobs/states"


    # トークン取得できてるなら TODO　使えるトークンがなければリフレッシュトークンを使い再取得
    # scriptスコープの$vbr_tokenから取得
    if ($vbr_token.access_token) {

        $return_token = $vbr_token.access_token
        
        # APIリクエストのヘッダーを設定（アクセストークンをAuthorizationヘッダーに設定）
        $headers = @{
            "Authorization" = "Bearer $return_token"
            "x-api-version" = "1.2-rev0"
        }

        # 必要に応じてクエリパラメータを追加してください
        $vbrRestApiUrl = "$vbrRestApiUrl$apiEndpoint" + "?typeFilter=Backup&idFilter=$jobId"

        # APIからJob情報を取得
        $jobStatesResponse = Invoke-RestMethod -Uri "$vbrRestApiUrl" -Method Get -Headers $headers


        # job情報の表示
        if ($jobStatesResponse) {
            # APIレスポンスからjob情報を構造体に変換
            $jobList = $jobStatesResponse.data | ForEach-Object {
                [PSCustomObject]@{
                    JobType         = $_.type
                    JobId           = $_.id
                    JobName         = $_.name
                    JobStatus       = $_.status
                    JobLastResult  = $_.lastResult

                }
            }

            # 構造体を表形式で表示
            # 条件式 なし
            $extractionList =  $jobList | Select-Object JobId, JobName, JobStatus, JobLastResult

            return $extractionList

        } else {
            Write-Host "job情報が取得できませんでした。"
        }

    } else {
        Write-Host "VBR RESTAPIアクセストークンの取得に失敗しました。"
    }
}


<#
.SYNOPSIS
    保存されているVeeamONE、VBRのクレデンシャルを安全に取得、PlainTextで返却する

.NOTES
    AES鍵と暗号化されたクレデンシャルがなければ作成する

#>
function GetVeeamCredentials {
    try {
        # スクリプトの保存ディレクトリ
        $secureDir = $PSScriptRoot
        $keyPath = Join-Path $secureDir "aes.key"
        $credPath = Join-Path $secureDir "veeam_credential.json"

        # AES鍵の生成（初回のみ）
        if (-not (Test-Path $keyPath)) {
            Write-Host "AES鍵を作成します..."
            $key = New-Object byte[] 32
            [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($key)
            [System.IO.File]::WriteAllBytes($keyPath, $key)
        } else {
            $key = [System.IO.File]::ReadAllBytes($keyPath)
        }

        # 資格情報が存在しない場合は作成
        if (-not (Test-Path $credPath)) {
            Write-Host "初回設定: 資格情報を入力してください"
            $plainUsername = Read-Host "ユーザー名を入力（例: VBR123-1\Administrator）"
            $securePassword = Read-Host "パスワードを入力" -AsSecureString
            $secureUsername = ConvertTo-SecureString $plainUsername -AsPlainText -Force

            # 暗号化（SecureString → AES文字列）
            $encUsername = $secureUsername | ConvertFrom-SecureString -Key $key
            $encPassword = $securePassword | ConvertFrom-SecureString -Key $key

            # JSONにまとめて保存
            $json = @{
                Username = $encUsername
                Password = $encPassword
            } | ConvertTo-Json -Depth 2

            Set-Content -Path $credPath -Value $json -Encoding UTF8
            Write-Host "資格情報を暗号化して保存しました。"
            Start-Sleep -Seconds 1
        }

        # 復号処理
        $jsonRaw = Get-Content $credPath -Raw | ConvertFrom-Json
        $secureUsername = $jsonRaw.Username | ConvertTo-SecureString -Key $key
        $securePassword = $jsonRaw.Password | ConvertTo-SecureString -Key $key

        # SecureString → プレーンテキスト（ユーザー名とパスワード）
        $plainUsername = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureUsername)
        )
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        )

        return @{
            Username = $plainUsername
            Password = $plainPassword
        }
    }
    catch {
        Write-Host "GetVeeamCredentials でエラーが発生しました: $_"
    }
}



<#
.SYNOPSIS
  メインの処理実行

.NOTES
  
#>

try {

    # REST API Call 
    $return_vmList = GetAllvSphereVMs

    $jobList = GetVBRAllJobsSettings

    Write-Host ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " PoweredOn VMs:" + $return_vmList.Count) -ForegroundColor Green

    # 除外VMリスト（MoRef）を作成
    $excludeList = @( 'vm-5255','vm-18001')

    # $return_vmList から除外リストに含まれる MoRef を除外
    # $return_vmList のループ内で MoRef を使って jobList の VirtualMachines から一致する objectId を探す
    $return_vmList | Where-Object { $excludeList -notcontains $_.MoRef } | ForEach-Object {

        $moRef = $_.MoRef  # ループ中の MoRef を取得

        if($moRef.Count -eq 1){

            # MoRef と一致する objectId を持つジョブ名とジョブIDを探す
            $matchingJobNames = $jobList | Where-Object {
                $_.VirtualMachines -and ($_.VirtualMachines | Where-Object { $_.objectId -eq $moRef })
            } | Select-Object -Property JobName, JobId
        

            Write-Host "VMName:$($_.VMName), MoRef:$moRef " 
            #Write-Host ($matchingJobNames -is[array])

            # 結果を表示
            $matchingJobNames | ForEach-Object {
                $jobId = $_.JobId

                #JobIdの直近のステータスを取得する
                $statusList = GetVBRJobStatus -jobId $jobId

                Write-Host " Job Name: $($_.JobName), Job ID: $jobId, LastJobStatus: $($statusList.JobLastResult)" -ForegroundColor Yellow
                #Write-Host " LastJobStatus: $($statusList.JobLastResult)" -ForegroundColor Yellow
            }
        }
    }
}
catch {
    Write-Host "エラーが発生しました: $_"
}
finally {
    LogoutAll
    Read-Host "続行するにはEnterキーを押してください"
    
}
