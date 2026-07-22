/*
 * Bird's fixed RG34XX-SP controls service for the mainline H700 kernel.
 *
 * This deliberately is not part of the launcher. It blocks in ppoll after
 * opening the three known input devices and owns only system-global actions:
 * volume, Menu+volume brightness, and power-button suspend. It never grabs an
 * input device, so games and media players continue to receive their controls.
 */

typedef unsigned short u16;
typedef unsigned long u64;
typedef signed int s32;
typedef signed long s64;

#define AT_FDCWD (-100)
#define F_OK 0
#define O_RDONLY 0
#define O_WRONLY 1
#define O_NONBLOCK 04000
#define O_TRUNC 01000
#define O_CLOEXEC 02000000
#define SIGCHLD 17
#define POLLIN 0x0001
#define EV_KEY 0x01
#define KEY_VOLUMEDOWN 114
#define KEY_VOLUMEUP 115
#define KEY_POWER 116
#define BTN_MODE 316
#define EVIOCGNAME_128 0x80804506UL

#define GAMEPAD_NAME "H700 Gamepad"
#define VOLUME_NAME "gpio-keys-volume"
#define POWER_NAME "axp20x-pek"
#define KMSG_DEVICE "/dev/kmsg"
#define BRIGHT_RAW_MAX "/sys/class/backlight/backlight/max_brightness"
#define BRIGHT_RAW_CURRENT "/sys/class/backlight/backlight/brightness"

#ifdef DANI_CLEAN_ROOT
#define VOLUME_SCRIPT "/opt/bird/volume.sh"
#define SUSPEND_SCRIPT "/opt/bird/suspend.sh"
#else
#define BRIGHT_CURRENT "/opt/muos/config/settings/general/brightness"
#define BRIGHT_INCREMENT "/opt/muos/config/settings/advanced/incbright"
#define BRIGHT_DEVICE_MAX "/opt/muos/device/config/screen/bright"
#define VOLUME_CURRENT "/opt/muos/config/settings/general/volume"
#define VOLUME_INCREMENT "/opt/muos/config/settings/advanced/incvolume"
#define VOLUME_MIN "/opt/muos/device/config/audio/min"
#define VOLUME_MAX "/opt/muos/device/config/audio/max"
#define AUDIO_READY "/opt/muos/config/device/audio/ready"
#define AUDIO_SOCKET "/run/pipewire-0"
#define AUDIO_SCRIPT "/opt/muos/script/device/audio.sh"
#define SUSPEND_SCRIPT "/opt/muos/script/system/suspend.sh"
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

static char *const fixed_env[] = {
    "HOME=/root",
    "LANG=C",
    "PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/muos/bin",
    "SHELL=/bin/sh",
    "USER=root",
    0,
};

static int kmsg_fd = -1;
#ifdef DANI_CLEAN_ROOT
static int clean_brightness = -1;
#endif

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

static long sys_faccessat(const char *path) {
    return syscall6(48, AT_FDCWD, (long)path, F_OK, 0, 0, 0);
}

static long sys_ppoll(struct pollfd *fds, u64 count) {
    return syscall6(73, (long)fds, (long)count, 0, 0, 0, 0);
}

static long sys_clone(void) {
    return syscall6(220, SIGCHLD, 0, 0, 0, 0, 0);
}

static long sys_execve(const char *path, char *const argv[]) {
    return syscall6(221, (long)path, (long)argv, (long)fixed_env, 0, 0, 0);
}

static long sys_wait4(long pid, int *status) {
    return syscall6(260, pid, (long)status, 0, 0, 0, 0);
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

static void log_text(const char *text) {
    write_all(1, text, string_length(text));
}

static void log_kernel(const char *text) {
    if (kmsg_fd >= 0) write_all(kmsg_fd, text, string_length(text));
}

static int read_integer(const char *path, int fallback) {
    char buffer[32];
    long fd = sys_open(path, O_RDONLY | O_CLOEXEC);
    long bytes;
    int value = 0;
    int position = 0;
    int negative = 0;

    if (fd < 0) return fallback;
    bytes = sys_read((int)fd, buffer, sizeof(buffer));
    sys_close((int)fd);
    if (bytes <= 0) return fallback;
    if (buffer[position] == '-') {
        negative = 1;
        position++;
    }
    if (position >= bytes || buffer[position] < '0' ||
        buffer[position] > '9')
        return fallback;
    while (position < bytes && buffer[position] >= '0' &&
           buffer[position] <= '9') {
        value = value * 10 + buffer[position] - '0';
        position++;
    }
    return negative ? -value : value;
}

static int write_integer(const char *path, int value) {
    char buffer[24];
    char *cursor = &buffer[23];
    unsigned int magnitude;
    long fd;

    *cursor-- = '\n';
    if (value < 0) {
        magnitude = (unsigned int)(-value);
    } else {
        magnitude = (unsigned int)value;
    }
    do {
        *cursor-- = (char)('0' + magnitude % 10U);
        magnitude /= 10U;
    } while (magnitude);
    if (value < 0) *cursor-- = '-';
    cursor++;

    fd = sys_open(path, O_WRONLY | O_TRUNC | O_CLOEXEC);
    if (fd < 0) return 0;
    write_all((int)fd, cursor, (u64)(&buffer[24] - cursor));
    sys_close((int)fd);
    return 1;
}

static int clamp(int value, int minimum, int maximum) {
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
}

static int adjust_brightness(int direction) {
#ifdef DANI_CLEAN_ROOT
    int raw_max = read_integer(BRIGHT_RAW_MAX, 255);
    int raw_current = read_integer(BRIGHT_RAW_CURRENT, 1);
    int raw;

    if (raw_max <= 0) raw_max = 255;
    if (clean_brightness < 0)
        clean_brightness = clamp((raw_current * 100 + raw_max / 2) / raw_max,
                                 1, 100);
    clean_brightness = clamp(clean_brightness + direction * 5, 1, 100);
    raw = (clean_brightness * raw_max + 50) / 100;
    if (raw < 1) raw = 1;
    return write_integer(BRIGHT_RAW_CURRENT, raw);
#else
    int current = read_integer(BRIGHT_CURRENT, 1);
    int increment = read_integer(BRIGHT_INCREMENT, 16);
    int device_max = read_integer(BRIGHT_DEVICE_MAX, 255);
    int raw_max = read_integer(BRIGHT_RAW_MAX, 255);
    int level;
    int raw;

    if (increment <= 0) increment = 16;
    if (device_max <= 0) device_max = 255;
    if (raw_max <= 0) raw_max = 255;
    level = clamp(current + direction * increment, 1, device_max);
    raw = (level * raw_max + device_max / 2) / device_max;
    if (raw < 1) raw = 1;
    if (!write_integer(BRIGHT_RAW_CURRENT, raw)) return 0;
    write_integer(BRIGHT_CURRENT, level);
    return 1;
#endif
}

static int run_action(const char *path, const char *argument) {
    long pid;
    int status = 0;
    char *const argv_with_argument[] = {(char *)path, (char *)argument, 0};
    char *const argv_without_argument[] = {(char *)path, 0};

    pid = sys_clone();
    if (pid < 0) return -1;
    if (pid == 0) {
        if (argument)
            sys_execve(path, argv_with_argument);
        else
            sys_execve(path, argv_without_argument);
        sys_exit(127);
    }
    if (sys_wait4(pid, &status) < 0) return -1;
    return status;
}

static int adjust_volume(int direction) {
#ifdef DANI_CLEAN_ROOT
    return run_action(VOLUME_SCRIPT, direction > 0 ? "U" : "D") == 0;
#else
    int current = read_integer(VOLUME_CURRENT, 45);
    int increment = read_integer(VOLUME_INCREMENT, 8);
    int minimum = read_integer(VOLUME_MIN, 0);
    int maximum = read_integer(VOLUME_MAX, 100);

    if (increment <= 0) increment = 8;
    if (maximum < minimum) maximum = 100;
    if (sys_faccessat(AUDIO_SOCKET) == 0 &&
        read_integer(AUDIO_READY, 0) == 1) {
        return run_action(AUDIO_SCRIPT, direction > 0 ? "U" : "D") == 0;
    }
    return write_integer(
        VOLUME_CURRENT,
        clamp(current + direction * increment, minimum, maximum));
#endif
}

static void event_path(char *path, int index) {
    static const char prefix[] = "/dev/input/event";
    int position = 0;
    int digit;

    while (prefix[position]) {
        path[position] = prefix[position];
        position++;
    }
    if (index >= 10) {
        digit = index / 10;
        path[position++] = (char)('0' + digit);
    }
    path[position++] = (char)('0' + index % 10);
    path[position] = '\0';
}

static void discover_inputs(struct input_source *sources, int count) {
    char path[32];
    char name[128];
    int index;
    int missing = 0;
    int source;

    for (source = 0; source < count; source++) {
        if (sources[source].fd < 0) missing++;
    }
    if (!missing) return;

    for (index = 0; index < 32; index++) {
        long fd;
        event_path(path, index);
        fd = sys_open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;
        name[0] = '\0';
        if (sys_ioctl((int)fd, EVIOCGNAME_128, name) < 0) {
            sys_close((int)fd);
            continue;
        }
        name[sizeof(name) - 1] = '\0';
        for (source = 0; source < count; source++) {
            if (sources[source].fd < 0 &&
                strings_equal(name, sources[source].name)) {
                sources[source].fd = (int)fd;
                fd = -1;
                missing--;
                if (source == 0)
                    log_kernel("<6>bird-controls: gamepad-ready\n");
                else if (source == 1)
                    log_kernel("<6>bird-controls: volume-keys-ready\n");
                else
                    log_kernel("<6>bird-controls: power-key-ready\n");
                break;
            }
        }
        if (fd >= 0) sys_close((int)fd);
        if (!missing) return;
    }
}

static void handle_gamepad(const struct input_event *event, int *menu_held) {
    if (event->type == EV_KEY && event->code == BTN_MODE) {
        *menu_held = event->value != 0;
        if (event->value == 1)
            log_kernel("<6>bird-controls: menu-held\n");
        else if (event->value == 0)
            log_kernel("<6>bird-controls: menu-released\n");
    }
}

static void handle_volume(const struct input_event *event, int menu_held) {
    int direction;

    if (event->type != EV_KEY || event->value == 0) return;
    if (event->code == KEY_VOLUMEUP)
        direction = 1;
    else if (event->code == KEY_VOLUMEDOWN)
        direction = -1;
    else
        return;
    if (menu_held) {
        if (adjust_brightness(direction))
            log_kernel(direction > 0
                           ? "<6>bird-controls: brightness-up-applied\n"
                           : "<6>bird-controls: brightness-down-applied\n");
        else
            log_kernel("<3>bird-controls: brightness-write-failed\n");
    } else {
        if (adjust_volume(direction))
            log_kernel(direction > 0
                           ? "<6>bird-controls: volume-up-applied\n"
                           : "<6>bird-controls: volume-down-applied\n");
        else
            log_kernel("<3>bird-controls: volume-action-failed\n");
    }
}

static void handle_power(const struct input_event *event,
                         int *power_pressed) {
    if (event->type != EV_KEY || event->code != KEY_POWER) return;
    if (event->value != 0) {
        *power_pressed = 1;
    } else if (*power_pressed) {
        *power_pressed = 0;
        log_kernel("<6>bird-controls: suspend-request\n");
        run_action(SUSPEND_SCRIPT, 0);
    }
}

static void process_source(struct input_source *source, int source_index,
                           int *menu_held, int *power_pressed) {
    struct input_event events[16];
    long bytes;
    int count;
    int index;

    while ((bytes = sys_read(source->fd, events, sizeof(events))) > 0) {
        count = (int)(bytes / (long)sizeof(events[0]));
        for (index = 0; index < count; index++) {
            if (source_index == 0)
                handle_gamepad(&events[index], menu_held);
            else if (source_index == 1)
                handle_volume(&events[index], *menu_held);
            else
                handle_power(&events[index], power_pressed);
        }
    }
    if (bytes == 0) {
        sys_close(source->fd);
        source->fd = -1;
    }
}

static void application(void) {
    struct input_source sources[3] = {
        {-1, GAMEPAD_NAME},
        {-1, VOLUME_NAME},
        {-1, POWER_NAME},
    };
    struct pollfd polls[3];
    int menu_held = 0;
    int power_pressed = 0;
    int index;

    kmsg_fd = (int)sys_open(KMSG_DEVICE, O_WRONLY | O_CLOEXEC);
    log_text("bird-controls: start\n");
    log_kernel("<6>bird-controls: start\n");
    for (;;) {
        discover_inputs(sources, 3);
        for (index = 0; index < 3; index++) {
            polls[index].fd = sources[index].fd;
            polls[index].events = POLLIN;
            polls[index].revents = 0;
        }
        if (sources[0].fd < 0 && sources[1].fd < 0 && sources[2].fd < 0) {
            sys_nanosleep(250000000L);
            continue;
        }
        if (sys_ppoll(polls, 3) < 0) continue;
        for (index = 0; index < 3; index++) {
            if (sources[index].fd >= 0 && (polls[index].revents & POLLIN))
                process_source(&sources[index], index, &menu_held,
                               &power_pressed);
        }
    }
}

__attribute__((noreturn, visibility("default"))) void _start(void) {
    application();
    sys_exit(0);
}
