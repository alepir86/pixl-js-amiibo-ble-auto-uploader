# Pixl.js: preparare e caricare una collezione Amiibo senza browser

Due script bastano per portare una collezione Amiibo di oltre mille file su un Pixl.js: il primo prepara nomi e cartelle nei limiti del dispositivo, il secondo li carica via Bluetooth senza browser e si riconnette da solo. La prova su 1063 file (firmware 2.16.0, Windows) è riuscita e i file sono rimasti dopo lo spegnimento.

File del repository: `crea_amiibo_clean.ps1` (script 1), `upload_ble.py` (script 2), `README_EN.md` (versione breve in inglese).

## Il problema

Il Pixl.js accetta file con nome fino a 47 byte e percorso fino a 63 byte, e la pagina web ufficiale non è adatta a caricare più di mille file: non estrae gli ZIP, non accetta cartelle trascinate e, nelle prove fatte, si blocca dopo alcuni minuti di trasferimento continuo.

| Limite | Valore | Note |
| --- | --- | --- |
| Nome del file, compreso `.bin` | 47 byte | nel firmware il buffer è di 48 byte, terminatore compreso |
| Percorso completo | 63 byte | la pagina web lo conta da `E:/` incluso: è la regola prudente da rispettare |
| Caratteri consigliati | solo ASCII | con ASCII i byte coincidono con i caratteri |

Cosa non funziona nella pagina web di caricamento (https://pixl.amiibo.xyz/, firmware 2.16.0):

- Un file ZIP viene caricato come un normale file, non viene estratto.
- Trascinare una cartella intera blocca il caricatore o lo disconnette.
- Dopo circa 11-12 minuti di trasferimento continuo si ferma, anche se mostra ancora "Connected", e serve disconnettere, riconnettere e aggiornare la pagina a mano.

Perché si blocca, secondo il sorgente della release 2.16.0: in `web/src/lib/pixl.proto.js` la pagina attende la risposta di ogni comando senza alcun timeout. Nel firmware, se l'invio di una risposta Bluetooth fallisce, l'errore viene solo scritto nel log. Se una risposta si perde, la pagina resta ferma per sempre. È una spiegazione ricavata dalla lettura del codice e coerente con quanto osservato, non dimostrata con strumenti sul dispositivo.

Due altri dati dal firmware: a connessione attiva il dispositivo si spegne dopo 180 secondi senza dati ricevuti (il timer si azzera a ogni dato), e accetta una sola connessione Bluetooth alla volta.

La soluzione adottata è un piccolo programma sul PC che parla direttamente lo stesso protocollo Bluetooth della pagina web, con un timeout per ogni comando e la riconnessione automatica. Il protocollo è breve e si legge nei sorgenti ufficiali del progetto Pixl.js (cartella `web/src/lib`).

## Verifiche e installazioni preliminari

Servono Windows 10 o 11 con Bluetooth Low Energy, PowerShell (già incluso), Python con la libreria `bleak` e un Pixl.js acceso con il firmware 2.16.0. Il test è stato fatto solo su Windows, con Python 3.14.3 e bleak 3.0.2; su Mac o Linux gli script PowerShell non girano e il resto non è stato provato.

1. Controlla Python. Apri PowerShell e scrivi:

```powershell
py --version
```

2. Se non risponde, installalo (poi chiudi e riapri PowerShell, altrimenti il comando non viene riconosciuto):

```powershell
winget install -e --id Python.Python.3.12
```

3. Se `python` dà l'errore "Python non è stato trovato ... Microsoft Store", è solo un alias di Windows: usa `py` al posto di `python`, oppure disattiva gli alias in Impostazioni > App > Impostazioni app avanzate > Alias di esecuzione app.

4. Installa la libreria Bluetooth:

```powershell
py -m pip install bleak
```

5. Controlla che sia installata:

```powershell
py -c "import bleak; print('bleak OK')"
```

Prima di ogni caricamento:

- Il dispositivo deve essere acceso, meglio se collegato all'USB.
- Nella pagina web Pixl.js premi Disconnect e chiudi la scheda (o tutto Chrome): il dispositivo accetta una sola connessione alla volta e, se la pagina è connessa, lo script non lo trova.
- Tieni il PC acceso, con sospensione e risparmio energetico disattivati, e il Bluetooth attivo.
- Dopo una disconnessione il dispositivo resta visibile per circa 3 minuti. Se si spegne, riaccendilo: lo script continua a cercarlo e riparte da solo.
- Se la collezione è su Google Drive, OneDrive o simili, copiala prima in una cartella locale e assicurati che i file siano scaricati sul disco, non solo "disponibili online" (vedi il prompt di verifica in fondo).

Il file `key_retail.bin` (la chiave degli emulatori) non fa parte della collezione da caricare e non va condiviso: gli script lo lasciano fuori.

## Percorsi da adattare e come trovarli

Prima di lanciare gli script vanno cambiati questi valori, che nel codice sono segnati da un commento. Tutto il resto funziona così com'è.

| Voce | Dove si cambia | A cosa serve | Come trovarla |
| --- | --- | --- | --- |
| Cartella originale | `$Origine` (script 1) | la cartella con la collezione scaricata, che non viene mai modificata | In Esplora file apri la cartella, clicca sulla barra dell'indirizzo e copia il testo, oppure Maiusc + clic destro > "Copia come percorso". Lascia i doppi apici: vanno bene anche con spazi e apostrofi. |
| Cartella pulita | `$Dest` (script 1) e `ROOT` (script 2) | la copia con nomi e cartelle a norma, che poi viene caricata; i due valori devono coincidere | Di default è `Desktop\Amiibo_Clean`. Se il Desktop è sincronizzato con OneDrive il percorso reale è diverso: controllalo con `[Environment]::GetFolderPath('Desktop')` e scrivi il percorso completo in `ROOT`. |
| Prefisso sul dispositivo | `$Prefix` (script 1) | serve a calcolare il limite dei 63 byte, che include unità e cartella di destinazione | È il percorso che la pagina web Pixl.js mostra in alto dopo la connessione, ad esempio `E:/amiibo/`. |
| Cartella sul dispositivo | `REMOTE` (script 2) | dove vengono caricate le cartelle; se manca viene creata | Lo stesso percorso del prefisso, senza barra finale: `E:/amiibo`. |
| Cartelle da escludere | `$ExcludeDirs` (script 1) | cartelle di primo livello che non devono finire nella copia | Guarda i nomi delle cartelle della tua collezione: qui c'era `!Essential Files`. |
| Abbreviazioni | `$Abbrev` (script 1) | accorcia i titoli lunghi per stare nei 47 byte | Sono scelte personali: modificale o svuotale. Le voci più lunghe vanno messe prima. |
| File di log | `LOGFILE` (script 2) | dove viene scritto il registro del caricamento | Di default `Desktop\upload_ble_log.txt`. |
| Nome Bluetooth | funzione `_find` (script 2) | il nome con cui lo script cerca il dispositivo | Il dispositivo si annuncia come "Pixl.js" (lo riconosce anche dal servizio Bluetooth). Se l'hai rinominato, cambia il nome nel codice. |

Controllo delle lunghezze sulla cartella pulita, da fare prima di caricare. Entrambi i conteggi devono essere 0:

```powershell
$D = "$env:USERPROFILE\Desktop\Amiibo_Clean"   # la tua cartella pulita
$P = 'E:/amiibo/'                               # lo stesso prefisso dello script 1
$r = Get-ChildItem -LiteralPath $D -Recurse -File | ForEach-Object {
    $full = $P + ($_.FullName.Substring($D.Length + 1) -replace '\\', '/')
    [pscustomobject]@{ Nome = $_.Name.Length; Percorso = $full.Length; File = $full }
}
"Nomi oltre 47:     " + @($r | Where-Object Nome -gt 47).Count
"Percorsi oltre 63: " + @($r | Where-Object Percorso -gt 63).Count
$r | Sort-Object Percorso -Descending | Select-Object -First 5 | Format-Table -AutoSize
```

Sul limite dei 63 byte: nel firmware il percorso viene contato dalla barra iniziale, quindi `/amiibo/...` senza `E:`, mentre la pagina web è più prudente e conta anche `E:/`. Nel test lo script 1 usava il prefisso `amiibo/` e il dispositivo ha creato tutti i 1063 file senza errori, quindi nessuno superava il limite reale. Con il prefisso `E:/amiibo/` indicato qui il controllo è prudente e vale anche per la pagina web.

## Script 1: copia pulita con nomi e cartelle a norma

Lo script crea una copia della collezione, senza toccare l'originale, in cui ogni nome file ha al massimo 47 caratteri, ogni percorso al massimo 63 (contando il prefisso del dispositivo) e non resta nessun file inutile.

Cosa fa, in ordine:

- scarta i file che non sono `.bin`, le cartelle elencate in `$ExcludeDirs` e i file inutili per Allmiibo (`Ally*`, `locked-secret.bin`, `unfixed-info.bin`);
- toglie le parole "Amiibo" e "Cards" dai nomi delle cartelle;
- abbrevia i titoli con il dizionario `$Abbrev`, per esempio Tears of the Kingdom in TotK, Breath of the Wild in BotW, Super Smash Bros in Smash, Animal Crossing in AC, Monster Hunter in MH;
- sostituisce spazi e caratteri speciali con `_` e toglie gli accenti;
- se dopo la rinomina due file hanno lo stesso nome, confronta l'hash SHA256: se sono identici ne tiene uno solo, se sono diversi aggiunge il suffisso `_2`;
- accorcia un nome solo quando serve per rispettare i limiti;
- salva il piano completo in `piano_amiibo.csv` sul Desktop e stampa un riepilogo.

Come si usa:

1. Imposta `$Origine` e gli altri valori della sezione sui percorsi.
2. La prima volta metti `$Apply = $false`: mostra solo l'anteprima e non crea nulla. Controlla il riepilogo.
3. Con `$Apply = $true` crea la copia in `$Dest` (se esiste già si ferma: rinominala o eliminala) e stampa la VERIFICA FINALE, dove nomi oltre 47, percorsi oltre 63 e file non `.bin` devono essere 0.

Nel test, da 1075 file `.bin` si è arrivati a 1063 dopo gli scarti: la cartella esclusa, i file inutili e 7 duplicati identici.

```powershell
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
```

## Script 2: caricamento via Bluetooth senza browser

Lo script legge la cartella pulita, si collega al Pixl.js, crea sul dispositivo le cartelle che mancano e carica i file mancanti o di dimensione diversa. Ogni comando ha un timeout di 8 secondi: se il dispositivo non risponde o si disconnette, lo script si riconnette da solo e rifa il file da capo.

Come funziona il protocollo, ricavato dai sorgenti 2.16.0 (`web/src/lib/pixl.proto.js` e il firmware):

- Servizio Bluetooth Nordic UART `6e400001-b5a3-f393-e0a9-e50e24dcca9e`: si scrive sulla caratteristica `...0002` e si ricevono le risposte come notifiche sulla `...0003`.
- Un frame è: comando (1 byte), stato (1), chunk (2, little-endian), dati. Le stringhe sono lunghezza (2 byte) + UTF-8. Lo stato 0 nella risposta significa successo.
- Il dispositivo tratta ogni scrittura come un frame completo di al massimo 247 byte, quindi serve un MTU di almeno 250 (nel test era 250). Con un MTU più basso lo script riduce da solo i blocchi.

| Comando | Codice | Contenuto |
| --- | --- | --- |
| Versione | `0x01` | vuoto |
| Apri file | `0x12` | percorso + flag `0x16` (crea o sostituisce, scrittura) |
| Scrivi file | `0x15` | id file (0) + fino a 242 byte; i blocchi intermedi hanno il bit `0x8000` e non attendono risposta |
| Chiudi file | `0x13` | id file |
| Leggi cartella | `0x16` | percorso, risposta con nome, dimensione e tipo di ogni voce |
| Crea cartella | `0x17` | percorso; scrive il file marcatore `.folder` |

Attenzione alle cartelle: il file system del dispositivo (SPIFFS) non ha vere cartelle. Una cartella esiste solo se contiene il file marcatore `.folder`, e leggere una cartella che non esiste risponde "vuota" invece di dare errore. Per questo lo script controlla che la cartella compaia nell'elenco di quella superiore e, se manca, la crea con `0x17`. Una versione precedente non lo faceva: i file venivano scritti, ma le cartelle non comparivano nella pagina web.

Come si usa:

1. Copia il codice qui sotto in un file di testo e salvalo come `upload_ble.py` (in Blocco note scegli "Tutti i file" e la codifica UTF-8).
2. Adatta `ROOT`, `REMOTE` e `LOGFILE` come nella sezione dei percorsi.
3. Chiudi la pagina web Pixl.js, accendi il dispositivo e lancia:

```powershell
py "C:\percorso\di\upload_ble.py"
py "C:\percorso\di\upload_ble.py" AC/Series_1
```

Il secondo comando carica solo le cartelle il cui percorso contiene il testo indicato: è utile per una prima prova prudente, e su una cartella già completa non scrive nulla. Si può interrompere con Ctrl+C e rilanciare quando si vuole, perché riparte da dove era. Alla fine stampa `RIEPILOGO: verificati N / totale` e l'elenco di eventuali file mancanti.

```python
# -*- coding: utf-8 -*-
# upload_ble.py - carica Amiibo_Clean su Pixl.js via BLE (senza browser)
# Protocollo ricavato dai sorgenti ufficiali pixl.js 2.16.0 (web/src/lib/pixl.proto.js)
# Uso:  python upload_ble.py            (tutto)
#       python upload_ble.py AC/Series_3 (solo cartelle che contengono il testo)
import asyncio
import datetime
import os
import struct
import sys

from bleak import BleakClient, BleakScanner
from bleak.exc import BleakError

ROOT = os.path.join(os.path.expanduser("~"), "Desktop", "Amiibo_Clean")
REMOTE = "E:/amiibo"
LOGFILE = os.path.join(os.path.expanduser("~"), "Desktop", "upload_ble_log.txt")

NUS = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
TX = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  # PC -> dispositivo
RX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # dispositivo -> PC (notifiche)

CMD_VERSION = 0x01
CMD_OPEN = 0x12
CMD_CLOSE = 0x13
CMD_WRITE = 0x15
CMD_READDIR = 0x16
CMD_MKDIR = 0x17

TIMEOUT = 8.0        # secondi di attesa per ogni risposta
FAILS_BEFORE_RECONNECT = 2
MAX_FILE_ERRORS = 4  # errori protocollo (status != 0) prima di saltare un file


def log(msg):
    line = "[%s] %s" % (datetime.datetime.now().strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    try:
        with open(LOGFILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


class LinkLost(Exception):
    pass


class ProtoError(Exception):
    pass


class Pixl:
    def __init__(self):
        self.client = None
        self.addr = None
        self.connected = False
        self.queue = asyncio.Queue()
        self.acc = None
        self.mtu = 23
        self.fails = 0

    # ---------- connessione ----------
    def _on_disconnect(self, _client):
        self.connected = False
        log("!! Disconnesso dal dispositivo")
        self.queue.put_nowait(None)

    def _on_rx(self, _char, data):
        data = bytes(data)
        if len(data) < 4:
            return
        cmd, status, chunk = struct.unpack("<BBH", data[:4])
        payload = data[4:]
        if self.acc is None:
            self.acc = {"cmd": cmd, "status": status, "payload": bytearray(payload)}
        else:
            self.acc["payload"] += payload
        if not (chunk & 0x8000):
            a = self.acc
            self.acc = None
            self.queue.put_nowait((a["cmd"], a["status"], bytes(a["payload"])))

    async def _find(self):
        found = await BleakScanner.discover(timeout=6.0, return_adv=True)
        best = None
        for addr, (dev, adv) in found.items():
            name = (dev.name or adv.local_name or "")
            uuids = [u.lower() for u in (adv.service_uuids or [])]
            if name.lower().startswith("pixl") or NUS in uuids:
                if addr == self.addr:
                    return dev
                best = best or dev
        return best

    async def connect(self):
        await self.drop()
        n = 0
        while True:
            n += 1
            try:
                dev = await self._find()
                if dev is None:
                    log("Dispositivo non trovato (tentativo %d). Accendilo / premi un tasto; "
                        "chiudi la pagina web Pixl.js in Chrome se e' connessa." % n)
                    await asyncio.sleep(3)
                    continue
                self.addr = dev.address
                self.client = BleakClient(dev, disconnected_callback=self._on_disconnect, timeout=15.0)
                await self.client.connect()
                await self.client.start_notify(RX, self._on_rx)
                self.connected = True
                self.acc = None
                while not self.queue.empty():
                    self.queue.get_nowait()
                try:
                    self.mtu = int(self.client.mtu_size)
                except Exception:
                    self.mtu = 23
                self.fails = 0
                log("Connesso a %s (MTU %d)" % (self.addr, self.mtu))
                return
            except Exception as e:
                log("Connessione fallita: %r (riprovo)" % (e,))
                await self.drop()
                await asyncio.sleep(3)

    async def drop(self):
        self.connected = False
        c = self.client
        self.client = None
        if c is not None:
            try:
                await asyncio.wait_for(c.disconnect(), 8)
            except Exception:
                pass

    # ---------- protocollo ----------
    async def request(self, cmd, payload=b"", chunk=0, expect=True, timeout=TIMEOUT):
        if not self.connected:
            raise LinkLost()
        while not self.queue.empty():
            self.queue.get_nowait()
        frame = struct.pack("<BBH", cmd, 0, chunk) + payload
        try:
            await asyncio.wait_for(self.client.write_gatt_char(TX, frame, response=True), timeout)
        except asyncio.TimeoutError:
            raise
        except (BleakError, OSError) as e:
            raise LinkLost(str(e))
        if not expect:
            return None
        while True:
            try:
                item = await asyncio.wait_for(self.queue.get(), timeout)
            except asyncio.TimeoutError:
                raise
            if item is None:
                raise LinkLost()
            if item[0] == cmd:
                return item[1], item[2]

    @staticmethod
    def _str(s):
        b = s.encode("utf-8")
        return struct.pack("<H", len(b)) + b

    async def list_dir(self, path):
        status, data = await self.request(CMD_READDIR, self._str(path))
        if status != 0:
            return None
        out = {}
        i = 0
        while i + 2 <= len(data):
            (n,) = struct.unpack_from("<H", data, i)
            i += 2
            if i + n + 6 > len(data):
                break
            name = data[i:i + n].decode("utf-8", "replace")
            i += n
            (size,) = struct.unpack_from("<I", data, i)
            i += 4
            typ = data[i]
            i += 1
            msz = data[i]
            i += 1 + msz
            out[name] = (size, typ)
        return out

    async def mkdir(self, path):
        status, _ = await self.request(CMD_MKDIR, self._str(path))
        return status == 0

    async def put_file(self, path, data):
        status, _ = await self.request(CMD_OPEN, self._str(path) + struct.pack("<I", 0x16))
        if status != 0:
            raise ProtoError("open status=%d" % status)
        step = max(8, min(242, self.mtu - 3 - 5))
        off = 0
        total = len(data)
        if total == 0:
            status, _ = await self.request(CMD_WRITE, b"\x00")
            if status != 0:
                raise ProtoError("write status=%d" % status)
        while off < total:
            part = data[off:off + step]
            off += len(part)
            last = off >= total
            if last:
                status, _ = await self.request(CMD_WRITE, b"\x00" + part, chunk=0)
                if status != 0:
                    raise ProtoError("write status=%d" % status)
            else:
                await self.request(CMD_WRITE, b"\x00" + part, chunk=0x8000, expect=False)
        status, _ = await self.request(CMD_CLOSE, b"\x00")
        if status != 0:
            raise ProtoError("close status=%d" % status)

    # ---------- esecuzione robusta ----------
    async def robust(self, fn, *args):
        """Esegue fn; su timeout/disconnessione riprova e, se serve, riconnette. Non si arrende mai."""
        while True:
            try:
                if not self.connected:
                    await self.connect()
                r = await fn(*args)
                self.fails = 0
                return r
            except ProtoError:
                raise
            except (asyncio.TimeoutError, LinkLost, BleakError, OSError) as e:
                self.fails += 1
                log("Problema (%s) - fallimenti consecutivi: %d" % (type(e).__name__, self.fails))
                if isinstance(e, LinkLost) or self.fails >= FAILS_BEFORE_RECONNECT:
                    log("Riconnessione automatica...")
                    await self.drop()
                    await asyncio.sleep(2)
                    await self.connect()
                else:
                    await asyncio.sleep(1)


def parent_of(path):
    par = path.rsplit("/", 1)[0]
    if par.endswith(":"):
        par += "/"          # radice dell'unita': "E:/"
    return par


async def dir_exists(p, path):
    # Sul Pixl.js (file system SPIFFS) leggere una cartella inesistente non da' errore:
    # risponde "vuota". Una cartella esiste davvero solo se compare come DIR nell'elenco
    # della cartella che la contiene (cioe' se contiene il marcatore ".folder").
    par = parent_of(path)
    name = path.rsplit("/", 1)[1]
    lst = await p.robust(p.list_dir, par)
    return lst is not None and name in lst and lst[name][1] == 1


async def ensure_dir(p, path, known):
    if path in known:
        return
    if not await dir_exists(p, path):
        par = parent_of(path)
        if len(par) > 3:
            await ensure_dir(p, par, known)
        await p.robust(p.mkdir, path)
        if not await dir_exists(p, path):
            raise RuntimeError("Impossibile creare la cartella " + path +
                               " (percorso troppo lungo o memoria piena?)")
        log("Creata cartella " + path)
    known.add(path)


async def main():
    flt = sys.argv[1].replace("\\", "/") if len(sys.argv) > 1 else None

    local = {}
    for dp, _dn, fn in os.walk(ROOT):
        rel = os.path.relpath(dp, ROOT).replace("\\", "/")
        rel = "" if rel == "." else rel
        for f in fn:
            if f.lower().endswith(".bin"):
                local.setdefault(rel, []).append(f)
    dirs = sorted(d for d in local if (flt is None or flt in d))
    total = sum(len(local[d]) for d in dirs)
    log("Cartelle: %d, file da verificare/caricare: %d" % (len(dirs), total))

    p = Pixl()
    await p.connect()
    v = await p.robust(p.request, CMD_VERSION)
    log("Dispositivo risponde (versione frame ok)")

    known = set()
    await ensure_dir(p, REMOTE, known)

    verified = 0
    bad = []
    t0 = datetime.datetime.now()
    for d in dirs:
        rdir = REMOTE + ("/" + d if d else "")
        await ensure_dir(p, rdir, known)
        files = sorted(local[d])
        for attempt in range(3):
            lst = await p.robust(p.list_dir, rdir) or {}
            todo = []
            for f in files:
                sz = os.path.getsize(os.path.join(ROOT, d, f))
                if f not in lst or lst[f][0] != sz:
                    todo.append(f)
            if attempt == 0:
                log("%s: presenti %d, da caricare %d" % (d or "(root)", len(files) - len(todo), len(todo)))
            if not todo:
                break
            for f in todo:
                with open(os.path.join(ROOT, d, f), "rb") as fh:
                    data = fh.read()
                errs = 0
                while True:
                    try:
                        await p.robust(p.put_file, rdir + "/" + f, data)
                        break
                    except ProtoError as e:
                        errs += 1
                        log("   %s errore protocollo: %s (%d)" % (f, e, errs))
                        if errs >= MAX_FILE_ERRORS:
                            break
                        await asyncio.sleep(1)
        lst = await p.robust(p.list_dir, rdir) or {}
        ok = 0
        for f in files:
            sz = os.path.getsize(os.path.join(ROOT, d, f))
            if f in lst and lst[f][0] == sz:
                ok += 1
            else:
                bad.append(d + "/" + f)
        verified += ok
        el = (datetime.datetime.now() - t0).total_seconds()
        log("   OK %d/%d  (totale verificati %d/%d, %.0f s)" % (ok, len(files), verified, total, el))

    log("RIEPILOGO: verificati %d / %d" % (verified, total))
    if bad:
        log("MANCANTI (%d):" % len(bad))
        for b in bad:
            log("  " + b)
    await p.drop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log("Interrotto dall'utente (puoi rilanciare: riprende da dove era)")
```

## Risultati e problemi incontrati

Il caricamento di 1063 file in 62 cartelle è riuscito, con riconnessioni automatiche e senza intervento. Al primo giro però lo script non creava davvero le cartelle: i file c'erano, ma le cartelle non comparivano come tali. Con la versione corrente, descritta qui sopra, tutto è visibile e funziona anche dopo il riavvio. Ogni file è un dump da 540 byte.

| Prova | Esito |
| --- | --- |
| Primo giro: circa 500 file mancanti caricati, gli altri già presenti verificati | 1063 / 1063 in 1109 secondi |
| Riconnessioni automatiche durante il primo giro | 3 (dopo 1, 2 e 4 minuti circa), ogni volta ripresa da sola |
| Secondo giro, nessuna scrittura necessaria | 1063 / 1063 in 156 secondi |
| Giro con la versione corretta: creazione delle cartelle mancanti | 56 cartelle create, 1063 / 1063 in 269 secondi |
| Dopo il riavvio del dispositivo | le cartelle compaiono e il dispositivo funziona |

La verifica controlla nome e dimensione di ogni file riletti dal dispositivo, non il contenuto byte per byte.

Problemi incontrati e come si risolvono:

| Problema | Causa probabile | Cosa fare |
| --- | --- | --- |
| Le cartelle non compaiono nella pagina web (solo quelle create a mano), anche dopo Refresh | il file system del dispositivo (SPIFFS) non ha vere cartelle: ne crea una scrivendo un file marcatore `.folder`. Leggere una cartella inesistente risponde "vuota" senza errore, e le prime versioni dello script lo scambiavano per "esiste" | usare la versione corrente dello script 2, che controlla la cartella nell'elenco di quella superiore e la crea con il comando `0x17` se manca |
| "Python non è stato trovato" | alias del Microsoft Store, oppure PATH non ancora aggiornato | riaprire PowerShell, usare `py`, disattivare gli alias |
| "Dispositivo non trovato" per alcuni tentativi | pagina web ancora connessa, dispositivo spento o non visibile | premere Disconnect e chiudere la scheda, accendere il dispositivo; nel test bastavano 2-3 tentativi |
| "Connessione fallita: TimeoutError" | il dispositivo non risponde subito alla connessione | nessuna, lo script riprova da solo |
| Pagina che mostra "Connected" ma non carica | una risposta Bluetooth si perde e la pagina non ha timeout | usare lo script 2 |
| ZIP non estratto, cartelle trascinate che bloccano | limiti della pagina web | usare lo script 2 |
| Dispositivo che si spegne durante il trasferimento | timer di sleep a 180 secondi senza dati, oppure batteria | alimentazione USB, riaccendere: lo script riprende |
| Automazione della pagina con Playwright su Chrome | la connessione Bluetooth va comunque confermata a mano e non regge i blocchi | abbandonata |

Limiti noti:

- Testato solo su Windows, firmware 2.16.0, Python 3.14.3, bleak 3.0.2.
- Lo script salta un file se esiste già con la stessa dimensione: se il contenuto è diverso non se ne accorge.
- Per i file nuovi o di dimensione diversa la scrittura sostituisce il file esistente con lo stesso nome.
- Se il dispositivo si spegne del tutto, va riacceso a mano.

## Prompt per far verificare script e documento

Chi riusa questa guida con il proprio account cloud o con un altro assistente può incollare il prompt qui sotto, compilando le parti tra parentesi quadre, prima di eseguire qualsiasi cosa. Serve a far controllare percorsi, versioni e rischi sul proprio caso, senza dare per buoni i valori di questo documento.

```text
Sto per usare la guida "Pixl.js: preparare e caricare una collezione Amiibo senza browser" e i suoi due script: uno PowerShell per preparare nomi e cartelle, uno Python con la libreria bleak per caricare i file via Bluetooth. Prima di eseguirli aiutami a verificare che siano adatti al mio caso. Non eseguire nulla al posto mio e non inventare: se un dato non lo puoi controllare, dimmelo.

Il mio ambiente: [sistema operativo e versione], [versione di Python e di bleak], [modello del dispositivo e versione del firmware Pixl.js], [dove si trova la collezione: disco locale / Google Drive / OneDrive / Dropbox / altro].

1. Percorsi. Ti incollo le variabili da adattare ($Origine, $Dest, $Prefix, ROOT, REMOTE, LOGFILE). Controlla che siano coerenti tra loro e con il mio sistema: Desktop reindirizzato su OneDrive, percorsi con spazi o apostrofi, unità del dispositivo diversa da E:.
2. Cloud. Se la collezione è su un servizio cloud, dimmi come verificare che tutti i file siano davvero scaricati sul disco e non solo "disponibili online", e di lavorare su una copia locale prima di lanciare lo script 1.
3. Limiti. Verifica se i limiti usati (nome file fino a 47 byte, percorso fino a 63 byte incluse unità e cartella di destinazione) valgono per la mia versione di firmware. Se non puoi saperlo con certezza, indicami dove controllarlo (i sorgenti ufficiali della mia release) e quali informazioni di versione o dati aggiornati conviene far confermare a una fonte esterna prima di procedere.
4. Sicurezza. Leggi lo script 1 e lo script 2 riga per riga e dimmi cosa scrivono e dove. Conferma che lo script 1 non modifica la cartella originale e che lo script 2 scrive solo nella cartella del dispositivo indicata in REMOTE. Segnala ogni comando che cancella o sovrascrive file.
5. Prova prudente. Proponimi una prova su una sola cartella piccola prima del caricamento completo (per esempio lo script 2 con il nome di una cartella come argomento) e come riconoscere che è andata bene.
6. Riepilogo. Alla fine elencami, in due liste separate, cosa hai verificato e cosa resta una mia responsabilità controllare.
```

Un consiglio per chi condivide o ripubblica la guida: prima di passarla ad altri togli dai percorsi il proprio nome utente, e non includere mai i file chiave degli emulatori né i dump della propria collezione.
