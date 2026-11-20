# Pin the Microsoft C++ toolset that Swift's clang compiles C++ against on a GitHub Windows runner.
#
# Why: Swift 6.4.1 for Windows ships Clang 21. From MSVC 14.52 on, the toolset's standard library refuses any Clang
# older than 22 ("error STL1000: Unexpected compiler version, expected Clang 22 or newer"). The runner images moved
# from 14.51 to 14.52 in November 2026, so desk-shell's C++ (deskshell.cc) built on some runners and not on others.
#
# What was learned (Nov 20 2026): naming the toolset through VCToolsInstallDir is not enough. `swift build` goes
# through Swift Build (the newer build system, the one whose log says CompileC ... Intermediates.noindex), and Swift
# Build sets VCToolsInstallDir itself for every task it runs: the newest toolset folder of the newest Visual Studio
# that vswhere lists, written over whatever the step's environment had (swift-build, SWBWindowsPlatform/Plugin.swift,
# WindowsEnvironmentExtension, added to the environment last in SWBBuildSystem/BuildOperation.swift). So a toolset
# named in GITHUB_ENV reached the manifest's link (14.44 in the log) but the C++ compile still took 14.52. When
# 14.51 was the newest folder on the image, the pin looked as if it worked; it was Swift Build's own choice that did.
#
# So this script makes the pinned toolset the newest one Swift Build can find: every toolset folder at or above
# $Below is moved out of each Visual Studio's VC\Tools\MSVC into a sibling folder (MSVC-set-aside). The runner is
# thrown away after the job, so nothing outlives the run. VCToolsInstallDir is still named for the steps after this
# one, for the programs that do read it (the Swift driver, a plain clang).
#
# Which toolset, the same way on every image: 14.51 when the runner has it; else the newest it has below $Below (the
# images carry Visual Studio 2022's 14.44 as well, whose library takes Clang 19 and newer); else 14.51 added through
# the Visual Studio installer, with the component's id read from the installer's own catalogue.
#
# Then it is checked by the same route the build takes: a tiny package with one C++ file that includes <string> is
# built with `swift build`, and the dependency file the compile writes must list headers from the pinned toolset's
# include folder and none from a toolset set aside. If not, the script fails, so this cannot pass quietly again.
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
$dir = Join-Path $root $have

# Set aside every toolset at or above $Below, in every Visual Studio here (Swift Build takes the newest Visual
# Studio, which need not be the one vswhere -latest named above).
$setAside = @()
$all = & "$installer\vswhere.exe" -all -products * -prerelease -property installationPath
foreach ($inst in $all) {
    $msvc = Join-Path $inst "VC\Tools\MSVC"
    if (-not (Test-Path $msvc)) { continue }
    $aside = Join-Path $inst "VC\Tools\MSVC-set-aside"
    foreach ($t in Get-ChildItem $msvc -Directory) {
        $v = $null
        if (-not [version]::TryParse($t.Name, [ref]$v)) { continue }
        if ($v -ge [version]"$Below.0") {
            New-Item -ItemType Directory -Force -Path $aside | Out-Null
            Move-Item -LiteralPath $t.FullName -Destination (Join-Path $aside $t.Name)
            "Set aside: $($t.FullName)"
            $setAside += $t.Name
        }
    }
}

# The check, by the build's own route: swift build, Swift Build, clang, and the dependency file it writes.
$trial = Join-Path ([IO.Path]::GetTempPath()) "msvc-pin-trial-$PID"
New-Item -ItemType Directory -Force -Path "$trial\Sources\Trial\include" | Out-Null
Set-Content -Path "$trial\Package.swift" -Encoding utf8 -Value @'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Trial", targets: [.target(name: "Trial")])
'@
Set-Content -Path "$trial\Sources\Trial\include\trial.h" -Encoding utf8 -Value "int trial_length(void);"
Set-Content -Path "$trial\Sources\Trial\trial.cc" -Encoding utf8 -Value @'
#include <string>
extern "C" int trial_length(void) { return (int)std::string("deckie").size(); }
'@
$env:VCToolsInstallDir = "$dir\"
Push-Location $trial
try { $out = (& swift build -v 2>&1 | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
if ($code -ne 0) { throw "the trial C++ build failed with the $have toolset pinned:`n$out" }
$deps = Get-ChildItem "$trial\.build" -Recurse -Filter "trial*.d" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $deps) { throw "the trial C++ build wrote no dependency file to check:`n$out" }
$listed = Get-Content -Raw $deps.FullName
$used = [regex]::Matches($listed, '(?i)[\\/]MSVC[\\/](\d+\.\d+\.\d+)[\\/]include') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
"The trial compile took headers from MSVC " + ($used -join ", ")
if ($used -notcontains $have -or @($used | Where-Object { $_ -ne $have }).Count -gt 0) {
    throw "the trial compile did not take the pinned $have toolset only (it took: $($used -join ', '))`n$listed"
}
Remove-Item -Recurse -Force $trial

"Pinned: MSVC $have ($dir)" + $(if ($setAside) { "; set aside: " + ($setAside -join ", ") } else { "" })
"VCToolsInstallDir=$dir\" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
"VCToolsVersion=$have" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
