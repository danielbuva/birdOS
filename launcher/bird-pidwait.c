/*
 * Efficiently wait for one known Bird process without polling /proc, or
 * terminate one exact PID/start-time identity without a numeric-PID signal
 * race. Freestanding AArch64 Linux: pidfd_open + pidfd_send_signal + ppoll.
 */

typedef unsigned long u64;

#define POLLIN 0x0001
#define POLLHUP 0x0010
#define AT_FDCWD -100
#define O_RDONLY 0
#define SIGTERM 15
#define SIGKILL 9
#define ESRCH 3
#define EINTR 4

struct timespec {
    long sec;
    long nsec;
};

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

static long parse_unsigned(const char *text, const char *end,
                           unsigned long *value) {
    unsigned long result = 0;
    if (!text || text == end) return -1;
    while (text != end) {
        unsigned long digit;
        if (*text < '0' || *text > '9') return -1;
        digit = (unsigned long)(*text++ - '0');
        if (result > (~0UL - digit) / 10UL) return -1;
        result = result * 10UL + digit;
    }
    *value = result;
    return 0;
}

static const char *text_end(const char *text) {
    const char *cursor = text;
    while (*cursor) cursor++;
    return cursor;
}

static int append_pid(char *path, long pid) {
    char reverse[16];
    int length = 0;
    int position = 6;
    long value = pid;
    path[0] = '/'; path[1] = 'p'; path[2] = 'r';
    path[3] = 'o'; path[4] = 'c'; path[5] = '/';
    do {
        reverse[length++] = (char)('0' + value % 10);
        value /= 10;
    } while (value && length < (int)sizeof(reverse));
    while (length) path[position++] = reverse[--length];
    path[position++] = '/'; path[position++] = 's'; path[position++] = 't';
    path[position++] = 'a'; path[position++] = 't'; path[position] = 0;
    return position;
}

static int read_start_ticks(long pid, unsigned long *ticks) {
    char path[48];
    char buffer[1024];
    char *last_close = 0;
    char *cursor;
    char *end;
    long fd;
    long count;
    int token;

    append_pid(path, pid);
    fd = syscall6(56, AT_FDCWD, (long)path, O_RDONLY, 0, 0, 0);
    if (fd < 0) return -1;
    count = syscall6(63, fd, (long)buffer, sizeof(buffer) - 1U, 0, 0, 0);
    syscall6(57, fd, 0, 0, 0, 0, 0);
    if (count <= 0 || count >= (long)sizeof(buffer)) return -1;
    buffer[count] = 0;
    for (cursor = buffer; *cursor; cursor++)
        if (*cursor == ')') last_close = cursor;
    if (!last_close || last_close[1] != ' ') return -1;
    cursor = last_close + 2;
    for (token = 1; token <= 20; token++) {
        while (*cursor == ' ') cursor++;
        if (!*cursor) return -1;
        end = cursor;
        while (*end && *end != ' ' && *end != '\n') end++;
        if (token == 20) return parse_unsigned(cursor, end, ticks) == 0 ? 0 : -1;
        cursor = end;
    }
    return -1;
}

static long wait_pidfd(long fd, const struct timespec *timeout) {
    struct pollfd event;
    long result;
    event.fd = (int)fd;
    event.events = POLLIN | POLLHUP;
    event.revents = 0;
    do {
        result = syscall6(73, (long)&event, 1, (long)timeout, 0, 0, 0);
    } while (result == -EINTR);
    return result;
}

static void start_c(u64 *stack) __attribute__((used, noinline, noreturn));
static void start_c(u64 *stack) {
    u64 argc = stack[0];
    char **argv = (char **)&stack[1];
    long pid;
    long fd;
    long result;
    struct pollfd event;

    if (argc == 4U) {
        unsigned long expected_start;
        unsigned long actual_start;
        struct timespec grace;
        if (argv[1][0] != '-' || argv[1][1] != '-' ||
            argv[1][2] != 't' || argv[1][3] != 'e' ||
            argv[1][4] != 'r' || argv[1][5] != 'm' ||
            argv[1][6] != 'i' || argv[1][7] != 'n' ||
            argv[1][8] != 'a' || argv[1][9] != 't' ||
            argv[1][10] != 'e' || argv[1][11] != 0)
            sys_exit(2);
        pid = parse_pid(argv[2]);
        if (pid < 0 || parse_unsigned(argv[3], text_end(argv[3]),
                                      &expected_start) < 0)
            sys_exit(2);
        fd = syscall6(434, pid, 0, 0, 0, 0, 0); /* pidfd_open */
        if (fd == -ESRCH) sys_exit(0);
        if (fd < 0) sys_exit(3);
        if (read_start_ticks(pid, &actual_start) < 0) {
            syscall6(57, fd, 0, 0, 0, 0, 0);
            sys_exit(0); /* exited after pidfd_open */
        }
        if (actual_start != expected_start) {
            syscall6(57, fd, 0, 0, 0, 0, 0);
            sys_exit(5); /* PID was already replaced; never signal it */
        }
        result = syscall6(424, fd, SIGTERM, 0, 0, 0, 0); /* pidfd_send_signal */
        if (result < 0 && result != -ESRCH) {
            syscall6(57, fd, 0, 0, 0, 0, 0);
            sys_exit(6);
        }
        grace.sec = 1;
        grace.nsec = 0;
        result = wait_pidfd(fd, &grace);
        if (result == 0) {
            result = syscall6(424, fd, SIGKILL, 0, 0, 0, 0);
            if (result < 0 && result != -ESRCH) {
                syscall6(57, fd, 0, 0, 0, 0, 0);
                sys_exit(6);
            }
            result = wait_pidfd(fd, 0);
        }
        syscall6(57, fd, 0, 0, 0, 0, 0);
        sys_exit(result > 0 ? 0 : 4);
    }

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
