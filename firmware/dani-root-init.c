/*
 * Permanent fixed-device PID 1 for Dani's RG34XX-SP.
 *
 * The first-stage init has already mounted and moved proc, sysfs, devtmpfs,
 * /run and /tmp before switch_root. This process completes only the exact
 * remaining root setup, dispatches muOS compatibility startup behind the
 * already-interactive launcher, reaps orphaned children, and blocks on a
 * signalfd for explicit halt/reboot requests.
 */

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;
typedef signed long s64;

#define AT_FDCWD (-100)
#define O_WRONLY 1
#define O_CREAT 0100
#define O_CLOEXEC 02000000

#define SIG_BLOCK 0
#define SIG_SETMASK 2
#define SIGHUP 1
#define SIGINT 2
#define SIGUSR1 10
#define SIGUSR2 12
#define SIGTERM 15
#define SIGCHLD 17
#define SIGPWR 30

#define WNOHANG 1
#define POLLIN 0x0001
#define CLOCK_BOOTTIME 7

#define REBOOT_MAGIC1 0xfee1deadUL
#define REBOOT_MAGIC2 0x28121969UL
#define REBOOT_RESTART 0x01234567UL
#define REBOOT_HALT 0xcdef0123UL
#define REBOOT_POWER_OFF 0x4321fedcUL

#ifdef DANI_CLEAN_ROOT
#define ROOT_INIT_MARKER "/run/bird/clean-root-v1"
#define SYSINIT_SCRIPT "/opt/bird/post-frame.sh"
#define SHUTDOWN_SCRIPT "/opt/bird/shutdown.sh"
#else
#define ROOT_INIT_MARKER "/run/muos/dani-root-init-active"
#define SYSINIT_SCRIPT "/opt/muos/script/init/sysinit"
#define SHUTDOWN_SCRIPT "/opt/muos/script/init/shutdown"
#endif

struct timespec {
    s64 sec;
    s64 nsec;
};

struct pollfd {
    int fd;
    short events;
    short revents;
};

static char *const fixed_env[] = {
    "DANI_STATIC_PID1=1",
    "HOME=/root",
    "LANG=C",
    "PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/muos/bin",
    "SHELL=/bin/sh",
    "USER=root",
    0,
};

static u64 blocked_signals;

static long syscall6(long number, long a0, long a1, long a2, long a3, long a4,
                     long a5) {
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x3 __asm__("x3") = a3;
    register long x4 __asm__("x4") = a4;
    register long x5 __asm__("x5") = a5;
    register long x8 __asm__("x8") = number;
    __asm__ volatile("svc 0"
                     : "+r"(x0)
                     : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5),
                       "r"(x8)
                     : "memory", "cc");
    return x0;
}

static long sys_mkdir(const char *path, int mode) {
    return syscall6(34, AT_FDCWD, (long)path, mode, 0, 0, 0);
}

static long sys_unlink(const char *path) {
    return syscall6(35, AT_FDCWD, (long)path, 0, 0, 0, 0);
}

static long sys_symlink(const char *target, const char *path) {
    return syscall6(36, (long)target, AT_FDCWD, (long)path, 0, 0, 0);
}

static long sys_mount(const char *source, const char *target, const char *type,
                      u64 flags, const char *data) {
    return syscall6(40, (long)source, (long)target, (long)type, (long)flags,
                    (long)data, 0);
}

static long sys_open(const char *path, int flags, int mode) {
    return syscall6(56, AT_FDCWD, (long)path, flags, mode, 0, 0);
}

static long sys_close(int fd) {
    return syscall6(57, fd, 0, 0, 0, 0, 0);
}

static long sys_read(int fd, void *buffer, u64 size) {
    return syscall6(63, fd, (long)buffer, (long)size, 0, 0, 0);
}

static long sys_write(int fd, const void *buffer, u64 size) {
    return syscall6(64, fd, (long)buffer, (long)size, 0, 0, 0);
}

static long sys_ppoll(struct pollfd *fds, u64 count) {
    return syscall6(73, (long)fds, (long)count, 0, 0, 0, 0);
}

static long sys_signalfd(const u64 *mask) {
    return syscall6(74, -1, (long)mask, sizeof(*mask), O_CLOEXEC, 0, 0);
}

static long sys_clone(void) {
    return syscall6(220, SIGCHLD, 0, 0, 0, 0, 0);
}

static long sys_execve(const char *path, char *const argv[],
                       char *const envp[]) {
    return syscall6(221, (long)path, (long)argv, (long)envp, 0, 0, 0);
}

static long sys_wait4(long pid, int *status, int options) {
    return syscall6(260, pid, (long)status, options, 0, 0, 0);
}

static long sys_clock_gettime(struct timespec *value) {
    return syscall6(113, CLOCK_BOOTTIME, (long)value, 0, 0, 0, 0);
}

static long sys_sigprocmask(int how, const u64 *set) {
    return syscall6(135, how, (long)set, 0, sizeof(*set), 0, 0);
}

static long sys_sethostname(const char *name, u64 length) {
    return syscall6(161, (long)name, (long)length, 0, 0, 0, 0);
}

static long sys_reboot(u64 command) {
    return syscall6(142, REBOOT_MAGIC1, REBOOT_MAGIC2, (long)command, 0, 0, 0);
}

static void sys_sync(void) {
    syscall6(81, 0, 0, 0, 0, 0, 0);
}

static void sys_nanosleep(s64 nanoseconds) {
    struct timespec request;
    request.sec = nanoseconds / 1000000000L;
    request.nsec = nanoseconds % 1000000000L;
    syscall6(101, (long)&request, 0, 0, 0, 0, 0);
}

__attribute__((noreturn)) static void sys_exit(int status) {
    syscall6(93, status, 0, 0, 0, 0, 0);
    __builtin_unreachable();
}

static u64 string_length(const char *text) {
    u64 length = 0;
    while (text[length]) length++;
    return length;
}

static void write_all(int fd, const char *text, u64 length) {
    while (length) {
        long written = sys_write(fd, text, length);
        if (written <= 0) return;
        text += written;
        length -= (u64)written;
    }
}

static void log_text(const char *text) {
    write_all(1, text, string_length(text));
}

static void log_number(u64 value) {
    char digits[24];
    int position = 23;
    digits[position--] = '\0';
    if (!value) digits[position--] = '0';
    while (value) {
        digits[position--] = (char)('0' + value % 10);
        value /= 10;
    }
    log_text(&digits[position + 1]);
}

static u64 boot_milliseconds(void) {
    struct timespec value;
    if (sys_clock_gettime(&value) < 0) return 0;
    return (u64)value.sec * 1000UL + (u64)value.nsec / 1000000UL;
}

static void log_stage(const char *stage) {
    log_text("root-init boot_ms=");
    log_number(boot_milliseconds());
    log_text(" stage=");
    log_text(stage);
    log_text("\n");
}

static void make_dir(const char *path, int mode) {
    sys_mkdir(path, mode);
}

static int create_marker(const char *path) {
    long fd = sys_open(path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
    if (fd < 0) return -1;
    write_all((int)fd, "1\n", 2);
    sys_close((int)fd);
    return 0;
}

static void replace_symlink(const char *target, const char *path) {
    sys_unlink(path);
    sys_symlink(target, path);
}

static void clear_signal_mask(void) {
    static const u64 empty_mask;
    sys_sigprocmask(SIG_SETMASK, &empty_mask);
}

static int run_child_wait(const char *path, char *const argv[]) {
    long pid = sys_clone();
    int status = 0;
    if (pid < 0) return -1;
    if (pid == 0) {
        clear_signal_mask();
        sys_execve(path, argv, fixed_env);
        sys_exit(127);
    }
    if (sys_wait4(pid, &status, 0) < 0) return -1;
    return status;
}

__attribute__((noreturn)) static void fallback_busybox_init(const char *reason) {
    char *const argv[] = {"/init", 0};
    log_text("root-init fallback=");
    log_text(reason);
    log_text("\n");
    clear_signal_mask();
    sys_execve(argv[0], argv, fixed_env);
    log_text("root-init fatal=busybox-init-exec\n");
    for (;;) sys_nanosleep(1000000000L);
}

static int setup_exact_root(void) {
    make_dir("/dev/pts", 0755);
    make_dir("/dev/shm", 01777);
    make_dir("/run/lock", 0755);
    make_dir("/run/lock/subsys", 0755);

    if (sys_mount("devpts", "/dev/pts", "devpts", 0, 0) < 0) return -1;
    if (sys_mount("tmpfs", "/dev/shm", "tmpfs", 0, 0) < 0) return -1;

    replace_symlink("/proc/self/fd", "/dev/fd");
    replace_symlink("/proc/self/fd/0", "/dev/stdin");
    replace_symlink("/proc/self/fd/1", "/dev/stdout");
    replace_symlink("/proc/self/fd/2", "/dev/stderr");
#ifdef DANI_CLEAN_ROOT
    if (sys_sethostname("bird", 4) < 0) return -1;
#else
    if (sys_sethostname("muos", 4) < 0) return -1;
#endif
    if (create_marker(ROOT_INIT_MARKER) < 0) return -1;
    return 0;
}

static int setup_signal_queue(void) {
    blocked_signals =
        (1UL << (SIGHUP - 1)) | (1UL << (SIGINT - 1)) |
        (1UL << (SIGUSR1 - 1)) | (1UL << (SIGUSR2 - 1)) |
        (1UL << (SIGTERM - 1)) | (1UL << (SIGCHLD - 1)) |
        (1UL << (SIGPWR - 1));
    if (sys_sigprocmask(SIG_BLOCK, &blocked_signals) < 0) return -1;
    return (int)sys_signalfd(&blocked_signals);
}

static void reap_children(void) {
    int status;
    while (sys_wait4(-1, &status, WNOHANG) > 0) {
    }
}

__attribute__((noreturn)) static void finish_power_action(u64 command) {
    char *const shutdown_argv[] = {SHUTDOWN_SCRIPT, 0};
    char *const umount_argv[] = {"/bin/umount", "-a", "-r", 0};

    log_stage("shutdown-scripts");
    run_child_wait(shutdown_argv[0], shutdown_argv);
    log_stage("unmount-all");
    run_child_wait(umount_argv[0], umount_argv);
    sys_sync();
    log_stage("kernel-power-action");
    sys_reboot(command);
    for (;;) sys_nanosleep(1000000000L);
}

static u32 decode_signal(const u8 *record) {
    return (u32)record[0] | ((u32)record[1] << 8) |
           ((u32)record[2] << 16) | ((u32)record[3] << 24);
}

__attribute__((noreturn)) static void event_loop(int signal_fd) {
    struct pollfd descriptor;
    u8 record[128];

    descriptor.fd = signal_fd;
    descriptor.events = POLLIN;
    descriptor.revents = 0;

    for (;;) {
        long result = sys_ppoll(&descriptor, 1);
        if (result <= 0) continue;
        if (descriptor.revents & POLLIN) {
            long bytes = sys_read(signal_fd, record, sizeof(record));
            u32 signal;
            if (bytes < 4) continue;
            signal = decode_signal(record);
            if (signal == SIGCHLD) {
                reap_children();
            } else if (signal == SIGUSR2 || signal == SIGPWR) {
                finish_power_action(REBOOT_POWER_OFF);
            } else if (signal == SIGUSR1) {
                finish_power_action(REBOOT_HALT);
            } else if (signal == SIGTERM || signal == SIGINT) {
                finish_power_action(REBOOT_RESTART);
            }
        }
    }
}

static void application(void) {
    int signal_fd;
    int sysinit_status;
    char *const sysinit_argv[] = {SYSINIT_SCRIPT, 0};

    log_stage("start");
    if (setup_exact_root() < 0) fallback_busybox_init("exact-root-setup");
    signal_fd = setup_signal_queue();
    if (signal_fd < 0) fallback_busybox_init("signal-queue");
    log_stage("ready");

    sysinit_status = run_child_wait(sysinit_argv[0], sysinit_argv);
    log_text("root-init sysinit_wait_status=");
    log_number((u64)(unsigned int)sysinit_status);
    log_text("\n");
    if (sysinit_status == (127 << 8)) fallback_busybox_init("sysinit-exec");
    log_stage("event-loop");
    reap_children();
    event_loop(signal_fd);
}

__attribute__((noreturn, visibility("default"))) void _start(void) {
    application();
    sys_exit(0);
}
