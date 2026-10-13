"""SND-13: the .lbv container and Ogg Opus plumbing.

A character line is stored as .lbv: a small header, then 20 ms Opus packets, so the client plays it
through SND-07's decoder and concealment exactly as it plays live voice.

    magic   b"LBV1"
    u16     pre_skip     (samples at 48 kHz the decoder drops first, from OpusHead)
    u32     samples      (the line's true length at 48 kHz)
    u32     frames       (packets that follow; each decodes to 960 samples)
    frames x (u16 length, length bytes)

All little-endian. ffmpeg's libopus writes the packets into Ogg; `packets_from_ogg` lifts them out,
and `ogg_from_lbv` wraps them back (with the same pre-skip and an end granule that trims the tail)
so ffmpeg can decode a file to prove its length and loudness.
"""
import struct

MAGIC = b"LBV1"
FRAME_SAMPLES = 960  # 20 ms at 48 kHz


def write_lbv(pre_skip, samples, packets):
    out = bytearray(MAGIC)
    out += struct.pack("<HII", pre_skip, samples, len(packets))
    for p in packets:
        out += struct.pack("<H", len(p)) + p
    return bytes(out)


def read_lbv(data):
    """(pre_skip, samples, packets); raises ValueError on a malformed file."""
    if data[:4] != MAGIC or len(data) < 14:
        raise ValueError("not an LBV1 file")
    pre_skip, samples, frames = struct.unpack_from("<HII", data, 4)
    pos = 14
    packets = []
    for _ in range(frames):
        if pos + 2 > len(data):
            raise ValueError("truncated")
        (n,) = struct.unpack_from("<H", data, pos)
        pos += 2
        if pos + n > len(data):
            raise ValueError("truncated")
        packets.append(bytes(data[pos:pos + n]))
        pos += n
    if pos != len(data):
        raise ValueError("trailing bytes")
    return pre_skip, samples, packets


def _pages(data):
    pos = 0
    while pos < len(data):
        if data[pos:pos + 4] != b"OggS":
            raise ValueError("bad Ogg page at %d" % pos)
        flags = data[pos + 5]
        granule = struct.unpack_from("<q", data, pos + 6)[0]
        nseg = data[pos + 26]
        lacing = data[pos + 27:pos + 27 + nseg]
        body = pos + 27 + nseg
        yield flags, granule, lacing, data[body:body + sum(lacing)]
        pos = body + sum(lacing)


def packets_from_ogg(data):
    """(pre_skip, final granule, [packets]) from an Ogg Opus file: OpusHead and OpusTags dropped."""
    packets, cur = [], bytearray()
    last_granule = 0
    for _flags, granule, lacing, body in _pages(data):
        off = 0
        for seg in lacing:
            cur += body[off:off + seg]
            off += seg
            if seg < 255:
                packets.append(bytes(cur))
                cur = bytearray()
        if granule >= 0:
            last_granule = granule
    if not packets or not packets[0].startswith(b"OpusHead"):
        raise ValueError("no OpusHead")
    pre_skip = struct.unpack_from("<H", packets[0], 10)[0]
    audio = [p for p in packets[2:]]
    return pre_skip, last_granule, audio


_CRC = []
for i in range(256):
    r = i << 24
    for _ in range(8):
        r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else (r << 1)
    _CRC.append(r & 0xFFFFFFFF)


def _crc(data):
    c = 0
    for b in data:
        c = ((c << 8) & 0xFFFFFFFF) ^ _CRC[((c >> 24) & 0xFF) ^ b]
    return c


def _page(packet, granule, seq, flags, serial=0x4C42):
    lacing = bytearray()
    n = len(packet)
    while n >= 255:
        lacing.append(255)
        n -= 255
    lacing.append(n)
    head = struct.pack("<4sBBqIIIB", b"OggS", 0, flags, granule, serial, seq, 0, len(lacing)) + bytes(lacing)
    page = bytearray(head + packet)
    struct.pack_into("<I", page, 22, _crc(page))
    return bytes(page)


def ogg_from_lbv(data):
    """An Ogg Opus stream carrying exactly the .lbv's packets, decodable by ffmpeg."""
    pre_skip, samples, packets = read_lbv(data)
    head = b"OpusHead" + struct.pack("<BBHIhB", 1, 1, pre_skip, 48000, 0, 0)
    tags = b"OpusTags" + struct.pack("<I", 3) + b"lbv" + struct.pack("<I", 0)
    out = bytearray(_page(head, 0, 0, 0x02) + _page(tags, 0, 1, 0x00))
    end = samples + pre_skip
    for i, p in enumerate(packets):
        last = i == len(packets) - 1
        granule = end if last else min((i + 1) * FRAME_SAMPLES, end)
        out += _page(p, granule, i + 2, 0x04 if last else 0x00)
    return bytes(out)
