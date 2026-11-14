# try-desk.ps1: how the packaging workflow starts a program from the unzipped Deckie folder, with no one at the
# keyboard. Dot-sourced by the steps of .github/workflows/pc-package.yml:
#
#   . core\Tools\windows\try-desk.ps1
#   $r = Start-FromZip -Program "Deckie Desk.exe" -Arguments "--check --check-log `"$log`"" -Seconds 180
#   $r.Code       the program's exit code, or $null when it did not end in time (it is stopped then)
#   $r.Said       what it wrote to standard error and output, when -Keep was given
#   -WholePath    leaves PATH as the runner has it (to tell a missing library from anything else)
#   -Folder       another folder to start the program from (the starter copied out alone)
#
# The program is started with PATH cut down to Windows itself, so a library missing from the zip cannot be found in
# the Swift toolchain the runner has. Without -Keep nothing is redirected: the program has no console and nothing to
# write to, as after a double click. With -Keep its output goes to files, which are read back.
#
# DECKIE_NO_BOXES is set for every start: a message box here would wait for a click that never comes. The starter
# and the window then say on standard error what they would have said in the box.
#
# When a program does not end in time, or ends with a code that is not expected, this says what it can find out:
# which of Deckie's programs are still running, and what Windows wrote in its log about a program that stopped.

$DeckieFolder = Join-Path $env:RUNNER_TEMP "A DJ's PC\Deckie Desk for Windows (first test)"

function Show-WhatWindowsSaw {
    param([datetime]$Since)
    "Deckie's programs running now:"
    Get-Process | Where-Object { $_.ProcessName -match "^(Deckie Desk|deckie-desk|deckie-desk-engine|deckie-make|Make Crate File|msedgewebview2|WerFault)$" } |
        Select-Object ProcessName, Id | Format-Table -AutoSize | Out-String -Width 200
    "What Windows logged about programs that stopped, since this start:"
    try {
        Get-WinEvent -FilterHashtable @{ LogName = "Application"; StartTime = $Since } -ErrorAction Stop |
            Where-Object { $_.ProviderName -match "Application Error|Windows Error Reporting|Application Hang|SideBySide" } |
            Select-Object -First 6 | ForEach-Object { "[$($_.ProviderName)] $($_.Message)" }
    } catch { "  (nothing, or the log could not be read: $_)" }
}

function Start-FromZip {
    param(
        [Parameter(Mandatory)] [string]$Program,
        [string]$Arguments = "",
        [int]$Seconds = 180,
        [switch]$Keep,
        [switch]$WholePath,
        [string]$Folder = $DeckieFolder
    )
    $path = Join-Path $Folder $Program
    if (-not (Test-Path $path -PathType Leaf)) { throw "not there: $path" }
    $since = Get-Date
    $savedPath = $env:PATH
    $savedBoxes = $env:DECKIE_NO_BOXES
    if (-not $WholePath) { $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot" }
    $env:DECKIE_NO_BOXES = "1"
    $kept = Join-Path $env:RUNNER_TEMP ("said-" + [guid]::NewGuid().ToString("N"))
    try {
        $options = @{ FilePath = $path; PassThru = $true }
        if ($Arguments) { $options.ArgumentList = $Arguments }
        if ($Keep) { $options.RedirectStandardError = "$kept.err"; $options.RedirectStandardOutput = "$kept.out" }
        $started = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $p = Start-Process @options
        $handle = $p.Handle   # kept, so that the exit code can be read after the program ends
        $ended = $p.WaitForExit($Seconds * 1000)
    } finally {
        $env:PATH = $savedPath
        $env:DECKIE_NO_BOXES = $savedBoxes
    }
    $said = ""
    $code = $null
    if ($ended) {
        $p.WaitForExit()
        $code = $p.ExitCode
    } else {
        # Written to the log, not returned: only the result object leaves this function.
        Write-Host "$Program did not end within $Seconds s."
        Show-WhatWindowsSaw -Since $since | Out-Host
        Get-Process | Where-Object { $_.ProcessName -match "^(Deckie Desk|deckie-desk|deckie-desk-engine|msedgewebview2)$" } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    if ($Keep) {
        foreach ($f in "$kept.err", "$kept.out") { if (Test-Path $f) { $said += (Get-Content $f -Raw) } }
    }
    [pscustomobject]@{ Code = $code; Said = $said; Started = $started; Since = $since }
}

# Says a code the way Windows names it when it is one of Windows' own (0xC0000135: a library file was not found).
function Format-Code {
    param($Code)
    if ($null -eq $Code) { return "none (it did not end)" }
    if ($Code -lt 0 -or $Code -gt 255) { return ("0x{0:X8}" -f [uint32]([int64]$Code -band 0xFFFFFFFFL)) }
    return "$Code"
}
