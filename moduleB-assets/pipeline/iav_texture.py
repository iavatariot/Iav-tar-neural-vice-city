"""IAVAT@R Neural Vice City - Texture2D cotte UE 4.26 (GTA VC DE): lettura, DDS/PNG, reiniezione in-place.

Strategia del pilota: NON ricuocere con l'editor. Si sostituiscono i pixel nella stessa risoluzione,
nello stesso formato BC e con lo stesso numero di mip, quindi .uasset/.uexp/.ubulk mantengono layout
e dimensioni identici. Il motore custom GSG non vede differenze strutturali.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field

BULK_PAYLOAD_IN_SEPARATE_FILE = 0x0100   # BULKDATA_PayloadInSeperateFile
BULK_FORCE_INLINE = 0x0040               # BULKDATA_ForceInlinePayload
BULK_SIZE64 = 0x2000                     # BULKDATA_Size64Bit
BULK_UNUSED = 0x0020                     # BULKDATA_Unused (mip non serializzato)

# byte per blocco 4x4
BLOCK_BYTES = {'PF_DXT1': 8, 'PF_BC4': 8, 'PF_DXT3': 16, 'PF_DXT5': 16, 'PF_BC5': 16, 'PF_BC7': 16, 'PF_BC6H': 16}
FOURCC = {'PF_DXT1': b'DXT1', 'PF_DXT3': b'DXT3', 'PF_DXT5': b'DXT5', 'PF_BC4': b'ATI1', 'PF_BC5': b'ATI2'}
DXGI = {'PF_BC7': 98, 'PF_BC6H': 95}


@dataclass
class Mip:
    index: int
    flags: int
    size: int            # byte su disco
    offset: int          # offset nel .ubulk (se separato) o nel file
    inline_pos: int      # posizione dei dati nel .uexp se inline, altrimenti -1
    width: int
    height: int
    separate: bool


@dataclass
class TextureInfo:
    pixel_format: str
    width: int
    height: int
    num_mips: int
    first_mip: int
    mips: list = field(default_factory=list)


def mip_bytes(fmt: str, w: int, h: int) -> int:
    return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * BLOCK_BYTES[fmt]


def parse(uexp: bytes) -> TextureInfo:
    i = uexp.find(b'PF_')
    if i < 0:
        raise ValueError('pixel format non trovato: non e\' una Texture2D cotta?')
    slen = struct.unpack_from('<i', uexp, i - 4)[0]
    fmt = uexp[i:i + slen - 1].decode()
    w, h, packed = struct.unpack_from('<iii', uexp, i - 16)
    p = i + slen
    first_mip, num_mips = struct.unpack_from('<ii', uexp, p)
    p += 8
    info = TextureInfo(fmt, w, h, num_mips, first_mip)
    for k in range(num_mips):
        _cooked = struct.unpack_from('<i', uexp, p)[0]; p += 4
        flags = struct.unpack_from('<I', uexp, p)[0]; p += 4
        if flags & BULK_SIZE64:
            count, size = struct.unpack_from('<qq', uexp, p); p += 16
        else:
            count, size = struct.unpack_from('<ii', uexp, p); p += 8
        offset = struct.unpack_from('<q', uexp, p)[0]; p += 8
        separate = bool(flags & BULK_PAYLOAD_IN_SEPARATE_FILE)
        inline_pos = -1
        if not separate and not (flags & BULK_UNUSED):
            inline_pos = p
            p += size
        mw, mh, _mz = struct.unpack_from('<iii', uexp, p); p += 12
        info.mips.append(Mip(k, flags, size, offset, inline_pos, mw, mh, separate))
    return info


def mip_data(info: TextureInfo, uexp: bytes, ubulk: bytes | None, m: Mip) -> bytes:
    if m.separate:
        return ubulk[m.offset:m.offset + m.size]
    return uexp[m.inline_pos:m.inline_pos + m.size]


def to_dds(info: TextureInfo, uexp: bytes, ubulk: bytes | None) -> bytes:
    """DDS con tutta la catena mip (per ispezione e per i tool di conversione)."""
    fmt = info.pixel_format
    data = b''.join(mip_data(info, uexp, ubulk, m) for m in info.mips)
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000
    pitch = mip_bytes(fmt, info.width, info.height)
    if fmt in FOURCC:
        pf = struct.pack('<II4sIIIII', 32, 0x4, FOURCC[fmt], 0, 0, 0, 0, 0)
        ext = b''
    else:
        pf = struct.pack('<II4sIIIII', 32, 0x4, b'DX10', 0, 0, 0, 0, 0)
        ext = struct.pack('<IIIII', DXGI[fmt], 3, 0, 1, 0)
    hdr = struct.pack('<4sIIIIIII', b'DDS ', 124, flags, info.height, info.width, pitch, 0, len(info.mips))
    hdr += b'\0' * 44 + pf + struct.pack('<IIIII', 0x1000 | 0x400000 | 0x8, 0, 0, 0, 0)
    return hdr + ext + data


def inject(info: TextureInfo, uexp: bytes, ubulk: bytes | None, new_mips: list[bytes]) -> tuple[bytes, bytes | None]:
    """Sostituisce i dati dei mip con blocchi della STESSA dimensione. Restituisce (uexp, ubulk) nuovi."""
    if len(new_mips) != len(info.mips):
        raise ValueError(f'servono {len(info.mips)} mip, forniti {len(new_mips)}')
    ue = bytearray(uexp)
    ub = bytearray(ubulk) if ubulk is not None else None
    for m, data in zip(info.mips, new_mips):
        if len(data) != m.size:
            raise ValueError(f'mip {m.index}: {len(data)} byte, attesi {m.size} (stesso formato e risoluzione)')
        if m.separate:
            ub[m.offset:m.offset + m.size] = data
        else:
            ue[m.inline_pos:m.inline_pos + m.size] = data
    return bytes(ue), (bytes(ub) if ub is not None else None)


def effective(info: TextureInfo) -> TextureInfo:
    """Vista della texture a partire dal primo mip realmente presente (texture ridotte in cottura)."""
    if not info.mips or info.mips[0].width == info.width:
        return info
    m0 = info.mips[0]
    return TextureInfo(info.pixel_format, m0.width, m0.height, len(info.mips), 0, info.mips)


# ------------------------------------------------------------------ texture a risoluzione maggiore
MIP_ENTRY_FIXED = 4 + 4 + 4 + 4 + 8 + 12   # bCooked, flag, count, size, offset, w/h/d (size a 32 bit)


def _set_imported_size(uasset: bytes, uexp: bytes, w: int, h: int) -> bytes:
    """Aggiorna la proprieta' ImportedSize (IntPoint) se presente; il resto delle proprieta' resta invariato."""
    from iav_uasset import Package
    pkg = Package(uasset, uexp)
    if 'ImportedSize' not in pkg.names or 'IntPoint' not in pkg.names:
        return uexp
    key = struct.pack('<ii', pkg.names.index('ImportedSize'), 0)
    p = 0
    ue = bytearray(uexp)
    end = uexp.find(b'PF_')
    while True:
        p = uexp.find(key, p)
        if p < 0 or p > end:
            return bytes(ue)
        if struct.unpack_from('<ii', uexp, p + 24)[0] == pkg.names.index('IntPoint'):
            vpos = p + 8 + 8 + 8 + 8 + 16 + 1
            struct.pack_into('<ii', ue, vpos, w, h)
            return bytes(ue)
        p += 1


def rebuild(info: TextureInfo, uasset: bytes, uexp: bytes, ubulk: bytes | None,
            new_w: int, new_h: int, new_mips: list[bytes]) -> tuple[bytes, bytes, bytes | None]:
    """Riscrive la catena mip con una risoluzione diversa (tipicamente 2x).

    Layout cotto UE 4.26 (verificato su questa build):
      FName PixelFormat | int64 SkipOffset (assoluto, = inizio del FName 'None' finale)
      | SizeX SizeY Packed | FString PF_xxx | FirstMip NumMips | mip[] | bIsVirtual | FName None | tag
      mip = bCooked, BulkFlags, Count, Size, Offset(int64), [dati se inline], SizeX SizeY SizeZ
      Offset dei mip inline = posizione assoluta nel file uasset+uexp; dei mip separati = posizione nel .ubulk.
    Politica: gli ultimi K mip restano inline come nell'originale (K = numero originale di inline), gli altri
    vanno nel .ubulk, contigui. Aggiorna anche nel .uasset SerialSize dell'export e BulkDataStartOffset.
    """
    if info.first_mip != 0 or info.mips[0].width != info.width:
        raise ValueError('texture ridotta in cottura: rebuild non supportato')
    if any(m.flags & BULK_SIZE64 for m in info.mips):
        raise ValueError('mip con size a 64 bit: non supportato')
    inline_k = sum(1 for m in info.mips if not m.separate)
    sep_flags = next((m.flags for m in info.mips if m.separate), None)
    inl_flags = next((m.flags for m in info.mips if not m.separate), None)
    fmt = info.pixel_format
    dims = []
    w, h = new_w, new_h
    while True:
        dims.append((w, h))
        if w == 1 and h == 1:
            break
        w, h = max(1, w // 2), max(1, h // 2)
    if len(new_mips) != len(dims):
        raise ValueError(f'servono {len(dims)} mip per {new_w}x{new_h}, forniti {len(new_mips)}')
    for (w, h), d in zip(dims, new_mips):
        if len(d) != mip_bytes(fmt, w, h):
            raise ValueError(f'mip {w}x{h}: {len(d)} byte, attesi {mip_bytes(fmt, w, h)}')
    n = len(dims)
    if sep_flags is None:
        inline_k = n            # texture tutta inline: resta tutta inline
    if inl_flags is None:
        inline_k = 0

    i = uexp.find(b'PF_')
    slen = struct.unpack_from('<i', uexp, i - 4)[0]
    head = uexp[:i - 24]                       # fino a FName PixelFormat incluso
    last = info.mips[-1]
    if last.separate:
        raise ValueError('ultimo mip non inline: layout inatteso')
    tail = uexp[last.inline_pos + last.size + 12:]   # bIsVirtual + FName None + tag
    base = len(uasset)

    out = bytearray(head)
    skip_pos = len(out); out += b'\0' * 8
    out += struct.pack('<iii', new_w, new_h, struct.unpack_from('<i', uexp, i - 8)[0])
    out += uexp[i - 4:i + slen]
    out += struct.pack('<ii', 0, n)
    bulk = bytearray()
    for k, ((w, h), d) in enumerate(zip(dims, new_mips)):
        inline = k >= n - inline_k
        out += struct.pack('<i', 1)
        if inline:
            out += struct.pack('<Iii', inl_flags, len(d), len(d))
            data_pos = len(out) + 8
            out += struct.pack('<q', base + data_pos)
            out += d
        else:
            out += struct.pack('<Iii', sep_flags, len(d), len(d))
            out += struct.pack('<q', len(bulk))
            bulk += d
        out += struct.pack('<iii', max(4, w) if fmt in BLOCK_BYTES else w, max(4, h) if fmt in BLOCK_BYTES else h, 1)
    none_pos = len(out) + 4                    # dopo bIsVirtual
    out += tail
    struct.pack_into('<q', out, skip_pos, base + none_pos)
    new_uexp = _set_imported_size(uasset, bytes(out), new_w, new_h)

    ua = bytearray(uasset)
    old_ser, new_ser = len(uexp) - 4, len(new_uexp) - 4
    old_bulk, new_bulk = base + len(uexp) - 4, base + len(new_uexp) - 4
    hits = 0
    for j in range(0, len(ua) - 15):
        if struct.unpack_from('<qq', ua, j) == (old_ser, base):          # export: SerialSize, SerialOffset
            struct.pack_into('<q', ua, j, new_ser); hits += 1
    j = 0
    while True:
        j = bytes(ua).find(struct.pack('<q', old_bulk), j)
        if j < 0:
            break
        struct.pack_into('<q', ua, j, new_bulk); hits += 1; j += 8
    if hits != 2:
        raise ValueError(f'uasset: attesi 2 campi da aggiornare (SerialSize, BulkDataStartOffset), trovati {hits}')
    return bytes(ua), new_uexp, (bytes(bulk) if bulk else None)
