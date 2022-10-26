
# Vars
$path = $PSScriptRoot
$mf2t = "$path\mf2tXP.exe"
$conv_midi = "$path\c.txt"
$output = "$path\output.txt"
$output2 = "$path\output2.txt"
$script:work_array = @()
$script:work_array2 = @()
# Functions


function cMtext($file) {
    $firstend = $true
    foreach ($line in Get-Content -Path $file) {
        $split = $($line.Split(" "))
        if ($($($split[0]) -contains "T") -and $firstend) {
            $script:work_array2 = $work_array
            $script:work_array = @()
            $firstend = $false
        }
        if ( ($split[0] -match '^[0-9]+$') -and ($split[1] -ccontains "On")) {
            $time = [int]$split[0]
            $note = [int]$split[3].TrimStart("n=")
            $vol = [int]$split[4].TrimStart("v=")
            $script:work_array += New-Object -TypeName psobject -Property @{Timing = $time; Note = $note; Volume = $vol }
        }
    }
    $script:work_array = $script:work_array | Sort-Object -Property Timing
    $script:work_array2 = $script:work_array2 | Sort-Object -Property Timing
}
function calcNoteTime() {
    $script:time_array = @()
    $script:time_array2 = @()
    foreach ($ent in $script:work_array) {
        if ($ent.Volume -gt 0) {
            $filt = $($script:work_array | Where-Object { $_.Note -eq $ent.Note -and $_.Volume -eq 0 -and $_.Timing -gt $ent.Timing } )[0]
            $script:time_array += New-Object -TypeName psobject -Property @{TStart = $ent.Timing; TDur = $($filt.timing - $ent.Timing - $ent.Volume); Note = $ent.Note; Volume = $ent.Volume }
        }
    }
    foreach ($ent in $script:work_array2) {
        if ($ent.Volume -gt 0) {
            $filt = $($script:work_array2 | Where-Object { $_.Note -eq $ent.Note -and $_.Volume -eq 0 -and $_.Timing -gt $ent.Timing })[0]
            $script:time_array2 += New-Object -TypeName psobject -Property @{TStart = $ent.Timing; TDur = $($filt.timing - $ent.Timing); Note = $ent.Note; Volume = $ent.Volume }
        }
    }
    $script:time_array2 = $time_array2 | Sort-Object -Property TStart
    $script:time_array = $time_array | Sort-Object -Property TStart
}

function Trksort() {
    # splits "double" timed notes from the midi and send it to the right time_array
    $firstindex = $false
    $corrected_array = $script:time_array2 | ConvertTo-Json | ConvertFrom-Json
    foreach($ent in $script:time_array2) {
        if ($firstindex) {
            $ix = [Array]::indexOf($time_array2, $ent)
            $pix = $time_array2[$ix -1]
            if($ent.TStart -ge $pix.TStart -and $ent.TStart -le $($pix.TStart + $pix.TDur)) {
                $corrected_array = $corrected_array | Where-Object {$_.TStart -ne $ent.TStart}
                $script:time_array += New-Object -TypeName psobject -Property @{TStart = $ent.TStart; TDur = $ent.TDur; Note = $ent.Note; Volume = $ent.Volume }
            }
        }
        else {$firstindex = $true}
    }
    $script:time_array2 = $corrected_array | ConvertTo-Json | ConvertFrom-Json
    "-"
    $firstindex = $false
    $corrected_array = $script:time_array | ConvertTo-Json | ConvertFrom-Json
    foreach($ent in $script:time_array) {
        if ($firstindex) {
            $ix = [Array]::indexOf($time_array, $ent)
            $pix = $time_array[$ix -1]
            if($ent.TStart -ge $pix.TStart -and $ent.TStart -le $($pix.TStart + $pix.TDur)) {
                $corrected_array = $corrected_array | Where-Object {$_.TStart -ne $ent.TStart}
                $script:time_array2 += New-Object -TypeName psobject -Property @{TStart = $ent.TStart; TDur = $ent.TDur; Note = $ent.Note; Volume = $ent.Volume }
            }
        }
        else {$firstindex = $true}
    }
    
    $script:time_array = $corrected_array | ConvertTo-Json | ConvertFrom-Json | Sort-Object -Property TStart
    $script:time_array2 = $script:time_array2 | Sort-Object -Property TStart
}

function ToFile() {
    # prepare code for arduino 1
    function prepare_lines($out) {
        "//" | Out-File -FilePath $out -Append
        "void setup()" | Out-File -FilePath $out -Append
        "{" | Out-File -FilePath $out -Append
        "  pinMode(0, OUTPUT);" | Out-File -FilePath $out -Append
        "}" | Out-File -FilePath $out -Append
        "//" | Out-File -FilePath $out -Append
        "void loop()" | Out-File -FilePath $out -Append
        "{" | Out-File -FilePath $out -Append
    }
    function ConvertTo-Ard() {
        $array = $args[0] | ConvertFrom-Json
        if($script:outp -eq 1) {
            $out = $output
        }
        else {
            $out = $output2
        }
        foreach ($entry in $array) {
            $freq = [System.Math]::Round(440 * [System.Math]::Pow(2, (($entry.Note - 69) / 12)))
            $ini = [Array]::indexOf($array, $entry)
            $delay = $entry.TDur
            if($ini -lt $array.length -1) {
                $delay = $array[$ini + 1].TStart - $entry.TStart
            }
            if ($ini -eq 0) {
                if ($entry.TStart -gt 0) {
                    "delay($($entry.TStart));" | Out-file -FilePath $out -Append # Initial Delay, if first note is off-time
                }
            }
            "tone(0, $freq, $($entry.TDur));" | Out-File -FilePath $out -Append
            "delay($($delay));" | Out-File -FilePath $out -Append
        }
    }
    Remove-Item $output -ErrorAction Ignore -Force
    "//Ard 1" | Out-File -FilePath $output -Append
    prepare_lines($output)
    $argctj = $time_array | ConvertTo-Json
    $script:outp = 1 
    ConvertTo-Ard($argctj)
    "delay(1000);" | Out-File -FilePath $output -Append
    "}" | Out-File -FilePath $output -Append

    ## code for arduino 2
    Remove-Item $output2 -ErrorAction Ignore -Force
    "//Ard 2" | Out-File -FilePath $output2 -Append
    prepare_lines($output2)
    $argctj = $time_array2 | ConvertTo-Json
    $script:outp = 2 
    ConvertTo-Ard($argctj)
    "delay(1000);" | Out-File -FilePath $output2 -Append
    "}" | Out-File -FilePath $output2 -Append
}

    


""
"Preparing midi..." #change filename to another midi-file
Start-Process -FilePath $mf2t -WorkingDirectory $path -ArgumentList "$path\gbtetris.mid $conv_midi"
"prepare text"
cMtext($conv_midi)
"Timings"
calcNoteTime($work_array, $work_array2)
"Sort"
Trksort
"Write to file"
ToFile($time_array, $time_array2)
return "Done, check files $output and $output2"