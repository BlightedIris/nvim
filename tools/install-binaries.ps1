<#
.SYNOPSIS
  Installs the lsp.lua servers pinned in tools/binaries.toml (lua_ls, clangd,
  verible, powershell_es) -- the ones with no npm/pip/go/cargo package.

.PARAMETER Dest
  Where extracted tool folders live, and where standalone .exe files are
  copied so a single PATH entry covers all of them. Defaults to ~/bin.

.PARAMETER Only
  Restrict to specific tool names (lua_ls, clangd, verible, powershell_es).
#>
param(
    [string]$Dest = "$env:USERPROFILE\bin",
    [string[]]$Only
)

$ErrorActionPreference = 'Stop'

function Read-BinariesToml([string]$Path) {
    $tools = [ordered]@{}
    $current = $null
    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^\[(.+)\]$') {
            $current = $Matches[1]
            $tools[$current] = @{}
            continue
        }
        if ($current -and $trimmed -match '^(\w+)\s*=\s*"(.*)"$') {
            $tools[$current][$Matches[1]] = $Matches[2]
        }
    }
    return $tools
}

$tools = Read-BinariesToml (Join-Path $PSScriptRoot 'binaries.toml')
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

foreach ($name in $tools.Keys) {
    if ($Only -and ($Only -notcontains $name)) { continue }
    $info = $tools[$name]
    $url = $info['url']
    $version = $info['version']
    Write-Output "==> $name $version"

    $extractDir = Join-Path $Dest $name
    if (Test-Path (Join-Path $extractDir '.version')) {
        $have = Get-Content (Join-Path $extractDir '.version') -Raw
        if ($have.Trim() -eq $version) {
            Write-Output "    already installed"
            continue
        }
    }

    $zip = Join-Path $env:TEMP "$name-$version.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip

    if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
    Expand-Archive -Path $zip -DestinationPath $extractDir -Force
    Remove-Item $zip

    # some archives nest everything one level deep under a single subfolder
    $entries = Get-ChildItem $extractDir
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
        Get-ChildItem $entries[0].FullName | Move-Item -Destination $extractDir
        Remove-Item $entries[0].FullName -Recurse -Force
    }

    Set-Content -Path (Join-Path $extractDir '.version') -Value $version -NoNewline

    if ($name -eq 'powershell_es') {
        Write-Output "    bundle_path (set in lsp.lua): $extractDir"
        continue
    }

    $exeName = if ($name -eq 'verible') { 'verible-verilog-ls.exe' } else { "$name.exe" }
    $exe = Get-ChildItem -Path $extractDir -Recurse -Filter $exeName | Select-Object -First 1
    if (-not $exe) { throw "$name`: could not find $exeName in extracted archive" }
    Copy-Item $exe.FullName -Destination (Join-Path $Dest $exeName) -Force
    Write-Output "    -> $Dest\$exeName"
}

if (($env:Path -split ';') -notcontains $Dest) {
    Write-Warning "$Dest is not on PATH -- nvim will not find these servers"
}
