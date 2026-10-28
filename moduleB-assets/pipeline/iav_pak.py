"""IAVAT@R Neural Vice City - lettura/scrittura pak UE4 versione 11 (GTA Vice City DE).

Lettura: indice v11 (encoded entries + full directory index), compressione None/Zlib/Oodle.
Scrittura: pak v11 NON cifrato, voci non compresse o Zlib, con full directory index.

Oodle: si usa la oo2core_8_win64.dll gia' installata col gioco (Windows, ctypes). In alternativa,
per sviluppo su Linux, il pacchetto opzionale `pyooz` (GPLv3, NON incluso ne' ridistribuito).
"""
from __future__ import annotations

import hashlib
import io
import os
import struct
import sys
import zlib
from dataclasses import dataclass, field

PAK_MAGIC = 0x5A6F12E1
PAK_VERSION = 11  # PakFile_Version_Fnv64BugFix (UE 4.26)
COMPRESSION_SLOTS = 5
FOOTER_SIZE = 16 + 1 + 4 + 4 + 8 + 8 + 20 + 32 * COMPRESSION_SLOTS  # 221


# ----------------------------------------------------------------------------------------- Oodle
class OodleBackend:
    def __init__(self, game_root: str | None = None):
        self._fn = None
        self.name = None
        dll = None
        if game_root:
            cand = os.path.join(game_root, 'Engine', 'Binaries', 'ThirdParty', 'Oodle', 'Win64', 'oo2core_8_win64.dll')
            if os.path.isfile(cand):
                dll = cand
        if dll and sys.platform == 'win32':
            import ctypes
            lib = ctypes.WinDLL(dll)
            f = lib.OodleLZ_Decompress
            f.restype = ctypes.c_longlong
            f.argtypes = [ctypes.c_void_p, ctypes.c_longlong, ctypes.c_void_p, ctypes.c_longlong,
                          ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_longlong,
                          ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_longlong, ctypes.c_int]
            self._ct = ctypes
            self._fn = f
            self.name = 'oo2core (gioco)'
            return
        try:
            import ooz  # type: ignore  # pip install pyooz (opzionale, solo sviluppo)
            self._ooz = ooz
            self.name = 'pyooz (sviluppo)'
        except ImportError:
            pass

    @property
    def available(self) -> bool:
        return self.name is not None

    def decompress(self, data: bytes, out_size: int) -> bytes:
        if self._fn is not None:
            ct = self._ct
            src = ct.create_string_buffer(data, len(data))
            dst = ct.create_string_buffer(out_size)
            n = self._fn(src, len(data), dst, out_size, 1, 0, 0, None, 0, None, None, None, 0, 3)
            if n != out_size:
                raise IOError(f'OodleLZ_Decompress ha restituito {n}, attesi {out_size}')
            return dst.raw
        if self.name:
            out = self._ooz.decompress(data, out_size)
            if len(out) != out_size:
                raise IOError(f'ooz ha restituito {len(out)} byte, attesi {out_size}')
            return bytes(out)
        raise RuntimeError('Nessun decompressore Oodle disponibile (serve la DLL del gioco su Windows, o pyooz)')


# ----------------------------------------------------------------------------------------- lettura
class _R:
    def __init__(self, b: bytes, p: int = 0):
        self.b = b
        self.p = p

    def u(self, fmt: str):
        v = struct.unpack_from('<' + fmt, self.b, self.p)
        self.p += struct.calcsize('<' + fmt)
        return v if len(v) > 1 else v[0]

    def fstring(self) -> str:
        n = self.u('i')
        if n == 0:
            return ''
        if n > 0:
            v = self.b[self.p:self.p + n - 1].decode('latin1')
            self.p += n
            return v
        n = -n
        v = self.b[self.p:self.p + 2 * (n - 1)].decode('utf-16le')
        self.p += 2 * n
        return v


@dataclass
class PakEntry:
    path: str            # relativo al mount point
    offset: int
    usize: int
    csize: int
    method: str          # 'None' | 'Zlib' | 'Oodle' | ...
    encrypted: bool
    block_size: int
    blocks: list = field(default_factory=list)  # [(start, end)] relativi all'inizio dell'header


def _entry_header_size(compressed: bool, nblocks: int) -> int:
    return 8 + 8 + 8 + 4 + 20 + ((4 + 16 * nblocks) if compressed else 0) + 1 + 4


class PakReader:
    def __init__(self, path: str, oodle: OodleBackend | None = None):
        self.path = path
        self.fh = open(path, 'rb')
        self.oodle = oodle
        size = os.path.getsize(path)
        self.fh.seek(size - FOOTER_SIZE)
        foot = self.fh.read(FOOTER_SIZE)
        magic, self.version, ioff, isz = struct.unpack_from('<IIQQ', foot, 17)
        if magic != PAK_MAGIC:
            raise ValueError('magic pak non trovato')
        if foot[16]:
            raise ValueError('indice cifrato: non supportato (e fuori dai vincoli del progetto)')
        if self.version != 11:
            raise ValueError(f'versione pak {self.version} non supportata')
        self.methods = [foot[61 + 32 * k:61 + 32 * (k + 1)].split(b'\0')[0].decode() for k in range(COMPRESSION_SLOTS)]
        r = _R(self._read(ioff, isz))
        self.mount = r.fstring()
        self.count = r.u('i')
        r.u('Q')
        if r.u('I'):
            r.u('qq'); r.p += 20
        has_fdi = r.u('I')
        fdi_off = fdi_size = None
        if has_fdi:
            fdi_off, fdi_size = r.u('qq'); r.p += 20
        enc_size = r.u('i')
        self._enc = r.b[r.p:r.p + enc_size]
        r.p += enc_size
        if r.u('i'):
            raise ValueError('voci non codificate presenti: non supportate')
        if not has_fdi:
            raise ValueError('full directory index assente')
        d = _R(self._read(fdi_off, fdi_size))
        self.index: dict[str, int] = {}
        for _ in range(d.u('i')):
            dname = d.fstring()
            for _ in range(d.u('i')):
                fname = d.fstring()
                self.index[dname + fname] = d.u('i')

    def _read(self, off: int, n: int) -> bytes:
        self.fh.seek(off)
        return self.fh.read(n)

    def entry(self, rel: str) -> PakEntry:
        if rel.startswith(self.mount):
            rel = rel[len(self.mount):]
        eo = self.index[rel]
        r = _R(self._enc, eo)
        v = r.u('I')
        packed_bs = v & 0x3F
        nblk = (v >> 6) & 0xFFFF
        enc = bool((v >> 22) & 1)
        cm = (v >> 23) & 0x3F
        off = r.u('I') if v & (1 << 31) else r.u('Q')
        usz = r.u('I') if v & (1 << 30) else r.u('Q')
        csz = (r.u('I') if v & (1 << 29) else r.u('Q')) if cm else usz
        # UE 4.26: nessun block size esplicito; se la voce e' < 64 KiB il blocco e' l'intera voce
        bs = (usz if usz < 65536 else packed_bs << 11) if nblk else 0
        e = PakEntry(rel, off, usz, csz, self.methods[cm - 1] if cm else 'None', enc, bs)
        if cm:
            hs = _entry_header_size(True, nblk)
            if nblk == 1:
                e.blocks = [(hs, hs + csz)]
            else:
                pos = hs
                for _ in range(nblk):
                    sz = r.u('I')
                    e.blocks.append((pos, pos + sz))
                    pos += sz
        return e

    def read(self, rel: str) -> bytes:
        e = self.entry(rel)
        if e.encrypted:
            raise ValueError(f'{rel}: voce cifrata')
        if e.method == 'None':
            return self._read(e.offset + _entry_header_size(False, 0), e.usize)
        out = bytearray()
        remaining = e.usize
        for (s, t) in e.blocks:
            raw = self._read(e.offset + s, t - s)
            # blocco singolo: contiene l'intera voce (il block size codificato e' arrotondato)
            n = remaining if (e.block_size == 0 or len(e.blocks) == 1) else min(e.block_size, remaining)
            if e.method == 'Zlib':
                out += zlib.decompress(raw)
            elif e.method == 'Oodle':
                if not self.oodle or not self.oodle.available:
                    raise RuntimeError('serve Oodle per ' + rel)
                out += self.oodle.decompress(raw, n)
            else:
                raise ValueError(f'compressione {e.method} non supportata')
            remaining -= n
        if len(out) != e.usize:
            raise IOError(f'{rel}: {len(out)} byte, attesi {e.usize}')
        return bytes(out)


# ----------------------------------------------------------------------------------------- scrittura
def path_hash(rel: str, seed: int) -> int:
    h = (0xCBF29CE484222325 + seed) & 0xFFFFFFFFFFFFFFFF
    for c in rel.lower().encode('utf-16le'):
        h ^= c
        h = (h * 0x00000100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def _fstring(s: str) -> bytes:
    if not s:
        return struct.pack('<i', 0)
    try:
        b = s.encode('ascii') + b'\0'
        return struct.pack('<i', len(b)) + b
    except UnicodeEncodeError:
        b = s.encode('utf-16le') + b'\0\0'
        return struct.pack('<i', -(len(b) // 2)) + b


def write_pak(out_path: str, files: dict[str, bytes], mount: str = '../../../', compress: bool = True,
              block_size: int = 0x10000, level: int = 9) -> dict:
    """Scrive un pak v11 NON cifrato. `files`: percorso relativo al mount -> contenuto.
    Con compress=True ogni voce e' compressa in blocchi Zlib da 64 KiB (offset relativi alla voce, v11);
    se la compressione non conviene la voce resta non compressa. Indice: path hash index + full directory index."""
    data = io.BytesIO()
    encoded = io.BytesIO()
    offsets: dict[str, int] = {}
    stats = {'usize': 0, 'csize': 0}
    for rel in sorted(files):
        content = files[rel]
        off = data.tell()
        usize = len(content)
        chunks = []
        if compress and usize > 0:
            for i in range(0, usize, block_size):
                chunks.append(zlib.compress(content[i:i + block_size], level))
            if sum(len(c) for c in chunks) >= usize:
                chunks = []
        stats['usize'] += usize
        if chunks:
            nblk = len(chunks)
            hdr_size = _entry_header_size(True, nblk)
            csize = sum(len(c) for c in chunks)
            blocks, pos = [], hdr_size
            for c in chunks:
                blocks.append((pos, pos + len(c)))
                pos += len(c)
            header = bytearray()
            header += struct.pack('<qqqi', 0, csize, usize, 1)
            header += hashlib.sha1(b''.join(chunks)).digest()
            header += struct.pack('<i', nblk)
            for b0, b1 in blocks:
                header += struct.pack('<qq', b0, b1)
            header += struct.pack('<BI', 0, block_size if nblk > 1 else usize)
            assert len(header) == hdr_size
            data.write(header)
            for c in chunks:
                data.write(c)
            stats['csize'] += csize
            # voce codificata come FPakFile::EncodePakEntry di UE 4.26: block size in 6 bit (>>11),
            # mai un valore esplicito (il formato 4.26 non lo prevede: il motore lo leggerebbe come offset)
            bs_packed = ((block_size if nblk > 1 else usize) >> 11) & 0x3F
            flags = bs_packed | ((nblk & 0xFFFF) << 6) | (1 << 23)  # metodo 1 = slot 0 (Zlib)
            flags |= (1 << 31) if off <= 0xFFFFFFFF else 0
            flags |= (1 << 30) if usize <= 0xFFFFFFFF else 0
            flags |= (1 << 29) if csize <= 0xFFFFFFFF else 0
            enc_off = encoded.tell()
            encoded.write(struct.pack('<I', flags))
            encoded.write(struct.pack('<I' if off <= 0xFFFFFFFF else '<Q', off))
            encoded.write(struct.pack('<I' if usize <= 0xFFFFFFFF else '<Q', usize))
            encoded.write(struct.pack('<I' if csize <= 0xFFFFFFFF else '<Q', csize))
            if nblk > 1:
                for c in chunks:
                    encoded.write(struct.pack('<I', len(c)))
        else:
            data.write(struct.pack('<qqqi', 0, usize, usize, 0) + hashlib.sha1(content).digest() + struct.pack('<BI', 0, 0))
            data.write(content)
            stats['csize'] += usize
            enc_off = encoded.tell()
            flags = (1 << 31 if off <= 0xFFFFFFFF else 0) | (1 << 30 if usize <= 0xFFFFFFFF else 0)
            encoded.write(struct.pack('<I', flags))
            encoded.write(struct.pack('<I' if off <= 0xFFFFFFFF else '<Q', off))
            encoded.write(struct.pack('<I' if usize <= 0xFFFFFFFF else '<Q', usize))
        offsets[rel] = enc_off
    # full directory index: radice "/" e ogni directory intermedia, come nei pak del gioco
    dirs: dict[str, list] = {'/': []}
    for rel in sorted(files):
        d, f = rel.rsplit('/', 1) if '/' in rel else ('', rel)
        parts = d.split('/') if d else []
        for i in range(1, len(parts) + 1):
            dirs.setdefault('/'.join(parts[:i]) + '/', [])
        dirs[(d + '/') if d else '/'].append((f, offsets[rel]))
    fdi = io.BytesIO()
    fdi.write(struct.pack('<i', len(dirs)))
    for dname in sorted(dirs):
        fdi.write(_fstring(dname))
        fdi.write(struct.pack('<i', len(dirs[dname])))
        for fname, eo in dirs[dname]:
            fdi.write(_fstring(fname) + struct.pack('<i', eo))
    # path hash index: FNV-64 del percorso minuscolo in UTF-16LE, base FNV + seed (verificato su pakchunk1)
    seed = zlib.crc32(os.path.basename(out_path).lower().encode('utf-16le')) & 0xFFFFFFFF
    phi = io.BytesIO()
    phi.write(struct.pack('<i', len(files)))
    for rel in sorted(files):
        phi.write(struct.pack('<Qi', path_hash(rel, seed), offsets[rel]))
    phi.write(struct.pack('<i', 0))  # pruned directory index vuoto
    data_bytes = data.getvalue()
    fdi_bytes = fdi.getvalue()
    phi_bytes = phi.getvalue()
    enc_bytes = encoded.getvalue()

    index_off = len(data_bytes)

    def primary(phi_off: int, fdi_off: int) -> bytes:
        b = io.BytesIO()
        b.write(_fstring(mount))
        b.write(struct.pack('<iQ', len(files), seed))
        b.write(struct.pack('<Iqq', 1, phi_off, len(phi_bytes)) + hashlib.sha1(phi_bytes).digest())
        b.write(struct.pack('<Iqq', 1, fdi_off, len(fdi_bytes)) + hashlib.sha1(fdi_bytes).digest())
        b.write(struct.pack('<i', len(enc_bytes)) + enc_bytes)
        b.write(struct.pack('<i', 0))
        return b.getvalue()
    plen = len(primary(0, 0))
    phi_off = index_off + plen
    fdi_off = phi_off + len(phi_bytes)
    p = primary(phi_off, fdi_off)
    assert len(p) == plen
    footer = (b'\0' * 16 + b'\0' + struct.pack('<IIQQ', PAK_MAGIC, PAK_VERSION, index_off, len(p))
              + hashlib.sha1(p).digest() + b'Zlib'.ljust(32, b'\0') + b'\0' * (32 * (COMPRESSION_SLOTS - 1)))
    assert len(footer) == FOOTER_SIZE
    with open(out_path, 'wb') as fh:
        fh.write(data_bytes)
        fh.write(p)
        fh.write(phi_bytes)
        fh.write(fdi_bytes)
        fh.write(footer)
    return {'files': len(files), 'bytes': os.path.getsize(out_path), 'usize': stats['usize'], 'csize': stats['csize']}
