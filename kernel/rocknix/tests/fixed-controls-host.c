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

static pid_t test_parent;
static int inject_wait_eintr;
static int inject_read_eintr;
static int fake_input_read;
static long fake_input_result;
static int fake_poll_recovery;
static unsigned fake_close_calls;
static unsigned fake_sleep_calls;
static u64 fake_sleep_ns;

static int check(int condition, const char *message) {
    if (condition) return 1;
    fprintf(stderr, "fixed-controls C test failure: %s\n", message);
    return 0;
}

long bird_test_syscall6(long number, long a0, long a1, long a2, long a3,
                        long a4, long a5) {
    (void)a3;
    (void)a4;
    (void)a5;
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
        if (fake_poll_recovery && a0 >= 100) {
            fake_close_calls++;
            return 0;
        }
        return close((int)a0);
    }
    if (number == 63) {
        if (fake_input_read) return fake_input_result;
        if (getpid() == test_parent && inject_read_eintr) {
            inject_read_eintr = 0;
            return -EINTR;
        }
        return (long)read((int)a0, (void *)a1, (size_t)a2);
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
    struct input_source read_source = {100, GAMEPAD_NAME};
    u64 delay;
    unsigned step;
    int ok = 1;

    if (argc != 2) {
        fprintf(stderr, "usage: %s NONEXECUTABLE\n", argv[0]);
        return 2;
    }
    test_parent = getpid();

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
    ok &= check(process_source(&read_source, SOURCE_GAMEPAD, &state) == 1,
                "input read EINTR caused descriptor loss");
    fake_input_result = -EAGAIN;
    ok &= check(process_source(&read_source, SOURCE_GAMEPAD, &state) == 1,
                "input read EAGAIN caused descriptor loss");
    fake_input_result = -EBADF_LINUX;
    ok &= check(process_source(&read_source, SOURCE_GAMEPAD, &state) == 0,
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

    if (!ok) return 1;
    puts("fixed-controls C tests: PASS");
    return 0;
}
