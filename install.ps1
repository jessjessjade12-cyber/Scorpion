# Scorpion - Install dependencies and run the server
# Run from the project root: powershell -ExecutionPolicy Bypass -File install.ps1

$LuaPath = "C:\Program Files (x86)\Lua\5.1\lua.exe"

Write-Host ""
Write-Host "Scorpion - EO Arena Server" -ForegroundColor Cyan
Write-Host "--------------------------"
Write-Host ""

# Check if Lua is already installed
if (Test-Path $LuaPath) {
    Write-Host "Lua 5.1 already installed." -ForegroundColor Green
} else {
    Write-Host "Lua 5.1 not found. Installing via Chocolatey..." -ForegroundColor Yellow

    # Install Chocolatey if not present
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }

    choco install lua -y

    if (-not (Test-Path $LuaPath)) {
        Write-Host "Installation failed. Please install LuaForWindows manually:" -ForegroundColor Red
        Write-Host "https://github.com/rjpcomputing/luaforwindows/releases" -ForegroundColor White
        exit 1
    }

    Write-Host "Lua 5.1 installed." -ForegroundColor Green
}

Write-Host ""
Write-Host "To start the server, run:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  & `"$LuaPath`" lua/main.lua" -ForegroundColor White
Write-Host ""
Write-Host "Starting server..." -ForegroundColor Cyan
Write-Host ""

& $LuaPath lua/main.lua
