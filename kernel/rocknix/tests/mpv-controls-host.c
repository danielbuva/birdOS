/* Host behavioral harness for Bird's fixed RG34XX-SP MPV event mapping. */

#include <stdio.h>
#include <string.h>

#define timespec bird_timespec
#define pollfd bird_pollfd
#define BIRD_HOST_TEST 1
#include "../stock-root/bird-mpv-controls.c"
#undef pollfd
#undef timespec

static long send_results[4];
static u32 send_result_count;
static u32 send_result_index;
static long send_flags;

long bird_test_syscall6(long number, long a0, long a1, long a2, long a3,
                        long a4, long a5) {
    (void)a0;
    (void)a1;
    (void)a2;
    (void)a4;
    (void)a5;
    if (number == 206 && send_result_index < send_result_count) {
        send_flags = a3;
        return send_results[send_result_index++];
    }
    return -38;
}

static int check(int condition, const char *message) {
    if (condition) return 1;
    fprintf(stderr, "MPV controls C test failure: %s\n", message);
    return 0;
}

static void reset_fixture(struct control_state *state,
                          struct command_queue *queue) {
    memset(state, 0, sizeof(*state));
    memset(queue, 0, sizeof(*queue));
}

static void key(struct control_state *state, struct command_queue *queue,
                u16 code, s32 value) {
    struct input_event event;
    memset(&event, 0, sizeof(event));
    event.type = EV_KEY;
    event.code = code;
    event.value = value;
    handle_gamepad(&event, state, queue);
}

static int commands_equal(const struct command_queue *queue,
                          const char *const *expected, u32 count,
                          const char *message) {
    u32 index;
    if (!check(queue->count == count, message)) return 0;
    for (index = 0U; index < count; index++) {
        u32 slot = (queue->head + index) % COMMAND_QUEUE_COUNT;
        if (!check(strcmp(queue->entries[slot].text, expected[index]) == 0,
                   message))
            return 0;
    }
    return 1;
}

int main(void) {
    struct control_state state;
    struct command_queue queue;
    int ok = 1;
    static const char *const regular[] = {
        command_pause,
        command_frame_step,
        command_audio,
        command_progress,
        command_seek_backward_short,
        command_seek_forward_short,
        command_seek_backward_long,
        command_seek_forward_long,
        command_chapter_previous,
        command_chapter_next,
    };
    static const u16 regular_codes[] = {
        BIRD_BUTTON_A,
        BIRD_BUTTON_B,
        BIRD_BUTTON_X,
        BIRD_BUTTON_Y,
        BTN_DPAD_LEFT,
        BTN_DPAD_RIGHT,
        BTN_DPAD_DOWN,
        BTN_DPAD_UP,
        BTN_TL2,
        BTN_TR2,
    };
    static const char *const flipped_commands[] = {
        command_pause,
        command_frame_step,
        command_audio,
        command_progress,
        command_seek_forward_short,
        command_seek_backward_long,
        command_seek_forward_long,
        command_seek_backward_short,
        command_playlist_previous,
        command_playlist_next,
    };
    static const u16 flipped_codes[] = {
        BTN_DPAD_LEFT,
        BTN_DPAD_DOWN,
        BTN_DPAD_UP,
        BTN_DPAD_RIGHT,
        BTN_EAST,
        BTN_SOUTH,
        BTN_WEST,
        BTN_NORTH,
        BTN_TL2,
        BTN_TR2,
    };
    static const char *const picture[] = {
        command_contrast_down,
        command_contrast_up,
        command_saturation_down,
        command_saturation_up,
    };
    static const u16 picture_codes[] = {
        BTN_DPAD_LEFT,
        BTN_DPAD_RIGHT,
        BTN_DPAD_DOWN,
        BTN_DPAD_UP,
    };
    u32 index;

    ok &= check(BTN_SOUTH == 304 && BTN_EAST == 305 && BTN_NORTH == 307 &&
                    BTN_WEST == 308 && BTN_TL == 310 && BTN_TR == 311 &&
                    BTN_TL2 == 312 && BTN_TR2 == 313 && BTN_SELECT == 314 &&
                    BTN_START == 315 && BTN_MODE == 316 &&
                    BTN_DPAD_UP == 544 && BTN_DPAD_DOWN == 545 &&
                    BTN_DPAD_LEFT == 546 && BTN_DPAD_RIGHT == 547,
                "fixed H700 raw button codes changed");
    ok &= check(BIRD_BUTTON_A == BTN_EAST &&
                    BIRD_BUTTON_B == BTN_SOUTH &&
                    BIRD_BUTTON_X == BTN_WEST &&
                    BIRD_BUTTON_Y == BTN_NORTH,
                "physical RG34XX-SP face labels changed");
    ok &= check(strcmp(command_contrast_down,
                       "{\"command\":[\"osd-auto\",\"add\",\"contrast\",-1]}\n") == 0 &&
                    strcmp(command_contrast_up,
                           "{\"command\":[\"osd-auto\",\"add\",\"contrast\",1]}\n") == 0 &&
                    strcmp(command_saturation_down,
                           "{\"command\":[\"osd-auto\",\"add\",\"saturation\",-1]}\n") == 0 &&
                    strcmp(command_saturation_up,
                           "{\"command\":[\"osd-auto\",\"add\",\"saturation\",1]}\n") == 0 &&
                    strcmp(command_brightness_down,
                           "{\"command\":[\"osd-auto\",\"add\",\"brightness\",-1]}\n") == 0 &&
                    strcmp(command_brightness_up,
                           "{\"command\":[\"osd-auto\",\"add\",\"brightness\",1]}\n") == 0,
                "picture adjustments are not one point per press");
    ok &= check(strcmp(command_audio,
                       "{\"command\":[\"osd-auto\",\"cycle\",\"audio\"]}\n") == 0 &&
                    strcmp(command_volume_down,
                           "{\"command\":[\"osd-auto\",\"add\",\"volume\",-2]}\n") == 0 &&
                    strcmp(command_volume_up,
                           "{\"command\":[\"osd-auto\",\"add\",\"volume\",2]}\n") == 0,
                "audio or player-volume command changed");

    reset_fixture(&state, &queue);
    {
        u64 bits[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] = {0U};
        bits[BTN_MODE / 64U] |= 1UL << (BTN_MODE % 64U);
        bits[BTN_TL / 64U] |= 1UL << (BTN_TL % 64U);
        bits[BTN_SELECT / 64U] |= 1UL << (BTN_SELECT % 64U);
        bits[BTN_START / 64U] |= 1UL << (BTN_START % 64U);
        apply_key_snapshot(&state, bits);
        ok &= check(state.menu_held && state.left_shoulder_held &&
                        state.left_shoulder_used &&
                        !state.right_shoulder_held &&
                        !state.right_shoulder_used && state.select_held &&
                        state.start_held && state.exit_chord_latched &&
                        state.select_pending == PENDING_BUTTON_NONE &&
                        state.start_pending == PENDING_BUTTON_NONE,
                    "held-key snapshot did not restore modifier/chord state");
    }

    reset_fixture(&state, &queue);
    for (index = 0U; index < sizeof(regular_codes) / sizeof(regular_codes[0]);
         index++) {
        key(&state, &queue, regular_codes[index], 1);
        key(&state, &queue, regular_codes[index], 0);
    }
    ok &= commands_equal(&queue, regular,
                         (u32)(sizeof(regular) / sizeof(regular[0])),
                         "regular control mapping changed");

    reset_fixture(&state, &queue);
    key(&state, &queue, BIRD_BUTTON_B, 1);
    key(&state, &queue, BIRD_BUTTON_B, 0);
    ok &= commands_equal(&queue,
                         (const char *const[]){command_frame_step}, 1U,
                         "physical B emitted pause or more than one frame step");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_TL, 1);
    ok &= check(queue.count == 0U,
                "left bumper adjusted volume before chord resolution");
    key(&state, &queue, BTN_TL, 0);
    key(&state, &queue, BTN_TR, 1);
    ok &= check(queue.count == 1U,
                "right bumper adjusted volume before chord resolution");
    key(&state, &queue, BTN_TR, 0);
    ok &= commands_equal(
        &queue,
        (const char *const[]){command_volume_down, command_volume_up}, 2U,
        "bumper taps did not restore player-relative volume");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_SELECT, 1);
    ok &= check(queue.count == 0U, "Select acted before chord could resolve");
    key(&state, &queue, BTN_SELECT, 0);
    ok &= commands_equal(&queue, (const char *const[]){command_subtitle}, 1U,
                         "Select did not cycle subtitles exactly once");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_START, 1);
    ok &= check(queue.count == 0U, "Start acted before chord could resolve");
    key(&state, &queue, BTN_START, 0);
    ok &= commands_equal(
        &queue, (const char *const[]){command_subtitle_visibility}, 1U,
        "Start did not toggle subtitle visibility exactly once");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_SELECT, 1);
    key(&state, &queue, BTN_START, 1);
    key(&state, &queue, BTN_SELECT, 0);
    key(&state, &queue, BTN_START, 0);
    ok &= check(queue.count == 0U,
                "Select+Start leaked a media action before global exit");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_START, 1);
    key(&state, &queue, BTN_SELECT, 1);
    key(&state, &queue, BTN_START, 0);
    key(&state, &queue, BTN_SELECT, 0);
    ok &= check(queue.count == 0U,
                "reverse Start+Select leaked a media action before global exit");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_SELECT, 1);
    key(&state, &queue, BTN_START, 1);
    key(&state, &queue, BTN_START, 0);
    key(&state, &queue, BTN_SELECT, 0);
    ok &= check(queue.count == 0U,
                "Select+Start reverse release leaked a media action");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_TL, 1);
    for (index = 0U;
         index < sizeof(flipped_codes) / sizeof(flipped_codes[0]); index++) {
        key(&state, &queue, flipped_codes[index], 1);
        key(&state, &queue, flipped_codes[index], 0);
    }
    key(&state, &queue, BTN_SELECT, 1);
    key(&state, &queue, BTN_SELECT, 0);
    key(&state, &queue, BTN_TL, 0);
    {
        const char *expected[11];
        for (index = 0U; index < 10U; index++)
            expected[index] = flipped_commands[index];
        expected[10] = command_audio;
        ok &= commands_equal(&queue, expected, 11U,
                             "one-handed layer mapping changed");
    }

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_TL, 1);
    key(&state, &queue, BTN_START, 1);
    key(&state, &queue, BTN_START, 0);
    key(&state, &queue, BTN_TL, 0);
    ok &= commands_equal(
        &queue, (const char *const[]){command_subtitle_visibility}, 1U,
        "shoulder+Start leaked tap volume or changed subtitle behavior");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_TL, 1);
    key(&state, &queue, BTN_SELECT, 1);
    key(&state, &queue, BTN_START, 1);
    key(&state, &queue, BTN_START, 0);
    key(&state, &queue, BTN_SELECT, 0);
    key(&state, &queue, BTN_TL, 0);
    ok &= check(queue.count == 0U,
                "shoulder+Select+Start leaked audio, subtitle, or volume");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_MODE, 1);
    for (index = 0U; index < sizeof(picture_codes) / sizeof(picture_codes[0]);
         index++)
        key(&state, &queue, picture_codes[index], 1);
    key(&state, &queue, BTN_MODE, 0);
    ok &= commands_equal(&queue, picture, 4U,
                         "Menu picture-adjustment mapping changed");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_MODE, 1);
    key(&state, &queue, BTN_TL, 1);
    key(&state, &queue, BTN_TL, 0);
    key(&state, &queue, BTN_TR, 1);
    key(&state, &queue, BTN_TR, 0);
    key(&state, &queue, BTN_MODE, 0);
    ok &= commands_equal(
        &queue,
        (const char *const[]){command_brightness_down, command_brightness_up},
        2U, "Menu+bumper changed volume or missed player brightness");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_TL, 1);
    key(&state, &queue, BTN_MODE, 1);
    key(&state, &queue, BTN_MODE, 0);
    key(&state, &queue, BTN_TL, 0);
    ok &= commands_equal(&queue,
                         (const char *const[]){command_brightness_down}, 1U,
                         "bumper-first brightness chord leaked player volume");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_TL, 1);
    key(&state, &queue, BTN_MODE, 1);
    key(&state, &queue, BTN_DPAD_LEFT, 1);
    key(&state, &queue, BTN_DPAD_LEFT, 0);
    key(&state, &queue, BTN_MODE, 0);
    key(&state, &queue, BTN_TL, 0);
    ok &= commands_equal(
        &queue,
        (const char *const[]){command_brightness_down, command_contrast_down},
        2U, "shoulder+Menu+D-pad leaked player volume");

    reset_fixture(&state, &queue);
    {
        u64 bits[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] = {0U};
        bits[BTN_TR / 64U] |= 1UL << (BTN_TR % 64U);
        apply_key_snapshot(&state, bits);
    }
    key(&state, &queue, BTN_TR, 0);
    ok &= check(queue.count == 0U,
                "reconnect snapshot emitted phantom bumper volume");

    reset_fixture(&state, &queue);
    key(&state, &queue, BTN_TR, 1);
    {
        struct input_event dropped;
        memset(&dropped, 0, sizeof(dropped));
        dropped.type = EV_SYN;
        dropped.code = SYN_DROPPED;
        handle_gamepad(&dropped, &state, &queue);
        key(&state, &queue, BIRD_BUTTON_A, 1);
        ok &= check(queue.count == 0U,
                    "event after SYN_DROPPED was not discarded");
        dropped.code = SYN_REPORT;
        handle_gamepad(&dropped, &state, &queue);
    }
    key(&state, &queue, BIRD_BUTTON_A, 1);
    ok &= commands_equal(&queue, (const char *const[]){command_pause}, 1U,
                         "SYN_DROPPED left the one-handed layer latched");

    reset_fixture(&state, &queue);
    for (index = 0U; index < COMMAND_QUEUE_COUNT + 1U; index++)
        key(&state, &queue, BIRD_BUTTON_A, 1);
    ok &= check(queue.count == COMMAND_QUEUE_COUNT,
                "bounded command queue exceeded its fixed capacity");

    reset_fixture(&state, &queue);
    (void)queue_command(&queue, command_pause);
    send_results[0] = 5;
    send_results[1] = -EAGAIN;
    send_result_count = 2U;
    send_result_index = 0U;
    send_flags = 0;
    ok &= check(flush_commands(7, &queue) && queue.count == 1U &&
                    queue.entries[queue.head].sent == 5U &&
                    send_flags == MSG_NOSIGNAL,
                "partial/EAGAIN IPC write was not retained safely");
    send_results[0] =
        (long)(queue.entries[queue.head].length - queue.entries[queue.head].sent);
    send_result_count = 1U;
    send_result_index = 0U;
    ok &= check(flush_commands(7, &queue) && queue.count == 0U,
                "queued IPC command did not resume after EAGAIN");

    reset_fixture(&state, &queue);
    (void)queue_command(&queue, command_pause);
    send_results[0] = -EINTR;
    send_results[1] = queue.entries[queue.head].length;
    send_result_count = 2U;
    send_result_index = 0U;
    ok &= check(flush_commands(7, &queue) && queue.count == 0U,
                "EINTR interrupted the queued IPC command");

    reset_fixture(&state, &queue);
    (void)queue_command(&queue, command_pause);
    send_results[0] = -32;
    send_result_count = 1U;
    send_result_index = 0U;
    ok &= check(!flush_commands(7, &queue),
                "fatal IPC write was treated as successful");
    {
        int ipc_fd = 7;
        disconnect_ipc(&ipc_fd, &queue);
        ok &= check(ipc_fd == -1 && queue.count == 0U,
                    "IPC reconnect retained stale commands");
    }

    if (!ok) return 1;
    puts("MPV controls C tests: PASS");
    return 0;
}
