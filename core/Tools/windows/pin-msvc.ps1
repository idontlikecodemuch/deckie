# Pin the Microsoft C++ toolset that Swift's clang compiles C++ against on a GitHub Windows runner.
#
# Why: Swift 6.4.1 for Windows ships Clang 21. With no toolset named, clang takes the newest Microsoft C++ toolset
# Visual Studio has, and from MSVC 14.52 on that toolset's standard library refuses any Clang older than 22
# ("error STL1000: Unexpected compiler version, expected Clang 22 or newer"). The runner images moved from 14.51 to
# 14.52 in November 2026, so desk-shell's C++ (deskshell.cc) built on some runners and not on others. This names a
# toolset for every step after it: clang reads the toolset folder from VCToolsInstallDir before looking for the
# newest one itself (LLVM's MSVCPaths.cpp), and that is checked here with the toolchain's own clang.
#
# Which toolset, the same way on every image: 14.51 when the runner has it; else the newest it has below 14.52 (the
# images carry Visual Studio 2022's 14.44 as well); else 14.51 added through the Visual Studio installer, with the
# component's id read from the installer's own catalogue.
#
# Usage, in a workflow step after the Swift toolchain is set up:  ./core/Tools/windows/pin-msvc.ps1
param([string]$Want = "14.51", [string]$Below = "14.52")
$ErrorActionPreference = "Stop"

$installer = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
$vs = & "$installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "no Visual Studio with the C++ tools here" }
$root = Join-Path $vs "VC\Tools\MSVC"

function Toolsets { Get-ChildItem $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName "include\yvals_core.h") } |
    ForEach-Object Name | Sort-Object { [version]$_ } }
function Wanted { Toolsets | Where-Object { $_ -like "$Want.*" } | Select-Object -Last 1 }
function Older { Toolsets | Where-Object { [version]$_ -lt [version]"$Below.0" } | Select-Object -Last 1 }

"Visual Studio: $vs"
"Microsoft C++ toolsets here: " + ((Toolsets) -join ", ")

$have = Wanted
if (-not $have) { $have = Older; if ($have) { "No $Want toolset here; the newest below $Below is $have" } }
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
    if (-not $id) { throw "no toolset below $Below here and no installer component for $Want found" }
    "Adding $id"
    $p = Start-Process -FilePath "$installer\vs_installer.exe" -Wait -PassThru -ArgumentList @(
        "modify", "--installPath", "`"$vs`"", "--add", $id, "--quiet", "--norestart", "--nocache")
    "Installer exit code: $($p.ExitCode)"
    $have = Wanted
    if (-not $have) { throw "the $Want toolset is still not here after the installer ran" }
}

# Clang takes the toolset named: the include folders it would search, with the variable set as the steps after
# this one will have it.
function Searched([string]$dir) {
    $saved = $env:VCToolsInstallDir
    $env:VCToolsInstallDir = "$dir\"
    try { (& clang -target x86_64-unknown-windows-msvc -x c++ -fsyntax-only -v NUL 2>&1 | Out-String) }
    finally { $env:VCToolsInstallDir = $saved }
}
$dir = Join-Path $root $have
$said = Searched $dir
if ($said -notlike "*$have\include*") { throw "clang did not take the $have toolset when named:`n$said" }
# And it is the naming that does it: named, an older toolset than the newest is taken too.
$other = Toolsets | Where-Object { $_ -ne $have } | Select-Object -First 1
if ($other -and (Searched (Join-Path $root $other)) -notlike "*$other\include*") { throw "clang does not take a toolset when named" }

"Pinned: MSVC $have ($dir)"
"VCToolsInstallDir=$dir\" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
"VCToolsVersion=$have" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
