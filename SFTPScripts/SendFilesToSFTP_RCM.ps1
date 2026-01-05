# === Setup Logging ===
$LogFile = "C:\Scripts\VM_SFTP_RCM_Log.txt"
Clear-Content -Path $LogFile -ErrorAction SilentlyContinue
Start-Transcript -Path $LogFile

# === Parameters ===
$SftpHost = "eu-central-1.sftpcloud.io"
$SftpUsername = "e5cb0849ee524c5382578efe87ab6521"
$SftpPassword = "qZXRXsndh8JkjDwDDQA2v06DRWcT9akv"
# $RemoteBaseFolder = "/RCMEDI/IncomingFiles"
# $LocalBaseFolder = "C:\RCMFiles\Python\Dataloader\Fetched Files from RCM"

# $SftpHost = "acoenoc.blob.core.windows.net"
# $SftpUsername = "acoenoc.pvignesh"
# $SftpPassword = "f08mSIkxVhBmIPp9+BYdiXjnW0HrS1i7"
$RemoteBaseFolder = "/rcmedi/inbound"
$LocalBaseFolder = "C:/RCMFILES/Outbound"

# === Check if Local Base Directory Exists ===
if (-not (Test-Path -Path $LocalBaseFolder)) {
    Write-Error "Local base folder does not exist: $LocalBaseFolder"
    Stop-Transcript
    exit 1
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
        
        # === Get List of Local Subfolders ===
        Write-Host "Checking for local subfolders in: $LocalBaseFolder"
        $LocalSubfolders = Get-ChildItem -Path $LocalBaseFolder -Directory
        
        if (-not $LocalSubfolders) {
            Write-Host "No local subfolders found in $LocalBaseFolder"
        } else {
            Write-Host "Found $($LocalSubfolders.Count) local subfolder(s)"
            
            foreach ($LocalSubfolder in $LocalSubfolders) {
                $LocalSubfolderPath = $LocalSubfolder.FullName
                $RemoteSubfolderPath = "$RemoteBaseFolder/$($LocalSubfolder.Name)"
                
                Write-Host "Processing local subfolder: $($LocalSubfolder.Name)"
                Write-Host "Local path: $LocalSubfolderPath"
                Write-Host "Target remote path: $RemoteSubfolderPath"
                
                # Check if remote subfolder exists, create if it doesn't
                try {
                    $RemoteSubfolderExists = Get-SFTPChildItem -SessionId $SftpSession.SessionId -Path $RemoteBaseFolder | Where-Object { $_.Name -eq $LocalSubfolder.Name -and $_.IsDirectory }
                    
                    if (-not $RemoteSubfolderExists) {
                        Write-Host "Remote subfolder doesn't exist, creating: $RemoteSubfolderPath"
                        try {
                            New-SFTPItem -SessionId $SftpSession.SessionId -Path $RemoteSubfolderPath -ItemType Directory
                            Write-Host "Successfully created remote folder: $RemoteSubfolderPath"
                        } catch {
                            Write-Error "Failed to create remote folder ${RemoteSubfolderPath}: $($_.Exception.Message)"
                            continue
                        }
                    } else {
                        Write-Host "Remote subfolder already exists: $RemoteSubfolderPath"
                    }
                    
                    # Get files in the local subfolder
                    $LocalFiles = Get-ChildItem -Path $LocalSubfolderPath -File
                    
                    if (-not $LocalFiles) {
                        Write-Host "No files found in local folder: $LocalSubfolderPath"
                    } else {
                        Write-Host "Found $($LocalFiles.Count) total file(s) in local folder"
                        
                        # Filter files modified/created within last 24 hours
                        $ThresholdTime = (Get-Date).AddHours(-24)
                        Write-Host "Looking for files modified/created after: $ThresholdTime"
                        
                        $RecentFiles = $LocalFiles | Where-Object { 
                            ($_.LastWriteTime -gt $ThresholdTime) -or ($_.CreationTime -gt $ThresholdTime)
                        }
                        
                        if (-not $RecentFiles) {
                            Write-Host "No files modified/created in the last 24 hours in $LocalSubfolderPath"
                            # Optional: List all files with their timestamps for debugging
                            Write-Host "All files in folder with timestamps:"
                            foreach ($File in $LocalFiles) {
                                Write-Host "  - $($File.Name) (Modified: $($File.LastWriteTime), Created: $($File.CreationTime))"
                            }
                        } else {
                            Write-Host "Found $($RecentFiles.Count) recent file(s) to upload"
                            
                            foreach ($LocalFile in $RecentFiles) {
                                $LocalFilePath = $LocalFile.FullName
                                $RemoteFilePath = "$RemoteSubfolderPath/$($LocalFile.Name)"
                                
                                Write-Host "Uploading $LocalFilePath to $RemoteFilePath..."
                                
                                try {
                                    # Check if remote file already exists
                                    $RemoteFileExists = $false
                                    try {
                                        $ExistingRemoteFiles = Get-SFTPChildItem -SessionId $SftpSession.SessionId -Path $RemoteSubfolderPath | Where-Object { -not $_.IsDirectory }
                                        $RemoteFileExists = $ExistingRemoteFiles | Where-Object { $_.Name -eq $LocalFile.Name }
                                    } catch {
                                        # Folder might not exist or be accessible, continue with upload
                                    }
                                    
                                    if ($RemoteFileExists) {
                                        Write-Host "File already exists remotely, overwriting: $($LocalFile.Name)"
                                    } else {
                                        Write-Host "Uploading new file: $($LocalFile.Name)"
                                    }
                                    
                                    Set-SFTPItem -SessionId $SftpSession.SessionId -Path $LocalFilePath -Destination $RemoteSubfolderPath -Force
                                    Write-Host "Successfully uploaded: $($LocalFile.Name)"
                                    
                                    # Optional: Move or delete local file after successful upload
                                    # Uncomment one of the following lines if you want to clean up after upload:
                                    
                                    # Move to processed folder:
                                    # $ProcessedFolder = Join-Path $LocalBaseFolder "Processed\$($LocalSubfolder.Name)"
                                    # if (-not (Test-Path $ProcessedFolder)) { New-Item -ItemType Directory -Path $ProcessedFolder -Force | Out-Null }
                                    # Move-Item -Path $LocalFilePath -Destination $ProcessedFolder -Force
                                    # Write-Host "Moved processed file to: $ProcessedFolder"
                                    
                                    # Or delete the file:
                                    # Remove-Item -Path $LocalFilePath -Force
                                    # Write-Host "Deleted local file after upload: $($LocalFile.Name)"
                                    
                                } catch {
                                    Write-Error "Failed to upload $($LocalFile.Name): $($_.Exception.Message)"
                                }
                            }
                        }
                    }
                    
                } catch {
                    Write-Error "Error processing subfolder ${LocalSubfolderPath}: $($_.Exception.Message)"
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

Write-Host "Upload script execution completed."
Stop-Transcript