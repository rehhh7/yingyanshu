# Test whether System.Speech honors SSML <phoneme alphabet="ipa">.
# Output: two wavs (plain text vs IPA phoneme) + durations for comparison.
param([string]$OutDir)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono)

function Speak-File($ssmlText, $path, $isSsml) {
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $s.SelectVoice("Microsoft Zira Desktop")
    $s.Rate = 0
    $s.SetOutputToWaveFile($path, $fmt)
    if ($isSsml) {
        $pb = New-Object System.Speech.Synthesis.PromptBuilder
        $pb.AppendSsmlMarkup($ssmlText)
        $s.Speak($pb)
    } else {
        $s.Speak($ssmlText)
    }
    $s.SetOutputToNull(); $s.Dispose()
}

# plain: voice reads the letter "x"
Speak-File "x" (Join-Path $OutDir "test_plain.wav") $false
# ipa: ask for the vowel /i:/ held
Speak-File '<phoneme alphabet="ipa" ph="i&#x2D0;">x</phoneme>' (Join-Path $OutDir "test_ipa.wav") $true
# ipa consonant cluster test
Speak-File '<phoneme alphabet="ipa" ph="&#x283;&#x251;">x</phoneme>' (Join-Path $OutDir "test_ipa2.wav") $true
Get-ChildItem $OutDir | ForEach-Object { "$($_.Name) $($_.Length) bytes" }
