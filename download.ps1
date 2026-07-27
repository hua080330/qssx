# ============================================================
# Qiusuo Mathmatica Interactive Downloader v2.0
# ============================================================
# A powerful interactive downloader with Metasploit-like CLI
# Commands: list, search, dl, bg, jobs, fg, stop, set, show, save, use, add, repos, muldl, script, info, help
# ============================================================

#requires -Version 5.0

#region Initialization
$script:version = "2.0.0"
$script:repoOwner = "hua080330"
$script:repoName = "qssx"
$script:repoType = "remote"
$script:localPath = $null

# GitHub API URL
$script:apiUrl = "https://api.github.com/repos/$script:repoOwner/$script:repoName/contents/"

# GitHub 加速代理列表
$script:proxyList = @(
    "https://ghproxy.net/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
    "https://ghproxy.com/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
    "https://hub.fastgit.xyz/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
    "https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/"
)

# 多仓库源
$script:repoSources = @{
    "default" = @{
        owner = "hua080330"
        name = "qssx"
        type = "remote"
    }
}
$script:activeRepo = "default"

# 配置文件路径
$script:configDir = "$env:USERPROFILE\.qiusuo"
$script:configFile = Join-Path $script:configDir "config.json"
$script:historyFile = Join-Path $script:configDir "history.txt"
$script:logFile = Join-Path $script:configDir "logs\download.log"
$script:statsFile = Join-Path $script:configDir "stats.json"
$script:profilesDir = Join-Path $script:configDir "profiles"

# 创建配置目录
if (-not (Test-Path $script:configDir)) {
    New-Item -ItemType Directory -Path $script:configDir -Force | Out-Null
}
if (-not (Test-Path $script:profilesDir)) {
    New-Item -ItemType Directory -Path $script:profilesDir -Force | Out-Null
}
$subDirs = @("logs", "downloads")
foreach ($sub in $subDirs) {
    $path = Join-Path $script:configDir $sub
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

# 默认配置
$script:defaultConfig = @{
    DOWNLOAD_DIR   = Join-Path $script:configDir "downloads"
    PROXY_INDEX    = 1
    AUTO_CONFIRM   = $true
    THREADS        = 4
    SPEED_LIMIT    = 0
    RESUME         = $true
    LOG_LEVEL      = "INFO"
    SHOW_PROGRESS   = $true
    ACTIVE_PROFILE = "default"
}

$script:config = @{}
$script:profiles = @{}
$script:fileCache = $null
$script:commandHistory = @()
$script:historyIndex = -1
#endregion

#region Self-Bootstrap (Auto-create directories and config)
$script:configDir = "$env:USERPROFILE\.qiusuo"
$script:profilesDir = Join-Path $script:configDir "profiles"
$script:downloadsDir = Join-Path $script:configDir "downloads"
$script:logsDir = Join-Path $script:configDir "logs"

$dirs = @($script:configDir, $script:profilesDir, $script:downloadsDir, $script:logsDir)
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "[BOOTSTRAP] Created: $dir" -ForegroundColor Gray
    }
}

$script:configFile = Join-Path $script:configDir "config.json"
if (-not (Test-Path $script:configFile)) {
    $defaultConfig = @{
        DOWNLOAD_DIR   = $script:downloadsDir
        PROXY_INDEX    = 1
        AUTO_CONFIRM   = $true
        THREADS        = 4
        SPEED_LIMIT    = 0
        RESUME         = $true
        LOG_LEVEL      = "INFO"
        SHOW_PROGRESS   = $true
        ACTIVE_PROFILE = "default"
    } | ConvertTo-Json
    Set-Content -Path $script:configFile -Value $defaultConfig
    Write-Host "[BOOTSTRAP] Created default config: $script:configFile" -ForegroundColor Gray
}
#endregion

#region Helper Functions
function Write-ErrorMsg {
    param([string]$Message, [string]$Solution = "")
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    if ($Solution) {
        Write-Host "[TIP] $Solution" -ForegroundColor Yellow
    }
    Write-Log -Message $Message -Level "ERROR"
}

function Write-SuccessMsg {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    Write-Log -Message $Message -Level "INFO"
}

function Write-InfoMsg {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
    Write-Log -Message $Message -Level "INFO"
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
    Write-Log -Message $Message -Level "WARN"
}

function Write-OutputMsg {
    param([string]$Message)
    Write-Host $Message -ForegroundColor White
}

function Write-CommandMsg {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Magenta
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:logFile -Value $logEntry -ErrorAction SilentlyContinue
}

function Format-FileSize {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
    }
}

function Get-FileIcon {
    param([string]$FileName)
    $ext = [System.IO.Path]::GetExtension($FileName).ToLower()
    switch ($ext) {
        ".apk" { return "📦" }
        ".ipa" { return "🍎" }
        ".exe" { return "⚙️" }
        ".msi" { return "📦" }
        ".zip" { return "🗜️" }
        ".rar" { return "🗜️" }
        ".7z" { return "🗜️" }
        ".pdf" { return "📄" }
        ".txt" { return "📝" }
        ".md" { return "📝" }
        ".json" { return "🔧" }
        ".xml" { return "🔧" }
        ".png" { return "🖼️" }
        ".jpg" { return "🖼️" }
        ".jpeg" { return "🖼️" }
        default { return "📄" }
    }
}
#endregion

#region Config Management
function Load-Config {
    if (Test-Path $script:configFile) {
        try {
            $json = Get-Content $script:configFile -Raw | ConvertFrom-Json
            foreach ($key in $json.PSObject.Properties) {
                $script:config[$key.Name] = $key.Value
            }
            if (-not $script:config.ContainsKey("ACTIVE_PROFILE")) {
                $script:config["ACTIVE_PROFILE"] = "default"
            }
            Write-InfoMsg "Configuration loaded"
            Write-Log "Configuration loaded" "INFO"
        }
        catch {
            Write-ErrorMsg "Failed to load config file" "Using default settings"
            $script:config = $script:defaultConfig.Clone()
        }
    }
    else {
        $script:config = $script:defaultConfig.Clone()
        Save-Config
    }
}

function Save-Config {
    try {
        $json = $script:config | ConvertTo-Json
        Set-Content -Path $script:configFile -Value $json
        Write-InfoMsg "Configuration saved"
        Write-Log "Configuration saved" "INFO"
    }
    catch {
        Write-ErrorMsg "Failed to save config file" "Check write permissions"
    }
}

function Save-Profile {
    param([string]$ProfileName)
    $profileFile = Join-Path $script:profilesDir "profile_$ProfileName.json"
    $profile = @{}
    foreach ($key in $script:config.Keys) {
        if ($key -ne "ACTIVE_PROFILE") {
            $profile[$key] = $script:config[$key]
        }
    }
    try {
        $profile | ConvertTo-Json | Set-Content -Path $profileFile
        $script:profiles[$ProfileName] = $profile
        Write-SuccessMsg "Profile '$ProfileName' saved"
        Write-Log "Profile '$ProfileName' saved" "INFO"
    }
    catch {
        Write-ErrorMsg "Failed to save profile '$ProfileName'" "Check write permissions"
    }
}

function Load-Profile {
    param([string]$ProfileName)
    $profileFile = Join-Path $script:profilesDir "profile_$ProfileName.json"
    if (Test-Path $profileFile) {
        try {
            $profile = Get-Content $profileFile -Raw | ConvertFrom-Json
            foreach ($key in $profile.PSObject.Properties) {
                $script:config[$key.Name] = $key.Value
            }
            $script:config["ACTIVE_PROFILE"] = $ProfileName
            Save-Config
            Write-SuccessMsg "Switched to profile '$ProfileName'"
            Write-Log "Switched to profile '$ProfileName'" "INFO"
        }
        catch {
            Write-ErrorMsg "Failed to load profile '$ProfileName'" "File may be corrupted"
        }
    }
    else {
        Write-ErrorMsg "Profile '$ProfileName' not found" "Use 'save <name>' to create a profile"
    }
}
#endregion

#region Display Config
function Show-Config {
    Write-Host "`n[*] Current Configuration:" -ForegroundColor Cyan
    Write-Host ("=" * 65) -ForegroundColor DarkGray
    Write-Host "  DOWNLOAD_DIR   = $($script:config.DOWNLOAD_DIR)" -ForegroundColor White
    Write-Host "  PROXY_INDEX    = $($script:config.PROXY_INDEX) ($($script:proxyList[$script:config.PROXY_INDEX-1]))" -ForegroundColor White
    Write-Host "  THREADS        = $($script:config.THREADS)" -ForegroundColor White
    Write-Host "  SPEED_LIMIT    = $($script:config.SPEED_LIMIT) KB/s (0 = unlimited)" -ForegroundColor White
    Write-Host "  RESUME         = $($script:config.RESUME)" -ForegroundColor White
    Write-Host "  AUTO_CONFIRM   = $($script:config.AUTO_CONFIRM)" -ForegroundColor White
    Write-Host "  LOG_LEVEL      = $($script:config.LOG_LEVEL)" -ForegroundColor White
    Write-Host "  ACTIVE_PROFILE = $($script:config.ACTIVE_PROFILE)" -ForegroundColor White
    Write-Host ("=" * 65) -ForegroundColor DarkGray
}

function Set-ConfigItem {
    param([string]$Key, [string]$Value)
    switch ($Key.ToUpper()) {
        "DOWNLOAD_DIR" {
            if (Test-Path $Value) {
                $script:config.DOWNLOAD_DIR = $Value
                Write-SuccessMsg "DOWNLOAD_DIR set to '$Value'"
                Write-Log "DOWNLOAD_DIR set to '$Value'" "INFO"
            }
            else {
                Write-ErrorMsg "Directory does not exist: $Value" "Create the directory first or use a valid path"
            }
        }
        "PROXY_INDEX" {
            $idx = [int]$Value
            if ($idx -ge 1 -and $idx -le $script:proxyList.Count) {
                $script:config.PROXY_INDEX = $idx
                Write-SuccessMsg "PROXY_INDEX set to $idx ($($script:proxyList[$idx-1]))"
                Write-Log "PROXY_INDEX set to $idx" "INFO"
            }
            else {
                Write-ErrorMsg "Invalid PROXY_INDEX: $Value" "Valid range: 1-$($script:proxyList.Count)"
            }
        }
        "THREADS" {
            $threads = [int]$Value
            if ($threads -ge 1 -and $threads -le 32) {
                $script:config.THREADS = $threads
                Write-SuccessMsg "THREADS set to $threads"
                Write-Log "THREADS set to $threads" "INFO"
            }
            else {
                Write-ErrorMsg "Invalid THREADS: $Value" "Valid range: 1-32"
            }
        }
        "SPEED_LIMIT" {
            $limit = [int]$Value
            if ($limit -ge 0) {
                $script:config.SPEED_LIMIT = $limit
                if ($limit -eq 0) {
                    Write-SuccessMsg "SPEED_LIMIT disabled (unlimited)"
                }
                else {
                    Write-SuccessMsg "SPEED_LIMIT set to $limit KB/s"
                }
                Write-Log "SPEED_LIMIT set to $limit" "INFO"
            }
            else {
                Write-ErrorMsg "Invalid SPEED_LIMIT: $Value" "Use 0 for unlimited, or positive number for KB/s"
            }
        }
        "RESUME" {
            $val = $Value.ToLower()
            if ($val -eq "true" -or $val -eq "false") {
                $script:config.RESUME = [bool]::Parse($val)
                Write-SuccessMsg "RESUME set to $val"
                Write-Log "RESUME set to $val" "INFO"
            }
            else {
                Write-ErrorMsg "Invalid RESUME value: $Value" "Use 'true' or 'false'"
            }
        }
        "AUTO_CONFIRM" {
            $val = $Value.ToLower()
            if ($val -eq "true" -or $val -eq "false") {
                $script:config.AUTO_CONFIRM = [bool]::Parse($val)
                Write-SuccessMsg "AUTO_CONFIRM set to $val"
                Write-Log "AUTO_CONFIRM set to $val" "INFO"
            }
            else {
                Write-ErrorMsg "Invalid AUTO_CONFIRM value: $Value" "Use 'true' or 'false'"
            }
        }
        "LOG_LEVEL" {
            $val = $Value.ToUpper()
            if ($val -in @("DEBUG", "INFO", "WARN", "ERROR")) {
                $script:config.LOG_LEVEL = $val
                Write-SuccessMsg "LOG_LEVEL set to $val"
                Write-Log "LOG_LEVEL set to $val" "INFO"
            }
            else {
                Write-ErrorMsg "Invalid LOG_LEVEL: $Value" "Valid values: DEBUG, INFO, WARN, ERROR"
            }
        }
        default {
            Write-ErrorMsg "Unknown config key: $Key" "Available keys: DOWNLOAD_DIR, PROXY_INDEX, THREADS, SPEED_LIMIT, RESUME, AUTO_CONFIRM, LOG_LEVEL"
        }
    }
    Save-Config
}
#endregion

#region Repository Management
function Switch-Repo {
    param([string]$RepoName)
    if ($script:repoSources.ContainsKey($RepoName)) {
        $repo = $script:repoSources[$RepoName]
        $script:repoOwner = $repo.owner
        $script:repoName = $repo.name
        $script:repoType = $repo.type
        $script:activeRepo = $RepoName
        $script:apiUrl = "https://api.github.com/repos/$script:repoOwner/$script:repoName/contents/"
        $script:proxyList = @(
            "https://ghproxy.net/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
            "https://ghproxy.com/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
            "https://hub.fastgit.xyz/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
            "https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/"
        )
        $script:fileCache = $null
        Write-SuccessMsg "Switched to repository '$RepoName' ($script:repoOwner/$script:repoName)"
        Write-Log "Switched to repository '$RepoName'" "INFO"
        Write-InfoMsg "Run 'list' to fetch files from new repository"
    }
    else {
        Write-ErrorMsg "Repository '$RepoName' not found" "Use 'repos' to see available repositories, or 'add repo' to add a new one"
    }
}

function Add-Repo {
    param([string]$RepoUrl)
    if ($RepoUrl -match 'github\.com/([^/]+)/([^/]+)') {
        $owner = $matches[1]
        $name = $matches[2]
        $repoId = "$owner/$name"
        $script:repoSources[$repoId] = @{
            owner = $owner
            name = $name
            type = "remote"
        }
        $script:repoOwner = $owner
        $script:repoName = $name
        $script:activeRepo = $repoId
        $script:apiUrl = "https://api.github.com/repos/$owner/$name/contents/"
        $script:proxyList = @(
            "https://ghproxy.net/https://raw.githubusercontent.com/$owner/$name/main/",
            "https://ghproxy.com/https://raw.githubusercontent.com/$owner/$name/main/",
            "https://hub.fastgit.xyz/https://raw.githubusercontent.com/$owner/$name/main/",
            "https://raw.githubusercontent.com/$owner/$name/main/"
        )
        $script:fileCache = $null
        Write-SuccessMsg "Repository '$repoId' added and set as active"
        Write-Log "Repository '$repoId' added" "INFO"
        Write-InfoMsg "Run 'list' to fetch files from new repository"
    }
    else {
        Write-ErrorMsg "Invalid GitHub URL: $RepoUrl" "Format: https://github.com/username/reponame"
    }
}

function Show-Repos {
    Write-Host "`n[*] Available Repositories in sources:" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor DarkGray
    foreach ($key in $script:repoSources.Keys) {
        $marker = if ($key -eq $script:activeRepo) { " [ACTIVE]" } else { "" }
        Write-Host "  $key$marker" -ForegroundColor White
    }
    Write-Host ("=" * 50) -ForegroundColor DarkGray
}

function Search-Repos {
    param([string]$Keyword = "")
    
    Write-InfoMsg "Searching repositories under $script:repoOwner..."
    
    try {
        $searchUrl = "https://api.github.com/users/$script:repoOwner/repos?per_page=100"
        $response = Invoke-RestMethod -Uri $searchUrl -UseBasicParsing -ErrorAction Stop
        
        $repos = $response | Where-Object { 
            if ($Keyword) {
                $_.name -like "*$Keyword*"
            } else {
                $true
            }
        }
        
        if ($repos.Count -eq 0) {
            Write-ErrorMsg "No repositories found matching '$Keyword'" "Try a different keyword"
            return
        }
        
        Write-Host "`n[*] Available Repositories under $script:repoOwner:" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor DarkGray
        
        $index = 1
        foreach ($repo in $repos) {
            $marker = if ($repo.name -eq $script:repoName) { " [ACTIVE]" } else { "" }
            $isPrivate = if ($repo.private) { "🔒" } else { "🌐" }
            Write-Host " [$index] $isPrivate $($repo.name)$marker" -ForegroundColor White
            if ($repo.description) {
                Write-Host "      $($repo.description)" -ForegroundColor Gray
            }
            $index++
        }
        Write-Host ("=" * 60) -ForegroundColor DarkGray
        
        $choice = Read-Host "[?] Enter number to switch, or 0 to cancel"
        if ($choice -match '^\d+$') {
            $idx = [int]$choice
            if ($idx -ge 1 -and $idx -le $repos.Count) {
                $selected = $repos[$idx-1]
                $script:repoName = $selected.name
                $script:apiUrl = "https://api.github.com/repos/$script:repoOwner/$script:repoName/contents/"
                $script:proxyList = @(
                    "https://ghproxy.net/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
                    "https://ghproxy.com/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
                    "https://hub.fastgit.xyz/https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/",
                    "https://raw.githubusercontent.com/$script:repoOwner/$script:repoName/main/"
                )
                $script:fileCache = $null
                Write-SuccessMsg "Switched to repository: $script:repoOwner/$script:repoName"
                Write-Log "Switched to repository: $script:repoOwner/$script:repoName" "INFO"
                Write-InfoMsg "Run 'list' to fetch files from new repository"
            }
        }
    }
    catch {
        Write-ErrorMsg "Failed to search repositories: $_" "Check network or repository visibility"
    }
}
#endregion

#region File List Functions
function Update-FileList {
    Write-InfoMsg "Fetching file list from $script:repoOwner/$script:repoName..."
    Write-Log "Fetching file list" "INFO"
    
    try {
        if ($script:repoType -eq "local" -and $script:localPath) {
            $script:fileCache = Get-ChildItem -Path $script:localPath -File | ForEach-Object {
                [PSCustomObject]@{
                    name = $_.Name
                    size = $_.Length
                    path = $_.FullName
                    download_url = $_.FullName
                    created_at = $_.CreationTime.ToString("yyyy-MM-dd")
                    type = "file"
                }
            }
            Write-SuccessMsg "Loaded $($script:fileCache.Count) files from local path"
        }
        else {
            $response = Invoke-RestMethod -Uri $script:apiUrl -UseBasicParsing -ErrorAction Stop
            $script:fileCache = $response | Where-Object { $_.type -eq "file" }
            Write-SuccessMsg "Loaded $($script:fileCache.Count) files from GitHub API"
        }
        return $true
    }
    catch {
        Write-ErrorMsg "Failed to fetch file list: $_" "Check your network connection and try again. Run 'list' to retry."
        Write-Log "Failed to fetch file list: $_" "ERROR"
        return $false
    }
}

function Show-FileList {
    param([string]$Filter = "*")
    
    if ($null -eq $script:fileCache) {
        Write-ErrorMsg "No file list available" "Run 'list' to fetch files from repository"
        return
    }
    
    $filtered = $script:fileCache | Where-Object { $_.name -like $Filter }
    if ($filtered.Count -eq 0) {
        Write-ErrorMsg "No files matching '$Filter'" "Try a different pattern or run 'list' to see all files"
        return
    }
    
    $pageSize = 20
    $totalPages = [math]::Ceiling($filtered.Count / $pageSize)
    $currentPage = 1
    
    while ($true) {
        $start = ($currentPage - 1) * $pageSize
        $end = [math]::Min($start + $pageSize, $filtered.Count)
        
        Write-Host "`n[*] Available Files (Page $currentPage/$totalPages, $($filtered.Count) total):" -ForegroundColor Cyan
        Write-Host ("=" * 80) -ForegroundColor DarkGray
        
        for ($i = $start; $i -lt $end; $i++) {
            $file = $filtered[$i]
            $magNo = ($i + 1).ToString("000000")
            $sizeStr = Format-FileSize -Bytes $file.size
            $icon = Get-FileIcon -FileName $file.name
            $dateStr = if ($file.created_at) { $file.created_at.Split('T')[0] } else { "Unknown" }
            
            Write-Host " [$magNo]" -ForegroundColor Yellow -NoNewline
            Write-Host " $icon $($file.name)" -ForegroundColor White -NoNewline
            Write-Host " ($sizeStr)" -ForegroundColor Gray -NoNewline
            Write-Host " $dateStr" -ForegroundColor DarkGray
        }
        
        Write-Host ("=" * 80) -ForegroundColor DarkGray
        
        if ($filtered.Count -le $pageSize) { break }
        
        Write-Host "[N]ext page, [P]revious page, [Q]uit: " -ForegroundColor Cyan -NoNewline
        $choice = Read-Host
        switch ($choice.ToUpper()) {
            "N" { if ($currentPage -lt $totalPages) { $currentPage++ } else { Write-WarningMsg "Already on last page" } }
            "P" { if ($currentPage -gt 1) { $currentPage-- } else { Write-WarningMsg "Already on first page" } }
            "Q" { break }
            default { Write-WarningMsg "Invalid input. Use N, P, or Q" }
        }
    }
}
#endregion

#region Search Functions
function Search-Files {
    param([string]$Pattern)
    
    if ($null -eq $script:fileCache) {
        Write-ErrorMsg "No file list available" "Run 'list' to fetch files first"
        return
    }
    
    $results = @()
    
    if ($Pattern -match '^\d{6}$') {
        $magNo = [int]$Pattern
        if ($magNo -ge 1 -and $magNo -le $script:fileCache.Count) {
            $file = $script:fileCache[$magNo-1]
            $results += $file
        }
    }
    else {
        $results = $script:fileCache | Where-Object { $_.name -like "*$Pattern*" }
    }
    
    if ($results.Count -eq 0) {
        Write-ErrorMsg "No files matching '$Pattern'" "Try a different keyword or use 'list' to see all files"
        return
    }
    
    Write-Host "`n[*] Search Results for '$Pattern' ($($results.Count) matches):" -ForegroundColor Cyan
    Write-Host ("=" * 75) -ForegroundColor DarkGray
    
    foreach ($file in $results) {
        $globalIdx = ($script:fileCache | ForEach-Object { $_.name } | Where-Object { $_ -eq $file.name }).Count
        $magNo = ($script:fileCache.IndexOf($file) + 1).ToString("000000")
        $sizeStr = Format-FileSize -Bytes $file.size
        $icon = Get-FileIcon -FileName $file.name
        
        Write-Host " [$magNo]" -ForegroundColor Yellow -NoNewline
        Write-Host " $icon $($file.name)" -ForegroundColor White -NoNewline
        Write-Host " ($sizeStr)" -ForegroundColor Gray
    }
    Write-Host ("=" * 75) -ForegroundColor DarkGray
}
#endregion

#region Download Functions
function Get-DownloadUrl {
    param([string]$FileName)
    $proxyIndex = $script:config.PROXY_INDEX - 1
    if ($proxyIndex -lt 0) { $proxyIndex = 0 }
    if ($proxyIndex -ge $script:proxyList.Count) { $proxyIndex = 0 }
    $baseUrl = $script:proxyList[$proxyIndex]
    return $baseUrl + $FileName
}

function Show-ProgressBar {
    param(
        [int]$Percent,
        [string]$Speed = "",
        [string]$Remaining = "",
        [string]$Downloaded = "",
        [string]$Total = ""
    )
    $barLength = 30
    $filled = [math]::Floor($Percent / 100 * $barLength)
    $empty = $barLength - $filled
    $bar = "[" + ("=" * $filled) + (" " * $empty) + "]"
    
    $info = "$bar $Percent%"
    if ($Speed) { $info += " | $Speed" }
    if ($Remaining) { $info += " | ETA: $Remaining" }
    if ($Downloaded -and $Total) { $info += " | $Downloaded / $Total" }
    
    Write-Host "`r$info" -NoNewline -ForegroundColor Cyan
}

function Download-File {
    param(
        [string]$FileName,
        [int]$Index = -1,
        [int]$CustomThreads = -1,
        [int]$CustomSpeedLimit = -1,
        [switch]$Background
    )
    
    if ($null -eq $script:fileCache) {
        Write-ErrorMsg "No file list available" "Run 'list' to fetch files first"
        return $false
    }
    
    $targetFile = $null
    if ($Index -gt 0 -and $Index -le $script:fileCache.Count) {
        $targetFile = $script:fileCache[$Index-1]
    }
    elseif (-not [string]::IsNullOrWhiteSpace($FileName)) {
        $targetFile = $script:fileCache | Where-Object { $_.name -eq $FileName } | Select-Object -First 1
        if ($null -eq $targetFile) {
            $matches = $script:fileCache | Where-Object { $_.name -like "*$FileName*" }
            if ($matches.Count -eq 1) {
                $targetFile = $matches[0]
                Write-WarningMsg "Multiple matches found, using: $($targetFile.name)"
            }
            elseif ($matches.Count -gt 1) {
                Write-ErrorMsg "Multiple files match '$FileName'" "Use the MagNo. (e.g., 'dl 3') for exact selection"
                $matches | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Gray }
                return $false
            }
        }
    }
    
    if ($null -eq $targetFile) {
        Write-ErrorMsg "File not found: $FileName" "Use 'list' to see available files or 'search' to find files"
        return $false
    }
    
    $fileName = $targetFile.name
    $fileSize = $targetFile.size
    $savePath = Join-Path -Path $script:config.DOWNLOAD_DIR -ChildPath $fileName
    $tempPath = $savePath + ".part"
    $sizeStr = Format-FileSize -Bytes $fileSize
    
    $resumeMode = $false
    if (Test-Path $tempPath) {
        $existingSize = (Get-Item $tempPath).Length
        if ($existingSize -lt $fileSize) {
            if ($script:config.RESUME) {
                if (-not $Background) {
                    $confirm = Read-Host "[?] Incomplete download found. Resume? (y/n)"
                    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                        $resumeMode = $true
                        Write-InfoMsg "Resuming download from $existingSize bytes"
                        Write-Log "Resuming download: $fileName" "INFO"
                    }
                    else {
                        Write-InfoMsg "Starting fresh download"
                        Remove-Item $tempPath -Force
                    }
                }
                else {
                    $resumeMode = $true
                    Write-InfoMsg "Resuming download from $existingSize bytes"
                }
            }
            else {
                Write-InfoMsg "Resume disabled. Starting fresh download"
                Remove-Item $tempPath -Force
            }
        }
        elseif ($existingSize -eq $fileSize) {
            Write-SuccessMsg "File already downloaded: $fileName"
            return $true
        }
    }
    
    if (-not $Background -and $script:config.AUTO_CONFIRM) {
        $confirm = Read-Host "[?] Download '$fileName' ($sizeStr) to '$($script:config.DOWNLOAD_DIR)'? (y/n)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-InfoMsg "Download cancelled"
            Write-Log "Download cancelled: $fileName" "INFO"
            return $false
        }
    }
    
    $downloadUrl = Get-DownloadUrl -FileName $fileName
    $threads = if ($CustomThreads -gt 0) { $CustomThreads } else { $script:config.THREADS }
    $speedLimit = if ($CustomSpeedLimit -gt 0) { $CustomSpeedLimit } else { $script:config.SPEED_LIMIT }
    
    Write-InfoMsg "Downloading: $fileName ($sizeStr) with $threads threads"
    Write-Log "Downloading: $fileName" "INFO"
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Qiusuo-Downloader/2.0")
        
        $lastPercent = 0
        $startTime = Get-Date
        $lastBytes = 0
        
        Register-ObjectEvent -InputObject $webClient -EventName "DownloadProgressChanged" -Action {
            $percent = $EventArgs.BytesReceived / $EventArgs.TotalBytesToReceive * 100
            $downloaded = Format-FileSize -Bytes $EventArgs.BytesReceived
            $total = Format-FileSize -Bytes $EventArgs.TotalBytesToReceive
            $elapsed = (Get-Date) - $startTime
            $speed = if ($elapsed.TotalSeconds -gt 0) { 
                $bytesPerSec = $EventArgs.BytesReceived / $elapsed.TotalSeconds
                Format-FileSize -Bytes $bytesPerSec + "/s"
            } else { "0 B/s" }
            $remainingSec = if ($speed -gt 0 -and $speed -ne "0 B/s") {
                $speedBytes = [int]($bytesPerSec)
                if ($speedBytes -gt 0) {
                    $remaining = ($EventArgs.TotalBytesToReceive - $EventArgs.BytesReceived) / $speedBytes
                    [TimeSpan]::FromSeconds($remaining).ToString("hh\:mm\:ss")
                } else { "unknown" }
            } else { "unknown" }
            if ($percent - $lastPercent -ge 1) {
                Show-ProgressBar -Percent [int]$percent -Speed $speed -Remaining $remainingSec -Downloaded $downloaded -Total $total
                $lastPercent = [int]$percent
            }
        } | Out-Null
        
        if ($resumeMode -and (Test-Path $tempPath)) {
            $webClient.DownloadFile($downloadUrl, $tempPath)
            Move-Item -Path $tempPath -Destination $savePath -Force
        }
        else {
            $webClient.DownloadFile($downloadUrl, $savePath)
        }
        
        Write-Host "`n"
        Write-SuccessMsg "Download completed: $fileName"
        Write-Log "Download completed: $fileName" "INFO"
        return $true
    }
    catch {
        Write-Host "`n"
        Write-ErrorMsg "Download failed: $_" "Check network connection and try again. You may try a different proxy with 'set PROXY_INDEX x'"
        Write-Log "Download failed: $fileName - $_" "ERROR"
        return $false
    }
}
#endregion

#region Background Job Management
$script:backgroundJobs = @{}
$script:nextJobId = 1

function Start-BackgroundDownload {
    param([string]$FileName, [int]$Index = -1, [int]$CustomThreads = -1)
    
    if ($null -eq $script:fileCache) {
        Write-ErrorMsg "No file list available" "Run 'list' to fetch files first"
        return
    }
    
    $targetFile = $null
    if ($Index -gt 0 -and $Index -le $script:fileCache.Count) {
        $targetFile = $script:fileCache[$Index-1]
    }
    elseif (-not [string]::IsNullOrWhiteSpace($FileName)) {
        $targetFile = $script:fileCache | Where-Object { $_.name -eq $FileName } | Select-Object -First 1
        if ($null -eq $targetFile) {
            $matches = $script:fileCache | Where-Object { $_.name -like "*$FileName*" }
            if ($matches.Count -eq 1) {
                $targetFile = $matches[0]
            }
            else {
                Write-ErrorMsg "File not found: $FileName" "Use 'list' to see available files"
                return
            }
        }
    }
    
    if ($null -eq $targetFile) {
        Write-ErrorMsg "File not found" "Use 'list' to see available files"
        return
    }
    
    $jobId = $script:nextJobId++
    $jobName = $targetFile.name
    $savePath = Join-Path $script:config.DOWNLOAD_DIR $jobName
    $downloadUrl = Get-DownloadUrl -FileName $jobName
    $threads = if ($CustomThreads -gt 0) { $CustomThreads } else { $script:config.THREADS }
    
    Write-InfoMsg "Starting background job # $jobId : $jobName"
    
    $jobScript = {
        param($url, $path, $threads, $configDir)
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($url, $path)
            return @{ Success = $true; Message = "Download completed" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    $job = Start-Job -Name "QS_Job_$jobId" -ScriptBlock $jobScript -ArgumentList $downloadUrl, $savePath, $threads, $script:configDir
    $script:backgroundJobs[$jobId] = @{
        Job = $job
        Name = $jobName
        Url = $downloadUrl
        Path = $savePath
        Status = "Running"
        StartTime = Get-Date
    }
    
    Write-SuccessMsg "Background job # $jobId started. Use 'jobs' to check status."
}

function Show-Jobs {
    Check-Jobs
    if ($script:backgroundJobs.Count -eq 0) {
        Write-InfoMsg "No background jobs"
        return
    }
    
    Write-Host "`n[*] Background Jobs:" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    
    foreach ($id in $script:backgroundJobs.Keys) {
        $job = $script:backgroundJobs[$id]
        $jobState = $job.Job.State
        $statusColor = if ($jobState -eq "Running") { "Green" } elseif ($jobState -eq "Completed") { "Cyan" } else { "Red" }
        $elapsed = (Get-Date) - $job.StartTime
        $elapsedStr = "{0:D2}:{1:D2}:{2:D2}" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds
        
        Write-Host "  [$id]" -ForegroundColor Yellow -NoNewline
        Write-Host " $($job.Name)" -ForegroundColor White -NoNewline
        Write-Host " [$jobState]" -ForegroundColor $statusColor -NoNewline
        Write-Host " $elapsedStr" -ForegroundColor Gray
    }
    Write-Host ("=" * 70) -ForegroundColor DarkGray
}

function Stop-JobById {
    param([int]$JobId)
    
    if ($script:backgroundJobs.ContainsKey($JobId)) {
        $job = $script:backgroundJobs[$JobId]
        Stop-Job -Job $job.Job
        $job.Status = "Stopped"
        Write-SuccessMsg "Stopped job # $JobId : $($job.Name)"
        Write-Log "Stopped background job # $JobId : $($job.Name)" "INFO"
    }
    else {
        Write-ErrorMsg "Job # $JobId not found" "Use 'jobs' to see running jobs"
    }
}

function Kill-JobById {
    param([int]$JobId)
    
    if ($script:backgroundJobs.ContainsKey($JobId)) {
        $job = $script:backgroundJobs[$JobId]
        Stop-Job -Job $job.Job -Force
        Remove-Job -Job $job.Job -Force
        $script:backgroundJobs.Remove($JobId)
        Write-SuccessMsg "Killed job # $JobId"
        Write-Log "Killed background job # $JobId" "INFO"
    }
    else {
        Write-ErrorMsg "Job # $JobId not found"
    }
}

function Foreground-Job {
    param([int]$JobId)
    
    if ($script:backgroundJobs.ContainsKey($JobId)) {
        $job = $script:backgroundJobs[$JobId]
        Write-InfoMsg "Bringing job # $JobId to foreground: $($job.Name)"
        Receive-Job -Job $job.Job -Wait -AutoRemoveJob
        $script:backgroundJobs.Remove($JobId)
        Write-SuccessMsg "Job # $JobId completed in foreground"
    }
    else {
        Write-ErrorMsg "Job # $JobId not found"
    }
}

function Check-Jobs {
    $completedJobs = @()
    foreach ($id in $script:backgroundJobs.Keys) {
        $job = $script:backgroundJobs[$id]
        if ($job.Job.State -eq "Completed") {
            $completedJobs += $id
        }
        elseif ($job.Job.State -eq "Failed") {
            Write-WarningMsg "Job # $id failed: $($job.Name)"
            $completedJobs += $id
        }
    }
    
    foreach ($id in $completedJobs) {
        $job = $script:backgroundJobs[$id]
        Receive-Job -Job $job.Job -ErrorAction SilentlyContinue
        Remove-Job -Job $job.Job -Force
        $script:backgroundJobs.Remove($id)
        Write-SuccessMsg "Background job # $id completed: $($job.Name)"
        Write-Log "Background job # $id completed: $($job.Name)" "INFO"
    }
}
#endregion

#region Other Commands
function Download-Batch {
    param([string]$Range, [int]$CustomThreads = -1)
    
    if ($null -eq $script:fileCache) {
        Write-ErrorMsg "No file list available" "Run 'list' to fetch files first"
        return
    }
    
    if ($Range -match '^(\d+)-(\d+)$') {
        $start = [int]$matches[1]
        $end = [int]$matches[2]
        if ($start -lt 1) { $start = 1 }
        if ($end -gt $script:fileCache.Count) { $end = $script:fileCache.Count }
        
        Write-InfoMsg "Batch downloading files $start to $end"
        for ($i = $start; $i -le $end; $i++) {
            Download-File -Index $i -CustomThreads $CustomThreads
        }
    }
    else {
        Write-ErrorMsg "Invalid batch range: $Range" "Use format: dl 1-5"
    }
}

function Show-FileInfo {
    param([string]$Input)
    
    if ($null -eq $script:fileCache) {
        Write-ErrorMsg "No file list available" "Run 'list' to fetch files first"
        return
    }
    
    $targetFile = $null
    
    # 方法1：按编号查找（纯数字）
    if ($Input -match '^\d+$') {
        $idx = [int]$Input
        if ($idx -ge 1 -and $idx -le $script:fileCache.Count) {
            $targetFile = $script:fileCache[$idx-1]
        }
    }
    # 方法2：按文件名精确匹配
    else {
        $targetFile = $script:fileCache | Where-Object { $_.name -eq $Input } | Select-Object -First 1
        # 方法3：如果精确匹配失败，尝试忽略大小写
        if ($null -eq $targetFile) {
            $targetFile = $script:fileCache | Where-Object { $_.name -like $Input } | Select-Object -First 1
        }
    }
    
    if ($null -eq $targetFile) {
        Write-ErrorMsg "File not found: $Input" "Use 'list' to see available files"
        return
    }
    
    $sizeStr = Format-FileSize -Bytes $targetFile.size
    $downloadUrl = Get-DownloadUrl -FileName $targetFile.name
    
    Write-Host "`n[*] File Information:" -ForegroundColor Cyan
    Write-Host ("=" * 65) -ForegroundColor DarkGray
    Write-Host "  Name     : $($targetFile.name)" -ForegroundColor White
    Write-Host "  Size     : $sizeStr" -ForegroundColor White
    Write-Host "  SHA      : $($targetFile.sha)" -ForegroundColor Gray
    Write-Host "  Date     : $($targetFile.created_at)" -ForegroundColor Gray
    Write-Host "  Download : $downloadUrl" -ForegroundColor Gray
    Write-Host ("=" * 65) -ForegroundColor DarkGray
}
function Show-FileInfo {
    param([string]$Input)
    
    if ($null -eq $script:fileCache) {
        Write-ErrorMsg "No file list available" "Run 'list' to fetch files first"
        return
    }
    
    $targetFile = $null
    if ($Input -match '^\d+$') {
        $idx = [int]$Input
        if ($idx -ge 1 -and $idx -le $script:fileCache.Count) {
            $targetFile = $script:fileCache[$idx-1]
        }
    }
    else {
        $targetFile = $script:fileCache | Where-Object { $_.name -eq $Input } | Select-Object -First 1
        if ($null -eq $targetFile) {
            $matches = $script:fileCache | Where-Object { $_.name -like "*$Input*" }
            if ($matches.Count -eq 1) {
                $targetFile = $matches[0]
            }
        }
    }
    
    if ($null -eq $targetFile) {
        Write-ErrorMsg "File not found: $Input" "Use 'list' to see available files"
        return
    }
    
    $sizeStr = Format-FileSize -Bytes $targetFile.size
    $downloadUrl = Get-DownloadUrl -FileName $targetFile.name
    
    Write-Host "`n[*] File Information:" -ForegroundColor Cyan
    Write-Host ("=" * 65) -ForegroundColor DarkGray
    Write-Host "  Name     : $($targetFile.name)" -ForegroundColor White
    Write-Host "  Size     : $sizeStr" -ForegroundColor White
    Write-Host "  SHA      : $($targetFile.sha)" -ForegroundColor Gray
    Write-Host "  Date     : $($targetFile.created_at)" -ForegroundColor Gray
    Write-Host "  Download : $downloadUrl" -ForegroundColor Gray
    Write-Host ("=" * 65) -ForegroundColor DarkGray
}

function Show-MuldlDialog {
    Write-InfoMsg "Opening file selection dialog..."
    
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Multiselect = $true
        $openFileDialog.Title = "Select files to download"
        $openFileDialog.Filter = "All files (*.*)|*.*"
        
        if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $selectedFiles = $openFileDialog.FileNames
            Write-InfoMsg "Selected $($selectedFiles.Count) file(s)"
            
            $confirm = Read-Host "[?] Download these files? (y/n)"
            if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                foreach ($file in $selectedFiles) {
                    $fileName = Split-Path $file -Leaf
                    $savePath = Join-Path $script:config.DOWNLOAD_DIR $fileName
                    try {
                        Copy-Item -Path $file -Destination $savePath -Force
                        Write-SuccessMsg "Copied: $fileName"
                        Write-Log "Copied from local: $fileName" "INFO"
                    }
                    catch {
                        Write-ErrorMsg "Failed to copy: $fileName" "Check if the file exists and is not in use"
                    }
                }
            }
            else {
                Write-InfoMsg "Batch download cancelled"
            }
        }
        else {
            Write-InfoMsg "No files selected"
        }
    }
    catch {
        Write-ErrorMsg "Failed to open file dialog" "Make sure System.Windows.Forms is available"
    }
}

function Execute-Script {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-ErrorMsg "File not found: $FilePath" "Check the file path and try again"
        return
    }
    
    try {
        $lines = Get-Content $FilePath -ErrorAction Stop
        $lineCount = 0
        $successCount = 0
        
        Write-InfoMsg "Executing script: $FilePath"
        Write-Host ("=" * 50) -ForegroundColor DarkGray
        
        foreach ($line in $lines) {
            $line = $line.Trim()
            # Skip empty lines and comments
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
                continue
            }
            $lineCount++
            Write-CommandMsg "[$lineCount] => $line"
            
            # Parse and execute command
            if ($line -match '^\d+-\d+$') {
                Download-Batch -Range $line
            }
            elseif ($line -match '^\d+$') {
                Download-File -Index ([int]$line)
            }
            else {
                Download-File -FileName $line
            }
            $successCount++
        }
        
        Write-Host ("=" * 50) -ForegroundColor DarkGray
        Write-SuccessMsg "Script executed: $successCount commands processed"
    }
    catch {
        Write-ErrorMsg "Failed to execute script: $_" "Check file format and content"
    }
}
#endregion

#region Tab Completion
function Get-TabCompletion {
    param([string]$CurrentText)
    
    $knownCommands = @("list", "ls", "search", "src", "download", "dl", "bg", "jobs", "fg", "stop", "kill", "info", "set", "show", "save", "use", "add", "repos", "muldl", "script", "clear", "cls", "help", "?", "exit", "quit")
    $knownConfigKeys = @("DOWNLOAD_DIR", "PROXY_INDEX", "THREADS", "SPEED_LIMIT", "RESUME", "AUTO_CONFIRM", "LOG_LEVEL")
    
    $lastWord = ($CurrentText -split '\s+')[-1]
    $baseText = ($CurrentText -split '\s+')[0..((($CurrentText -split '\s+').Count)-2)] -join ' '
    
    $matches = @()
    
    if ($CurrentText -match '^\S+$') {
        $matches = $knownCommands | Where-Object { $_ -like "$lastWord*" }
        if ($matches.Count -eq 1) {
            return $baseText + $matches[0]
        }
    }
    elseif ($CurrentText -match '^(set|show)\s+(\S*)$') {
        $matches = $knownConfigKeys | Where-Object { $_ -like "$($matches[2])*" }
        if ($matches.Count -eq 1) {
            return "$($matches[1]) $($matches[0])"
        }
    }
    elseif ($CurrentText -match '^(dl|download|info|bg)\s+(\S*)$') {
        if ($script:fileCache) {
            $matches = @()
            if ($matches[2] -match '^\d*$') {
                for ($i = 1; $i -le [math]::Min(10, $script:fileCache.Count); $i++) {
                    if ($i.ToString().StartsWith($matches[2])) {
                        $matches += $i.ToString()
                    }
                }
            }
            foreach ($file in $script:fileCache) {
                if ($file.name -like "$($matches[2])*") {
                    $matches += $file.name
                    if ($matches.Count -ge 5) { break }
                }
            }
            if ($matches.Count -eq 1) {
                return "$($matches[1]) $($matches[0])"
            }
        }
    }
    
    if ($matches.Count -gt 1) {
        Write-Host "`n" + ($matches -join "  ") -ForegroundColor Gray
    }
    return $null
}
#endregion

#region Help and Banner
function Show-Banner {
    Clear-Host
    Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║     ██████╗ ██╗   ██╗██╗███████╗██╗   ██╗ ██████╗            ║
║    ██╔═══██╗██║   ██║██║██╔════╝██║   ██║██╔═══██╗           ║
║    ██║   ██║██║   ██║██║███████╗██║   ██║██║   ██║           ║
║    ██║▄▄ ██║██║   ██║██║╚════██║██║   ██║██║   ██║           ║
║    ╚██████╔╝╚██████╔╝██║███████║╚██████╔╝╚██████╔╝           ║
║     ╚══▀▀═╝  ╚═════╝ ╚═╝╚══════╝ ╚═════╝  ╚═════╝            ║
║                                                              ║
║              Qiusuo Downloader Interactive v2.0              ║
║              Type 'help' or '?' for commands                ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    Write-InfoMsg "Run 'list' to load files from repository"
}

function Show-Help {
    Write-Host @"
`n======================================== HELP ========================================
 Command          Alias       Description
----------------------------------------------------------------------------------------
 list             ls          Fetch and display file list (paginated)
 search <pattern> src         Search by MagNo. (000001) or filename keyword
 download <idx>   dl          Download file: dl 3, dl 3 8 (8 threads), dl 1-5 (batch)
 download <name>  dl          Download by filename: dl myfile.apk
 bg dl <idx>      -           Background download: bg dl 3
 jobs             -           List all background jobs
 fg <id>          -           Bring background job to foreground
 stop <id>        -           Stop a background job
 kill <id>        -           Force kill a background job
 info <idx/name>  -           Show detailed file information
 set <key> <val>  -           Set configuration
 show options     show        Display current configuration
 save <name>      -           Save current settings as a profile
 use profile <name> -         Switch to a saved profile
 use repo <name>  -           Switch to a repository in sources
 add repo <url>   -           Add and switch to a new repository
 repos            -           List all repositories under your GitHub account
 repos <keyword>  -           Search repositories by keyword
 muldl            -           Open file selection dialog for local files
 script <file>    -           Execute batch download commands from a text file
 clear            cls         Clear screen
 help             ?           Show this help
 exit             quit        Exit the program
----------------------------------------------------------------------------------------
 Configuration Keys: DOWNLOAD_DIR, PROXY_INDEX, THREADS, SPEED_LIMIT, RESUME, AUTO_CONFIRM, LOG_LEVEL
"@ -ForegroundColor Cyan
}
#endregion

#region Main Interactive Loop
function Start-InteractiveShell {
    Load-Config
    Show-Banner
    Write-InfoMsg "Type 'help' for commands. Run 'list' to load files."
    
    [System.Console]::TreatControlCAsInput = $false
    
    while ($true) {
        $prompt = "=> "
        
        $currentInput = ""
        $cursorPos = 0
        $script:historyIndex = $script:commandHistory.Count
        
        while ($true) {
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            if ($key.VirtualKeyCode -eq 13) {
                Write-Host ""
                break
            }
            elseif ($key.VirtualKeyCode -eq 8) {
                if ($cursorPos -gt 0) {
                    $currentInput = $currentInput.Remove($cursorPos-1, 1)
                    $cursorPos--
                    Write-Host "`b `b" -NoNewline
                }
            }
            elseif ($key.VirtualKeyCode -eq 9) {
                $completion = Get-TabCompletion -CurrentText $currentInput
                if ($completion) {
                    $currentInput = $completion
                    $cursorPos = $currentInput.Length
                    Write-Host "`r$prompt$currentInput" -NoNewline
                }
            }
            elseif ($key.VirtualKeyCode -eq 38) {
                if ($script:historyIndex -gt 0) {
                    $script:historyIndex--
                    $currentInput = $script:commandHistory[$script:historyIndex]
                    $cursorPos = $currentInput.Length
                    Write-Host "`r$prompt$currentInput" -NoNewline
                }
            }
            elseif ($key.VirtualKeyCode -eq 40) {
                if ($script:historyIndex -lt $script:commandHistory.Count - 1) {
                    $script:historyIndex++
                    $currentInput = $script:commandHistory[$script:historyIndex]
                    $cursorPos = $currentInput.Length
                    Write-Host "`r$prompt$currentInput" -NoNewline
                }
                elseif ($script:historyIndex -eq $script:commandHistory.Count - 1) {
                    $script:historyIndex = $script:commandHistory.Count
                    $currentInput = ""
                    $cursorPos = 0
                    Write-Host "`r$prompt" -NoNewline
                    Write-Host " " * $currentInput.Length -NoNewline
                    Write-Host "`r$prompt" -NoNewline
                }
            }
            elseif ($key.Character) {
                $currentInput = $currentInput.Insert($cursorPos, $key.Character)
                $cursorPos++
                Write-Host $key.Character -NoNewline
            }
        }
        
        # 用户输入用紫色显示
        Write-CommandMsg "=> $currentInput"
        
        $inputLine = $currentInput.Trim()
        if ([string]::IsNullOrWhiteSpace($inputLine)) { continue }
        
        $script:commandHistory += $inputLine
        if ($script:commandHistory.Count -gt 100) { $script:commandHistory = $script:commandHistory[-100..-1] }
        $script:historyIndex = $script:commandHistory.Count
        
        $parts = $inputLine -split '\s+', 2
        $cmd = $parts[0].ToLower()
        $args = if ($parts.Count -gt 1) { $parts[1] } else { "" }
        
        Write-Log "Command: $inputLine" "INFO"
        
       switch ($cmd) {
    "list" { Update-FileList; if ($script:fileCache) { Show-FileList } }
    "ls" { if ($script:fileCache) { Show-FileList } else { Write-ErrorMsg "No file list. Run 'list' first." "Run 'list' to fetch files" } }
    "repos" { Search-Repos -Keyword $args }
    "search" { Search-Files -Pattern $args }
    "src" { Search-Files -Pattern $args }
    "download" {
        $dlParts = $args -split '\s+'
        $threads = -1
        $target = $dlParts[0]
        if ($dlParts.Count -gt 1) { $threads = [int]$dlParts[1] }
        if ($target -match '^\d+-\d+$') { Download-Batch -Range $target -CustomThreads $threads }
        elseif ($target -match '^\d+$') { Download-File -Index ([int]$target) -CustomThreads $threads }
        else { Download-File -FileName $target -CustomThreads $threads }
    }
    "dl" {
        $dlParts = $args -split '\s+'
        $threads = -1
        $target = $dlParts[0]
        if ($dlParts.Count -gt 1) { $threads = [int]$dlParts[1] }
        if ($target -match '^\d+-\d+$') { Download-Batch -Range $target -CustomThreads $threads }
        elseif ($target -match '^\d+$') { Download-File -Index ([int]$target) -CustomThreads $threads }
        else { Download-File -FileName $target -CustomThreads $threads }
    }
    "bg" {
        $bgParts = $args -split '\s+', 2
        if ($bgParts[0] -eq "dl") {
            $dlParts = $bgParts[1] -split '\s+'
            $target = $dlParts[0]
            $threads = if ($dlParts.Count -gt 1) { [int]$dlParts[1] } else { -1 }
            if ($target -match '^\d+$') { Start-BackgroundDownload -Index ([int]$target) -CustomThreads $threads }
            else { Start-BackgroundDownload -FileName $target -CustomThreads $threads }
        }
        else { Write-ErrorMsg "Usage: bg dl <index or filename>" "Example: bg dl 3" }
    }
    "jobs" { Show-Jobs }
    "fg" {
        if ($args -match '^\d+$') { Foreground-Job -JobId ([int]$args) }
        else { Write-ErrorMsg "Usage: fg <job_id>" "Example: fg 1" }
    }
    "stop" {
        if ($args -match '^\d+$') { Stop-JobById -JobId ([int]$args) }
        else { Write-ErrorMsg "Usage: stop <job_id>" "Example: stop 1" }
    }
    "kill" {
        if ($args -match '^\d+$') { Kill-JobById -JobId ([int]$args) }
        else { Write-ErrorMsg "Usage: kill <job_id>" "Example: kill 1" }
    }
    "info" { Show-FileInfo -Input $args }
    "set" {
        $setParts = $args -split '\s+', 2
        if ($setParts.Count -lt 2) {
            Write-ErrorMsg "Usage: set <key> <value>" "Example: set THREADS 8"
        }
        else { Set-ConfigItem -Key $setParts[0] -Value $setParts[1] }
    }
    "show" {
        if ($args -eq "options" -or $args -eq "") { Show-Config }
        else { Write-ErrorMsg "Usage: show options" "Type 'show options' to display configuration" }
    }
    "save" {
        if ([string]::IsNullOrWhiteSpace($args)) {
            Write-ErrorMsg "Usage: save <profile_name>" "Example: save work"
        }
        else { Save-Profile -ProfileName $args }
    }
    "use" {
        $useParts = $args -split '\s+', 2
        if ($useParts.Count -lt 2) {
            Write-ErrorMsg "Usage: use <type> <name>" "Example: use profile work | use repo default"
        }
        else {
            switch ($useParts[0].ToLower()) {
                "profile" { Load-Profile -ProfileName $useParts[1] }
                "repo" { Switch-Repo -RepoName $useParts[1] }
                default { Write-ErrorMsg "Unknown type: $($useParts[0])" "Available: profile, repo" }
            }
        }
    }
    "add" {
        $addParts = $args -split '\s+', 2
        if ($addParts.Count -lt 2 -or $addParts[0] -ne "repo") {
            Write-ErrorMsg "Usage: add repo <url>" "Example: add repo https://github.com/username/reponame"
        }
        else { Add-Repo -RepoUrl $addParts[1] }
    }
    "muldl" { Show-MuldlDialog }
    "script" {
        if ([string]::IsNullOrWhiteSpace($args)) {
            Write-ErrorMsg "Usage: script <filename>" "Example: script download.txt"
        }
        else {
            Execute-Script -FilePath $args
        }
    }
    "clear" { Show-Banner; if ($script:fileCache) { Write-InfoMsg "File list loaded. Use 'list' to refresh." } }
    "cls" { Show-Banner; if ($script:fileCache) { Write-InfoMsg "File list loaded. Use 'list' to refresh." } }
    "help" { Show-Help }
    "?" { Show-Help }
    "exit" { Write-SuccessMsg "Exiting... Goodbye!"; Write-Log "Session ended" "INFO"; break }
    "quit" { Write-SuccessMsg "Exiting... Goodbye!"; Write-Log "Session ended" "INFO"; break }
    default { Write-ErrorMsg "Unknown command: $cmd" "Type 'help' or '?' for available commands" }
}
        
        Check-Jobs
    }
}
#endregion

# Start
Start-InteractiveShell