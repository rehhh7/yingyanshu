# Generate offline word-audio WAVs via Windows SAPI (Microsoft Zira, en-US).
# Paths come in as parameters to avoid CJK literal encoding issues in PS 5.1.
param(
    [Parameter(Mandatory=$true)][string]$ListFile,
    [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono)
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SelectVoice("Microsoft Zira Desktop")
$s.Rate = -1   # slightly slower for learners

$lines = Get-Content $ListFile -Encoding UTF8
$done = 0; $skip = 0; $i = 0
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split "`t", 2
    $id = $parts[0]; $word = $parts[1]
    $path = Join-Path $OutDir ($id + ".wav")
    if (Test-Path $path) { $skip++; continue }
    $s.SetOutputToWaveFile($path, $fmt)
    $s.Speak($word)
    $done++
    $i++
    if ($i % 50 -eq 0) { Write-Host "progress: done=$done skip=$skip" }
}
$s.SetOutputToNull()
$s.Dispose()
Write-Host "FINISH: done=$done skip=$skip"
