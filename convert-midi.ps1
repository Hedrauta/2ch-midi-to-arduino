
# Vars
$path = $PSScriptRoot
$mf2t = "$path\mf2tXP.exe"
$conv_midi = "$path\c.txt"
$output = "$path\output.txt"
# Functions


function cMtext($file) {
    $script:work_array = @()
    $tempo = 1
    foreach ($line in Get-Content -Path $file) {
        $split = $($line.Split(" "))
        if ($split[1] -eq "Tempo") {
            $tempo = 1 / ($($split[2]) / 500000)
        }
        if ( ($split[0] -match '^[0-9]+$') -and ($split[1] -ccontains "On")) {
            $time = [int]$split[0]
            $note = [int]$split[3].TrimStart("n=")
            $vol = [int]$split[4].TrimStart("v=")
            $state = if($split[1] -contains "On") {$true} else {$false}
            $script:work_array += New-Object -TypeName psobject -Property @{State = $state; Timing = $time; Note = $note; Volume = $vol; Speed = $tempo; Port = 0 }
        }
    }
    $script:work_array = $script:work_array | Sort-Object -Property Timing
}
function calcNoteTime() {
    function MathSpeed($time, $speed) {
        return [Math]::Floor($time / $speed)
    }
    $script:time_array = @()
    foreach ($ent in $script:work_array) {
        if ($ent.Volume -gt 0) {
            $filt = $($script:work_array | Where-Object { $_.Note -eq $ent.Note -and $($_.Volume -eq 0 -or $_.State -eq $false) -and $_.Timing -gt $ent.Timing } )[0]
            $script:time_array += New-Object -TypeName psobject -Property @{TStart = $(MathSpeed $ent.Timing $ent.speed); TDur = $(MathSpeed $($filt.timing - $ent.Timing) $ent.speed); Note = $ent.Note; Port = $ent.Port}
        }
    }
    $script:time_array = $time_array | Sort-Object -Property TStart
}

function Portsort() {
    # Set note to correct port, if in another port for each "time-array"

    $firstindex = $true
    $CorrectedObject = @()
    foreach ($entry in $time_array) {
        if ($firstindex) {
            $CorrectedObject += $entry
            $firstindex = $false
        }
        elseif (!$firstindex) {
            $pick = $null
            $filter = $CorrectedObject | Where-Object {$entry.Tstart -ge $_.Tstart -and $entry.Tstart -le ($_.TStart + $_.TDur)}
            if ($filter.length -gt 0) {
                $pick = $filter[$filter.length -1]
            }
            if ($null -ne $pick) {
                $CorrectedObject += New-Object -TypeName psobject -Property @{Note = $entry.Note; Speed = $entry.Speed; TStart = $entry.Tstart; TDur = $entry.TDur; Port = $($pick.Port + 1)}
            }
            else {
                $CorrectedObject += $entry
            }
        }
    }
    
    $script:time_array = $CorrectedObject | ConvertTo-Json | ConvertFrom-Json | Sort-Object -Property TStart
}

function MathAndWrite() {
    # prepare code for arduino 1
    function prepare_lines() {
        "// Code written by a Powershell-Script" | Out-File -FilePath $output -Append
        "void setup()" | Out-File -FilePath $output -Append
        "{" | Out-File -FilePath $output -Append
        "  pinMode(0, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(1, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(2, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(3, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(4, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(5, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(6, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(7, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(8, OUTPUT);" | Out-File -FilePath $output -Append
        "  pinMode(9, OUTPUT);" | Out-File -FilePath $output -Append
        "}" | Out-File -FilePath $output -Append
        "//" | Out-File -FilePath $output -Append
        "void loop()" | Out-File -FilePath $output -Append
        "{" | Out-File -FilePath $output -Append
    }
    function ConvertTo-Ard($array) {
        $script:end = $null
        foreach ($entry in $array) {
            # TODO: MATH!!!!!!!
            $freq = [System.Math]::Round(440 * [System.Math]::Pow(2, (($entry.Note - 69) / 12)))
            $i = [Array]::indexOf($array, $entry)
            if ($entry.Port -eq 0) {
                if ($null -ne $script:end) {
                    $pix = $time_array[$i - 1]
                    "delay($($($entry.TStart - $script:end) + $($script:end - $pix.TStart)));" | Out-File -FilePath $output -Append;
                }
                $script:end = $entry.TStart + $entry.TDur
                "tone($($entry.Port), $($freq), $($entry.TDur));" | Out-File -FilePath $output -Append
            }
            elseif ($entry.Port -ne 0) {
                $pix = $time_array[$i - 1]
                if ($($entry.TStart - $pix.TStart) -gt 0) {
                    "delay($($entry.TStart - $pix.TStart));" | Out-File -FilePath $output -Append
                }
                if ($script:end -lt $($entry.TStart + $entry.TDur)) {
                    $script:end = $entry.TStart + $entry.TDur
                }
                "tone($($entry.Port), $($freq), $($entry.TDur));" | Out-File -FilePath $output -Append
            }
        }
    }
    
    Remove-Item $output -ErrorAction Ignore -Force
    "//Ard 1" | Out-File -FilePath $output -Append
    prepare_lines
    ConvertTo-Ard $time_array
    "delay(1000);" | Out-File -FilePath $output -Append
    "}" | Out-File -FilePath $output -Append

}

# TODO: do some serious math

""
"Preparing midi..." #change filename to another midi-file
Start-Process -FilePath $mf2t -WorkingDirectory $path -Wait -ArgumentList "$path\gbtetris.mid $conv_midi"
"prepare text"
cMtext($conv_midi)
"Timings"
calcNoteTime
"Sort"
Portsort
"Write to file"
MathAndWrite $time_array
return "Done, check file: $output"