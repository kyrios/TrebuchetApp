/* softtest: executes an invalid-in-long-mode opcode (0x16, PUSH SS) that its own vectored
 * handler skips, like the AoE2 anti-tamper traps. Checks that the handler sees the right
 * address and register values, and measures the cost per exception.
 * Build: x86_64-w64-mingw32-gcc -O2 -o AoE2DE_s.exe softtest.c */
#include <windows.h>
#include <stdio.h>

extern void trap_site(void);
extern unsigned long long run_trap(unsigned long long magic);
__asm__(".text\n"
        ".globl run_trap\n"
        "run_trap:\n"
        "  push %rbx\n  push %r12\n  push %r15\n"
        "  mov %rcx, %rbx\n  lea 1(%rcx), %r12\n  lea 2(%rcx), %r15\n"
        "  mov %rcx, %rax\n"
        "  movq %rcx, %xmm6\n  pinsrq $1, %rbx, %xmm6\n"
        ".globl trap_site\n"
        "trap_site:\n"
        "  .byte 0x16\n"            /* PUSH SS: #UD in 64-bit mode */
        "  add %rbx, %rax\n"        /* handler resumes here; rax = magic + rbx */
        "  add %r12, %rax\n  add %r15, %rax\n"
        "  pop %r15\n  pop %r12\n  pop %rbx\n  ret\n");

static volatile LONG bad, seen;
static LONG CALLBACK handler(EXCEPTION_POINTERS *ep)
{
    CONTEXT *c = ep->ContextRecord;
    if (ep->ExceptionRecord->ExceptionCode != STATUS_ILLEGAL_INSTRUCTION) return EXCEPTION_CONTINUE_SEARCH;
    if (c->Rip != (DWORD64)trap_site || ep->ExceptionRecord->ExceptionAddress != (void *)trap_site) { bad++; return EXCEPTION_CONTINUE_SEARCH; }
    if (c->Rbx != c->Rax || c->R12 != c->Rax + 1 || c->R15 != c->Rax + 2) bad++;
    if ((c->Rsp & 7) != 0) bad++;
    if (!seen) {
        M128A x = c->Xmm6;
        printf("first: code %lx flags %lx nparams %lu ctxflags %lx cs %x ss %x ds %x fs %x gs %x eflags %lx mxcsr %lx xmm6 %llx:%llx dr7 %llx rsp&15 %llx\n",
               ep->ExceptionRecord->ExceptionCode, ep->ExceptionRecord->ExceptionFlags, ep->ExceptionRecord->NumberParameters,
               c->ContextFlags, c->SegCs, c->SegSs, c->SegDs, c->SegFs, c->SegGs, c->EFlags, c->MxCsr,
               (unsigned long long)x.High, (unsigned long long)x.Low, (unsigned long long)c->Dr7, (unsigned long long)(c->Rsp & 15));
    }
    seen++;
    c->Rip += 1;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static double now(void)
{
    LARGE_INTEGER f, c; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&c);
    return (double)c.QuadPart / f.QuadPart;
}

int main(int argc, char **argv)
{
    double secs = argc > 1 ? atof(argv[1]) : 3.0, t0, t;
    long n = 0;
    unsigned long long r, wrong = 0;
    printf("trap_site=%p\n", (void *)trap_site);
    AddVectoredExceptionHandler(1, handler);
    t0 = now();
    do {
        for (int i = 0; i < 64; i++, n++) {
            unsigned long long m = 0x1000 + n * 4;
            r = run_trap(m);
            if (r != 4 * m + 3) wrong++;
        }
        t = now() - t0;
    } while (t < secs);
    printf("traps %ld  %.2f us/op  handler-mismatch %ld  result-mismatch %llu  seen %ld\n",
           n, t * 1e6 / n, bad, wrong, seen);
    fflush(stdout);
    return (bad || wrong) ? 1 : 0;
}
