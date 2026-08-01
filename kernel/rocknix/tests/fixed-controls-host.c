/* Host behavioral harness for the exact production exec handshake and poll
 * recovery code. Linux syscall numbers are mapped to host libc only here. */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define timespec bird_timespec
#define pollfd bird_pollfd
#define BIRD_HOST_TEST 1
#include "../stock-root/bird-fixed-controls.c"
#undef pollfd
#undef timespec

#define EBADF_LINUX 9
#define ENOENT_LINUX 2

static pid_t test_parent;
static int inject_wait_eintr;
static int inject_read_eintr;
static int fake_input_read;
static long fake_input_result;
static int fake_poll_recovery;
static unsigned fake_close_calls;
static unsigned fake_sleep_calls;
static u64 fake_sleep_ns;
static int fake_discovery;
static const char *fake_event_names[EVENT_SCAN_COUNT];
static unsigned fake_discovery_open_calls;
static unsigned fake_discovery_ioctl_calls;
static unsigned fake_discovery_close_calls;
static long fake_inotify_init_result;
static long fake_inotify_add_result;
static unsigned fake_inotify_init_calls;
static unsigned fake_inotify_add_calls;
static int fake_watch_fd;
static const void *fake_watch_payload;
static u64 fake_watch_payload_bytes;
static int fake_watch_consumed;
static int fake_input_contract_mismatch;

static int check(int condition, const char *message) {
    if (condition) return 1;
    fprintf(stderr, "fixed-controls C test failure: %s\n", message);
    return 0;
}

static void reset_discovery_fixture(void) {
    memset(fake_event_names, 0, sizeof(fake_event_names));
    fake_discovery = 1;
    fake_discovery_open_calls = 0;
    fake_discovery_ioctl_calls = 0;
    fake_discovery_close_calls = 0;
    fake_inotify_init_result = -EBADF_LINUX;
    fake_inotify_add_result = -EBADF_LINUX;
    fake_inotify_init_calls = 0;
    fake_inotify_add_calls = 0;
    fake_watch_fd = -1;
    fake_watch_payload = 0;
    fake_watch_payload_bytes = 0;
    fake_watch_consumed = 0;
    fake_input_contract_mismatch = 0;
}

long bird_test_syscall6(long number, long a0, long a1, long a2, long a3,
                        long a4, long a5) {
    (void)a3;
    (void)a4;
    (void)a5;
    if (number == 26) {
        fake_inotify_init_calls++;
        return fake_inotify_init_result;
    }
    if (number == 27) {
        fake_inotify_add_calls++;
        return fake_inotify_add_result;
    }
    if (number == 56 && fake_discovery) {
        int index = -1;
        fake_discovery_open_calls++;
        if (sscanf((const char *)a1, "/dev/input/event%d", &index) != 1 ||
            index < 0 || index >= EVENT_SCAN_COUNT || !fake_event_names[index])
            return -ENOENT_LINUX;
        return 1000 + index;
    }
    if (number == 59) {
        int *pipes = (int *)a0;
        if (pipe(pipes) < 0) return -1;
        if (fcntl(pipes[0], F_SETFD, FD_CLOEXEC) < 0 ||
            fcntl(pipes[1], F_SETFD, FD_CLOEXEC) < 0) {
            close(pipes[0]);
            close(pipes[1]);
            return -1;
        }
        return 0;
    }
    if (number == 57) {
        if (fake_discovery && (a0 >= 1000 || a0 == fake_watch_fd)) {
            fake_discovery_close_calls++;
            return 0;
        }
        if (fake_poll_recovery && a0 >= 100) {
            fake_close_calls++;
            return 0;
        }
        return close((int)a0);
    }
    if (number == 63) {
        if ((int)a0 == fake_watch_fd && fake_watch_payload) {
            u64 bytes;
            if (fake_watch_consumed) return -EAGAIN;
            bytes = fake_watch_payload_bytes < (u64)a2
                        ? fake_watch_payload_bytes : (u64)a2;
            memcpy((void *)a1, fake_watch_payload, (size_t)bytes);
            fake_watch_consumed = 1;
            return (long)bytes;
        }
        if (fake_input_read) return fake_input_result;
        if (getpid() == test_parent && inject_read_eintr) {
            inject_read_eintr = 0;
            return -EINTR;
        }
        return (long)read((int)a0, (void *)a1, (size_t)a2);
    }
    if (number == 29 && fake_discovery && a0 >= 1000) {
        static const u64 expected_key[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] =
            BIRD_DEVICE_INPUT_KEY_BITMAP_WORDS;
        static const u64 expected_ff[BIRD_DEVICE_INPUT_FF_BITMAP_WORD_COUNT] =
            BIRD_DEVICE_INPUT_FF_BITMAP_WORDS;
        int index = (int)a0 - 1000;
        fake_discovery_ioctl_calls++;
        if (index < 0 || index >= EVENT_SCAN_COUNT || !fake_event_names[index])
            return -EBADF_LINUX;
        if ((u64)a1 == EVIOCGNAME_128)
            snprintf((char *)a2, 128U, "%s", fake_event_names[index]);
        else if ((u64)a1 == EVIOCGID) {
            struct input_id *id = (struct input_id *)a2;
            id->bus = BIRD_DEVICE_INPUT_BUS;
            id->vendor = BIRD_DEVICE_INPUT_VENDOR;
            id->product = BIRD_DEVICE_INPUT_PRODUCT;
            id->version = BIRD_DEVICE_INPUT_VERSION;
        } else if ((u64)a1 == EVIOCGBIT_EV)
            *(u64 *)a2 = BIRD_DEVICE_INPUT_EV_BITMAP;
        else if ((u64)a1 == EVIOCGBIT_KEY)
            memcpy((void *)a2, expected_key, sizeof(expected_key));
        else if ((u64)a1 == EVIOCGBIT_ABS)
            *(u64 *)a2 = BIRD_DEVICE_INPUT_ABS_BITMAP;
        else if ((u64)a1 == EVIOCGBIT_FF) {
            memcpy((void *)a2, expected_ff, sizeof(expected_ff));
            if (fake_input_contract_mismatch) ((u64 *)a2)[1] ^= 1U;
        } else
            return -EBADF_LINUX;
        return 0;
    }
    if (number == 64) {
        if ((int)a0 == 1) return a2; /* discard diagnostics */
        return (long)write((int)a0, (const void *)a1, (size_t)a2);
    }
    if (number == 73) {
        if (fake_poll_recovery && a0 == 0 && a1 == 0) {
            const struct bird_timespec *timeout =
                (const struct bird_timespec *)a2;
            fake_sleep_calls++;
            fake_sleep_ns = (u64)timeout->sec * 1000000000UL +
                            (u64)timeout->nsec;
            return 0;
        }
        return -EBADF_LINUX;
    }
    if (number == 220) {
        pid_t child = fork();
        return child < 0 ? -1 : (long)child;
    }
    if (number == 221)
        return (long)execve((const char *)a0, (char *const *)a1,
                            (char *const *)a2);
    if (number == 260) {
        if (getpid() == test_parent && inject_wait_eintr) {
            inject_wait_eintr = 0;
            return -EINTR;
        }
        return (long)waitpid((pid_t)a0, (int *)a1, (int)a2);
    }
    if (number == 93) _exit((int)a0);
    return -EBADF_LINUX;
}

int main(int argc, char **argv) {
    struct input_source sources[SOURCE_COUNT] = {
        {100, GAMEPAD_NAME},
        {101, VOLUME_NAME},
        {102, POWER_NAME},
        {103, LID_NAME},
    };
    struct control_state state = {1, 1, 1, 1, 1, 1, 1, 1234};
    struct suspend_state suspend = {0, 0, 0};
    struct input_source read_source = {100, GAMEPAD_NAME};
    u64 delay;
    unsigned step;
    int ok = 1;
    struct input_event key = {0};
    struct control_state discovery_state = {0, 0, 0, 0, 0, 0, 0, 0};
    struct input_source discovery_sources[SOURCE_COUNT] = {
        {-1, GAMEPAD_NAME},
        {-1, VOLUME_NAME},
        {-1, POWER_NAME},
        {-1, LID_NAME},
    };
    struct {
        s32 wd;
        u32 mask;
        u32 cookie;
        u32 len;
        char name[16];
    } creation_event = {0};
    struct bird_timespec discovery_timeout;

    if (argc != 2) {
        fprintf(stderr, "usage: %s NONEXECUTABLE\n", argv[0]);
        return 2;
    }
    test_parent = getpid();

    state.menu_held = 0;
    state.select_held = 0;
    state.start_held = 0;
    state.exit_latched = 0;
    key.type = EV_KEY;
    key.value = 1;
    key.code = BTN_MODE;
    handle_gamepad(&key, &state);
    key.code = BTN_START;
    handle_gamepad(&key, &state);
    ok &= check(!state.exit_latched,
                "native Menu+Start incorrectly triggered Bird exit");
    key.value = 0;
    key.code = BTN_MODE;
    handle_gamepad(&key, &state);
    key.value = 1;
    key.code = BTN_SELECT;
    handle_gamepad(&key, &state);
    ok &= check(state.exit_latched,
                "Select+Start did not trigger Bird exit");
    clear_gamepad_state(&state);

    ok &= check(brightness_raw_target(125, 2499, -1) == 75,
                "five-percent brightness did not step down to three percent");
    ok &= check(brightness_raw_target(75, 2499, -1) == 25,
                "three-percent brightness did not step down to one percent");
    ok &= check(brightness_raw_target(25, 2499, -1) == 25,
                "one-percent brightness did not remain lit");
    ok &= check(brightness_raw_target(25, 2499, 1) == 75 &&
                    brightness_raw_target(75, 2499, 1) == 125,
                "low-end brightness up ladder is not reversible");
    ok &= check(brightness_raw_target(2499, 2499, 1) == 2499,
                "maximum brightness was not clamped");

    ok &= check(spawn_action("/usr/bin/true", 0, 0) == SPAWN_DISPATCHED,
                "valid executable was not dispatched");
    ok &= check(spawn_action("/definitely/missing/bird-helper", 0, 0) ==
                    SPAWN_EXEC_FAILED,
                "missing executable did not fail the exec handshake");
    ok &= check(spawn_action(argv[1], 0, 0) == SPAWN_EXEC_FAILED,
                "non-executable helper did not fail the exec handshake");
    inject_wait_eintr = 1;
    inject_read_eintr = 1;
    ok &= check(spawn_action("/usr/bin/true", "argument", 0) == SPAWN_DISPATCHED &&
                    !inject_wait_eintr && !inject_read_eintr,
                "exec handshake did not recover from wait/read EINTR");

    ok &= check(classify_poll_result(-EINTR) == POLL_RESULT_INTERRUPTED,
                "poll EINTR was not classified as an immediate retry");
    ok &= check(classify_poll_result(-EBADF_LINUX) == POLL_RESULT_FAILED,
                "poll EBADF was not classified as recovery");
    ok &= check(poll_descriptor_failed(POLLERR) &&
                    poll_descriptor_failed(POLLHUP) &&
                    poll_descriptor_failed(POLLNVAL) &&
                    !poll_descriptor_failed(POLLIN),
                "poll error/hup/nval classification is incomplete");

    fake_input_read = 1;
    fake_input_result = -EINTR;
    ok &= check(process_source(&read_source, SOURCE_GAMEPAD, &state,
                               &suspend) == 1,
                "input read EINTR caused descriptor loss");
    fake_input_result = -EAGAIN;
    ok &= check(process_source(&read_source, SOURCE_GAMEPAD, &state,
                               &suspend) == 1,
                "input read EAGAIN caused descriptor loss");
    fake_input_result = -EBADF_LINUX;
    ok &= check(process_source(&read_source, SOURCE_GAMEPAD, &state,
                               &suspend) == 0,
                "input read EBADF did not request descriptor recovery");
    fake_input_read = 0;

    fake_poll_recovery = 1;
    delay = recover_poll_failure(sources, &state, 1000000UL);
    ok &= check(fake_close_calls == SOURCE_COUNT &&
                    fake_sleep_calls == 1 && fake_sleep_ns == 1000000UL,
                "poll recovery did not close all sources and sleep once");
    ok &= check(delay == 2000000UL,
                "poll recovery did not advance its backoff");
    for (step = 0; step < 32U; step++) delay = next_poll_error_delay(delay);
    ok &= check(delay == (u64)DISCOVERY_RETRY_NS &&
                    next_poll_error_delay(delay) == (u64)DISCOVERY_RETRY_NS,
                "control poll backoff is not capped");
    ok &= check(sources[0].fd < 0 && sources[1].fd < 0 &&
                    sources[2].fd < 0 && sources[3].fd < 0 &&
                    !state.menu_held && !state.select_held &&
                    !state.start_held && !state.exit_latched &&
                    !state.volume_up_held && !state.volume_down_held &&
                    !state.repeat_direction && !state.repeat_at_ns,
                "poll recovery retained descriptors or held-key state");

    queue_power_suspend(&suspend);
    ok &= check(suspend.pending_suspend == PENDING_SUSPEND_POWER,
                "resume coordinator did not retain a power intent");
    queue_power_suspend(&suspend);
    ok &= check(suspend.pending_suspend == PENDING_SUSPEND_NONE,
                "second queued power edge did not cancel the toggle");
    queue_lid_suspend(&suspend, 1);
    ok &= check(suspend.pending_suspend == PENDING_SUSPEND_LID_CLOSE,
                "resume coordinator did not retain lid close");
    queue_lid_suspend(&suspend, 0);
    ok &= check(suspend.pending_suspend == PENDING_SUSPEND_NONE,
                "lid open did not cancel pending lid close");

    suspend.resume_in_flight = 1;
    suspend.pending_suspend = PENDING_SUSPEND_LID_CLOSE;
    suspend.resume_deadline_ns = 1234;
    ok &= check(complete_resume_state(&suspend) == PENDING_SUSPEND_LID_CLOSE &&
                    !suspend.resume_in_flight &&
                    suspend.pending_suspend == PENDING_SUSPEND_NONE &&
                    !suspend.resume_deadline_ns,
                "resume completion did not atomically consume one intent");

    suspend.resume_in_flight = 1;
    ok &= check(poll_timeout(sources, &state, &suspend, 0,
                            &discovery_timeout) == &discovery_timeout &&
                    discovery_timeout.sec == 0 &&
                    discovery_timeout.nsec == RESUME_READY_RETRY_NS,
                "resume completion lost its bounded transition poll");
    suspend.resume_in_flight = 0;

    reset_discovery_fixture();
    fake_event_names[0] = POWER_NAME;
    fake_event_names[1] = "H616 Audio Codec Headphone Jack";
    fake_event_names[2] = VOLUME_NAME;
    fake_event_names[3] = LID_NAME;
    fake_event_names[4] = GAMEPAD_NAME;
    discover_inputs(discovery_sources);
    ok &= check(discovery_sources[SOURCE_GAMEPAD].fd == 1004 &&
                    discovery_sources[SOURCE_VOLUME].fd == 1002 &&
                    discovery_sources[SOURCE_POWER].fd == 1000 &&
                    discovery_sources[SOURCE_LID].fd == 1003 &&
                    fake_discovery_open_calls == 5U &&
                    fake_discovery_ioctl_calls == 10U &&
                    fake_discovery_close_calls == 1U,
                "initial control discovery did not stop after the four sources");

    discovery_sources[SOURCE_GAMEPAD].fd = -1;
    reset_discovery_fixture();
    fake_event_names[7] = GAMEPAD_NAME;
    fake_input_contract_mismatch = 1;
    try_input_event(discovery_sources, 7);
    ok &= check(discovery_sources[SOURCE_GAMEPAD].fd < 0 &&
                    fake_discovery_open_calls == 1U &&
                    fake_discovery_ioctl_calls == 6U &&
                    fake_discovery_close_calls == 1U,
                "fixed controls accepted a mismatched H700 capability set");
    fake_input_contract_mismatch = 0;

    reset_discovery_fixture();
    fake_inotify_init_result = 90;
    fake_inotify_add_result = 1;
    fake_watch_fd = 90;
    ok &= check(open_input_watch() == 90 &&
                    fake_inotify_init_calls == 1U &&
                    fake_inotify_add_calls == 1U,
                "control input watch did not initialize exactly once");

    discovery_sources[SOURCE_GAMEPAD].fd = -1;
    fake_event_names[7] = GAMEPAD_NAME;
    creation_event.wd = 1;
    creation_event.mask = IN_CREATE;
    creation_event.len = sizeof(creation_event.name);
    snprintf(creation_event.name, sizeof(creation_event.name), "event7");
    fake_watch_payload = &creation_event;
    fake_watch_payload_bytes = sizeof(creation_event);
    ok &= check(process_input_watch(90, discovery_sources) == 1 &&
                    discovery_sources[SOURCE_GAMEPAD].fd == 1007 &&
                    fake_discovery_open_calls == 1U &&
                    fake_discovery_ioctl_calls == 6U,
                "control creation edge rescanned unrelated event nodes");

    discovery_sources[SOURCE_GAMEPAD].fd = -1;
    ok &= check(poll_timeout(discovery_sources, &discovery_state, &suspend, 0,
                            &discovery_timeout) == 0,
                "live discovery watch retained a periodic retry timeout");
    ok &= check(poll_timeout(discovery_sources, &discovery_state, &suspend, 1,
                            &discovery_timeout) == &discovery_timeout &&
                    discovery_timeout.sec == 0 &&
                    discovery_timeout.nsec == DISCOVERY_RETRY_NS,
                "inotify failure lost bounded polling fallback");
    ok &= check(input_event_index("event4", 7U) == 4 &&
                    input_event_index("event31", 8U) == 31 &&
                    input_event_index("event32", 8U) < 0 &&
                    input_event_index("mouse0", 7U) < 0,
                "control creation event accepted an ambiguous node");

    if (!ok) return 1;
    puts("fixed-controls C tests: PASS");
    return 0;
}
