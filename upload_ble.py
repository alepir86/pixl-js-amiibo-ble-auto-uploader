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
