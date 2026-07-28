/* Host fault-injection harness. It includes the production launcher so every
 * assertion below executes the exact favorites and poll decision code shipped
 * in the freestanding AArch64 binary. */

#include <stdio.h>
#include <string.h>

#define BIRD_HOST_TEST 1
#define PERSIST_UI_STATE 1
#define STORAGE_ANCHOR_MARKER "/run/muos/bird-storage-anchor-ready"
#define STORAGE_READY_SIGNAL "/run/muos/bird-storage-ready"
#include "../../../launcher/bird-launcher.c"

#define FAKE_FD 41
#define EIO_LINUX 5
#define EBADF_LINUX 9

static long fake_now_ms;
static long fake_now_sub_ms_ns;
static long fake_open_result;
#define FAKE_OPEN_SCRIPT_MAX 16U
static long fake_open_script[FAKE_OPEN_SCRIPT_MAX];
static unsigned fake_open_script_count;
static unsigned fake_open_script_index;
#define FAKE_OPEN_PATH_BYTES 128U
static char fake_open_path[FAKE_OPEN_SCRIPT_MAX][FAKE_OPEN_PATH_BYTES];
static unsigned fake_open_path_count;
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
#define TEST_FB_WIDTH RG34XX_FB_WIDTH
#define TEST_FB_HEIGHT RG34XX_FB_HEIGHT
#define TEST_FB_BYTES_PER_PIXEL RG34XX_FB_BYTES_PER_PIXEL
_Alignas(8) static u8 fake_framebuffer[TEST_FB_WIDTH * TEST_FB_HEIGHT *
                                       TEST_FB_BYTES_PER_PIXEL * 2U];
_Alignas(8) static u8 fake_framebuffer_reference[
    TEST_FB_WIDTH * TEST_FB_HEIGHT * TEST_FB_BYTES_PER_PIXEL * 2U];
#ifdef BIRD_PROFILE
#define PROFILE_LOG_BYTES 16384U
static char fake_profile_log[PROFILE_LOG_BYTES];
static u64 fake_profile_log_bytes;
static int fake_capture_diagnostics;
#endif

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
        long result = fake_open_result;
        if (fake_open_path_count < FAKE_OPEN_SCRIPT_MAX) {
            snprintf(fake_open_path[fake_open_path_count],
                     FAKE_OPEN_PATH_BYTES, "%s", (const char *)a1);
            fake_open_path_count++;
        }
        if ((int)a2 & O_CREAT) fake_create_calls++;
        fake_open_calls++;
        if (fake_open_script_index < fake_open_script_count)
            result = fake_open_script[fake_open_script_index++];
        return result;
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
    if (number == 64) {
#ifdef BIRD_PROFILE
        if ((bird_profile.emitting || fake_capture_diagnostics) &&
            fake_profile_log_bytes < PROFILE_LOG_BYTES) {
            u64 available = PROFILE_LOG_BYTES - fake_profile_log_bytes;
            u64 bytes = (u64)a2 < available ? (u64)a2 : available;
            memcpy(fake_profile_log + fake_profile_log_bytes, (const void *)a1,
                   (size_t)bytes);
            fake_profile_log_bytes += bytes;
        }
#endif
        return a2; /* discard production diagnostics */
    }
    if (number == 101) {
        const struct timespec *request = (const struct timespec *)a0;
        fake_sleep_calls++;
        fake_last_sleep_ns = request->sec * 1000000000L + request->nsec;
        return 0;
    }
    if (number == 113) {
        struct timespec *value = (struct timespec *)a1;
        value->sec = fake_now_ms / 1000;
        value->nsec = (fake_now_ms % 1000) * 1000000L +
                      fake_now_sub_ms_ns;
        return 0;
    }
    return -EBADF_LINUX;
}

static void reset_fake_file(long open_result, const char *payload,
                            long terminal_read) {
    fake_open_result = open_result;
    fake_open_script_count = 0;
    fake_open_script_index = 0;
    fake_open_path_count = 0;
    fake_open_calls = 0;
    fake_create_calls = 0;
    fake_rename_calls = 0;
    fake_payload = payload ? payload : "";
    fake_payload_bytes = payload ? (u64)strlen(payload) : 0;
    fake_payload_offset = 0;
    fake_terminal_read = terminal_read;
}

static void set_fake_open_script(const long *results, unsigned count) {
    unsigned index;
    if (count > FAKE_OPEN_SCRIPT_MAX) count = FAKE_OPEN_SCRIPT_MAX;
    for (index = 0; index < count; index++)
        fake_open_script[index] = results[index];
    fake_open_script_count = count;
    fake_open_script_index = 0;
}

static void reset_favorites(void) {
    clear_favorites();
    favorites_loaded = 0;
    favorites_retry_count = 0;
    favorites_retry_ms = FAVORITES_RETRY_INITIAL_MS;
    next_favorites_retry = 0;
    storage_ready = 1;
}

static void setup_test_framebuffer(u32 pages, u8 *memory) {
    memset(&fb_var, 0, sizeof(fb_var));
    memset(&fb_fix, 0, sizeof(fb_fix));
    fb_var.xres = TEST_FB_WIDTH;
    fb_var.yres = TEST_FB_HEIGHT;
    fb_var.xres_virtual = TEST_FB_WIDTH;
    fb_var.yres_virtual = TEST_FB_HEIGHT * pages;
    fb_var.bits_per_pixel = 32U;
    fb_var.red.offset = 16U;
    fb_var.red.length = 8U;
    fb_var.green.offset = 8U;
    fb_var.green.length = 8U;
    fb_var.blue.length = 8U;
    fb_var.transp.offset = 0U;
    fb_var.transp.length = 0U;
    fb_fix.type = FB_TYPE_PACKED_PIXELS;
    fb_fix.visual = FB_VISUAL_TRUECOLOR;
    fb_fix.xpanstep = 1U;
    fb_fix.ypanstep = 1U;
    fb_fix.line_length = TEST_FB_WIDTH * TEST_FB_BYTES_PER_PIXEL;
    fb_fix.smem_len = fb_fix.line_length * TEST_FB_HEIGHT * pages;
    fb = memory;
    configure_framebuffer_path();
}

static void draw_phase2_primitive_pattern(void) {
    rectangle(0, 0, (int)TEST_FB_WIDTH, (int)TEST_FB_HEIGHT,
              color(3U, 9U, 17U));
    rectangle(-2, -1, 7, 4, color(0x12U, 0x34U, 0x56U));
    rectangle(1, 3, 719, 2, color(0x80U, 0x40U, 0x20U));
    rectangle(32, 86, 656, 3, color(0xf1U, 0xe2U, 0xd3U));
    rectangle(719, 479, 4, 4, color(0xaaU, 0xbbU, 0xccU));
}

static int run_framebuffer_primitive_tests(void) {
    u32 expected;
    int ok = 1;

    setup_test_framebuffer(1U, fake_framebuffer);
    ok &= check(framebuffer_path == FRAMEBUFFER_PATH_RG34XX_XRGB8888 &&
                    framebuffer_mismatch_mask == 0U &&
                    fb_var.xoffset == 0U && fb_var.yoffset == 0U &&
                    fb_var.yres_virtual == fb_var.yres &&
                    fb_fix.line_length == RG34XX_FB_STRIDE &&
                    fb_fix.smem_len == RG34XX_FB_BYTES,
                "accepted RG34XX-SP fixed-page framebuffer missed fast path");
    ok &= check(color(0x12U, 0x34U, 0x56U) == 0x00123456U,
                "RG34XX-SP XRGB8888 fast color packing changed");

    memset(fake_framebuffer, 0, RG34XX_FB_BYTES);
    draw_phase2_primitive_pattern();
    setup_test_framebuffer(1U, fake_framebuffer_reference);
    framebuffer_path = FRAMEBUFFER_PATH_DIAGNOSTIC;
    memset(fake_framebuffer_reference, 0, RG34XX_FB_BYTES);
    draw_phase2_primitive_pattern();
    ok &= check(memcmp(fake_framebuffer, fake_framebuffer_reference,
                       RG34XX_FB_BYTES) == 0,
                "fast rectangles differ from checked recovery rendering");

    setup_test_framebuffer(2U, fake_framebuffer);
    ok &= check(framebuffer_path == FRAMEBUFFER_PATH_DIAGNOSTIC &&
                    framebuffer_mismatch_mask ==
                        (FB_MISMATCH_YRES_VIRTUAL | FB_MISMATCH_SMEM_LEN),
                "multi-page framebuffer entered the fixed-page fast path");
    memset(fake_framebuffer, 0, sizeof(fake_framebuffer));
    expected = color(0x12U, 0x34U, 0x56U);
    rectangle(0, 0, 1, 1, expected);
    ok &= check(memcmp(fake_framebuffer, &expected, sizeof(expected)) == 0 &&
                    memcmp(fake_framebuffer + RG34XX_FB_BYTES, &expected,
                           sizeof(expected)) == 0,
                "diagnostic renderer no longer preserves both-page writes");

    setup_test_framebuffer(2U, fake_framebuffer);
    fb_var.yoffset = TEST_FB_HEIGHT;
    configure_framebuffer_path();
    memset(fake_framebuffer, 0, sizeof(fake_framebuffer));
    expected = color(0x21U, 0x43U, 0x65U);
    rectangle(3, 2, 1, 1, expected);
    ok &= check(memcmp(fake_framebuffer + 2U * RG34XX_FB_STRIDE + 12U,
                       &expected, sizeof(expected)) == 0 &&
                    memcmp(fake_framebuffer + RG34XX_FB_BYTES +
                               2U * RG34XX_FB_STRIDE + 12U,
                           &expected, sizeof(expected)) == 0,
                "diagnostic renderer changed selected-page recovery behavior");

    setup_test_framebuffer(1U, fake_framebuffer);
    fb_fix.line_length += 4U;
    configure_framebuffer_path();
    ok &= check(framebuffer_path == FRAMEBUFFER_PATH_DIAGNOSTIC &&
                    framebuffer_mismatch_mask == FB_MISMATCH_STRIDE,
                "noncanonical stride entered the RG34XX-SP fast path");
    setup_test_framebuffer(1U, fake_framebuffer);
    fb_var.red.offset = 0U;
    configure_framebuffer_path();
    ok &= check(framebuffer_path == FRAMEBUFFER_PATH_DIAGNOSTIC &&
                    framebuffer_mismatch_mask == FB_MISMATCH_RED,
                "noncanonical channel offsets entered the RG34XX-SP fast path");
    setup_test_framebuffer(1U, fake_framebuffer);
    fb_var.xoffset = 1U;
    configure_framebuffer_path();
    ok &= check(framebuffer_path == FRAMEBUFFER_PATH_DIAGNOSTIC &&
                    framebuffer_mismatch_mask == FB_MISMATCH_XOFFSET,
                "nonzero page offset entered the RG34XX-SP fast path");
    setup_test_framebuffer(1U, fake_framebuffer);
    fb_fix.smem_len += 4U;
    configure_framebuffer_path();
    ok &= check(framebuffer_path == FRAMEBUFFER_PATH_DIAGNOSTIC &&
                    framebuffer_mismatch_mask == FB_MISMATCH_SMEM_LEN,
                "noncanonical mapping size entered the RG34XX-SP fast path");

    setup_test_framebuffer(1U, fake_framebuffer);
    fb_var.bits_per_pixel = 24U;
    fb_var.transp.offset = 0U;
    fb_var.transp.length = 0U;
    fb_fix.line_length = TEST_FB_WIDTH * 3U;
    fb_fix.smem_len = fb_fix.line_length * TEST_FB_HEIGHT;
    configure_framebuffer_path();
    memset(fake_framebuffer, 0, 4U);
    rectangle(0, 0, 1, 1, color(0x12U, 0x34U, 0x56U));
    ok &= check(framebuffer_path == FRAMEBUFFER_PATH_DIAGNOSTIC &&
                    fake_framebuffer[0] == 0x56U &&
                    fake_framebuffer[1] == 0x34U &&
                    fake_framebuffer[2] == 0x12U,
                "24-bit diagnostic framebuffer fallback changed");

    setup_test_framebuffer(1U, fake_framebuffer);
    fb_var.bits_per_pixel = 16U;
    fb_var.red.offset = 11U;
    fb_var.red.length = 5U;
    fb_var.green.offset = 5U;
    fb_var.green.length = 6U;
    fb_var.blue.offset = 0U;
    fb_var.blue.length = 5U;
    fb_var.transp.offset = 0U;
    fb_var.transp.length = 0U;
    fb_fix.line_length = TEST_FB_WIDTH * 2U;
    fb_fix.smem_len = fb_fix.line_length * TEST_FB_HEIGHT;
    configure_framebuffer_path();
    memset(fake_framebuffer, 0, 4U);
    rectangle(0, 0, 1, 1, color(0xffU, 0U, 0U));
    ok &= check(framebuffer_path == FRAMEBUFFER_PATH_DIAGNOSTIC &&
                    fake_framebuffer[0] == 0U && fake_framebuffer[1] == 0xf8U,
                "16-bit diagnostic framebuffer fallback changed");

    return ok;
}

static void setup_main_view(void) {
    view = VIEW_MAIN;
    selection = 0U;
    active_system = 0U;
    active_media_category = 0U;
    media_section = CATALOG_MEDIA_SECTION_LISTEN;
    selected_status = "DIRECT FRAMEBUFFER READY";
    battery_percent = -1;
    charging_state = -1;
    pending_launch.kind = PENDING_LAUNCH_NONE;
    pending_render_invalid = 0U;
}

static void reset_storage_handoff_state(void) {
    runtime_dir_fd = FAKE_FD;
    input_dir_fd = FAKE_FD;
    power_dir_fd = FAKE_FD;
    storage_dir_fd = -1;
    config_dir_fd = -1;
    storage_signal_fd = -1;
    storage_signal_disabled = 0;
    storage_handoff_signaled = 0;
    storage_probe_attempted = 0;
    storage_ready = 0;
    favorites_loaded = 1;
    next_favorites_retry = 0;
#ifdef BIRD_PROFILE
    bird_profile_storage_dir_source = PROFILE_STORAGE_SOURCE_NONE;
    bird_profile_config_dir_source = PROFILE_STORAGE_SOURCE_NONE;
    bird_profile_storage_live_result = 0;
    bird_profile_storage_sysroot_result = 0;
    bird_profile_config_live_result = 0;
    bird_profile_config_sysroot_result = 0;
    bird_profile_storage_signal_seen = 0;
    bird_profile_storage_after_signal_attempt = 0U;
#endif
}

static int run_storage_handoff_tests(void) {
    unsigned opens;
    unsigned closes;
    long open_script[4];
    int ok = 1;

    /* The pending-selection queue covers the whole pre-signal interval. The
     * early launcher must not open either covered storage mountpoint. */
    reset_storage_handoff_state();
    reset_fake_file(FAKE_FD, 0, 0);
    probe_storage();
    ok &= check(fake_open_calls == 0 && !storage_probe_attempted &&
                    !storage_ready,
                "storage was probed before the handoff signal");

    /* Reproduce the original covered-directory failure defensively: even if
     * stale descriptors exist, the edge discards them and acquires only the
     * completed /sysroot tree once. */
    reset_storage_handoff_state();
    storage_dir_fd = 70;
    config_dir_fd = 71;
    reset_fake_file(FAKE_FD, 0, 0);
    fake_close_calls = 0;
    open_script[0] = FAKE_FD;
    open_script[1] = FAKE_FD;
    open_script[2] = FAKE_FD;
    open_script[3] = FAKE_FD;
    set_fake_open_script(open_script, 4U);
    receive_storage_handoff_signal();
    ok &= check(storage_ready && storage_probe_attempted,
                "post-signal storage acquisition did not become ready");
    ok &= check(fake_open_calls == 4,
                "post-signal storage acquisition did not perform four exact opens");
    ok &= check(fake_close_calls == 4,
                "post-signal storage acquisition did not close stale and validation descriptors");
    ok &= check(fake_open_path_count == 4 &&
                    strcmp(fake_open_path[0],
                           "/sysroot/storage/bird-data") == 0 &&
                    strcmp(fake_open_path[1],
                           "/sysroot/storage/.config/bird") == 0 &&
                    strcmp(fake_open_path[2], "ROMS") == 0,
                "early handoff did not acquire the exact post-prepare_sysroot paths");
    opens = fake_open_calls;
    closes = fake_close_calls;
    receive_storage_handoff_signal();
    probe_storage();
    ok &= check(fake_open_calls == opens && fake_close_calls == closes,
                "duplicate storage signal caused a second acquisition");

    /* A broken readiness contract is reported once. It must not turn into a
     * 50-ms filesystem polling loop or an input-triggered retry. */
    reset_storage_handoff_state();
    reset_fake_file(FAKE_FD, 0, 0);
    fake_close_calls = 0;
    open_script[0] = -ENOENT;
    open_script[1] = FAKE_FD;
    set_fake_open_script(open_script, 2U);
    receive_storage_handoff_signal();
    opens = fake_open_calls;
    closes = fake_close_calls;
    receive_storage_handoff_signal();
    probe_storage();
    ok &= check(!storage_ready && storage_probe_attempted && opens == 2 &&
                    fake_open_calls == opens && fake_close_calls == closes,
                "failed storage handoff retried filesystem acquisition");

    return ok;
}

static u64 framebuffer_hash(void) {
    u64 value = 1469598103934665603UL;
    u64 i;
    for (i = 0; i < RG34XX_FB_BYTES; i++) {
        value ^= fake_framebuffer[i];
        value *= 1099511628211UL;
    }
    return value;
}

static void setup_full_render_golden(void) {
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    favorites_loaded = 0;
    favorite_count = 0U;
    active_system = 0U;
    active_media_category = 0U;
    media_section = CATALOG_MEDIA_SECTION_LISTEN;
    selection = 0U;
    battery_percent = -1;
    charging_state = -1;
    pending_launch.kind = PENDING_LAUNCH_NONE;
    pending_render_invalid = 0U;
}

static int check_full_render_golden(u64 expected, const char *message) {
    draw_screen();
    return check(framebuffer_hash() == expected, message);
}

static int run_full_render_golden_tests(void) {
    int ok = 1;

    /* These hashes retain the accepted Phase 2 visual output with the
     * hardware-measured XRGB8888 unused byte stored as zero. They keep later
     * helpers from changing pixels while dirty-vs-full tests cover coherence. */
    setup_full_render_golden();
    view = VIEW_MAIN;
    selected_status = "DIRECT FRAMEBUFFER READY";
    ok &= check_full_render_golden(0x9a021a90fe889095UL,
                                   "Phase 2 main-view pixels changed");

    setup_full_render_golden();
    view = VIEW_PLAY;
    selected_status = "PLAY LIBRARY READY";
    ok &= check_full_render_golden(0x29b212de1134226dUL,
                                   "Phase 2 Play-view pixels changed");

    setup_full_render_golden();
    view = VIEW_SYSTEMS;
    selected_status = "CATALOG READY FROM FIRMWARE";
    ok &= check_full_render_golden(0x1564013b9270897bUL,
                                   "Phase 2 Systems pixels changed");

    setup_full_render_golden();
    view = VIEW_SYSTEMS;
    selection = SYSTEM_ROWS;
    selected_status = "DIRECT EVDEV INPUT READY";
    ok &= check_full_render_golden(0x4af17f03e0947cf3UL,
                                   "Phase 2 scrolled Systems pixels changed");

    setup_full_render_golden();
    view = VIEW_GAMES;
    set_favorite(0U, 1);
    favorite_count = 1U;
    favorites_loaded = 1;
    selected_status = "ROM STORAGE READY";
    ok &= check_full_render_golden(0xaa329c19dfcf2353UL,
                                   "Phase 2 Games pixels changed");

    setup_full_render_golden();
    view = VIEW_FAVORITES;
    selected_status = "FAVORITES LOAD WITH STORAGE";
    ok &= check_full_render_golden(0xe47cbe6ea1804441UL,
                                   "Phase 2 loading-Favorites pixels changed");

    setup_full_render_golden();
    view = VIEW_FAVORITES;
    set_favorite(0U, 1);
    set_favorite(1U, 1);
    favorite_count = 2U;
    favorites_loaded = 1;
    selected_status = "FAVORITES READY";
    ok &= check_full_render_golden(0xe6d5ee471721ff03UL,
                                   "Phase 2 Favorites pixels changed");

    setup_full_render_golden();
    view = VIEW_MEDIA_CATEGORIES;
    selected_status = "AUDIO CATALOG READY FROM FIRMWARE";
    ok &= check_full_render_golden(0x061f22c74ba05003UL,
                                   "Phase 2 media-category pixels changed");

    setup_full_render_golden();
    view = VIEW_MEDIA_CATEGORIES;
    media_section = CATALOG_MEDIA_SECTION_READ;
    selected_status = "READING LIBRARY READY FROM FIRMWARE";
    ok &= check_full_render_golden(0xd2a698a8eeebfa91UL,
                                   "Phase 2 empty-media pixels changed");

    setup_full_render_golden();
    view = VIEW_MEDIA_ENTRIES;
    selected_status = "MEDIA STORAGE READY";
    ok &= check_full_render_golden(0x1f1e262089fe38cbUL,
                                   "Phase 2 media-entry pixels changed");

    setup_full_render_golden();
    view = VIEW_MAIN;
    battery_percent = 100;
    charging_state = 1;
    selected_status = "DIRECT FRAMEBUFFER READY";
    ok &= check_full_render_golden(0x3babda9a0be291bdUL,
                                   "Phase 2 charging pixels changed");

    return ok;
}

static int dirty_framebuffer_matches_full(u32 pages, const char *message) {
    u64 bytes = (u64)RG34XX_FB_BYTES * pages;
    setup_test_framebuffer(pages, fake_framebuffer_reference);
    memset(fake_framebuffer_reference, 0xa5, (size_t)bytes);
    draw_screen();
    return check(memcmp(fake_framebuffer, fake_framebuffer_reference,
                        (size_t)bytes) == 0,
                 message);
}

static int run_dirty_region_render_tests(void) {
    u8 published_favorites[(CATALOG_ENTRY_COUNT + 7U) / 8U];
    u32 old_first;
    u32 old_selection;
    int action;
    int ok = 1;

    ok &= check(viewport_first(VIEW_SYSTEMS, SYSTEM_ROWS - 1U) == 0U &&
                    viewport_first(VIEW_SYSTEMS, SYSTEM_ROWS) == 1U &&
                    viewport_first(VIEW_MAIN, 3U) == 0U,
                "accepted one-row viewport policy changed");

    /* Ordinary fixed-page movement changes only the old row, new row, and
     * status line, but must produce the exact same final pixels as a full
     * render of the new state. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    setup_main_view();
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "main-menu dirty movement differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    setup_main_view();
    view = VIEW_PLAY;
    selected_status = "PLAY LIBRARY READY";
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "Play-menu dirty movement differs from a full render");

    /* A list movement inside the current viewport also repaints exactly two
     * rows without changing the accepted viewport origin. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    view = VIEW_SYSTEMS;
    selection = 0U;
    selected_status = "CATALOG READY FROM FIRMWARE";
    battery_percent = -1;
    charging_state = -1;
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "list-row dirty movement differs from a full render");

    /* Crossing row seven retains today's one-row scrolling and repaints the
     * bounded content band rather than the header/footer or whole screen. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    view = VIEW_SYSTEMS;
    selection = SYSTEM_ROWS - 1U;
    selected_status = "CATALOG READY FROM FIRMWARE";
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = SYSTEM_ROWS;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "viewport-band dirty render differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    view = VIEW_SYSTEMS;
    selection = CATALOG_SYSTEM_COUNT - 1U;
    selected_status = "CATALOG READY FROM FIRMWARE";
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 0U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "wrapped viewport dirty render differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    view = VIEW_MEDIA_CATEGORIES;
    media_section = CATALOG_MEDIA_SECTION_LISTEN;
    selection = 0U;
    selected_status = "AUDIO CATALOG READY FROM FIRMWARE";
    battery_percent = -1;
    charging_state = -1;
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "one-item media wrap differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    setup_main_view();
    battery_percent = 100;
    charging_state = 1;
    draw_screen();
    battery_percent = 9;
    charging_state = 0;
    draw_battery_update();
    ok &= dirty_framebuffer_matches_full(
        1U, "battery dirty render differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    setup_main_view();
    draw_screen();
    selected_status = "WAITING FOR FAVORITES STORAGE";
    draw_status_update();
    ok &= dirty_framebuffer_matches_full(
        1U, "status dirty render differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    view = VIEW_FAVORITES;
    selection = 0U;
    selected_status = "FAVORITES LOAD WITH STORAGE";
    favorites_loaded = 0;
    battery_percent = -1;
    charging_state = -1;
    draw_screen();
    favorites_loaded = 1;
    draw_content_and_status_update();
    ok &= dirty_framebuffer_matches_full(
        1U, "Favorites completion dirty render differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    set_favorite(0U, 1);
    favorite_count = 1U;
    favorites_loaded = 1;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "ROM STORAGE READY";
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "game-row dirty movement differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    set_favorite(0U, 1);
    set_favorite(1U, 1);
    favorite_count = 2U;
    favorites_loaded = 1;
    view = VIEW_FAVORITES;
    selection = 0U;
    selected_status = "FAVORITES READY";
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "Favorites-row dirty movement differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    favorite_count = 0U;
    favorites_loaded = 1;
    storage_ready = 1;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "ROM STORAGE READY";
    draw_screen();
    reset_fake_file(FAKE_FD, 0, 0);
    toggle_current_favorite();
    ok &= check(is_favorite(0U) && favorite_count == 1U,
                "successful game favorite add did not publish state");
    ok &= dirty_framebuffer_matches_full(
        1U, "successful game favorite dirty render differs from full");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    set_favorite(0U, 1);
    set_favorite(1U, 1);
    favorite_count = 2U;
    favorites_loaded = 1;
    storage_ready = 1;
    view = VIEW_FAVORITES;
    selection = 0U;
    selected_status = "FAVORITES READY";
    draw_screen();
    reset_fake_file(FAKE_FD, 0, 0);
    toggle_current_favorite();
    ok &= check(!is_favorite(0U) && is_favorite(1U) &&
                    favorite_count == 1U && selection == 0U,
                "successful Favorites removal did not publish state");
    ok &= dirty_framebuffer_matches_full(
        1U, "successful Favorites removal dirty render differs from full");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    view = VIEW_MEDIA_ENTRIES;
    active_media_category = 0U;
    media_section = CATALOG_MEDIA_SECTION_LISTEN;
    selection = 0U;
    selected_status = "MEDIA STORAGE READY";
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "media-row dirty movement differs from a full render");

    /* Favorites may publish while Games is visible without an immediate
     * background redraw. The next partial commit must absorb the pending
     * content invalidation, including stars on rows it did not otherwise
     * touch. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    memset(published_favorites, 0, sizeof(published_favorites));
    published_favorites[2U >> 3] |= (u8)(1U << (2U & 7U));
    clear_favorites();
    favorites_loaded = 0;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "CATALOG READY // ROMS MOUNTING";
    battery_percent = 9;
    charging_state = 0;
    draw_screen();
    finish_favorites_load(published_favorites, 1U, "host-test");
    ok &= check(pending_render_invalid & RENDER_INVALID_CONTENT,
                "Games did not retain async Favorites content invalidation");
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= check(pending_render_invalid == 0U,
                "selection commit did not consume content invalidation");
    ok &= dirty_framebuffer_matches_full(
        1U, "selection commit left an untouched async favorite star stale");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    favorites_loaded = 0;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "CATALOG READY // ROMS MOUNTING";
    battery_percent = 9;
    charging_state = 0;
    draw_screen();
    finish_favorites_load(published_favorites, 1U, "host-test");
    battery_percent = 100;
    charging_state = 1;
    draw_battery_update();
    ok &= dirty_framebuffer_matches_full(
        1U, "battery commit left async favorite stars stale");

    /* A failed automatic pending launch changes status without an immediate
     * render. A later battery-only event must consume that invalidation. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    favorites_loaded = 1;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "GAME QUEUED // STORAGE MOUNTING";
    battery_percent = 9;
    charging_state = 0;
    storage_ready = 1;
    pending_launch.kind = PENDING_LAUNCH_GAME;
    pending_launch.index = 0U;
    pending_launch.active_index = 0U;
    draw_screen();
    reset_fake_file(-ENOENT, 0, 0);
    action = dispatch_pending_launch();
    ok &= check(action == ACTION_NONE &&
                    (pending_render_invalid & RENDER_INVALID_STATUS),
                "failed pending dispatch did not retain status invalidation");
    battery_percent = 100;
    charging_state = 1;
    draw_battery_update();
    ok &= dirty_framebuffer_matches_full(
        1U, "battery commit left failed-dispatch status stale");

    /* The diagnostic/recovery renderer intentionally writes both exposed
     * pages. Dirty updates must retain that page-selection behavior. */
    setup_test_framebuffer(2U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, sizeof(fake_framebuffer));
    setup_main_view();
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        2U, "two-page diagnostic dirty render differs from a full render");

    return ok;
}

#ifdef BIRD_PROFILE
static void reset_profile_log(void) {
    fake_profile_log_bytes = 0;
    fake_profile_log[0] = 0;
}

static int profile_log_contains(const char *needle) {
    u64 end = fake_profile_log_bytes < PROFILE_LOG_BYTES - 1U
                  ? fake_profile_log_bytes : PROFILE_LOG_BYTES - 1U;
    fake_profile_log[end] = 0;
    return strstr(fake_profile_log, needle) != NULL;
}

static u64 profile_syscall_category_sum(void) {
    u64 total = 0;
    u32 kind;
    for (kind = 0; kind < PROFILE_SYSCALL_KIND_COUNT; kind++)
        total += bird_profile.syscall_kind[kind];
    return total;
}

static void setup_profile_path_anchors(void) {
    runtime_dir_fd = FAKE_FD;
    input_dir_fd = FAKE_FD;
    power_dir_fd = FAKE_FD;
    storage_dir_fd = FAKE_FD;
    config_dir_fd = FAKE_FD;
}

static void reset_profile_storage_diagnostics(void) {
    reset_storage_handoff_state();
}

static int run_profile_tests(void) {
    const struct bird_profile_render_totals *render;
    struct input_event event;
    u64 before_syscalls;
    u64 before_diagnostics;
    u64 prior_input_samples;
    u64 maximum_physical;
    u64 first_storage_report_bytes;
    long open_script[4];
    u32 old_first;
    u32 old_selection;
    int action;
    int ok = 1;

    /* Profile mode reports the one deterministic post-signal attempt without
     * adding a retry or altering its readiness result. */
    bird_profile_reset();
    reset_profile_log();
    reset_profile_storage_diagnostics();
    fake_now_ms = 6000;
    reset_fake_file(FAKE_FD, 0, 0);
    open_script[0] = -ENOENT;
    open_script[1] = FAKE_FD;
    set_fake_open_script(open_script, 2U);
    fake_capture_diagnostics = 1;
    receive_storage_handoff_signal();
    fake_capture_diagnostics = 0;
    ok &= check(profile_log_contains(
                    "storage_probe result=failed boot_ms=6000 "
                    "post_signal_attempt=1 stage=storage-dir errno=2") &&
                    profile_log_contains(
                        "storage_source=unavailable config_source=sysroot "
                        "live_errno=0 sysroot_errno=2"),
                "first post-signal storage-directory failure lacked errno diagnostics");
    first_storage_report_bytes = fake_profile_log_bytes;
    fake_capture_diagnostics = 1;
    receive_storage_handoff_signal();
    probe_storage();
    fake_capture_diagnostics = 0;
    ok &= check(fake_profile_log_bytes == first_storage_report_bytes,
                "failed storage contract emitted a retry diagnostic");

    reset_profile_log();
    reset_profile_storage_diagnostics();
    fake_now_ms = 7000;
    reset_fake_file(FAKE_FD, 0, 0);
    open_script[0] = FAKE_FD;
    open_script[1] = -EIO_LINUX;
    set_fake_open_script(open_script, 2U);
    fake_capture_diagnostics = 1;
    receive_storage_handoff_signal();
    fake_capture_diagnostics = 0;
    ok &= check(profile_log_contains(
                    "post_signal_attempt=1 stage=config-dir errno=5") &&
                    profile_log_contains(
                        "storage_source=sysroot config_source=unavailable "
                        "live_errno=0 sysroot_errno=5"),
                "post-signal configuration-directory failure was misclassified");

    reset_profile_log();
    reset_profile_storage_diagnostics();
    fake_now_ms = 8000;
    reset_fake_file(FAKE_FD, 0, 0);
    open_script[0] = FAKE_FD;
    open_script[1] = FAKE_FD;
    open_script[2] = -EIO_LINUX;
    set_fake_open_script(open_script, 3U);
    fake_capture_diagnostics = 1;
    receive_storage_handoff_signal();
    fake_capture_diagnostics = 0;
    ok &= check(profile_log_contains(
                    "post_signal_attempt=1 stage=rom-root errno=5") &&
                    profile_log_contains(
                        "storage_source=sysroot config_source=sysroot"),
                "post-signal ROM-root failure was misclassified");

    reset_profile_log();
    reset_profile_storage_diagnostics();
    fake_now_ms = 9000;
    reset_fake_file(FAKE_FD, 0, 0);
    open_script[0] = FAKE_FD;
    open_script[1] = FAKE_FD;
    open_script[2] = FAKE_FD;
    open_script[3] = -EIO_LINUX;
    set_fake_open_script(open_script, 4U);
    fake_capture_diagnostics = 1;
    receive_storage_handoff_signal();
    fake_capture_diagnostics = 0;
    ok &= check(profile_log_contains(
                    "post_signal_attempt=1 stage=marker errno=5") &&
                    profile_log_contains(
                        "storage_source=sysroot config_source=sysroot"),
                "marker failure lacked acquired anchor sources and errno");

    reset_profile_log();
    reset_profile_storage_diagnostics();
    fake_now_ms = 10000;
    reset_fake_file(FAKE_FD, 0, 0);
    open_script[0] = FAKE_FD;
    open_script[1] = FAKE_FD;
    open_script[2] = FAKE_FD;
    open_script[3] = FAKE_FD;
    set_fake_open_script(open_script, 4U);
    fake_capture_diagnostics = 1;
    receive_storage_handoff_signal();
    fake_capture_diagnostics = 0;
    ok &= check(storage_ready && profile_log_contains(
                    "storage_probe result=ready boot_ms=10000 "
                    "after_signal=1 post_signal_attempt=1 "
                    "storage_source=sysroot config_source=sysroot"),
                "successful first post-signal probe lacked source diagnostics");
    reset_profile_storage_diagnostics();

    /* Serialization is forbidden until an interactive framebuffer barrier.
     * Sampling and serialization are profiler overhead, not launcher work. */
    bird_profile_reset();
    reset_profile_log();
    fake_now_ms = 1000;
    before_syscalls = bird_profile.syscalls;
    (void)bird_profile_now_ns();
    ok &= check(bird_profile.syscalls == before_syscalls,
                "profile clock sampling changed workload syscall totals");
    bird_profile_emit_startup();
    bird_profile_note_exit_and_emit();
    ok &= check(fake_profile_log_bytes == 0 && bird_profile.output_records == 0,
                "profile output occurred before the interactive barrier");

    /* Preserve the current milestone order exactly: the startup frame barrier
     * precedes input discovery. Equal millisecond timestamps must not hide it. */
    setup_test_framebuffer(2U, fake_framebuffer);
    setup_main_view();
    bird_profile_application_entry((u64)fake_now_ms * 1000000UL);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    bird_profile_input_opened();
    bird_profile_first_frame_marked();
    before_syscalls = bird_profile.syscalls;
    before_diagnostics = bird_profile.diagnostic_writes;
    bird_profile_emit_startup();
    ok &= check(fake_profile_log_bytes > 0 && bird_profile.output_records >= 2,
                "profile output did not become available after the barrier");
    ok &= check(profile_log_contains(
                    "input_open_to_interactive_barrier_ns="
                    "unavailable:barrier-before-input"),
                "reversed startup milestone order was reported as a duration");
    ok &= check(profile_log_contains(
                    "framebuffer_format path=diagnostic-fallback ") &&
                    profile_log_contains(
                        "red=16:8:0 green=8:8:0 blue=0:8:0 transp=0:0:0") &&
                    profile_log_contains(
                        "pansteps=1:1:0 stride=2880 smem_len=2764800 ") &&
                    profile_log_contains(
                        "virtual_pages=2 mapped_pages=2 mapped_remainder=0 ") &&
                    profile_log_contains(
                        "renderer_page_policy=diagnostic-recovery"),
                "startup profile omitted exact framebuffer format or page behavior");
    ok &= check(bird_profile.syscalls == before_syscalls &&
                    bird_profile.diagnostic_writes == before_diagnostics,
                "profile serialization changed workload counters");
    render = &bird_profile.render[PROFILE_RENDER_STARTUP_FULL];
    maximum_physical = render->logical_pixels * 4U * 2U;
    ok &= check(render->commits == 1U &&
                    render->logical_pixels >= TEST_FB_WIDTH * TEST_FB_HEIGHT &&
                    render->logical_pixels <= 600000U,
                "startup render reason or logical-pixel bounds are wrong");
    ok &= check(render->pages_written == 2U &&
                    render->visible_bytes <= render->physical_bytes &&
                    render->physical_bytes <= maximum_physical,
                "startup framebuffer page/byte metrics do not reconcile");

    /* A small primitive makes the metric definitions exact without pinning a
     * brittle whole-screen write count. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STATUS);
    rectangle(-1, 0, 2, 1, 0U);
    BIRD_PROFILE_BARRIER();
    render = &bird_profile.render[PROFILE_RENDER_STATUS];
    ok &= check(render->commits == 1U && render->logical_pixels == 2U &&
                    render->visible_bytes == 4U &&
                    render->physical_bytes == 4U &&
                    render->pages_written == 1U,
                "small framebuffer metric reconciliation failed");
#ifdef BIRD_PROFILE_DEEP
    ok &= check(bird_profile_deep.clipped_pixels == 1U,
                "deep profiling did not count a clipped pixel");
#endif

    /* Hot-path intervals retain sub-millisecond resolution. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    fake_now_ms = 1500;
    fake_now_sub_ms_ns = 100L;
    BIRD_PROFILE_BEGIN_EVENT();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STATUS);
    rectangle(0, 0, 1, 1, 0U);
    fake_now_sub_ms_ns = 900L;
    BIRD_PROFILE_BARRIER();
    BIRD_PROFILE_FINISH_EVENT();
    ok &= check(bird_profile.input_to_barrier_samples == 1U &&
                    bird_profile.input_to_barrier_total_ns == 800U,
                "input-to-barrier timing lost sub-millisecond precision");
    fake_now_sub_ms_ns = 0;

    /* Measure today's D-pad ordering. The save and ordinary diagnostics are
     * intentionally before its render barrier until Phase 4 changes them. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
#ifdef BIRD_PROFILE_DEEP
    /* Keep renderer-internal benchmark counters scoped to the input event;
     * aggregate Phase 1 render totals continue to retain both commits. */
    bird_profile_zero(&bird_profile_deep, sizeof(bird_profile_deep));
#endif
    fake_now_ms = 2000;
    reset_fake_file(FAKE_FD, 0, 0);
    h700_input = 1;
    event.sec = 0;
    event.usec = 0;
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;
    BIRD_PROFILE_BEGIN_EVENT();
    action = handle_event(&event);
    BIRD_PROFILE_FINISH_EVENT();
    render = &bird_profile.render[PROFILE_RENDER_SELECTION_MOVEMENT];
    ok &= check(action == ACTION_NONE && selection == 1U &&
                    render->commits == 1U,
                "D-pad event did not produce one selection render");
    ok &= check(render->logical_pixels < 100000U &&
                    render->visible_bytes < 400000U &&
                    render->pages_written == 1U &&
                    render->physical_bytes == render->visible_bytes,
                "fixed-page movement exceeded its dirty-region byte bounds");
    ok &= check(bird_profile.input_to_barrier_samples == 1U &&
                    bird_profile.event_pre_barrier_filesystem_ops > 0U &&
                    bird_profile.event_pre_barrier_diagnostic_writes > 0U &&
                    bird_profile.event_pre_barrier_diagnostic_bytes > 0U,
                "existing pre-barrier filesystem/diagnostic work was not measured");
    ok &= check(bird_profile.resume_before_barrier == 1U &&
                    bird_profile.barrier_to_resume_samples == 0U,
                "current resume-before-barrier order was not represented honestly");
    ok &= check(bird_profile.syscalls < 64U &&
                    profile_syscall_category_sum() == bird_profile.syscalls,
                "movement syscall categories or upper bound are wrong");
    ok &= check(
        bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_OPENAT] > 0U &&
            bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_CLOSE] > 0U &&
            bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_WRITE] >
                bird_profile.event_pre_barrier_diagnostic_writes,
        "event-local syscall categories missed the resume transaction");
#ifdef BIRD_PROFILE_DEEP
    ok &= check(bird_profile_deep.catalog_iterations == 0U &&
                    bird_profile_deep.string_bytes > 0U &&
                    bird_profile_deep.glyph_lookups > 0U &&
                    bird_profile_deep.glyph_scan_iterations > 0U &&
                    bird_profile_deep.rectangle_calls > 0U &&
                    bird_profile_deep.fast_rectangle_calls ==
                        bird_profile_deep.rectangle_calls &&
                    bird_profile_deep.fast_row_spans > 0U &&
                    bird_profile_deep.fast_u64_stores > 0U &&
                    bird_profile_deep.fast_u32_stores +
                            bird_profile_deep.fast_u64_stores * 2U ==
                        render->physical_bytes / RG34XX_FB_BYTES_PER_PIXEL &&
                    bird_profile_deep.fallback_rectangle_calls == 0U &&
                    bird_profile_deep.fallback_pixel_checks == 0U &&
                    bird_profile_deep.fallback_pixel_stores == 0U &&
                    bird_profile_deep.fallback_byte_stores == 0U,
                "deep movement counters are incomplete or scanned the catalog");
#endif
    prior_input_samples = bird_profile.input_to_barrier_samples;
    BIRD_PROFILE_BEGIN_EVENT();
    event.type = EV_KEY;
    event.code = 0U;
    event.value = 0;
    (void)handle_event(&event);
    BIRD_PROFILE_FINISH_EVENT();
    ok &= check(bird_profile.input_to_barrier_samples == prior_input_samples,
                "a later non-render event captured a prior barrier");

    printf("launcher profile benchmark scenario=movement syscalls=%lu "
           "filesystem_namespace_before_barrier=%lu "
           "file_writes_before_barrier=%lu closes_before_barrier=%lu "
           "diagnostics_before_barrier=%lu "
           "logical_pixels=%lu visible_bytes=%lu pages=%lu physical_bytes=%lu\n",
           (unsigned long)bird_profile.syscalls,
           (unsigned long)bird_profile.event_pre_barrier_filesystem_ops,
           (unsigned long)(
               bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_WRITE] -
               bird_profile.event_pre_barrier_diagnostic_writes),
           (unsigned long)
               bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_CLOSE],
           (unsigned long)bird_profile.event_pre_barrier_diagnostic_writes,
           (unsigned long)render->logical_pixels,
           (unsigned long)render->visible_bytes,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes);
#ifdef BIRD_PROFILE_DEEP
    printf("launcher profile_deep benchmark scenario=movement string_bytes=%lu "
           "catalog_iterations=%lu glyph_lookups=%lu glyph_scan_iterations=%lu "
           "rectangle_calls=%lu clipped_pixels=%lu fast_rectangle_calls=%lu "
           "fast_row_spans=%lu fast_u32_stores=%lu fast_u64_stores=%lu "
           "fallback_rectangle_calls=%lu fallback_pixel_checks=%lu "
           "fallback_pixel_stores=%lu fallback_byte_stores=%lu\n",
           (unsigned long)bird_profile_deep.string_bytes,
           (unsigned long)bird_profile_deep.catalog_iterations,
           (unsigned long)bird_profile_deep.glyph_lookups,
           (unsigned long)bird_profile_deep.glyph_scan_iterations,
           (unsigned long)bird_profile_deep.rectangle_calls,
           (unsigned long)bird_profile_deep.clipped_pixels,
           (unsigned long)bird_profile_deep.fast_rectangle_calls,
           (unsigned long)bird_profile_deep.fast_row_spans,
           (unsigned long)bird_profile_deep.fast_u32_stores,
           (unsigned long)bird_profile_deep.fast_u64_stores,
           (unsigned long)bird_profile_deep.fallback_rectangle_calls,
           (unsigned long)bird_profile_deep.fallback_pixel_checks,
           (unsigned long)bird_profile_deep.fallback_pixel_stores,
           (unsigned long)bird_profile_deep.fallback_byte_stores);
#endif

    /* Crossing row seven changes the current scrolling viewport. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    view = VIEW_SYSTEMS;
    selection = SYSTEM_ROWS - 1U;
    selected_status = "CATALOG READY FROM FIRMWARE";
    reset_fake_file(FAKE_FD, 0, 0);
    BIRD_PROFILE_BEGIN_EVENT();
    move_selection(1, 1U);
    BIRD_PROFILE_FINISH_EVENT();
    render = &bird_profile.render[PROFILE_RENDER_VIEWPORT_CHANGE];
    ok &= check(selection == SYSTEM_ROWS &&
                    render->commits == 1U &&
                    render->logical_pixels < 350000U &&
                    render->physical_bytes < 1400000U &&
                    render->pages_written == 1U,
                "scroll-boundary movement was not classified as viewport change");
    printf("launcher profile benchmark scenario=viewport-change "
           "logical_pixels=%lu visible_bytes=%lu pages=%lu physical_bytes=%lu\n",
           (unsigned long)render->logical_pixels,
           (unsigned long)render->visible_bytes,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes);

    bird_profile_reset();
    setup_test_framebuffer(2U, fake_framebuffer);
    setup_main_view();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    BIRD_PROFILE_RENDER(PROFILE_RENDER_SELECTION_MOVEMENT);
    draw_selection_update(old_selection, old_first);
    render = &bird_profile.render[PROFILE_RENDER_SELECTION_MOVEMENT];
    ok &= check(render->commits == 1U && render->pages_written == 2U &&
                    render->visible_bytes < render->physical_bytes &&
                    render->physical_bytes == render->visible_bytes * 2U,
                "diagnostic dirty movement lost two-page accounting");
#ifdef BIRD_PROFILE_DEEP
    ok &= check(bird_profile_deep.fast_rectangle_calls == 0U &&
                    bird_profile_deep.fallback_rectangle_calls > 0U &&
                    bird_profile_deep.fallback_pixel_checks > 0U &&
                    bird_profile_deep.fallback_pixel_stores > 0U &&
                    bird_profile_deep.fallback_byte_stores ==
                        render->physical_bytes,
                "diagnostic dirty movement bypassed checked fallback stores");
#endif
    printf("launcher profile benchmark scenario=movement-diagnostic "
           "logical_pixels=%lu visible_bytes=%lu pages=%lu physical_bytes=%lu\n",
           (unsigned long)render->logical_pixels,
           (unsigned long)render->visible_bytes,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes);

    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    reset_fake_file(FAKE_FD, 0, 0);
    action = select_current();
    ok &= check(action == ACTION_NONE && view == VIEW_PLAY &&
                    bird_profile.render[PROFILE_RENDER_VIEW_CHANGE].commits == 1U,
                "view transition did not use the view-change reason");

    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    toggle_current_favorite();
    render = &bird_profile.render[PROFILE_RENDER_STATUS];
    ok &= check(render->commits == 1U &&
                    render->physical_bytes < 100000U,
                "status-only path did not use the status reason");

    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    clear_favorites();
    favorites_loaded = 1;
    storage_ready = 1;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "ROM STORAGE READY";
    reset_fake_file(FAKE_FD, 0, 0);
    toggle_current_favorite();
    render = &bird_profile.render[PROFILE_RENDER_STATUS];
    ok &= check(is_favorite(0U) && render->commits == 1U &&
                    render->physical_bytes < 300000U &&
                    render->pages_written == 1U,
                "successful favorite update missed its bounded status render");
    printf("launcher profile benchmark scenario=favorite-toggle "
           "logical_pixels=%lu visible_bytes=%lu pages=%lu physical_bytes=%lu\n",
           (unsigned long)render->logical_pixels,
           (unsigned long)render->visible_bytes,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes);

    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    battery_percent = 9;
    charging_state = 0;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    bird_profile_reset();
    battery_percent = 100;
    charging_state = 1;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_BATTERY);
    draw_battery_update();
    render = &bird_profile.render[PROFILE_RENDER_BATTERY];
    ok &= check(render->commits == 1U &&
                    render->logical_pixels < 5000U &&
                    render->physical_bytes < 20000U &&
                    render->pages_written == 1U,
                "battery render reason was not recorded");
    printf("launcher profile benchmark scenario=battery "
           "logical_pixels=%lu visible_bytes=%lu pages=%lu physical_bytes=%lu\n",
           (unsigned long)render->logical_pixels,
           (unsigned long)render->visible_bytes,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes);

    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    clear_favorites();
    view = VIEW_FAVORITES;
    selection = 0U;
    favorites_loaded = 1;
    selected_status = "FAVORITES READY";
    BIRD_PROFILE_RENDER(PROFILE_RENDER_FAVORITES_COMPLETION);
    draw_content_and_status_update();
    render = &bird_profile.render[PROFILE_RENDER_FAVORITES_COMPLETION];
    ok &= check(render->commits == 1U &&
                    render->physical_bytes < RG34XX_FB_BYTES &&
                    render->pages_written == 1U,
                "Favorites-completion dirty render exceeded one full page");
    BIRD_PROFILE_RENDER(PROFILE_RENDER_RECOVERY);
    draw_screen();
    ok &= check(
        bird_profile.render[PROFILE_RENDER_FAVORITES_COMPLETION].commits == 1U &&
            bird_profile.render[PROFILE_RENDER_RECOVERY].commits == 1U,
        "Favorites-completion or recovery reason was not recorded");

    /* Production Favorites wiring distinguishes a completed publication from
     * a deferred retry while preserving today's redraw behavior. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    reset_storage_handoff_state();
    view = VIEW_FAVORITES;
    selection = 0U;
    favorites_loaded = 0;
    favorite_count = 0U;
    next_favorites_retry = (u64)fake_now_ms + 100U;
    reset_fake_file(FAKE_FD, 0, 0);
    receive_storage_handoff_signal();
    ok &= check(
        bird_profile.render[PROFILE_RENDER_STATUS].commits == 1U &&
            bird_profile.render[PROFILE_RENDER_FAVORITES_COMPLETION].commits == 0U,
        "deferred Favorites retry was mislabeled as completion");

    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    reset_storage_handoff_state();
    view = VIEW_FAVORITES;
    selection = 0U;
    favorites_loaded = 0;
    favorite_count = 0U;
    next_favorites_retry = 0;
    reset_fake_file(FAKE_FD, 0, 0);
    receive_storage_handoff_signal();
    ok &= check(favorites_loaded &&
                    bird_profile.render[
                        PROFILE_RENDER_FAVORITES_COMPLETION].commits == 1U,
                "successful Favorites publication lacked its render reason");

    /* An exit without a content selection is explicitly unavailable. */
    bird_profile_reset();
    reset_profile_log();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    bird_profile_note_exit_and_emit();
    ok &= check(profile_log_contains("selection_to_launcher_exit_ns=unavailable"),
                "non-selection exit serialized a false zero interval");

    /* A direct game launch retains the input-read timestamp through exit. */
    bird_profile_reset();
    reset_profile_log();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_profile_path_anchors();
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "ROM STORAGE READY";
    storage_ready = 1;
    pending_launch.kind = PENDING_LAUNCH_NONE;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    fake_now_ms = 4000;
    fake_now_sub_ms_ns = 100L;
    reset_fake_file(FAKE_FD, 0, 0);
    event.type = EV_KEY;
    event.code = BTN_EAST;
    event.value = 1;
    BIRD_PROFILE_BEGIN_EVENT();
    action = handle_event(&event);
    BIRD_PROFILE_FINISH_EVENT();
    ok &= check(action == ACTION_LAUNCH && bird_profile.selection_pending &&
                    bird_profile.resume_before_barrier > 0U,
                "direct launch lost its selection or content resume commit");
    fake_now_sub_ms_ns = 900L;
    bird_profile_note_exit_and_emit();
    ok &= check(bird_profile.selection_to_exit_ns == 800U &&
                    !profile_log_contains(
                        "selection_to_launcher_exit_ns=unavailable"),
                "direct selection-to-exit interval was not retained");
    fake_now_sub_ms_ns = 0;

    /* Navigation cancels a queued selection timestamp. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_profile_path_anchors();
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "CATALOG READY // ROMS MOUNTING";
    storage_ready = 0;
    pending_launch.kind = PENDING_LAUNCH_NONE;
    reset_fake_file(-ENOENT, 0, 0);
    BIRD_PROFILE_BEGIN_EVENT();
    action = handle_event(&event);
    BIRD_PROFILE_FINISH_EVENT();
    ok &= check(action == ACTION_NONE &&
                    pending_launch.kind == PENDING_LAUNCH_GAME &&
                    bird_profile.selection_pending,
                "queued game selection did not retain its timestamp");
    move_selection(1, 1U);
    ok &= check(pending_launch.kind == PENDING_LAUNCH_NONE &&
                    !bird_profile.selection_pending,
                "navigation did not cancel the queued selection timestamp");

    /* A queued selection remains attributable when storage later dispatches
     * the one pending intent. */
    bird_profile_reset();
    reset_profile_log();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_profile_path_anchors();
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "CATALOG READY // ROMS MOUNTING";
    storage_ready = 0;
    pending_launch.kind = PENDING_LAUNCH_NONE;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    fake_now_ms = 5000;
    reset_fake_file(-ENOENT, 0, 0);
    BIRD_PROFILE_BEGIN_EVENT();
    action = handle_event(&event);
    BIRD_PROFILE_FINISH_EVENT();
    ok &= check(action == ACTION_NONE &&
                    pending_launch.kind == PENDING_LAUNCH_GAME &&
                    bird_profile.selection_pending,
                "pending dispatch setup lost its selection timestamp");
    storage_ready = 1;
    fake_now_ms = 5001;
    reset_fake_file(FAKE_FD, 0, 0);
    action = dispatch_pending_launch();
    ok &= check(action == ACTION_LAUNCH && bird_profile.selection_pending,
                "queued dispatch did not retain its originating selection");
    bird_profile_note_exit_and_emit();
    ok &= check(bird_profile.selection_to_exit_ns == 1000000U &&
                    !profile_log_contains(
                        "selection_to_launcher_exit_ns=unavailable"),
                "queued selection-to-exit interval was unavailable");

    bird_profile_reset();
    setup_profile_path_anchors();
    pending_launch.kind = PENDING_LAUNCH_GAME;
    pending_launch.index = 0U;
    pending_launch.active_index = 0U;
    BIRD_PROFILE_MARK_SELECTION();
    reset_fake_file(-ENOENT, 0, 0);
    action = dispatch_pending_launch();
    ok &= check(action == ACTION_NONE && !bird_profile.selection_pending,
                "failed pending dispatch retained a stale selection interval");

#ifdef BIRD_PROFILE_DEEP
    bird_profile_reset();
    (void)catalog_path_supported("/mnt/mmc/a");
    (void)path_matches("/mnt/mmc/a", 10U, "/mnt/mmc/a");
    ok &= check(bird_profile_deep.string_bytes > 20U,
                "deep profiling missed path-validation string scans");
    clear_favorites();
    set_favorite(10U, 1);
    (void)favorite_catalog_index(0U);
    ok &= check(bird_profile_deep.catalog_iterations > 0U,
                "deep profiling did not count favorite catalog iterations");
#endif

    return ok;
}
#endif

int main(void) {
    char partial[CATALOG_PATH_MAX_BYTES + 8U];
    char complete[CATALOG_PATH_MAX_BYTES * 2U + 8U];
    u64 due;
    unsigned opens;
    u64 delay;
    int ok = 1;

    ok &= run_framebuffer_primitive_tests();
    ok &= run_full_render_golden_tests();
    ok &= run_dirty_region_render_tests();
    ok &= run_storage_handoff_tests();

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

#ifdef BIRD_PROFILE
    ok &= run_profile_tests();
#endif

    if (!ok) return 1;
    puts("launcher runtime C tests: PASS");
    return 0;
}
