/* Host fault-injection harness. It includes the production launcher so every
 * assertion below executes the exact favorites and poll decision code shipped
 * in the freestanding AArch64 binary. */

#include <stdio.h>
#include <string.h>

#define BIRD_HOST_TEST 1
#define PERSIST_UI_STATE 1
#define STORAGE_ANCHOR_MARKER "/run/muos/bird-storage-anchor-ready"
#define STORAGE_READY_SIGNAL "/run/muos/bird-storage-ready"
#define HANDOFF_ACTION_PATH "/run/muos/bird-launch-action"
#include "../../../launcher/bird-launcher.c"

#define FAKE_FD 41
#define EIO_LINUX 5
#define EBADF_LINUX 9

static long fake_now_ms;
static long fake_now_sub_ms_ns;
static long fake_open_result;
#define FAKE_OPEN_SCRIPT_MAX 64U
static long fake_open_script[FAKE_OPEN_SCRIPT_MAX];
static unsigned fake_open_script_count;
static unsigned fake_open_script_index;
#define FAKE_OPEN_PATH_BYTES 128U
static char fake_open_path[FAKE_OPEN_SCRIPT_MAX][FAKE_OPEN_PATH_BYTES];
static unsigned fake_open_path_count;
static unsigned fake_open_calls;
static unsigned fake_create_calls;
static unsigned fake_rename_calls;
static long fake_rename_result;
static char fake_rename_old_path[FAKE_OPEN_PATH_BYTES];
static char fake_rename_new_path[FAKE_OPEN_PATH_BYTES];
static unsigned fake_unlink_calls;
static char fake_unlink_path[FAKE_OPEN_PATH_BYTES];
static int fake_unlinked_launch_request;
static unsigned fake_close_calls;
static long fake_inotify_init_result;
static long fake_inotify_add_result;
static unsigned fake_inotify_init_calls;
static unsigned fake_inotify_add_calls;
static long fake_ppoll_result;
static short fake_ppoll_revents;
static unsigned fake_ppoll_calls;
#define FAKE_SYSCALL_TRACE_MAX 128U
static long fake_syscall_trace[FAKE_SYSCALL_TRACE_MAX];
static unsigned fake_syscall_trace_count;
static long fake_ioctl_result;
#define FAKE_IOCTL_SCRIPT_MAX 64U
static long fake_ioctl_script[FAKE_IOCTL_SCRIPT_MAX];
static const char *fake_ioctl_name_script[FAKE_IOCTL_SCRIPT_MAX];
static unsigned fake_ioctl_script_count;
static unsigned fake_ioctl_script_index;
static unsigned fake_ioctl_calls;
static long fake_write_result;
#define FAKE_WRITE_CAPTURE_BYTES 16384U
static char fake_write_capture[FAKE_WRITE_CAPTURE_BYTES];
static u64 fake_write_capture_bytes;
static int fake_capture_file_writes;
static const char *fake_payload;
static u64 fake_payload_bytes;
static u64 fake_payload_offset;
static long fake_terminal_read;
#define FAKE_READ_SCRIPT_MAX 64U
struct fake_read_step {
    long result;
    const char *payload;
};
static struct fake_read_step fake_read_script[FAKE_READ_SCRIPT_MAX];
static unsigned fake_read_script_count;
static unsigned fake_read_script_index;
static int fake_read_fd[FAKE_READ_SCRIPT_MAX * 2U];
static unsigned fake_read_fd_count;
static unsigned fake_sleep_calls;
static unsigned fake_clock_calls;
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
    if (fake_syscall_trace_count < FAKE_SYSCALL_TRACE_MAX)
        fake_syscall_trace[fake_syscall_trace_count++] = number;
    if (number == 26) {
        fake_inotify_init_calls++;
        return fake_inotify_init_result;
    }
    if (number == 27) {
        fake_inotify_add_calls++;
        return fake_inotify_add_result;
    }
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
    if (number == 73) {
        fake_ppoll_calls++;
        if (fake_ppoll_result > 0 && a0 && a1)
            ((struct pollfd *)a0)[0].revents = fake_ppoll_revents;
        return fake_ppoll_result;
    }
    if (number == 29) {
        long result = fake_ioctl_result;
        const char *name = 0;
        if (fake_ioctl_script_index < fake_ioctl_script_count) {
            result = fake_ioctl_script[fake_ioctl_script_index];
            name = fake_ioctl_name_script[fake_ioctl_script_index];
            fake_ioctl_script_index++;
        }
        fake_ioctl_calls++;
        if (result >= 0 && (u64)a1 == EVIOCGNAME_128 && name)
            snprintf((char *)a2, 128U, "%s", name);
        return result;
    }
    if (number == 82) return 0;
    if (number == 35) {
        fake_unlink_calls++;
        snprintf(fake_unlink_path, FAKE_OPEN_PATH_BYTES, "%s",
                 (const char *)a1);
        if (strcmp((const char *)a1, "bird-launch-request") == 0 ||
            strcmp((const char *)a1, LAUNCH_REQUEST) == 0)
            fake_unlinked_launch_request = 1;
        return 0;
    }
    if (number == 38) {
        fake_rename_calls++;
        snprintf(fake_rename_old_path, FAKE_OPEN_PATH_BYTES, "%s",
                 (const char *)a1);
        snprintf(fake_rename_new_path, FAKE_OPEN_PATH_BYTES, "%s",
                 (const char *)a3);
        return fake_rename_result;
    }
    if (number == 63) {
        u64 available;
        u64 bytes;
        if (fake_read_fd_count < sizeof(fake_read_fd) / sizeof(fake_read_fd[0]))
            fake_read_fd[fake_read_fd_count++] = (int)a0;
        if (fake_read_script_index < fake_read_script_count) {
            struct fake_read_step *step =
                &fake_read_script[fake_read_script_index++];
            if (step->result <= 0) return step->result;
            bytes = (u64)step->result < (u64)a2
                        ? (u64)step->result : (u64)a2;
            if (step->payload)
                memcpy((void *)a1, step->payload, (size_t)bytes);
            else
                memset((void *)a1, 0, (size_t)bytes);
            return (long)bytes;
        }
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
        if (fake_write_result) return fake_write_result;
        if (fake_capture_file_writes && a0 == FAKE_FD &&
            fake_write_capture_bytes < FAKE_WRITE_CAPTURE_BYTES) {
            u64 available = FAKE_WRITE_CAPTURE_BYTES -
                            fake_write_capture_bytes;
            u64 bytes = (u64)a2 < available ? (u64)a2 : available;
            memcpy(fake_write_capture + fake_write_capture_bytes,
                   (const void *)a1, (size_t)bytes);
            fake_write_capture_bytes += bytes;
        }
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
        fake_clock_calls++;
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
    fake_rename_result = 0;
    fake_rename_old_path[0] = 0;
    fake_rename_new_path[0] = 0;
    fake_unlink_calls = 0;
    fake_unlink_path[0] = 0;
    fake_unlinked_launch_request = 0;
    fake_ioctl_result = -EBADF_LINUX;
    fake_ioctl_script_count = 0;
    fake_ioctl_script_index = 0;
    fake_ioctl_calls = 0;
    fake_write_result = 0;
    fake_payload = payload ? payload : "";
    fake_payload_bytes = payload ? (u64)strlen(payload) : 0;
    fake_payload_offset = 0;
    fake_terminal_read = terminal_read;
    fake_read_script_count = 0U;
    fake_read_script_index = 0U;
    fake_read_fd_count = 0U;
    fake_clock_calls = 0;
    fake_inotify_init_result = -EBADF_LINUX;
    fake_inotify_add_result = -EBADF_LINUX;
    fake_inotify_init_calls = 0;
    fake_inotify_add_calls = 0;
    fake_ppoll_result = -EBADF_LINUX;
    fake_ppoll_revents = 0;
    fake_ppoll_calls = 0;
    fake_syscall_trace_count = 0;
    fake_write_capture_bytes = 0U;
    fake_capture_file_writes = 0;
}

static void begin_fake_file_write_capture(void) {
    fake_write_capture_bytes = 0U;
    fake_capture_file_writes = 1;
}

static void end_fake_file_write_capture(void) {
    fake_capture_file_writes = 0;
}

static void set_fake_read_script(const struct fake_read_step *steps,
                                 unsigned count) {
    unsigned index;
    if (count > FAKE_READ_SCRIPT_MAX) count = FAKE_READ_SCRIPT_MAX;
    for (index = 0; index < count; index++)
        fake_read_script[index] = steps[index];
    fake_read_script_count = count;
    fake_read_script_index = 0U;
}

static unsigned fake_read_count_for_fd(int fd) {
    unsigned count = 0U;
    unsigned index;
    for (index = 0; index < fake_read_fd_count; index++)
        if (fake_read_fd[index] == fd) count++;
    return count;
}

static int fake_opened_path(const char *path) {
    unsigned index;
    for (index = 0U; index < fake_open_path_count; index++)
        if (strcmp(fake_open_path[index], path) == 0) return 1;
    return 0;
}

static void set_fake_open_script(const long *results, unsigned count) {
    unsigned index;
    if (count > FAKE_OPEN_SCRIPT_MAX) count = FAKE_OPEN_SCRIPT_MAX;
    for (index = 0; index < count; index++)
        fake_open_script[index] = results[index];
    fake_open_script_count = count;
    fake_open_script_index = 0;
}

static void set_fake_ioctl_script(const long *results, const char **names,
                                  unsigned count) {
    unsigned index;
    if (count > FAKE_IOCTL_SCRIPT_MAX) count = FAKE_IOCTL_SCRIPT_MAX;
    for (index = 0; index < count; index++) {
        fake_ioctl_script[index] = results[index];
        fake_ioctl_name_script[index] = names ? names[index] : 0;
    }
    fake_ioctl_script_count = count;
    fake_ioctl_script_index = 0;
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

static u64 host_catalog_string_hash(const char *value) {
    u64 hash = 1469598103934665603UL;
    while (*value) {
        hash ^= (u8)*value++;
        hash *= 1099511628211UL;
    }
    return hash;
}

static int run_phase7_catalog_and_favorites_tests(void) {
    char favorites_file[1024];
    char expected_file[8192];
    char expected_request[8192];
    static const char utf8_e_acute[] = {(char)0xc3, (char)0xa9, 0};
    static const char utf8_e_grave[] = {(char)0xc3, (char)0xa8, 0};
    struct frame_resume_state snapshot;
    u32 index;
    u32 system_index;
    u32 media_index;
    u64 compact_record_bytes;
    const char *retained_name;
    const char *retained_path;
    u64 retained_name_hash;
    u64 retained_path_hash;
    int ok = 1;

    compact_record_bytes =
        sizeof(catalog_system_name_offsets) +
        sizeof(catalog_system_core_offsets) + sizeof(catalog_system_firsts) +
        sizeof(catalog_system_counts) + sizeof(catalog_system_launch_kinds) +
        sizeof(catalog_entry_name_offsets) + sizeof(catalog_entry_path_offsets) +
        sizeof(catalog_entry_systems) +
        sizeof(catalog_media_category_name_offsets) +
        sizeof(catalog_media_category_core_offsets) +
        sizeof(catalog_media_category_firsts) +
        sizeof(catalog_media_category_counts) +
        sizeof(catalog_media_category_sections) +
        sizeof(catalog_media_category_launch_kinds) +
        sizeof(catalog_media_entry_name_offsets) +
        sizeof(catalog_media_entry_path_offsets) +
        sizeof(catalog_media_entry_categories);
    ok &= check(sizeof(catalog_string_pool) == CATALOG_STRING_POOL_BYTES &&
                    catalog_string_pool[CATALOG_STRING_POOL_BYTES - 1U] == 0 &&
                    compact_record_bytes == CATALOG_RECORD_BYTES &&
                    sizeof(catalog_entry_path_order_xor) ==
                        CATALOG_PATH_ORDER_BYTES &&
                    CATALOG_METADATA_BYTES ==
                        CATALOG_RECORD_BYTES + CATALOG_PATH_ORDER_BYTES &&
                    CATALOG_STATIC_BYTES ==
                        CATALOG_STRING_POOL_BYTES + CATALOG_METADATA_BYTES,
                "compact catalog byte accounting does not match its arrays");
    ok &= check(CATALOG_STRING_POOL_BYTES <= 460000U &&
                    CATALOG_RECORD_BYTES <= 56U * 1024U &&
                    CATALOG_PATH_ORDER_BYTES <= 16U * 1024U,
                "compact catalog exceeded its explicit static-data budget");

    retained_name = catalog_entry_name(0U);
    retained_path = catalog_entry_path(CATALOG_ENTRY_COUNT - 1U);
    retained_name_hash = host_catalog_string_hash(retained_name);
    retained_path_hash = host_catalog_string_hash(retained_path);

    /* The generated representation is private to the accessor block. Verify
     * its stable logical contract before Favorites depends on it. */
    for (system_index = 0U; system_index < CATALOG_SYSTEM_COUNT;
         system_index++) {
        u32 first = catalog_system_first(system_index);
        u32 count = catalog_system_entry_count(system_index);
        ok &= check(catalog_system_name(system_index)[0] &&
                        catalog_system_core(system_index)[0] &&
                        first <= CATALOG_ENTRY_COUNT &&
                        count <= CATALOG_ENTRY_COUNT - first,
                    "catalog system accessor returned an invalid range");
        for (index = first; index < first + count; index++)
            ok &= check(catalog_entry_system(index) == system_index,
                        "catalog entry accessor lost its system identity");
    }
    for (index = 0U; index < CATALOG_ENTRY_COUNT; index++) {
        u32 catalog_index = catalog_entry_path_order_index(index);
        const char *path = catalog_entry_path(catalog_index);
        ok &= check(catalog_index < CATALOG_ENTRY_COUNT &&
                        catalog_entry_name(catalog_index)[0] && path[0] == '/' &&
                        catalog_find_entry_by_path(path, (u32)strlen(path)) ==
                            catalog_index,
                    "catalog path index failed an accessor round trip");
        if (index) {
            u32 previous = catalog_entry_path_order_index(index - 1U);
            ok &= check(strcmp(catalog_entry_path(previous), path) < 0,
                        "catalog path index is not strictly ordered");
        }
    }
    {
        const char *missing = "/mnt/mmc/ROMS/not-in-catalog.bird";
        ok &= check(catalog_find_entry_by_path(
                        missing, (u32)strlen(missing)) == CATALOG_ENTRY_COUNT,
                    "catalog path index returned a false match");
    }
    ok &= check(compare_catalog_path("abc", 3U, "abc") == 0 &&
                    compare_catalog_path("abc", 3U, "abcd") < 0 &&
                    compare_catalog_path("abcd", 4U, "abc") > 0 &&
                    compare_catalog_path(utf8_e_grave, 2U,
                                         utf8_e_acute) < 0 &&
                    compare_catalog_path(utf8_e_acute, 2U,
                                         utf8_e_grave) > 0,
                "catalog path comparator lost prefix or unsigned-byte order");

    for (media_index = 0U; media_index < CATALOG_MEDIA_CATEGORY_COUNT;
         media_index++) {
        u32 first = catalog_media_category_first(media_index);
        u32 count = catalog_media_category_entry_count(media_index);
        ok &= check(catalog_media_category_name(media_index)[0] &&
                        catalog_media_category_core(media_index)[0] &&
                        first <= CATALOG_MEDIA_ENTRY_COUNT &&
                        count <= CATALOG_MEDIA_ENTRY_COUNT - first,
                    "media category accessor returned an invalid range");
        for (index = first; index < first + count; index++)
            ok &= check(catalog_media_entry_category(index) == media_index &&
                            catalog_media_entry_name(index)[0] &&
                            catalog_media_entry_path(index)[0] == '/',
                        "media entry accessor lost its category identity");
    }
    ok &= check(host_catalog_string_hash(retained_name) == retained_name_hash &&
                    host_catalog_string_hash(retained_path) ==
                        retained_path_hash &&
                    retained_name == catalog_entry_name(0U) &&
                    retained_path ==
                        catalog_entry_path(CATALOG_ENTRY_COUNT - 1U),
                "catalog accessors did not return stable pooled pointers");

    /* Favorites remain in catalog order regardless of toggle order. Ordinal
     * mapping is O(1), duplicate mutations are idempotent, and a removal
     * shifts only the fixed index suffix while retaining bitmap membership. */
    clear_favorites();
    set_favorite(CATALOG_ENTRY_COUNT - 1U, 1);
    set_favorite(2U, 1);
    set_favorite(100U, 1);
    set_favorite(2U, 1);
    ok &= check(favorite_count == 3U && favorite_catalog_index(0U) == 2U &&
                    favorite_catalog_index(1U) == 100U &&
                    favorite_catalog_index(2U) == CATALOG_ENTRY_COUNT - 1U &&
                    favorite_catalog_index(3U) == CATALOG_ENTRY_COUNT,
                "Favorites index did not preserve catalog ordering");
    set_favorite(100U, 0);
    set_favorite(100U, 0);
    ok &= check(favorite_count == 2U && is_favorite(2U) &&
                    !is_favorite(100U) &&
                    is_favorite(CATALOG_ENTRY_COUNT - 1U) &&
                    favorite_catalog_index(0U) == 2U &&
                    favorite_catalog_index(1U) == CATALOG_ENTRY_COUNT - 1U,
                "Favorites removal left its fixed index inconsistent");

    /* Persistence remains exact-path based and may arrive in any order with
     * duplicates. Publication sorts only the in-memory ordinal index; it does
     * not change membership or the on-disk compatibility contract. */
    {
        const char *first_path = catalog_entry_path(0U);
        const char *middle_path =
            catalog_entry_path(CATALOG_ENTRY_COUNT / 2U);
        const char *last_path = catalog_entry_path(CATALOG_ENTRY_COUNT - 1U);
        int bytes = snprintf(favorites_file, sizeof(favorites_file),
                             "%s\n%s\n%s\n%s\n", last_path, first_path,
                             middle_path, first_path);
        ok &= check(bytes > 0 && (u32)bytes < sizeof(favorites_file),
                    "Favorites path-order fixture exceeded its host buffer");
        reset_favorites();
        reset_fake_file(FAKE_FD, favorites_file, 0);
        load_favorites();
        ok &= check(favorites_loaded && favorite_count == 3U &&
                        favorite_catalog_index(0U) == 0U &&
                        favorite_catalog_index(1U) ==
                            CATALOG_ENTRY_COUNT / 2U &&
                        favorite_catalog_index(2U) ==
                            CATALOG_ENTRY_COUNT - 1U,
                    "Favorites path load did not publish catalog order");

        bytes = snprintf(expected_file, sizeof(expected_file), "%s\n%s\n%s\n",
                         first_path, middle_path, last_path);
        ok &= check(bytes > 0 && (u32)bytes < sizeof(expected_file),
                    "Favorites save fixture exceeded its host buffer");
        reset_fake_file(FAKE_FD, 0, 0);
        begin_fake_file_write_capture();
        ok &= check(save_favorites() == 0,
                    "indexed Favorites failed its exact-byte save");
        end_fake_file_write_capture();
        ok &= check(fake_write_capture_bytes == (u64)bytes &&
                        memcmp(fake_write_capture, expected_file,
                               (size_t)bytes) == 0,
                    "Favorites save changed exact path order or bytes");
    }

    /* Accessor wiring must preserve the exact content-handoff protocol and
     * recent-file path, not merely return nonempty fields. */
    runtime_dir_fd = FAKE_FD;
    storage_dir_fd = FAKE_FD;
    config_dir_fd = FAKE_FD;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    reset_fake_file(FAKE_FD, 0, 0);
    begin_fake_file_write_capture();
    index = (u32)snprintf(
        expected_request, sizeof(expected_request), "%u\n%s\n%s\n%s\n",
        catalog_system_launch_kind(0U), catalog_system_core(0U),
        catalog_entry_name(0U), catalog_entry_path(0U));
    ok &= check(index < sizeof(expected_request) &&
                    launch_catalog_entry(0U) == ACTION_LAUNCH,
                "game accessor handoff did not launch");
    end_fake_file_write_capture();
    ok &= check(
        fake_write_capture_bytes ==
                (u64)index + sizeof(struct ui_resume_state) +
                    strlen(catalog_entry_path(0U)) + 1U &&
            memcmp(fake_write_capture, expected_request, index) == 0 &&
            memcmp(fake_write_capture + fake_write_capture_bytes -
                       strlen(catalog_entry_path(0U)) - 1U,
                   catalog_entry_path(0U),
                   strlen(catalog_entry_path(0U))) == 0 &&
            fake_write_capture[fake_write_capture_bytes - 1U] == '\n',
        "game request or recent path changed through catalog accessors");

    view = VIEW_MEDIA_ENTRIES;
    active_media_category = 0U;
    media_section = CATALOG_MEDIA_SECTION_LISTEN;
    selection = 0U;
    reset_fake_file(FAKE_FD, 0, 0);
    begin_fake_file_write_capture();
    index = (u32)snprintf(
        expected_request, sizeof(expected_request), "%u\n%s\n%s\n%s\n",
        catalog_media_category_launch_kind(0U),
        catalog_media_category_core(0U), catalog_media_entry_name(0U),
        catalog_media_entry_path(0U));
    ok &= check(index < sizeof(expected_request) &&
                    launch_media_entry(0U, 0U) == ACTION_LAUNCH,
                "media accessor handoff did not launch");
    end_fake_file_write_capture();
    ok &= check(fake_write_capture_bytes ==
                        (u64)index + sizeof(struct ui_resume_state) &&
                    memcmp(fake_write_capture, expected_request, index) == 0,
                "media request changed through catalog accessors");
    runtime_dir_fd = -1;
    storage_dir_fd = -1;
    config_dir_fd = -1;

    memset(&snapshot, 0, sizeof(snapshot));
    snapshot.favorites_loaded = 1U;
    snapshot.favorite_count = 2U;
    bitmap_set_favorite(snapshot.favorites, 3U, 1);
    bitmap_set_favorite(snapshot.favorites, CATALOG_ENTRY_COUNT - 2U, 1);
    restore_frame_resume_snapshot(&snapshot);
    ok &= check(favorites_loaded && favorite_count == 2U &&
                    favorite_catalog_index(0U) == 3U &&
                    favorite_catalog_index(1U) ==
                        CATALOG_ENTRY_COUNT - 2U,
                "retained Favorites bitmap did not rebuild ordinal order");
    clear_favorites();
    favorites_loaded = 0;
    charging_state = -1;
    battery_percent = -1;
    displayed_charging_state = -1;
    displayed_battery_percent = -1;
    frame_recovery_snapshot_restored = 0;
    return ok;
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
    reset_selected_text_scroll();
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

static int input_path_is(unsigned position, int event_index) {
    char expected[32];
    snprintf(expected, sizeof(expected), "/dev/input/event%d", event_index);
    return position < fake_open_path_count &&
           strcmp(fake_open_path[position], expected) == 0;
}

static int run_preferred_input_probe_tests(void) {
    long open_results[INPUT_EVENT_SCAN_COUNT];
    long ioctl_results[INPUT_EVENT_SCAN_COUNT];
    const char *ioctl_names[INPUT_EVENT_SCAN_COUNT];
    int seen[INPUT_EVENT_SCAN_COUNT];
    unsigned index;
    int event_index;
    int ok = 1;

    /* The measured RG34XX-SP node is accepted immediately, without opening
     * any fallback candidate or closing the retained descriptor. */
    reset_fake_file(-ENOENT, 0, 0);
    fake_close_calls = 0U;
    open_results[0] = 70;
    ioctl_results[0] = 0;
    ioctl_names[0] = "H700 Gamepad";
    set_fake_open_script(open_results, 1U);
    set_fake_ioctl_script(ioctl_results, ioctl_names, 1U);
    input_fd = -1;
    axis_x = 1;
    axis_y = -1;
    ok &= check(open_fixed_input_once() == 0 && input_fd == 70 &&
                    h700_input == 1 && input_path_is(0U, 4) &&
                    fake_open_path_count == 1U && fake_open_calls <= 1U &&
                    fake_ioctl_calls <= 1U && fake_close_calls == 0U &&
                    axis_x == 0 && axis_y == 0,
                "preferred H700 input did not take the one-candidate path");
    abandon_input();

    /* A missing preferred node falls through directly. Since no descriptor
     * was acquired, only the accepted fallback remains open. */
    reset_fake_file(-ENOENT, 0, 0);
    fake_close_calls = 0U;
    open_results[0] = -ENOENT;
    open_results[1] = 71;
    ioctl_results[0] = 0;
    ioctl_names[0] = "H700 Gamepad";
    set_fake_open_script(open_results, 2U);
    set_fake_ioctl_script(ioctl_results, ioctl_names, 1U);
    input_fd = -1;
    ok &= check(open_fixed_input_once() == 0 && input_fd == 71 &&
                    h700_input == 1 && input_path_is(0U, 4) &&
                    input_path_is(1U, 0) && fake_open_calls <= 2U &&
                    fake_ioctl_calls <= 1U && fake_close_calls == 0U,
                "missing preferred input did not fall back to event0");
    abandon_input();

    /* A live non-controller at event4 must be closed before event0 is kept. */
    reset_fake_file(-ENOENT, 0, 0);
    fake_close_calls = 0U;
    open_results[0] = 72;
    open_results[1] = 73;
    ioctl_results[0] = 0;
    ioctl_results[1] = 0;
    ioctl_names[0] = "Unrelated input";
    ioctl_names[1] = "H700 Gamepad";
    set_fake_open_script(open_results, 2U);
    set_fake_ioctl_script(ioctl_results, ioctl_names, 2U);
    input_fd = -1;
    ok &= check(open_fixed_input_once() == 0 && input_fd == 73 &&
                    h700_input == 1 && input_path_is(0U, 4) &&
                    input_path_is(1U, 0) && fake_open_calls <= 2U &&
                    fake_ioctl_calls <= 2U && fake_close_calls == 1U,
                "rejected preferred input descriptor leaked before fallback");
    abandon_input();

    /* EVIOCGNAME failure is a rejected candidate too: its fd is closed and
     * the validated fallback is retained. */
    reset_fake_file(-ENOENT, 0, 0);
    fake_close_calls = 0U;
    open_results[0] = 74;
    open_results[1] = 75;
    ioctl_results[0] = -EIO_LINUX;
    ioctl_results[1] = 0;
    ioctl_names[0] = 0;
    ioctl_names[1] = "H700 Gamepad";
    set_fake_open_script(open_results, 2U);
    set_fake_ioctl_script(ioctl_results, ioctl_names, 2U);
    input_fd = -1;
    ok &= check(open_fixed_input_once() == 0 && input_fd == 75 &&
                    h700_input == 1 && input_path_is(0U, 4) &&
                    input_path_is(1U, 0) && fake_open_calls <= 2U &&
                    fake_ioctl_calls <= 2U && fake_close_calls == 1U,
                "failed preferred EVIOCGNAME did not close and fall back");
    abandon_input();

    /* The vendor node remains accepted and selects the existing vendor map;
     * the navigation suite separately exercises its ABS and button bindings. */
    reset_fake_file(-ENOENT, 0, 0);
    fake_close_calls = 0U;
    open_results[0] = 76;
    ioctl_results[0] = 0;
    ioctl_names[0] = "muOS-Keys";
    set_fake_open_script(open_results, 1U);
    set_fake_ioctl_script(ioctl_results, ioctl_names, 1U);
    input_fd = -1;
    h700_input = 1;
    ok &= check(open_fixed_input_once() == 0 && input_fd == 76 &&
                    h700_input == 0 && input_path_is(0U, 4) &&
                    fake_open_path_count == 1U && fake_open_calls <= 1U &&
                    fake_ioctl_calls <= 1U && fake_close_calls == 0U,
                "preferred muOS-Keys input did not select the vendor map");
    abandon_input();

    /* If every candidate opens but names an unrelated device, the bounded
     * fallback visits each node once, closes every fd, and retains none. */
    for (index = 0; index < INPUT_EVENT_SCAN_COUNT; index++) {
        open_results[index] = 100L + (long)index;
        ioctl_results[index] = 0;
        ioctl_names[index] = "Unrelated input";
        seen[index] = 0;
    }
    reset_fake_file(-ENOENT, 0, 0);
    fake_close_calls = 0U;
    set_fake_open_script(open_results, INPUT_EVENT_SCAN_COUNT);
    set_fake_ioctl_script(ioctl_results, ioctl_names,
                          INPUT_EVENT_SCAN_COUNT);
    input_fd = -1;
    ok &= check(open_fixed_input_once() < 0 && input_fd == -1 &&
                    fake_open_calls <= INPUT_EVENT_SCAN_COUNT &&
                    fake_ioctl_calls <= fake_open_calls &&
                    fake_close_calls == fake_ioctl_calls &&
                    fake_open_path_count == INPUT_EVENT_SCAN_COUNT &&
                    input_path_is(0U, 4) && input_path_is(1U, 0),
                "exhaustive input fallback was unbounded or leaked an fd");
    for (index = 0; index < fake_open_path_count; index++) {
        event_index = -1;
        if (sscanf(fake_open_path[index], "/dev/input/event%d",
                   &event_index) != 1 || event_index < 0 ||
            event_index >= INPUT_EVENT_SCAN_COUNT || seen[event_index]) {
            ok &= check(0,
                        "exhaustive input fallback repeated an event node");
            break;
        }
        seen[event_index] = 1;
    }
    for (index = 0; index < INPUT_EVENT_SCAN_COUNT; index++)
        ok &= check(seen[index],
                    "exhaustive input fallback omitted an event node");

    /* Reconnect closes the broken descriptor and successful reacquisition
     * clears both axis latches before the replacement can emit an edge. */
    reset_fake_file(-ENOENT, 0, 0);
    fake_close_calls = 0U;
    open_results[0] = 80;
    ioctl_results[0] = 0;
    ioctl_names[0] = "H700 Gamepad";
    set_fake_open_script(open_results, 1U);
    set_fake_ioctl_script(ioctl_results, ioctl_names, 1U);
    fake_now_ms = 1000;
    input_fd = 79;
    axis_x = 1;
    axis_y = -1;
    ok &= check(reconnect_input("host-preferred-probe") == 0 &&
                    input_fd == 80 && h700_input == 1 &&
                    input_path_is(0U, 4) && fake_close_calls == 1U &&
                    fake_open_calls <= 1U && fake_ioctl_calls <= 1U &&
                    axis_x == 0 && axis_y == 0,
                "preferred reconnect leaked its old fd or retained latches");
    abandon_input();
    fake_close_calls = 0U;
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    return ok;
}

static int run_event_driven_input_discovery_tests(void) {
    struct inotify_fixture {
        s32 wd;
        u32 mask;
        u32 cookie;
        u32 len;
        char name[16];
    } event;
    struct fake_read_step read_steps[2];
    long open_results[INPUT_EVENT_SCAN_COUNT + 1U];
    long ioctl_results[1] = {0};
    const char *ioctl_names[1] = {"H700 Gamepad"};
    unsigned index;
    int ok = 1;

    ok &= check(fixed_input_event_index("event4", 7U) == 4 &&
                    fixed_input_event_index("event31", 8U) == 31 &&
                    fixed_input_event_index("event32", 8U) < 0 &&
                    fixed_input_event_index("mouse0", 7U) < 0 &&
                    fixed_input_event_index("event4-extra", 13U) < 0,
                "input creation-name validation accepted an ambiguous node");

    /* The production entry point must establish the watch before even its
     * preferred-node fast path. An already-present event4 still costs only
     * one open and one identity query. */
    reset_fake_file(-ENOENT, 0, 0);
    fake_inotify_init_result = 90;
    fake_inotify_add_result = 1;
    open_results[0] = 70;
    set_fake_open_script(open_results, 1U);
    set_fake_ioctl_script(ioctl_results, ioctl_names, 1U);
    input_fd = -1;
    ok &= check(open_fixed_input() == 0 && input_fd == 70 &&
                    fake_syscall_trace_count >= 3U &&
                    fake_syscall_trace[0] == 26 &&
                    fake_syscall_trace[1] == 27 &&
                    fake_syscall_trace[2] == 56 &&
                    fake_inotify_init_calls == 1U &&
                    fake_inotify_add_calls == 1U &&
                    fake_open_calls == 1U && fake_ppoll_calls == 0U &&
                    fake_sleep_calls == 0U,
                "input watch was not installed before the preferred probe");
    abandon_input();

    /* If no input exists, scan all nodes once, block on the creation edge,
     * and validate only that new node. No 1-ms sleep or second full scan is
     * allowed on the ordinary edge-driven path. */
    for (index = 0; index < INPUT_EVENT_SCAN_COUNT; index++)
        open_results[index] = -ENOENT;
    open_results[INPUT_EVENT_SCAN_COUNT] = 71;
    memset(&event, 0, sizeof(event));
    event.wd = 1;
    event.mask = IN_CREATE;
    event.len = sizeof(event.name);
    snprintf(event.name, sizeof(event.name), "event7");
    read_steps[0].result = sizeof(event);
    read_steps[0].payload = (const char *)&event;
    read_steps[1].result = -EAGAIN;
    read_steps[1].payload = 0;
    reset_fake_file(-ENOENT, 0, 0);
    fake_inotify_init_result = 90;
    fake_inotify_add_result = 1;
    fake_ppoll_result = 1;
    fake_ppoll_revents = POLLIN;
    set_fake_open_script(open_results, INPUT_EVENT_SCAN_COUNT + 1U);
    set_fake_ioctl_script(ioctl_results, ioctl_names, 1U);
    set_fake_read_script(read_steps, 2U);
    input_fd = -1;
    fake_now_ms = 1000;
    ok &= check(open_fixed_input() == 0 && input_fd == 71 &&
                    fake_open_calls == INPUT_EVENT_SCAN_COUNT + 1U &&
                    fake_open_path_count == INPUT_EVENT_SCAN_COUNT + 1U &&
                    strcmp(fake_open_path[INPUT_EVENT_SCAN_COUNT],
                           "event7") == 0 &&
                    fake_ioctl_calls == 1U && fake_ppoll_calls == 1U &&
                    fake_sleep_calls == 0U,
                "creation edge repeated the full input scan or slept");
    abandon_input();
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

static u32 framebuffer_pixel(u32 x, u32 y) {
    u32 value;
    memcpy(&value, fake_framebuffer +
                       ((u64)y * RG34XX_FB_STRIDE + (u64)x * 4U),
           sizeof(value));
    return value;
}

static int framebuffer_region_is_color(u32 x, u32 y, u32 width,
                                       u32 height, u32 expected) {
    u32 row;
    u32 column;
    for (row = 0U; row < height; row++) {
        for (column = 0U; column < width; column++) {
            if (framebuffer_pixel(x + column, y + row) != expected)
                return 0;
        }
    }
    return 1;
}

static int framebuffer_regions_equal(const u8 *left, const u8 *right,
                                     u32 x, u32 y, u32 width, u32 height) {
    u32 row;
    for (row = 0U; row < height; row++) {
        u64 offset = (u64)(y + row) * RG34XX_FB_STRIDE + (u64)x * 4U;
        if (memcmp(left + offset, right + offset,
                   (size_t)width * 4U) != 0)
            return 0;
    }
    return 1;
}

static int buffer_region_is_color(const u8 *buffer, u32 x, u32 y,
                                  u32 width, u32 height, u32 expected) {
    u32 row;
    u32 column;
    for (row = 0U; row < height; row++) {
        const u32 *pixels = (const u32 *)(buffer +
            (u64)(y + row) * RG34XX_FB_STRIDE + (u64)x * 4U);
        for (column = 0U; column < width; column++) {
            if (pixels[column] != expected)
                return 0;
        }
    }
    return 1;
}

static int framebuffer_visible_rgb_equal(const u8 *left, const u8 *right) {
    u64 offset;
    for (offset = 0; offset < RG34XX_FB_BYTES; offset += 4U) {
        if (left[offset] != right[offset] ||
            left[offset + 1U] != right[offset + 1U] ||
            left[offset + 2U] != right[offset + 2U])
            return 0;
    }
    return 1;
}

#ifdef BIRD_TEST_BOOT_FRAME_XRGB
static int load_boot_frame_fixture(u8 *target) {
    FILE *asset = fopen(BIRD_TEST_BOOT_FRAME_XRGB, "rb");
    int ok = asset != NULL &&
             fread(target, 1U, RG34XX_FB_BYTES, asset) == RG34XX_FB_BYTES &&
             fgetc(asset) == EOF;
    if (asset) fclose(asset);
    return ok;
}
#endif

static int run_phase5_startup_tests(void) {
    struct frame_resume_state state;
    struct frame_resume_state fallback_state;
    struct startup_work_state work;
    u32 candidate;
    u64 byte_offset;
    u8 saved_byte;
    int ok = 1;
    int seen_input_index[INPUT_EVENT_SCAN_COUNT];
    int order;

    memset(&work, 0, sizeof(work));
    work.task = STARTUP_TASK_PROFILE;
    ok &= check(startup_input_timeout(&work, 500U) == 0U,
                "deferred startup work blocked the immediate input sample");
    work.task = STARTUP_TASK_DONE;
    ok &= check(startup_input_timeout(&work, 500U) == 500U,
                "completed startup work changed the ordinary poll timeout");
    memset(seen_input_index, 0, sizeof(seen_input_index));
    for (order = 0; order < INPUT_EVENT_SCAN_COUNT; order++) {
        int index = fixed_input_scan_index(order);
        ok &= check(index >= 0 && index < INPUT_EVENT_SCAN_COUNT &&
                        !seen_input_index[index],
                    "preferred input scan omitted or duplicated an event");
        if (index >= 0 && index < INPUT_EVENT_SCAN_COUNT)
            seen_input_index[index] = 1;
    }
    ok &= check(fixed_input_scan_index(0) == PREFERRED_INPUT_EVENT &&
                    fixed_input_scan_index(1) == 0 &&
                    fixed_input_scan_index(INPUT_EVENT_SCAN_COUNT - 1) ==
                        INPUT_EVENT_SCAN_COUNT - 1,
                "hardware input event was not tried before fallback scan");
    input_fd = -1;
    ok &= check(!retained_frame_can_wait_for_verification(
                        FRAME_RECOVERY_CANDIDATE),
                "retained rows survived without an open input descriptor");
    input_fd = FAKE_FD;
    ok &= check(retained_frame_can_wait_for_verification(
                        FRAME_RECOVERY_CANDIDATE) &&
                    !retained_frame_can_wait_for_verification(
                        FRAME_RECOVERY_MATCHED),
                "retained-row gate did not require an open candidate");

    /* The production helper is called only after an input drain. A failed or
     * reconnecting drain cannot run background work, and one clean sample
     * advances exactly one bounded task before input is sampled again. */
    memset(&work, 0, sizeof(work));
    work.task = STARTUP_TASK_STORAGE_LOG;
    storage_signal_fd = -1;
    storage_signal_disabled = 0;
    reset_fake_file(FAKE_FD, 0, 0);
    ok &= check(!service_startup_work_after_input_sample(
                        &work, ACTION_LAUNCH, -EAGAIN, 0) &&
                    !service_startup_work_after_input_sample(
                        &work, ACTION_NONE, -EIO_LINUX, 0) &&
                    !service_startup_work_after_input_sample(
                        &work, ACTION_NONE, -EAGAIN, 1) &&
                    work.task == STARTUP_TASK_STORAGE_LOG &&
                    fake_unlink_calls == 0U,
                "deferred work crossed an input/action interruption");
    ok &= check(service_startup_work_after_input_sample(
                        &work, ACTION_NONE, -EAGAIN, 0) &&
                    work.task == STARTUP_TASK_FRAME_CLEANUP &&
                    fake_unlink_calls == 0U,
                "one input sample did not advance exactly one deferred task");
    ok &= check(service_startup_work_after_input_sample(
                        &work, ACTION_NONE, -EAGAIN, 0) &&
                    work.task == STARTUP_TASK_DONE &&
                    fake_unlink_calls == 2U,
                "the next input sample did not advance the next task");

    /* A validated resume descriptor is already the authoritative state.
     * Missing or malformed state still receives one deferred atomic repair. */
    memset(&work, 0, sizeof(work));
    work.task = STARTUP_TASK_CHECKPOINT;
    work.resume_loaded = 1;
    reset_fake_file(FAKE_FD, 0, 0);
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    service_startup_work_step(&work);
    ok &= check(work.task == STARTUP_TASK_POWER_ANCHOR &&
                    fake_create_calls == 0U && fake_rename_calls == 0U &&
                    fake_unlink_calls == 0U,
                "valid startup resume state was rewritten");
#ifdef BIRD_PROFILE
    ok &= check(bird_profile.syscalls == 0U &&
                    bird_profile.filesystem_ops == 0U &&
                    bird_profile.diagnostic_writes == 0U,
                "valid startup resume state retained hidden work");
    printf("launcher profile benchmark scenario=valid-resume-checkpoint "
           "syscalls=%lu filesystem_ops=%lu diagnostic_writes=%lu\n",
           (unsigned long)bird_profile.syscalls,
           (unsigned long)bird_profile.filesystem_ops,
           (unsigned long)bird_profile.diagnostic_writes);
#endif

    memset(&work, 0, sizeof(work));
    work.task = STARTUP_TASK_CHECKPOINT;
    work.resume_loaded = 0;
    reset_fake_file(FAKE_FD, 0, 0);
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    service_startup_work_step(&work);
    ok &= check(work.task == STARTUP_TASK_POWER_ANCHOR &&
                    fake_create_calls == 1U && fake_rename_calls == 1U &&
                    fake_unlink_calls == 0U,
                "invalid startup resume state lost its deferred repair");
#ifdef BIRD_PROFILE
    ok &= check(bird_profile.syscalls > 0U &&
                    bird_profile.filesystem_ops == 2U &&
                    bird_profile.diagnostic_writes > 0U,
                "invalid startup resume repair lost measurable work");
    printf("launcher profile benchmark scenario=invalid-resume-repair "
           "syscalls=%lu filesystem_ops=%lu diagnostic_writes=%lu\n",
           (unsigned long)bird_profile.syscalls,
           (unsigned long)bird_profile.filesystem_ops,
           (unsigned long)bird_profile.diagnostic_writes);
#endif

    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    clear_favorites();
    favorites_loaded = 1;
    set_favorite(0U, 1);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_base();
    ok &= check(framebuffer_pixel(10U, 10U) == color(10U, 14U, 20U) &&
                    framebuffer_pixel(MENU_TOP_BAR_X, MENU_TOP_BAR_Y) ==
                        color(239U, 226U, 217U) &&
                    framebuffer_pixel(SIDEBAR_X, SIDEBAR_Y) ==
                        color(239U, 226U, 217U) &&
                    framebuffer_pixel(MENU_ROW_LEFT,
                                      MENU_MAIN_ROW_START_Y) ==
                        color(36U, 10U, 18U) &&
                    framebuffer_pixel(MENU_FRAME_X, MENU_FOOTER_Y) ==
                        color(10U, 14U, 20U),
                "Phase 5A fallback exposed interactive menu pixels");
#if defined(BIRD_STATIC_BASE_PATH) && defined(BIRD_TEST_BOOT_FRAME_XRGB)
    ok &= check(load_boot_frame_fixture(fake_framebuffer_reference),
                "final-root XRGB fixture was unavailable");
    ok &= check(
        buffer_region_is_color(fake_framebuffer_reference,
                               MENU_TOP_BAR_X, MENU_TOP_BAR_Y,
                               MENU_TOP_BAR_WIDTH, MENU_TOP_BAR_H, 0U) &&
            buffer_region_is_color(fake_framebuffer_reference,
                                   SIDEBAR_X, SIDEBAR_Y,
                                   MENU_CONTENT_RIGHT - SIDEBAR_X,
                                   MENU_CONTENT_H, 0U) &&
            buffer_region_is_color(fake_framebuffer_reference,
                                   SIDEBAR_X + 3,
                                   MENU_CONTENT_Y + MENU_CONTENT_H,
                                   MENU_FRAME_RIGHT - (SIDEBAR_X + 3),
                                   3U, 0U),
        "native XRGB base retained pixels hidden by opaque launcher chrome");
    static_base = fake_framebuffer_reference;
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_RECOVERY);
    draw_startup_base();
    ok &= check(
        framebuffer_regions_equal(fake_framebuffer,
                                  fake_framebuffer_reference,
                                  0U, 0U, RG34XX_FB_WIDTH, 36U) &&
            framebuffer_regions_equal(fake_framebuffer,
                                      fake_framebuffer_reference,
                                      0U, 395U, RG34XX_FB_WIDTH,
                                      RG34XX_FB_HEIGHT - 395U) &&
            framebuffer_region_is_color(MENU_TOP_BAR_X, MENU_TOP_BAR_Y,
                                        MENU_TOP_BAR_WIDTH, MENU_TOP_BAR_H,
                                        color(239U, 226U, 217U)) &&
            framebuffer_region_is_color(SIDEBAR_X, SIDEBAR_Y,
                                        SIDEBAR_WIDTH, MENU_CONTENT_H,
                                        color(239U, 226U, 217U)) &&
            framebuffer_region_is_color(MENU_LEFT, MENU_CONTENT_Y,
                                        MENU_DIVIDER_WIDTH, MENU_CONTENT_H,
                                        color(55U, 18U, 29U)) &&
            framebuffer_region_is_color(MENU_LEFT + MENU_DIVIDER_WIDTH,
                                        MENU_CONTENT_Y,
                                        MENU_CONTENT_WIDTH - MENU_DIVIDER_WIDTH,
                                        MENU_CONTENT_H,
                                        color(36U, 10U, 18U)),
        "final-root recovery did not compose sparse native base and chrome");
    static_base = 0;
    memcpy(fake_framebuffer_reference, fake_framebuffer, RG34XX_FB_BYTES);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_base();
    ok &= check(
        framebuffer_regions_equal(fake_framebuffer,
                                  fake_framebuffer_reference,
                                  MENU_TOP_BAR_X, MENU_TOP_BAR_Y,
                                  MENU_TOP_BAR_WIDTH, MENU_TOP_BAR_H) &&
            framebuffer_regions_equal(fake_framebuffer,
                                      fake_framebuffer_reference,
                                      SIDEBAR_X, SIDEBAR_Y,
                                      SIDEBAR_WIDTH, MENU_CONTENT_H) &&
            framebuffer_regions_equal(fake_framebuffer,
                                      fake_framebuffer_reference,
                                      MENU_LEFT, MENU_CONTENT_Y,
                                      MENU_DIVIDER_WIDTH, MENU_CONTENT_H) &&
            framebuffer_regions_equal(fake_framebuffer,
                                      fake_framebuffer_reference,
                                      MENU_ROW_LEFT, MENU_CONTENT_Y,
                                      MENU_ROW_WIDTH, MENU_CONTENT_H) &&
            framebuffer_regions_equal(fake_framebuffer,
                                      fake_framebuffer_reference,
                                      SIDEBAR_X + 3,
                                      MENU_CONTENT_Y + MENU_CONTENT_H,
                                      MENU_FRAME_RIGHT - (SIDEBAR_X + 3),
                                      3U),
        "fallback and generated static chrome are not byte-identical");
#endif
#ifdef BIRD_REUSE_UBOOT_FRAME
#ifdef BIRD_TEST_BOOT_FRAME_XRGB
    ok &= check(load_boot_frame_fixture(fake_framebuffer_reference),
                "generated U-Boot XRGB fixture was unavailable");
    static_base = fake_framebuffer_reference;
    draw_startup_base();
    static_base = 0;
#endif
    ok &= check(inherited_boot_frame_matches(),
                "manifest-matched generated boot frame was not reusable");
    fake_framebuffer[3U] ^= 0xffU;
    ok &= check(inherited_boot_frame_matches(),
                "unused X byte rejected a visibly identical boot frame");
    fake_framebuffer[3U] ^= 0xffU;
    fake_framebuffer[0U] ^= 1U;
    ok &= check(!inherited_boot_frame_matches(),
                "changed visible boot pixel passed inherited-frame matching");
    fake_framebuffer[0U] ^= 1U;

    /* A verified-reuse production build intentionally has no early static
     * asset. Known-good view changes must preserve the inherited backdrop
     * outside the fixed opaque launcher chrome. */
    {
        u32 inherited_backdrop = framebuffer_pixel(10U, 10U);
        setup_main_view();
        selected_status = "DIRECT FRAMEBUFFER READY";
        draw_startup_menu_overlay();
        view = VIEW_PLAY;
        selection = 0U;
        selected_status = "PLAY SYSTEMS READY";
        draw_interactive_screen();
        ok &= check(inherited_backdrop != color(10U, 14U, 20U) &&
                        framebuffer_pixel(10U, 10U) == inherited_backdrop,
                    "verified-reuse view change erased the inherited backdrop");
    }
#endif

    selected_status = "STARTING GAME";
    charging_state = 0;
    battery_percent = 77;
    setup_test_framebuffer(1U, fake_framebuffer_reference);
    memset(fake_framebuffer_reference, 0x5a, RG34XX_FB_BYTES);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_base();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_menu_overlay();
    ok &= check(framebuffer_visible_rgb_equal(fake_framebuffer,
                                               fake_framebuffer_reference),
                "startup-base overlay diverged from the full interactive frame");
    view = VIEW_SYSTEMS;
    selection = 0U;
    selected_status = "CATALOG READY FROM FIRMWARE";
    setup_test_framebuffer(1U, fake_framebuffer_reference);
    memset(fake_framebuffer_reference, 0x5a, RG34XX_FB_BYTES);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_base();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_menu_overlay();
    ok &= check(framebuffer_visible_rgb_equal(fake_framebuffer,
                                               fake_framebuffer_reference),
                "non-main startup overlay left stale U-Boot header pixels");
    setup_main_view();
    selected_status = "STARTING GAME";
    charging_state = 0;
    battery_percent = 77;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    charging_state = 1;
    battery_percent = 88;
    ok &= check(capture_frame_resume_state(&state) == 0 &&
                    state.charging_state == 0 &&
                    state.battery_percent == 77 &&
                    state.favorite_count == 1U &&
                    bitmap_is_favorite(state.favorites, 0U) &&
                    frame_resume_state_matches(&state),
                "exact retained framebuffer did not qualify for recovery");
    pending_render_invalid = RENDER_INVALID_CONTENT;
    ok &= check(capture_frame_resume_state(&state) < 0,
                "stale content pixels qualified for retained recovery");
    pending_render_invalid = 0U;

    /* X has no scanout-visible bits in the exact measured framebuffer. DRM
     * may normalize it while ownership changes, so X-only differences must
     * not force a visually redundant full render. */
    saved_byte = fake_framebuffer[3U];
    fake_framebuffer[3U] ^= 0xffU;
    reset_frame_recovery_diagnostics();
    ok &= check(frame_resume_state_matches(&state) &&
                    frame_recovery_fingerprint_attempted &&
                    frame_recovery_region_mismatch_mask == 0U &&
                    frame_recovery_unused_x_changed,
                "unused-X-only change rejected a visible-equivalent frame");
    fake_framebuffer[3U] = saved_byte;

    byte_offset = 10U * RG34XX_FB_STRIDE + 10U * 4U;
    saved_byte = fake_framebuffer[byte_offset];
    fake_framebuffer[byte_offset] ^= 1U;
    reset_frame_recovery_diagnostics();
    ok &= check(!frame_resume_state_matches(&state) &&
                    frame_recovery_region_mismatch_mask ==
                        (1U << FRAME_REGION_HEADER) &&
                    !frame_recovery_unused_x_changed,
                "header RGB change passed retained-frame verification");
    fake_framebuffer[byte_offset] = saved_byte;

    byte_offset = 120U * RG34XX_FB_STRIDE + 10U * 4U;
    saved_byte = fake_framebuffer[byte_offset];
    fake_framebuffer[byte_offset] ^= 1U;
    reset_frame_recovery_diagnostics();
    ok &= check(!frame_resume_state_matches(&state) &&
                    frame_recovery_region_mismatch_mask ==
                        (1U << FRAME_REGION_CONTENT) &&
                    !frame_recovery_unused_x_changed,
                "content RGB change passed retained-frame verification");
    fake_framebuffer[byte_offset] = saved_byte;

    byte_offset = 450U * RG34XX_FB_STRIDE + 10U * 4U;
    saved_byte = fake_framebuffer[byte_offset];
    fake_framebuffer[byte_offset] ^= 1U;
    reset_frame_recovery_diagnostics();
    ok &= check(!frame_resume_state_matches(&state) &&
                    frame_recovery_region_mismatch_mask ==
                        (1U << FRAME_REGION_FOOTER) &&
                    !frame_recovery_unused_x_changed,
                "footer RGB change passed retained-frame verification");
    fake_framebuffer[byte_offset] = saved_byte;

    fake_framebuffer[3U] ^= 0xffU;
    byte_offset = 120U * RG34XX_FB_STRIDE + 10U * 4U;
    fake_framebuffer[byte_offset] ^= 1U;
    reset_frame_recovery_diagnostics();
    ok &= check(!frame_resume_state_matches(&state) &&
                    frame_recovery_region_mismatch_mask ==
                        (1U << FRAME_REGION_CONTENT) &&
                    frame_recovery_unused_x_changed,
                "combined X and RGB change lost recovery diagnostics");
    fake_framebuffer[3U] ^= 0xffU;
    fake_framebuffer[byte_offset] ^= 1U;

    state.battery_percent = 78;
    ok &= check(!frame_resume_state_matches(&state),
                "changed recovery metadata passed frame verification");
    state.battery_percent = 77;
    state.favorites[0] ^= 1U;
    ok &= check(!frame_resume_state_matches(&state),
                "changed Favorites snapshot passed frame verification");
    state.favorites[0] ^= 1U;
    selection = 1U;
    ok &= check(!frame_resume_state_matches(&state),
                "changed UI state passed retained-frame verification");
    selection = 0U;
    ok &= check(frame_resume_state_matches(&state),
                "restored retained frame no longer verified");
    state.descriptor_hash_a ^= 1U;
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    fake_payload = (const char *)&state;
    fake_payload_bytes = sizeof(state);
    ok &= check(read_frame_resume_candidate(&state) ==
                        FRAME_RECOVERY_INVALID &&
                    !frame_recovery_snapshot_restored,
                "corrupt frame descriptor digest passed the read boundary");
#ifdef BIRD_PROFILE
    ok &= check(
        bird_profile.frame_fingerprint_physical_bytes_read == 0U &&
            bird_profile.frame_fingerprint_visible_bytes_compared == 0U &&
            bird_profile.frame_fingerprint_pages_read == 0U,
        "corrupt frame descriptor scanned the framebuffer");
#endif
    state.descriptor_hash_a ^= 1U;
    state.version--;
    ok &= check(!frame_resume_state_is_candidate(&state),
                "old frame descriptor version qualified for recovery");
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    fake_payload = (const char *)&state;
    fake_payload_bytes = sizeof(state);
    ok &= check(read_frame_resume_candidate(&state) ==
                        FRAME_RECOVERY_INVALID,
                "old frame descriptor version passed the read boundary");
    state.version = FRAME_RESUME_VERSION;
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    fake_payload = (const char *)&state;
    fake_payload_bytes = sizeof(state) - 1U;
    ok &= check(read_frame_resume_candidate(&state) ==
                        FRAME_RECOVERY_INVALID,
                "truncated frame descriptor passed the read boundary");
#ifdef BIRD_PROFILE
    ok &= check(
        bird_profile.frame_fingerprint_physical_bytes_read == 0U &&
            bird_profile.frame_fingerprint_visible_bytes_compared == 0U &&
            bird_profile.frame_fingerprint_pages_read == 0U,
        "invalid frame descriptor scanned the framebuffer");
#endif

    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    fake_payload = (const char *)&state;
    fake_payload_bytes = sizeof(state);
    input_fd = -1;
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    candidate = read_frame_resume_candidate(&state);
    ok &= check(candidate == FRAME_RECOVERY_CANDIDATE &&
                    restore_frame_resume_candidate(&state) ==
                        FRAME_RECOVERY_MISMATCH,
                "retained frame was verified before input opened");
#ifdef BIRD_PROFILE
    ok &= check(bird_profile.frame_fingerprint_physical_bytes_read == 0U &&
                    bird_profile.frame_fingerprint_visible_bytes_compared ==
                        0U &&
                    bird_profile.frame_fingerprint_pages_read == 0U,
                "pre-input retained-frame path scanned framebuffer bytes");
#endif
    input_fd = FAKE_FD;
    charging_state = -1;
    battery_percent = -1;
    displayed_charging_state = -1;
    displayed_battery_percent = -1;
    clear_favorites();
    favorites_loaded = 0;
    fake_payload_offset = 0U;
    ok &= check(inspect_frame_resume() == FRAME_RECOVERY_MATCHED &&
                    charging_state == 0 && battery_percent == 77 &&
                    displayed_charging_state == 0 &&
                    displayed_battery_percent == 77 &&
                    favorites_loaded && favorite_count == 1U &&
                    is_favorite(0U),
                "published frame descriptor did not restore volatile display state");
#ifdef BIRD_PROFILE
    ok &= check(bird_profile.frame_fingerprint_physical_bytes_read ==
                        RG34XX_FB_BYTES &&
                    bird_profile.frame_fingerprint_visible_bytes_compared ==
                        RG34XX_FB_WIDTH * RG34XX_FB_HEIGHT * 3UL &&
                    bird_profile.frame_fingerprint_pages_read == 1U,
                "post-input recovery omitted framebuffer-read accounting");
    printf("launcher profile benchmark scenario=frame-fingerprint "
           "physical_bytes_read=%lu visible_bytes_compared=%lu "
           "pages_read=%lu pixel_pair_iterations=%u\n",
           (unsigned long)
               bird_profile.frame_fingerprint_physical_bytes_read,
           (unsigned long)
               bird_profile.frame_fingerprint_visible_bytes_compared,
           (unsigned long)bird_profile.frame_fingerprint_pages_read,
           (unsigned)(RG34XX_FB_WIDTH * RG34XX_FB_HEIGHT / 2U));
    bird_profile_reset();
    load_favorites_and_update_view();
    ok &= check(bird_profile.render[
                        PROFILE_RENDER_FAVORITES_COMPLETION].commits == 0U,
                "matched recovery redundantly completed Favorites");
#endif

    reset_fake_file(FAKE_FD, 0, 0);
    ok &= check(publish_frame_resume() == 0 &&
                    fake_create_calls == 1U && fake_rename_calls == 1U &&
                    (strcmp(fake_rename_old_path, FRAME_RESUME_TEMP) == 0 ||
                     strcmp(fake_rename_old_path,
                            "bird-launcher-frame-resume.tmp") == 0) &&
                    (strcmp(fake_rename_new_path, FRAME_RESUME_PATH) == 0 ||
                     strcmp(fake_rename_new_path,
                            "bird-launcher-frame-resume") == 0),
                "frame recovery descriptor was not atomically published");

    memcpy(fake_framebuffer_reference, fake_framebuffer, RG34XX_FB_BYTES);
    for (byte_offset = 3U; byte_offset < RG34XX_FB_BYTES;
         byte_offset += 4U)
        fake_framebuffer[byte_offset] ^= 0xffU;
    reset_frame_recovery_diagnostics();
    ok &= check(frame_resume_state_matches(&state) &&
                    frame_recovery_region_mismatch_mask == 0U &&
                    frame_recovery_unused_x_changed,
                "full-page unused-X normalization rejected retained RGB");
    selected_status = "RETURNED TO PREVIOUS SCREEN";
    setup_test_framebuffer(1U, fake_framebuffer);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_RECOVERY);
    draw_recovery_update();
    setup_test_framebuffer(1U, fake_framebuffer_reference);
    setup_main_view();
    selected_status = "RETURNED TO PREVIOUS SCREEN";
    charging_state = 0;
    battery_percent = 77;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    ok &= check(memcmp(fake_framebuffer, fake_framebuffer_reference,
                       RG34XX_FB_BYTES) != 0 &&
                    framebuffer_visible_rgb_equal(
                        fake_framebuffer, fake_framebuffer_reference),
                "retained-frame recovery differs visibly from a full render");

    setup_test_framebuffer(2U, fake_framebuffer);
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    ok &= check(capture_frame_resume_state(&state) < 0 &&
                    inspect_frame_resume() == FRAME_RECOVERY_UNSUPPORTED,
                "diagnostic framebuffer entered retained-frame fast recovery");
#ifdef BIRD_PROFILE
    ok &= check(
        bird_profile.frame_fingerprint_physical_bytes_read == 0U &&
            bird_profile.frame_fingerprint_visible_bytes_compared == 0U &&
            bird_profile.frame_fingerprint_pages_read == 0U,
        "diagnostic framebuffer scanned the exact-path fingerprint");
#endif

    /* A sealed descriptor's volatile UI snapshot remains useful when a real
     * RGB mismatch requires a full render. Restore it before that render so
     * Favorites stars and displayed power do not wait for later navigation. */
    setup_test_framebuffer(1U, fake_framebuffer);
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "STARTING GAME";
    clear_favorites();
    favorites_loaded = 1;
    set_favorite(catalog_system_first(0U), 1);
    charging_state = 0;
    battery_percent = 77;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    ok &= check(capture_frame_resume_state(&fallback_state) == 0,
                "favorite fallback descriptor was not captured");
    fake_framebuffer[10U * RG34XX_FB_STRIDE + 10U * 4U] ^= 1U;
    fake_framebuffer[120U * RG34XX_FB_STRIDE + 10U * 4U] ^= 1U;
    fake_framebuffer[450U * RG34XX_FB_STRIDE + 10U * 4U] ^= 1U;
    clear_favorites();
    favorites_loaded = 0;
    charging_state = -1;
    battery_percent = -1;
    displayed_charging_state = -1;
    displayed_battery_percent = -1;
    reset_frame_recovery_diagnostics();
    input_fd = FAKE_FD;
    ok &= check(restore_frame_resume_candidate(&fallback_state) ==
                        FRAME_RECOVERY_MISMATCH &&
                    frame_recovery_region_mismatch_mask == 7U &&
                    frame_recovery_snapshot_restored && favorites_loaded &&
                    favorite_count == 1U &&
                    is_favorite(catalog_system_first(0U)) &&
                    charging_state == 0 && battery_percent == 77,
                "RGB fallback discarded the sealed display snapshot");
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    memcpy(fake_framebuffer_reference, fake_framebuffer, RG34XX_FB_BYTES);
    clear_favorites();
    favorites_loaded = 0;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    ok &= check(memcmp(fake_framebuffer, fake_framebuffer_reference,
                       RG34XX_FB_BYTES) != 0,
                "favorite snapshot did not affect fallback pixels");
    favorites_loaded = 1;
    set_favorite(catalog_system_first(0U), 1);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    ok &= check(memcmp(fake_framebuffer, fake_framebuffer_reference,
                       RG34XX_FB_BYTES) == 0,
                "snapshot fallback differs from canonical favorite render");
    input_fd = -1;
    return ok;
}

static int run_phase6_background_tests(void) {
    static const char unrelated_event[] =
        "change@/devices/virtual/input/input0\0SUBSYSTEM=input\0";
    static const char relevant_event_a[] =
        "change@/devices/platform/battery\0ACTION=change\0"
        "SUBSYSTEM=power_supply\0";
    static const char relevant_event_b[] =
        "change@/devices/platform/charger\0ACTION=change\0"
        "SUBSYSTEM=power_supply\0";
    static const char charging_value[] = "Charging\n";
    static const char percent_value[] = "75\n";
    struct navigation_batch cancel_batch;
    struct input_event cancel_event;
    struct fake_read_step read_steps[16];
    long storage_opens[4];
    char oversized_unrelated[2048];
    unsigned reads_before;
    unsigned index;
    int post_action;
    int ok = 1;

    /* No-op work does not read the clock. Unfinished startup and an initial
     * acquisition request an immediate input sample without reading it either. */
    fake_now_ms = 0;
    fake_clock_calls = 0;
    storage_ready = 1;
    favorites_loaded = 1;
    storage_signal_fd = -1;
    storage_signal_disabled = 0;
    storage_probe_attempted = 1;
    power_event_fd = -1;
    power_event_disabled = 1;
    next_power_event_retry = 0;
    ok &= check(idle_background_poll_timeout(1U, 77U) == 77U &&
                    fake_clock_calls == 0U,
                "idle background timeout caused a clock read unnecessarily");
    ok &= check(idle_background_poll_timeout(0U, 77U) == 0U &&
                    fake_clock_calls == 0U,
                "unfinished startup did not request an immediate input sample");
    power_event_disabled = 0;
    next_power_event_retry = 0;
    ok &= check(idle_background_poll_timeout(1U, (u64)-1) == 0U &&
                    fake_clock_calls == 0U,
                "initial background acquisition read the clock");

    /* Power retry deadline is deferred until interactive startup and should
     * convert to a minimum timeout via the shared background timeout helper. */
    fake_now_ms = 1000;
    fake_clock_calls = 0;
    power_event_fd = -1;
    power_event_disabled = 0;
    next_power_event_retry = 2200;
    power_event_retry_count = 0;
    ok &= check(idle_background_poll_timeout(1U, (u64)-1) == 1200U &&
                    fake_clock_calls == 1U,
                "idle background timeout did not use the bounded power retry");
    fake_clock_calls = 0;
    ok &= check(idle_background_poll_timeout(1U, 0U) == 0U &&
                    fake_clock_calls == 0U,
                "already-immediate input sample read a retry clock");

    /* Favorites and power share one current-time sample when both retry
     * deadlines are still in the future. */
    storage_ready = 1;
    favorites_loaded = 0;
    next_favorites_retry = 2000U;
    power_event_fd = -1;
    power_event_disabled = 0;
    next_power_event_retry = 2200U;
    fake_clock_calls = 0;
    ok &= check(!service_idle_background_after_input(1, 0, 0, 0, 0) &&
                    fake_clock_calls == 1U,
                "background retry checks did not share one clock sample");

    /* Simultaneous storage and power failures consume only the storage slot.
     * Power remains untouched until a new input sample. */
    reset_storage_handoff_state();
    storage_ready = 1;
    favorites_loaded = 1;
    storage_signal_fd = FAKE_FD;
    storage_signal_disabled = 0;
    storage_probe_attempted = 1;
    power_event_fd = 42;
    power_event_disabled = 0;
    power_event_retry_count = 0;
    next_power_event_retry = 0;
    pending_launch.kind = PENDING_LAUNCH_NONE;
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    fake_close_calls = 0U;
    post_action = ACTION_NONE;
    ok &= check(service_post_input_work(
                    1, POLLHUP, 1, POLLHUP, 1,
                    &post_action, -EAGAIN, 0) &&
                storage_signal_disabled && storage_signal_fd == -1 &&
                power_event_fd == 42 && fake_close_calls == 1U &&
                post_action == ACTION_NONE,
                "one background slot handled more than storage");
    ok &= check(service_post_input_work(
                    1, 0, 0, POLLHUP, 1,
                    &post_action, -EAGAIN, 0) &&
                power_event_fd == -1 && fake_close_calls == 2U &&
                post_action == ACTION_NONE,
                "next clean sample did not advance exactly one power unit");

    /* Exit, failed drains and reconnects suppress post-input background work. */
    storage_ready = 1;
    favorites_loaded = 1;
    storage_signal_fd = FAKE_FD;
    storage_signal_disabled = 0;
    power_event_fd = 42;
    power_event_disabled = 0;
    reset_fake_file(FAKE_FD, 0, 0);
    fake_close_calls = 0U;
    post_action = ACTION_SHUTDOWN;
    ok &= check(!service_post_input_work(
                    1, POLLHUP, 1, POLLHUP, 1,
                    &post_action, -EAGAIN, 0),
                "post-input background crossed an exit action");
    post_action = ACTION_NONE;
    ok &= check(!service_post_input_work(
                    1, POLLHUP, 1, POLLHUP, 1,
                    &post_action, -EIO_LINUX, 0),
                "post-input background crossed a failed input drain");
    ok &= check(!service_post_input_work(
                    1, POLLHUP, 1, POLLHUP, 1,
                    &post_action, -EAGAIN, 1) &&
                    storage_signal_fd == FAKE_FD &&
                    !storage_signal_disabled && power_event_fd == 42 &&
                    fake_close_calls == 0U,
                "post-input background crossed an exit or invalid input drain");
    pending_launch.kind = PENDING_LAUNCH_NONE;

    /* A storage-ready pending intent is foreground work. It dispatches after
     * the clean input drain and before a simultaneously readable power fd can
     * consume any event or open either power-supply attribute. */
    runtime_dir_fd = FAKE_FD;
    input_dir_fd = FAKE_FD;
    power_dir_fd = FAKE_FD;
    storage_dir_fd = FAKE_FD;
    config_dir_fd = FAKE_FD;
    storage_ready = 1;
    favorites_loaded = 1;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    pending_launch.kind = PENDING_LAUNCH_GAME;
    pending_launch.index = 0U;
    pending_launch.active_index = 0U;
    power_event_fd = 42;
    power_event_disabled = 0;
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    post_action = ACTION_NONE;
    ok &= check(service_post_input_work(
                    1, 0, 0, POLLIN, 1, &post_action, -EAGAIN, 0) &&
                    post_action == ACTION_LAUNCH &&
                    pending_launch.kind == PENDING_LAUNCH_NONE &&
                    fake_read_count_for_fd(42) == 0U &&
                    !fake_opened_path("status") &&
                    !fake_opened_path("capacity") &&
                    fake_opened_path("bird-launch-request"),
                "ready pending launch was starved by a readable power fd");

    /* Cancellation committed by the just-finished input batch remains
     * authoritative: the same post-input scheduler sees no intent to launch. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    favorites_loaded = 1;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "GAME QUEUED // STORAGE MOUNTING";
    charging_state = 0;
    battery_percent = 50;
    storage_ready = 1;
    pending_launch.kind = PENDING_LAUNCH_GAME;
    pending_launch.index = 0U;
    pending_launch.active_index = 0U;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    reset_navigation_batch(&cancel_batch);
    cancel_event.sec = 0;
    cancel_event.usec = 0;
    cancel_event.type = EV_KEY;
    cancel_event.code = BTN_DPAD_DOWN;
    cancel_event.value = 1;
    h700_input = 1;
    (void)handle_batched_input_event(&cancel_batch, &cancel_event);
    finish_navigation_batch(&cancel_batch);
    read_steps[0].result = (long)sizeof(unrelated_event) - 1L;
    read_steps[0].payload = unrelated_event;
    read_steps[1].result = -EAGAIN;
    read_steps[1].payload = 0;
    power_event_fd = 42;
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    set_fake_read_script(read_steps, 2U);
    post_action = ACTION_NONE;
    ok &= check(pending_launch.kind == PENDING_LAUNCH_NONE &&
                    service_post_input_work(
                        1, 0, 0, POLLIN, 1, &post_action, -EAGAIN, 0) &&
                    post_action == ACTION_NONE &&
                    !fake_opened_path("bird-launch-request"),
                "completed navigation cancellation was followed by dispatch");

    /* The one-shot storage FIFO consumes no more than one read attempt in a
     * background slot. A positive edge still enters the existing exact
     * acquisition path immediately. */
    reset_storage_handoff_state();
    storage_signal_fd = 42;
    reset_fake_file(FAKE_FD, "ready\n", -EAGAIN);
    storage_opens[0] = FAKE_FD;
    storage_opens[1] = FAKE_FD;
    storage_opens[2] = FAKE_FD;
    storage_opens[3] = FAKE_FD;
    set_fake_open_script(storage_opens, 4U);
    ok &= check(service_storage_poll_event(POLLIN, 1) && storage_ready &&
                    storage_handoff_signaled &&
                    fake_read_count_for_fd(42) <= 1U,
                "storage FIFO read was unbounded or missed its positive edge");

    reset_storage_handoff_state();
    storage_signal_fd = 42;
    reset_fake_file(FAKE_FD, 0, -EINTR);
    ok &= check(service_storage_poll_event(POLLIN, 1) &&
                    fake_read_count_for_fd(42) <= 1U &&
                    storage_signal_fd == 42 && !storage_handoff_signaled &&
                    !storage_signal_disabled,
                "interrupted storage FIFO read retried within one slot");

    /* A large unrelated record followed by an unrelated storm yields after
     * the fixed read budget without touching sysfs. The unread tail advances
     * when a later clean input sample grants another background slot. */
    storage_ready = 1;
    favorites_loaded = 1;
    memset(oversized_unrelated, 'x', sizeof(oversized_unrelated));
    for (index = 0U; index < 10U; index++) {
        read_steps[index].result = index == 0U
                                       ? (long)sizeof(oversized_unrelated)
                                       : (long)sizeof(unrelated_event) - 1L;
        read_steps[index].payload = index == 0U
                                        ? oversized_unrelated
                                        : unrelated_event;
    }
    power_event_fd = 42;
    power_event_disabled = 0;
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    set_fake_read_script(read_steps, 10U);
    ok &= check(service_power_poll_event(POLLIN, 1) &&
                    fake_read_count_for_fd(42) <= POWER_EVENT_READ_BUDGET &&
                    fake_read_script_index == POWER_EVENT_READ_BUDGET &&
                    fake_open_calls == 0U && power_event_fd == 42,
                "unrelated power storm exceeded its slot or read sysfs");
    reads_before = fake_read_count_for_fd(42);
    ok &= check(service_power_poll_event(POLLIN, 1) &&
                    fake_read_script_index == 10U &&
                    fake_read_count_for_fd(42) > reads_before &&
                    fake_read_count_for_fd(42) - reads_before <=
                        POWER_EVENT_READ_BUDGET &&
                    fake_open_calls == 0U,
                "later power slot did not advance the unread storm tail");

    /* EINTR consumes the same finite budget. A signal storm therefore cannot
     * keep input from being sampled again. */
    for (index = 0U; index < 12U; index++) {
        read_steps[index].result = -EINTR;
        read_steps[index].payload = 0;
    }
    power_event_fd = 42;
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    set_fake_read_script(read_steps, 12U);
    ok &= check(service_power_poll_event(POLLIN, 1) &&
                    fake_read_count_for_fd(42) <= POWER_EVENT_READ_BUDGET &&
                    fake_read_script_index == POWER_EVENT_READ_BUDGET &&
                    fake_open_calls == 0U,
                "power EINTR storm was not bounded by the read budget");
    reads_before = fake_read_count_for_fd(42);
    ok &= check(service_power_poll_event(POLLIN, 1) &&
                    fake_read_script_index == 12U &&
                    fake_read_count_for_fd(42) > reads_before &&
                    fake_read_count_for_fd(42) - reads_before <=
                        POWER_EVENT_READ_BUDGET,
                "power EINTR tail did not progress in a later slot");

    /* Multiple relevant records in one slot are coalesced into one status and
     * capacity snapshot, followed by at most one battery render. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    setup_main_view();
    charging_state = 0;
    battery_percent = 50;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    read_steps[0].result = (long)sizeof(relevant_event_a) - 1L;
    read_steps[0].payload = relevant_event_a;
    read_steps[1].result = (long)sizeof(relevant_event_b) - 1L;
    read_steps[1].payload = relevant_event_b;
    read_steps[2].result = -EAGAIN;
    read_steps[2].payload = 0;
    read_steps[3].result = (long)sizeof(charging_value) - 1L;
    read_steps[3].payload = charging_value;
    read_steps[4].result = (long)sizeof(percent_value) - 1L;
    read_steps[4].payload = percent_value;
    power_event_fd = 42;
    power_event_disabled = 0;
    reset_fake_file(FAKE_FD, 0, -EAGAIN);
    set_fake_read_script(read_steps, 5U);
    ok &= check(service_power_poll_event(POLLIN, 1) &&
                    fake_read_count_for_fd(42) <= POWER_EVENT_READ_BUDGET &&
                    fake_open_calls <= 2U && charging_state == 1 &&
                    battery_percent == 75 && displayed_charging_state == 1 &&
                    displayed_battery_percent == 75,
                "relevant power burst did not coalesce one sysfs snapshot");
#ifdef BIRD_PROFILE
    ok &= check(bird_profile.render[PROFILE_RENDER_BATTERY].commits <= 1U &&
                    bird_profile.render[PROFILE_RENDER_BATTERY].commits == 1U,
                "relevant power burst committed more than one battery render");
#endif
    power_event_fd = -1;
    power_event_disabled = 1;

    return ok;
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
    reset_selected_text_scroll();
}

static int check_full_render_golden(u64 expected, const char *message) {
    u64 actual;
    draw_screen();
    actual = framebuffer_hash();
    if (actual != expected)
        fprintf(stderr, "%s: expected=0x%016llx actual=0x%016llx\n",
                message, (unsigned long long)expected,
                (unsigned long long)actual);
    return check(actual == expected, message);
}

static int run_full_render_golden_tests(void) {
    char breadcrumb[64];
    u32 psp_system = CATALOG_SYSTEM_COUNT;
    u32 index;
    int ok = 1;

    ok &= check(MENU_FRAME_X == RG34XX_FB_WIDTH - MENU_FRAME_RIGHT &&
                    MENU_TOP_BAR_WIDTH == 400 &&
                    MENU_CONTENT_H == 288 &&
                    MENU_TOP_BAR_WIDTH * 100U / MENU_CONTENT_H == 138U,
                "launcher chrome lost its centered MiSTer proportions");
    ok &= check(MENU_LABEL_SCALE == 2 && MENU_ITEM_SCALE_X == 3 &&
                    MENU_ITEM_SCALE_Y == 3,
                "launcher visual contract no longer has exactly two scales");
    ok &= check(MENU_PAGE_ROWS == 9U &&
                    SYSTEM_ROWS == MENU_PAGE_ROWS &&
                    GAME_ROWS == MENU_PAGE_ROWS &&
                    MENU_CONTENT_H == MENU_PAGE_ROWS * MENU_ROW_SPACING &&
                    MENU_ROW_H == MENU_ROW_SPACING,
                "fixed page no longer exactly tiles nine complete rows");
    ok &= check(MENU_MAIN_ROW_START_Y == MENU_CONTENT_Y &&
                    MENU_MAIN_ROW_SPACING == MENU_ROW_SPACING &&
                    MENU_MAIN_ROW_H == MENU_ROW_H &&
                    MENU_MAIN_TEXT_Y_OFFSET == 5,
                "main menu rows are no longer top-justified on the list grid");
    ok &= check(MENU_ROW_LEFT == MENU_LEFT + MENU_DIVIDER_WIDTH &&
                    MENU_ROW_LEFT + MENU_ROW_WIDTH == MENU_FRAME_RIGHT &&
                    MENU_DIVIDER_WIDTH == 10,
                "selection no longer preserves its dark divider and flush right edge");
    ok &= check(MENU_HELP_X_OFFSET == 2 && MENU_HELP_Y == 429 &&
                    MENU_HELP_Y + 7 * MENU_LABEL_SCALE ==
                        (MENU_CONTENT_Y + MENU_CONTENT_H + RG34XX_FB_HEIGHT) /
                            2 + 7,
                "footer legend is not centered below the menu");
    ok &= check(MENU_SIDEBAR_SCALE == 3 &&
                    MENU_SIDEBAR_LETTER_ADVANCE == 20,
                "sidebar label lost its larger, letter-spaced type");
    ok &= check(MENU_BATTERY_TEXT_RIGHT == 552 &&
                    MENU_BATTERY_ICON_MIN_X == 489,
                "battery group lost its balanced top-bar inset");

    setup_full_render_golden();
    view = VIEW_MAIN;
    selected_status = "DIRECT FRAMEBUFFER READY";
    draw_screen();
    ok &= check(framebuffer_region_is_color(
                        MENU_ROW_LEFT, MENU_CONTENT_Y,
                        MENU_TEXT_X - MENU_ROW_LEFT,
                        MENU_MAIN_ROW_H, color(239U, 226U, 217U)) &&
                    framebuffer_pixel(MENU_FRAME_RIGHT - 1U,
                                      MENU_CONTENT_Y) ==
                        color(239U, 226U, 217U) &&
                    framebuffer_region_is_color(
                        MENU_LEFT, MENU_CONTENT_Y,
                        MENU_DIVIDER_WIDTH, MENU_MAIN_ROW_H,
                        color(55U, 18U, 29U)),
                "main selection gained an arrow, top margin, right margin, or lost its divider");
    ok &= check(framebuffer_pixel(MENU_FRAME_RIGHT - 1U,
                                  MENU_TOP_BAR_Y + 4U) ==
                        color(239U, 226U, 217U) &&
                    framebuffer_pixel(MENU_FRAME_RIGHT,
                                      MENU_TOP_BAR_Y + 4U) ==
                        color(10U, 14U, 20U) &&
                    framebuffer_pixel(MENU_FRAME_X + 4U,
                                      MENU_TOP_BAR_Y + MENU_TOP_BAR_H) ==
                        color(10U, 14U, 20U),
                "top bar regained a right or bottom shadow");
    {
        u64 without_log = framebuffer_hash();
        selected_status = "THIS DIAGNOSTIC MUST NOT BE VISIBLE";
        draw_screen();
        ok &= check(framebuffer_hash() == without_log,
                    "diagnostic status text remained visible in the footer");
    }

    setup_full_render_golden();
    view = VIEW_SYSTEMS;
    selection = MENU_PAGE_ROWS - 1U;
    selected_status = "CATALOG READY FROM FIRMWARE";
    draw_screen();
    ok &= check(framebuffer_region_is_color(
                        MENU_ROW_LEFT,
                        MENU_CONTENT_Y +
                            (MENU_PAGE_ROWS - 1U) * MENU_ROW_SPACING,
                        MENU_TEXT_X - MENU_ROW_LEFT,
                        MENU_ROW_H, color(239U, 226U, 217U)) &&
                    framebuffer_pixel(
                        MENU_FRAME_RIGHT - 1U,
                        MENU_CONTENT_Y + MENU_CONTENT_H - 1U) ==
                        color(239U, 226U, 217U),
                "list selection gained an arrow or left a partial bottom row");

    view = VIEW_MAIN;
    ok &= check(strcmp(current_sidebar_label(), "HOME") == 0 &&
                    current_breadcrumb(breadcrumb, sizeof(breadcrumb)) == 0U &&
                    breadcrumb[0] == 0,
                "home chrome exposed top text or lost its HOME rail");
    view = VIEW_SYSTEMS;
    ok &= check(strcmp(current_sidebar_label(), "SYSTEMS") == 0 &&
                    current_breadcrumb(breadcrumb, sizeof(breadcrumb)) > 0U &&
                    strcmp(breadcrumb, "PLAY / SYSTEMS") == 0,
                "systems breadcrumb contract changed");
    for (index = 0U; index < CATALOG_SYSTEM_COUNT; index++) {
        if (strcmp(catalog_system_name(index), "PSP") == 0) {
            psp_system = index;
            break;
        }
    }
    view = VIEW_GAMES;
    active_system = psp_system < CATALOG_SYSTEM_COUNT ? psp_system : 0U;
    ok &= check(psp_system < CATALOG_SYSTEM_COUNT &&
                    strcmp(current_sidebar_label(), "PSP") == 0 &&
                    current_breadcrumb(breadcrumb, sizeof(breadcrumb)) > 0U &&
                    strcmp(breadcrumb, "PLAY / SYSTEMS / PSP") == 0,
                "PSP breadcrumb contract changed");

    /* These hashes pin the deliberate Phase 9 fixed-device visual contract
     * with the hardware-measured XRGB8888 unused byte stored as zero. Dirty-
     * versus-full tests separately protect renderer coherence. */
    setup_full_render_golden();
    view = VIEW_MAIN;
    selected_status = "DIRECT FRAMEBUFFER READY";
    ok &= check_full_render_golden(0xbcf899e7cf4ff2b0UL,
                                   "Phase 9 main-view pixels changed");

    setup_full_render_golden();
    view = VIEW_PLAY;
    selected_status = "PLAY SYSTEMS READY";
    ok &= check_full_render_golden(0x3e5e9e351bc7b6a4UL,
                                   "Phase 9 Play-view pixels changed");

    setup_full_render_golden();
    view = VIEW_SYSTEMS;
    selected_status = "CATALOG READY FROM FIRMWARE";
    ok &= check_full_render_golden(0x77a68baab14522ecUL,
                                   "Phase 9 Systems pixels changed");

    setup_full_render_golden();
    view = VIEW_SYSTEMS;
    selection = SYSTEM_ROWS;
    selected_status = "DIRECT EVDEV INPUT READY";
    ok &= check_full_render_golden(0xac6b7e9c33eca1ccUL,
                                   "Phase 9 fixed-page Systems pixels changed");

    setup_full_render_golden();
    view = VIEW_GAMES;
    set_favorite(0U, 1);
    favorites_loaded = 1;
    selected_status = "ROM STORAGE READY";
    ok &= check_full_render_golden(0xd8d89065aaf7510cUL,
                                   "Phase 9 Games pixels changed");

    setup_full_render_golden();
    view = VIEW_FAVORITES;
    selected_status = "FAVORITES LOAD WITH STORAGE";
    ok &= check_full_render_golden(0x03b04c6a82012764UL,
                                   "Phase 9 loading-Favorites pixels changed");

    setup_full_render_golden();
    view = VIEW_FAVORITES;
    set_favorite(0U, 1);
    set_favorite(1U, 1);
    favorites_loaded = 1;
    selected_status = "FAVORITES READY";
    ok &= check_full_render_golden(0x8e62f95496db9214UL,
                                   "Phase 9 Favorites pixels changed");

    setup_full_render_golden();
    view = VIEW_MEDIA_CATEGORIES;
    selected_status = "AUDIO CATALOG READY FROM FIRMWARE";
    ok &= check_full_render_golden(0x12f46bfb57abc0d0UL,
                                   "Phase 9 media-category pixels changed");

    setup_full_render_golden();
    view = VIEW_MEDIA_CATEGORIES;
    media_section = CATALOG_MEDIA_SECTION_READ;
    selected_status = "READING LIBRARY READY FROM FIRMWARE";
    ok &= check(CATALOG_READ_CATEGORY_COUNT == 1U &&
                    catalog_media_category_entry_count(
                        CATALOG_READ_CATEGORY_FIRST) == 5U &&
                    catalog_media_category_launch_kind(
                        CATALOG_READ_CATEGORY_FIRST) ==
                        CATALOG_LAUNCH_KOREADER,
                "embedded Read catalog did not retain five KOReader entries");
    ok &= check_full_render_golden(0x6205f58fc79c6aa8UL,
                                   "Phase 9 Read-category pixels changed");

    setup_full_render_golden();
    view = VIEW_MEDIA_ENTRIES;
    selected_status = "MEDIA STORAGE READY";
    ok &= check_full_render_golden(0x818450a9f22b57f4UL,
                                   "Phase 9 media-entry pixels changed");

    setup_full_render_golden();
    view = VIEW_MAIN;
    battery_percent = 100;
    charging_state = 1;
    selected_status = "DIRECT FRAMEBUFFER READY";
    ok &= check_full_render_golden(0xb0a6c209ea86fa10UL,
                                   "Phase 9 charging pixels changed");

    return ok;
}

static int run_selected_text_scroll_tests(void) {
    const char *long_name;
    u64 cycle_end;
    int ok = 1;

    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    fake_now_ms = 1000;
    draw_screen();
    ok &= check(!selected_text_scroll.deadline_ms &&
                    selected_text_scroll_poll_timeout((u64)-1) == (u64)-1,
                "short selection introduced an idle wakeup");

    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    reset_selected_text_scroll();
    long_name = current_selected_text();
    ok &= check(long_name && string_length(long_name) > MENU_LIST_TEXT_LIMIT,
                "scroll fixture no longer overflows the selected row");
    draw_screen();
    ok &= check(selected_text_scroll.offset == 0U &&
                    selected_text_scroll.deadline_ms == 3500U &&
                    selected_text_scroll_poll_timeout((u64)-1) == 2500U,
                "overflow selection did not arm the 2.5-second delay");
    fake_now_ms = 3499;
    ok &= check(!service_selected_text_scroll() &&
                    selected_text_scroll.offset == 0U,
                "selected text scrolled before its initial delay");
    fake_now_ms = 3500;
    ok &= check(service_selected_text_scroll() &&
                    selected_text_scroll.offset == 1U &&
                    selected_text_scroll.deadline_ms == 3650U,
                "selected text did not advance at its deadline");

    cycle_end = selected_text_scroll.length + MENU_SCROLL_GAP - 1U;
    selected_text_scroll.offset = (u32)cycle_end;
    selected_text_scroll.deadline_ms = 4000U;
    fake_now_ms = 4000;
    ok &= check(service_selected_text_scroll() &&
                    selected_text_scroll.offset == 0U &&
                    selected_text_scroll.deadline_ms == 6500U,
                "wrapped text did not pause for 2.5 seconds at its origin");

    selection = 1U;
    reset_selected_text_scroll();
    draw_selection_update(0U, 0U);
    ok &= check(selected_text_scroll.offset == 0U,
                "leaving a selected row retained its scroll offset");
    return ok;
}

static int dirty_framebuffer_matches_full(u32 pages, const char *message) {
    u64 bytes = (u64)RG34XX_FB_BYTES * pages;
    u64 offset;
    setup_test_framebuffer(pages, fake_framebuffer_reference);
    memset(fake_framebuffer_reference, 0xa5, (size_t)bytes);
    draw_screen();
    if (memcmp(fake_framebuffer, fake_framebuffer_reference,
               (size_t)bytes) != 0) {
        for (offset = 0; offset < bytes; offset++) {
            if (fake_framebuffer[offset] != fake_framebuffer_reference[offset]) {
                fprintf(stderr,
                        "%s: first_difference=%llu x=%llu y=%llu "
                        "dirty=0x%02x full=0x%02x\n",
                        message, (unsigned long long)offset,
                        (unsigned long long)((offset % RG34XX_FB_STRIDE) / 4U),
                        (unsigned long long)(offset / RG34XX_FB_STRIDE),
                        fake_framebuffer[offset],
                        fake_framebuffer_reference[offset]);
                break;
            }
        }
        return check(0, message);
    }
    return 1;
}

static int run_dirty_region_render_tests(void) {
    u8 published_favorites[(CATALOG_ENTRY_COUNT + 7U) / 8U];
    u32 old_first;
    u32 old_selection;
    int action;
    int ok = 1;

    ok &= check(viewport_first(VIEW_SYSTEMS, SYSTEM_ROWS - 1U) == 0U &&
                    viewport_first(VIEW_SYSTEMS, SYSTEM_ROWS) == SYSTEM_ROWS &&
                    viewport_first(VIEW_SYSTEMS, SYSTEM_ROWS + 1U) == SYSTEM_ROWS &&
                    viewport_first(VIEW_SYSTEMS, SYSTEM_ROWS * 2U) ==
                        SYSTEM_ROWS * 2U &&
                    viewport_first(VIEW_GAMES, GAME_ROWS + 3U) == GAME_ROWS &&
                    viewport_first(VIEW_FAVORITES, GAME_ROWS * 2U + 1U) ==
                        GAME_ROWS * 2U &&
                    viewport_first(VIEW_MEDIA_CATEGORIES, SYSTEM_ROWS + 2U) ==
                        SYSTEM_ROWS &&
                    viewport_first(VIEW_MEDIA_ENTRIES, GAME_ROWS + 2U) ==
                        GAME_ROWS &&
                    viewport_first(VIEW_MAIN, 3U) == 0U,
                "fixed-page viewport boundaries changed");

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
    selected_status = "PLAY SYSTEMS READY";
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

    /* Movement within a later fixed page remains a two-row dirty update. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    view = VIEW_SYSTEMS;
    selection = SYSTEM_ROWS;
    selected_status = "CATALOG READY FROM FIRMWARE";
    draw_screen();
    old_selection = selection;
    old_first = viewport_first(view, selection);
    selection = SYSTEM_ROWS + 1U;
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_selection_update(old_selection, old_first);
    ok &= dirty_framebuffer_matches_full(
        1U, "second-page dirty movement differs from a full render");

    /* Crossing row seven changes to the next fixed page and repaints the
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
    clear_favorites();
    favorites_loaded = 1;
    storage_ready = 1;
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "ROM STORAGE READY";
    draw_screen();
    reset_fake_file(FAKE_FD, 0, 0);
    fake_write_result = -EIO_LINUX;
    toggle_current_favorite();
    ok &= check(!is_favorite(0U) && favorite_count == 0U &&
                    favorite_catalog_index(0U) == CATALOG_ENTRY_COUNT &&
                    selection == 0U,
                "failed favorite add did not restore its indexed state");
    ok &= dirty_framebuffer_matches_full(
        1U, "failed favorite add rollback differs from a full render");

    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    set_favorite(0U, 1);
    set_favorite(1U, 1);
    favorites_loaded = 1;
    storage_ready = 1;
    view = VIEW_FAVORITES;
    selection = 0U;
    selected_status = "FAVORITES READY";
    draw_screen();
    reset_fake_file(FAKE_FD, 0, 0);
    fake_rename_result = -EIO_LINUX;
    toggle_current_favorite();
    ok &= check(is_favorite(0U) && is_favorite(1U) &&
                    favorite_count == 2U &&
                    favorite_catalog_index(0U) == 0U &&
                    favorite_catalog_index(1U) == 1U && selection == 0U,
                "failed favorite removal did not restore its indexed state");
    ok &= dirty_framebuffer_matches_full(
        1U, "failed favorite removal rollback differs from a full render");

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

    /* A marquee tick redraws the selected row exactly once and must still
     * produce the same pixels as the full-render recovery path. */
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    selected_status = "ROM STORAGE READY";
    reset_selected_text_scroll();
    fake_now_ms = 1000;
    draw_screen();
    fake_now_ms = 3500;
    ok &= check(service_selected_text_scroll(),
                "marquee dirty-render fixture did not advance");
    ok &= dirty_framebuffer_matches_full(
        1U, "marquee dirty render differs from a full render");

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

static void setup_navigation_test(struct navigation_batch *batch, u32 test_view) {
    setup_test_framebuffer(1U, fake_framebuffer);
    memset(fake_framebuffer, 0x5a, RG34XX_FB_BYTES);
    clear_favorites();
    favorites_loaded = 1;
    favorite_count = 0U;
    view = test_view;
    selection = 0U;
    active_system = 0U;
    active_media_category = 0U;
    media_section = CATALOG_MEDIA_SECTION_LISTEN;
    selected_status = test_view == VIEW_SYSTEMS
                          ? "CATALOG READY FROM FIRMWARE"
                          : (test_view == VIEW_GAMES
                                 ? "ROM STORAGE READY"
                                 : "DIRECT FRAMEBUFFER READY");
    battery_percent = -1;
    charging_state = -1;
    pending_launch.kind = PENDING_LAUNCH_NONE;
    pending_render_invalid = 0U;
    h700_input = 1;
    reset_input_latches();
    runtime_dir_fd = FAKE_FD;
    storage_dir_fd = FAKE_FD;
    config_dir_fd = FAKE_FD;
    reset_navigation_batch(batch);
    draw_screen();
    reset_fake_file(FAKE_FD, 0, 0);
}

static int run_navigation_batch_tests(void) {
    struct navigation_batch batch;
    struct input_event event;
    struct ui_resume_state resume;
    u64 before_hash;
    u32 index;
    int action;
    int ok = 1;

    event.sec = 0;
    event.usec = 0;
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;

    /* A drained burst mutates the final in-memory selection without touching
     * pixels or the filesystem, then publishes one dirty render and one
     * atomic resume replacement at the batch boundary. */
    setup_navigation_test(&batch, VIEW_MAIN);
    before_hash = framebuffer_hash();
    for (index = 0; index < 3U; index++)
        action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && selection == 3U && batch.active &&
                    batch.event_count == 3U &&
                    framebuffer_hash() == before_hash &&
                    fake_create_calls == 0U && fake_rename_calls == 0U,
                "navigation burst performed work before its batch boundary");
    finish_navigation_batch(&batch);
    ok &= check(!batch.active && selection == 3U &&
                    fake_create_calls == 1U && fake_rename_calls == 1U &&
                    fake_open_path_count == 1U &&
                    strcmp(fake_open_path[0],
                           "bird-launcher-ui-resume.tmp") == 0 &&
                    strcmp(fake_rename_old_path,
                           "bird-launcher-ui-resume.tmp") == 0 &&
                    strcmp(fake_rename_new_path,
                           "bird-launcher-ui-resume") == 0,
                "navigation batch did not atomically commit one resume state");
    ok &= dirty_framebuffer_matches_full(
        1U, "batched navigation pixels differ from a full render");

    /* Vendor ABS press/release and SYN records remain one batch. Neutral
     * latch traffic must neither flush early nor duplicate the movement. */
    setup_navigation_test(&batch, VIEW_MAIN);
    h700_input = 0;
    event.type = EV_ABS;
    event.code = ABS_HAT0Y;
    event.value = 1;
    (void)handle_batched_input_event(&batch, &event);
    event.type = 0U;
    event.code = 0U;
    event.value = 0;
    (void)handle_batched_input_event(&batch, &event);
    event.type = EV_ABS;
    event.code = ABS_HAT0Y;
    event.value = 0;
    (void)handle_batched_input_event(&batch, &event);
    ok &= check(batch.active && batch.event_count == 1U && selection == 1U &&
                    axis_y == 0 && fake_create_calls == 0U,
                "vendor ABS/SYN traffic split or duplicated navigation");
    finish_navigation_batch(&batch);
    ok &= check(fake_create_calls == 1U && fake_rename_calls == 1U,
                "vendor ABS batch did not publish exactly once");

    /* Both production controller maps retain their existing page and action
     * buttons; Phase 4 changes event ordering only. */
    setup_navigation_test(&batch, VIEW_SYSTEMS);
    h700_input = 0;
    event.type = EV_KEY;
    event.code = MUOS_BTN_TR;
    event.value = 1;
    (void)handle_batched_input_event(&batch, &event);
    finish_navigation_batch(&batch);
    ok &= check(selection == SYSTEM_ROWS,
                "vendor page-down mapping changed during batching");
    event.code = BTN_SOUTH;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && view == VIEW_GAMES &&
                    active_system == SYSTEM_ROWS,
                "vendor select mapping changed during batching");
    event.code = BTN_EAST;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && view == VIEW_SYSTEMS,
                "vendor back mapping changed during batching");
    setup_navigation_test(&batch, VIEW_GAMES);
    h700_input = 0;
    storage_ready = 1;
    event.code = BUTTON_Y;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && is_favorite(0U),
                "vendor favorite mapping changed during batching");

    /* The explicit cap prevents a permanently busy evdev source from keeping
     * an arbitrarily large unpublished recovery window. */
    setup_navigation_test(&batch, VIEW_MAIN);
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;
    for (index = 0; index < NAVIGATION_BATCH_MAX_EVENTS + 1U; index++)
        (void)handle_batched_input_event(&batch, &event);
    ok &= check(batch.active && batch.event_count == 1U &&
                    fake_create_calls == 1U && fake_rename_calls == 1U,
                "navigation batch cap did not publish the first bounded batch");
    finish_navigation_batch(&batch);
    ok &= check(!batch.active && fake_create_calls == 2U &&
                    fake_rename_calls == 2U,
                "navigation tail was not committed after the bounded batch");

    setup_navigation_test(&batch, VIEW_MAIN);
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;
    (void)handle_batched_input_event(&batch, &event);
    event.type = 0U;
    event.code = 0U;
    event.value = 0;
    for (index = 1U; index < NAVIGATION_BATCH_MAX_RECORDS; index++)
        (void)handle_batched_input_event(&batch, &event);
    ok &= check(!batch.active && fake_create_calls == 1U &&
                    fake_rename_calls == 1U,
                "non-navigation records bypassed the unpublished-batch cap");

    setup_navigation_test(&batch, VIEW_FAVORITES);
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && !batch.active && selection == 0U &&
                    fake_create_calls == 0U && fake_rename_calls == 0U,
                "empty view created a phantom navigation batch");

    /* A is an ordering boundary: it flushes navigation first and enters the
     * system selected by the final event in that burst. */
    setup_navigation_test(&batch, VIEW_SYSTEMS);
    (void)handle_batched_input_event(&batch, &event);
    (void)handle_batched_input_event(&batch, &event);
    event.code = BTN_EAST;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && !batch.active &&
                    active_system == 2U && view == VIEW_GAMES && selection == 0U &&
                    fake_create_calls == 2U && fake_rename_calls == 2U,
                "selection action did not observe the final batched navigation state");

    /* Y is also ordered after the burst and therefore changes only the final
     * selected game. The physical button mapping itself is unchanged. */
    setup_navigation_test(&batch, VIEW_GAMES);
    storage_ready = 1;
    event.code = BTN_DPAD_DOWN;
    (void)handle_batched_input_event(&batch, &event);
    event.code = BTN_NORTH;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && !batch.active && selection == 1U &&
                    !is_favorite(0U) && is_favorite(1U),
                "favorite action did not use the final batched selection");

    /* Pending content remains cancellable throughout the in-memory batch and
     * is retired immediately after the visible movement barrier. */
    setup_navigation_test(&batch, VIEW_GAMES);
    pending_launch.kind = PENDING_LAUNCH_GAME;
    pending_launch.index = 0U;
    event.code = BTN_DPAD_DOWN;
    (void)handle_batched_input_event(&batch, &event);
    ok &= check(pending_launch.kind == PENDING_LAUNCH_GAME && batch.active,
                "pending launch was cancelled before the visible batch commit");
    finish_navigation_batch(&batch);
    ok &= check(pending_launch.kind == PENDING_LAUNCH_NONE && !batch.active,
                "visible navigation did not cancel the pending launch");

    /* B flushes the older movement before changing views, so no uncommitted
     * selection survives across the back-navigation ordering boundary. */
    setup_navigation_test(&batch, VIEW_GAMES);
    pending_launch.kind = PENDING_LAUNCH_GAME;
    pending_launch.index = 0U;
    event.code = BTN_DPAD_DOWN;
    (void)handle_batched_input_event(&batch, &event);
    event.code = BTN_SOUTH;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && !batch.active &&
                    pending_launch.kind == PENDING_LAUNCH_NONE &&
                    view == VIEW_SYSTEMS && selection == active_system,
                "back action crossed an uncommitted navigation batch");

    /* A direct content action may follow a navigation batch, but it can exit
     * only after the final selection's request and resume state both commit. */
    setup_navigation_test(&batch, VIEW_GAMES);
    storage_ready = 1;
    event.code = BTN_DPAD_DOWN;
    (void)handle_batched_input_event(&batch, &event);
    event.code = BTN_EAST;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_LAUNCH && !batch.active && selection == 1U &&
                    fake_rename_calls == 3U,
                "content handoff did not commit the final batched selection");

    setup_navigation_test(&batch, VIEW_GAMES);
    storage_ready = 1;
    fake_rename_result = -EIO_LINUX;
    event.code = BTN_EAST;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE &&
                    pending_launch.kind == PENDING_LAUNCH_NONE &&
                    fake_rename_calls >= 1U && fake_unlink_calls >= 2U &&
                    fake_unlinked_launch_request,
                "launcher exit survived a failed authoritative resume handoff");

    /* UI-resume publication never truncates the last committed descriptor.
     * A failed atomic replace removes only its temporary candidate. */
    setup_navigation_test(&batch, VIEW_MAIN);
    reset_fake_file(FAKE_FD, 0, 0);
    fake_write_result = -EIO_LINUX;
    ok &= check(save_ui_resume() < 0 && fake_rename_calls == 0U &&
                    fake_unlink_calls == 1U &&
                    strcmp(fake_unlink_path,
                           "bird-launcher-ui-resume.tmp") == 0,
                "failed resume write damaged the committed descriptor");
    reset_fake_file(FAKE_FD, 0, 0);
    fake_rename_result = -EIO_LINUX;
    ok &= check(save_ui_resume() < 0 && fake_rename_calls == 1U &&
                    fake_unlink_calls == 1U &&
                    strcmp(fake_unlink_path,
                           "bird-launcher-ui-resume.tmp") == 0,
                "failed resume replacement damaged more than its temporary file");

    reset_fake_file(FAKE_FD, 0, 0);
    ok &= check(write_handoff_action(ACTION_LAUNCH) == 0 &&
                    fake_create_calls == 1U && fake_rename_calls == 1U &&
                    strcmp(fake_open_path[0], "bird-launch-action.tmp") == 0 &&
                    strcmp(fake_rename_new_path, "bird-launch-action") == 0,
                "early action was not atomically published before exit");
    reset_fake_file(FAKE_FD, 0, 0);
    fake_write_result = -EIO_LINUX;
    ok &= check(write_handoff_action(ACTION_LAUNCH) < 0 &&
                    fake_rename_calls == 0U && fake_unlink_calls == 1U &&
                    strcmp(fake_unlink_path, "bird-launch-action.tmp") == 0,
                "short/failed early action write was accepted");

    setup_navigation_test(&batch, VIEW_GAMES);
    reset_fake_file(FAKE_FD, 0, 0);
    fake_rename_result = -EIO_LINUX;
    ok &= check(publish_handoff_action(ACTION_LAUNCH) < 0 &&
                    fake_unlinked_launch_request && fake_unlink_calls == 4U &&
                    strcmp(selected_status, "HANDOFF PUBLICATION FAILED") == 0,
                "failed action did not clear both frame paths and launch request");

    /* A valid descriptor survives the read until application() atomically
     * refreshes it. Invalid bytes are also left untouched until that deferred
     * checkpoint, so startup never creates an unlink/write crash window. */
    setup_navigation_test(&batch, VIEW_MAIN);
    resume.magic = UI_RESUME_MAGIC;
    resume.view = VIEW_SYSTEMS;
    resume.active_index = 0U;
    resume.selection = SYSTEM_ROWS + 1U;
    reset_fake_file(FAKE_FD, 0, 0);
    fake_payload = (const char *)&resume;
    fake_payload_bytes = sizeof(resume);
    ok &= check(load_ui_resume() == 1 && view == VIEW_SYSTEMS &&
                    selection == SYSTEM_ROWS + 1U &&
                    viewport_first(view, selection) == SYSTEM_ROWS &&
                    fake_unlink_calls == 0U,
                "valid resume did not reconstruct its fixed page safely");
    resume.view = VIEW_MAIN;
    resume.selection = 6U;
    reset_fake_file(FAKE_FD, 0, 0);
    fake_payload = (const char *)&resume;
    fake_payload_bytes = sizeof(resume);
    ok &= check(load_ui_resume() == 0 && fake_unlink_calls == 0U,
                "invalid resume descriptor was mutated before the barrier");
    reset_fake_file(FAKE_FD, 0, 0);
    ok &= check(save_ui_resume() == 0 && fake_create_calls == 1U &&
                    fake_rename_calls == 1U && fake_unlink_calls == 0U,
                "deferred checkpoint did not replace invalid resume state");

    /* A cold Favorites resume reads only the UI descriptor. Storage parsing
     * and its diagnostics remain deferred until after the interactive frame. */
    setup_navigation_test(&batch, VIEW_MAIN);
    resume.magic = UI_RESUME_MAGIC;
    resume.view = VIEW_FAVORITES;
    resume.active_index = 0U;
    resume.selection = 3U;
    favorites_loaded = 0;
    reset_fake_file(FAKE_FD, 0, 0);
    fake_payload = (const char *)&resume;
    fake_payload_bytes = sizeof(resume);
#ifdef BIRD_PROFILE
    bird_profile_reset();
#endif
    ok &= check(load_ui_resume() == 1 && view == VIEW_FAVORITES &&
                    selection == 3U && fake_open_calls == 1U &&
                    !favorites_loaded,
                "Favorites resume performed storage initialization");
#ifdef BIRD_PROFILE
    ok &= check(bird_profile.pre_barrier_diagnostic_writes == 0U,
                "Favorites resume logged before the interactive barrier");
#endif

    return ok;
}

static int run_user_reload_handoff_tests(void) {
    struct navigation_batch batch;
#ifdef BIRD_PROFILE
    const struct bird_profile_render_totals *render;
#endif
    int action;
    int result;
    int ok = 1;

    /* Main-page B returns to PLAY with an ordinary dirty selection update.
     * It remains deliberately absent from the visible footer legend and
     * commits resume state only after the row barrier. */
    setup_navigation_test(&batch, VIEW_MAIN);
    selection = 2U;
    pending_launch.kind = PENDING_LAUNCH_GAME;
    pending_launch.index = 4U;

    /* Build the authoritative selection-zero content independently. Pixels
     * outside the two dirty rows remain untouched: Home B is no longer a
     * hidden full-screen recovery command. */
    selected_status = "DIRECT EVDEV INPUT READY";
    setup_test_framebuffer(1U, fake_framebuffer_reference);
    memset(fake_framebuffer_reference, 0xa5, RG34XX_FB_BYTES);
    selection = 0U;
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    setup_test_framebuffer(1U, fake_framebuffer);
    selection = 2U;
    selected_status = "DIRECT FRAMEBUFFER READY";
    memset(fake_framebuffer, 0xa5, RG34XX_FB_BYTES);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    memset(fake_framebuffer + 10U * RG34XX_FB_STRIDE + 10U * 4U,
           0xde, 4U);
    memset(fake_framebuffer + 200U * RG34XX_FB_STRIDE + 10U * 4U,
           0xad, 4U);
    memset(fake_framebuffer + 470U * RG34XX_FB_STRIDE + 700U * 4U,
           0xbe, 4U);
    reset_fake_file(FAKE_FD, 0, 0);
#ifdef BIRD_PROFILE
    bird_profile_reset();
    fake_now_ms = 2863;
    BIRD_PROFILE_BEGIN_EVENT();
#endif
    action = handle_back();
#ifdef BIRD_PROFILE
    BIRD_PROFILE_FINISH_EVENT();
    render = &bird_profile.render[PROFILE_RENDER_SELECTION_MOVEMENT];
#endif
    ok &= check(action == ACTION_NONE && view == VIEW_MAIN &&
                    selection == 0U &&
                    pending_launch.kind == PENDING_LAUNCH_NONE &&
                    fake_create_calls == 1U && fake_rename_calls == 1U &&
                    strcmp(selected_status, "DIRECT EVDEV INPUT READY") == 0,
                "main-page B did not return to the top selection");
    ok &= check(framebuffer_regions_equal(
                        fake_framebuffer, fake_framebuffer_reference,
                        MENU_LEFT, MENU_CONTENT_Y,
                        MENU_CONTENT_WIDTH, MENU_CONTENT_H) &&
                    framebuffer_pixel(10U, 10U) == 0xdedededeU &&
                    framebuffer_pixel(10U, 200U) == 0xadadadadU &&
                    framebuffer_pixel(700U, 470U) == 0xbebebebeU,
                "main-page B repainted outside its dirty selection rows");
#ifdef BIRD_PROFILE
    ok &= check(render->commits == 1U && render->pages_written == 1U &&
                    bird_profile.render[PROFILE_RENDER_RECOVERY].commits ==
                        0U,
                "main-page B was not recorded as one selection render");
    ok &= check(bird_profile.input_to_barrier_samples == 1U &&
                    bird_profile.resume_before_barrier == 0U &&
                    bird_profile.barrier_to_resume_samples == 1U &&
                    bird_profile.event_pre_barrier_filesystem_ops == 0U &&
                    bird_profile.event_pre_barrier_diagnostic_writes == 0U,
                "main-page B persisted or logged before its row barrier");
    printf("launcher profile benchmark scenario=home-b-top "
           "renders=%lu logical_pixels=%lu visible_bytes=%lu pages=%lu "
           "physical_bytes=%lu syscalls=%lu\n",
           (unsigned long)render->commits,
           (unsigned long)render->logical_pixels,
           (unsigned long)render->visible_bytes,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes,
           (unsigned long)bird_profile.syscalls);
#endif
    ok &= check(!action_preserves_frame(action) &&
                    action_preserves_frame(ACTION_RELOAD) &&
                    action_preserves_frame(ACTION_LAUNCH) &&
                    action_preserves_frame(ACTION_PORTMASTER) &&
                    !action_preserves_frame(ACTION_SHUTDOWN) &&
                    !action_preserves_frame(ACTION_REBOOT),
                "legacy reload compatibility lost its framebuffer contract");

    /* Action 13 remains readable for release compatibility with an older
     * already-running launcher, but the current input path never emits it. */
    reset_fake_file(FAKE_FD, 0, 0);
    begin_fake_file_write_capture();
    result = write_handoff_action(ACTION_RELOAD);
    end_fake_file_write_capture();
    ok &= check(result == 0 && fake_write_capture_bytes == 3U &&
                    memcmp(fake_write_capture, "13\n", 3U) == 0 &&
                    fake_rename_calls == 1U,
                "reload handoff did not publish the canonical action");

    reset_fake_file(FAKE_FD, 0, 0);
    begin_fake_file_write_capture();
    result = write_handoff_action(ACTION_REBOOT);
    end_fake_file_write_capture();
    ok &= check(result == 0 && fake_write_capture_bytes == 3U &&
                    memcmp(fake_write_capture, "14\n", 3U) == 0 &&
                    fake_rename_calls == 1U,
                "reboot handoff did not publish the canonical action");

    /* Nested B remains ordinary navigation; no current input path emits the
     * legacy action 13 compatibility value. */
    setup_navigation_test(&batch, VIEW_GAMES);
    active_system = 3U;
    selection = 2U;
    reset_fake_file(FAKE_FD, 0, 0);
    action = handle_back();
    ok &= check(action == ACTION_NONE && view == VIEW_SYSTEMS &&
                    selection == 3U && fake_create_calls == 1U &&
                    fake_rename_calls == 1U,
                "nested B changed from navigation into user reload");

    return ok;
}

static int run_phase9_menu_hierarchy_tests(void) {
    struct navigation_batch batch;
    int action;
    int ok = 1;

    setup_navigation_test(&batch, VIEW_MAIN);
    ok &= check(current_count() == 6U &&
                    strcmp(menu_item[4], "TOOLS") == 0 &&
                    strcmp(menu_item[5], "QUIT") == 0,
                "home hierarchy did not expose Tools and Quit");

    selection = 0U;
    action = select_current();
    ok &= check(action == ACTION_NONE && view == VIEW_PLAY &&
                    current_count() == 2U &&
                    strcmp(play_item[0], "SYSTEMS") == 0 &&
                    strcmp(play_item[1], "FAVORITES") == 0,
                "Play retained PortMaster/Shutdown or lost Systems/Favorites");
    (void)handle_back();

    selection = 4U;
    action = select_current();
    ok &= check(action == ACTION_NONE && view == VIEW_TOOLS &&
                    current_count() == 1U &&
                    strcmp(tools_item[0], "PORTMASTER") == 0,
                "Tools did not own the single PortMaster entry");
    reset_fake_file(FAKE_FD, 0, 0);
    action = select_current();
    ok &= check(action == ACTION_PORTMASTER,
                "Tools PortMaster selection changed its handoff action");
    (void)handle_back();

    selection = 5U;
    action = select_current();
    ok &= check(action == ACTION_NONE && view == VIEW_QUIT &&
                    current_count() == 3U &&
                    strcmp(quit_item[0], "RELOAD") == 0 &&
                    strcmp(quit_item[1], "REBOOT") == 0 &&
                    strcmp(quit_item[2], "SHUTDOWN") == 0,
                "Quit hierarchy changed");
    selection = 0U;
    ok &= check(select_current() == ACTION_RELOAD,
                "Quit Reload action changed");
    selection = 1U;
    ok &= check(select_current() == ACTION_REBOOT,
                "Quit Reboot action changed");
    selection = 2U;
    ok &= check(select_current() == ACTION_SHUTDOWN,
                "Quit Shutdown action changed");
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
    struct navigation_batch batch;
    struct input_event event;
    u64 before_syscalls;
    u64 before_diagnostics;
    u64 prior_input_samples;
    u64 maximum_physical;
    u64 first_storage_report_bytes;
    u64 unbatched_physical;
    u64 unbatched_syscalls;
    long open_script[4];
    u32 old_first;
    u32 old_selection;
    unsigned clocks_after_first;
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

    /* Phase 5A may publish a noninteractive base, but the readiness barrier
     * cannot become interactive until input is open and menu rows are drawn. */
    setup_test_framebuffer(2U, fake_framebuffer);
    setup_main_view();
    bird_profile_application_entry((u64)fake_now_ms * 1000000UL);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_base();
    ok &= check(!bird_profile.interactive_barrier_seen,
                "noninteractive startup base published readiness");
    fake_now_ms++;
    bird_profile_input_opened();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_menu_overlay();
    bird_profile_first_frame_marked();
    before_syscalls = bird_profile.syscalls;
    before_diagnostics = bird_profile.diagnostic_writes;
    bird_profile_emit_startup();
    ok &= check(fake_profile_log_bytes > 0 && bird_profile.output_records >= 2,
                "profile output did not become available after the barrier");
    ok &= check(profile_log_contains(
                    "input_open_to_interactive_barrier_ns=") &&
                    !profile_log_contains(
                        "input_open_to_interactive_barrier_ns="
                        "unavailable:barrier-before-input"),
                "interactive startup barrier did not follow input open");
    ok &= check(profile_log_contains(
                    " frame_fingerprint_physical_bytes_read=0") &&
                    profile_log_contains(
                        " frame_fingerprint_visible_bytes_compared=0") &&
                    profile_log_contains(
                        " frame_fingerprint_pages_read=0"),
                "startup profile omitted retained-frame read accounting");
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
    ok &= check(render->commits == 2U &&
                    render->logical_pixels >=
                        RG34XX_FB_WIDTH * RG34XX_FB_HEIGHT &&
                    render->logical_pixels <= 500000U,
                "startup render reason or logical-pixel bounds are wrong");
    ok &= check(render->pages_written == 4U &&
                    render->visible_bytes <= render->physical_bytes &&
                    render->physical_bytes <= maximum_physical,
                "startup framebuffer page/byte metrics do not reconcile");

    /* Production uses one exact XRGB8888 page. The Phase 5A fallback renders
     * the honest base, then overlays only pixels made interactive by input. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_base();
    bird_profile_input_opened();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_menu_overlay();
    render = &bird_profile.render[PROFILE_RENDER_STARTUP_FULL];
    ok &= check(render->commits == 2U && render->pages_written == 2U &&
                    render->physical_bytes <=
                        STARTUP_FRAMEBUFFER_WRITE_BUDGET,
                "Phase 5A startup exceeded its framebuffer-write budget");
    printf("launcher profile benchmark scenario=phase5a-startup "
           "renders=%lu pages=%lu physical_bytes=%lu budget=%lu\n",
           (unsigned long)render->commits,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes,
           (unsigned long)STARTUP_FRAMEBUFFER_WRITE_BUDGET);

    /* Once the manifest and hardware gates admit the inherited base, startup
     * writes only the newly interactive menu pixels after input is open. */
    bird_profile_reset();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_startup_menu_overlay();
    render = &bird_profile.render[PROFILE_RENDER_STARTUP_FULL];
    ok &= check(render->commits == 1U && render->pages_written == 1U &&
                    render->physical_bytes <=
                        INHERITED_BOOT_FRAME_WRITE_BUDGET,
                "Phase 5B inherited overlay exceeded its write budget");
    printf("launcher profile benchmark scenario=phase5b-inherited-overlay "
           "renders=%lu pages=%lu physical_bytes=%lu budget=%lu\n",
           (unsigned long)render->commits,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes,
           (unsigned long)INHERITED_BOOT_FRAME_WRITE_BUDGET);

    selected_status = "RETURNED TO PREVIOUS SCREEN";
    bird_profile_reset();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_RECOVERY);
    draw_recovery_update();
    render = &bird_profile.render[PROFILE_RENDER_RECOVERY];
    ok &= check(render->commits == 1U && render->pages_written == 0U &&
                    render->physical_bytes == 0U &&
                    render->physical_bytes <=
                        RECOVERY_FRAMEBUFFER_WRITE_BUDGET,
                "retained recovery exceeded its framebuffer-write budget");
    printf("launcher profile benchmark scenario=phase5-recovery "
           "renders=%lu pages=%lu physical_bytes=%lu budget=%lu\n",
           (unsigned long)render->commits,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes,
           (unsigned long)RECOVERY_FRAMEBUFFER_WRITE_BUDGET);

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

    /* A D-pad response publishes pixels first. The atomic resume replacement
     * and ordinary diagnostics must be entirely after its render barrier. */
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
                    bird_profile.event_pre_barrier_filesystem_ops == 0U &&
                    bird_profile.event_pre_barrier_diagnostic_writes == 0U &&
                    bird_profile.event_pre_barrier_diagnostic_bytes == 0U,
                "movement performed filesystem or diagnostic work before pixels");
    ok &= check(bird_profile.resume_before_barrier == 0U &&
                    bird_profile.barrier_to_resume_samples == 1U &&
                    bird_profile.navigation_events == 1U &&
                    bird_profile.navigation_batches == 1U,
                "post-barrier movement persistence or batch metrics are wrong");
    ok &= check(bird_profile.syscalls < 64U &&
                    profile_syscall_category_sum() == bird_profile.syscalls,
                "movement syscall categories or upper bound are wrong");
    ok &= check(
        bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_OPENAT] == 0U &&
            bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_CLOSE] == 0U &&
            bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_WRITE] == 0U &&
            bird_profile.event_pre_barrier_syscall_kind[PROFILE_SYSCALL_RENAMEAT] == 0U,
        "movement issued a persistence syscall before the framebuffer barrier");
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
           "navigation_events=%lu navigation_batches=%lu "
           "filesystem_namespace_before_barrier=%lu "
           "file_writes_before_barrier=%lu closes_before_barrier=%lu "
           "diagnostics_before_barrier=%lu "
           "logical_pixels=%lu visible_bytes=%lu pages=%lu physical_bytes=%lu\n",
           (unsigned long)bird_profile.syscalls,
           (unsigned long)bird_profile.navigation_events,
           (unsigned long)bird_profile.navigation_batches,
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

    /* Keep an unbatched semantic reference as benchmark output, not a brittle
     * exact-count contract. It establishes the work eliminated by coalescing. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    runtime_dir_fd = FAKE_FD;
    h700_input = 1;
    reset_fake_file(FAKE_FD, 0, 0);
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;
    BIRD_PROFILE_BEGIN_EVENT();
    (void)handle_event(&event);
    BIRD_PROFILE_FINISH_EVENT();
    BIRD_PROFILE_BEGIN_EVENT();
    (void)handle_event(&event);
    BIRD_PROFILE_FINISH_EVENT();
    BIRD_PROFILE_BEGIN_EVENT();
    (void)handle_event(&event);
    BIRD_PROFILE_FINISH_EVENT();
    render = &bird_profile.render[PROFILE_RENDER_SELECTION_MOVEMENT];
    unbatched_physical = render->physical_bytes;
    unbatched_syscalls = bird_profile.syscalls;
    ok &= check(selection == 3U && render->commits == 3U &&
                    bird_profile.navigation_events == 3U &&
                    bird_profile.navigation_batches == 3U &&
                    bird_profile.barrier_to_resume_samples == 3U,
                "unbatched navigation reference lost its semantic commits");
    printf("launcher profile benchmark scenario=movement-unbatched "
           "events=%lu batches=%lu renders=%lu resume_commits=%lu syscalls=%lu "
           "physical_bytes=%lu\n",
           (unsigned long)bird_profile.navigation_events,
           (unsigned long)bird_profile.navigation_batches,
           (unsigned long)render->commits,
           (unsigned long)bird_profile.barrier_to_resume_samples,
           (unsigned long)unbatched_syscalls,
           (unsigned long)unbatched_physical);

    /* Three already-buffered D-pad edges publish one response and one resume
     * transaction, with no filesystem or diagnostics ahead of the pixels. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    runtime_dir_fd = FAKE_FD;
    h700_input = 1;
    reset_navigation_batch(&batch);
    reset_fake_file(FAKE_FD, 0, 0);
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;
    (void)handle_batched_input_event(&batch, &event);
    clocks_after_first = fake_clock_calls;
    (void)handle_batched_input_event(&batch, &event);
    (void)handle_batched_input_event(&batch, &event);
    ok &= check(fake_clock_calls == clocks_after_first,
                "coalesced navigation sampled redundant profile clocks");
    finish_navigation_batch(&batch);
    render = &bird_profile.render[PROFILE_RENDER_SELECTION_MOVEMENT];
    ok &= check(selection == 3U && render->commits == 1U &&
                    bird_profile.navigation_events == 3U &&
                    bird_profile.navigation_batches == 1U &&
                    bird_profile.input_to_barrier_samples == 1U &&
                    bird_profile.barrier_to_resume_samples == 1U &&
                    bird_profile.resume_before_barrier == 0U &&
                    bird_profile.event_pre_barrier_filesystem_ops == 0U &&
                    bird_profile.event_pre_barrier_diagnostic_writes == 0U &&
                    bird_profile.syscalls < 20U &&
                    render->physical_bytes < 400000U &&
                    bird_profile.syscalls < unbatched_syscalls &&
                    render->physical_bytes < unbatched_physical &&
                    fake_create_calls == 1U && fake_rename_calls == 1U,
                "batched movement did not produce one post-barrier transaction");
    printf("launcher profile benchmark scenario=movement-batch "
           "events=%lu batches=%lu renders=%lu resume_commits=%lu syscalls=%lu "
           "filesystem_namespace_before_barrier=%lu "
           "diagnostics_before_barrier=%lu physical_bytes=%lu\n",
           (unsigned long)bird_profile.navigation_events,
           (unsigned long)bird_profile.navigation_batches,
           (unsigned long)render->commits,
           (unsigned long)bird_profile.barrier_to_resume_samples,
           (unsigned long)bird_profile.syscalls,
           (unsigned long)bird_profile.event_pre_barrier_filesystem_ops,
           (unsigned long)bird_profile.event_pre_barrier_diagnostic_writes,
           (unsigned long)render->physical_bytes);
    reset_profile_log();
    bird_profile.interactive_barrier_seen = 1;
    bird_profile_note_exit_and_emit();
    ok &= check(profile_log_contains(
                    "navigation_events=3 navigation_batches=1"),
                "exit profile omitted navigation batch aggregates");

    /* A following action is timestamped and baselined when it is read, before
     * the older navigation batch is flushed. Its interval and syscall scope
     * must describe the same real span. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    clear_favorites();
    favorites_loaded = 1;
    view = VIEW_SYSTEMS;
    selection = 0U;
    selected_status = "CATALOG READY FROM FIRMWARE";
    runtime_dir_fd = FAKE_FD;
    h700_input = 1;
    reset_navigation_batch(&batch);
    reset_fake_file(FAKE_FD, 0, 0);
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;
    (void)handle_batched_input_event(&batch, &event);
    event.code = BTN_EAST;
    action = handle_batched_input_event(&batch, &event);
    ok &= check(action == ACTION_NONE && !batch.active &&
                    view == VIEW_GAMES && active_system == 1U &&
                    bird_profile.input_to_barrier_samples == 2U &&
                    bird_profile.barrier_to_resume_samples == 2U &&
                    bird_profile.resume_before_barrier == 0U &&
                    bird_profile.event_pre_barrier_filesystem_ops > 0U &&
                    bird_profile.event_pre_barrier_diagnostic_writes > 0U,
                "mixed navigation/action profile used mismatched interval baselines");

    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    clear_favorites();
    favorites_loaded = 1;
    view = VIEW_FAVORITES;
    selection = 0U;
    h700_input = 1;
    reset_navigation_batch(&batch);
    event.type = EV_KEY;
    event.code = BTN_DPAD_DOWN;
    event.value = 1;
    (void)handle_batched_input_event(&batch, &event);
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STATUS);
    rectangle(0, 0, 1, 1, 0U);
    BIRD_PROFILE_BARRIER();
    ok &= check(!batch.active && !bird_profile.event_active &&
                    bird_profile.input_to_barrier_samples == 0U &&
                    bird_profile.navigation_events == 0U &&
                    bird_profile.navigation_batches == 0U,
                "empty view left a profile event active for a later barrier");

    /* Record the current cost of moving within the second logical page. The
     * Phase 3B fixed-page assertion is applied after the production policy is
     * changed, so this same scenario gives a directly comparable baseline. */
    bird_profile_reset();
    setup_test_framebuffer(1U, fake_framebuffer);
    view = VIEW_SYSTEMS;
    selection = SYSTEM_ROWS;
    selected_status = "CATALOG READY FROM FIRMWARE";
    reset_fake_file(FAKE_FD, 0, 0);
    BIRD_PROFILE_BEGIN_EVENT();
    move_selection(1, 1U);
    BIRD_PROFILE_FINISH_EVENT();
    ok &= check(selection == SYSTEM_ROWS + 1U,
                "second-page benchmark changed selection semantics");
    ok &= check(
        bird_profile.render[PROFILE_RENDER_SELECTION_MOVEMENT].commits == 1U &&
            bird_profile.render[PROFILE_RENDER_SELECTION_MOVEMENT]
                    .physical_bytes < 400000U &&
            bird_profile.render[PROFILE_RENDER_VIEWPORT_CHANGE].commits == 0U,
        "fixed second page did not retain the dirty selection path");
    printf("launcher profile benchmark scenario=second-page-movement "
           "selection_commits=%lu selection_physical_bytes=%lu "
           "viewport_commits=%lu viewport_physical_bytes=%lu\n",
           (unsigned long)bird_profile
               .render[PROFILE_RENDER_SELECTION_MOVEMENT].commits,
           (unsigned long)bird_profile
               .render[PROFILE_RENDER_SELECTION_MOVEMENT].physical_bytes,
           (unsigned long)bird_profile
               .render[PROFILE_RENDER_VIEWPORT_CHANGE].commits,
           (unsigned long)bird_profile
               .render[PROFILE_RENDER_VIEWPORT_CHANGE].physical_bytes);

    /* Crossing row seven changes the current viewport. */
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
                "fixed-page boundary was not classified as viewport change");
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
    view = VIEW_QUIT;
    selection = 0U;
    selected_status = "QUIT OPTIONS READY";
    action = select_current();
    render = &bird_profile.render[PROFILE_RENDER_STATUS];
    ok &= check(action == ACTION_RELOAD && render->commits == 1U &&
                    render->logical_pixels == 0U &&
                    render->visible_bytes == 0U &&
                    render->physical_bytes == 0U &&
                    render->pages_written == 0U,
                "same-view A selection performed framebuffer traffic");
    printf("launcher profile benchmark scenario=same-view-select "
           "logical_pixels=%lu visible_bytes=%lu pages=%lu physical_bytes=%lu\n",
           (unsigned long)render->logical_pixels,
           (unsigned long)render->visible_bytes,
           (unsigned long)render->pages_written,
           (unsigned long)render->physical_bytes);

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

    setup_test_framebuffer(1U, fake_framebuffer);
    setup_main_view();
    view = VIEW_GAMES;
    active_system = 0U;
    selection = 0U;
    fake_now_ms = 1000;
    draw_screen();
    bird_profile_reset();
    fake_now_ms = 3500;
    BIRD_PROFILE_BEGIN_EVENT();
    ok &= check(service_selected_text_scroll(),
                "overflow scroll deadline produced no render");
    BIRD_PROFILE_FINISH_EVENT();
    render = &bird_profile.render[PROFILE_RENDER_TEXT_SCROLL];
    ok &= check(render->commits == 1U && render->pages_written == 1U &&
                    render->physical_bytes < 60000U &&
                    bird_profile.event_pre_barrier_filesystem_ops == 0U &&
                    bird_profile.event_pre_barrier_diagnostic_writes == 0U,
                "text scroll exceeded its row-only render contract");
    printf("launcher profile benchmark scenario=text-scroll "
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
    load_favorites_and_update_view();
    ok &= check(
        bird_profile.render[PROFILE_RENDER_STATUS].commits == 0U &&
            bird_profile.render[PROFILE_RENDER_FAVORITES_COMPLETION].commits == 0U,
        "deferred Favorites retry rendered before publication");

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
    load_favorites_and_update_view();
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
    ok &= check(
        bird_profile.render[PROFILE_RENDER_STATUS].commits == 1U &&
            bird_profile.render[PROFILE_RENDER_STATUS].physical_bytes == 0U,
        "direct launch performed a same-view framebuffer rewrite");
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
    ok &= check(
        bird_profile.render[PROFILE_RENDER_STATUS].commits == 1U &&
            bird_profile.render[PROFILE_RENDER_STATUS].physical_bytes == 0U,
        "queued selection performed a same-view framebuffer rewrite");
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
    {
        char favorites_file[1024];
        const char *first_path = catalog_entry_path(0U);
        const char *middle_path =
            catalog_entry_path(CATALOG_ENTRY_COUNT / 2U);
        const char *last_path = catalog_entry_path(CATALOG_ENTRY_COUNT - 1U);
        u64 lookup_iterations;
        u64 load_iterations;
        u64 save_iterations;
        u64 load_string_bytes;
        u32 lookup_bound = 1U;
        u32 span = CATALOG_ENTRY_COUNT;
        int file_bytes;

        while (span > 1U) {
            span = (span + 1U) / 2U;
            lookup_bound++;
        }

        bird_profile_reset();
        ok &= check(catalog_find_entry_by_path(
                        last_path, (u32)strlen(last_path)) ==
                        CATALOG_ENTRY_COUNT - 1U,
                    "binary catalog path lookup missed an exact path");
        lookup_iterations = bird_profile_deep.catalog_iterations;
        ok &= check(lookup_iterations > 0U &&
                        lookup_iterations <= lookup_bound,
                    "binary catalog path lookup exceeded its logarithmic bound");

        clear_favorites();
        set_favorite(CATALOG_ENTRY_COUNT - 1U, 1);
        set_favorite(10U, 1);
        bird_profile_zero(&bird_profile_deep, sizeof(bird_profile_deep));
        ok &= check(favorite_catalog_index(0U) == 10U &&
                        favorite_catalog_index(1U) ==
                            CATALOG_ENTRY_COUNT - 1U &&
                        bird_profile_deep.catalog_iterations == 0U,
                    "Favorites ordinal lookup still scanned the catalog");

        file_bytes = snprintf(favorites_file, sizeof(favorites_file),
                              "%s\n%s\n%s\n%s\n", last_path, first_path,
                              middle_path, first_path);
        ok &= check(file_bytes > 0 &&
                        (u32)file_bytes < (u32)sizeof(favorites_file),
                    "Favorites benchmark paths exceeded its host buffer");
        reset_favorites();
        bird_profile_reset();
        reset_fake_file(FAKE_FD, favorites_file, 0);
        load_favorites();
        load_iterations = bird_profile_deep.catalog_iterations;
        load_string_bytes = bird_profile_deep.string_bytes;
        ok &= check(favorites_loaded && favorite_count == 3U &&
                        favorite_catalog_index(0U) == 0U &&
                        favorite_catalog_index(1U) ==
                            CATALOG_ENTRY_COUNT / 2U &&
                        favorite_catalog_index(2U) ==
                            CATALOG_ENTRY_COUNT - 1U &&
                        load_iterations <=
                            CATALOG_ENTRY_COUNT + 4U * lookup_bound,
                    "Favorites load exceeded one bounded index rebuild plus path lookups");

        bird_profile_zero(&bird_profile_deep, sizeof(bird_profile_deep));
        reset_fake_file(FAKE_FD, 0, 0);
        ok &= check(save_favorites() == 0,
                    "indexed Favorites benchmark failed to save");
        save_iterations = bird_profile_deep.catalog_iterations;
        ok &= check(save_iterations <= favorite_count,
                    "Favorites save scanned beyond indexed members");
        printf("launcher profile_deep benchmark scenario=favorites-index "
               "lookup_iterations=%lu lookup_bound=%u "
               "load_iterations=%lu load_bound=%u string_bytes=%lu "
               "save_iterations=%lu favorite_count=%u "
               "prior_linear_load_iterations=%u "
               "prior_linear_save_iterations=%u\n",
               (unsigned long)lookup_iterations, lookup_bound,
               (unsigned long)load_iterations,
               CATALOG_ENTRY_COUNT + 4U * lookup_bound,
               (unsigned long)load_string_bytes,
               (unsigned long)save_iterations, favorite_count,
               CATALOG_ENTRY_COUNT + CATALOG_ENTRY_COUNT / 2U + 3U,
               CATALOG_ENTRY_COUNT);
    }

    bird_profile_reset();
    (void)catalog_path_supported("/mnt/mmc/a");
    (void)catalog_find_entry_by_path(
        catalog_entry_path(0U),
        (u32)strlen(catalog_entry_path(0U)));
    ok &= check(bird_profile_deep.string_bytes > 20U,
                "deep profiling missed active path-lookup string scans");
    clear_favorites();
    set_favorite(10U, 1);
    bird_profile_zero(&bird_profile_deep, sizeof(bird_profile_deep));
    (void)favorite_catalog_index(0U);
    ok &= check(bird_profile_deep.catalog_iterations == 0U,
                "deep profiling found a catalog scan in indexed lookup");
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
    ok &= run_phase7_catalog_and_favorites_tests();
    ok &= run_preferred_input_probe_tests();
    ok &= run_phase5_startup_tests();
    ok &= run_phase6_background_tests();
    ok &= run_full_render_golden_tests();
    ok &= run_selected_text_scroll_tests();
    ok &= run_dirty_region_render_tests();
    ok &= run_navigation_batch_tests();
    ok &= run_phase9_menu_hierarchy_tests();
    ok &= run_user_reload_handoff_tests();
    ok &= run_storage_handoff_tests();
    ok &= run_event_driven_input_discovery_tests();

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
    snprintf(partial, sizeof(partial), "%s\n", catalog_entry_path(0U));
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
             catalog_entry_path(CATALOG_ENTRY_COUNT - 1U),
             catalog_entry_path(0U));
    fake_now_ms = (long)due - 1;
    reset_fake_file(FAKE_FD, complete, 0);
    load_favorites();
    ok &= check(!favorites_loaded && fake_open_calls == 0,
                "successful source was opened before the retry deadline");
    fake_now_ms = (long)due;
    load_favorites();
    ok &= check(favorites_loaded && favorite_count == 2 &&
                    is_favorite(0) &&
                    is_favorite(CATALOG_ENTRY_COUNT - 1U) &&
                    favorite_catalog_index(0U) == 0U &&
                    favorite_catalog_index(1U) ==
                        CATALOG_ENTRY_COUNT - 1U,
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
                    poll_descriptor_failed(POLLIN | POLLHUP) &&
                    !poll_descriptor_failed(POLLIN),
                "poll descriptor error/hup/nval classification is incomplete");
    ok &= check(input_drain_allows_pending_dispatch(-EAGAIN, 0) &&
                    !input_drain_allows_pending_dispatch(-EIO_LINUX, 0) &&
                    !input_drain_allows_pending_dispatch(
                        (long)sizeof(struct input_event) - 1L, 0) &&
                    !input_drain_allows_pending_dispatch(-EAGAIN, 1),
                "incomplete or reconnecting input drain allowed pending dispatch");
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
