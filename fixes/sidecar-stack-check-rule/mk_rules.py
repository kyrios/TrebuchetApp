#!/usr/bin/env python3
"""mk_rules.py — fingerprint locator for translation-time rules tied to a game build (2026-11-22).

Policy: a rule tied to a game build must (1) find its site by
fingerprint, not by fixed offsets, (2) let the launcher WARN visibly when it does not match, (3) fit an update path.
This finder covers (1) and (2): every rule is a byte pattern with wildcards + a semantic check; the output is

    AOE_SUBST_LIST=pc:orig:new[,pc:orig:new...]     (only rules that matched exactly once and passed their check)
    WARN rule <name>: <reason>                       (one line per rule that did not; the launcher shows it, runs stock)
    RULESET <sha256 of the rule definitions>         (identifies the rule set, for an update channel later)

Nothing is written to the game. The sidecar shows the decoder NEW only while the live bytes equal ORIG (exact gate).
usage: mk_rules.py <AoE2DE_s.exe> [rule ...]        (default: all rules)
"""
import hashlib, re, struct, sys

def sections(d):
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    n = struct.unpack_from('<H', d, pe + 6)[0]; osz = struct.unpack_from('<H', d, pe + 20)[0]
    base = struct.unpack_from('<Q', d, pe + 24 + 24)[0]
    out = []
    for i in range(n):
        o = pe + 24 + osz + 40 * i
        name = d[o:o + 8].rstrip(b'\0').decode(errors='replace')
        vs, va, rs, ro, ch = struct.unpack_from('<IIII', d, o + 8) + (struct.unpack_from('<I', d, o + 36)[0],)
        out.append(dict(name=name, va=base + va, vs=vs, raw=ro, rs=rs, exe=bool(ch & 0x20000000), write=bool(ch & 0x80000000)))
    return base, out

def pat(s):  # "48 3b 0d ?? ?? ?? ?? 75 10" -> compiled regex over bytes
    return re.compile(b''.join(b'.' if t == '??' else re.escape(bytes([int(t, 16)])) for t in s.split()), re.S)

# ── rule T13: GS cookie check (__security_check_cookie), tighter but identical form ─────────────────────────────
# cmp rcx,[rip+cookie]; jne F1; rol rcx,16; test cx,0xffff; jne F2; ret; F2: ror rcx,16; F1: jmp report
# NEW: rol rcx,16 -> ror rcx,48 (same rcx; the rotate's flags are dead: TEST rewrites all of them before any read)
#      test cx,0xffff -> test cx,cx ; nop (66 90)   (same 16-bit result -> identical CF/PF/ZF/SF/OF; AF undefined both)
T13_PAT = pat('48 3b 0d ?? ?? ?? ?? 75 10 48 c1 c1 10 66 f7 c1 ff ff 75 01 c3 48 c1 c9 10 e9 ?? ?? ?? ??')
def t13(d, base, secs):
    hits = []
    for s in secs:
        if not s['exe']: continue
        blob = d[s['raw']:s['raw'] + min(s['rs'], s['vs'])]
        for m in T13_PAT.finditer(blob):
            hits.append((s, m.start()))
    if len(hits) != 1: return None, f'{len(hits)} matches (need exactly 1)'
    s, o = hits[0]; va = s['va'] + o; raw = d[s['raw'] + o:s['raw'] + o + 30]
    cookie = va + 7 + struct.unpack_from('<i', raw, 3)[0]
    report = va + 30 + struct.unpack_from('<i', raw, 26)[0]
    if not any(x['write'] and not x['exe'] and x['va'] <= cookie < x['va'] + x['vs'] for x in secs):
        return None, 'cookie operand is not in a writable data section'
    if not any(x['exe'] and x['va'] <= report < x['va'] + x['vs'] for x in secs):
        return None, 'failure branch does not lead into code'
    orig = raw[:21]
    new = orig[:9] + bytes.fromhex('48c1c930') + bytes.fromhex('6685c9') + bytes.fromhex('6690') + orig[18:21]
    assert len(new) == len(orig) == 21 and new[18:21] == bytes.fromhex('7501c3')
    return (va, orig, new), f'cookie check at 0x{va:x} (cookie 0x{cookie:x}, report 0x{report:x})'

RULES = {'T13': t13}

def main():
    if len(sys.argv) < 2: print(__doc__); return 2
    d = open(sys.argv[1], 'rb').read()
    base, secs = sections(d)
    want = sys.argv[2:] or list(RULES)
    entries = []
    for name in want:
        r, why = RULES[name](d, base, secs)
        if r is None: print(f'WARN rule {name}: {why} -> running stock for this rule'); continue
        va, orig, new = r
        entries.append(f'0x{va:x}:{orig.hex()}:{new.hex()}')
        print(f'# rule {name}: {why}', file=sys.stderr)
    if entries: print('AOE_SUBST_LIST=' + ','.join(entries))
    src = open(__file__, 'rb').read()
    print('RULESET ' + hashlib.sha256(src).hexdigest()[:16])
    return 0

if __name__ == '__main__':
    sys.exit(main())
