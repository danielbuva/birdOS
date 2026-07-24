/*
 * Bird's fixed RG34XX-SP global-controls process for ROCKNIX 20260701.
 *
 * The stock input_sense service expands into Bash, grep, four evtest workers,
 * and several coordinating shells.  This freestanding AArch64 process opens
 * only the four immutable internal input devices and preserves the subset of
 * global policy used by Bird:
 *
 *   - dedicated volume keys, including 300 ms / 100 ms hold repeat;
 *   - Menu + volume for a direct fixed-panel brightness step, including the
 *     hardware's lowest nonzero raw level;
 *   - power and lid events through ROCKNIX's proven fake-suspend helper; and
 *   - L1 + Select + Start through ROCKNIX's current process-kill contract.
 *
 * It never grabs the H700 gamepad, so Bird and selected applications continue
 * to receive their normal controls.  Event numbers are treated only as a fast
 * bounded search space: every descriptor is accepted by its kernel name.
 */

typedef unsigned short u16;
typedef unsigned long u64;
typedef signed int s32;
typedef signed long s64;

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_NONBLOCK 04000
#define O_CLOEXEC 02000000
#define SIGCHLD 17
#define POLLIN 0x0001
#define POLLERR 0x0008
#define POLLHUP 0x0010
#define POLLNVAL 0x0020
#define WNOHANG 1
#define EAGAIN 11
#define EINTR 4
#define CLOCK_BOOTTIME 7

#define EV_SYN 0x00
#define EV_KEY 0x01
#define EV_SW 0x05
#define SYN_DROPPED 3
#define SW_LID 0
#define KEY_VOLUMEDOWN 114
#define KEY_VOLUMEUP 115
#define KEY_POWER 116
#define BTN_TL 310
#define BTN_SELECT 314
#define BTN_START 315
#define BTN_MODE 316

#define EVIOCGNAME_128 0x80804506UL

#define GAMEPAD_NAME "H700 Gamepad"
#define VOLUME_NAME "gpio-keys-volume"
#define POWER_NAME "axp20x-pek"
#define LID_NAME "gpio-keys-lid"

#define VOLUME_PROGRAM "/usr/bin/volume"
#define BRIGHTNESS_CURRENT "/sys/class/backlight/backlight/brightness"
#define BRIGHTNESS_MAX "/sys/class/backlight/backlight/max_brightness"
#define SUSPEND_PROGRAM "/storage/.config/bird/bird-suspend.sh"
#define EXIT_HELPER "/storage/.config/bird/bird-fixed-control-exit.sh"
#define KMSG_DEVICE "/dev/kmsg"

#define SOURCE_GAMEPAD 0
#define SOURCE_VOLUME 1
#define SOURCE_POWER 2
#define SOURCE_LID 3
#define SOURCE_COUNT 4
#define EVENT_SCAN_COUNT 32

#define VOLUME_REPEAT_DELAY_NS 300000000L
#define VOLUME_REPEAT_INTERVAL_NS 100000000L
#define DISCOVERY_RETRY_NS 250000000L

struct timespec {
    s64 sec;
    s64 nsec;
};

struct pollfd {
    int fd;
    short events;
    short revents;
};

struct input_event {
    s64 seconds;
    s64 microseconds;
    u16 type;
    u16 code;
    s32 value;
};

struct input_source {
    int fd;
    const char *name;
};

struct control_state {
    int menu_held;
    int l1_held;
    int select_held;
    int start_held;
    int exit_latched;
    int volume_up_held;
    int volume_down_held;
    int repeat_direction;
    u64 repeat_at_ns;
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

static long sys_open(const char *path, int flags) {
    return syscall6(56, AT_FDCWD, (long)path, flags, 0, 0, 0);
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

static long sys_ioctl(int fd, u64 request, void *argument) {
    return syscall6(29, fd, (long)request, (long)argument, 0, 0, 0);
}

static long sys_ppoll(struct pollfd *fds, u64 count,
                      const struct timespec *timeout) {
    return syscall6(73, (long)fds, (long)count, (long)timeout, 0, 0, 0);
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

/*
 * Detach every potentially long-running action with a double fork.  The short
 * intermediate child is reaped synchronously; the action itself is adopted by
 * PID 1 and can sleep for ROCKNIX's full fake-suspend timeout without blocking
 * input processing or leaving a daemon-owned zombie.
 */
static int spawn_action(const char *path, const char *first,
                        const char *second) {
    long child;
    int status = 0;

    child = sys_clone();
    if (child < 0) return 0;
    if (child == 0) {
        long action = sys_clone();
        if (action < 0) sys_exit(127);
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
            sys_exit(127);
        }
        sys_exit(0);
    }
    if (sys_wait4(child, &status, 0) < 0) return 0;
    return status == 0;
}

static void run_volume(int direction) {
    if (spawn_action(VOLUME_PROGRAM, direction > 0 ? "up" : "down", 0))
        log_text(direction > 0
                     ? "bird-fixed-controls: volume-up\n"
                     : "bird-fixed-controls: volume-down\n");
    else
        log_text("bird-fixed-controls: volume-spawn-failed\n");
}

static void run_brightness(int direction) {
    u64 current;
    u64 maximum;
    u64 percent;
    u64 target;
    u64 raw;
    if (!read_number(BRIGHTNESS_CURRENT, &current) ||
        !read_number(BRIGHTNESS_MAX, &maximum) || !maximum) {
        log_text("bird-fixed-controls: brightness-read-failed\n");
        return;
    }
    percent = (current * 100U + maximum / 2U) / maximum;
    if (direction > 0) {
        target = percent < 5U ? 5U : percent + 5U;
        if (target > 100U) target = 100U;
        raw = (target * maximum + 50U) / 100U;
    } else if (percent <= 5U) {
        /* Raw one is the fixed panel's lowest lit level. It is intentionally
         * distinct from zero, which belongs to display power-off. */
        raw = 1U;
    } else {
        target = percent - 5U;
        raw = (target * maximum + 50U) / 100U;
    }
    if (raw < 1U) raw = 1U;
    if (raw > maximum) raw = maximum;
    if (write_number(BRIGHTNESS_CURRENT, raw))
        log_text(direction > 0
                     ? "bird-fixed-controls: brightness-up-direct\n"
                     : "bird-fixed-controls: brightness-down-direct\n");
    else
        log_text("bird-fixed-controls: brightness-write-failed\n");
}

static void run_suspend(const char *source, const char *action) {
    if (spawn_action(SUSPEND_PROGRAM, source, action))
        log_text(action ? (action[0] == 'c'
                               ? "bird-fixed-controls: lid-close\n"
                               : "bird-fixed-controls: lid-open\n")
                        : "bird-fixed-controls: power\n");
    else
        log_text("bird-fixed-controls: suspend-spawn-failed\n");
}

static void run_exit(void) {
    if (spawn_action(EXIT_HELPER, 0, 0))
        log_text("bird-fixed-controls: content-exit\n");
    else
        log_text("bird-fixed-controls: content-exit-spawn-failed\n");
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

static void discover_inputs(struct input_source *sources) {
    char path[32];
    char name[128];
    int event_index;

    if (!missing_sources(sources)) return;
    for (event_index = 0; event_index < EVENT_SCAN_COUNT; event_index++) {
        long fd;
        int source_index;

        event_path(path, event_index);
        fd = sys_open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;
        name[0] = '\0';
        if (sys_ioctl((int)fd, EVIOCGNAME_128, name) < 0) {
            sys_close((int)fd);
            continue;
        }
        name[sizeof(name) - 1] = '\0';
        for (source_index = 0; source_index < SOURCE_COUNT; source_index++) {
            if (sources[source_index].fd < 0 &&
                strings_equal(name, sources[source_index].name)) {
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
}

static void clear_gamepad_state(struct control_state *state) {
    state->menu_held = 0;
    state->l1_held = 0;
    state->select_held = 0;
    state->start_held = 0;
    state->exit_latched = 0;
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

static void update_exit_combo(struct control_state *state) {
    if (state->l1_held && state->select_held && state->start_held) {
        if (!state->exit_latched) {
            state->exit_latched = 1;
            run_exit();
        }
    } else {
        state->exit_latched = 0;
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
    else if (event->code == BTN_TL)
        state->l1_held = pressed;
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

static void handle_power(const struct input_event *event) {
    if (event->type == EV_KEY && event->code == KEY_POWER &&
        event->value == 1)
        run_suspend("power", 0);
}

static void handle_lid(const struct input_event *event) {
    if (event->type != EV_SW || event->code != SW_LID) return;
    if (event->value == 1)
        run_suspend("lid", "close");
    else if (event->value == 0)
        run_suspend("lid", "open");
}

static int process_source(struct input_source *source, int source_index,
                          struct control_state *state) {
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
                handle_power(&events[index]);
            else
                handle_lid(&events[index]);
        }
    }
    if (bytes == 0) return 0;
    if (bytes == -EAGAIN || bytes == -EINTR) return 1;
    return 0;
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
    struct timespec *timeout) {
    u64 delay = 0;

    if (missing_sources(sources)) delay = (u64)DISCOVERY_RETRY_NS;
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
    struct control_state state = {0, 0, 0, 0, 0, 0, 0, 0, 0};
    struct pollfd polls[SOURCE_COUNT];

    kmsg_fd = (int)sys_open(KMSG_DEVICE, O_WRONLY | O_CLOEXEC);
    log_text("bird-fixed-controls: start\n");
    for (;;) {
        struct timespec timeout;
        const struct timespec *timeout_pointer;
        long ready;
        int index;

        discover_inputs(sources);
        for (index = 0; index < SOURCE_COUNT; index++) {
            polls[index].fd = sources[index].fd;
            polls[index].events = POLLIN;
            polls[index].revents = 0;
        }
        timeout_pointer = poll_timeout(sources, &state, &timeout);
        ready = sys_ppoll(polls, SOURCE_COUNT, timeout_pointer);
        if (ready < 0 && ready != -EINTR) continue;
        for (index = 0; index < SOURCE_COUNT; index++) {
            if (sources[index].fd < 0) continue;
            if (polls[index].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                close_source(&sources[index], index, &state);
                continue;
            }
            if ((polls[index].revents & POLLIN) &&
                !process_source(&sources[index], index, &state))
                close_source(&sources[index], index, &state);
        }
        process_repeat(&state);
    }
}

__attribute__((noreturn, visibility("default"))) void _start(void) {
    application();
    sys_exit(0);
}
