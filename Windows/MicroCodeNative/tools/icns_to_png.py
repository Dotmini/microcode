"""Extract the largest PNG image from an Apple .icns file (stdlib only)."""
import struct, sys
data = open(sys.argv[1], "rb").read()
assert data[:4] == b"icns", "not an icns file"
pos, best = 8, None
while pos + 8 <= len(data):
    typ, ln = data[pos:pos + 4], struct.unpack(">I", data[pos + 4:pos + 8])[0]
    body = data[pos + 8:pos + ln]
    if body[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", body[16:24])
        if best is None or w > best[0]:
            best = (w, typ.decode("latin1"), body)
    if ln < 8: break
    pos += ln
open(sys.argv[2], "wb").write(best[2])
print("extracted", best[1], best[0], "px")
