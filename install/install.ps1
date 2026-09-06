<#
.SYNOPSIS
    Bootstrap for Windows.

.DESCRIPTION
    The Windows twin of install.sh, and deliberately just as small: make sure
    git and a new enough Neovim exist, make sure the config is checked out at
    $env:LOCALAPPDATA\nvim, then hand over to install\install.lua. All the
    per-tool knowledge lives in the Lua so the two bootstraps cannot drift.

.PARAMETER Rest
    Passed straight through to install.lua: --check, --tree, --dry-run,
    --all, --with=..., -y and so on. (Named Rest rather than Args, which
    collides with PowerShell's automatic $Args variable.)

.EXAMPLE
    .\install\install.ps1

.EXAMPLE
    .\install\install.ps1 --check

.EXAMPLE
    irm https://raw.githubusercontent.com/BlightedIris/nvim/main/install/install.ps1 | iex
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$RepoUrl = if ($env:NVIM_CONFIG_REPO) { $env:NVIM_CONFIG_REPO } else { 'https://github.com/BlightedIris/nvim.git' }
$NvimMin = [version]'0.12.0'

# --- output ------------------------------------------------------------------

function Write-Step { param([string]$Text) Write-Host "> $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  + $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  ! $Text" -ForegroundColor Yellow }
function Write-Dim  { param([string]$Text) Write-Host "  $Text" -ForegroundColor DarkGray }
function Stop-With  { param([string]$Text) Write-Host "  x $Text" -ForegroundColor Red; exit 1 }

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# winget puts new binaries on the machine PATH, but this process started with
# the old one. Re-read it so `git` and `nvim` are usable without a new shell.
function Update-PathFromEnvironment {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Install-WithWinget {
    param([string]$Id)
    if (-not (Test-Command winget)) {
        Stop-With "winget is not available. Install App Installer from the Microsoft Store, or install $Id manually."
    }
    Write-Step "winget install $Id"
    winget install --id $Id -e --source winget `
        --accept-source-agreements --accept-package-agreements --disable-interactivity
    Update-PathFromEnvironment
}

# --- 1. git ------------------------------------------------------------------

Write-Step 'Checking for git'
if (Test-Command git) {
    Write-Ok "git $((git --version) -replace 'git version ', '')"
} else {
    Install-WithWinget 'Git.Git'
    if (-not (Test-Command git)) { Stop-With 'git is still not on PATH; open a new terminal and re-run' }
    Write-Ok 'git installed'
}

# --- 2. neovim ---------------------------------------------------------------

Write-Step "Checking for Neovim >= $NvimMin"
$nvimVersion = $null
if (Test-Command nvim) {
    $line = (nvim --version | Select-Object -First 1)
    if ($line -match 'v(\d+\.\d+\.\d+)') { $nvimVersion = [version]$Matches[1] }
}

if ($nvimVersion -and $nvimVersion -ge $NvimMin) {
    Write-Ok "Neovim $nvimVersion"
} else {
    if ($nvimVersion) {
        Write-Warn "Neovim $nvimVersion is too old (nvim-treesitter needs $NvimMin+)"
    }
    Install-WithWinget 'Neovim.Neovim'
    if (-not (Test-Command nvim)) {
        Stop-With 'Neovim is still not on PATH; open a new terminal and re-run'
    }
    $line = (nvim --version | Select-Object -First 1)
    $nvimVersion = $null
    if ($line -match 'v(\d+\.\d+\.\d+)') { $nvimVersion = [version]$Matches[1] }
    if (-not $nvimVersion) {
        Stop-With "Could not read the Neovim version from: $line"
    }
    if ($nvimVersion -lt $NvimMin) {
        Stop-With "Neovim $nvimVersion is still older than $NvimMin; install a current build from https://github.com/neovim/neovim/releases"
    }
    Write-Ok "Neovim $nvimVersion"
}

# --- 3. the config -----------------------------------------------------------

# Run from a checkout when there is one (the normal case), otherwise clone into
# the path Neovim actually reads on Windows.
$configRoot = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot '..\init.lua'))) {
    $configRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if (-not $configRoot) {
    $configRoot = Join-Path $env:LOCALAPPDATA 'nvim'
    if (Test-Path (Join-Path $configRoot 'init.lua')) {
        Write-Step "Using existing config at $configRoot"
    } else {
        if (Test-Path $configRoot) {
            Stop-With "$configRoot exists but has no init.lua; move it aside first"
        }
        Write-Step "Cloning $RepoUrl into $configRoot"
        git clone --recurse-submodules $RepoUrl $configRoot
        if ($LASTEXITCODE -ne 0) { Stop-With 'Clone failed' }
        Write-Ok 'Cloned'
    }
}

# --- 4. hand over ------------------------------------------------------------

Write-Step 'Running the installer'
Write-Host ''
$installer = Join-Path $configRoot 'install\install.lua'
& nvim -l $installer @Rest
exit $LASTEXITCODE
