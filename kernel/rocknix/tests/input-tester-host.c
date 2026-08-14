/* Host behavioral harness for the freestanding RG34XX-SP input tester. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define timespec bird_timespec
#define pollfd bird_pollfd
#define BIRD_HOST_TEST 1
#include "../../../launcher/bird-input-tester.c"
#undef pollfd
#undef timespec

#define EBADF_LINUX 9

static int fake_contract;
static int fake_contract_mismatch;
static int fake_rumble;
static int fake_grab;
static int grabbed_value = -1;
static int rumble_uploads;
static int rumble_plays;
static int rumble_stops;
static int rumble_erases;

static int check(int condition, const char *message) {
    if (condition) return 1;
    fprintf(stderr, "input-tester C test failure: %s\n", message);
    return 0;
}

long bird_test_syscall6(long number, long a0, long a1, long a2, long a3,
                        long a4, long a5) {
    (void)a0;
    (void)a3;
    (void)a4;
    (void)a5;
    if (number == 29 && fake_contract > 1) {
        if ((u64)a1 == EVIOCGNAME_128) {
            snprintf((char *)a2, 128U, "%s",
                     fake_contract == 2 ? "gpio-keys-volume" : "axp20x-pek");
            return 0;
        }
        if ((u64)a1 == EVIOCGBIT_KEY) {
            u64 *bits = (u64 *)a2;
            memset(bits, 0, sizeof(u64) * 12U);
            if (fake_contract == 2) {
                bits[KEY_VOLUMEDOWN / 64U] |=
                    1UL << (KEY_VOLUMEDOWN % 64U);
                bits[KEY_VOLUMEUP / 64U] |= 1UL << (KEY_VOLUMEUP % 64U);
            } else {
                bits[KEY_POWER / 64U] |= 1UL << (KEY_POWER % 64U);
            }
            return 0;
        }
        return -EBADF_LINUX;
    }
    if (number == 29 && fake_contract == 1) {
        static const u64 expected_key[BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT] =
            BIRD_DEVICE_INPUT_KEY_BITMAP_WORDS;
        static const u64 expected_ff[BIRD_DEVICE_INPUT_FF_BITMAP_WORD_COUNT] =
            BIRD_DEVICE_INPUT_FF_BITMAP_WORDS;
        if ((u64)a1 == EVIOCGNAME_128)
            snprintf((char *)a2, 128U, "%s", BIRD_DEVICE_INPUT_NAME);
        else if ((u64)a1 == EVIOCGID) {
            struct input_id *id = (struct input_id *)a2;
            id->bus = BIRD_DEVICE_INPUT_BUS;
            id->vendor = BIRD_DEVICE_INPUT_VENDOR;
            id->product = BIRD_DEVICE_INPUT_PRODUCT;
            id->version = BIRD_DEVICE_INPUT_VERSION;
        } else if ((u64)a1 == EVIOCGBIT_EV)
            *(u64 *)a2 = BIRD_DEVICE_INPUT_EV_BITMAP;
        else if ((u64)a1 == EVIOCGBIT_KEY) {
            memcpy((void *)a2, expected_key, sizeof(expected_key));
            if (fake_contract_mismatch) ((u64 *)a2)[4] ^= 1U;
        } else if ((u64)a1 == EVIOCGBIT_ABS)
            *(u64 *)a2 = BIRD_DEVICE_INPUT_ABS_BITMAP;
        else if ((u64)a1 == EVIOCGBIT_FF)
            memcpy((void *)a2, expected_ff, sizeof(expected_ff));
        else
            return -EBADF_LINUX;
        return 0;
    }
    if (number == 29 && fake_rumble) {
        if ((u64)a1 == EVIOCSFF) {
            ((struct ff_effect *)a2)->id = 7;
            rumble_uploads++;
            return 0;
        }
        if ((u64)a1 == EVIOCRMFF) {
            if (*(int *)a2 == 7) rumble_erases++;
            return 0;
        }
    }
    if (number == 29 && fake_grab && (u64)a1 == EVIOCGRAB) {
        grabbed_value = *(int *)a2;
        return 0;
    }
    if (number == 64 && fake_rumble) {
        const struct input_event *event = (const struct input_event *)a1;
        if ((u64)a2 != sizeof(*event) || event->type != EV_FF ||
            event->code != 7)
            return -EBADF_LINUX;
        if (event->value == 1)
            rumble_plays++;
        else if (event->value == 0)
            rumble_stops++;
        return a2;
    }
    return -EBADF_LINUX;
}

static void initialize_state(struct tester_state *state) {
    int index;
    memset(state, 0, sizeof(*state));
    for (index = 0; index < 4; index++) {
        state->axis_minimum[index] = -32768;
        state->axis_maximum[index] = 32767;
    }
    state->effect_id = -1;
}

int main(void) {
    static u32 guarded_frame[(BIRD_DEVICE_FB_WIDTH * BIRD_DEVICE_FB_HEIGHT) + 2];
    struct tester_state state;
    struct input_event event = {0};
    u32 all_buttons = (1U << BUTTON_COUNT) - 1U;
    int index;
    int ok = 1;

    initialize_state(&state);
    ok &= check(BUTTON_COUNT == 17, "all seventeen digital controls modeled");
    ok &= check(button_index_for_code(BIRD_BUTTON_A) == BUTTON_A &&
                    button_index_for_code(BIRD_BUTTON_B) == BUTTON_B &&
                    button_index_for_code(BIRD_BUTTON_X) == BUTTON_X &&
                    button_index_for_code(BIRD_BUTTON_Y) == BUTTON_Y,
                "physical face-button legends map to H700 raw codes");
    ok &= check(BIRD_BUTTON_X == BTN_NORTH && BIRD_BUTTON_Y == BTN_WEST,
                "printed X north and Y west follow physical RG34XX-SP");
    ok &= check(button_layouts[BUTTON_L1].x < button_layouts[BUTTON_L2].x &&
                    button_layouts[BUTTON_R1].x > button_layouts[BUTTON_R2].x,
                "L1/R1 are outer and L2/R2 are inner");
    ok &= check(button_layouts[BUTTON_DPAD_LEFT].width >= 62 &&
                    button_layouts[BUTTON_DPAD_RIGHT].width >= 62,
                "large LEFT and RIGHT labels have full-width controls");
    ok &= check(button_layouts[BUTTON_L3].x +
                        button_layouts[BUTTON_L3].width <
                    button_layouts[BUTTON_R3].x,
                "L3 and R3 regions remain separated");
    ok &= check(button_index_for_code(BTN_THUMBL) == BUTTON_L3 &&
                    button_index_for_code(BTN_THUMBR) == BUTTON_R3,
                "both stick clicks modeled");

    for (index = 0; index < BUTTON_COUNT; index++) {
        event.type = EV_KEY;
        event.code = button_codes[index];
        event.value = 1;
        ok &= check(handle_event(&state, &event, 100U) == HANDLE_CHANGED,
                    "button press changes visible state");
        if (index == BUTTON_X)
            ok &= check(strings_equal(state.last_event, "KEY X DOWN"),
                        "live event line names physical button press");
        event.value = 0;
        ok &= check(handle_event(&state, &event, 200U) == HANDLE_CHANGED,
                    "button release changes visible state");
    }
    ok &= check(state.seen_buttons == all_buttons && state.held_buttons == 0U,
                "every digital control retained in seen-ever checklist");

    initialize_state(&state);
    event.type = EV_KEY;
    event.code = BIRD_BUTTON_B;
    event.value = 1;
    (void)handle_event(&state, &event, 500U);
    ok &= check(!exit_hold_complete(&state, 500U + EXIT_HOLD_NS - 1U),
                "B tap cannot exit tester");
    ok &= check(exit_hold_complete(&state, 500U + EXIT_HOLD_NS),
                "one-second physical B hold exits tester");
    event.value = 0;
    (void)handle_event(&state, &event, 600U);
    ok &= check(!exit_hold_complete(&state, 500U + EXIT_HOLD_NS + 1U),
                "B release cancels exit hold");

    initialize_state(&state);
    for (index = 0; index < 4; index++) {
        event.type = EV_ABS;
        event.code = index == 0 ? ABS_X : index == 1 ? ABS_Y :
                     index == 2 ? ABS_RX : ABS_RY;
        event.value = -32768;
        ok &= check(handle_event(&state, &event, 0U) == HANDLE_CHANGED,
                    "negative stick edge changes state");
        event.value = 32767;
        ok &= check(handle_event(&state, &event, 0U) == HANDLE_CHANGED,
                    "positive stick edge changes state");
    }
    ok &= check(state.seen_axis_directions == 0xffU,
                "all eight analog directions retained in checklist");
    ok &= check(strings_equal(state.last_event, "ABS RY 32767"),
                "live event line reports current analog value");
    ok &= check(state.axis_observed_minimum[0] == -32768 &&
                    state.axis_observed_maximum[0] == 32767,
                "session log retains observed analog extrema");

    event.type = EV_SYN;
    event.code = SYN_DROPPED;
    event.value = 0;
    ok &= check(handle_event(&state, &event, 0U) == HANDLE_NONE &&
                    state.discard_until_report,
                "SYN_DROPPED starts discarding the damaged report");
    event.type = EV_KEY;
    event.code = BIRD_BUTTON_A;
    event.value = 1;
    ok &= check(handle_event(&state, &event, 0U) == HANDLE_NONE,
                "records after SYN_DROPPED discarded");
    event.type = EV_SYN;
    event.code = SYN_REPORT;
    ok &= check(handle_event(&state, &event, 0U) == HANDLE_RESYNC &&
                    !state.discard_until_report,
                "same-batch synchronization boundary requests resync");

    for (index = 0; index < AUXILIARY_COUNT; index++) {
        ok &= check(update_auxiliary(&state, index, 1),
                    "auxiliary press changes visible state");
        ok &= check(update_auxiliary(&state, index, 0),
                    "auxiliary release changes visible state");
    }
    ok &= check(state.seen_auxiliary == 0x7U,
                "volume down, volume up and power retained in checklist");
    ok &= check(strings_equal(state.last_event, "KEY POWER UP"),
                "live event line reports auxiliary press and release");

    state.seen_buttons = all_buttons;
    state.seen_axis_directions = 0xffU;
    state.rumble_sent = 1;
    ok &= check(tested_count(&state) == TEST_TOTAL && TEST_TOTAL == 29,
                "completion covers buttons, auxiliaries, analog and rumble");
    state.held_buttons = all_buttons;
    clear_live_state(&state);
    ok &= check(state.held_buttons == 0U && state.seen_buttons == all_buttons &&
                    state.seen_axis_directions == 0xffU && state.rumble_sent,
                "reconnect clears live state but preserves completed checks");

    fake_contract = 1;
    fake_contract_mismatch = 0;
    ok &= check(h700_input_contract_matches(100),
                "exact generated H700 contract accepted");
    fake_contract_mismatch = 1;
    ok &= check(!h700_input_contract_matches(100),
                "nearby input device contract rejected");
    fake_contract = 0;

    fake_grab = 1;
    ok &= check(set_auxiliary_exclusive(100, 1) && grabbed_value == 1,
                "auxiliary device is exclusive while tester is open");
    ok &= check(set_auxiliary_exclusive(100, 0) && grabbed_value == 0,
                "auxiliary device exclusivity is released on return");
    fake_grab = 0;

    fake_contract = 2;
    ok &= check(auxiliary_contract_matches(100, "gpio-keys-volume",
                                           KEY_VOLUMEDOWN, KEY_VOLUMEUP),
                "exact volume-button device accepted without grabbing");
    fake_contract = 3;
    ok &= check(auxiliary_contract_matches(100, "axp20x-pek", KEY_POWER, 0),
                "exact power-button device accepted without grabbing");
    ok &= check(!auxiliary_contract_matches(100, "gpio-keys-volume",
                                            KEY_VOLUMEDOWN, KEY_VOLUMEUP),
                "auxiliary device name mismatch rejected");
    fake_contract = 0;

    initialize_state(&state);
    fake_rumble = 1;
    state.rumble_enabled = 1;
    ok &= check(upload_rumble(100, &state) && state.effect_id == 7 &&
                    state.rumble_sent && rumble_uploads == 1 &&
                    rumble_plays == 1 &&
                    strings_equal(state.last_event, "FF RUMBLE"),
                "bounded rumble effect uploads and plays once");
    ok &= check(upload_rumble(100, &state) && rumble_uploads == 1 &&
                    rumble_plays == 2,
                "later Menu press replays existing bounded effect");
    erase_rumble(100, &state);
    ok &= check(state.effect_id == -1 && rumble_stops == 1 &&
                    rumble_erases == 1,
                "rumble is stopped and erased on exit/reconnect");
    fake_rumble = 0;

    initialize_state(&state);
    state.connected = 1;
    state.dirty = DIRTY_ALL;
    guarded_frame[0] = 0x12345678U;
    guarded_frame[(BIRD_DEVICE_FB_WIDTH * BIRD_DEVICE_FB_HEIGHT) + 1] =
        0x87654321U;
    framebuffer = &guarded_frame[1];
    render_all(&state);
    ok &= check(guarded_frame[0] == 0x12345678U &&
                    guarded_frame[(BIRD_DEVICE_FB_WIDTH *
                                   BIRD_DEVICE_FB_HEIGHT) + 1] == 0x87654321U,
                "renderer stays inside fixed framebuffer mapping");
    ok &= check(framebuffer[12U * BIRD_DEVICE_FB_WIDTH + 22U] !=
                    COLOR_BACKGROUND,
                "INPUT TEST title begins at top-left");
    state.seen_axis_directions = 1U << 0;
    state.axes[0] = state.axis_minimum[0];
    render_axis_pair(&state, 0);
    ok &= check(framebuffer[411U * BIRD_DEVICE_FB_WIDTH + (270U - 34U)] ==
                    COLOR_ACTIVE &&
                    framebuffer[(411U - 34U) * BIRD_DEVICE_FB_WIDTH + 270U] ==
                    COLOR_UNTESTED,
                "stick history follows tested circular rim quadrants");
    state.axes[0] = 0;
    render_axis_pair(&state, 0);
    ok &= check(framebuffer[411U * BIRD_DEVICE_FB_WIDTH + (270U - 27U)] !=
                    COLOR_ACTIVE,
                "moving stick dot does not leave a linear rectangular trail");
    framebuffer[0] = 0xabcdef01U;
    state.dirty = 0U;
    render_dirty(&state);
    ok &= check(framebuffer[0] == 0xabcdef01U,
                "idle state performs no redraw");

    if (!ok) return 1;
    printf("input-tester C tests: PASS\n");
    return 0;
}
