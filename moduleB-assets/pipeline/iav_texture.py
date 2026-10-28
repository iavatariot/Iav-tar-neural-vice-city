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
