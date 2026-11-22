/* Test for the translation-time reorder (x87sidecar AOE_SUBST_*).
 * Builds the original 59-byte wrapper at 0x150000000 with thunks to C stand-ins for the
 * DLC lookup and the settings getter, registers the game's unwind info for it, and checks
 * result, call counts, return address seen by the lookup, and stack walks. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define F      0x150000000ULL
#define DLC    0x150000100ULL
#define GETTER 0x150000200ULL
#define SLOT   0x150000800ULL

static volatile int dlc_ret, setting_val, dlc_calls, getter_calls, bad;
static void *dlc_retaddr_seen, *settings_obj = (void *)0x1234500;
static int walk_ok_dlc, walk_ok_getter;
extern int main(int, char **);

static int walk_reaches_main(void)
{
    void *fr[16]; int i, n = RtlCaptureStackBackTrace(0, 16, fr, NULL);
    for (i = 0; i < n; i++)
        if ((char *)fr[i] >= (char *)main && (char *)fr[i] < (char *)main + 0x2000) return 1;
    return 0;
}
__attribute__((noinline)) static int c_dlc(int id)
{
    dlc_calls++;
    if (id != 8) bad++;
    walk_ok_dlc += walk_reaches_main();
    return dlc_ret;
}
__attribute__((noinline)) static int c_getter(void *obj, int key)
{
    getter_calls++;
    if (obj != settings_obj || key != 14) bad++;
    walk_ok_getter += walk_reaches_main();
    return setting_val;
}
/* thunk that records the caller's return address, then tail-jumps */
static void thunk(unsigned char *p, void *fn, void **save)
{
    if (save) { /* mov rax,[rsp] ; mov [abs],rax */
        *p++ = 0x48; *p++ = 0x8b; *p++ = 0x04; *p++ = 0x24;
        *p++ = 0x48; *p++ = 0xa3; memcpy(p, &save, 8); p += 8;
    }
    *p++ = 0x48; *p++ = 0xb8; memcpy(p, &fn, 8); p += 8; *p++ = 0xff; *p++ = 0xe0;
}
static void rel(unsigned char *at, ULONG64 target, ULONG64 next) { int d = (int)(target - next); memcpy(at, &d, 4); }

int main(int argc, char **argv)
{
    static const unsigned char tmpl[59] = {0x40,0x53,0x48,0x83,0xec,0x20,0xb9,0x08,0,0,0,0xe8,0,0,0,0,0x48,0x8b,0x0d,0,0,0,0,
        0xba,0x0e,0,0,0,0x0f,0xb6,0xd8,0xe8,0,0,0,0,0x83,0xf8,0x01,0x75,0x0a,0x84,0xdb,0x74,0x06,0x48,0x83,0xc4,0x20,0x5b,0xc3,
        0x32,0xc0,0x48,0x83,0xc4,0x20,0x5b,0xc3};
    static const unsigned char unwind[8] = {1,6,2,0,6,0x32,2,0x30};
    static const int dl[] = {0, 1, 0xff, 0x100}, st[] = {0, 1, 2, -1};
    unsigned char *pg = VirtualAlloc((void *)F, 0x1000, MEM_COMMIT|MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    RUNTIME_FUNCTION *rf; int (*f)(void) = (void *)F; int i, j, k, n = argc > 1 ? atoi(argv[1]) : 200000, fails = 0;
    LARGE_INTEGER fq, a, b;

    if (pg != (void *)F) { printf("alloc failed\n"); return 2; }
    memcpy(pg, tmpl, 59);
    rel(pg + 12, DLC, F + 16); rel(pg + 19, SLOT, F + 23); rel(pg + 32, GETTER, F + 36);
    thunk(pg + 0x100, c_dlc, &dlc_retaddr_seen); thunk(pg + 0x200, c_getter, NULL);
    memcpy(pg + 0x800, &settings_obj, 8);
    memcpy(pg + 0x900, unwind, 8);
    rf = (RUNTIME_FUNCTION *)(pg + 0xa00);
    rf->BeginAddress = 0; rf->EndAddress = 59; rf->UnwindData = 0x900;
    RtlAddFunctionTable(rf, 1, F);

    for (i = 0; i < 4; i++) for (j = 0; j < 4; j++) for (k = 0; k < 3; k++) {
        int want_al = (dl[i] & 0xff) && st[j] == 1, r, c0 = dlc_calls;
        dlc_ret = dl[i]; setting_val = st[j];
        r = f();
        if ((r & 0xff) != want_al) { fails++; printf("FAIL dlc=%x setting=%d -> %x\n", dl[i], st[j], r); }
        if (want_al && r != 1) { fails++; printf("FAIL eax on true: %x\n", r); }
        if (dlc_calls != c0 && dlc_retaddr_seen != (void *)(F + 16)) { fails++; printf("FAIL lookup return address %p\n", dlc_retaddr_seen); }
    }
    printf("equivalence: %d fails, bad args %d; dlc calls %d of 48, getter calls %d of 48; walks ok dlc %d getter %d\n",
           fails, bad, dlc_calls, getter_calls, walk_ok_dlc, walk_ok_getter);
    printf("mode: %s\n", dlc_calls == 48 ? "ORIGINAL order (lookup always called)" : dlc_calls == 12 ? "REORDERED (lookup only when setting == 1)" : "UNEXPECTED");

    dlc_ret = 1; setting_val = 0; dlc_calls = 0;
    QueryPerformanceFrequency(&fq); QueryPerformanceCounter(&a);
    for (i = 0; i < n; i++) k += f();
    QueryPerformanceCounter(&b);
    printf("setting=0: %.3f us/call, lookup calls %d of %d\n", (b.QuadPart - a.QuadPart) * 1e6 / fq.QuadPart / n, dlc_calls, n);
    /* guest memory must still hold the original bytes */
    printf("guest bytes %s\n", !memcmp(pg, tmpl, 12) && pg[0] == 0x40 ? "unchanged" : "CHANGED");
    return fails || bad;
}
