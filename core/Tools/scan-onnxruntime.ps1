# scan-onnxruntime.ps1: look for Microsoft's usage-reporting client ("telemetry") in ONNX Runtime library files.
#
#   pwsh core/Tools/scan-onnxruntime.ps1 LIBRARY...   exit 0 when no file carries a trace, 1 when any does, 2 on an error
#   pwsh core/Tools/scan-onnxruntime.ps1 -List        print the marker texts, one per line
#
# This is the gate in .github/workflows/onnxruntime-build.yml on Windows: the library Deckie builds with
# --no_telemetry is not uploaded if this finds any trace of the client in it (DEPENDENCIES.md, section 6).
# scan-onnxruntime.sh is the same scan for Linux and macOS.
#
# The markers. The source of truth is OnnxRuntime.ReportingClientScan.markers in
# core/Sources/DeckieInference/ReportingClientScan.swift, which the Swift release test scans with; the list below is
# a copy, so that the gate needs no Swift toolchain on the build machines. Keep this list, the one in
# scan-onnxruntime.sh and the Swift one equal, in the same order (the workflow's first job checks that they are).
#
# How it looks. Each marker's text is searched for as plain bytes anywhere in the file, as the Swift scan does: the
# file is read whole and mapped byte for byte to characters (Latin-1, so every byte is one character and the ASCII
# markers match exactly the bytes they are), then searched with an ordinal comparison. Runs on Windows PowerShell 5.1
# and PowerShell 7.

param(
    [switch]$List,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths
)

$markers = @(
    @{ Text = 'mobile.events.data.microsoft.com'; Name = 'the reporting address' },
    @{ Text = 'Microsoft12Applications6Events'; Name = "the 1DS client's namespace" },
    @{ Text = 'telemetry_1ds'; Name = "ONNX Runtime's 1DS source file" },
    @{ Text = 'OneDsTelemetry'; Name = "ONNX Runtime's 1DS provider class" },
    @{ Text = 'CurlHttpOperation'; Name = "the 1DS client's curl transport" },
    @{ Text = 'https://curl.se/docs/'; Name = "curl's documentation address" },
    @{ Text = 'SQLite format 3'; Name = "SQLite's file header" },
    @{ Text = 'mbedtls_ssl_'; Name = "mbedTLS's TLS functions" },
    @{ Text = 'Microsoft.ML.ONNXRuntime'; Name = 'the Windows event-tracing provider' }
)

function Fail-Usage {
    [Console]::Error.WriteLine('usage: scan-onnxruntime.ps1 LIBRARY... | -List')
    exit 2
}

if ($List) {
    if ($Paths) { Fail-Usage }
    foreach ($m in $markers) { Write-Output $m.Text }
    exit 0
}
if (-not $Paths) { Fail-Usage }

$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$carrying = $false
foreach ($lib in $Paths) {
    if (-not (Test-Path -LiteralPath $lib -PathType Leaf)) {
        [Console]::Error.WriteLine("scan-onnxruntime: ${lib}: not a readable file")
        exit 2
    }
    try {
        $full = (Resolve-Path -LiteralPath $lib).ProviderPath
        $bytes = [System.IO.File]::ReadAllBytes($full)
    } catch {
        [Console]::Error.WriteLine("scan-onnxruntime: could not read ${lib}: $($_.Exception.Message)")
        exit 2
    }
    $text = $latin1.GetString($bytes)
    $found = @($markers | Where-Object { $text.IndexOf($_.Text, [System.StringComparison]::Ordinal) -ge 0 })
    # In a Windows library (.dll) the event-tracing provider's name is present but never registered, so it is
    # reported, not fatal (the main session's rule, Oct 29, 2026, confirmed by the first build): windows/telemetry.cc
    # defines the provider with its name (TRACELOGGING_DEFINE_PROVIDER(telemetry_provider_handle,
    # "Microsoft.ML.ONNXRuntime", ...), line 61 at the pinned commit) and is compiled into every Windows build
    # (cmake/onnxruntime_common.cmake); the one call that registers it, TraceLoggingRegisterEx in
    # WindowsTelemetry::WindowsTelemetry(), runs only when WindowsEnv holds a WindowsTelemetry, which needs
    # USE_WINDOWS_TELEMETRY or USE_1DS_TELEMETRY (windows/env.h), both left undefined by --no_telemetry; the
    # environment then holds the base Telemetry class, whose functions do nothing. Every other marker still fails,
    # and the name fails too in any file that is not a .dll.
    $providerName = 'Microsoft.ML.ONNXRuntime'
    $isDll = [System.IO.Path]::GetExtension($lib).ToLowerInvariant() -eq '.dll'
    $fatal = @($found | Where-Object { -not ($isDll -and $_.Text -eq $providerName) })
    $reported = @($found | Where-Object { $isDll -and $_.Text -eq $providerName })
    if ($fatal.Count -eq 0) {
        Write-Output "$lib ($($bytes.Length) bytes): no trace of the reporting client ($($fatal.Count) of $($markers.Count) markers)"
    } else {
        $carrying = $true
        Write-Output "$lib ($($bytes.Length) bytes): REPORTING CLIENT FOUND, $($fatal.Count) of $($markers.Count) markers:"
        foreach ($m in $fatal) { Write-Output "  $($m.Name): $($m.Text)" }
    }
    foreach ($m in $reported) {
        Write-Output "  reported, not fatal: $($m.Name), $($m.Text): present, never registered (TraceLoggingRegisterEx is called only by WindowsTelemetry::WindowsTelemetry(), which --no_telemetry leaves unconstructed; see the comment above)"
    }
}
if ($carrying) { exit 1 }
exit 0
