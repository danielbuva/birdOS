/* Host fault-injection harness. It includes the production launcher so every
 * assertion below executes the exact favorites and poll decision code shipped
 * in the freestanding AArch64 binary. */

#include <stdio.h>
#include <string.h>

#define BIRD_HOST_TEST 1
#include "../../../launcher/bird-launcher.c"

#define FAKE_FD 41
#define EIO_LINUX 5
#define EBADF_LINUX 9

static long fake_now_ms;
static long fake_open_result;
static unsigned fake_open_calls;
static unsigned fake_create_calls;
static unsigned fake_rename_calls;
static unsigned fake_close_calls;
static const char *fake_payload;
static u64 fake_payload_bytes;
static u64 fake_payload_offset;
static long fake_terminal_read;
static unsigned fake_sleep_calls;
static s64 fake_last_sleep_ns;

static int check(int condition, const char *message) {
    if (condition) return 1;
    fprintf(stderr, "launcher runtime test failure: %s\n", message);
    return 0;
}

long bird_test_syscall6(long number, long a0, long a1, long a2, long a3,
                        long a4, long a5) {
    (void)a0;
    (void)a3;
    (void)a4;
    (void)a5;
    if (number == 56) {
        if ((int)a2 & O_CREAT) fake_create_calls++;
        fake_open_calls++;
        return fake_open_result;
    }
    if (number == 57) {
        fake_close_calls++;
        return 0;
    }
    if (number == 82 || number == 35) return 0;
    if (number == 38) {
        fake_rename_calls++;
        return 0;
    }
    if (number == 63) {
        u64 available;
        u64 bytes;
        if (fake_payload_offset >= fake_payload_bytes)
            return fake_terminal_read;
        available = fake_payload_bytes - fake_payload_offset;
        bytes = available < (u64)a2 ? available : (u64)a2;
        memcpy((void *)a1, fake_payload + fake_payload_offset, (size_t)bytes);
        fake_payload_offset += bytes;
        return (long)bytes;
    }
    if (number == 64) return a2; /* discard production diagnostics */
    if (number == 101) {
        const struct timespec *request = (const struct timespec *)a0;
        fake_sleep_calls++;
        fake_last_sleep_ns = request->sec * 1000000000L + request->nsec;
        return 0;
    }
    if (number == 113) {
        struct timespec *value = (struct timespec *)a1;
        value->sec = fake_now_ms / 1000;
        value->nsec = (fake_now_ms % 1000) * 1000000L;
        return 0;
    }
    return -EBADF_LINUX;
}

static void reset_fake_file(long open_result, const char *payload,
                            long terminal_read) {
    fake_open_result = open_result;
    fake_open_calls = 0;
    fake_create_calls = 0;
    fake_rename_calls = 0;
    fake_payload = payload ? payload : "";
    fake_payload_bytes = payload ? (u64)strlen(payload) : 0;
    fake_payload_offset = 0;
    fake_terminal_read = terminal_read;
}

static void reset_favorites(void) {
    clear_favorites();
    favorites_loaded = 0;
    favorites_retry_count = 0;
    favorites_retry_ms = FAVORITES_RETRY_INITIAL_MS;
    next_favorites_retry = 0;
    storage_ready = 1;
}

int main(void) {
    char partial[CATALOG_PATH_MAX_BYTES + 8U];
    char complete[CATALOG_PATH_MAX_BYTES * 2U + 8U];
    u64 due;
    unsigned opens;
    u64 delay;
    int ok = 1;

    /* ENOENT alone establishes a new, successfully loaded empty collection. */
    reset_favorites();
    fake_now_ms = 1000;
    reset_fake_file(-ENOENT, 0, 0);
    load_favorites();
    ok &= check(favorites_loaded && favorite_count == 0,
                "ENOENT did not become a loaded empty collection");

    /* Any other open failure remains fail-closed and schedules a timed retry. */
    reset_favorites();
    set_favorite(0, 1);
    favorite_count = 1;
    fake_now_ms = 2000;
    reset_fake_file(-EIO_LINUX, 0, 0);
    load_favorites();
    ok &= check(!favorites_loaded && favorite_count == 0 && !is_favorite(0),
                "open error retained a partial/stale favorites view");
    ok &= check(next_favorites_retry == 2100,
                "open error did not schedule the initial bounded retry");
    opens = fake_open_calls;
    fake_now_ms = 2099;
    load_favorites();
    ok &= check(fake_open_calls == opens,
                "favorites retried before its bounded retry deadline");

    /* A complete line followed by an I/O error must not leak its partial bit. */
    reset_favorites();
    fake_now_ms = 3000;
    snprintf(partial, sizeof(partial), "%s\n", catalog_entries[0].path);
    reset_fake_file(FAKE_FD, partial, -EIO_LINUX);
    load_favorites();
    due = next_favorites_retry;
    ok &= check(!favorites_loaded && favorite_count == 0 && !is_favorite(0),
                "read error published a partially parsed bitmap");
    fake_open_calls = 0;
    fake_create_calls = 0;
    fake_rename_calls = 0;
    ok &= check(save_favorites() < 0 && fake_open_calls == 0 &&
                    fake_create_calls == 0 && fake_rename_calls == 0,
                "incomplete load was allowed to create or rename favorites");

    /* The first successful retry consumes the full file and publishes at EOF. */
    snprintf(complete, sizeof(complete), "%s\n%s\n",
             catalog_entries[0].path, catalog_entries[1].path);
    fake_now_ms = (long)due - 1;
    reset_fake_file(FAKE_FD, complete, 0);
    load_favorites();
    ok &= check(!favorites_loaded && fake_open_calls == 0,
                "successful source was opened before the retry deadline");
    fake_now_ms = (long)due;
    load_favorites();
    ok &= check(favorites_loaded && favorite_count == 2 &&
                    is_favorite(0) && is_favorite(1),
                "successful later retry did not publish the full bitmap");
    ok &= check(next_favorites_retry == 0 &&
                    favorites_retry_ms == FAVORITES_RETRY_INITIAL_MS,
                "successful retry did not reset retry state");

    /* These helpers are used by the production ppoll loop. Exercise the
     * interrupted/error split, every broken-descriptor bit, EBADF, and cap. */
    ok &= check(classify_poll_result(-EINTR) == POLL_RESULT_INTERRUPTED,
                "EINTR was not classified as an immediate retry");
    ok &= check(classify_poll_result(-EBADF_LINUX) == POLL_RESULT_FAILED,
                "EBADF was not classified as recoverable poll failure");
    ok &= check(classify_poll_result(0) == POLL_RESULT_READY,
                "poll timeout was not classified as ready processing");
    ok &= check(poll_descriptor_failed(POLLERR) &&
                    poll_descriptor_failed(POLLHUP) &&
                    poll_descriptor_failed(POLLNVAL) &&
                    !poll_descriptor_failed(POLLIN),
                "poll descriptor error/hup/nval classification is incomplete");
    delay = POLL_RETRY_INITIAL_MS;
    fake_sleep_calls = 0;
    for (opens = 0; opens < 32U; opens++)
        delay = recover_poll_delay(delay);
    ok &= check(delay == POLL_RETRY_MAX_MS &&
                    next_poll_retry_ms(delay) == POLL_RETRY_MAX_MS &&
                    fake_sleep_calls == 32U &&
                    fake_last_sleep_ns == (s64)POLL_RETRY_MAX_MS * 1000000L,
                "launcher poll recovery did not sleep or cap its backoff");

    /* A descriptor can disappear while a nonzero hat value is latched. The
     * replacement device's first same-axis press must not be suppressed. */
    axis_x = 1;
    axis_y = -1;
    input_fd = 77;
    fake_close_calls = 0;
    abandon_input();
    ok &= check(axis_x == 0 && axis_y == 0 && input_fd == -1 &&
                    fake_close_calls == 1,
                "input fault did not close its descriptor and reset latches");
    ok &= check(update_axis_latch(&axis_x, 1) == 1 &&
                    update_axis_latch(&axis_x, 1) == 0 &&
                    update_axis_latch(&axis_x, 0) == 0 &&
                    update_axis_latch(&axis_x, 1) == 1,
                "first same-axis press after reconnect was not edge-triggered");

    if (!ok) return 1;
    puts("launcher runtime C tests: PASS");
    return 0;
}
