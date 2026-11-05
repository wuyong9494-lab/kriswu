"""Read the supplied SC 5/6 data without running client code.

The format is documented by SC Workshop's MIT-licensed SupercellFlash schemas
and readers. See source_flash_LICENSE.txt. Unknown compressed encodings fail
explicitly; they are never replaced by identity matrices or empty frames.
Only the selected export's reachable data is emitted by the adapter.
"""
from __future__ import annotations

import hashlib
import struct
from pathlib import Path

import numpy as np
import zstandard


class FormatError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise FormatError(message)


def unpack(data, offset, fmt):
    fmt = '<' + fmt
    require(0 <= offset <= len(data) - struct.calcsize(fmt), 'Binary field outside source buffer')
    return struct.unpack_from(fmt, data, offset)


class Table:
    """Small bounded FlatBuffer reader, with no generated or executable input."""
    def __init__(self, data, pos=None):
        self.data = data
        self.pos = unpack(data, 0, 'I')[0] if pos is None else pos
        self.vtable = self.pos - unpack(data, self.pos, 'i')[0]
        self.vsize = unpack(data, self.vtable, 'H')[0]
        require(self.vsize >= 4 and self.vtable + self.vsize <= len(data), 'Invalid vtable')

    def field(self, slot):
        offset = 4 + slot * 2
        if offset >= self.vsize:
            return None
        value = unpack(self.data, self.vtable + offset, 'H')[0]
        return self.pos + value if value else None

    def scalar(self, slot, fmt='I', default=0):
        pos = self.field(slot)
        return default if pos is None else unpack(self.data, pos, fmt)[0]

    def vector(self, slot, stride=1):
        pos = self.field(slot)
        if pos is None:
            return (0, 0)
        pos += unpack(self.data, pos, 'I')[0]
        count = unpack(self.data, pos, 'I')[0]
        require(count <= 100_000_000 and pos + 4 + count * stride <= len(self.data), 'Invalid vector')
        return pos + 4, count

    def array(self, slot, fmt):
        pos, count = self.vector(slot, struct.calcsize('<' + fmt))
        return [unpack(self.data, pos + i * struct.calcsize('<' + fmt), fmt) for i in range(count)]

    def values(self, slot, fmt='I'):
        return [v[0] for v in self.array(slot, fmt)]

    def tables(self, slot):
        pos, count = self.vector(slot, 4)
        return [Table(self.data, pos + 4*i + unpack(self.data, pos + 4*i, 'I')[0]) for i in range(count)]

    def string_at(self, pos):
        pos += unpack(self.data, pos, 'I')[0]
        count = unpack(self.data, pos, 'I')[0]
        require(count <= 1_048_576 and pos + 4 + count <= len(self.data), 'Invalid string')
        return self.data[pos+4:pos+4+count].decode('utf-8')

    def string(self, slot):
        pos = self.field(slot)
        return self.string_at(pos) if pos is not None else ''

    def blob(self, slot):
        pos, count = self.vector(slot)
        return self.data[pos:pos+count]

    def table(self, slot):
        pos = self.field(slot)
        require(pos is not None, 'Missing required table')
        return Table(self.data, pos + unpack(self.data, pos, 'I')[0])


def decompress(data, limit=256*1024*1024):
    require(0 < limit <= 256*1024*1024, 'Decompression size exceeds budget')
    result = zstandard.ZstdDecompressor().decompress(data, max_output_size=limit)
    require(len(result) <= limit, 'Decompression exceeded budget')
    return result


class SourceFlash:
    def __init__(self, path):
        self.path = Path(path)
        require(self.path.stat().st_size <= 256*1024*1024, 'Source SC exceeds budget')
        raw = self.path.read_bytes()
        require(raw[:2] == b'SC', 'Not an SC container')
        self.sha256 = hashlib.sha256(raw).hexdigest()
        self.version = unpack(raw, 2, 'I')[0]
        require(self.version in (5, 6), 'Unsupported SC version')
        header_pos = 6
        if self.version == 6:
            require(unpack(raw, 6, 'H')[0] == 0, 'Unknown SC6 header flags')
            header_pos += 2
        header_size = unpack(raw, header_pos, 'I')[0]
        require(0 < header_size <= 16*1024*1024, 'Invalid descriptor size')
        comp_pos = header_pos + 4 + header_size
        header = Table(raw[header_pos+4:comp_pos])
        comp_size = header.scalar(11) or len(raw)-comp_pos
        require(comp_pos+comp_size <= len(raw), 'Truncated SC payload')
        data = decompress(raw[comp_pos:comp_pos+comp_size])

        def chunk(offset):
            size = unpack(data, offset, 'I')[0]
            require(size > 0 and offset+4+size <= len(data), 'Invalid SC chunk')
            return Table(data[offset+4:offset+4+size]), offset+4+size

        storage, _ = chunk(0)
        pos, count = storage.vector(0, 4)
        self.strings = [storage.string_at(pos+4*i) for i in range(count)]
        self.rectangles = storage.array(3, '4f')
        points = storage.blob(5)
        require(len(points) % 12 == 0, 'Invalid vertex stream')
        self.vertices = list(struct.iter_unpack('<ffHH', points))
        pos, count = storage.vector(4, 2)
        elements = np.frombuffer(storage.data, dtype='<u2', offset=pos, count=count)
        require(len(elements) % 3 == 0, 'Invalid frame element stream')
        self.banks = {}
        ext_size = header.scalar(12)
        if ext_size:
            ext = raw[comp_pos+comp_size:comp_pos+comp_size+ext_size]
            require(len(ext) == ext_size, 'Truncated external bank stream')
            size = unpack(ext, 0, 'I')[0]
            for bank in Table(ext[4:4+size]).tables(0):
                bpos = 4 + size + bank.scalar(1)
                buffer = decompress(ext[bpos:bpos+bank.scalar(2)], bank.scalar(3))
                require(len(buffer) == bank.scalar(3), 'Bank length mismatch')
                floats, shorts, blocks = bank.scalar(7), bank.scalar(6), bank.scalar(4)
                require(floats+shorts <= 65536, 'Matrix bank exceeds index range')
                # These are all uncompressed in the supplied v69 UI. A source
                # with delta blocks must get a real codec, never a silent skip.
                require(blocks*16 <= floats+shorts, 'Delta-compressed matrix bank needs a codec')
                f = np.frombuffer(buffer, dtype='<f4', count=floats*6).reshape(-1, 6).astype(float)
                short_pos = floats*24 + blocks*4
                s = np.frombuffer(buffer, dtype='<i2', count=shorts*6, offset=short_pos).reshape(-1, 6)
                s = s / np.array([1024,1024,1024,1024,20,20])
                color_pos = short_pos + bank.scalar(5)*2
                colors = np.frombuffer(buffer, dtype='u1', count=bank.scalar(8)*7, offset=color_pos).reshape(-1,7)
                index = bank.scalar(0)
                require(index not in self.banks, 'Duplicate matrix bank')
                self.banks[index] = (np.concatenate([f,s]), colors, buffer[bank.scalar(9):bank.scalar(9)+bank.scalar(10)])
        for index, bank in enumerate([] if ext_size else storage.tables(6)):
            require(index not in self.banks, 'Conflicting internal and external bank')
            matrices = bank.array(0, '6f')
            if not matrices:
                scale = {2:20, 3:1024}.get(header.scalar(1), 1)
                translation = {2:20, 3:1024}.get(header.scalar(0), 1)
                matrices = [np.array(m) / [scale,scale,scale,scale,translation,translation] for m in bank.array(2,'6h')]
            self.banks[index] = (np.array(matrices), np.array(bank.array(1,'7B')), b'')

        exports, pos = chunk(header.scalar(8))
        ids, names = exports.values(0,'H'), exports.values(1)
        require(len(ids) == len(names), 'Export vector mismatch')
        self.exports = {self.string(name): oid for oid, name in zip(ids, names)}
        require(len(self.exports) == len(ids), 'Duplicate export name')
        self.objects = {}
        text, pos = chunk(pos)
        for value in text.array(0, 'HHIhhhhIIIIBBBBi'):
            oid, _, font, left, top, right, bottom, color, outline, label, typography, style, align, size, _, angle = value
            self.add({'id': oid, 'commands': [], 'textField': {
                'fontName': self.string(font), 'text': self.string(label), 'typography': self.string(typography),
                'left':left, 'top':top, 'right':right, 'bottom':bottom, 'fontColor':color,
                'outlineColor':outline, 'styles':style, 'align':align, 'fontSize':size, 'outlineAngle':angle}})
        shapes, pos = chunk(pos)
        for shape in shapes.tables(0):
            commands = []
            for _, texture, count, offset in shape.array(1,'4I'):
                require(3 <= count <= 8192 and offset+count <= len(self.vertices), 'Invalid shape vertices')
                commands.append({'textureIndex':texture, 'vertices':self.vertices[offset:offset+count]})
            self.add({'id':shape.scalar(0,'H'), 'commands':commands})
        clips, pos = chunk(pos)
        for clip in clips.tables(0):
            oid = clip.scalar(0,'H')
            children = clip.values(5,'H')
            names, blends = clip.values(6), clip.values(7,'B')
            require(len(names) in (0,len(children)) and len(blends) in (0,len(children)), 'Child vector mismatch')
            counts_labels = clip.array(8,'II')
            if not counts_labels and self.version == 5:
                counts_labels = [(x,0) for x in clip.values(12,'H')]
            require(len(counts_labels) == clip.scalar(3,'H'), 'Clip frame count mismatch')
            offset = clip.scalar(9, default=None)
            require(offset is not None, 'Compressed clip stream needs a codec')
            bank_index = clip.scalar(10)
            bank = self.banks.get(bank_index)
            require(bank is not None, 'Missing clip matrix bank')
            frames, labels = [], []
            for count, label in counts_labels:
                require(offset+count*3 <= len(elements), 'Frame outside element stream')
                refs = elements[offset:offset+count*3].reshape(-1,3)
                offset += count*3
                for child, matrix, color in refs:
                    require(child < len(children), 'Invalid child index')
                    require(matrix == 65535 or matrix < len(bank[0]), 'Invalid matrix index')
                    require(color == 65535 or color < len(bank[1]), 'Invalid color index')
                rows = refs.astype(int).tolist()
                if frames and frames[-1]['elements'] == rows:
                    frames[-1]['repeat'] += 1
                else:
                    frames.append({'repeat':1, 'elements':rows})
                labels.append(self.string(label))
            item = {'id':oid, 'commands':[], 'fps':clip.scalar(2,'B'), 'frameCount':len(counts_labels),
                'children':[{'objectID':cid, 'name':self.string(names[i]) if names else '',
                             'blendMode':blends[i] if blends else 0} for i,cid in enumerate(children)],
                'frames':frames, 'frameLabels':labels, '_bank':bank_index}
            grid = clip.scalar(11, default=None)
            if grid is not None:
                require(grid < len(self.rectangles), 'Invalid scaling grid')
                item['scalingGrid'] = dict(zip(['left','top','right','bottom'],self.rectangles[grid]))
            self.add(item)
        modifiers, pos = chunk(pos)
        for oid, kind in modifiers.array(0,'HBx'):
            self.add({'id':oid, 'commands':[], 'modifier':kind})
        textures, pos = chunk(pos)
        self.textures = []
        for pair in textures.tables(0):
            texture = pair.table(1)
            self.textures.append({'width':texture.scalar(2,'H'), 'height':texture.scalar(3,'H'),
                'format':texture.scalar(0,'B'), 'pixelType':texture.scalar(1,'B'),
                'external':texture.string(5), 'data':texture.blob(4)})

    def add(self, item):
        require(item['id'] not in self.objects, 'Duplicate object ID')
        self.objects[item['id']] = item

    def string(self, index):
        require(0 <= index < len(self.strings), 'String reference out of bounds')
        # References are zero-based, including the empty string at index zero.
        return self.strings[index]

    def reachable(self, exports):
        visited = set()
        def walk(oid, stack):
            require(oid in self.objects and oid not in stack and len(stack)<48, 'Missing/cyclic display object')
            if oid in visited:
                return
            visited.add(oid)
            for child in self.objects[oid].get('children',[]):
                walk(child['objectID'],stack|{oid})
        for name in exports:
            require(name in self.exports, 'Unknown export: '+name)
            walk(self.exports[name],set())
        return visited
