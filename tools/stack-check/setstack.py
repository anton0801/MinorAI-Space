# Sets the main thread stack size (LC_MAIN) of a built simulator app; re-sign with `codesign -f -s -` after.
import struct, sys
path, size = sys.argv[1], int(sys.argv[2], 0)
data = bytearray(open(path, 'rb').read())
magic, cpu, sub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from('<IiiIIIII', data, 0)
assert magic == 0xfeedfacf, hex(magic)
off = 32
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', data, off)
    if cmd == 0x80000028:
        entry, old = struct.unpack_from('<QQ', data, off + 8)
        struct.pack_into('<Q', data, off + 16, size)
        open(path, 'wb').write(data)
        print('stacksize', old, '->', size)
        break
    off += cmdsize
else:
    sys.exit('no LC_MAIN')
