# Bulk upload amiibo to a Pixl.js over Bluetooth (no web uploader)

Two small scripts to prepare a large amiibo collection for a Pixl.js and copy it to the device over BLE from Windows, without the web uploader. Tested with about 1,000 files on firmware 2.16.0: the upload finished in roughly 18 minutes, the script reconnected by itself three times, and everything was still there after a power cycle.

The full write-up (in Italian) is in `README.md`. This file is the short English version.

## Why

The web uploader (https://pixl.amiibo.xyz/) is fine for a handful of files, but for a big collection I ran into this:

- ZIP files are uploaded as a normal file, they are not extracted.
- Dragging a whole folder hangs the uploader or disconnects it.
- After roughly 11-12 minutes of continuous transfer it stalls while still showing "Connected".

Reading the 2.16.0 sources, the likely reason is that the page waits for the answer to each command with no timeout, and the firmware only logs an error if it fails to send an answer. If one answer is lost, the page waits forever. This is my reading of the code, not something I proved on the device.

## Device limits

| Limit | Value |
| --- | --- |
| File name, including `.bin` | 47 bytes |
| Full path | 63 bytes (the web page counts it from `E:/`, which is the safe rule to follow) |

Use plain ASCII names so bytes and characters match.

## What is in this repo

| File | What it does |
| --- | --- |
| `crea_amiibo_clean.ps1` | PowerShell. Makes a clean copy of your collection with names and folders that fit the limits. The original is never modified. |
| `upload_ble.py` | Python. Uploads the clean copy to the Pixl.js over Bluetooth, creates missing folders, skips files already present, reconnects automatically. |
| `README.md` | Full write-up in Italian, with the complete explanation. |

## Requirements

- Windows 10 or 11 with Bluetooth Low Energy, PowerShell, Python 3 and the `bleak` library.
- A Pixl.js with firmware 2.16.0 (other versions are untested).

Tested with Python 3.14.3 and bleak 3.0.2. Not tested on macOS or Linux.

```powershell
winget install -e --id Python.Python.3.12
py -m pip install bleak
```

Close and reopen PowerShell after installing Python. If `python` shows a "Microsoft Store" message, use `py` instead.

## Usage

1. Open `crea_amiibo_clean.ps1` and set `$Origine` to the folder with your collection. Leave `$Apply = $false` for a first run: it only prints a preview and creates nothing. Then set it to `$true` to create the clean copy.
2. Check the final report: names over 47, paths over 63 and non-`.bin` files must all be 0.
3. In the Pixl.js web page press Disconnect and close the tab (the device accepts one Bluetooth connection at a time). Turn the device on, ideally on USB power.
4. Run the uploader:

```powershell
py upload_ble.py                  # everything
py upload_ble.py AC/Series_1      # only folders whose path contains this text
```

You can stop it with Ctrl+C and run it again: it picks up where it left off. At the end it prints `RIEPILOGO: verificati N / total` (verified N out of total).

## Paths to adapt

| What | Where | How to find it |
| --- | --- | --- |
| Original collection folder | `$Origine` (ps1) | Copy the path from Explorer's address bar, keep the double quotes |
| Clean copy folder | `$Dest` (ps1) and `ROOT` (py), they must match | Default is `Desktop\Amiibo_Clean`. If your Desktop is synced with OneDrive the real path is different, check it with `[Environment]::GetFolderPath('Desktop')` |
| Device path prefix | `$Prefix` (ps1) | The path shown at the top of the web page, for example `E:/amiibo/` |
| Folder on the device | `REMOTE` (py) | Same as above without the trailing slash: `E:/amiibo` |
| Folders to skip | `$ExcludeDirs` (ps1) | Top-level folders you do not want copied |
| Title abbreviations | `$Abbrev` (ps1) | Personal choice, edit or empty it |

## Good to know

- The device filesystem (SPIFFS) has no real folders. A folder only exists if it contains a `.folder` marker file, and listing a folder that does not exist returns "empty" instead of an error. The uploader checks the parent listing and creates the folder if it is missing. An early version of my script did not do this: the files were written but the folders did not show up.
- The uploader compares file name and size, not content. A file with the same size but different content is skipped.
- New files, or files with a different size, replace an existing file with the same name.
- If the device powers off during a transfer, turn it back on: the script keeps searching and resumes.
- Do not share key files or dumps of your collection. The scripts leave `key_retail.bin` out of the clean copy.

## Check before you run

Scripts that write to a device are worth reading first. Both are short. The PowerShell script only reads your original folder and writes the clean copy. The Python script only writes inside the device folder set in `REMOTE`. If you use an AI assistant to review them for your setup, the end of `README.md` has a ready-made prompt for that.

## Credits

The Bluetooth protocol comes from the official Pixl.js sources (release 2.16.0, `web/src/lib/pixl.proto.js` and the firmware). All credit for the device goes to its authors.
