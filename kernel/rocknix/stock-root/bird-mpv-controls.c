/*
 * Fixed RG34XX-SP media controls for the retained ROCKNIX MPV provider.
 *
 * The stock player starts both mpv_sense and MPV's SDL gamepad reader.  Those
 * independent readers can translate one H700 press into two different MPV
 * commands.  Bird instead validates the one fixed evdev device and writes one
 * command stream to MPV's JSON IPC socket.  The process exists only while MPV
 * is running, never grabs the gamepad, and blocks in ppoll once both endpoints
 * are ready.
 */

typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long u64;
typedef signed int s32;
typedef signed long s64;

#include "bird-device-contract.h"

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_NONBLOCK 04000
#define O_CLOEXEC 02000000
#define AF_UNIX 1
#define SOCK_STREAM 1
#define SOCK_NONBLOCK O_NONBLOCK
#define SOCK_CLOEXEC O_CLOEXEC
#define MSG_NOSIGNAL 0x4000
#define POLLIN 0x0001
#define POLLOUT 0x0004
#define POLLERR 0x0008
#define POLLHUP 0x0010
#define POLLNVAL 0x0020
#define IN_MOVED_TO 0x00000080U
#define IN_CREATE 0x00000100U
#define IN_Q_OVERFLOW 0x00004000U
#define EINTR 4
#define EAGAIN 11

#define EV_SYN 0x00
#define EV_KEY 0x01
#define SYN_REPORT 0
#define SYN_DROPPED 3
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
#define BTN_DPAD_UP 544
#define BTN_DPAD_DOWN 545
#define BTN_DPAD_LEFT 546
#define BTN_DPAD_RIGHT 547

/* H700's Linux cardinal names do not match the RG34XX-SP legends. */
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

#define INPUT_DIRECTORY "/dev/input"
#define IPC_PATH "/tmp/mpvsocket"
#define INPUT_SCAN_COUNT ((int)BIRD_DEVICE_INPUT_SCAN_COUNT)
#define COMMAND_QUEUE_COUNT 32U
#define IPC_RETRY_NS 10000000L
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

struct sockaddr_un {
    u16 family;
    char path[108];
};

struct queued_command {
    const char *text;
    u16 length;
    u16 sent;
};

struct command_queue {
    struct queued_command entries[COMMAND_QUEUE_COUNT];
    u32 head;
    u32 count;
};

enum pending_button_action {
    PENDING_BUTTON_NONE,
    PENDING_BUTTON_SUBTITLE,
    PENDING_BUTTON_AUDIO,
    PENDING_BUTTON_SUBTITLE_VISIBILITY,
};

struct control_state {
    int menu_held;
    int left_shoulder_held;
    int right_shoulder_held;
    int left_shoulder_used;
    int right_shoulder_used;
    int select_held;
    int start_held;
    int exit_chord_latched;
    int discard_until_syn_report;
    enum pending_button_action select_pending;
    enum pending_button_action start_pending;
};

_Static_assert(sizeof(struct input_id) == 8U, "input ID ABI changed");

static const char command_pause[] =
    "{\"command\":[\"cycle\",\"pause\"]}\n";
static const char command_frame_step[] =
    "{\"command\":[\"frame-step\"]}\n";
static const char command_progress[] =
    "{\"command\":[\"show-progress\"]}\n";
static const char command_seek_forward_short[] =
    "{\"command\":[\"seek\",5]}\n";
static const char command_seek_backward_short[] =
    "{\"command\":[\"seek\",-5]}\n";
static const char command_seek_forward_long[] =
    "{\"command\":[\"seek\",60]}\n";
static const char command_seek_backward_long[] =
    "{\"command\":[\"seek\",-60]}\n";
static const char command_chapter_previous[] =
    "{\"command\":[\"osd-auto\",\"add\",\"chapter\",-1]}\n";
static const char command_chapter_next[] =
    "{\"command\":[\"osd-auto\",\"add\",\"chapter\",1]}\n";
static const char command_playlist_previous[] =
    "{\"command\":[\"playlist-prev\",\"weak\"]}\n";
static const char command_playlist_next[] =
    "{\"command\":[\"playlist-next\",\"weak\"]}\n";
static const char command_subtitle[] =
    "{\"command\":[\"cycle\",\"sub\"]}\n";
static const char command_subtitle_visibility[] =
    "{\"command\":[\"cycle\",\"sub-visibility\"]}\n";
static const char command_audio[] =
    "{\"command\":[\"osd-auto\",\"cycle\",\"audio\"]}\n";
static const char command_volume_down[] =
    "{\"command\":[\"osd-auto\",\"add\",\"volume\",-2]}\n";
static const char command_volume_up[] =
    "{\"command\":[\"osd-auto\",\"add\",\"volume\",2]}\n";
static const char command_brightness_down[] =
    "{\"command\":[\"osd-auto\",\"add\",\"brightness\",-1]}\n";
static const char command_brightness_up[] =
    "{\"command\":[\"osd-auto\",\"add\",\"brightness\",1]}\n";
static const char command_contrast_down[] =
    "{\"command\":[\"osd-auto\",\"add\",\"contrast\",-1]}\n";
static const char command_contrast_up[] =
    "{\"command\":[\"osd-auto\",\"add\",\"contrast\",1]}\n";
static const char command_saturation_down[] =
    "{\"command\":[\"osd-auto\",\"add\",\"saturation\",-1]}\n";
static const char command_saturation_up[] =
    "{\"command\":[\"osd-auto\",\"add\",\"saturation\",1]}\n";

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

static long sys_close(int fd) {
    return syscall6(57, fd, 0, 0, 0, 0, 0);
}

static long sys_read(int fd, void *buffer, u64 size) {
    return syscall6(63, fd, (long)buffer, (long)size, 0, 0, 0);
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

static long sys_socket(int domain, int type, int protocol) {
    return syscall6(198, domain, type, protocol, 0, 0, 0);
}

static long sys_connect(int fd, const struct sockaddr_un *address,
                        u32 length) {
    return syscall6(203, fd, (long)address, length, 0, 0, 0);
}

static long sys_send(int fd, const void *buffer, u64 length) {
    return syscall6(206, fd, (long)buffer, (long)length, MSG_NOSIGNAL, 0, 0);
}

__attribute__((noreturn)) static void sys_exit(int status) {
    syscall6(93, status, 0, 0, 0, 0, 0);
    __builtin_unreachable();
}

static u64 string_length(const char *text) {
    u64 length = 0U;
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

static void event_path(char *path, int event_index) {
    static const char prefix[] = "/dev/input/event";
    u32 position = 0U;
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

static int try_input_event(int event_index) {
    char path[32];
    long fd;

    event_path(path, event_index);
    fd = sys_open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return -1;
    if (!h700_input_contract_matches((int)fd)) {
        sys_close((int)fd);
        return -1;
    }
    return (int)fd;
}

static int discover_input(void) {
    int preferred = (int)BIRD_DEVICE_INPUT_PREFERRED_EVENT;
    int event_index;
    int fd = try_input_event(preferred);

    if (fd >= 0) return fd;
    for (event_index = 0; event_index < INPUT_SCAN_COUNT; event_index++) {
        if (event_index == preferred) continue;
        fd = try_input_event(event_index);
        if (fd >= 0) return fd;
    }
    return -1;
}

static int input_event_index(const char *name, u32 length) {
    static const char prefix[] = "event";
    u32 position = 0U;
    int index = 0;

    while (prefix[position]) {
        if (position >= length || name[position] != prefix[position]) return -1;
        position++;
    }
    if (position >= length || name[position] < '0' || name[position] > '9')
        return -1;
    while (position < length && name[position] >= '0' && name[position] <= '9') {
        index = index * 10 + (name[position] - '0');
        if (index >= INPUT_SCAN_COUNT) return -1;
        position++;
    }
    if (position >= length || name[position] != '\0') return -1;
    return index;
}

static int open_input_watch(void) {
    int fd = (int)sys_inotify_init1(O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return -1;
    if (sys_inotify_add_watch(fd, INPUT_DIRECTORY,
                              IN_CREATE | IN_MOVED_TO) < 0) {
        sys_close(fd);
        return -1;
    }
    return fd;
}

static int process_input_watch(int watch_fd, int *input_fd) {
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
            int event_index;

            if (record_bytes > (u64)bytes - offset) return 0;
            if ((event->mask & IN_Q_OVERFLOW) && *input_fd < 0) {
                *input_fd = discover_input();
            } else if (*input_fd < 0 &&
                       (event->mask & (IN_CREATE | IN_MOVED_TO)) &&
                       event->len) {
                event_index = input_event_index(event->name, event->len);
                if (event_index >= 0) *input_fd = try_input_event(event_index);
            }
            offset += record_bytes;
        }
        if (offset != (u64)bytes) return 0;
    }
}

static int queue_command(struct command_queue *queue, const char *text) {
    u32 tail;
    u64 length;

    if (queue->count == COMMAND_QUEUE_COUNT) return 0;
    length = string_length(text);
    if (!length || length > 65535U) return 0;
    tail = (queue->head + queue->count) % COMMAND_QUEUE_COUNT;
    queue->entries[tail].text = text;
    queue->entries[tail].length = (u16)length;
    queue->entries[tail].sent = 0U;
    queue->count++;
    return 1;
}

static int flush_commands(int ipc_fd, struct command_queue *queue) {
    while (queue->count) {
        struct queued_command *command = &queue->entries[queue->head];
        u16 remaining = (u16)(command->length - command->sent);
        long written = sys_send(ipc_fd, command->text + command->sent,
                                remaining);

        if (written == -EINTR) continue;
        if (written == -EAGAIN) return 1;
        if (written <= 0 || written > remaining) return 0;
        command->sent = (u16)(command->sent + (u16)written);
        if (command->sent != command->length) continue;
        queue->head = (queue->head + 1U) % COMMAND_QUEUE_COUNT;
        queue->count--;
    }
    return 1;
}

static void disconnect_ipc(int *ipc_fd, struct command_queue *queue) {
    if (*ipc_fd >= 0) sys_close(*ipc_fd);
    *ipc_fd = -1;
    queue->head = 0U;
    queue->count = 0U;
}

static void clear_control_state(struct control_state *state) {
    state->menu_held = 0;
    state->left_shoulder_held = 0;
    state->right_shoulder_held = 0;
    state->left_shoulder_used = 0;
    state->right_shoulder_used = 0;
    state->select_held = 0;
    state->start_held = 0;
    state->exit_chord_latched = 0;
    state->discard_until_syn_report = 0;
    state->select_pending = PENDING_BUTTON_NONE;
    state->start_pending = PENDING_BUTTON_NONE;
}

static int key_bit(const u64 *bits, u16 code) {
    return (int)((bits[code / 64U] >> (code % 64U)) & 1U);
}

static void apply_key_snapshot(struct control_state *state, const u64 *bits) {
    clear_control_state(state);
    state->menu_held = key_bit(bits, BTN_MODE);
    state->left_shoulder_held = key_bit(bits, BTN_TL);
    state->right_shoulder_held = key_bit(bits, BTN_TR);
    state->left_shoulder_used = state->left_shoulder_held;
    state->right_shoulder_used = state->right_shoulder_held;
    state->select_held = key_bit(bits, BTN_SELECT);
    state->start_held = key_bit(bits, BTN_START);
    state->exit_chord_latched = state->select_held && state->start_held;
}

static int resync_control_state(int input_fd, struct control_state *state) {
    u64 bits[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] = {0U};

    if (sys_ioctl(input_fd, EVIOCGKEY_768, bits) < 0) return 0;
    apply_key_snapshot(state, bits);
    return 1;
}

static int open_synchronized_input(struct control_state *state) {
    int fd = discover_input();

    if (fd >= 0 && !resync_control_state(fd, state)) {
        sys_close(fd);
        fd = -1;
    }
    return fd;
}

static int flipped(const struct control_state *state) {
    return state->left_shoulder_held || state->right_shoulder_held;
}

static void use_held_shoulders(struct control_state *state) {
    if (state->left_shoulder_held) state->left_shoulder_used = 1;
    if (state->right_shoulder_held) state->right_shoulder_used = 1;
}

static void queue_pending(struct command_queue *queue,
                          enum pending_button_action pending) {
    if (pending == PENDING_BUTTON_SUBTITLE)
        (void)queue_command(queue, command_subtitle);
    else if (pending == PENDING_BUTTON_AUDIO)
        (void)queue_command(queue, command_audio);
    else if (pending == PENDING_BUTTON_SUBTITLE_VISIBILITY)
        (void)queue_command(queue, command_subtitle_visibility);
}

static void update_exit_chord(struct control_state *state) {
    if (state->select_held && state->start_held) {
        state->exit_chord_latched = 1;
        state->select_pending = PENDING_BUTTON_NONE;
        state->start_pending = PENDING_BUTTON_NONE;
    } else if (!state->select_held && !state->start_held) {
        state->exit_chord_latched = 0;
    }
}

static void handle_select(const struct input_event *event,
                          struct control_state *state,
                          struct command_queue *queue) {
    if (event->value == 1) {
        state->select_held = 1;
        state->select_pending = flipped(state) ? PENDING_BUTTON_AUDIO
                                               : PENDING_BUTTON_SUBTITLE;
        if (flipped(state)) use_held_shoulders(state);
        update_exit_chord(state);
    } else if (event->value == 0 && state->select_held) {
        enum pending_button_action pending = state->select_pending;
        state->select_held = 0;
        state->select_pending = PENDING_BUTTON_NONE;
        if (!state->exit_chord_latched && !state->start_held)
            queue_pending(queue, pending);
        update_exit_chord(state);
    }
}

static void handle_start(const struct input_event *event,
                         struct control_state *state,
                         struct command_queue *queue) {
    if (event->value == 1) {
        state->start_held = 1;
        state->start_pending = PENDING_BUTTON_SUBTITLE_VISIBILITY;
        if (flipped(state)) use_held_shoulders(state);
        update_exit_chord(state);
    } else if (event->value == 0 && state->start_held) {
        enum pending_button_action pending = state->start_pending;
        state->start_held = 0;
        state->start_pending = PENDING_BUTTON_NONE;
        if (!state->exit_chord_latched && !state->select_held)
            queue_pending(queue, pending);
        update_exit_chord(state);
    }
}

static void handle_picture_dpad(u16 code, struct command_queue *queue) {
    if (code == BTN_DPAD_LEFT)
        (void)queue_command(queue, command_contrast_down);
    else if (code == BTN_DPAD_RIGHT)
        (void)queue_command(queue, command_contrast_up);
    else if (code == BTN_DPAD_DOWN)
        (void)queue_command(queue, command_saturation_down);
    else if (code == BTN_DPAD_UP)
        (void)queue_command(queue, command_saturation_up);
}

static void handle_regular(u16 code, struct command_queue *queue) {
    if (code == BIRD_BUTTON_A)
        (void)queue_command(queue, command_pause);
    else if (code == BIRD_BUTTON_B)
        (void)queue_command(queue, command_frame_step);
    else if (code == BIRD_BUTTON_X)
        (void)queue_command(queue, command_audio);
    else if (code == BIRD_BUTTON_Y)
        (void)queue_command(queue, command_progress);
    else if (code == BTN_DPAD_LEFT)
        (void)queue_command(queue, command_seek_backward_short);
    else if (code == BTN_DPAD_RIGHT)
        (void)queue_command(queue, command_seek_forward_short);
    else if (code == BTN_DPAD_DOWN)
        (void)queue_command(queue, command_seek_backward_long);
    else if (code == BTN_DPAD_UP)
        (void)queue_command(queue, command_seek_forward_long);
    else if (code == BTN_TL2)
        (void)queue_command(queue, command_chapter_previous);
    else if (code == BTN_TR2)
        (void)queue_command(queue, command_chapter_next);
}

static void handle_flipped(u16 code, struct command_queue *queue) {
    if (code == BTN_DPAD_LEFT)
        (void)queue_command(queue, command_pause);
    else if (code == BTN_DPAD_DOWN)
        (void)queue_command(queue, command_frame_step);
    else if (code == BTN_DPAD_UP)
        (void)queue_command(queue, command_audio);
    else if (code == BTN_DPAD_RIGHT)
        (void)queue_command(queue, command_progress);
    else if (code == BIRD_BUTTON_A)
        (void)queue_command(queue, command_seek_forward_short);
    else if (code == BIRD_BUTTON_B)
        (void)queue_command(queue, command_seek_backward_long);
    else if (code == BIRD_BUTTON_X)
        (void)queue_command(queue, command_seek_forward_long);
    else if (code == BIRD_BUTTON_Y)
        (void)queue_command(queue, command_seek_backward_short);
    else if (code == BTN_TL2)
        (void)queue_command(queue, command_playlist_previous);
    else if (code == BTN_TR2)
        (void)queue_command(queue, command_playlist_next);
}

static void handle_shoulder(const struct input_event *event,
                            struct control_state *state,
                            struct command_queue *queue, int left) {
    int *held = left ? &state->left_shoulder_held
                     : &state->right_shoulder_held;
    int *used = left ? &state->left_shoulder_used
                     : &state->right_shoulder_used;

    if (event->value == 1) {
        *held = 1;
        *used = 0;
        if (state->menu_held) {
            *used = 1;
            (void)queue_command(queue, left ? command_brightness_down
                                            : command_brightness_up);
        }
    } else if (event->value == 0 && *held) {
        if (!*used)
            (void)queue_command(queue,
                                left ? command_volume_down : command_volume_up);
        *held = 0;
        *used = 0;
    }
}

static int handle_gamepad(const struct input_event *event,
                          struct control_state *state,
                          struct command_queue *queue) {
    int pressed;

    if (state->discard_until_syn_report) {
        if (event->type == EV_SYN && event->code == SYN_REPORT) {
            state->discard_until_syn_report = 0;
            return 1;
        }
        return 0;
    }
    if (event->type == EV_SYN && event->code == SYN_DROPPED) {
        clear_control_state(state);
        state->discard_until_syn_report = 1;
        return 0;
    }
    if (event->type != EV_KEY) return 0;
    if (event->code == BTN_SELECT) {
        handle_select(event, state, queue);
        return 0;
    }
    if (event->code == BTN_START) {
        handle_start(event, state, queue);
        return 0;
    }
    pressed = event->value != 0;
    if (event->code == BTN_MODE) {
        state->menu_held = pressed;
        if (event->value == 1) {
            if (state->left_shoulder_held &&
                !state->left_shoulder_used) {
                state->left_shoulder_used = 1;
                (void)queue_command(queue, command_brightness_down);
            }
            if (state->right_shoulder_held &&
                !state->right_shoulder_used) {
                state->right_shoulder_used = 1;
                (void)queue_command(queue, command_brightness_up);
            }
        }
        return 0;
    }
    if (event->code == BTN_TL) {
        handle_shoulder(event, state, queue, 1);
        return 0;
    }
    if (event->code == BTN_TR) {
        handle_shoulder(event, state, queue, 0);
        return 0;
    }
    if (event->value != 1) return 0;
    if (state->menu_held &&
        (event->code == BTN_DPAD_LEFT || event->code == BTN_DPAD_RIGHT ||
         event->code == BTN_DPAD_DOWN || event->code == BTN_DPAD_UP)) {
        use_held_shoulders(state);
        handle_picture_dpad(event->code, queue);
    } else if (flipped(state)) {
        use_held_shoulders(state);
        handle_flipped(event->code, queue);
    } else {
        handle_regular(event->code, queue);
    }
    return 0;
}

static int process_input(int input_fd, struct control_state *state,
                         struct command_queue *queue) {
    struct input_event events[32];

    for (;;) {
        long bytes = sys_read(input_fd, events, sizeof(events));
        u64 index;
        u64 count;

        if (bytes == -EINTR) continue;
        if (bytes == -EAGAIN) return 1;
        if (bytes <= 0 || (u64)bytes % sizeof(events[0])) return 0;
        count = (u64)bytes / sizeof(events[0]);
        for (index = 0U; index < count; index++) {
            if (handle_gamepad(&events[index], state, queue)) {
                if (!resync_control_state(input_fd, state)) return 0;
                /* The ioctl snapshot can already include later records from
                 * this read batch. Discard the remainder rather than replaying
                 * an action that is now represented in synchronized state. */
                break;
            }
        }
    }
}

static int connect_ipc(void) {
    struct sockaddr_un address;
    u32 index = 0U;
    int fd = (int)sys_socket(AF_UNIX,
                             SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);

    if (fd < 0) return -1;
    address.family = AF_UNIX;
    while (IPC_PATH[index] && index + 1U < sizeof(address.path)) {
        address.path[index] = IPC_PATH[index];
        index++;
    }
    address.path[index] = '\0';
    if (IPC_PATH[index] ||
        sys_connect(fd, &address, (u32)(sizeof(address.family) + index + 1U)) < 0) {
        sys_close(fd);
        return -1;
    }
    return fd;
}

static int drain_ipc(int ipc_fd) {
    unsigned char buffer[512];
    for (;;) {
        long bytes = sys_read(ipc_fd, buffer, sizeof(buffer));
        if (bytes == -EINTR) continue;
        if (bytes == -EAGAIN) return 1;
        if (bytes <= 0) return 0;
    }
}

#ifndef BIRD_HOST_TEST
static void application(void) {
    static struct control_state state;
    static struct command_queue queue;
    struct pollfd polls[3];
    int watch_fd = open_input_watch();
    int input_fd = open_synchronized_input(&state);
    int ipc_fd = -1;

    for (;;) {
        struct timespec timeout;
        const struct timespec *timeout_pointer = 0;
        long ready;

        if (input_fd < 0 && watch_fd < 0) {
            watch_fd = open_input_watch();
            input_fd = open_synchronized_input(&state);
        }
        if (ipc_fd < 0) ipc_fd = connect_ipc();

        polls[0].fd = input_fd;
        polls[0].events = POLLIN;
        polls[0].revents = 0;
        polls[1].fd = watch_fd;
        polls[1].events = POLLIN;
        polls[1].revents = 0;
        polls[2].fd = ipc_fd;
        polls[2].events = POLLIN | (queue.count ? POLLOUT : 0);
        polls[2].revents = 0;

        if (ipc_fd < 0 || (input_fd < 0 && watch_fd < 0)) {
            timeout.sec = 0;
            timeout.nsec = ipc_fd < 0 ? IPC_RETRY_NS : DISCOVERY_RETRY_NS;
            timeout_pointer = &timeout;
        }
        ready = sys_ppoll(polls, 3U, timeout_pointer);
        if (ready == -EINTR) continue;
        if (ready < 0) return;

        if (input_fd >= 0 &&
            (polls[0].revents & (POLLERR | POLLHUP | POLLNVAL))) {
            sys_close(input_fd);
            clear_control_state(&state);
            input_fd = open_synchronized_input(&state);
        } else if (input_fd >= 0 && (polls[0].revents & POLLIN) &&
                   !process_input(input_fd, &state, &queue)) {
            sys_close(input_fd);
            clear_control_state(&state);
            input_fd = open_synchronized_input(&state);
        }

        if (watch_fd >= 0 &&
            (polls[1].revents & (POLLERR | POLLHUP | POLLNVAL))) {
            sys_close(watch_fd);
            watch_fd = -1;
        } else if (watch_fd >= 0 && (polls[1].revents & POLLIN)) {
            int input_was_missing = input_fd < 0;
            if (!process_input_watch(watch_fd, &input_fd)) {
                sys_close(watch_fd);
                watch_fd = -1;
            } else if (input_was_missing && input_fd >= 0 &&
                       !resync_control_state(input_fd, &state)) {
                sys_close(input_fd);
                input_fd = -1;
                clear_control_state(&state);
            }
        }

        if (ipc_fd >= 0 &&
            (polls[2].revents & (POLLERR | POLLHUP | POLLNVAL))) {
            disconnect_ipc(&ipc_fd, &queue);
        }
        if (ipc_fd >= 0 && (polls[2].revents & POLLIN) && !drain_ipc(ipc_fd))
            disconnect_ipc(&ipc_fd, &queue);
        if (ipc_fd >= 0 && queue.count &&
            !flush_commands(ipc_fd, &queue))
            disconnect_ipc(&ipc_fd, &queue);
    }
}

void _start(void) {
    application();
    sys_exit(0);
}
#endif
