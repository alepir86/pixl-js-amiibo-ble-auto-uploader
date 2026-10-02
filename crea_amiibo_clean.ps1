# ---- DA ADATTARE: cartella che contiene la collezione originale ----
$Origine = "C:\Percorso\Della\Tua\Collezione"   # doppi apici: va bene anche con apostrofi nel percorso
Set-Location -LiteralPath $Origine

# ---- CONFIGURAZIONE ----
$Apply       = $true                    # $false = solo anteprima | $true = crea la copia pulita
$KeepKey     = $false                   # $true = copia key_retail.bin nella radice di Amiibo_Clean
$ExcludeDirs = @('!Essential Files')    # cartelle di primo livello da scartare per intero
$Root    = (Get-Location).Path.TrimEnd('\')
$Dest    = "$env:USERPROFILE\Desktop\Amiibo_Clean"
$MaxName = 47
$MaxPath = 63
$Prefix  = 'E:/amiibo/'                  # unita' + cartella di destinazione sul dispositivo (conta nel limite dei 63)

# ---- ABBREVIAZIONI (le piu' lunghe prima) ----
$Abbrev = [ordered]@{
    'The Legend of Zelda Tears of the Kingdom' = 'TotK'
    'Legend of Zelda Tears of the Kingdom'     = 'TotK'
    'Zelda Tears of the Kingdom'               = 'TotK'
    'Tears of the Kingdom'                     = 'TotK'
    'The Legend of Zelda Breath of the Wild'   = 'BotW'
    'Legend of Zelda Breath of the Wild'       = 'BotW'
    'Zelda Breath of the Wild'                 = 'BotW'
    'Breath of the Wild'                       = 'BotW'
    'The Legend of Zelda'                      = 'Zelda'
    'Legend of Zelda'                          = 'Zelda'
    'Super Smash Brothers'                     = 'Smash'
    'Super Smash Bros'                         = 'Smash'
    'Super Nintendo World'                     = 'SNW'
    'Kirby Air Riders'                         = 'KAR'
    'Animal Crossing'                          = 'AC'
    'Monster Hunter'                           = 'MH'
}
$AbbrevRx = foreach ($k in $Abbrev.Keys) {
    [pscustomobject]@{
        Rx  = '(?<![A-Za-z0-9])' + (($k -split ' ' | ForEach-Object { [regex]::Escape($_) }) -join '\s+') + '(?![A-Za-z0-9])'
        Rep = $Abbrev[$k]
    }
}

function NormText([string]$s) {
    $s = $s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $s = ($s -replace '[^A-Za-z0-9]+', ' ').Trim()
    foreach ($a in $AbbrevRx) { $s = [regex]::Replace($s, $a.Rx, $a.Rep, 'IgnoreCase') }
    return $s
}
function NormDir([string]$s) {
    $t = NormText $s
    $t = [regex]::Replace($t, '(?<![A-Za-z0-9])(Amiibos?|Cards)(?![A-Za-z0-9])', '', 'IgnoreCase')
    return (($t -replace '\s+', ' ').Trim() -replace ' ', '_')
}
function NormFile([string]$s) {
    $t = NormText $s
    return (($t -replace '\s+', ' ').Trim() -replace ' ', '_')
}

# ---- PIANO ----
$files   = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)
$keyFile = $files | Where-Object { $_.Name -ieq 'key_retail.bin' } | Sort-Object { $_.FullName.Length } | Select-Object -First 1
$plan    = New-Object System.Collections.Generic.List[object]
$used    = @{}
$usedSrc = @{}
$usedRel = @{}

foreach ($f in $files) {
    $src    = $f.FullName.Substring($Root.Length).TrimStart('\')
    $oldDir = [IO.Path]::GetDirectoryName($src)
    if ($null -eq $oldDir) { $oldDir = '' }
    $top    = ($oldDir -split '\\')[0]
    $row = [pscustomobject]@{ Src = $src; OldDir = ($oldDir -replace '\\', '/'); Action = ''; Reason = ''; NewDir = ''; NewRel = ''; NewPathLen = 0; Note = '' }

    if ($f.Extension -ine '.bin') {
        $row.Action = 'DELETE'; $row.Reason = 'non .bin'
    } elseif ($f.Name -ieq 'key_retail.bin') {
        if ($KeepKey -and ($f.FullName -ieq $keyFile.FullName)) {
            $row.Action = 'COPY'; $row.Reason = 'key_retail'; $row.NewRel = 'key_retail.bin'
            if ($src -ine 'key_retail.bin') { $row.Note = 'SPOSTATO IN RADICE' }
            $used['/key_retail'] = $true
        } else {
            $row.Action = 'DELETE'; $row.Reason = 'key_retail non incluso'
        }
    } elseif ($ExcludeDirs -contains $top) {
        $row.Action = 'DELETE'; $row.Reason = 'cartella esclusa'
    } elseif ($f.Name -like 'Ally*' -or $f.Name -ieq 'locked-secret.bin' -or $f.Name -ieq 'unfixed-info.bin') {
        $row.Action = 'DELETE'; $row.Reason = 'non usato da Allmiibo'
    } else {
        $parts  = @(($oldDir -split '\\') | ForEach-Object { NormDir $_ } | Where-Object { $_ -ne '' })
        $newDir = $parts -join '/'
        $base   = NormFile $f.BaseName
        if ($base -eq '') { $base = 'file' }
        $dirLen = 0
        if ($newDir -ne '') { $dirLen = $newDir.Length + 1 }
        $maxBase = [Math]::Min($MaxName - 4, $MaxPath - $Prefix.Length - $dirLen - 4)
        $note = ''
        if ($maxBase -lt 6) { $maxBase = 6; $note = 'MANUALE: cartella troppo lunga' }
        if ($base.Length -gt $maxBase) { $base = $base.Substring(0, $maxBase).TrimEnd('_'); $note = ($note + ' TRONCATO').Trim() }

        $key0  = ($newDir + '/' + $base).ToLower()
        $isDup = $false
        if ($usedSrc.ContainsKey($key0)) {
            $h1 = (Get-FileHash -LiteralPath $usedSrc[$key0] -Algorithm SHA256).Hash
            $h2 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
            if ($h1 -eq $h2) { $isDup = $true }
        }

        if ($isDup) {
            $row.Action = 'DELETE'; $row.Reason = 'duplicato identico'; $row.Note = 'uguale a ' + $usedRel[$key0]
        } else {
            $cand = $base
            $i = 2
            while ($used.ContainsKey(($newDir + '/' + $cand).ToLower())) {
                $suf     = '_' + $i
                $keepLen = [Math]::Min($base.Length, $maxBase - $suf.Length)
                $cand    = $base.Substring(0, $keepLen).TrimEnd('_') + $suf
                $i++
                if ($note -notlike '*COLLISIONE*') { $note = ($note + ' COLLISIONE (contenuto diverso)').Trim() }
            }
            $keyF = ($newDir + '/' + $cand).ToLower()
            $row.Action = 'COPY'
            $row.NewDir = $newDir
            if ($newDir -ne '') { $row.NewRel = $newDir + '/' + $cand + '.bin' } else { $row.NewRel = $cand + '.bin' }
            $row.Note = $note
            $used[$keyF]    = $true
            $usedSrc[$keyF] = $f.FullName
            $usedRel[$keyF] = $row.NewRel
        }
    }
    if ($row.Action -ne 'DELETE') { $row.NewPathLen = ($Prefix + $row.NewRel).Length }
    [void]$plan.Add($row)
}

$keep   = @($plan | Where-Object { $_.Action -ne 'DELETE' })
$delNon = @($plan | Where-Object { $_.Action -eq 'DELETE' -and $_.Reason -eq 'non .bin' })
$delDup = @($plan | Where-Object { $_.Action -eq 'DELETE' -and $_.Reason -eq 'duplicato identico' })
$delUn  = @($plan | Where-Object { $_.Action -eq 'DELETE' -and $_.Reason -ne 'non .bin' -and $_.Reason -ne 'duplicato identico' })
$hasKey = @($plan | Where-Object { $_.Reason -eq 'key_retail' }).Count -gt 0
$badN   = @($keep | Where-Object { ($_.NewRel -split '/')[-1].Length -gt $MaxName })
$badP   = @($keep | Where-Object { $_.NewPathLen -gt $MaxPath })

Write-Host "=== PIANO ==="
Write-Host ("File .bin da tenere                    = " + $keep.Count)
Write-Host ("Scartati (non .bin)                    = " + $delNon.Count)
Write-Host ("Scartati (cartella esclusa / non usati)= " + $delUn.Count)
Write-Host ("Scartati (duplicati identici)          = " + $delDup.Count)
Write-Host ("key_retail.bin incluso                 = " + $hasKey)
Write-Host ("Nomi oltre 47 dopo piano               = " + $badN.Count)
Write-Host ("Percorsi oltre 63 dopo piano           = " + $badP.Count)
Write-Host ("Nomi troncati                          = " + @($keep | Where-Object { $_.Note -like '*TRONCATO*' }).Count)
Write-Host ("Collisioni con contenuto diverso (_2)  = " + @($keep | Where-Object { $_.Note -like '*COLLISIONE*' }).Count)
Write-Host ("Da sistemare a mano                    = " + @($keep | Where-Object { $_.Note -like '*MANUALE*' }).Count)

Write-Host "`n=== BIN SCARTATI (cartella esclusa / non usati) ==="
$delUn | Select-Object Src, Reason | Format-Table -AutoSize -Wrap

Write-Host "`n=== DUPLICATI IDENTICI SCARTATI ==="
$delDup | Select-Object Src, Note | Format-Table -AutoSize -Wrap

Write-Host "`n=== COLLISIONI CON CONTENUTO DIVERSO (tenuti con _2) ==="
$keep | Where-Object { $_.Note -like '*COLLISIONE*' } | Select-Object Src, NewRel | Format-Table -AutoSize -Wrap

$plan | Export-Csv -Path "$env:USERPROFILE\Desktop\piano_amiibo.csv" -NoTypeInformation -Encoding UTF8

# ---- APPLICAZIONE + VERIFICA FINALE (solo con $Apply = $true) ----
if ($Apply) {
    if (Test-Path -LiteralPath $Dest) { throw "La cartella $Dest esiste gia'. Rinominala o eliminala e rilancia." }
    New-Item -ItemType Directory -Path $Dest | Out-Null
    $toCopy = @($plan | Where-Object { $_.Action -ne 'DELETE' })
    foreach ($p in $toCopy) {
        $srcFull = Join-Path $Root $p.Src
        $dstFull = Join-Path $Dest ($p.NewRel -replace '/', '\')
        $dstDir  = Split-Path -Parent $dstFull
        if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Copy-Item -LiteralPath $srcFull -Destination $dstFull
    }

    $D = (Resolve-Path -LiteralPath $Dest).Path.TrimEnd('\')
    $v = @(Get-ChildItem -LiteralPath $D -Recurse -File -Force | ForEach-Object {
        $rel = $Prefix + ($_.FullName.Substring($D.Length).TrimStart('\') -replace '\\', '/')
        [pscustomobject]@{ Rel = $rel; Ext = $_.Extension.ToLower(); NameLen = $_.Name.Length; PathLen = $rel.Length }
    })
    $vBin = @($v | Where-Object Ext -eq '.bin')

    Write-Host "`n=== VERIFICA FINALE (su Amiibo_Clean) ==="
    Write-Host ("File .bin salvati (attesi " + $keep.Count + ") = " + $vBin.Count)
    Write-Host ("File non .bin presenti       = " + ($v.Count - $vBin.Count))
    Write-Host ("Nomi oltre 47                = " + @($vBin | Where-Object NameLen -gt $MaxName).Count)
    Write-Host ("Percorsi oltre 63            = " + @($vBin | Where-Object PathLen -gt $MaxPath).Count)
    Write-Host ("Nome piu' lungo              = " + (($vBin | Measure-Object NameLen -Maximum).Maximum))
    Write-Host ("Percorso piu' lungo          = " + (($vBin | Measure-Object PathLen -Maximum).Maximum))
    Write-Host ("key_retail.bin in radice     = " + (Test-Path -LiteralPath (Join-Path $D 'key_retail.bin')) + " (atteso: " + $KeepKey + ")")
    Write-Host ("Cartelle                     = " + @(Get-ChildItem -LiteralPath $D -Recurse -Directory -Force).Count)
}
