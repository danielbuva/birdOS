/*
 * Fixed RG34XX-SP power policy and low-battery warning.
 *
 * Freestanding AArch64 Linux: no libc, shell, configuration parser or
 * two-second status polling.  The process applies the one known idle policy,
 * then sleeps in ppoll(2) until the kernel reports a power-supply event.  The
 * AXP717 driver has no capacity-change interrupt or delayed work, so one
 * 40-second capacity check remains while discharging.  That check both detects
 * the 25-percent crossing and preserves ROCKNIX's warning cadence; it is
 * completely disarmed on external power.
 *
 * ROCKNIX's H700 profile disables charging LED changes, and both its charger
 * branch and default battery branch resolve to simple_ondemand.  Therefore a
 * power event never rewrites GPU policy here: runemu remains the sole owner of
 * application-scoped performance changes.
 */

typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long u64;
typedef signed long s64;

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_CREAT 0100
#define O_TRUNC 01000
#define O_NONBLOCK 04000

#define POLLIN 0x0001
#define POLLERR 0x0008
#define POLLHUP 0x0010
#define AF_NETLINK 16
#define SOCK_DGRAM 2
#define NETLINK_KOBJECT_UEVENT 15
#define CLOCK_BOOTTIME 7

#define LOW_PERCENT 25
#define LOW_REMINDER_SECONDS 40

#define CPU_GOVERNOR \
    "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"
#define CPU_MIN "/sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq"
#define CPU_MAX "/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
#define GPU_ROOT "/sys/devices/platform/soc/1800000.gpu/devfreq/1800000.gpu"
#define GPU_GOVERNOR GPU_ROOT "/governor"
#define GPU_MIN GPU_ROOT "/min_freq"
#define GPU_MAX GPU_ROOT "/max_freq"
#define BATTERY_STATUS "/sys/class/power_supply/battery/status"
#define BATTERY_CAPACITY "/sys/class/power_supply/battery/capacity"
#define CONTENT_KILL_DATA "/tmp/.process-kill-data"
#define GPU_PERFORMANCE_LEVEL "/tmp/.gpu_performance_level"
#define GREEN_LED "/sys/class/leds/green:power/brightness"
#define RED_LED "/sys/class/leds/red:status/brightness"
#define POWER_LOG "/storage/bird-data/MUOS/Bird/log/powerstate-latest.log"

struct timespec {
    s64 sec;
    s64 nsec;
};

struct itimerspec {
    struct timespec interval;
    struct timespec value;
};

struct pollfd {
    int fd;
    short events;
    short revents;
};

struct sockaddr_nl {
    u16 family;
    u16 padding;
    u32 pid;
    u32 groups;
};

static int log_fd = -1;
static int event_fd = -1;
static int timer_fd = -1;
static int discharging = -1;
static int capacity = -1;
static int low_state;
static int flash_phase;
static int saved_green;
static int saved_red;

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

static long sys_open(const char *path, int flags, int mode) {
    return syscall6(56, AT_FDCWD, (long)path, flags, mode, 0, 0);
}

static long sys_close(int fd) {
    return syscall6(57, fd, 0, 0, 0, 0, 0);
}

static long sys_read(int fd, void *buffer, u64 length) {
    return syscall6(63, fd, (long)buffer, (long)length, 0, 0, 0);
}

static long sys_write(int fd, const void *buffer, u64 length) {
    return syscall6(64, fd, (long)buffer, (long)length, 0, 0, 0);
}

static long sys_ppoll(struct pollfd *fds, u64 count) {
    return syscall6(73, (long)fds, (long)count, 0, 0, 0, 0);
}

static long sys_timerfd_create(int clock, int flags) {
    return syscall6(85, clock, flags, 0, 0, 0, 0);
}

static long sys_timerfd_settime(int fd, const struct itimerspec *value) {
    return syscall6(86, fd, 0, (long)value, 0, 0, 0);
}

static long sys_socket(int domain, int type, int protocol) {
    return syscall6(198, domain, type, protocol, 0, 0, 0);
}

static long sys_bind(int fd, const struct sockaddr_nl *address, u32 length) {
    return syscall6(200, fd, (long)address, length, 0, 0, 0);
}

static void sys_exit(int status) __attribute__((noreturn));
static void sys_exit(int status) {
    syscall6(93, status, 0, 0, 0, 0, 0);
    for (;;) {}
}

static u64 string_length(const char *text) {
    u64 length = 0;
    while (text[length]) length++;
    return length;
}

static int string_starts_with(const char *text, const char *prefix) {
    while (*prefix) {
        if (*text++ != *prefix++) return 0;
    }
    return 1;
}

static int string_equal_bounded(const char *left, u64 left_length,
                                const char *right) {
    u64 index = 0;
    while (index < left_length && right[index]) {
        if (left[index] != right[index]) return 0;
        index++;
    }
    return index == left_length && right[index] == 0;
}

static void write_all(int fd, const char *buffer, u64 length) {
    while (length) {
        long written = sys_write(fd, buffer, length);
        if (written <= 0) return;
        buffer += written;
        length -= (u64)written;
    }
}

static void log_text(const char *text) {
    u64 length = string_length(text);
    write_all(1, text, length);
    if (log_fd >= 0) write_all(log_fd, text, length);
}

static void log_number(u64 value) {
    char buffer[24];
    int position = 23;
    buffer[position--] = 0;
    if (!value) buffer[position--] = '0';
    while (value) {
        buffer[position--] = (char)('0' + value % 10U);
        value /= 10U;
    }
    buffer[23] = 0;
    log_text(&buffer[position + 1]);
}

static long read_text(const char *path, char *buffer, u64 size) {
    long fd = sys_open(path, O_RDONLY | O_NONBLOCK, 0);
    long count;
    if (fd < 0 || size < 2U) return -1;
    count = sys_read((int)fd, buffer, size - 1U);
    sys_close((int)fd);
    if (count <= 0) return -1;
    while (count > 0 &&
           (buffer[count - 1] == '\n' || buffer[count - 1] == '\r'))
        count--;
    buffer[count] = 0;
    return count;
}

static int write_text(const char *path, const char *value) {
    long fd = sys_open(path, O_WRONLY | O_NONBLOCK, 0);
    u64 length = string_length(value);
    long written;
    if (fd < 0) return -1;
    written = sys_write((int)fd, value, length);
    sys_close((int)fd);
    return written == (long)length ? 0 : -1;
}

static int path_exists(const char *path) {
    long fd = sys_open(path, O_RDONLY | O_NONBLOCK, 0);
    if (fd < 0) return 0;
    sys_close((int)fd);
    return 1;
}

static int read_integer(const char *path) {
    char value[32];
    long count = read_text(path, value, sizeof(value));
    long offset = 0;
    int result = 0;
    int digits = 0;
    if (count <= 0) return -1;
    while (offset < count && (value[offset] == ' ' || value[offset] == '\t'))
        offset++;
    while (offset < count && value[offset] >= '0' && value[offset] <= '9') {
        result = result * 10 + value[offset] - '0';
        offset++;
        digits++;
    }
    return digits ? result : -1;
}

static void log_file_value(const char *name, const char *path) {
    char value[64];
    log_text(name);
    if (read_text(path, value, sizeof(value)) > 0)
        log_text(value);
    else
        log_text("unavailable");
}

static void apply_initial_policy(void) {
    int cpu_result;
    int gpu_result;

    /* A service restart must not overwrite runemu/player policy.  The exact
     * content wrappers publish at least one marker while they own it. */
    if (path_exists(CONTENT_KILL_DATA) || path_exists(GPU_PERFORMANCE_LEVEL)) {
        log_text("policy write=skipped-active-content ");
        log_file_value("cpu_governor=", CPU_GOVERNOR);
        log_text(" ");
        log_file_value("gpu_governor=", GPU_GOVERNOR);
        log_text("\n");
        return;
    }

    cpu_result = write_text(CPU_GOVERNOR, "ondemand\n");
    gpu_result = write_text(GPU_GOVERNOR, "simple_ondemand\n");

    log_text("policy cpu_write=");
    log_text(cpu_result == 0 ? "ready" : "failed");
    log_text(" gpu_write=");
    log_text(gpu_result == 0 ? "ready" : "failed");
    log_text(" ");
    log_file_value("cpu_governor=", CPU_GOVERNOR);
    log_text(" ");
    log_file_value("cpu_min_khz=", CPU_MIN);
    log_text(" ");
    log_file_value("cpu_max_khz=", CPU_MAX);
    log_text(" ");
    log_file_value("gpu_governor=", GPU_GOVERNOR);
    log_text(" ");
    log_file_value("gpu_min_hz=", GPU_MIN);
    log_text(" ");
    log_file_value("gpu_max_hz=", GPU_MAX);
    log_text("\n");
}

static int read_discharging(void) {
    char status[32];
    if (read_text(BATTERY_STATUS, status, sizeof(status)) <= 0) return -1;
    return string_starts_with(status, "Discharging") ? 1 : 0;
}

static void arm_timer(s64 seconds, s64 nanoseconds) {
    struct itimerspec value;
    value.interval.sec = 0;
    value.interval.nsec = 0;
    value.value.sec = seconds;
    value.value.nsec = nanoseconds;
    sys_timerfd_settime(timer_fd, &value);
}

static void disarm_timer(void) {
    arm_timer(0, 0);
}

static void write_led(const char *path, int value) {
    write_text(path, value ? "1\n" : "0\n");
}

static void set_leds(int green, int red) {
    write_led(GREEN_LED, green);
    write_led(RED_LED, red);
}

static void restore_leds(void) {
    if (saved_green >= 0) write_led(GREEN_LED, saved_green);
    if (saved_red >= 0) write_led(RED_LED, saved_red);
    flash_phase = 0;
}

static void start_flash(void) {
    saved_green = read_integer(GREEN_LED);
    saved_red = read_integer(RED_LED);
    if (saved_green < 0 || saved_red < 0) {
        log_text("warning led=unavailable\n");
        arm_timer(LOW_REMINDER_SECONDS, 0);
        return;
    }
    set_leds(0, 1);
    flash_phase = 1;
    log_text("warning battery=low led=red-flash\n");
    arm_timer(0, 500000000L);
}

static void advance_flash(void) {
    if (flash_phase == 1 || flash_phase == 3 || flash_phase == 5)
        set_leds(0, 0);
    else if (flash_phase == 2 || flash_phase == 4)
        set_leds(0, 1);
    else {
        restore_leds();
        if (discharging == 1) arm_timer(LOW_REMINDER_SECONDS, 0);
        return;
    }
    flash_phase++;
    arm_timer(0, 500000000L);
}

static void log_power_state(const char *reason) {
    log_text(reason);
    log_text(" status=");
    if (discharging < 0)
        log_text("unavailable");
    else
        log_text(discharging ? "discharging" : "external-power");
    log_text(" capacity=");
    if (capacity < 0)
        log_text("unavailable");
    else
        log_number((u64)capacity);
    log_text(" low=");
    log_text(low_state ? "yes" : "no");
    log_text("\n");
}

static void refresh_power_state(int log_mode) {
    int old_discharging = discharging;
    int old_capacity = capacity;
    int was_low = low_state;
    int now_low;

    discharging = read_discharging();
    capacity = read_integer(BATTERY_CAPACITY);
    now_low = discharging == 1 && capacity >= 0 && capacity <= LOW_PERCENT;
    low_state = now_low;

    if (!now_low && was_low && flash_phase) restore_leds();

    if (log_mode == 2 ||
        (log_mode == 1 && (discharging != old_discharging ||
                           capacity != old_capacity)))
        log_power_state(log_mode == 2 ? "initial" : "event");
}

static int event_is_power_supply(const char *event, u64 length) {
    u64 offset = 0;
    while (offset < length) {
        u64 field_length = 0;
        while (offset + field_length < length && event[offset + field_length])
            field_length++;
        if (string_equal_bounded(event + offset, field_length,
                                 "SUBSYSTEM=power_supply"))
            return 1;
        offset += field_length + 1U;
    }
    return 0;
}

static int open_power_events(void) {
    struct sockaddr_nl address;
    long fd = sys_socket(AF_NETLINK, SOCK_DGRAM | O_NONBLOCK,
                         NETLINK_KOBJECT_UEVENT);
    if (fd < 0) return -1;
    address.family = AF_NETLINK;
    address.padding = 0;
    address.pid = 0;
    address.groups = 1;
    if (sys_bind((int)fd, &address, sizeof(address)) < 0) {
        sys_close((int)fd);
        return -1;
    }
    return (int)fd;
}

static void run(void) __attribute__((used, noinline, noreturn));
static void run(void) {
    struct pollfd events[2];

    log_fd = (int)sys_open(POWER_LOG, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    log_text("Bird fixed powerstate start capacity_check_s=40 threshold=25\n");

    event_fd = open_power_events();
    timer_fd = (int)sys_timerfd_create(CLOCK_BOOTTIME, O_NONBLOCK);
    if (event_fd < 0 || timer_fd < 0) {
        log_text("fatal power-event or timerfd unavailable\n");
        sys_exit(2);
    }

    apply_initial_policy();
    refresh_power_state(2);
    if (discharging == 1) arm_timer(LOW_REMINDER_SECONDS, 0);

    events[0].fd = event_fd;
    events[0].events = POLLIN;
    events[1].fd = timer_fd;
    events[1].events = POLLIN;

    for (;;) {
        long result;
        events[0].revents = 0;
        events[1].revents = 0;
        do {
            result = sys_ppoll(events, 2);
        } while (result == -4); /* EINTR */
        if (result < 0) {
            log_text("fatal ppoll failed\n");
            sys_exit(3);
        }
        if ((events[0].revents | events[1].revents) &
            (POLLERR | POLLHUP)) {
            log_text("fatal power descriptor closed\n");
            sys_exit(4);
        }

        if (events[0].revents & POLLIN) {
            char event[2048];
            long count;
            int power_changed = 0;
            while ((count = sys_read(event_fd, event, sizeof(event))) > 0) {
                if (event_is_power_supply(event, (u64)count))
                    power_changed = 1;
            }
            if (power_changed) {
                refresh_power_state(1);
                if (discharging == 1) {
                    if (!flash_phase) arm_timer(LOW_REMINDER_SECONDS, 0);
                } else {
                    if (flash_phase) restore_leds();
                    disarm_timer();
                }
            }
        }

        if (events[1].revents & POLLIN) {
            u64 expirations;
            if (sys_read(timer_fd, &expirations, sizeof(expirations)) > 0) {
                if (flash_phase) {
                    advance_flash();
                } else {
                    /* Capacity is a raw PMIC register read.  The exact AXP717
                     * driver emits no event as it falls, so this is a safety
                     * policy timer rather than a status-polling loop. */
                    refresh_power_state(0);
                    if (discharging != 1)
                        disarm_timer();
                    else if (low_state)
                        start_flash();
                    else
                        arm_timer(LOW_REMINDER_SECONDS, 0);
                }
            }
        }
    }
}

__attribute__((naked, noreturn)) void _start(void) {
    __asm__ volatile("b run\n");
}
