#!/usr/bin/env python3
"""Parse the string table out of a Dart AOT snapshot (libapp.so).

Dart's clustered-snapshot serializer writes each String as
    ReadUnsigned( (length << 1) | is_two_byte ) , raw characters
back to back (OneByteString = Latin-1 bytes, TwoByteString = UTF-16LE).
ReadUnsigned is a little-endian base-128 varint whose *terminating* byte has the
high bit set (value = byte - 128).

The strings are stored as one contiguous deduplicated run. We find runs by chaining
(varint, chars) records and keeping chains that parse cleanly for many records.

Usage: parse_dart_strings.py <libapp.so> <out_dir>
"""
import json
import os
import sys

MIN_CHAIN = 8


def read_varint(d, i):
    """Return (value, next_index) or None."""
    shift = 0
    v = 0
    n = len(d)
    for _ in range(4):
        if i >= n:
            return None
        b = d[i]
        i += 1
        if b >= 0x80:
            return v | ((b - 0x80) << shift), i
        v |= b << shift
        shift += 7
    return None


def plausible_one_byte(chunk):
    for b in chunk:
        if b < 0x20 and b not in (9, 10, 13):
            return False
        if 0x7F <= b < 0xA0:
            return False
    return True


def plausible_two_byte(chunk):
    try:
        s = chunk.decode("utf-16-le")
    except UnicodeDecodeError:
        return False
    for ch in s:
        o = ord(ch)
        if o < 0x20 and o not in (9, 10, 13):
            return False
        if 0xD800 <= o <= 0xDFFF:
            return False
    return True


def parse_one(d, i):
    r = read_varint(d, i)
    if r is None:
        return None
    v, j = r
    n, two = v >> 1, v & 1
    if n == 0 or n > 20000:
        return None
    size = n * 2 if two else n
    if j + size > len(d):
        return None
    chunk = d[j : j + size]
    if two:
        if not plausible_two_byte(chunk):
            return None
        s = chunk.decode("utf-16-le")
    else:
        if not plausible_one_byte(chunk):
            return None
        s = chunk.decode("latin-1")
    return s, j + size


def main():
    so, out = sys.argv[1:3]
    os.makedirs(out, exist_ok=True)
    d = open(so, "rb").read()
    i = 0
    chains = []
    L = len(d)
    while i < L:
        if d[i] < 0x80:  # a record's varint must end in a >=0x80 byte within 3 bytes
            pass
        r = parse_one(d, i)
        if r is None:
            i += 1
            continue
        start = i
        strs = []
        pos = i
        while True:
            r = parse_one(d, pos)
            if r is None:
                break
            strs.append(r[0])
            pos = r[1]
        if len(strs) >= MIN_CHAIN:
            chains.append((start, pos, strs))
            i = pos
        else:
            i += 1
    total = sum(len(c[2]) for c in chains)
    print(f"chains={len(chains)} strings={total}")
    for s, e, st in sorted(chains, key=lambda c: -len(c[2]))[:6]:
        print(f"  chain @{s}-{e}: {len(st)} strings, e.g. {st[:3]}")
    allstr = []
    for s, e, st in chains:
        allstr.extend(st)
    uniq = sorted(set(allstr))
    with open(os.path.join(out, "snapshot_strings.json"), "w") as fh:
        json.dump(uniq, fh, ensure_ascii=False)
    print("unique", len(uniq))


if __name__ == "__main__":
    main()
