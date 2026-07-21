/*
 * Fixed early init for Dani's RG34XX-SP.
 *
 * This is deliberately a first-stage replacement only. It performs the exact
 * SD-card boot path with Linux syscalls, starts the already-proven launcher,
 * then executes the existing BusyBox switch_root and permanent root init.
 * The previous shell init is retained as /init.stock for early recovery.
 */

typedef unsigned char u8;
typedef unsigned long u64;
typedef signed long s64;

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_DIRECTORY 00200000
#define O_CLOEXEC 02000000

#define AT_REMOVEDIR 0x200
#define SEEK_SET 0

#define MS_NOSUID 2
#define MS_NODEV 4
#define MS_NOATIME 1024
#define MS_NODIRATIME 2048
#define MS_BIND 4096
#define MS_MOVE 8192

#define SIGCHLD 17
#define CLOCK_BOOTTIME 7

#define ROOT_DEVICE "/dev/mmcblk0p5"
#define ROOT_MOUNT "/mnt"
#define LAUNCHER_SOURCE "/opt/dani-launcher"
#define LAUNCHER_TARGET "/mnt/opt/muos/bin/dani-launcher"
#define ROOT_SUPERVISOR "/opt/muos/script/init/S03danilauncher"
#define READY_MARKER "/mnt/run/muos/dani-first-frame-ready"
#define FIXED_INIT_MARKER "/mnt/run/muos/dani-fixed-initramfs-v1"
#define TRIMMED_INIT_MARKER "/mnt/run/muos/dani-trimmed-initramfs-v1"
#define DIRECT_HANDOFF_MARKER "/mnt/run/muos/dani-direct-handoff-v1"
#define CLEAN_FS_MARKER "/mnt/run/muos/dani-fsck-clean-skip"
#ifdef DANI_STATIC_ROOT_INIT
#define ROOT_INIT_SOURCE "/opt/dani-root-init"
#define ROOT_INIT_TARGET "/mnt/sbin/dani-root-init"
#endif

struct timespec {
    s64 sec;
    s64 nsec;
};

struct linux_dirent64 {
    u64 ino;
    s64 offset;
    unsigned short record_length;
    u8 type;
    char name[];
};

static char *const fixed_env[] = {
    "DANI_FIXED_INITRAMFS=1",
    "HOME=/root",
    "LANG=C",
    "PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/muos/bin",
    "SHELL=/bin/sh",
    "USER=root",
    0,
};

#ifdef DANI_STATIC_ROOT_INIT
static int root_init_bound;
#endif
static int clean_root_skipped;

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

static long sys_mount(const char *source, const char *target, const char *type,
                      u64 flags, const char *data) {
    return syscall6(40, (long)source, (long)target, (long)type, (long)flags,
                    (long)data, 0);
}

static long sys_mkdir(const char *path, int mode) {
    return syscall6(34, AT_FDCWD, (long)path, mode, 0, 0, 0);
}

static long sys_open(const char *path, int flags, int mode) {
    return syscall6(56, AT_FDCWD, (long)path, flags, mode, 0, 0);
}

static long sys_openat(int directory_fd, const char *path, int flags,
                       int mode) {
    return syscall6(56, directory_fd, (long)path, flags, mode, 0, 0);
}

static long sys_unlinkat(int directory_fd, const char *path, int flags) {
    return syscall6(35, directory_fd, (long)path, flags, 0, 0, 0);
}

static long sys_close(int fd) {
    return syscall6(57, fd, 0, 0, 0, 0, 0);
}

static long sys_pread64(int fd, void *buffer, u64 size, u64 offset) {
    return syscall6(67, fd, (long)buffer, (long)size, (long)offset, 0, 0);
}

static long sys_getdents64(int fd, void *buffer, u64 size) {
    return syscall6(61, fd, (long)buffer, (long)size, 0, 0, 0);
}

static long sys_lseek(int fd, s64 offset, int whence) {
    return syscall6(62, fd, (long)offset, whence, 0, 0, 0);
}

static long sys_write(int fd, const void *buffer, u64 size) {
    return syscall6(64, fd, (long)buffer, (long)size, 0, 0, 0);
}

static long sys_dup3(int old_fd, int new_fd, int flags) {
    return syscall6(24, old_fd, new_fd, flags, 0, 0, 0);
}

static long sys_chdir(const char *path) {
    return syscall6(49, (long)path, 0, 0, 0, 0, 0);
}

static long sys_chroot(const char *path) {
    return syscall6(51, (long)path, 0, 0, 0, 0, 0);
}

static long sys_clone(void) {
    return syscall6(220, SIGCHLD, 0, 0, 0, 0, 0);
}

static long sys_execve(const char *path, char *const argv[],
                       char *const envp[]) {
    return syscall6(221, (long)path, (long)argv, (long)envp, 0, 0, 0);
}

static long sys_wait4(long pid, int *status) {
    return syscall6(260, pid, (long)status, 0, 0, 0, 0);
}

static long sys_clock_gettime(struct timespec *value) {
    return syscall6(113, CLOCK_BOOTTIME, (long)value, 0, 0, 0, 0);
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
    log_text("fixed-init boot_ms=");
    log_number(boot_milliseconds());
    log_text(" stage=");
    log_text(stage);
    log_text("\n");
}

static int path_exists(const char *path) {
    long fd = sys_open(path, O_RDONLY | O_CLOEXEC, 0);
    if (fd < 0) return 0;
    sys_close((int)fd);
    return 1;
}

static void make_dir(const char *path, int mode) {
    /* EEXIST is expected for directories already supplied by the rootfs. */
    sys_mkdir(path, mode);
}

static int create_marker(const char *path) {
    long fd = sys_open(path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
    if (fd < 0) return -1;
    write_all((int)fd, "1\n", 2);
    sys_close((int)fd);
    return 0;
}

static int run_child(const char *path, char *const argv[]) {
    long pid = sys_clone();
    int status = 0;
    if (pid < 0) return -1;
    if (pid == 0) {
        sys_execve(path, argv, fixed_env);
        sys_exit(127);
    }
    if (sys_wait4(pid, &status) < 0) return -1;
    return status;
}

__attribute__((noreturn)) static void stock_init_fallback(const char *reason) {
    char *const argv[] = {"/bin/sh", "/init.stock", 0};
    log_text("fixed-init fallback=");
    log_text(reason);
    log_text("\n");
    sys_execve(argv[0], argv, fixed_env);
    log_text("fixed-init fatal=stock-fallback-exec\n");
    for (;;) sys_nanosleep(1000000000L);
}

static void attach_console(void) {
    long console = sys_open("/dev/console", O_RDWR, 0);
    if (console < 0) return;
    if (console != 0) sys_dup3((int)console, 0, 0);
    if (console != 1) sys_dup3((int)console, 1, 0);
    if (console != 2) sys_dup3((int)console, 2, 0);
    if (console > 2) sys_close((int)console);
}

static int wait_for_root_device(void) {
    int count;
    for (count = 0; count < 100; count++) {
        if (path_exists(ROOT_DEVICE)) return 0;
        sys_nanosleep(10000000L);
    }
    return -1;
}

static int root_filesystem_is_clean(void) {
    u8 magic_and_state[4];
    long fd = sys_open(ROOT_DEVICE, O_RDONLY | O_CLOEXEC, 0);
    long bytes;
    unsigned int state;

    if (fd < 0) return 0;
    /* ext4 superblock starts at byte 1024. Magic is +56, state is +58. */
    bytes = sys_pread64((int)fd, magic_and_state, sizeof(magic_and_state),
                        1024 + 56);
    sys_close((int)fd);
    if (bytes != (long)sizeof(magic_and_state)) return 0;
    if (magic_and_state[0] != 0x53 || magic_and_state[1] != 0xef) return 0;

    state = (unsigned int)magic_and_state[2] |
            ((unsigned int)magic_and_state[3] << 8);
    return (state & 0x0001U) && !(state & 0x0002U);
}

static void run_filesystem_check(void) {
    char *const argv[] = {"/usr/sbin/e2fsck", "-y", ROOT_DEVICE, 0};
    int status;

    if (root_filesystem_is_clean()) {
        clean_root_skipped = 1;
        log_stage("fsck-clean-skip");
        return;
    }

    log_stage("fsck-start");
    status = run_child(argv[0], argv);
    log_stage("fsck-end");
    log_text("fixed-init fsck_wait_status=");
    log_number((u64)(unsigned int)status);
    log_text("\n");
}

static int prepare_future_root(void) {
    static const char root_options[] =
        "noauto_da_alloc,barrier=0,data=ordered";

    if (sys_mount(ROOT_DEVICE, ROOT_MOUNT, "ext4",
                  MS_NOATIME | MS_NODIRATIME, root_options) < 0)
        return -1;
    log_stage("root-mounted");

    make_dir("/mnt/dev", 0755);
    make_dir("/mnt/proc", 0555);
    make_dir("/mnt/sys", 0555);
    make_dir("/mnt/run", 0755);
    make_dir("/mnt/tmp", 01777);
    make_dir("/mnt/opt", 0755);
    make_dir("/mnt/opt/muos", 0755);
    make_dir("/mnt/opt/muos/bin", 0755);

    if (sys_mount("/dev", "/mnt/dev", 0, MS_MOVE | MS_NOATIME, 0) < 0)
        return -2;
    if (sys_mount("/proc", "/mnt/proc", 0, MS_MOVE, 0) < 0)
        return -2;
    if (sys_mount("/sys", "/mnt/sys", 0, MS_MOVE, 0) < 0)
        return -2;
    if (sys_mount("tmpfs", "/mnt/run", "tmpfs", MS_NOSUID | MS_NODEV,
                  "mode=0755") < 0)
        return -2;
    if (sys_mount("tmpfs", "/mnt/tmp", "tmpfs", 0, "mode=1777") < 0)
        return -2;
    make_dir("/mnt/run/muos", 0755);
    create_marker(FIXED_INIT_MARKER);
    create_marker(TRIMMED_INIT_MARKER);
    create_marker(DIRECT_HANDOFF_MARKER);
    if (clean_root_skipped) create_marker(CLEAN_FS_MARKER);
    log_stage("future-root-ready");
    return 0;
}

static int start_launcher_supervisor(void) {
    long target_fd;
    long pid;
    int status = 0;
    char *const argv[] = {ROOT_SUPERVISOR, "start", 0};

    if (!path_exists(LAUNCHER_SOURCE)) return -1;
    target_fd = sys_open(LAUNCHER_TARGET, O_WRONLY | O_CREAT | O_CLOEXEC, 0755);
    if (target_fd < 0) return -1;
    sys_close((int)target_fd);
    if (sys_mount(LAUNCHER_SOURCE, LAUNCHER_TARGET, 0, MS_BIND, 0) < 0)
        return -1;

    pid = sys_clone();
    if (pid < 0) return -1;
    if (pid == 0) {
        if (sys_chroot(ROOT_MOUNT) < 0 || sys_chdir("/") < 0) sys_exit(126);
        sys_execve(ROOT_SUPERVISOR, argv, fixed_env);
        sys_exit(127);
    }
    if (sys_wait4(pid, &status) < 0) return -1;
    log_stage("supervisor-dispatched");
    return status;
}

#ifdef DANI_STATIC_ROOT_INIT
static void bind_static_root_init(void) {
    long target_fd;

    make_dir("/mnt/sbin", 0755);
    if (!path_exists(ROOT_INIT_SOURCE)) {
        log_stage("root-init-source-missing");
        return;
    }
    target_fd = sys_open(ROOT_INIT_TARGET, O_WRONLY | O_CREAT | O_CLOEXEC, 0755);
    if (target_fd < 0) {
        log_stage("root-init-target-failed");
        return;
    }
    sys_close((int)target_fd);
    if (sys_mount(ROOT_INIT_SOURCE, ROOT_INIT_TARGET, 0, MS_BIND, 0) < 0) {
        log_stage("root-init-bind-failed");
        return;
    }
    root_init_bound = 1;
    log_stage("root-init-bound");
}
#endif

static void wait_for_first_frame(void) {
    int count;
    for (count = 0; count < 500; count++) {
        if (path_exists(READY_MARKER)) {
            log_stage("first-frame-ready");
            return;
        }
        sys_nanosleep(1000000L);
    }
    log_stage("first-frame-timeout");
}

static int same_name(const char *left, const char *right) {
    while (*left && *left == *right) {
        left++;
        right++;
    }
    return *left == *right;
}

static int dot_entry(const char *name) {
    return same_name(name, ".") || same_name(name, "..");
}

/*
 * Match switch_root's memory behavior without starting its BusyBox applet:
 * remove only the known initramfs tree and never descend into /mnt, which is
 * the already-mounted ext4 future root. Multiple passes make deletion robust
 * while directory offsets change underneath getdents64.
 */
static void delete_old_root_contents(int directory_fd, int preserve_mnt) {
    u8 buffer[1024];
    int pass;

    for (pass = 0; pass < 32; pass++) {
        long bytes;
        int removed = 0;

        sys_lseek(directory_fd, 0, SEEK_SET);
        while ((bytes = sys_getdents64(directory_fd, buffer,
                                       sizeof(buffer))) > 0) {
            long position = 0;
            while (position < bytes) {
                struct linux_dirent64 *entry =
                    (struct linux_dirent64 *)(buffer + position);
                int child_fd;

                if (entry->record_length < 20 ||
                    position + entry->record_length > bytes)
                    return;
                position += entry->record_length;
                if (dot_entry(entry->name)) continue;
                if (preserve_mnt && same_name(entry->name, "mnt")) continue;

                if (sys_unlinkat(directory_fd, entry->name, 0) == 0) {
                    removed++;
                    continue;
                }
                child_fd = (int)sys_openat(
                    directory_fd, entry->name,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0);
                if (child_fd < 0) continue;
                delete_old_root_contents(child_fd, 0);
                sys_close(child_fd);
                if (sys_unlinkat(directory_fd, entry->name,
                                 AT_REMOVEDIR) == 0)
                    removed++;
            }
        }
        if (!removed) return;
    }
}

__attribute__((noreturn)) static void busybox_handoff_fallback(
    const char *reason) {
    char *const stock_argv[] = {"/sbin/switch_root", "/mnt", "/init", 0};
#ifdef DANI_STATIC_ROOT_INIT
    char *const fixed_argv[] = {
        "/sbin/switch_root", "/mnt", "/sbin/dani-root-init", 0};
#endif

    log_text("fixed-init direct-handoff-fallback=");
    log_text(reason);
    log_text("\n");
#ifdef DANI_STATIC_ROOT_INIT
    if (root_init_bound) sys_execve(fixed_argv[0], fixed_argv, fixed_env);
#endif
    sys_execve(stock_argv[0], stock_argv, fixed_env);
    for (;;) sys_nanosleep(1000000000L);
}

__attribute__((noreturn)) static void handoff_root_init(void) {
    int old_root_fd;
    char *const stock_init_argv[] = {"/init", 0};
#ifdef DANI_STATIC_ROOT_INIT
    char *const fixed_init_argv[] = {"/sbin/dani-root-init", 0};
#endif

    old_root_fd = (int)sys_open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0);
    if (old_root_fd < 0 || sys_chdir(ROOT_MOUNT) < 0) {
        if (old_root_fd >= 0) sys_close(old_root_fd);
        busybox_handoff_fallback("prepare");
    }
    log_stage("direct-handoff-delete-old-root");
    delete_old_root_contents(old_root_fd, 1);
    sys_close(old_root_fd);
    if (sys_mount(".", "/", 0, MS_MOVE, 0) < 0 ||
        sys_chroot(".") < 0 || sys_chdir("/") < 0) {
        log_stage("direct-handoff-root-failed");
        for (;;) sys_nanosleep(1000000000L);
    }
#ifdef DANI_STATIC_ROOT_INIT
    if (root_init_bound) {
        log_stage("direct-handoff-static-pid1");
        sys_execve(fixed_init_argv[0], fixed_init_argv, fixed_env);
    }
#endif
    log_stage("direct-handoff-stock-pid1");
    sys_execve(stock_init_argv[0], stock_init_argv, fixed_env);
    log_stage("direct-handoff-exec-failed");
    for (;;) sys_nanosleep(1000000000L);
}

static void application(void) {
    int root_status;
    int supervisor_status;

    if (sys_mount("proc", "/proc", "proc", 0, 0) < 0)
        stock_init_fallback("mount-proc");
    if (sys_mount("sysfs", "/sys", "sysfs", 0, 0) < 0)
        stock_init_fallback("mount-sys");
    if (sys_mount("none", "/dev", "devtmpfs", 0, 0) < 0)
        stock_init_fallback("mount-dev");
    attach_console();
    log_stage("start");

    if (wait_for_root_device() < 0) stock_init_fallback("root-device-timeout");
    run_filesystem_check();
    root_status = prepare_future_root();
    if (root_status == -1) stock_init_fallback("mount-root");
    if (root_status < 0) {
        log_stage("future-root-partial-fallback");
        handoff_root_init();
    }

#ifdef DANI_STATIC_ROOT_INIT
    bind_static_root_init();
#endif

    supervisor_status = start_launcher_supervisor();
    log_text("fixed-init supervisor_wait_status=");
    log_number((u64)(unsigned int)supervisor_status);
    log_text("\n");
    if (supervisor_status >= 0) wait_for_first_frame();
    handoff_root_init();
}

__attribute__((noreturn, visibility("default"))) void _start(void) {
    application();
    sys_exit(0);
}
