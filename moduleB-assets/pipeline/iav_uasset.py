"""IAVAT@R Neural Vice City - lettura minima di package UE 4.26 cotti (summary, name map, import, export)
e delle proprieta' taggate di un MaterialInstanceConstant (parametri texture/scalari/vettori)."""
from __future__ import annotations

import struct


NATIVE_PARAM_STRUCTS = {'ScalarParameterValue': 'scalar', 'TextureParameterValue': 'texture', 'VectorParameterValue': 'vector'}


class _R:
    def __init__(self, b: bytes, p: int = 0):
        self.b, self.p = b, p

    def u(self, fmt):
        v = struct.unpack_from('<' + fmt, self.b, self.p)
        self.p += struct.calcsize('<' + fmt)
        return v if len(v) > 1 else v[0]

    def fs(self):
        n = self.u('i')
        if n == 0:
            return ''
        if n > 0:
            s = self.b[self.p:self.p + n - 1].decode('latin1'); self.p += n; return s
        n = -n
        s = self.b[self.p:self.p + 2 * (n - 1)].decode('utf-16le'); self.p += 2 * n; return s


class Package:
    def __init__(self, uasset: bytes, uexp: bytes):
        r = _R(uasset)
        if r.u('I') != 0x9E2A83C1:
            raise ValueError('tag package non valido')
        legacy = r.u('i')
        if legacy != -4:
            r.u('i')  # LegacyUE3Version
        self.ue4ver, self.licensee = r.u('ii')
        ncv = r.u('i'); r.p += ncv * 20  # custom versions
        self.total_header = r.u('i')
        r.fs()  # FolderName
        self.flags = r.u('I')
        name_count, name_off = r.u('ii')
        if self.ue4ver >= 516:  # localization id (non nei cooked editor-only, ma il campo c'e')
            pass
        r.u('ii')  # GatherableText count/offset
        export_count, export_off, import_count, import_off = r.u('iiii')
        self.names = []
        n = _R(uasset, name_off)
        for _ in range(name_count):
            self.names.append(n.fs()); n.u('HH')
        self.imports = []
        m = _R(uasset, import_off)
        for _ in range(import_count):
            cpkg = self.name(m.u('ii')); cls = self.name(m.u('ii')); outer = m.u('i'); obj = self.name(m.u('ii'))
            self.imports.append({'class_package': cpkg, 'class': cls, 'outer': outer, 'name': obj})
        self.uexp = uexp
        self.header_size = self.total_header

    def name(self, pair):
        idx, num = pair
        s = self.names[idx]
        return s if num == 0 else f'{s}_{num - 1}'

    def object_path(self, index: int) -> str:
        if index < 0:
            imp = self.imports[-index - 1]
            if imp['outer']:
                return self.object_path(imp['outer']) + '.' + imp['name']
            return imp['name']
        return f'export:{index}'

    # --- proprieta' taggate (sottoinsieme sufficiente per i MaterialInstanceConstant) ---
    def properties(self, data: bytes, start: int = 0):
        r = _R(data, start)
        return self._props(r)

    def _props(self, r):
        out = {}
        while True:
            pname = self.name(r.u('ii'))
            if pname == 'None':
                return out
            ptype = self.name(r.u('ii'))
            size, aidx = r.u('ii')
            extra = {}
            if ptype == 'StructProperty':
                extra['struct'] = self.name(r.u('ii')); r.p += 16
            elif ptype in ('ByteProperty', 'EnumProperty'):
                extra['enum'] = self.name(r.u('ii'))
            elif ptype == 'ArrayProperty':
                extra['inner'] = self.name(r.u('ii'))
            elif ptype == 'BoolProperty':
                extra['bool'] = r.u('B')
            has_guid = r.u('B')
            if has_guid:
                r.p += 16
            vstart = r.p
            val = self._value(r, ptype, size, extra)
            r.p = vstart + size
            out.setdefault(pname, []).append(val) if aidx else out.__setitem__(pname, val)

    def _value(self, r, ptype, size, extra):
        if ptype == 'ObjectProperty':
            return self.object_path(r.u('i'))
        if ptype == 'FloatProperty':
            return r.u('f')
        if ptype in ('IntProperty',):
            return r.u('i')
        if ptype == 'BoolProperty':
            return bool(extra['bool'])
        if ptype == 'NameProperty':
            return self.name(r.u('ii'))
        if ptype in ('ByteProperty', 'EnumProperty'):
            return self.name(r.u('ii')) if extra['enum'] != 'None' else r.u('B')
        if ptype == 'StructProperty':
            st = extra['struct']
            if st == 'LinearColor':
                return r.u('ffff')
            if st == 'Vector':
                return r.u('fff')
            if st == 'Guid':
                return r.b[r.p:r.p + 16].hex()
            return self._props(r)
        if ptype == 'ArrayProperty':
            n = r.u('i')
            inner = extra['inner']
            if inner == 'StructProperty':
                # tag dell'elemento
                self.name(r.u('ii')); self.name(r.u('ii')); r.u('ii'); sname = self.name(r.u('ii')); r.p += 16; r.u('B')
                if sname in NATIVE_PARAM_STRUCTS:
                    # in questa build i parametri dei materiali sono serializzati in binario, senza tag:
                    # FName(8) + Association(1) + Index(4) + valore + ExpressionGUID(16)
                    out = []
                    for _ in range(n):
                        name = self.name(r.u('ii')); assoc = r.u('B'); index = r.u('i')
                        kind = NATIVE_PARAM_STRUCTS[sname]
                        if kind == 'scalar':
                            val = r.u('f')
                        elif kind == 'texture':
                            val = self.object_path(r.u('i'))
                        else:
                            val = r.u('ffff')
                        r.p += 16
                        out.append({'ParameterInfo': {'Name': name, 'Association': assoc, 'Index': index}, 'ParameterValue': val})
                    return out
                try:
                    return [self._props(r) for _ in range(n)]
                except (IndexError, struct.error, UnicodeDecodeError):
                    return f'<array {sname} x{n} (non interpretato)>'
            if inner == 'ObjectProperty':
                return [self.object_path(r.u('i')) for _ in range(n)]
            return f'<array {inner} x{n}>'
        return f'<{ptype} {size}B>'


def material_parameters(uasset: bytes, uexp: bytes) -> dict:
    pkg = Package(uasset, uexp)
    props = pkg.properties(uexp, 0)
    res = {'parent': props.get('Parent'), 'textures': {}, 'scalars': {}, 'vectors': {}}
    for t in props.get('TextureParameterValues', []) or []:
        res['textures'][t['ParameterInfo']['Name']] = t.get('ParameterValue')
    for s in props.get('ScalarParameterValues', []) or []:
        res['scalars'][s['ParameterInfo']['Name']] = s.get('ParameterValue')
    for v in props.get('VectorParameterValues', []) or []:
        res['vectors'][v['ParameterInfo']['Name']] = v.get('ParameterValue')
    return res
