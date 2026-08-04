/*
 * Bird's fixed RG34XX-SP global-controls process for ROCKNIX 20260701.
 *
 * The stock input_sense service expands into Bash, grep, four evtest workers,
 * and several coordinating shells.  This freestanding AArch64 process opens
 * only the four immutable internal input devices and preserves the subset of
 * global policy used by Bird:
 *
 *   - dedicated volume keys, including 300 ms / 100 ms hold repeat;
 *   - Menu + volume for direct fixed-panel brightness steps, including stable
 *     three-percent and one-percent low-end levels;
 *   - power and lid events through ROCKNIX's proven fake-suspend helper; and
 *   - Select + Start through Bird's foreground-session exit contract; and
 *   - Menu + Select + Start through an on-demand logged UI recovery contract.
 *
 * It never grabs the H700 gamepad, so Bird and selected applications continue
 * to receive their normal controls.  Event numbers are treated only as a fast
 * bounded search space: every descriptor is accepted by its kernel name.
 */

typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long u64;
typedef signed int s32;
typedef signed long s64;

#include "bird-device-contract.h"

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_CREAT 0100
#define O_APPEND 02000
#define O_NONBLOCK 04000
#define O_DSYNC 010000
#define O_CLOEXEC 02000000
#define SIGCHLD 17
#define POLLIN 0x0001
#define POLLERR 0x0008
#define POLLHUP 0x0010
#define POLLNVAL 0x0020
#define IN_MOVED_TO 0x00000080U
#define IN_CREATE 0x00000100U
#define IN_Q_OVERFLOW 0x00004000U
#define WNOHANG 1
#define EAGAIN 11
#define EINTR 4
#define CLOCK_BOOTTIME 7

#define SPAWN_INTERNAL_FAILED 0
#define SPAWN_DISPATCHED 1
#define SPAWN_EXEC_FAILED (-1)

#define EV_SYN 0x00
#define EV_KEY 0x01
#define EV_SW 0x05
#define SYN_DROPPED 3
#define SW_LID 0
#define KEY_VOLUMEDOWN 114
#define KEY_VOLUMEUP 115
#define KEY_POWER 116
#define BTN_SELECT 314
#define BTN_START 315
#define BTN_MODE 316

#define EVIOCGNAME_128 0x80804506UL
#define EVIOCGID 0x80084502UL
#define EVIOCGBIT_EV 0x80084520UL
#define EVIOCGBIT_KEY 0x80604521UL
#define EVIOCGBIT_ABS 0x80084523UL
#define EVIOCGBIT_FF 0x80104535UL

#define GAMEPAD_NAME BIRD_DEVICE_INPUT_NAME
#define VOLUME_NAME "gpio-keys-volume"
#define POWER_NAME "axp20x-pek"
#define LID_NAME "gpio-keys-lid"

#define VOLUME_PROGRAM "/flash/bird/bird-volume.sh"
#define OSD_PROGRAM "/flash/bird/bird-control-osd.sh"
#define BRIGHTNESS_CURRENT BIRD_DEVICE_BACKLIGHT_DIRECTORY "/brightness"
#define BRIGHTNESS_MAX BIRD_DEVICE_BACKLIGHT_DIRECTORY "/max_brightness"
#define SUSPEND_PROGRAM "/flash/bird/bird-suspend.sh"
#define SUSPEND_RESUME_READY "/run/bird/bird-suspend-resume-ready"
#define POWER_SUSPEND_ACTIVE "/var/run/power-fake-suspend-active.flag"
#define EXIT_HELPER "/flash/bird/bird-fixed-control-exit.sh"
#define EMERGENCY_HELPER "/flash/bird/bird-emergency-recover.sh"
#define KMSG_DEVICE "/dev/kmsg"
#define SUSPEND_TRACE "/storage/bird-data/Bird/log/suspend-events.tsv"

#define SOURCE_GAMEPAD 0
#define SOURCE_VOLUME 1
#define SOURCE_POWER 2
#define SOURCE_LID 3
#define SOURCE_COUNT 4
#define EVENT_SCAN_COUNT 32

#define VOLUME_REPEAT_DELAY_NS 300000000L
#define VOLUME_REPEAT_INTERVAL_NS 100000000L
#define DISCOVERY_RETRY_NS 250000000L
#define RESUME_READY_RETRY_NS 25000000L
#define RESUME_READY_TIMEOUT_NS 10000000000UL

#define PENDING_SUSPEND_NONE 0
#define PENDING_SUSPEND_POWER 1
#define PENDING_SUSPEND_LID_CLOSE 2

#define POLL_RESULT_READY 0
#define POLL_RESULT_INTERRUPTED 1
#define POLL_RESULT_FAILED 2

struct timespec {
    s64 sec;
    s64 nsec;
};

struct pollfd {
    int fd;
    short events;
    short revents;
};

struct inotify_event {
    s32 wd;
    u32 mask;
    u32 cookie;
    u32 len;
    char name[];
};

struct input_event {
    s64 seconds;
    s64 microseconds;
    u16 type;
    u16 code;
    s32 value;
};

struct input_id {
    u16 bus;
    u16 vendor;
    u16 product;
    u16 version;
};

_Static_assert(sizeof(struct input_id) == 8U, "input ID ABI changed");

struct input_source {
    int fd;
    const char *name;
};

struct control_state {
    int menu_held;
    int select_held;
    int start_held;
    int exit_latched;
    int emergency_latched;
    int volume_up_held;
    int volume_down_held;
    int repeat_direction;
    u64 repeat_at_ns;
};

struct suspend_state {
    int resume_in_flight;
    int pending_suspend;
    u64 resume_deadline_ns;
};

static char *const fixed_env[] = {
    "HOME=/storage",
    "LANG=C",
    "LC_ALL=C",
    "PATH=/usr/bin:/usr/local/bin:/storage/bin:/bin:/sbin:/usr/sbin",
    "XDG_RUNTIME_DIR=/var/run/0-runtime-dir",
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket",
    0,
};

static int kmsg_fd = -1;
static u64 suspend_trace_sequence;

#ifdef BIRD_HOST_TEST
extern long bird_test_syscall6(long number, long a0, long a1, long a2,
                               long a3, long a4, long a5);
#endif

static long syscall6(long number, long a0, long a1, long a2, long a3, long a4,
                     long a5) {
#ifdef BIRD_HOST_TEST
    return bird_test_syscall6(number, a0, a1, a2, a3, a4, a5);
#else
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
#endif
}

static long sys_open(const char *path, int flags) {
    return syscall6(56, AT_FDCWD, (long)path, flags, 0, 0, 0);
}

static long sys_open_mode(const char *path, int flags, int mode) {
    return syscall6(56, AT_FDCWD, (long)path, flags, mode, 0, 0);
}

static long sys_close(int fd) {
    return syscall6(57, fd, 0, 0, 0, 0, 0);
}

static long sys_unlink(const char *path) {
    return syscall6(35, AT_FDCWD, (long)path, 0, 0, 0, 0);
}

static long sys_pipe2(int pipes[2], int flags) {
    return syscall6(59, (long)pipes, flags, 0, 0, 0, 0);
}

static long sys_read(int fd, void *buffer, u64 size) {
    return syscall6(63, fd, (long)buffer, (long)size, 0, 0, 0);
}

static long sys_write(int fd, const void *buffer, u64 size) {
    return syscall6(64, fd, (long)buffer, (long)size, 0, 0, 0);
}

static long sys_ioctl(int fd, u64 request, void *argument) {
    return syscall6(29, fd, (long)request, (long)argument, 0, 0, 0);
}

static long sys_ppoll(struct pollfd *fds, u64 count,
                      const struct timespec *timeout) {
    return syscall6(73, (long)fds, (long)count, (long)timeout, 0, 0, 0);
}

static long sys_inotify_init1(int flags) {
    return syscall6(26, flags, 0, 0, 0, 0, 0);
}

static long sys_inotify_add_watch(int fd, const char *path, u32 mask) {
    return syscall6(27, fd, (long)path, mask, 0, 0, 0);
}

static long sys_clock_gettime(int clock, struct timespec *value) {
    return syscall6(113, clock, (long)value, 0, 0, 0, 0);
}

static long sys_clone(void) {
    return syscall6(220, SIGCHLD, 0, 0, 0, 0, 0);
}

static long sys_execve(const char *path, char *const argv[]) {
    return syscall6(221, (long)path, (long)argv, (long)fixed_env, 0, 0, 0);
}

static long sys_wait4(long pid, int *status, int options) {
    return syscall6(260, pid, (long)status, options, 0, 0, 0);
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

static int strings_equal(const char *left, const char *right) {
    while (*left && *left == *right) {
        left++;
        right++;
    }
    return *left == *right;
}

static void write_all(int fd, const char *text, u64 length) {
    while (length) {
        long written = sys_write(fd, text, length);
        if (written <= 0) return;
        text += written;
        length -= (u64)written;
    }
}

static int read_number(const char *path, u64 *value) {
    char buffer[32];
    long fd = sys_open(path, O_RDONLY | O_CLOEXEC);
    long count;
    u64 parsed = 0;
    int digits = 0;
    int index;
    if (fd < 0) return 0;
    count = sys_read((int)fd, buffer, sizeof(buffer));
    sys_close((int)fd);
    if (count <= 0) return 0;
    for (index = 0; index < count; index++) {
        char c = buffer[index];
        if (c < '0' || c > '9') break;
        parsed = parsed * 10U + (u64)(c - '0');
        digits++;
    }
    if (!digits) return 0;
    *value = parsed;
    return 1;
}

static int write_number(const char *path, u64 value) {
    char buffer[32];
    int position = 31;
    long fd;
    long length;
    long written;
    buffer[--position] = '\n';
    do {
        buffer[--position] = (char)('0' + value % 10U);
        value /= 10U;
    } while (value);
    fd = sys_open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    length = 31 - position;
    written = sys_write((int)fd, buffer + position, (u64)length);
    sys_close((int)fd);
    return written == length;
}

static int path_exists(const char *path) {
    long fd = sys_open(path, O_RDONLY | O_CLOEXEC);

    if (fd < 0) return 0;
    sys_close((int)fd);
    return 1;
}

static void log_text(const char *text) {
    u64 length = string_length(text);
    write_all(1, text, length);
    if (kmsg_fd >= 0) write_all(kmsg_fd, text, length);
}

static u64 now_ns(void) {
    struct timespec value;
    if (sys_clock_gettime(CLOCK_BOOTTIME, &value) < 0) return 0;
    return (u64)value.sec * 1000000000UL + (u64)value.nsec;
}

static void ns_to_timespec(u64 nanoseconds, struct timespec *value) {
    value->sec = (s64)(nanoseconds / 1000000000UL);
    value->nsec = (s64)(nanoseconds % 1000000000UL);
}

static char *append_trace_text(char *output, const char *text) {
    while (*text) *output++ = *text++;
    return output;
}

static char *append_trace_u64(char *output, u64 value) {
    char digits[20];
    int count = 0;

    do {
        digits[count++] = (char)('0' + value % 10U);
        value /= 10U;
    } while (value);
    while (count) *output++ = digits[--count];
    return output;
}

static void trace_suspend(const char *source, const char *action,
                          const char *phase) {
    char record[192];
    char *end = record;
    long fd;

    end = append_trace_text(end, "boottime_ns\t");
    end = append_trace_u64(end, now_ns());
    end = append_trace_text(end, "\tsequence\t");
    end = append_trace_u64(end, ++suspend_trace_sequence);
    end = append_trace_text(end, "\tsource\t");
    end = append_trace_text(end, source);
    end = append_trace_text(end, "\taction\t");
    end = append_trace_text(end, action ? action : "toggle");
    end = append_trace_text(end, "\tphase\t");
    end = append_trace_text(end, phase);
    *end++ = '\n';
    fd = sys_open_mode(SUSPEND_TRACE,
                       O_WRONLY | O_CREAT | O_APPEND | O_DSYNC | O_CLOEXEC,
                       0600);
    if (fd < 0) return;
    write_all((int)fd, record, (u64)(end - record));
    sys_close((int)fd);
}

static int report_exec_failure(int fd) {
    const char marker = 'E';
    long result;

    do {
        result = sys_write(fd, &marker, 1);
    } while (result == -EINTR);
    return result == 1;
}

/*
 * Detach every potentially long-running action with a double fork.  The short
 * intermediate child is reaped synchronously; the action itself is adopted by
 * PID 1 and can sleep for ROCKNIX's full fake-suspend timeout without blocking
 * input processing or leaving a daemon-owned zombie.
 *
 * A close-on-exec pipe distinguishes a successful dispatch from a missing,
 * non-executable, or incompatible helper.  A successful exec closes the
 * grandchild's write descriptor in the kernel, so the parent observes EOF as
 * soon as exec completes rather than waiting for the action to finish.  An
 * exec failure writes one marker before the detached child exits.
 */
static int spawn_action(const char *path, const char *first,
                        const char *second) {
    int handshake[2];
    long child;
    int status = 0;
    char marker;
    long result;

    if (sys_pipe2(handshake, O_CLOEXEC) < 0) return SPAWN_INTERNAL_FAILED;
    child = sys_clone();
    if (child < 0) {
        sys_close(handshake[0]);
        sys_close(handshake[1]);
        return SPAWN_INTERNAL_FAILED;
    }
    if (child == 0) {
        long action = sys_clone();

        sys_close(handshake[0]);
        if (action < 0) {
            report_exec_failure(handshake[1]);
            sys_close(handshake[1]);
            sys_exit(127);
        }
        if (action == 0) {
            char *const argv0[] = {(char *)path, 0};
            char *const argv1[] = {(char *)path, (char *)first, 0};
            char *const argv2[] = {
                (char *)path, (char *)first, (char *)second, 0};
            if (second)
                sys_execve(path, argv2);
            else if (first)
                sys_execve(path, argv1);
            else
                sys_execve(path, argv0);
            report_exec_failure(handshake[1]);
            sys_close(handshake[1]);
            sys_exit(127);
        }
        sys_close(handshake[1]);
        sys_exit(0);
    }
    sys_close(handshake[1]);
    do {
        result = sys_wait4(child, &status, 0);
    } while (result == -EINTR);
    if (result < 0 || status != 0) {
        sys_close(handshake[0]);
        return SPAWN_INTERNAL_FAILED;
    }
    do {
        result = sys_read(handshake[0], &marker, 1);
    } while (result == -EINTR);
    sys_close(handshake[0]);
    if (result == 0) return SPAWN_DISPATCHED;
    if (result == 1 && marker == 'E') return SPAWN_EXEC_FAILED;
    return SPAWN_INTERNAL_FAILED;
}

static void run_volume(int direction) {
    int result =
        spawn_action(VOLUME_PROGRAM, direction > 0 ? "up" : "down", 0);

    if (result == SPAWN_DISPATCHED)
        {
        (void)spawn_action(OSD_PROGRAM, "volume", 0);
        log_text(direction > 0
                     ? "bird-fixed-controls: volume-up\n"
                     : "bird-fixed-controls: volume-down\n");
        }
    else if (result == SPAWN_EXEC_FAILED)
        log_text("bird-fixed-controls: volume-exec-failed\n");
    else
        log_text("bird-fixed-controls: volume-spawn-failed\n");
}

static u64 brightness_raw_target(u64 current, u64 maximum, int direction) {
    u64 percent;
    u64 target;
    u64 raw;

    if (!maximum) return 0;
    percent = (current * 100U + maximum / 2U) / maximum;
    if (direction > 0) {
        if (percent < 1U)
            target = 1U;
        else if (percent < 3U)
            target = 3U;
        else if (percent < 5U)
            target = 5U;
        else
            target = percent + 5U;
        if (target > 100U) target = 100U;
    } else {
        if (percent > 5U)
            target = percent - 5U;
        else if (percent > 3U)
            target = 3U;
        else
            target = 1U;
    }
    raw = (target * maximum + 50U) / 100U;
    if (raw < 1U) raw = 1U;
    if (raw > maximum) raw = maximum;
    return raw;
}

static void run_brightness(int direction) {
    u64 current;
    u64 maximum;
    u64 raw;
    if (!read_number(BRIGHTNESS_CURRENT, &current) ||
        !read_number(BRIGHTNESS_MAX, &maximum) || !maximum) {
        log_text("bird-fixed-controls: brightness-read-failed\n");
        return;
    }
    raw = brightness_raw_target(current, maximum, direction);
    if (write_number(BRIGHTNESS_CURRENT, raw)) {
        (void)spawn_action(OSD_PROGRAM, "brightness", 0);
        log_text(direction > 0
                     ? "bird-fixed-controls: brightness-up-direct\n"
                     : "bird-fixed-controls: brightness-down-direct\n");
    } else
        log_text("bird-fixed-controls: brightness-write-failed\n");
}

static int run_suspend(const char *source, const char *action) {
    int result;

    result = spawn_action(SUSPEND_PROGRAM, source, action);

    if (result == SPAWN_DISPATCHED) {
        trace_suspend(source, action, "dispatched");
        log_text(action ? (action[0] == 'c'
                               ? "bird-fixed-controls: lid-close\n"
                               : "bird-fixed-controls: lid-open\n")
                        : "bird-fixed-controls: power\n");
    } else if (result == SPAWN_EXEC_FAILED) {
        trace_suspend(source, action, "exec-failed");
        log_text("bird-fixed-controls: suspend-exec-failed\n");
    } else {
        trace_suspend(source, action, "spawn-failed");
        log_text("bird-fixed-controls: suspend-spawn-failed\n");
    }
    return result == SPAWN_DISPATCHED;
}

static void run_exit(void) {
    int result = spawn_action(EXIT_HELPER, 0, 0);

    if (result == SPAWN_DISPATCHED)
        log_text("bird-fixed-controls: content-exit\n");
    else if (result == SPAWN_EXEC_FAILED)
        log_text("bird-fixed-controls: content-exit-exec-failed\n");
    else
        log_text("bird-fixed-controls: content-exit-spawn-failed\n");
}

static void run_emergency(void) {
    int result = spawn_action(EMERGENCY_HELPER, 0, 0);

    if (result == SPAWN_DISPATCHED)
        log_text("bird-fixed-controls: emergency-recovery\n");
    else if (result == SPAWN_EXEC_FAILED)
        log_text("bird-fixed-controls: emergency-recovery-exec-failed\n");
    else
        log_text("bird-fixed-controls: emergency-recovery-spawn-failed\n");
}

static void event_path(char *path, int index) {
    static const char prefix[] = "/dev/input/event";
    int position = 0;

    while (prefix[position]) {
        path[position] = prefix[position];
        position++;
    }
    if (index >= 10) path[position++] = (char)('0' + index / 10);
    path[position++] = (char)('0' + index % 10);
    path[position] = '\0';
}

static int missing_sources(const struct input_source *sources) {
    int index;
    for (index = 0; index < SOURCE_COUNT; index++) {
        if (sources[index].fd < 0) return 1;
    }
    return 0;
}

static int input_words_equal(const u64 *left, const u64 *right, u32 count) {
    u32 index;

    for (index = 0U; index < count; index++) {
        if (left[index] != right[index]) return 0;
    }
    return 1;
}

static int h700_input_contract_matches(int fd) {
    static const u64 expected_key[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] =
        BIRD_DEVICE_INPUT_KEY_BITMAP_WORDS;
    static const u64 expected_ff[BIRD_DEVICE_INPUT_FF_BITMAP_WORD_COUNT] =
        BIRD_DEVICE_INPUT_FF_BITMAP_WORDS;
    struct input_id id;
    u64 event_bits = 0U;
    u64 key_bits[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] = {0U};
    u64 absolute_bits = 0U;
    u64 force_feedback_bits[BIRD_DEVICE_INPUT_FF_BITMAP_WORD_COUNT] = {0U};

    if (sys_ioctl(fd, EVIOCGID, &id) < 0 ||
        sys_ioctl(fd, EVIOCGBIT_EV, &event_bits) < 0 ||
        sys_ioctl(fd, EVIOCGBIT_KEY, key_bits) < 0 ||
        sys_ioctl(fd, EVIOCGBIT_ABS, &absolute_bits) < 0 ||
        sys_ioctl(fd, EVIOCGBIT_FF, force_feedback_bits) < 0)
        return 0;
    return id.bus == BIRD_DEVICE_INPUT_BUS &&
           id.vendor == BIRD_DEVICE_INPUT_VENDOR &&
           id.product == BIRD_DEVICE_INPUT_PRODUCT &&
           id.version == BIRD_DEVICE_INPUT_VERSION &&
           event_bits == BIRD_DEVICE_INPUT_EV_BITMAP &&
           input_words_equal(key_bits, expected_key,
                             BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT) &&
           absolute_bits == BIRD_DEVICE_INPUT_ABS_BITMAP &&
           input_words_equal(force_feedback_bits, expected_ff,
                             BIRD_DEVICE_INPUT_FF_BITMAP_WORD_COUNT);
}

static void try_input_event(struct input_source *sources, int event_index) {
    char path[32];
    char name[128];
    long fd;
    int source_index;

    if (!missing_sources(sources)) return;

    event_path(path, event_index);
    fd = sys_open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return;
    name[0] = '\0';
    if (sys_ioctl((int)fd, EVIOCGNAME_128, name) < 0) {
        sys_close((int)fd);
        return;
    }
    name[sizeof(name) - 1] = '\0';
    for (source_index = 0; source_index < SOURCE_COUNT; source_index++) {
        if (sources[source_index].fd < 0 &&
            strings_equal(name, sources[source_index].name) &&
            (source_index != SOURCE_GAMEPAD ||
             h700_input_contract_matches((int)fd))) {
            sources[source_index].fd = (int)fd;
            fd = -1;
            if (source_index == SOURCE_GAMEPAD)
                log_text("bird-fixed-controls: gamepad-ready\n");
            else if (source_index == SOURCE_VOLUME)
                log_text("bird-fixed-controls: volume-ready\n");
            else if (source_index == SOURCE_POWER)
                log_text("bird-fixed-controls: power-ready\n");
            else
                log_text("bird-fixed-controls: lid-ready\n");
            break;
        }
    }
    if (fd >= 0) sys_close((int)fd);
}

static void discover_inputs(struct input_source *sources) {
    int event_index;

    for (event_index = 0;
         event_index < EVENT_SCAN_COUNT && missing_sources(sources);
         event_index++)
        try_input_event(sources, event_index);
}

static int input_event_index(const char *name, u32 length) {
    static const char prefix[] = "event";
    u32 position = 0U;
    int index = 0;

    while (prefix[position]) {
        if (position >= length || name[position] != prefix[position])
            return -1;
        position++;
    }
    if (position >= length || name[position] < '0' || name[position] > '9')
        return -1;
    while (position < length && name[position] >= '0' && name[position] <= '9') {
        index = index * 10 + (name[position] - '0');
        if (index >= EVENT_SCAN_COUNT) return -1;
        position++;
    }
    if (position >= length || name[position] != '\0') return -1;
    return index;
}

static int open_input_watch(void) {
    int fd = (int)sys_inotify_init1(O_NONBLOCK | O_CLOEXEC);

    if (fd < 0) return -1;
    if (sys_inotify_add_watch(fd, "/dev/input", IN_CREATE | IN_MOVED_TO) < 0) {
        sys_close(fd);
        return -1;
    }
    return fd;
}

static int process_input_watch(int watch_fd, struct input_source *sources) {
    _Alignas(8) unsigned char buffer[512];

    for (;;) {
        long bytes = sys_read(watch_fd, buffer, sizeof(buffer));
        u64 offset = 0U;

        if (bytes == -EINTR) continue;
        if (bytes == -EAGAIN) return 1;
        if (bytes <= 0) return 0;
        while (offset + sizeof(struct inotify_event) <= (u64)bytes) {
            struct inotify_event *event =
                (struct inotify_event *)(buffer + offset);
            u64 record_bytes = sizeof(*event) + event->len;
            int index;

            if (record_bytes > (u64)bytes - offset) return 0;
            if (event->mask & IN_Q_OVERFLOW) {
                discover_inputs(sources);
            } else if ((event->mask & (IN_CREATE | IN_MOVED_TO)) &&
                       event->len) {
                index = input_event_index(event->name, event->len);
                if (index >= 0) try_input_event(sources, index);
            }
            offset += record_bytes;
        }
        if (offset != (u64)bytes) return 0;
        if (!missing_sources(sources)) return 1;
    }
}

static void clear_gamepad_state(struct control_state *state) {
    state->menu_held = 0;
    state->select_held = 0;
    state->start_held = 0;
    state->exit_latched = 0;
    state->emergency_latched = 0;
}

static void clear_volume_state(struct control_state *state) {
    state->volume_up_held = 0;
    state->volume_down_held = 0;
    state->repeat_direction = 0;
    state->repeat_at_ns = 0;
}

static void close_source(struct input_source *source, int source_index,
                         struct control_state *state) {
    if (source->fd >= 0) sys_close(source->fd);
    source->fd = -1;
    if (source_index == SOURCE_GAMEPAD) clear_gamepad_state(state);
    if (source_index == SOURCE_VOLUME) clear_volume_state(state);
    log_text("bird-fixed-controls: device-reconnect\n");
}

static int classify_poll_result(long result) {
    if (result >= 0) return POLL_RESULT_READY;
    if (result == -EINTR) return POLL_RESULT_INTERRUPTED;
    return POLL_RESULT_FAILED;
}

static int poll_descriptor_failed(short revents) {
    return (revents & (POLLERR | POLLHUP | POLLNVAL)) != 0;
}

static u64 next_poll_error_delay(u64 delay) {
    if (delay >= (u64)DISCOVERY_RETRY_NS / 2U)
        return (u64)DISCOVERY_RETRY_NS;
    return delay * 2U;
}

static u64 recover_poll_failure(struct input_source *sources,
                                struct control_state *state, u64 delay) {
    struct timespec timeout;
    int index;

    log_text("bird-fixed-controls: poll-failed-recovering\n");
    for (index = 0; index < SOURCE_COUNT; index++)
        close_source(&sources[index], index, state);
    ns_to_timespec(delay, &timeout);
    (void)sys_ppoll(0, 0, &timeout);
    return next_poll_error_delay(delay);
}

static void update_exit_combo(struct control_state *state) {
    if (!state->select_held || !state->start_held) {
        state->exit_latched = 0;
        state->emergency_latched = 0;
        return;
    }
    if (state->menu_held) {
        if (!state->emergency_latched) {
            state->emergency_latched = 1;
            state->exit_latched = 1;
            run_emergency();
        }
    } else if (!state->exit_latched) {
        state->exit_latched = 1;
        run_exit();
    }
}

static void handle_gamepad(const struct input_event *event,
                           struct control_state *state) {
    int pressed;

    if (event->type == EV_SYN && event->code == SYN_DROPPED) {
        clear_gamepad_state(state);
        return;
    }
    if (event->type != EV_KEY) return;
    pressed = event->value != 0;
    if (event->code == BTN_MODE)
        state->menu_held = pressed;
    else if (event->code == BTN_SELECT)
        state->select_held = pressed;
    else if (event->code == BTN_START)
        state->start_held = pressed;
    else
        return;
    update_exit_combo(state);
}

static void start_repeat(struct control_state *state, int direction) {
    state->repeat_direction = direction;
    state->repeat_at_ns = now_ns() + (u64)VOLUME_REPEAT_DELAY_NS;
}

static void handle_volume(const struct input_event *event,
                          struct control_state *state) {
    int direction;

    if (event->type == EV_SYN && event->code == SYN_DROPPED) {
        clear_volume_state(state);
        return;
    }
    if (event->type != EV_KEY) return;
    if (event->code == KEY_VOLUMEUP)
        direction = 1;
    else if (event->code == KEY_VOLUMEDOWN)
        direction = -1;
    else
        return;

    if (direction > 0)
        state->volume_up_held = event->value != 0;
    else
        state->volume_down_held = event->value != 0;

    if (event->value == 1) {
        if (state->menu_held) {
            state->repeat_direction = 0;
            state->repeat_at_ns = 0;
            run_brightness(direction);
        } else {
            run_volume(direction);
            start_repeat(state, direction);
        }
    } else if (event->value == 0 && state->repeat_direction == direction) {
        state->repeat_direction = 0;
        state->repeat_at_ns = 0;
    }
}

static void queue_power_suspend(struct suspend_state *suspend) {
    suspend->pending_suspend =
        suspend->pending_suspend == PENDING_SUSPEND_POWER
            ? PENDING_SUSPEND_NONE
            : PENDING_SUSPEND_POWER;
}

static void queue_lid_suspend(struct suspend_state *suspend, int closed) {
    suspend->pending_suspend =
        closed ? PENDING_SUSPEND_LID_CLOSE : PENDING_SUSPEND_NONE;
}

static void begin_resume(struct suspend_state *suspend, const char *source,
                         const char *action) {
    (void)sys_unlink(SUSPEND_RESUME_READY);
    if (!run_suspend(source, action)) return;
    suspend->resume_in_flight = 1;
    suspend->pending_suspend = PENDING_SUSPEND_NONE;
    suspend->resume_deadline_ns = now_ns() + RESUME_READY_TIMEOUT_NS;
}

static void handle_power(const struct input_event *event,
                         struct suspend_state *suspend) {
    if (event->type != EV_KEY || event->code != KEY_POWER ||
        event->value != 1)
        return;
    if (suspend->resume_in_flight) {
        queue_power_suspend(suspend);
        trace_suspend("power", 0,
                      suspend->pending_suspend == PENDING_SUSPEND_POWER
                          ? "queued"
                          : "cancelled");
    } else if (path_exists(POWER_SUSPEND_ACTIVE)) {
        begin_resume(suspend, "power", 0);
    } else {
        (void)run_suspend("power", 0);
    }
}

static void handle_lid(const struct input_event *event,
                       struct suspend_state *suspend) {
    if (event->type != EV_SW || event->code != SW_LID) return;
    if (suspend->resume_in_flight) {
        queue_lid_suspend(suspend, event->value == 1);
        trace_suspend("lid", event->value == 1 ? "close" : "open",
                      event->value == 1 ? "queued" : "cancelled");
    } else if (event->value == 1) {
        (void)run_suspend("lid", "close");
    } else if (event->value == 0) {
        begin_resume(suspend, "lid", "open");
    }
}

static int process_source(struct input_source *source, int source_index,
                          struct control_state *state,
                          struct suspend_state *suspend) {
    struct input_event events[16];
    long bytes;

    for (;;) {
        int count;
        int index;

        bytes = sys_read(source->fd, events, sizeof(events));
        if (bytes <= 0) break;
        count = (int)(bytes / (long)sizeof(events[0]));
        for (index = 0; index < count; index++) {
            if (source_index == SOURCE_GAMEPAD)
                handle_gamepad(&events[index], state);
            else if (source_index == SOURCE_VOLUME)
                handle_volume(&events[index], state);
            else if (source_index == SOURCE_POWER)
                handle_power(&events[index], suspend);
            else
                handle_lid(&events[index], suspend);
        }
    }
    if (bytes == 0) return 0;
    if (bytes == -EAGAIN || bytes == -EINTR) return 1;
    return 0;
}

static int complete_resume_state(struct suspend_state *suspend) {
    int pending = suspend->pending_suspend;

    suspend->resume_in_flight = 0;
    suspend->pending_suspend = PENDING_SUSPEND_NONE;
    suspend->resume_deadline_ns = 0;
    return pending;
}

static void process_resume_transition(struct suspend_state *suspend) {
    int pending;

    if (!suspend->resume_in_flight) return;
    if (!path_exists(SUSPEND_RESUME_READY)) {
        if (now_ns() < suspend->resume_deadline_ns) return;
        trace_suspend("coordinator", "resume", "timeout");
        (void)complete_resume_state(suspend);
        return;
    }
    (void)sys_unlink(SUSPEND_RESUME_READY);
    pending = complete_resume_state(suspend);
    trace_suspend("coordinator", "resume", "complete");
    if (pending == PENDING_SUSPEND_POWER)
        (void)run_suspend("power", 0);
    else if (pending == PENDING_SUSPEND_LID_CLOSE)
        (void)run_suspend("lid", "close");
}

static int repeat_is_held(const struct control_state *state) {
    if (state->repeat_direction > 0) return state->volume_up_held;
    if (state->repeat_direction < 0) return state->volume_down_held;
    return 0;
}

static void process_repeat(struct control_state *state) {
    u64 now;

    if (!state->repeat_direction || !repeat_is_held(state)) {
        state->repeat_direction = 0;
        state->repeat_at_ns = 0;
        return;
    }
    now = now_ns();
    if (now < state->repeat_at_ns) return;
    run_volume(state->repeat_direction);
    state->repeat_at_ns = now + (u64)VOLUME_REPEAT_INTERVAL_NS;
}

static const struct timespec *poll_timeout(
    const struct input_source *sources, const struct control_state *state,
    const struct suspend_state *suspend, int discovery_poll_fallback,
    struct timespec *timeout) {
    u64 delay = 0;

    if (discovery_poll_fallback && missing_sources(sources))
        delay = (u64)DISCOVERY_RETRY_NS;
    if (suspend->resume_in_flight &&
        (!delay || (u64)RESUME_READY_RETRY_NS < delay))
        delay = (u64)RESUME_READY_RETRY_NS;
    if (state->repeat_direction && repeat_is_held(state)) {
        u64 now = now_ns();
        u64 repeat_delay = state->repeat_at_ns > now
                               ? state->repeat_at_ns - now
                               : 0;
        if (!delay || repeat_delay < delay) delay = repeat_delay;
        if (!delay) {
            timeout->sec = 0;
            timeout->nsec = 0;
            return timeout;
        }
    }
    if (!delay) return 0;
    ns_to_timespec(delay, timeout);
    return timeout;
}

static void application(void) {
    struct input_source sources[SOURCE_COUNT] = {
        {-1, GAMEPAD_NAME},
        {-1, VOLUME_NAME},
        {-1, POWER_NAME},
        {-1, LID_NAME},
    };
    struct control_state state = {0};
    struct suspend_state suspend = {0, 0, 0};
    struct pollfd polls[SOURCE_COUNT + 1];
    u64 poll_error_delay_ns = 1000000UL;
    int watch_fd;

    kmsg_fd = (int)sys_open(KMSG_DEVICE, O_WRONLY | O_CLOEXEC);
    log_text("bird-fixed-controls: start\n");
    watch_fd = open_input_watch();
    discover_inputs(sources);
    for (;;) {
        struct timespec timeout;
        const struct timespec *timeout_pointer;
        long ready;
        u64 poll_count = SOURCE_COUNT;
        int rescan_required = 0;
        int index;

        if (missing_sources(sources) && watch_fd < 0) {
            watch_fd = open_input_watch();
            discover_inputs(sources);
        }
        for (index = 0; index < SOURCE_COUNT; index++) {
            polls[index].fd = sources[index].fd;
            polls[index].events = POLLIN;
            polls[index].revents = 0;
        }
        if (watch_fd >= 0) {
            polls[SOURCE_COUNT].fd = watch_fd;
            polls[SOURCE_COUNT].events = POLLIN;
            polls[SOURCE_COUNT].revents = 0;
            poll_count++;
        }
        timeout_pointer = poll_timeout(sources, &state, &suspend,
                                       watch_fd < 0, &timeout);
        ready = sys_ppoll(polls, poll_count, timeout_pointer);
        if (classify_poll_result(ready) == POLL_RESULT_INTERRUPTED) continue;
        if (classify_poll_result(ready) == POLL_RESULT_FAILED) {
            /* A bad auxiliary descriptor must not turn the fixed controls
             * service into a full-core spin. Drop every descriptor, clear
             * held-key state, sleep with capped backoff, and rediscover the
             * immutable devices on the next iteration. */
            if (watch_fd >= 0) sys_close(watch_fd);
            watch_fd = -1;
            poll_error_delay_ns = recover_poll_failure(
                sources, &state, poll_error_delay_ns);
            continue;
        }
        poll_error_delay_ns = 1000000UL;
        if (watch_fd >= 0) {
            if (poll_descriptor_failed(polls[SOURCE_COUNT].revents) ||
                ((polls[SOURCE_COUNT].revents & POLLIN) &&
                 !process_input_watch(watch_fd, sources))) {
                sys_close(watch_fd);
                watch_fd = -1;
                rescan_required = 1;
            }
        }
        for (index = 0; index < SOURCE_COUNT; index++) {
            if (sources[index].fd < 0) continue;
            if (poll_descriptor_failed(polls[index].revents)) {
                close_source(&sources[index], index, &state);
                rescan_required = 1;
                continue;
            }
            if ((polls[index].revents & POLLIN) &&
                !process_source(&sources[index], index, &state, &suspend)) {
                close_source(&sources[index], index, &state);
                rescan_required = 1;
            }
        }
        if (rescan_required && missing_sources(sources)) {
            if (watch_fd < 0) watch_fd = open_input_watch();
            discover_inputs(sources);
        }
        process_resume_transition(&suspend);
        process_repeat(&state);
    }
}

#ifndef BIRD_HOST_TEST
__attribute__((noreturn, visibility("default"))) void _start(void) {
    application();
    sys_exit(0);
}
#endif
