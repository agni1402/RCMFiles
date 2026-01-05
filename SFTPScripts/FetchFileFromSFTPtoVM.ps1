# === Setup Logging ===
$LogFile = "C:\Scripts\SFTP_VM_RCM_Log.txt"
Clear-Content -Path $LogFile -ErrorAction SilentlyContinue
Start-Transcript -Path $LogFile

# === Parameters ===
$SftpHost = "eu-central-1.sftpcloud.io"
$SftpUsername = "e5cb0849ee524c5382578efe87ab6521"
$SftpPassword = "qZXRXsndh8JkjDwDDQA2v06DRWcT9akv"
# $SftpHost = "acoenoc.blob.core.windows.net"
# $SftpUsername = "acoenoc.pvignesh"
# $SftpPassword = "f08mSIkxVhBmIPp9+BYdiXjnW0HrS1i7"
$RemoteBaseFolder = "/rcmedi/outbound"
$LocalBaseFolder = "C:\RCMFILES\Inbound"

# === Ensure Local Base Directory Exists ===
if (-not (Test-Path -Path $LocalBaseFolder)) {
    New-Item -ItemType Directory -Path $LocalBaseFolder | Out-Null
    Write-Host "Created base local folder: $LocalBaseFolder"
}

# === Convert Password and Setup Credentials ===
$SecureSftpPassword = ConvertTo-SecureString -String $SftpPassword -AsPlainText -Force
$SftpCredential = New-Object System.Management.Automation.PSCredential ($SftpUsername, $SecureSftpPassword)

# === Import Required Module ===
Import-Module Posh-SSH -ErrorAction Stop

# === Establish SFTP Connection ===
Write-Host "Connecting to SFTP..."
try {
    $SftpSession = New-SFTPSession -ComputerName $SftpHost -Credential $SftpCredential -AcceptKey
    
    if ($SftpSession) {
        Write-Host "Connected successfully to SFTP."
        
        # === Get List of Subfolders under /RCMEDI ===
        Write-Host "Checking for subfolders in: $RemoteBaseFolder"
        $Subfolders = Get-SFTPChildItem -SessionId $SftpSession.SessionId -Path $RemoteBaseFolder | Where-Object { $_.IsDirectory }
        
        if (-not $Subfolders) {
            Write-Host "No subfolders found in $RemoteBaseFolder"
        } else {
            Write-Host "Found $($Subfolders.Count) subfolder(s)"
            
            foreach ($Subfolder in $Subfolders) {
                # Fix: Use forward slashes for SFTP paths
                $RemoteSubfolderPath = "$RemoteBaseFolder/$($Subfolder.Name)"
                $LocalSubfolderPath = Join-Path $LocalBaseFolder $Subfolder.Name
                
                Write-Host "Processing subfolder: $($Subfolder.Name)"
                Write-Host "Remote path: $RemoteSubfolderPath"
                
                # Ensure local subfolder exists
                if (-not (Test-Path -Path $LocalSubfolderPath)) {
                    New-Item -ItemType Directory -Path $LocalSubfolderPath | Out-Null
                    Write-Host "Created local folder: $LocalSubfolderPath"
                }
                
                # Get files in the subfolder
                try {
                    $Files = Get-SFTPChildItem -SessionId $SftpSession.SessionId -Path $RemoteSubfolderPath | Where-Object { -not $_.IsDirectory }
                    
                    if (-not $Files) {
                        Write-Host "No files found in $RemoteSubfolderPath"
                    } else {
                        Write-Host "Found $($Files.Count) file(s) in $RemoteSubfolderPath"
                        
                        $ThresholdTime = (Get-Date).AddHours(-24)
                        Write-Host "Looking for files modified after: $ThresholdTime"
                        
                        $RecentFiles = $Files | Where-Object { ($_.LastWriteTime -gt $ThresholdTime) -or ($_.CreationTime -gt $ThresholdTime) }
                        
                        if (-not $RecentFiles) {
                            Write-Host "No files modified in the last 24 hours in $RemoteSubfolderPath"
                            # Optional: List all files with their timestamps for debugging
                            Write-Host "All files in folder with timestamps:"
                            foreach ($File in $Files) {
                                Write-Host "  - $($File.Name) (Modified: $($File.LastWriteTime))"
                            }
                        } else {
                            Write-Host "Found $($RecentFiles.Count) recent file(s) to download"
                            
                            foreach ($File in $RecentFiles) {
                                $RemoteFilePath = $File.FullName
                                $LocalFilePath = Join-Path $LocalSubfolderPath $File.Name
                                
                                Write-Host "Downloading $RemoteFilePath to $LocalFilePath..."
                                Write-Host "Local subfolder path: $LocalSubfolderPath"
                                Write-Host "Local subfolder exists: $(Test-Path $LocalSubfolderPath)"
                                
                                # Ensure the local subfolder exists before downloading
                                if (-not (Test-Path -Path $LocalSubfolderPath)) {
                                    Write-Host "Creating missing local subfolder: $LocalSubfolderPath"
                                    New-Item -ItemType Directory -Path $LocalSubfolderPath -Force | Out-Null
                                }
                                
                                try {
                                    Get-SFTPItem -SessionId $SftpSession.SessionId -Path $RemoteFilePath -Destination $LocalSubfolderPath -Force
                                    Write-Host "Successfully downloaded: $($File.Name)"
                                } catch {
                                    Write-Error "Failed to download $($File.Name): $($_.Exception.Message)"
                                }
                            }
                        }
                    }
                } catch {
                    Write-Error "Error accessing subfolder ${RemoteSubfolderPath}: $($_.Exception.Message)"
                }
            }
        }
        
        # === Clean Up SFTP Session ===
        Remove-SFTPSession -SessionId $SftpSession.SessionId
        Write-Host "SFTP session closed."
        
    } else {
        Write-Error "Failed to establish SFTP connection."
    }
} catch {
    Write-Error "Script error: $($_.Exception.Message)"
}

Write-Host "Script execution completed."
Stop-Transcript