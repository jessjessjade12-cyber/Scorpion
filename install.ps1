# Scorpion bootstrap script:
# - installs required dependencies via Chocolatey when missing
# - ensures local MongoDB is running
# - starts the Lua server

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LuaDefaultPath = "C:\Program Files (x86)\Lua\5.1\lua.exe"
$MongoDataPath = Join-Path $ProjectRoot "Data\mongo"

function Write-Section([string]$Text) {
    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
}

function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ExePath([string]$CommandName) {
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command -and $command.Path) {
        return $command.Path
    }
    return $null
}

function Ensure-Chocolatey {
    $chocoPath = Get-ExePath "choco"
    if ($chocoPath) {
        return $chocoPath
    }

    Write-Host "Chocolatey not found. Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))

    $chocoPath = Get-ExePath "choco"
    if (-not $chocoPath) {
        $fallback = "C:\ProgramData\chocolatey\bin\choco.exe"
        if (Test-Path $fallback) {
            $chocoPath = $fallback
        }
    }

    if (-not $chocoPath) {
        throw "Chocolatey installation failed."
    }

    return $chocoPath
}

function Install-ChocoPackage([string]$ChocoPath, [string]$PackageName) {
    Write-Host "Installing $PackageName via Chocolatey..." -ForegroundColor Yellow
    & $ChocoPath install $PackageName -y --no-progress
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install package '$PackageName'."
    }
}

function Find-MongodPath {
    $fromPath = Get-ExePath "mongod"
    if ($fromPath) {
        return $fromPath
    }

    $serverRoot = "C:\Program Files\MongoDB\Server"
    if (-not (Test-Path $serverRoot)) {
        return $null
    }

    $versions = Get-ChildItem -Path $serverRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending

    foreach ($version in $versions) {
        $candidate = Join-Path $version.FullName "bin\mongod.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Find-MongoshPath {
    $fromPath = Get-ExePath "mongosh"
    if ($fromPath) {
        return $fromPath
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\mongosh\mongosh.exe"),
        (Join-Path $env:ProgramFiles "MongoDB\mongosh\bin\mongosh.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $serverRoot = "C:\Program Files\MongoDB\Server"
    if (Test-Path $serverRoot) {
        $versions = Get-ChildItem -Path $serverRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending

        foreach ($version in $versions) {
            $candidate = Join-Path $version.FullName "bin\mongosh.exe"
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function Test-MongoRunning([string]$MongoshPath) {
    if (-not $MongoshPath) {
        return $false
    }

    & $MongoshPath "mongodb://127.0.0.1:27017" --quiet --eval "db.runCommand({ ping: 1 }).ok" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Ensure-MongoRunning([string]$MongodPath, [string]$MongoshPath) {
    if (Test-MongoRunning $MongoshPath) {
        Write-Host "MongoDB already running on 127.0.0.1:27017." -ForegroundColor Green
        return
    }

    if (-not (Test-Path $MongoDataPath)) {
        New-Item -ItemType Directory -Path $MongoDataPath -Force | Out-Null
    }

    $args = @(
        "--dbpath", "`"$MongoDataPath`"",
        "--bind_ip", "127.0.0.1",
        "--port", "27017"
    ) -join " "

    Write-Host "Starting MongoDB with dbpath '$MongoDataPath'..." -ForegroundColor Cyan
    Start-Process -FilePath $MongodPath -ArgumentList $args -WindowStyle Minimized | Out-Null

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-MongoRunning $MongoshPath) {
            Write-Host "MongoDB started." -ForegroundColor Green
            return
        }
    }

    throw "MongoDB did not become ready on 127.0.0.1:27017."
}

Write-Section "Scorpion - EO Arena Server"

$luaPath = $null
if (Test-Path $LuaDefaultPath) {
    $luaPath = $LuaDefaultPath
} else {
    $luaPath = Get-ExePath "lua"
}

$mongodPath = Find-MongodPath
$mongoshPath = Find-MongoshPath

$missing = @()
if (-not $luaPath) { $missing += "lua" }
if (-not $mongodPath) { $missing += "mongodb" }
if (-not $mongoshPath) { $missing += "mongosh" }

if ($missing.Count -gt 0) {
    if (-not (Is-Admin)) {
        throw "Missing dependencies ($($missing -join ', ')). Re-run this script in an elevated PowerShell window."
    }

    $chocoPath = Ensure-Chocolatey

    if (-not $luaPath) {
        Install-ChocoPackage $chocoPath "lua"
    }
    if (-not $mongodPath) {
        Install-ChocoPackage $chocoPath "mongodb"
    }
    if (-not $mongoshPath) {
        Install-ChocoPackage $chocoPath "mongosh"
    }

    $luaPath = if (Test-Path $LuaDefaultPath) { $LuaDefaultPath } else { Get-ExePath "lua" }
    $mongodPath = Find-MongodPath
    $mongoshPath = Find-MongoshPath
}

if (-not $luaPath) {
    throw "Lua 5.1 not found after install. Install LuaForWindows manually: https://github.com/rjpcomputing/luaforwindows/releases"
}
if (-not $mongodPath) {
    throw "mongod not found after install. Check MongoDB server installation."
}
if (-not $mongoshPath) {
    throw "mongosh not found after install. Check mongosh installation."
}

# Ensure this shell can resolve all tools immediately.
$toolDirs = @(
    (Split-Path -Parent $luaPath),
    (Split-Path -Parent $mongodPath),
    (Split-Path -Parent $mongoshPath)
) | Select-Object -Unique

foreach ($dir in $toolDirs) {
    if ($dir -and (Test-Path $dir) -and -not ($env:PATH -split ";" | Where-Object { $_ -eq $dir })) {
        $env:PATH += ";$dir"
    }
}

Write-Host "Lua: $luaPath" -ForegroundColor Green
Write-Host "mongod: $mongodPath" -ForegroundColor Green
Write-Host "mongosh: $mongoshPath" -ForegroundColor Green

Ensure-MongoRunning $mongodPath $mongoshPath

Write-Section "Starting Scorpion server"
Write-Host "& `"$luaPath`" lua/main.lua" -ForegroundColor White
Write-Host ""

& $luaPath lua/main.lua
