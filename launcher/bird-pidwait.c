/*
 * Efficiently wait for one known Bird process without polling /proc.
 * Freestanding AArch64 Linux: pidfd_open + ppoll, then exit.
 */

typedef unsigned long u64;

#define POLLIN 0x0001
#define POLLHUP 0x0010

struct pollfd {
    int fd;
    short events;
    short revents;
};

static long syscall6(long number, long a0, long a1, long a2,
                     long a3, long a4, long a5) {
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x3 __asm__("x3") = a3;
    register long x4 __asm__("x4") = a4;
    register long x5 __asm__("x5") = a5;
    register long x8 __asm__("x8") = number;
    __asm__ volatile("svc 0" : "+r"(x0)
                     : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5),
                       "r"(x8)
                     : "memory", "cc");
    return x0;
}

static void sys_exit(int status) __attribute__((noreturn));
static void sys_exit(int status) {
    syscall6(93, status, 0, 0, 0, 0, 0);
    for (;;) {}
}

static long parse_pid(const char *text) {
    long value = 0;
    if (!text || !*text) return -1;
    while (*text) {
        if (*text < '0' || *text > '9') return -1;
        value = value * 10 + (*text++ - '0');
        if (value > 2147483647L) return -1;
    }
    return value > 0 ? value : -1;
}

static void start_c(u64 *stack) __attribute__((used, noinline, noreturn));
static void start_c(u64 *stack) {
    u64 argc = stack[0];
    char **argv = (char **)&stack[1];
    long pid;
    long fd;
    long result;
    struct pollfd event;

    if (argc != 2U) sys_exit(2);
    pid = parse_pid(argv[1]);
    if (pid < 0) sys_exit(2);

    fd = syscall6(434, pid, 0, 0, 0, 0, 0); /* pidfd_open */
    if (fd < 0) sys_exit(3);
    event.fd = (int)fd;
    event.events = POLLIN | POLLHUP;
    event.revents = 0;
    do {
        result = syscall6(73, (long)&event, 1, 0, 0, 0, 0); /* ppoll */
    } while (result == -4); /* EINTR */
    syscall6(57, fd, 0, 0, 0, 0, 0); /* close */
    sys_exit(result > 0 ? 0 : 4);
}

__attribute__((naked, noreturn)) void _start(void) {
    __asm__ volatile("mov x0, sp\n"
                     "b start_c\n");
}
