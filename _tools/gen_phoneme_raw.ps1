# Synthesize raw phoneme wavs from manifest (ASCII-only TSV: clip_id, ssml, mode).
param(
    [Parameter(Mandatory=$true)][string]$Manifest,
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
$s.Rate = 0

$lines = Get-Content $Manifest -Encoding ASCII
$n = 0
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split "`t", 3
    $id = $parts[0]; $ssml = $parts[1]
    $path = Join-Path $OutDir ($id + ".wav")
    if (Test-Path $path) { continue }
    $pb = New-Object System.Speech.Synthesis.PromptBuilder
    $pb.AppendSsmlMarkup($ssml)
    $s.SetOutputToWaveFile($path, $fmt)
    $s.Speak($pb)
    $n++
}
$s.SetOutputToNull(); $s.Dispose()
Write-Host "FINISH: synthesized=$n"
