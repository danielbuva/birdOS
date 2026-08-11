/*
 * Native RG34XX-SP input and rumble tester.
 *
 * This is deliberately the same kind of program as the Bird launcher: one
 * freestanding static AArch64 process, direct access to the fixed framebuffer
 * and exact H700 evdev device, no libc, SDL, compositor, parser or allocator.
 * It never grabs the gamepad.  The display sleeps in ppoll while idle and only
 * redraws controls whose accepted state changed.
 */

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long u64;
typedef signed short s16;
typedef signed int s32;
typedef signed long s64;

#include "bird-device-contract.h"

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_TRUNC 01000
#define O_APPEND 02000
#define O_NONBLOCK 04000
#define O_DSYNC 010000
#define O_CLOEXEC 02000000
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1
#define POLLIN 0x0001
#define POLLERR 0x0008
#define POLLHUP 0x0010
#define POLLNVAL 0x0020
#define EINTR 4
#define EAGAIN 11
#define CLOCK_BOOTTIME 7

#define EV_SYN 0x00
#define EV_KEY 0x01
#define EV_ABS 0x03
#define EV_FF 0x15
#define SYN_REPORT 0
#define SYN_DROPPED 3
#define ABS_X 0
#define ABS_Y 1
#define ABS_RX 3
#define ABS_RY 4
#define BTN_SOUTH 304
#define BTN_EAST 305
#define BTN_NORTH 307
#define BTN_WEST 308
#define BTN_TL 310
#define BTN_TR 311
#define BTN_TL2 312
#define BTN_TR2 313
#define BTN_SELECT 314
#define BTN_START 315
#define BTN_MODE 316
#define BTN_THUMBL 317
#define BTN_THUMBR 318
#define BTN_DPAD_UP 544
#define BTN_DPAD_DOWN 545
#define BTN_DPAD_LEFT 546
#define BTN_DPAD_RIGHT 547
#define FF_RUMBLE 0x50

/* H700 cardinal button names differ from the printed RG34XX-SP legends. */
#define BIRD_BUTTON_A BTN_EAST
#define BIRD_BUTTON_B BTN_SOUTH
#define BIRD_BUTTON_X BTN_WEST
#define BIRD_BUTTON_Y BTN_NORTH

#define EVIOCGNAME_128 0x80804506UL
#define EVIOCGID 0x80084502UL
#define EVIOCGBIT_EV 0x80084520UL
#define EVIOCGBIT_KEY 0x80604521UL
#define EVIOCGBIT_ABS 0x80084523UL
#define EVIOCGBIT_FF 0x80104535UL
#define EVIOCGKEY_768 0x80604518UL
#define EVIOCGABS_X 0x80184540UL
#define EVIOCGABS_Y 0x80184541UL
#define EVIOCGABS_RX 0x80184543UL
#define EVIOCGABS_RY 0x80184544UL
#define EVIOCSFF 0x40304580UL
#define EVIOCRMFF 0x40044581UL

#define INPUT_SCAN_COUNT ((int)BIRD_DEVICE_INPUT_SCAN_COUNT)
#define RECONNECT_NS 250000000L
#define EXIT_HOLD_NS 1000000000UL
#define RUMBLE_LENGTH_MS 300U
#define LOG_PATH "/storage/bird-data/Bird/log/input-tester-latest.log"

#define COLOR_BACKGROUND 0x0010151cU
#define COLOR_PANEL 0x001b2530U
#define COLOR_UNTESTED 0x00526170U
#define COLOR_TESTED 0x0036d17dU
#define COLOR_ACTIVE 0x00ffd24aU
#define COLOR_TEXT 0x00f4f7faU
#define COLOR_MUTED 0x0095a3b3U
#define COLOR_DANGER 0x00ff6677U

#define DIRTY_AXIS_LEFT (1U << BUTTON_COUNT)
#define DIRTY_AXIS_RIGHT (1U << (BUTTON_COUNT + 1))
#define DIRTY_STATUS (1U << (BUTTON_COUNT + 2))
#define DIRTY_ALL ((1U << (BUTTON_COUNT + 3)) - 1U)

#define HANDLE_NONE 0
#define HANDLE_CHANGED 1
#define HANDLE_RESYNC 2

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

struct input_id {
    u16 bus;
    u16 vendor;
    u16 product;
    u16 version;
};

struct input_absinfo {
    s32 value;
    s32 minimum;
    s32 maximum;
    s32 fuzz;
    s32 flat;
    s32 resolution;
};

struct ff_trigger {
    u16 button;
    u16 interval;
};

struct ff_replay {
    u16 length;
    u16 delay;
};

struct ff_rumble_effect {
    u16 strong_magnitude;
    u16 weak_magnitude;
};

union ff_effect_data {
    struct ff_rumble_effect rumble;
    u64 alignment_and_size[4];
};

struct ff_effect {
    u16 type;
    s16 id;
    u16 direction;
    struct ff_trigger trigger;
    struct ff_replay replay;
    union ff_effect_data data;
};

struct glyph {
    char c;
    u8 rows[7];
};

enum button_index {
    BUTTON_DPAD_UP,
    BUTTON_DPAD_DOWN,
    BUTTON_DPAD_LEFT,
    BUTTON_DPAD_RIGHT,
    BUTTON_A,
    BUTTON_B,
    BUTTON_X,
    BUTTON_Y,
    BUTTON_L1,
    BUTTON_R1,
    BUTTON_L2,
    BUTTON_R2,
    BUTTON_SELECT,
    BUTTON_START,
    BUTTON_MENU,
    BUTTON_L3,
    BUTTON_R3,
    BUTTON_COUNT,
};

struct button_layout {
    int x;
    int y;
    int width;
    int height;
    const char *label;
    int round;
};

struct tester_state {
    u32 held_buttons;
    u32 seen_buttons;
    u32 seen_axis_directions;
    u32 dirty;
    s32 axes[4];
    s32 axis_minimum[4];
    s32 axis_maximum[4];
    s32 axis_observed_minimum[4];
    s32 axis_observed_maximum[4];
    u32 axis_observed_valid;
    u64 b_exit_deadline_ns;
    u32 connections;
    int connected;
    int discard_until_report;
    int rumble_enabled;
    int rumble_attempted;
    int rumble_failed;
    int rumble_sent;
    int effect_id;
};

_Static_assert(sizeof(struct input_id) == 8U, "input ID ABI changed");
_Static_assert(sizeof(struct input_absinfo) == 24U, "ABS info ABI changed");
_Static_assert(sizeof(struct ff_effect) == 48U, "force-feedback ABI changed");

static volatile u32 *framebuffer;
static int framebuffer_fd = -1;
static int discovered_event_index = -1;

static const u16 button_codes[BUTTON_COUNT] = {
    BTN_DPAD_UP, BTN_DPAD_DOWN, BTN_DPAD_LEFT, BTN_DPAD_RIGHT,
    BIRD_BUTTON_A, BIRD_BUTTON_B, BIRD_BUTTON_X, BIRD_BUTTON_Y,
    BTN_TL, BTN_TR, BTN_TL2, BTN_TR2, BTN_SELECT, BTN_START, BTN_MODE,
    BTN_THUMBL, BTN_THUMBR,
};

static const char *const button_log_names[BUTTON_COUNT] = {
    "DPAD-UP", "DPAD-DOWN", "DPAD-LEFT", "DPAD-RIGHT",
    "A", "B", "X", "Y", "L1", "R1", "L2", "R2",
    "SELECT", "START", "MENU", "L3", "R3",
};

static const struct button_layout button_layouts[BUTTON_COUNT] = {
    {105, 205, 48, 48, "UP", 0},       {105, 301, 48, 48, "DOWN", 0},
    {57, 253, 48, 48, "LEFT", 0},     {153, 253, 48, 48, "RIGHT", 0},
    {625, 253, 48, 48, "A", 1},       {577, 301, 48, 48, "B", 1},
    {529, 253, 48, 48, "X", 1},       {577, 205, 48, 48, "Y", 1},
    {145, 72, 112, 38, "L1", 0},      {463, 72, 112, 38, "R1", 0},
    {20, 72, 112, 38, "L2", 0},       {588, 72, 112, 38, "R2", 0},
    {269, 214, 76, 34, "SELECT", 0},  {375, 214, 76, 34, "START", 0},
    {333, 263, 54, 34, "MENU", 0},    {257, 337, 86, 32, "L3", 0},
    {377, 337, 86, 32, "R3", 0},
};

/* Five-wide uppercase font; the tester uses no runtime font service. */
static const struct glyph font[] = {
    {' ', {0, 0, 0, 0, 0, 0, 0}},       {'-', {0, 0, 0, 31, 0, 0, 0}},
    {'/', {1, 2, 4, 8, 16, 0, 0}},      {':', {0, 4, 0, 0, 4, 0, 0}},
    {'0', {14, 17, 19, 21, 25, 17, 14}}, {'1', {4, 12, 4, 4, 4, 4, 14}},
    {'2', {14, 17, 1, 2, 4, 8, 31}},    {'3', {30, 1, 1, 14, 1, 1, 30}},
    {'4', {2, 6, 10, 18, 31, 2, 2}},    {'5', {31, 16, 16, 30, 1, 1, 30}},
    {'6', {14, 16, 16, 30, 17, 17, 14}}, {'7', {31, 1, 2, 4, 8, 8, 8}},
    {'8', {14, 17, 17, 14, 17, 17, 14}}, {'9', {14, 17, 17, 15, 1, 1, 14}},
    {'A', {14, 17, 17, 31, 17, 17, 17}}, {'B', {30, 17, 17, 30, 17, 17, 30}},
    {'C', {14, 17, 16, 16, 16, 17, 14}}, {'D', {30, 17, 17, 17, 17, 17, 30}},
    {'E', {31, 16, 16, 30, 16, 16, 31}}, {'F', {31, 16, 16, 30, 16, 16, 16}},
    {'G', {14, 17, 16, 23, 17, 17, 15}}, {'H', {17, 17, 17, 31, 17, 17, 17}},
    {'I', {14, 4, 4, 4, 4, 4, 14}},     {'J', {7, 2, 2, 2, 2, 18, 12}},
    {'K', {17, 18, 20, 24, 20, 18, 17}}, {'L', {16, 16, 16, 16, 16, 16, 31}},
    {'M', {17, 27, 21, 21, 17, 17, 17}}, {'N', {17, 25, 21, 19, 17, 17, 17}},
    {'O', {14, 17, 17, 17, 17, 17, 14}}, {'P', {30, 17, 17, 30, 16, 16, 16}},
    {'Q', {14, 17, 17, 17, 21, 18, 13}}, {'R', {30, 17, 17, 30, 20, 18, 17}},
    {'S', {15, 16, 16, 14, 1, 1, 30}},  {'T', {31, 4, 4, 4, 4, 4, 4}},
    {'U', {17, 17, 17, 17, 17, 17, 14}}, {'V', {17, 17, 17, 17, 17, 10, 4}},
    {'W', {17, 17, 17, 21, 21, 21, 10}}, {'X', {17, 17, 10, 4, 10, 17, 17}},
    {'Y', {17, 17, 10, 4, 4, 4, 4}},    {'Z', {31, 1, 2, 4, 8, 16, 31}},
};

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

static long sys_clock_gettime(struct timespec *value) {
    return syscall6(113, CLOCK_BOOTTIME, (long)value, 0, 0, 0, 0);
}

static void *sys_mmap(int fd, u64 length) {
    return (void *)syscall6(222, 0, (long)length, PROT_READ | PROT_WRITE,
                            MAP_SHARED, fd, 0);
}

static long sys_munmap(void *address, u64 length) {
    return syscall6(215, (long)address, (long)length, 0, 0, 0, 0);
}

__attribute__((noreturn)) static void sys_exit(int status) {
    syscall6(93, status, 0, 0, 0, 0, 0);
    __builtin_unreachable();
}

static u64 monotonic_ns(void) {
    struct timespec now;
    if (sys_clock_gettime(&now) < 0) return 0U;
    return (u64)now.sec * 1000000000UL + (u64)now.nsec;
}

static int strings_equal(const char *left, const char *right) {
    while (*left && *left == *right) {
        left++;
        right++;
    }
    return *left == *right;
}

static int string_length(const char *text) {
    int length = 0;
    while (text[length]) length++;
    return length;
}

static int input_words_equal(const u64 *left, const u64 *right, u32 count) {
    u32 index;
    for (index = 0U; index < count; index++)
        if (left[index] != right[index]) return 0;
    return 1;
}

static void event_path(char *path, int event_index) {
    static const char prefix[] = "/dev/input/event";
    int position = 0;
    int divisor = 1;
    int value = event_index;
    while (prefix[position]) {
        path[position] = prefix[position];
        position++;
    }
    while (value >= divisor * 10) divisor *= 10;
    do {
        path[position++] = (char)('0' + value / divisor);
        value %= divisor;
        divisor /= 10;
    } while (divisor);
    path[position] = '\0';
}

static int h700_input_contract_matches(int fd) {
    static const u64 expected_key[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] =
        BIRD_DEVICE_INPUT_KEY_BITMAP_WORDS;
    static const u64 expected_ff[BIRD_DEVICE_INPUT_FF_BITMAP_WORD_COUNT] =
        BIRD_DEVICE_INPUT_FF_BITMAP_WORDS;
    struct input_id id;
    char name[128];
    u64 event_bits = 0U;
    u64 key_bits[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] = {0U};
    u64 absolute_bits = 0U;
    u64 force_feedback_bits[BIRD_DEVICE_INPUT_FF_BITMAP_WORD_COUNT] = {0U};

    name[0] = '\0';
    if (sys_ioctl(fd, EVIOCGNAME_128, name) < 0 ||
        sys_ioctl(fd, EVIOCGID, &id) < 0 ||
        sys_ioctl(fd, EVIOCGBIT_EV, &event_bits) < 0 ||
        sys_ioctl(fd, EVIOCGBIT_KEY, key_bits) < 0 ||
        sys_ioctl(fd, EVIOCGBIT_ABS, &absolute_bits) < 0 ||
        sys_ioctl(fd, EVIOCGBIT_FF, force_feedback_bits) < 0)
        return 0;
    name[sizeof(name) - 1U] = '\0';
    return strings_equal(name, BIRD_DEVICE_INPUT_NAME) &&
           id.bus == BIRD_DEVICE_INPUT_BUS &&
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

static int try_input_event(int index) {
    char path[32];
    long fd;
    event_path(path, index);
    fd = sys_open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) fd = sys_open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return -1;
    if (!h700_input_contract_matches((int)fd)) {
        sys_close((int)fd);
        return -1;
    }
    return (int)fd;
}

static int discover_input(void) {
    int preferred = (int)BIRD_DEVICE_INPUT_PREFERRED_EVENT;
    int index;
    int fd = try_input_event(preferred);
    if (fd >= 0) {
        discovered_event_index = preferred;
        return fd;
    }
    for (index = 0; index < INPUT_SCAN_COUNT; index++) {
        if (index == preferred) continue;
        fd = try_input_event(index);
        if (fd >= 0) {
            discovered_event_index = index;
            return fd;
        }
    }
    return -1;
}

static int read_rumble_enabled(void) {
    char value[8];
    long fd = sys_open(BIRD_DEVICE_RUMBLE_ENABLE_PATH, O_RDONLY | O_CLOEXEC);
    long bytes;
    if (fd < 0) return 0;
    bytes = sys_read((int)fd, value, sizeof(value));
    sys_close((int)fd);
    return bytes > 0 && value[0] == '1';
}

static int button_index_for_code(u16 code) {
    int index;
    for (index = 0; index < BUTTON_COUNT; index++)
        if (button_codes[index] == code) return index;
    return -1;
}

static int axis_index_for_code(u16 code) {
    if (code == ABS_X) return 0;
    if (code == ABS_Y) return 1;
    if (code == ABS_RX) return 2;
    if (code == ABS_RY) return 3;
    return -1;
}

static u32 axis_direction_bits(const struct tester_state *state, int axis,
                               s32 value) {
    s64 center = ((s64)state->axis_minimum[axis] +
                  (s64)state->axis_maximum[axis]) / 2;
    s64 negative_span = center - (s64)state->axis_minimum[axis];
    s64 positive_span = (s64)state->axis_maximum[axis] - center;
    s64 delta = (s64)value - center;
    u32 bits = 0U;
    if (negative_span > 0 && -delta * 5 >= negative_span * 3)
        bits |= 1U << (axis * 2);
    if (positive_span > 0 && delta * 5 >= positive_span * 3)
        bits |= 1U << (axis * 2 + 1);
    return bits;
}

static int update_axis(struct tester_state *state, int axis, s32 value) {
    u32 old_seen = state->seen_axis_directions;
    if (state->axes[axis] == value &&
        !(axis_direction_bits(state, axis, value) & ~old_seen))
        return 0;
    state->axes[axis] = value;
    if (!(state->axis_observed_valid & (1U << axis)) ||
        value < state->axis_observed_minimum[axis])
        state->axis_observed_minimum[axis] = value;
    if (!(state->axis_observed_valid & (1U << axis)) ||
        value > state->axis_observed_maximum[axis])
        state->axis_observed_maximum[axis] = value;
    state->axis_observed_valid |= 1U << axis;
    state->seen_axis_directions |= axis_direction_bits(state, axis, value);
    state->dirty |= axis < 2 ? DIRTY_AXIS_LEFT : DIRTY_AXIS_RIGHT;
    if (state->seen_axis_directions != old_seen) state->dirty |= DIRTY_STATUS;
    return 1;
}

static int update_button(struct tester_state *state, int index, int pressed,
                         u64 now_ns) {
    u32 bit = 1U << index;
    u32 old_held = state->held_buttons;
    u32 old_seen = state->seen_buttons;
    if (pressed) {
        state->held_buttons |= bit;
        state->seen_buttons |= bit;
    } else {
        state->held_buttons &= ~bit;
    }
    if (index == BUTTON_B) {
        if (pressed && !(old_held & bit))
            state->b_exit_deadline_ns = now_ns + EXIT_HOLD_NS;
        else if (!pressed)
            state->b_exit_deadline_ns = 0U;
    }
    if (state->held_buttons != old_held || state->seen_buttons != old_seen) {
        state->dirty |= bit;
        if (state->seen_buttons != old_seen) state->dirty |= DIRTY_STATUS;
        return 1;
    }
    return 0;
}

static int handle_event(struct tester_state *state,
                        const struct input_event *event, u64 now_ns) {
    int index;
    if (state->discard_until_report) {
        if (event->type == EV_SYN && event->code == SYN_REPORT) {
            state->discard_until_report = 0;
            return HANDLE_RESYNC;
        }
        return HANDLE_NONE;
    }
    if (event->type == EV_SYN && event->code == SYN_DROPPED) {
        state->discard_until_report = 1;
        return HANDLE_NONE;
    }
    if (event->type == EV_KEY) {
        index = button_index_for_code(event->code);
        if (index >= 0 && update_button(state, index, event->value != 0, now_ns))
            return HANDLE_CHANGED;
    } else if (event->type == EV_ABS) {
        index = axis_index_for_code(event->code);
        if (index >= 0 && update_axis(state, index, event->value))
            return HANDLE_CHANGED;
    }
    return HANDLE_NONE;
}

static int key_bit_set(const u64 *bits, u16 code) {
    return (bits[code / 64U] & (1UL << (code % 64U))) != 0U;
}

static u64 abs_request_for_axis(int axis) {
    if (axis == 0) return EVIOCGABS_X;
    if (axis == 1) return EVIOCGABS_Y;
    if (axis == 2) return EVIOCGABS_RX;
    return EVIOCGABS_RY;
}

static int resync_input(int fd, struct tester_state *state, u64 now_ns) {
    u64 keys[12] = {0U};
    int index;
    if (sys_ioctl(fd, EVIOCGKEY_768, keys) < 0) return 0;
    for (index = 0; index < BUTTON_COUNT; index++)
        (void)update_button(state, index,
                            key_bit_set(keys, button_codes[index]), now_ns);
    for (index = 0; index < 4; index++) {
        struct input_absinfo info;
        if (sys_ioctl(fd, abs_request_for_axis(index), &info) < 0) return 0;
        state->axis_minimum[index] = info.minimum;
        state->axis_maximum[index] = info.maximum;
        (void)update_axis(state, index, info.value);
    }
    return 1;
}

static void clear_live_state(struct tester_state *state) {
    state->held_buttons = 0U;
    state->b_exit_deadline_ns = 0U;
    state->connected = 0;
    state->discard_until_report = 0;
    state->effect_id = -1;
    state->dirty |= DIRTY_ALL;
}

static int exit_hold_complete(const struct tester_state *state, u64 now_ns) {
    return state->b_exit_deadline_ns != 0U &&
           now_ns >= state->b_exit_deadline_ns;
}

static void erase_rumble(int fd, struct tester_state *state);

static int upload_rumble(int fd, struct tester_state *state) {
    struct ff_effect effect = {0};
    struct input_event play = {0};
    state->rumble_attempted = 1;
    if (!state->rumble_enabled) {
        state->rumble_failed = 1;
        state->dirty |= DIRTY_STATUS;
        return 0;
    }
    if (state->effect_id >= 0) {
        play.type = EV_FF;
        play.code = (u16)state->effect_id;
        play.value = 1;
        if (sys_write(fd, &play, sizeof(play)) == (long)sizeof(play)) {
            state->rumble_failed = 0;
            state->rumble_sent = 1;
            state->dirty |= DIRTY_STATUS;
            return 1;
        }
        state->rumble_failed = 1;
        state->dirty |= DIRTY_STATUS;
        return 0;
    }
    effect.type = FF_RUMBLE;
    effect.id = -1;
    effect.replay.length = RUMBLE_LENGTH_MS;
    effect.data.rumble.strong_magnitude = 0xc000U;
    effect.data.rumble.weak_magnitude = 0x6000U;
    if (sys_ioctl(fd, EVIOCSFF, &effect) < 0 || effect.id < 0) {
        state->rumble_failed = 1;
        state->dirty |= DIRTY_STATUS;
        return 0;
    }
    play.type = EV_FF;
    play.code = (u16)effect.id;
    play.value = 1;
    if (sys_write(fd, &play, sizeof(play)) != (long)sizeof(play)) {
        int id = effect.id;
        (void)sys_ioctl(fd, EVIOCRMFF, &id);
        state->rumble_failed = 1;
        state->dirty |= DIRTY_STATUS;
        return 0;
    }
    state->effect_id = effect.id;
    state->rumble_failed = 0;
    if (!state->rumble_sent) {
        state->rumble_sent = 1;
        state->dirty |= DIRTY_STATUS;
    }
    return 1;
}

static void erase_rumble(int fd, struct tester_state *state) {
    if (fd >= 0 && state->effect_id >= 0) {
        struct input_event stop = {0};
        int id = state->effect_id;
        stop.type = EV_FF;
        stop.code = (u16)id;
        stop.value = 0;
        (void)sys_write(fd, &stop, sizeof(stop));
        (void)sys_ioctl(fd, EVIOCRMFF, &id);
    }
    state->effect_id = -1;
}

static int decimal_text(char *out, s32 value);
static int tested_count(const struct tester_state *state);

static int buffer_text(char *buffer, int length, int limit, const char *text) {
    while (*text && length < limit) buffer[length++] = *text++;
    return length;
}

static int buffer_number(char *buffer, int length, int limit, s32 value) {
    char number[16];
    int index;
    int count = decimal_text(number, value);
    for (index = 0; index < count && length < limit; index++)
        buffer[length++] = number[index];
    return length;
}

static void write_log_snapshot(const struct tester_state *state,
                               const char *phase, int truncate) {
    char buffer[2048];
    int length = 0;
    int index;
    long fd;
    length = buffer_text(buffer, length, sizeof(buffer),
                         "schema\tbird-input-test-v1\nphase\t");
    length = buffer_text(buffer, length, sizeof(buffer), phase);
    length = buffer_text(buffer, length, sizeof(buffer),
                         "\ncontract\texact-h700-gamepad\nevent\t/dev/input/event");
    length = buffer_number(buffer, length, sizeof(buffer),
                           discovered_event_index);
    length = buffer_text(buffer, length, sizeof(buffer), "\nconnections\t");
    length = buffer_number(buffer, length, sizeof(buffer),
                           (s32)state->connections);
    length = buffer_text(buffer, length, sizeof(buffer), "\n");
    for (index = 0; index < BUTTON_COUNT; index++) {
        length = buffer_text(buffer, length, sizeof(buffer), "button\t");
        length = buffer_text(buffer, length, sizeof(buffer),
                             button_log_names[index]);
        length = buffer_text(buffer, length, sizeof(buffer), "\t");
        length = buffer_number(buffer, length, sizeof(buffer),
                               (state->seen_buttons & (1U << index)) ? 1 : 0);
        length = buffer_text(buffer, length, sizeof(buffer), "\n");
    }
    for (index = 0; index < 4; index++) {
        static const char *const axis_names[4] = {"LX", "LY", "RX", "RY"};
        length = buffer_text(buffer, length, sizeof(buffer), "axis\t");
        length = buffer_text(buffer, length, sizeof(buffer), axis_names[index]);
        length = buffer_text(buffer, length, sizeof(buffer), "\t");
        length = buffer_number(buffer, length, sizeof(buffer),
                               state->axis_observed_minimum[index]);
        length = buffer_text(buffer, length, sizeof(buffer), "\t");
        length = buffer_number(buffer, length, sizeof(buffer),
                               state->axis_observed_maximum[index]);
        length = buffer_text(buffer, length, sizeof(buffer), "\n");
    }
    length = buffer_text(buffer, length, sizeof(buffer), "rumble-enabled\t");
    length = buffer_number(buffer, length, sizeof(buffer), state->rumble_enabled);
    length = buffer_text(buffer, length, sizeof(buffer), "\nrumble-sent\t");
    length = buffer_number(buffer, length, sizeof(buffer), state->rumble_sent);
    length = buffer_text(buffer, length, sizeof(buffer), "\nrumble-failed\t");
    length = buffer_number(buffer, length, sizeof(buffer), state->rumble_failed);
    length = buffer_text(buffer, length, sizeof(buffer), "\ntested\t");
    length = buffer_number(buffer, length, sizeof(buffer), tested_count(state));
    length = buffer_text(buffer, length, sizeof(buffer), "/26\n");
    /* Keep the opening diagnostic durable, but never put a storage flush on
     * the normal app-to-menu return path. */
    fd = sys_open_mode(LOG_PATH,
                       O_WRONLY | O_CREAT |
                           (truncate ? O_TRUNC | O_DSYNC : O_APPEND), 0644);
    if (fd >= 0) {
        int offset = 0;
        while (offset < length) {
            long written = sys_write((int)fd, buffer + offset,
                                     (u64)(length - offset));
            if (written <= 0) break;
            offset += (int)written;
        }
        sys_close((int)fd);
    }
}

static void pixel(int x, int y, u32 color) {
    if ((u32)x >= BIRD_DEVICE_FB_WIDTH || (u32)y >= BIRD_DEVICE_FB_HEIGHT)
        return;
    framebuffer[(u32)y * (BIRD_DEVICE_FB_STRIDE / 4U) + (u32)x] = color;
}

static void rectangle(int x, int y, int width, int height, u32 color) {
    int xx;
    int yy;
    for (yy = y; yy < y + height; yy++)
        for (xx = x; xx < x + width; xx++) pixel(xx, yy, color);
}

static void circle(int center_x, int center_y, int radius, u32 color,
                   int filled) {
    int x;
    int y;
    int outer = radius * radius;
    int inner = (radius - 3) * (radius - 3);
    for (y = -radius; y <= radius; y++) {
        for (x = -radius; x <= radius; x++) {
            int distance = x * x + y * y;
            if (distance <= outer && (filled || distance >= inner))
                pixel(center_x + x, center_y + y, color);
        }
    }
}

static const struct glyph *find_glyph(char c) {
    u32 index;
    for (index = 0U; index < sizeof(font) / sizeof(font[0]); index++)
        if (font[index].c == c) return &font[index];
    return &font[0];
}

static void draw_character(int x, int y, char c, int scale, u32 color) {
    const struct glyph *glyph = find_glyph(c);
    int row;
    int column;
    for (row = 0; row < 7; row++)
        for (column = 0; column < 5; column++)
            if (glyph->rows[row] & (1U << (4 - column)))
                rectangle(x + column * scale, y + row * scale,
                          scale, scale, color);
}

static void draw_text(int x, int y, const char *text, int scale, u32 color) {
    while (*text) {
        draw_character(x, y, *text++, scale, color);
        x += 6 * scale;
    }
}

static int decimal_text(char *out, s32 value) {
    char reverse[16];
    u32 magnitude;
    int count = 0;
    int length = 0;
    if (value < 0) {
        out[length++] = '-';
        magnitude = (u32)(-(s64)value);
    } else {
        magnitude = (u32)value;
    }
    do {
        reverse[count++] = (char)('0' + magnitude % 10U);
        magnitude /= 10U;
    } while (magnitude);
    while (count) out[length++] = reverse[--count];
    out[length] = '\0';
    return length;
}

static int tested_count(const struct tester_state *state) {
    u32 value;
    int count = 0;
    value = state->seen_buttons;
    while (value) {
        count += (int)(value & 1U);
        value >>= 1;
    }
    value = state->seen_axis_directions;
    while (value) {
        count += (int)(value & 1U);
        value >>= 1;
    }
    if (state->rumble_sent) count++;
    return count;
}

static void render_button(const struct tester_state *state, int index) {
    const struct button_layout *layout = &button_layouts[index];
    u32 bit = 1U << index;
    u32 color = (state->held_buttons & bit) ? COLOR_ACTIVE :
                ((state->seen_buttons & bit) ? COLOR_TESTED : COLOR_UNTESTED);
    int text_width = 6 * string_length(layout->label) - 1;
    rectangle(layout->x - 4, layout->y - 4,
              layout->width + 8, layout->height + 8, COLOR_BACKGROUND);
    if (layout->round) {
        circle(layout->x + layout->width / 2,
               layout->y + layout->height / 2,
               layout->width / 2, color, 1);
    } else {
        rectangle(layout->x, layout->y, layout->width, layout->height, color);
    }
    draw_text(layout->x + (layout->width - text_width) / 2,
              layout->y + (layout->height - 7) / 2,
              layout->label, 1,
              (state->held_buttons & bit) ? COLOR_BACKGROUND : COLOR_TEXT);
}

static int axis_pixel(const struct tester_state *state, int axis) {
    s64 center = ((s64)state->axis_minimum[axis] +
                  (s64)state->axis_maximum[axis]) / 2;
    s64 delta = (s64)state->axes[axis] - center;
    s64 span = delta < 0 ? center - state->axis_minimum[axis]
                         : state->axis_maximum[axis] - center;
    s64 result;
    if (span <= 0) return 0;
    result = delta * 34 / span;
    if (result < -34) result = -34;
    if (result > 34) result = 34;
    return (int)result;
}

static void render_axis_pair(const struct tester_state *state, int right) {
    char first[16];
    char second[16];
    int axis = right ? 2 : 0;
    int center_x = right ? 431 : 289;
    int center_y = 407;
    int dot_x = center_x + axis_pixel(state, axis);
    int dot_y = center_y + axis_pixel(state, axis + 1);
    int first_length;
    rectangle(center_x - 62, center_y - 34, 124, 69, COLOR_BACKGROUND);
    circle(center_x, center_y, 34, COLOR_UNTESTED, 0);
    rectangle(center_x - 31, center_y, 63, 1, COLOR_MUTED);
    rectangle(center_x, center_y - 31, 1, 63, COLOR_MUTED);
    circle(dot_x, dot_y, 6, COLOR_ACTIVE, 1);
    first_length = decimal_text(first, state->axes[axis]);
    (void)decimal_text(second, state->axes[axis + 1]);
    rectangle(center_x - 67, 445, 134, 14, COLOR_BACKGROUND);
    draw_text(center_x - 67, 445, right ? "R " : "L ", 1, COLOR_TEXT);
    draw_text(center_x - 55, 445, first, 1, COLOR_MUTED);
    draw_text(center_x - 49 + first_length * 6, 445, "/", 1, COLOR_MUTED);
    draw_text(center_x - 37 + first_length * 6, 445, second, 1, COLOR_MUTED);
}

static void render_status(const struct tester_state *state) {
    char count_text[16];
    int count = tested_count(state);
    rectangle(0, 0, (int)BIRD_DEVICE_FB_WIDTH, 66, COLOR_BACKGROUND);
    draw_text(160, 12, "RG34XX-SP INPUT TEST", 2, COLOR_TEXT);
    draw_text(20, 45, state->connected ? "CONNECTED" : "DISCONNECTED",
              1, state->connected ? COLOR_TESTED : COLOR_DANGER);
    draw_text(284, 45, "TESTED", 1, COLOR_MUTED);
    (void)decimal_text(count_text, count);
    draw_text(332, 45, count_text, 1,
              count == BUTTON_COUNT + 8 + 1 ? COLOR_TESTED : COLOR_TEXT);
    draw_text(350, 45, "/26", 1, COLOR_MUTED);
    draw_text(478, 45,
              state->rumble_failed ? "RUMBLE FAILED" :
              (state->rumble_sent ? "RUMBLE OK" :
               (state->rumble_enabled ? "MENU RUMBLE" : "RUMBLE DISABLED")),
              1, state->rumble_failed ? COLOR_DANGER :
                 (state->rumble_sent ? COLOR_TESTED :
                  (state->rumble_enabled ? COLOR_TEXT : COLOR_DANGER)));
}

static void render_static(void) {
    rectangle(0, 0, (int)BIRD_DEVICE_FB_WIDTH,
              (int)BIRD_DEVICE_FB_HEIGHT, COLOR_BACKGROUND);
    rectangle(12, 65, 696, 53, COLOR_PANEL);
    draw_text(270, 126, "PRESS EVERY CONTROL", 1, COLOR_MUTED);
    draw_text(268, 150, "MOVE STICKS TO EDGES", 1, COLOR_MUTED);
    draw_text(293, 178, "HOLD B TO EXIT", 1, COLOR_TEXT);
}

static void render_all(struct tester_state *state) {
    int index;
    render_static();
    render_status(state);
    for (index = 0; index < BUTTON_COUNT; index++) render_button(state, index);
    render_axis_pair(state, 0);
    render_axis_pair(state, 1);
    state->dirty = 0U;
}

static void render_dirty(struct tester_state *state) {
    u32 dirty = state->dirty;
    int index;
    if (!dirty) return;
    if (dirty & DIRTY_STATUS) render_status(state);
    for (index = 0; index < BUTTON_COUNT; index++)
        if (dirty & (1U << index)) render_button(state, index);
    if (dirty & DIRTY_AXIS_LEFT) render_axis_pair(state, 0);
    if (dirty & DIRTY_AXIS_RIGHT) render_axis_pair(state, 1);
    state->dirty = 0U;
}

static int process_input(int fd, struct tester_state *state) {
    struct input_event events[32];
    for (;;) {
        long bytes = sys_read(fd, events, sizeof(events));
        u64 count;
        u64 index;
        if (bytes == -EINTR) continue;
        if (bytes == -EAGAIN) return 1;
        if (bytes <= 0 || (u64)bytes % sizeof(events[0])) return 0;
        count = (u64)bytes / sizeof(events[0]);
        for (index = 0U; index < count; index++) {
            int result = handle_event(state, &events[index], monotonic_ns());
            if (result == HANDLE_RESYNC) {
                if (!resync_input(fd, state, monotonic_ns())) return 0;
                render_dirty(state);
                continue;
            }
            if (events[index].type == EV_KEY &&
                events[index].code == BTN_MODE && events[index].value == 1)
                (void)upload_rumble(fd, state);
            if (events[index].type == EV_SYN &&
                events[index].code == SYN_REPORT)
                render_dirty(state);
        }
    }
}

#ifndef BIRD_HOST_TEST
static int connect_input(struct tester_state *state) {
    int fd = discover_input();
    if (fd < 0) return -1;
    state->rumble_enabled = read_rumble_enabled();
    state->effect_id = -1;
    if (!resync_input(fd, state, monotonic_ns())) {
        sys_close(fd);
        return -1;
    }
    state->connected = 1;
    state->connections++;
    state->dirty |= DIRTY_ALL;
    render_dirty(state);
    write_log_snapshot(state, state->connections == 1U ? "connected" :
                       "reconnected", state->connections == 1U);
    return fd;
}

static void disconnect_input(int *fd, struct tester_state *state) {
    erase_rumble(*fd, state);
    if (*fd >= 0) sys_close(*fd);
    *fd = -1;
    clear_live_state(state);
    render_dirty(state);
}

static void application(void) {
    static struct tester_state state = {
        .axis_minimum = {-32768, -32768, -32768, -32768},
        .axis_maximum = {32767, 32767, 32767, 32767},
        .effect_id = -1,
    };
    struct pollfd poll;
    long mapped;
    int input_fd = -1;

    framebuffer_fd = (int)sys_open(BIRD_DEVICE_FRAMEBUFFER_NODE,
                                   O_RDWR | O_CLOEXEC);
    if (framebuffer_fd < 0) return;
    mapped = (long)sys_mmap(framebuffer_fd, BIRD_DEVICE_FB_MAPPING_BYTES);
    if (mapped < 0) {
        sys_close(framebuffer_fd);
        return;
    }
    framebuffer = (volatile u32 *)mapped;
    render_all(&state);
    input_fd = connect_input(&state);

    for (;;) {
        struct timespec timeout;
        const struct timespec *timeout_pointer = 0;
        u64 now = monotonic_ns();
        long ready;

        if (exit_hold_complete(&state, now)) break;
        if (input_fd < 0) {
            timeout.sec = 0;
            timeout.nsec = RECONNECT_NS;
            timeout_pointer = &timeout;
        } else if (state.b_exit_deadline_ns) {
            u64 remaining = state.b_exit_deadline_ns > now
                                ? state.b_exit_deadline_ns - now : 0U;
            timeout.sec = (s64)(remaining / 1000000000UL);
            timeout.nsec = (s64)(remaining % 1000000000UL);
            timeout_pointer = &timeout;
        }
        poll.fd = input_fd;
        poll.events = POLLIN;
        poll.revents = 0;
        ready = sys_ppoll(input_fd >= 0 ? &poll : 0,
                          input_fd >= 0 ? 1U : 0U, timeout_pointer);
        if (ready == -EINTR) continue;
        if (ready < 0) break;
        if (input_fd < 0) {
            input_fd = connect_input(&state);
            continue;
        }
        if (poll.revents & (POLLERR | POLLHUP | POLLNVAL)) {
            disconnect_input(&input_fd, &state);
            continue;
        }
        if ((poll.revents & POLLIN) && !process_input(input_fd, &state))
            disconnect_input(&input_fd, &state);
    }

    write_log_snapshot(&state, "exit-b-hold", 0);
    erase_rumble(input_fd, &state);
    if (input_fd >= 0) sys_close(input_fd);
    (void)sys_munmap((void *)framebuffer, BIRD_DEVICE_FB_MAPPING_BYTES);
    sys_close(framebuffer_fd);
}

void _start(void) {
    application();
    sys_exit(0);
}
#endif
