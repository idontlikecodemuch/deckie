# Pin the Microsoft C++ toolset that Swift's clang compiles C++ against on a GitHub Windows runner.
#
# Why: Swift 6.4.1 for Windows ships Clang 21. With no toolset named, clang takes the newest Microsoft C++ toolset
# Visual Studio has, and from MSVC 14.52 on that toolset's standard library refuses any Clang older than 22
# ("error STL1000: Unexpected compiler version, expected Clang 22 or newer"). The runner images moved from 14.51 to
# 14.52 in November 2026, so desk-shell's C++ (deskshell.cc) built on some runners and not on others. This names
# 14.51 for every step after it: clang reads the toolset folder from VCToolsInstallDir before looking for the newest
# one itself (LLVM's MSVCPaths.cpp). If the runner has no 14.51 toolset, it is added through the Visual Studio
# installer first, with the component's id read from the installer's own catalogue.
#
# Usage, in a workflow step after the Swift toolchain is set up:  ./core/Tools/windows/pin-msvc.ps1 [-Want 14.51]
param([string]$Want = "14.51")
$ErrorActionPreference = "Stop"

$installer = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
$vs = & "$installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "no Visual Studio with the C++ tools here" }
$root = Join-Path $vs "VC\Tools\MSVC"

function Toolsets { Get-ChildItem $root -Directory | ForEach-Object Name | Sort-Object { [version]$_ } }
function Wanted { Toolsets | Where-Object { $_ -like "$Want.*" } | Select-Object -Last 1 }

"Visual Studio: $vs"
"Microsoft C++ toolsets here: " + ((Toolsets) -join ", ")

$have = Wanted
if (-not $have) {
    # The component ids carry the Visual Studio version too (for example ...VC.14.51.<vs version>.x86.x64), so the
    # id is looked up rather than guessed: every catalogue the installer keeps on the runner is searched.
    $pattern = "Microsoft\.VisualStudio\.Component\.VC\.$([regex]::Escape($Want))(\.\d+)*\.x86\.x64(?=`")"
    $places = @("$env:ProgramData\Microsoft\VisualStudio\Packages", "$env:LOCALAPPDATA\Microsoft\VisualStudio\Packages")
    $ids = foreach ($p in $places) {
        if (Test-Path $p) {
            Get-ChildItem $p -Recurse -Filter "*.json" -ErrorAction SilentlyContinue |
                Select-String -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Matches.Value }
        }
    }
    $id = $ids | Sort-Object -Unique | Select-Object -Last 1
    if (-not $id) { throw "no $Want toolset here and no installer component for it found" }
    "Adding $id"
    $p = Start-Process -FilePath "$installer\vs_installer.exe" -Wait -PassThru -ArgumentList @(
        "modify", "--installPath", "`"$vs`"", "--add", $id, "--quiet", "--norestart", "--nocache")
    "Installer exit code: $($p.ExitCode)"
    $have = Wanted
    if (-not $have) { throw "the $Want toolset is still not here after the installer ran" }
}

$dir = Join-Path $root $have
"Pinned: MSVC $have ($dir)"
"VCToolsInstallDir=$dir\" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
"VCToolsVersion=$have" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
