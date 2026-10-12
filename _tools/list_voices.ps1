Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.GetInstalledVoices() | ForEach-Object { "$($_.VoiceInfo.Name) | $($_.VoiceInfo.Culture)" }
