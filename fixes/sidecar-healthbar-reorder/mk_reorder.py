#!/usr/bin/env python3
"""Byte strings for the translation-time reorder of the AoE2 DE wrapper
    bool f() { return dlc_owned(8) && setting(14) == 1; }
into
    bool f() { return setting(14) == 1 && dlc_owned(8); }

  mk_reorder.py exe <AoE2DE_s.exe>         find the wrapper in the exe, print shell exports
  mk_reorder.py addr <f> <dlc> <getter> <slot>   same for given addresses (test exe)

The new layout keeps `mov ecx,8 ; call dlc` at its original place (offsets 6..15), so the
protected lookup is called from the same address, with the same return address, as in the
original code. Nothing is written to the game: the bytes are only shown to Rosetta's decoder
(x87sidecar, AOE_SUBST_*), and only while the game's own 59 bytes equal ORIG."""
import re, struct, sys, hashlib

def rel(target, next_ip): 
    d = target - next_ip
    assert -2**31 <= d < 2**31
    return struct.pack('<i', d)

def build(f, dlc, getter, slot):
    orig  = bytes.fromhex('405348 83ec20 b908000000') + b'\xe8' + rel(dlc, f + 16)
    orig += b'\x48\x8b\x0d' + rel(slot, f + 23) + bytes.fromhex('ba0e000000 0fb6d8') + b'\xe8' + rel(getter, f + 36)
    orig += bytes.fromhex('83f801 750a 84db 7406 4883c420 5b c3 32c0 4883c420 5b c3')
    new  = bytes.fromhex('53 eb1b cccccc')                       #  0 push rbx ; jmp X(30)
    new += bytes.fromhex('b908000000') + b'\xe8' + rel(dlc, f + 16)   #  6 mov ecx,8 ; call dlc   (original bytes)
    new += bytes.fromhex('84c0 0f95c0 0fb6c0')                  # 16 test al,al ; setne al ; movzx eax,al
    new += bytes.fromhex('4883c420 5b c3')                      # 24 end: add rsp,20h ; pop rbx ; ret
    new += bytes.fromhex('4883ec20')                            # 30 X: sub rsp,20h
    new += b'\x48\x8b\x0d' + rel(slot, f + 41)                  # 34 mov rcx,[settings]
    new += bytes.fromhex('6a0e 5a') + b'\xe8' + rel(getter, f + 49)   # 41 push 0Eh ; pop rdx ; call getter
    new += bytes.fromhex('83f801 74d0 32c0 ebde cc')            # 49 cmp eax,1 ; je 6 ; xor al,al ; jmp end
    assert len(orig) == 59 and len(new) == 59 and orig[6:16] == new[6:16]
    return orig, new

def from_exe(path):
    d = open(path, 'rb').read()
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    n = struct.unpack_from('<H', d, pe + 6)[0]; osz = struct.unpack_from('<H', d, pe + 20)[0]
    base = struct.unpack_from('<Q', d, pe + 24 + 24)[0]
    secs = [struct.unpack_from('<8sIIII', d, pe + 24 + osz + 40 * i) for i in range(n)]
    def va(off):
        for _, vs, rva, rs, ro in secs:
            if ro <= off < ro + rs: return base + rva + off - ro
    pat = re.compile(rb'\x40\x53\x48\x83\xec\x20\xb9\x08\x00\x00\x00\xe8(....)\x48\x8b\x0d(....)\xba\x0e\x00\x00\x00\x0f\xb6\xd8\xe8(....)'
                     rb'\x83\xf8\x01\x75\x0a\x84\xdb\x74\x06\x48\x83\xc4\x20\x5b\xc3\x32\xc0\x48\x83\xc4\x20\x5b\xc3', re.S)
    ms = list(pat.finditer(d))
    if len(ms) != 1: sys.exit('wrapper not found exactly once (%d matches)' % len(ms))
    m = ms[0]; f = va(m.start())
    g = lambda i, nxt: f + nxt + struct.unpack('<i', m.group(i))[0]
    orig, new = build(f, g(1, 16), g(3, 36), g(2, 23))
    assert orig == m.group(0)
    return f, orig, new, hashlib.sha256(d).hexdigest()

if sys.argv[1] == 'exe':
    f, orig, new, sha = from_exe(sys.argv[2])
    print('# AoE2DE_s.exe sha256 %s' % sha)
else:
    f = int(sys.argv[2], 16)
    orig, new = build(f, *(int(a, 16) for a in sys.argv[3:6]))
print('export AOE_SUBST_PC=0x%x' % f)
print('export AOE_SUBST_ORIG=%s' % orig.hex())
print('export AOE_SUBST_NEW=%s' % new.hex())
