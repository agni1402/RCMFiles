$LogFile = "C:\Scripts\VM_SFTP_ErrorFiles_RCM_Log.txt"
Clear-Content -Path $LogFile -ErrorAction SilentlyContinue
Start-Transcript -Path $LogFile

# Parameters
$SftpHost = "eu-central-1.sftpcloud.io"
$SftpUsername = "2f8f8b7569304592ad49367af642ef93"
$SftpPassword = "wXqhOQfg8fgQmaA0vKSn25sSE1DOMmXW"
$LocalFolder = "C:\RCMFiles\ErrorFiles"
$RemoteFolder = "/RCMEDI/IncomingErrorFiles"

# Convert password to SecureString
$SecureSftpPassword = ConvertTo-SecureString -String $SftpPassword -AsPlainText -Force

# Create credential object
$SftpCredential = New-Object System.Management.Automation.PSCredential ($SftpUsername, $SecureSftpPassword)

# Import Posh-SSH module
Import-Module Posh-SSH -ErrorAction Stop

# Start SFTP session
Write-Host "Connecting to SFTP server..."
$SftpSession = New-SFTPSession -ComputerName $SftpHost -Credential $SftpCredential -AcceptKey

if ($SftpSession) {
    Write-Host "Connected to SFTP."

    # Get current threshold time (12 hours back)
    $ThresholdTime = (Get-Date).AddHours(-12)

    # Get recent files from local folder
    $FilesToUpload = Get-ChildItem -Path $LocalFolder -File | Where-Object { 
                            ($_.LastWriteTime -gt $ThresholdTime) -or ($_.CreationTime -gt $ThresholdTime)
                        }

    if (-not $FilesToUpload) {
        Write-Host "No files modified in the last 12 hours in: $LocalFolder"
    } else {
        foreach ($File in $FilesToUpload) {
            $LocalFilePath = $File.FullName
            Write-Host "Uploading $LocalFilePath to $RemoteFolder..."
            Set-SFTPItem -SessionId $SftpSession.SessionId -Path $LocalFilePath -Destination $RemoteFolder
            Write-Host "Uploaded: $File.Name"
        }

        Write-Host "Upload completed for recent files."
    }

    # Close session
    Remove-SFTPSession -SessionId $SftpSession.SessionId
    Write-Host "SFTP session closed."
} else {
    Write-Error "Failed to connect to SFTP."
}

Write-Host "Script finished."
Stop-Transcript
