/*
 * birdOS fixed-device RG34XX-SP launcher.
 *
 * Freestanding AArch64 Linux: no libc, dynamic loader, SDL, font engine,
 * image decoder, locale database, configuration parser or storage scan.
 */

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long u64;
typedef signed int s32;
typedef signed long s64;

#if defined(BIRD_PROFILE_DEEP) && !defined(BIRD_HOST_TEST)
#error "BIRD_PROFILE_DEEP is host-test-only"
#endif
#if defined(BIRD_PROFILE_DEEP) && !defined(BIRD_PROFILE)
#define BIRD_PROFILE 1
#endif

#include "catalog.generated.h"

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_TRUNC 01000
#define O_NONBLOCK 04000
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1

#define FBIOGET_VSCREENINFO 0x4600
#define FBIOGET_FSCREENINFO 0x4602
#define FB_TYPE_PACKED_PIXELS 0U
#define FB_VISUAL_TRUECOLOR 2U
#define EVIOCGNAME_128 0x80804506

#define EV_KEY 0x01
#define EV_ABS 0x03
#define BTN_SOUTH 304
#define BTN_EAST 305
#define BUTTON_Y 306
#define BTN_NORTH 307
#define BTN_WEST 308
#define MUOS_BTN_TL 308
#define MUOS_BTN_TR 309
#define H700_BTN_TL 310
#define H700_BTN_TR 311
#define BTN_DPAD_UP 544
#define BTN_DPAD_DOWN 545
#define BTN_DPAD_LEFT 546
#define BTN_DPAD_RIGHT 547
#define ABS_HAT0X 16
#define ABS_HAT0Y 17
#define POLLIN 0x0001
#define POLLERR 0x0008
#define POLLHUP 0x0010
#define POLLNVAL 0x0020
#define EINTR 4
#define EAGAIN 11
#define ENOENT 2
#define AF_NETLINK 16
#define SOCK_DGRAM 2
#define SOCK_NONBLOCK 04000
#define NETLINK_KOBJECT_UEVENT 15

#define CLOCK_BOOTTIME 7
#ifndef DEVICE_WAIT_MS
#define DEVICE_WAIT_MS 5000UL
#endif
#ifndef ROM_ROOT
#define ROM_ROOT "/mnt/mmc/ROMS"
#endif
#ifndef LIVE_STORAGE_ROOT
#define LIVE_STORAGE_ROOT "/mnt/mmc"
#endif
#define CATALOG_STORAGE_ROOT "/mnt/mmc"
#define LIVE_PATH_BYTES 4096U
#ifndef CATALOG_PATH_MAX_BYTES
/* Transitional fallback for catalogues generated before this contract was
 * embedded in catalog.generated.h. New catalogues define the same value. */
#define CATALOG_PATH_MAX_BYTES 4085U
#endif
#define AUX_RETRY_INITIAL_MS 100UL
#define AUX_RETRY_MAX_MS 3200UL
#define AUX_RETRY_LIMIT 8U
#define POLL_RETRY_INITIAL_MS 1UL
#define POLL_RETRY_MAX_MS 100UL
#define FAVORITES_RETRY_INITIAL_MS 100UL
#define FAVORITES_RETRY_MAX_MS 3200UL
#ifndef LAUNCH_REQUEST
#define LAUNCH_REQUEST "/run/muos/bird-launch-request"
#endif
#ifndef UI_RESUME_PATH
#define UI_RESUME_PATH "/run/muos/bird-launcher-ui-resume"
#endif
#define UI_RESUME_MAGIC 0x42495244U
#ifndef FAVORITES_PATH
#define FAVORITES_PATH "/mnt/mmc/MUOS/bespoke-launcher/favorites.txt"
#endif
#ifndef FAVORITES_TEMP
#define FAVORITES_TEMP "/mnt/mmc/MUOS/bespoke-launcher/favorites.tmp"
#endif
#ifndef RECENT_PATH
#define RECENT_PATH "/mnt/mmc/MUOS/bespoke-launcher/recent.txt"
#endif
#ifndef RECENT_TEMP
#define RECENT_TEMP "/mnt/mmc/MUOS/bespoke-launcher/recent.tmp"
#endif
#ifndef FIRST_FRAME_MARKER
#define FIRST_FRAME_MARKER "/run/muos/bird-first-frame-ready"
#endif
#ifndef STORAGE_ANCHOR_MARKER
#define STORAGE_ANCHOR_MARKER ""
#endif
#ifndef STORAGE_READY_SIGNAL
#define STORAGE_READY_SIGNAL ""
#endif

#define VIEW_MAIN 0U
#define VIEW_PLAY 1U
#define VIEW_SYSTEMS 2U
#define VIEW_GAMES 3U
#define VIEW_FAVORITES 4U
#define VIEW_MEDIA_CATEGORIES 5U
#define VIEW_MEDIA_ENTRIES 6U
#define SYSTEM_ROWS 8U
#define GAME_ROWS 8U
#define ACTION_NONE 0
#define ACTION_RECOVER 1
#define ACTION_LAUNCH 10
#define ACTION_SHUTDOWN 11
#define ACTION_PORTMASTER 12
#define ACTION_RELOAD 13

#define POLL_RESULT_READY 0
#define POLL_RESULT_INTERRUPTED 1
#define POLL_RESULT_FAILED 2

#define PENDING_LAUNCH_NONE 0U
#define PENDING_LAUNCH_GAME 1U
#define PENDING_LAUNCH_MEDIA 2U
#define INPUT_EVENT_SCAN_COUNT 32

/* The accepted stock-root image uses Linux 7.0.11 sun4i-drm fbdev
 * emulation with CONFIG_DRM_FBDEV_OVERALLOC=100. The DRM helper selects
 * XRGB8888, exposes its unused byte as the fbdev transparency field, and the
 * sun4i dumb-buffer helper aligns this already-even pitch to two bytes. */
#define RG34XX_FB_WIDTH 720U
#define RG34XX_FB_HEIGHT 480U
#define RG34XX_FB_BYTES_PER_PIXEL 4U
#define RG34XX_FB_STRIDE (RG34XX_FB_WIDTH * RG34XX_FB_BYTES_PER_PIXEL)
#define RG34XX_FB_BYTES (RG34XX_FB_STRIDE * RG34XX_FB_HEIGHT)

#define FRAMEBUFFER_PATH_DIAGNOSTIC 0U
#define FRAMEBUFFER_PATH_RG34XX_XRGB8888 1U

struct fb_bitfield {
    u32 offset;
    u32 length;
    u32 msb_right;
};

struct fb_var_screeninfo {
    u32 xres;
    u32 yres;
    u32 xres_virtual;
    u32 yres_virtual;
    u32 xoffset;
    u32 yoffset;
    u32 bits_per_pixel;
    u32 grayscale;
    struct fb_bitfield red;
    struct fb_bitfield green;
    struct fb_bitfield blue;
    struct fb_bitfield transp;
    u32 nonstd;
    u32 activate;
    u32 height;
    u32 width;
    u32 accel_flags;
    u32 pixclock;
    u32 left_margin;
    u32 right_margin;
    u32 upper_margin;
    u32 lower_margin;
    u32 hsync_len;
    u32 vsync_len;
    u32 sync;
    u32 vmode;
    u32 rotate;
    u32 colorspace;
    u32 reserved[4];
};

struct fb_fix_screeninfo {
    char id[16];
    u64 smem_start;
    u32 smem_len;
    u32 type;
    u32 type_aux;
    u32 visual;
    u16 xpanstep;
    u16 ypanstep;
    u16 ywrapstep;
    u32 line_length;
    u64 mmio_start;
    u32 mmio_len;
    u32 accel;
    u16 capabilities;
    u16 reserved[2];
};

struct input_event {
    s64 sec;
    s64 usec;
    u16 type;
    u16 code;
    s32 value;
};

struct timespec {
    s64 sec;
    s64 nsec;
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

struct glyph {
    char c;
    u8 row[7];
};

struct ui_resume_state {
    u32 magic;
    u32 view;
    u32 active_index;
    u32 selection;
};

struct pending_launch_state {
    u32 kind;
    u32 index;
    u32 active_index;
};

static struct fb_var_screeninfo fb_var;
static struct fb_fix_screeninfo fb_fix;
static volatile u8 *fb;
static int fb_fd = -1;
static u32 framebuffer_path;
static int input_fd = -1;
static int power_event_fd = -1;
static int h700_input;
static int charging_state = -1;
static int battery_percent = -1;
static int runtime_dir_fd = -1;
static int input_dir_fd = -1;
static int power_dir_fd = -1;
static int storage_dir_fd = -1;
static int config_dir_fd = -1;
static int storage_signal_fd = -1;
static u64 next_storage_signal_retry;
static u64 next_power_event_retry;
static u64 storage_signal_retry_ms = AUX_RETRY_INITIAL_MS;
static u64 power_event_retry_ms = AUX_RETRY_INITIAL_MS;
static u32 storage_signal_retry_count;
static u32 power_event_retry_count;
static int storage_signal_disabled;
static int power_event_disabled;
static char input_path[32] = "/dev/input/event0";
static u32 view;
static u32 selection;
static u32 active_system;
static u32 active_media_category;
static u32 media_section;
static int axis_x;
static int axis_y;
static int storage_ready;
static int favorites_loaded;
static u32 favorite_count;
static u8 favorites[(CATALOG_ENTRY_COUNT + 7U) / 8U];
static u64 next_favorites_retry;
static u64 favorites_retry_ms = FAVORITES_RETRY_INITIAL_MS;
static u32 favorites_retry_count;
static char live_path[LIVE_PATH_BYTES];
static u64 next_storage_probe;
static struct pending_launch_state pending_launch;

static void probe_storage(void);
static const char *selected_status = "DIRECT FRAMEBUFFER READY";

static const char *menu_item[4] = {"PLAY", "LISTEN", "READ", "WATCH"};
static const char *play_item[4] = {"LIBRARY", "FAVORITES", "PORTMASTER", "SHUTDOWN"};

/* Five-wide uppercase bitmap alphabet plus the exact punctuation this UI uses. */
static const struct glyph font[] = {
    {' ', {0, 0, 0, 0, 0, 0, 0}},       {'!', {4, 4, 4, 4, 4, 0, 4}},
    {'\'', {4, 4, 0, 0, 0, 0, 0}},      {'(', {2, 4, 8, 8, 8, 4, 2}},
    {')', {8, 4, 2, 2, 2, 4, 8}},       {'&', {12, 18, 20, 8, 21, 18, 13}},
    {'*', {0, 21, 14, 31, 14, 21, 0}},
    {',', {0, 0, 0, 0, 0, 4, 8}},       {'-', {0, 0, 0, 31, 0, 0, 0}},
    {'.', {0, 0, 0, 0, 0, 0, 4}},       {'%', {17, 18, 4, 8, 19, 17, 0}},
    {'/', {1, 2, 4, 8, 16, 0, 0}},
    {':', {0, 4, 0, 0, 4, 0, 0}},       {'?', {14, 17, 1, 2, 4, 0, 4}},
    {'>', {16, 8, 4, 2, 4, 8, 16}},      {'0', {14, 17, 19, 21, 25, 17, 14}},
    {'1', {4, 12, 4, 4, 4, 4, 14}},      {'2', {14, 17, 1, 2, 4, 8, 31}},
    {'3', {30, 1, 1, 14, 1, 1, 30}},     {'4', {2, 6, 10, 18, 31, 2, 2}},
    {'5', {31, 16, 16, 30, 1, 1, 30}},   {'6', {14, 16, 16, 30, 17, 17, 14}},
    {'7', {31, 1, 2, 4, 8, 8, 8}},       {'8', {14, 17, 17, 14, 17, 17, 14}},
    {'9', {14, 17, 17, 15, 1, 1, 14}},   {'A', {14, 17, 17, 31, 17, 17, 17}},
    {'B', {30, 17, 17, 30, 17, 17, 30}}, {'C', {14, 17, 16, 16, 16, 17, 14}},
    {'D', {30, 17, 17, 17, 17, 17, 30}}, {'E', {31, 16, 16, 30, 16, 16, 31}},
    {'F', {31, 16, 16, 30, 16, 16, 16}}, {'G', {14, 17, 16, 23, 17, 17, 15}},
    {'H', {17, 17, 17, 31, 17, 17, 17}}, {'I', {14, 4, 4, 4, 4, 4, 14}},
    {'J', {7, 2, 2, 2, 2, 18, 12}},      {'K', {17, 18, 20, 24, 20, 18, 17}},
    {'L', {16, 16, 16, 16, 16, 16, 31}}, {'M', {17, 27, 21, 21, 17, 17, 17}},
    {'N', {17, 25, 21, 19, 17, 17, 17}}, {'O', {14, 17, 17, 17, 17, 17, 14}},
    {'P', {30, 17, 17, 30, 16, 16, 16}}, {'Q', {14, 17, 17, 17, 21, 18, 13}},
    {'R', {30, 17, 17, 30, 20, 18, 17}}, {'S', {15, 16, 16, 14, 1, 1, 30}},
    {'T', {31, 4, 4, 4, 4, 4, 4}},       {'U', {17, 17, 17, 17, 17, 17, 14}},
    {'V', {17, 17, 17, 17, 17, 10, 4}},  {'W', {17, 17, 17, 21, 21, 21, 10}},
    {'X', {17, 17, 10, 4, 10, 17, 17}},  {'Y', {17, 17, 10, 4, 4, 4, 4}},
    {'Z', {31, 1, 2, 4, 8, 16, 31}},
};

#ifdef BIRD_PROFILE
enum bird_profile_render_reason {
    PROFILE_RENDER_STARTUP_FULL,
    PROFILE_RENDER_VIEW_CHANGE,
    PROFILE_RENDER_SELECTION_MOVEMENT,
    PROFILE_RENDER_VIEWPORT_CHANGE,
    PROFILE_RENDER_STATUS,
    PROFILE_RENDER_BATTERY,
    PROFILE_RENDER_FAVORITES_COMPLETION,
    PROFILE_RENDER_RECOVERY,
    PROFILE_RENDER_REASON_COUNT,
};

enum bird_profile_syscall_kind {
    PROFILE_SYSCALL_OPENAT,
    PROFILE_SYSCALL_CLOSE,
    PROFILE_SYSCALL_READ,
    PROFILE_SYSCALL_WRITE,
    PROFILE_SYSCALL_FSYNC,
    PROFILE_SYSCALL_IOCTL,
    PROFILE_SYSCALL_MMAP,
    PROFILE_SYSCALL_MUNMAP,
    PROFILE_SYSCALL_CLOCK,
    PROFILE_SYSCALL_PPOLL,
    PROFILE_SYSCALL_SOCKET,
    PROFILE_SYSCALL_BIND,
    PROFILE_SYSCALL_NANOSLEEP,
    PROFILE_SYSCALL_UNLINKAT,
    PROFILE_SYSCALL_RENAMEAT,
    PROFILE_SYSCALL_EXIT,
    PROFILE_SYSCALL_OTHER,
    PROFILE_SYSCALL_KIND_COUNT,
};

struct bird_profile_render_totals {
    u64 commits;
    u64 logical_pixels;
    u64 visible_bytes;
    u64 pages_written;
    u64 physical_bytes;
};

struct bird_profile_state {
    struct bird_profile_render_totals render[PROFILE_RENDER_REASON_COUNT];
    u64 syscalls;
    u64 syscall_kind[PROFILE_SYSCALL_KIND_COUNT];
    u64 filesystem_ops;
    u64 diagnostic_writes;
    u64 diagnostic_bytes;
    u64 pre_barrier_filesystem_ops;
    u64 pre_barrier_diagnostic_writes;
    u64 pre_barrier_diagnostic_bytes;
    u64 application_entry_ns;
    u64 input_open_ns;
    u64 interactive_barrier_ns;
    u64 first_frame_marker_ns;
    u64 milestone_sequence;
    u64 application_entry_order;
    u64 input_open_order;
    u64 interactive_barrier_order;
    u64 first_frame_marker_order;
    u64 input_to_barrier_total_ns;
    u64 input_to_barrier_max_ns;
    u64 input_to_barrier_samples;
    u64 event_pre_barrier_filesystem_ops;
    u64 event_pre_barrier_diagnostic_writes;
    u64 event_pre_barrier_diagnostic_bytes;
    u64 event_pre_barrier_syscall_kind[PROFILE_SYSCALL_KIND_COUNT];
    u64 barrier_to_resume_total_ns;
    u64 barrier_to_resume_max_ns;
    u64 barrier_to_resume_samples;
    u64 resume_before_barrier;
    u64 selection_ns;
    u64 selection_to_exit_ns;
    u64 current_logical_pixels;
    u64 current_visible_bytes;
    u64 current_physical_bytes;
    u64 current_page_mask;
    u64 input_read_ns;
    u64 event_start_filesystem_ops;
    u64 event_start_diagnostic_writes;
    u64 event_start_diagnostic_bytes;
    u64 event_start_syscall_kind[PROFILE_SYSCALL_KIND_COUNT];
    u64 event_barrier_ns;
    u64 barrier_generation;
    u64 event_barrier_generation;
    u64 output_records;
    u32 current_render_reason;
    int current_render_active;
    int interactive_barrier_seen;
    int input_open_seen;
    int event_active;
    int event_barrier_seen;
    int selection_pending;
    int emitting;
    int sampling;
    int application_entry_seen;
    int first_frame_marker_seen;
};

#ifdef BIRD_PROFILE_DEEP
struct bird_profile_deep_state {
    u64 string_calls;
    u64 string_bytes;
    u64 catalog_iterations;
    u64 glyph_lookups;
    u64 glyph_scan_iterations;
    u64 rectangle_calls;
    u64 clipped_pixels;
    u64 fast_rectangle_calls;
    u64 fast_row_spans;
    u64 fast_u32_stores;
    u64 fast_u64_stores;
    u64 fallback_rectangle_calls;
    u64 fallback_pixel_checks;
    u64 fallback_pixel_stores;
    u64 fallback_byte_stores;
};
static struct bird_profile_deep_state bird_profile_deep;
#endif

static struct bird_profile_state bird_profile;
static u64 bird_profile_now_ns(void);
static void bird_profile_application_entry(u64 now);
static void bird_profile_input_opened(void);
static void bird_profile_begin_event(void);
static void bird_profile_finish_event(void);
static void bird_profile_mark_selection(void);
static void bird_profile_cancel_selection(void);
static void bird_profile_resume_committed(void);
static void bird_profile_first_frame_marked(void);
static void bird_profile_emit_startup(void);
static void bird_profile_note_exit_and_emit(void);

static void bird_profile_note_syscall(long number) {
    u32 kind = PROFILE_SYSCALL_OTHER;
    if (bird_profile.emitting || bird_profile.sampling) return;
    if (number == 56) kind = PROFILE_SYSCALL_OPENAT;
    else if (number == 57) kind = PROFILE_SYSCALL_CLOSE;
    else if (number == 63) kind = PROFILE_SYSCALL_READ;
    else if (number == 64) kind = PROFILE_SYSCALL_WRITE;
    else if (number == 82) kind = PROFILE_SYSCALL_FSYNC;
    else if (number == 29) kind = PROFILE_SYSCALL_IOCTL;
    else if (number == 222) kind = PROFILE_SYSCALL_MMAP;
    else if (number == 215) kind = PROFILE_SYSCALL_MUNMAP;
    else if (number == 113) kind = PROFILE_SYSCALL_CLOCK;
    else if (number == 73) kind = PROFILE_SYSCALL_PPOLL;
    else if (number == 198) kind = PROFILE_SYSCALL_SOCKET;
    else if (number == 200) kind = PROFILE_SYSCALL_BIND;
    else if (number == 101) kind = PROFILE_SYSCALL_NANOSLEEP;
    else if (number == 35) kind = PROFILE_SYSCALL_UNLINKAT;
    else if (number == 38) kind = PROFILE_SYSCALL_RENAMEAT;
    else if (number == 93) kind = PROFILE_SYSCALL_EXIT;
    bird_profile.syscall_kind[kind]++;
    if (!bird_profile.emitting && !bird_profile.sampling)
        bird_profile.syscalls++;
}

static void bird_profile_note_filesystem(void) {
    bird_profile.filesystem_ops++;
    if (!bird_profile.interactive_barrier_seen)
        bird_profile.pre_barrier_filesystem_ops++;
}

static void bird_profile_note_diagnostic(u64 bytes) {
    bird_profile.diagnostic_writes++;
    bird_profile.diagnostic_bytes += bytes;
    if (!bird_profile.interactive_barrier_seen) {
        bird_profile.pre_barrier_diagnostic_writes++;
        bird_profile.pre_barrier_diagnostic_bytes += bytes;
    }
}

static void bird_profile_begin_render(u32 reason) {
    bird_profile.current_render_reason = reason < PROFILE_RENDER_REASON_COUNT
                                             ? reason
                                             : PROFILE_RENDER_RECOVERY;
    bird_profile.current_logical_pixels = 0;
    bird_profile.current_visible_bytes = 0;
    bird_profile.current_physical_bytes = 0;
    bird_profile.current_page_mask = 0;
    bird_profile.current_render_active = 1;
}

static void bird_profile_note_fb_span(int x, int framebuffer_y, u32 pixels,
                                      u32 bytes) {
    u32 page = fb_var.yres ? (u32)framebuffer_y / fb_var.yres : 0U;
    u64 offset;
    u64 stored_pixels;
    if (!pixels || (bytes != 2U && bytes != 3U && bytes != 4U))
        return;
    offset = (u64)framebuffer_y * fb_fix.line_length +
             (u64)(x + (int)fb_var.xoffset) * bytes;
    if (offset + bytes > fb_fix.smem_len) return;
    stored_pixels = (fb_fix.smem_len - offset) / bytes;
    if (stored_pixels > pixels) stored_pixels = pixels;
    bird_profile.current_physical_bytes += stored_pixels * bytes;
    if (framebuffer_y >= (int)fb_var.yoffset &&
        framebuffer_y < (int)(fb_var.yoffset + fb_var.yres))
        bird_profile.current_visible_bytes += stored_pixels * bytes;
    if (stored_pixels)
        bird_profile.current_page_mask |= 1UL << (page < 63U ? page : 63U);
}

static void bird_profile_note_rectangle(int x, int y, int width, int height) {
    int first_x;
    int last_x;
    int first_y;
    int last_y;
    int yy;
    u32 bytes;
    u32 visible_width;
    u64 logical_pixels;
#ifdef BIRD_PROFILE_DEEP
    u64 screen_pixels;
#endif
    if (!bird_profile.current_render_active || width <= 0 || height <= 0)
        return;
    logical_pixels = (u64)(u32)width * (u64)(u32)height;
    bird_profile.current_logical_pixels += logical_pixels;
    first_x = x < 0 ? 0 : x;
    last_x = x + width > (int)fb_var.xres
                 ? (int)fb_var.xres : x + width;
    first_y = y < 0 ? 0 : y;
    last_y = y + height > (int)fb_var.yres
                 ? (int)fb_var.yres : y + height;
    if (first_x >= last_x || first_y >= last_y) {
#ifdef BIRD_PROFILE_DEEP
        bird_profile_deep.clipped_pixels += logical_pixels;
#endif
        return;
    }
    visible_width = (u32)(last_x - first_x);
#ifdef BIRD_PROFILE_DEEP
    screen_pixels = (u64)visible_width * (u64)(last_y - first_y);
    bird_profile_deep.clipped_pixels += logical_pixels - screen_pixels;
#endif
    bytes = (fb_var.bits_per_pixel + 7U) / 8U;
    for (yy = first_y; yy < last_y; yy++) {
        bird_profile_note_fb_span(first_x, yy, visible_width, bytes);
        if (fb_var.yres_virtual >= fb_var.yres * 2U)
            bird_profile_note_fb_span(first_x, yy + (int)fb_var.yres,
                                      visible_width, bytes);
        else if (fb_var.yoffset)
            bird_profile_note_fb_span(first_x, yy + (int)fb_var.yoffset,
                                      visible_width, bytes);
    }
}

static u64 bird_profile_page_count(u64 mask) {
    u64 count = 0;
    while (mask) {
        count += mask & 1UL;
        mask >>= 1;
    }
    return count;
}

static void bird_profile_note_barrier(void) {
    struct bird_profile_render_totals *total;
    u64 now;
    u64 delta;
    u32 kind;
    if (!bird_profile.current_render_active) return;
    now = bird_profile_now_ns();
    total = &bird_profile.render[bird_profile.current_render_reason];
    total->commits++;
    total->logical_pixels += bird_profile.current_logical_pixels;
    total->visible_bytes += bird_profile.current_visible_bytes;
    total->pages_written += bird_profile_page_count(bird_profile.current_page_mask);
    total->physical_bytes += bird_profile.current_physical_bytes;
    bird_profile.barrier_generation++;
    if (!bird_profile.interactive_barrier_seen &&
        bird_profile.current_render_reason == PROFILE_RENDER_STARTUP_FULL) {
        bird_profile.interactive_barrier_seen = 1;
        bird_profile.interactive_barrier_ns = now;
        bird_profile.interactive_barrier_order = ++bird_profile.milestone_sequence;
    }
    if (bird_profile.event_active) {
        delta = now >= bird_profile.input_read_ns
                    ? now - bird_profile.input_read_ns : 0;
        bird_profile.input_to_barrier_total_ns += delta;
        if (delta > bird_profile.input_to_barrier_max_ns)
            bird_profile.input_to_barrier_max_ns = delta;
        bird_profile.input_to_barrier_samples++;
        bird_profile.event_pre_barrier_filesystem_ops +=
            bird_profile.filesystem_ops - bird_profile.event_start_filesystem_ops;
        bird_profile.event_pre_barrier_diagnostic_writes +=
            bird_profile.diagnostic_writes - bird_profile.event_start_diagnostic_writes;
        bird_profile.event_pre_barrier_diagnostic_bytes +=
            bird_profile.diagnostic_bytes - bird_profile.event_start_diagnostic_bytes;
        for (kind = 0; kind < PROFILE_SYSCALL_KIND_COUNT; kind++)
            bird_profile.event_pre_barrier_syscall_kind[kind] +=
                bird_profile.syscall_kind[kind] -
                bird_profile.event_start_syscall_kind[kind];
        bird_profile.event_barrier_ns = now;
        bird_profile.event_barrier_generation = bird_profile.barrier_generation;
        bird_profile.event_barrier_seen = 1;
    }
    bird_profile.current_render_active = 0;
}

#ifdef BIRD_PROFILE_DEEP
static void bird_profile_deep_note_string(u64 bytes) {
    bird_profile_deep.string_calls++;
    bird_profile_deep.string_bytes += bytes;
}
#define BIRD_PROFILE_DEEP_STRING(bytes) bird_profile_deep_note_string(bytes)
#define BIRD_PROFILE_DEEP_STRING_BYTE() (bird_profile_deep.string_bytes++)
#define BIRD_PROFILE_DEEP_CATALOG_ITERATION() \
    (bird_profile_deep.catalog_iterations++)
#define BIRD_PROFILE_DEEP_GLYPH_LOOKUP() (bird_profile_deep.glyph_lookups++)
#define BIRD_PROFILE_DEEP_GLYPH_SCAN() \
    (bird_profile_deep.glyph_scan_iterations++)
#define BIRD_PROFILE_DEEP_RECTANGLE() (bird_profile_deep.rectangle_calls++)
#define BIRD_PROFILE_DEEP_FAST_RECTANGLE(rows) do { \
    bird_profile_deep.fast_rectangle_calls++; \
    bird_profile_deep.fast_row_spans += (rows); \
} while (0)
#define BIRD_PROFILE_DEEP_FAST_U32_STORES(stores) \
    (bird_profile_deep.fast_u32_stores += (stores))
#define BIRD_PROFILE_DEEP_FAST_U64_STORES(stores) \
    (bird_profile_deep.fast_u64_stores += (stores))
#define BIRD_PROFILE_DEEP_FALLBACK_RECTANGLE() \
    (bird_profile_deep.fallback_rectangle_calls++)
#define BIRD_PROFILE_DEEP_FALLBACK_PIXEL_CHECK() \
    (bird_profile_deep.fallback_pixel_checks++)
#define BIRD_PROFILE_DEEP_FALLBACK_PIXEL_STORE(bytes) do { \
    bird_profile_deep.fallback_pixel_stores++; \
    bird_profile_deep.fallback_byte_stores += (bytes); \
} while (0)
#else
#define BIRD_PROFILE_DEEP_STRING(bytes) ((void)0)
#define BIRD_PROFILE_DEEP_STRING_BYTE() ((void)0)
#define BIRD_PROFILE_DEEP_CATALOG_ITERATION() ((void)0)
#define BIRD_PROFILE_DEEP_GLYPH_LOOKUP() ((void)0)
#define BIRD_PROFILE_DEEP_GLYPH_SCAN() ((void)0)
#define BIRD_PROFILE_DEEP_RECTANGLE() ((void)0)
#define BIRD_PROFILE_DEEP_FAST_RECTANGLE(rows) ((void)0)
#define BIRD_PROFILE_DEEP_FAST_U32_STORES(stores) ((void)0)
#define BIRD_PROFILE_DEEP_FAST_U64_STORES(stores) ((void)0)
#define BIRD_PROFILE_DEEP_FALLBACK_RECTANGLE() ((void)0)
#define BIRD_PROFILE_DEEP_FALLBACK_PIXEL_CHECK() ((void)0)
#define BIRD_PROFILE_DEEP_FALLBACK_PIXEL_STORE(bytes) ((void)0)
#endif

#define BIRD_PROFILE_SYSCALL(number) bird_profile_note_syscall(number)
#define BIRD_PROFILE_FILESYSTEM() bird_profile_note_filesystem()
#define BIRD_PROFILE_DIAGNOSTIC(bytes) bird_profile_note_diagnostic(bytes)
#define BIRD_PROFILE_RENDER(reason) bird_profile_begin_render(reason)
#define BIRD_PROFILE_RECTANGLE(x, y, width, height) \
    bird_profile_note_rectangle(x, y, width, height)
#define BIRD_PROFILE_BARRIER() bird_profile_note_barrier()
#define BIRD_PROFILE_APPLICATION_ENTRY(now) bird_profile_application_entry(now)
#define BIRD_PROFILE_INPUT_OPENED() bird_profile_input_opened()
#define BIRD_PROFILE_BEGIN_EVENT() bird_profile_begin_event()
#define BIRD_PROFILE_FINISH_EVENT() bird_profile_finish_event()
#define BIRD_PROFILE_MARK_SELECTION() bird_profile_mark_selection()
#define BIRD_PROFILE_CANCEL_SELECTION() bird_profile_cancel_selection()
#define BIRD_PROFILE_RESUME_COMMITTED() bird_profile_resume_committed()
#define BIRD_PROFILE_FIRST_FRAME_MARKED() bird_profile_first_frame_marked()
#define BIRD_PROFILE_EMIT_STARTUP() bird_profile_emit_startup()
#define BIRD_PROFILE_EXIT_AND_EMIT() bird_profile_note_exit_and_emit()
#else
#define BIRD_PROFILE_SYSCALL(number)
#define BIRD_PROFILE_FILESYSTEM()
#define BIRD_PROFILE_DIAGNOSTIC(bytes)
#define BIRD_PROFILE_RENDER(reason)
#define BIRD_PROFILE_RECTANGLE(x, y, width, height)
#define BIRD_PROFILE_BARRIER()
#define BIRD_PROFILE_DEEP_STRING(bytes)
#define BIRD_PROFILE_DEEP_STRING_BYTE()
#define BIRD_PROFILE_DEEP_CATALOG_ITERATION()
#define BIRD_PROFILE_DEEP_GLYPH_LOOKUP()
#define BIRD_PROFILE_DEEP_GLYPH_SCAN()
#define BIRD_PROFILE_DEEP_RECTANGLE()
#define BIRD_PROFILE_DEEP_FAST_RECTANGLE(rows)
#define BIRD_PROFILE_DEEP_FAST_U32_STORES(stores)
#define BIRD_PROFILE_DEEP_FAST_U64_STORES(stores)
#define BIRD_PROFILE_DEEP_FALLBACK_RECTANGLE()
#define BIRD_PROFILE_DEEP_FALLBACK_PIXEL_CHECK()
#define BIRD_PROFILE_DEEP_FALLBACK_PIXEL_STORE(bytes)
#define BIRD_PROFILE_APPLICATION_ENTRY(now)
#define BIRD_PROFILE_INPUT_OPENED()
#define BIRD_PROFILE_BEGIN_EVENT()
#define BIRD_PROFILE_FINISH_EVENT()
#define BIRD_PROFILE_MARK_SELECTION()
#define BIRD_PROFILE_CANCEL_SELECTION()
#define BIRD_PROFILE_RESUME_COMMITTED()
#define BIRD_PROFILE_FIRST_FRAME_MARKED()
#define BIRD_PROFILE_EMIT_STARTUP()
#define BIRD_PROFILE_EXIT_AND_EMIT()
#endif

#ifdef BIRD_HOST_TEST
extern long bird_test_syscall6(long number, long a0, long a1, long a2,
                               long a3, long a4, long a5);
#endif

static long syscall6(long number, long a0, long a1, long a2, long a3, long a4, long a5) {
    BIRD_PROFILE_SYSCALL(number);
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
    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5), "r"(x8) : "memory", "cc");
    return x0;
#endif
}

static long sys_open(const char *path, int flags) {
    BIRD_PROFILE_FILESYSTEM();
    return syscall6(56, AT_FDCWD, (long)path, flags, 0, 0, 0);
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

static long sys_fsync(int fd) {
    return syscall6(82, fd, 0, 0, 0, 0, 0);
}

static long sys_ioctl(int fd, u64 request, void *arg) {
    return syscall6(29, fd, (long)request, (long)arg, 0, 0, 0);
}

static void *sys_mmap(u64 length) {
    return (void *)syscall6(222, 0, (long)length, PROT_READ | PROT_WRITE, MAP_SHARED, fb_fd, 0);
}

static long sys_munmap(void *address, u64 length) {
    return syscall6(215, (long)address, (long)length, 0, 0, 0, 0);
}

static long sys_clock_gettime(struct timespec *value) {
    return syscall6(113, CLOCK_BOOTTIME, (long)value, 0, 0, 0, 0);
}

static long sys_ppoll(struct pollfd *fds, u64 count, struct timespec *timeout) {
    return syscall6(73, (long)fds, (long)count, (long)timeout, 0, 0, 0);
}

static long sys_socket(int domain, int type, int protocol) {
    return syscall6(198, domain, type, protocol, 0, 0, 0);
}

static long sys_bind(int fd, const struct sockaddr_nl *address, u32 length) {
    return syscall6(200, fd, (long)address, length, 0, 0, 0);
}

static void sys_nanosleep(s64 nanoseconds) {
    struct timespec request;
    request.sec = 0;
    request.nsec = nanoseconds;
    syscall6(101, (long)&request, 0, 0, 0, 0, 0);
}

__attribute__((noreturn)) static void sys_exit(int status) {
    syscall6(93, status, 0, 0, 0, 0, 0);
    __builtin_unreachable();
}

static u64 string_length(const char *text) {
    u64 length = 0;
    while (text[length]) length++;
    BIRD_PROFILE_DEEP_STRING(length + 1U);
    return length;
}

static int string_equal(const char *left, const char *right) {
    while (*left && *left == *right) {
        BIRD_PROFILE_DEEP_STRING_BYTE();
        left++;
        right++;
    }
    BIRD_PROFILE_DEEP_STRING_BYTE();
    return *left == *right;
}

static int string_starts_with(const char *text, const char *prefix) {
    while (*prefix) {
        BIRD_PROFILE_DEEP_STRING_BYTE();
        if (*text++ != *prefix++) return 0;
    }
    return 1;
}

/*
 * The initramfs Bird survives switch_root. Directory descriptors keep pointing
 * at the same moved tmpfs/devtmpfs/sysfs/storage mounts even though that
 * process intentionally retains its tiny old root. All post-handoff file work
 * therefore uses openat/renameat/unlinkat through these fixed anchors.
 */
static void refresh_path_anchors(void) {
    if (runtime_dir_fd < 0)
        runtime_dir_fd = (int)sys_open("/run/muos", O_RDONLY | O_NONBLOCK);
    if (input_dir_fd < 0)
        input_dir_fd = (int)sys_open("/dev/input", O_RDONLY | O_NONBLOCK);
    if (power_dir_fd < 0)
        power_dir_fd = (int)sys_open("/sys/class/power_supply/battery",
                                     O_RDONLY | O_NONBLOCK);
    if (storage_dir_fd < 0)
        storage_dir_fd = (int)sys_open(LIVE_STORAGE_ROOT,
                                      O_RDONLY | O_NONBLOCK);
    if (storage_dir_fd < 0)
        storage_dir_fd = (int)sys_open("/sysroot/storage/bird-data",
                                      O_RDONLY | O_NONBLOCK);
    if (config_dir_fd < 0)
        config_dir_fd = (int)sys_open("/storage/.config/bird",
                                     O_RDONLY | O_NONBLOCK);
    if (config_dir_fd < 0)
        config_dir_fd = (int)sys_open("/sysroot/storage/.config/bird",
                                     O_RDONLY | O_NONBLOCK);
}

static int anchored_dirfd(const char *path, const char **relative) {
    static const char run_root[] = "/run/muos";
    static const char input_root[] = "/dev/input";
    static const char power_root[] = "/sys/class/power_supply/battery";
    static const char config_root[] = "/storage/.config/bird";
    u64 length;

    length = sizeof(run_root) - 1U;
    if (runtime_dir_fd >= 0 && string_starts_with(path, run_root) &&
        path[length] == '/') {
        *relative = path + length + 1U;
        return runtime_dir_fd;
    }
    length = sizeof(input_root) - 1U;
    if (input_dir_fd >= 0 && string_starts_with(path, input_root) &&
        path[length] == '/') {
        *relative = path + length + 1U;
        return input_dir_fd;
    }
    length = sizeof(power_root) - 1U;
    if (power_dir_fd >= 0 && string_starts_with(path, power_root) &&
        path[length] == '/') {
        *relative = path + length + 1U;
        return power_dir_fd;
    }
    length = sizeof(config_root) - 1U;
    if (config_dir_fd >= 0 && string_starts_with(path, config_root) &&
        path[length] == '/') {
        *relative = path + length + 1U;
        return config_dir_fd;
    }
    length = string_length(LIVE_STORAGE_ROOT);
    if (storage_dir_fd >= 0 && string_starts_with(path, LIVE_STORAGE_ROOT) &&
        path[length] == '/') {
        *relative = path + length + 1U;
        return storage_dir_fd;
    }
    *relative = path;
    return AT_FDCWD;
}

static long fixed_open(const char *path, int flags) {
    const char *relative;
    int dirfd = anchored_dirfd(path, &relative);
    BIRD_PROFILE_FILESYSTEM();
    return syscall6(56, dirfd, (long)relative, flags, 0, 0, 0);
}

static long fixed_create(const char *path, int flags, int mode) {
    const char *relative;
    int dirfd = anchored_dirfd(path, &relative);
    BIRD_PROFILE_FILESYSTEM();
    return syscall6(56, dirfd, (long)relative, flags, mode, 0, 0);
}

static long fixed_unlink(const char *path) {
    const char *relative;
    int dirfd = anchored_dirfd(path, &relative);
    BIRD_PROFILE_FILESYSTEM();
    return syscall6(35, dirfd, (long)relative, 0, 0, 0, 0);
}

static long fixed_rename(const char *old_path, const char *new_path) {
    const char *old_relative;
    const char *new_relative;
    int old_dirfd = anchored_dirfd(old_path, &old_relative);
    int new_dirfd = anchored_dirfd(new_path, &new_relative);
    BIRD_PROFILE_FILESYSTEM();
    return syscall6(38, old_dirfd, (long)old_relative,
                    new_dirfd, (long)new_relative, 0, 0);
}

/*
 * Catalogue paths remain stable across firmware providers. Only live file
 * access is translated, so favorites, recents and launch requests continue
 * to use the canonical /mnt/mmc paths embedded in the cached index.
 */
static int catalog_path_supported(const char *path) {
    u64 root_length = string_length(CATALOG_STORAGE_ROOT);
    u64 length = 0;

    while (path[length]) {
        u8 byte = (u8)path[length];
        BIRD_PROFILE_DEEP_STRING_BYTE();
        if (length >= CATALOG_PATH_MAX_BYTES || byte < 32U || byte == 127U)
            return 0;
        length++;
    }
    BIRD_PROFILE_DEEP_STRING_BYTE();
    return length > root_length &&
           string_starts_with(path, CATALOG_STORAGE_ROOT) &&
           path[root_length] == '/';
}

static const char *resolve_live_path(const char *path) {
    u64 source_length = string_length(CATALOG_STORAGE_ROOT);
    u64 target_length = string_length(LIVE_STORAGE_ROOT);
    u64 tail_length;
    u64 i;

    if (!catalog_path_supported(path)) return 0;
    if (string_equal(CATALOG_STORAGE_ROOT, LIVE_STORAGE_ROOT)) return path;
    for (i = 0; i < source_length; i++)
        if (path[i] != CATALOG_STORAGE_ROOT[i]) return path;
    if (path[source_length] && path[source_length] != '/') return path;

    tail_length = string_length(path + source_length);
    if (target_length + tail_length + 1U > sizeof(live_path)) return 0;
    for (i = 0; i < target_length; i++) live_path[i] = LIVE_STORAGE_ROOT[i];
    for (i = 0; i <= tail_length; i++)
        live_path[target_length + i] = path[source_length + i];
    return live_path;
}

static void log_text(const char *text) {
#ifdef BIRD_PROFILE
    u64 length = string_length(text);
    BIRD_PROFILE_DIAGNOSTIC(length);
    sys_write(1, text, length);
#else
    sys_write(1, text, string_length(text));
#endif
}

static void log_number(u64 value) {
    char buffer[24];
    int position = 23;
    buffer[position--] = 0;
    if (!value) buffer[position--] = '0';
    while (value) {
        buffer[position--] = (char)('0' + (value % 10));
        value /= 10;
    }
    BIRD_PROFILE_DIAGNOSTIC((u64)(22 - position));
    sys_write(1, &buffer[position + 1], (u64)(22 - position));
}

static u64 boot_ms(void) {
    struct timespec now;
    if (sys_clock_gettime(&now) < 0) return 0;
    return (u64)now.sec * 1000UL + (u64)(now.nsec / 1000000L);
}

#ifdef BIRD_PROFILE
static const char *bird_profile_render_name[PROFILE_RENDER_REASON_COUNT] = {
    "startup-full",
    "view-change",
    "selection-movement",
    "viewport-change",
    "status",
    "battery",
    "favorites-completion",
    "recovery",
};

static const char *bird_profile_syscall_name[PROFILE_SYSCALL_KIND_COUNT] = {
    "openat", "close", "read", "write", "fsync", "ioctl", "mmap",
    "munmap", "clock", "ppoll", "socket", "bind", "nanosleep",
    "unlinkat", "renameat", "exit", "other",
};

static u64 bird_profile_now_ns(void) {
    struct timespec now;
    bird_profile.sampling = 1;
    (void)sys_clock_gettime(&now);
    bird_profile.sampling = 0;
    return (u64)now.sec * 1000000000UL + (u64)now.nsec;
}

static void bird_profile_zero(void *memory, u64 bytes) {
    u8 *cursor = (u8 *)memory;
    while (bytes--) *cursor++ = 0;
}

static void bird_profile_reset(void) {
    bird_profile_zero(&bird_profile, sizeof(bird_profile));
#ifdef BIRD_PROFILE_DEEP
    bird_profile_zero(&bird_profile_deep, sizeof(bird_profile_deep));
#endif
}

static void bird_profile_application_entry(u64 now) {
    bird_profile.application_entry_ns = now;
    bird_profile.application_entry_order = ++bird_profile.milestone_sequence;
    bird_profile.application_entry_seen = 1;
}

static void bird_profile_input_opened(void) {
    if (bird_profile.input_open_seen) return;
    bird_profile.input_open_ns = bird_profile_now_ns();
    bird_profile.input_open_order = ++bird_profile.milestone_sequence;
    bird_profile.input_open_seen = 1;
}

static void bird_profile_begin_event(void) {
    u32 kind;
    bird_profile.event_active = 1;
    bird_profile.event_barrier_seen = 0;
    bird_profile.event_barrier_ns = 0;
    bird_profile.event_barrier_generation = bird_profile.barrier_generation;
    bird_profile.input_read_ns = bird_profile_now_ns();
    bird_profile.event_start_filesystem_ops = bird_profile.filesystem_ops;
    bird_profile.event_start_diagnostic_writes = bird_profile.diagnostic_writes;
    bird_profile.event_start_diagnostic_bytes = bird_profile.diagnostic_bytes;
    for (kind = 0; kind < PROFILE_SYSCALL_KIND_COUNT; kind++)
        bird_profile.event_start_syscall_kind[kind] =
            bird_profile.syscall_kind[kind];
}

static void bird_profile_finish_event(void) {
    bird_profile.event_active = 0;
    bird_profile.event_barrier_seen = 0;
    bird_profile.event_barrier_ns = 0;
}

static void bird_profile_mark_selection(void) {
    bird_profile.selection_ns = bird_profile.event_active
                                    ? bird_profile.input_read_ns
                                    : bird_profile_now_ns();
    bird_profile.selection_pending = 1;
}

static void bird_profile_cancel_selection(void) {
    bird_profile.selection_pending = 0;
    bird_profile.selection_ns = 0;
}

static void bird_profile_resume_committed(void) {
    u64 now;
    u64 delta;
    if (!bird_profile.event_active) return;
    if (!bird_profile.event_barrier_seen) {
        bird_profile.resume_before_barrier++;
        return;
    }
    now = bird_profile_now_ns();
    delta = now >= bird_profile.event_barrier_ns
                ? now - bird_profile.event_barrier_ns : 0;
    bird_profile.barrier_to_resume_total_ns += delta;
    if (delta > bird_profile.barrier_to_resume_max_ns)
        bird_profile.barrier_to_resume_max_ns = delta;
    bird_profile.barrier_to_resume_samples++;
}

static void bird_profile_first_frame_marked(void) {
    bird_profile.first_frame_marker_ns = bird_profile_now_ns();
    bird_profile.first_frame_marker_order = ++bird_profile.milestone_sequence;
    bird_profile.first_frame_marker_seen = 1;
}

static void bird_profile_write_text(const char *text) {
    const char *end = text;
    while (*end) end++;
    (void)sys_write(1, text, (u64)(end - text));
}

static void bird_profile_write_number(u64 value) {
    char buffer[24];
    int position = 23;
    buffer[position--] = 0;
    if (!value) buffer[position--] = '0';
    while (value) {
        buffer[position--] = (char)('0' + value % 10U);
        value /= 10U;
    }
    (void)sys_write(1, &buffer[position + 1], (u64)(22 - position));
}

static void bird_profile_write_interval(const char *name, int start_seen,
                                        u64 start, u64 start_order,
                                        int end_seen, u64 end, u64 end_order,
                                        const char *reverse_reason) {
    bird_profile_write_text(" ");
    bird_profile_write_text(name);
    bird_profile_write_text("=");
    if (!start_seen || !end_seen) {
        bird_profile_write_text("unavailable");
    } else if (end_order < start_order) {
        bird_profile_write_text("unavailable:");
        bird_profile_write_text(reverse_reason);
    } else {
        bird_profile_write_number(end - start);
    }
}

static void bird_profile_emit_startup(void) {
    if (!bird_profile.interactive_barrier_seen) return;
    bird_profile.emitting = 1;
    bird_profile.output_records++;
    bird_profile_write_text("bird_profile milestone=startup");
    bird_profile_write_interval("entry_to_input_open_ns",
                                bird_profile.application_entry_seen,
                                bird_profile.application_entry_ns,
                                bird_profile.application_entry_order,
                                bird_profile.input_open_seen,
                                bird_profile.input_open_ns,
                                bird_profile.input_open_order,
                                "input-before-entry");
    bird_profile_write_interval("input_open_to_interactive_barrier_ns",
                                bird_profile.input_open_seen,
                                bird_profile.input_open_ns,
                                bird_profile.input_open_order,
                                bird_profile.interactive_barrier_seen,
                                bird_profile.interactive_barrier_ns,
                                bird_profile.interactive_barrier_order,
                                "barrier-before-input");
    bird_profile_write_interval("barrier_to_first_frame_marker_ns",
                                bird_profile.interactive_barrier_seen,
                                bird_profile.interactive_barrier_ns,
                                bird_profile.interactive_barrier_order,
                                bird_profile.first_frame_marker_seen,
                                bird_profile.first_frame_marker_ns,
                                bird_profile.first_frame_marker_order,
                                "marker-before-barrier");
    bird_profile_write_text(" pre_barrier_filesystem_namespace_ops=");
    bird_profile_write_number(bird_profile.pre_barrier_filesystem_ops);
    bird_profile_write_text(" pre_barrier_diagnostic_writes=");
    bird_profile_write_number(bird_profile.pre_barrier_diagnostic_writes);
    bird_profile_write_text(" pre_barrier_diagnostic_bytes=");
    bird_profile_write_number(bird_profile.pre_barrier_diagnostic_bytes);
    bird_profile_write_text("\n");
    bird_profile.emitting = 0;
}

static void bird_profile_emit_render_totals(void) {
    u32 reason;
    for (reason = 0; reason < PROFILE_RENDER_REASON_COUNT; reason++) {
        const struct bird_profile_render_totals *total =
            &bird_profile.render[reason];
        if (!total->commits) continue;
        bird_profile.output_records++;
        bird_profile_write_text("bird_profile render_reason=");
        bird_profile_write_text(bird_profile_render_name[reason]);
        bird_profile_write_text(" commits=");
        bird_profile_write_number(total->commits);
        bird_profile_write_text(" logical_pixels_requested=");
        bird_profile_write_number(total->logical_pixels);
        bird_profile_write_text(" visible_framebuffer_bytes=");
        bird_profile_write_number(total->visible_bytes);
        bird_profile_write_text(" pages_written=");
        bird_profile_write_number(total->pages_written);
        bird_profile_write_text(" physical_bytes_stored=");
        bird_profile_write_number(total->physical_bytes);
        bird_profile_write_text("\n");
    }
}

static void bird_profile_emit_syscall_totals(void) {
    u32 kind;
    bird_profile.output_records++;
    bird_profile_write_text("bird_profile syscall_categories");
    for (kind = 0; kind < PROFILE_SYSCALL_KIND_COUNT; kind++) {
        bird_profile_write_text(" ");
        bird_profile_write_text(bird_profile_syscall_name[kind]);
        bird_profile_write_text("=");
        bird_profile_write_number(bird_profile.syscall_kind[kind]);
    }
    bird_profile_write_text("\n");
}

static void bird_profile_emit_event_syscall_totals(void) {
    u32 kind;
    bird_profile.output_records++;
    bird_profile_write_text("bird_profile event_pre_barrier_syscalls");
    for (kind = 0; kind < PROFILE_SYSCALL_KIND_COUNT; kind++) {
        bird_profile_write_text(" ");
        bird_profile_write_text(bird_profile_syscall_name[kind]);
        bird_profile_write_text("=");
        bird_profile_write_number(
            bird_profile.event_pre_barrier_syscall_kind[kind]);
    }
    bird_profile_write_text("\n");
}

static void bird_profile_note_exit_and_emit(void) {
    u64 now = bird_profile_now_ns();
    if (bird_profile.selection_pending && now >= bird_profile.selection_ns)
        bird_profile.selection_to_exit_ns = now - bird_profile.selection_ns;
    if (!bird_profile.interactive_barrier_seen) return;
    bird_profile.emitting = 1;
    bird_profile.output_records++;
    bird_profile_write_text("bird_profile milestone=exit");
    bird_profile_write_text(" input_read_to_barrier_samples=");
    bird_profile_write_number(bird_profile.input_to_barrier_samples);
    bird_profile_write_text(" input_read_to_barrier_total_ns=");
    bird_profile_write_number(bird_profile.input_to_barrier_total_ns);
    bird_profile_write_text(" input_read_to_barrier_max_ns=");
    bird_profile_write_number(bird_profile.input_to_barrier_max_ns);
    bird_profile_write_text(" event_pre_barrier_filesystem_namespace_ops=");
    bird_profile_write_number(bird_profile.event_pre_barrier_filesystem_ops);
    bird_profile_write_text(" event_pre_barrier_diagnostic_writes=");
    bird_profile_write_number(bird_profile.event_pre_barrier_diagnostic_writes);
    bird_profile_write_text(" event_pre_barrier_diagnostic_bytes=");
    bird_profile_write_number(bird_profile.event_pre_barrier_diagnostic_bytes);
    bird_profile_write_text(" barrier_to_resume_samples=");
    bird_profile_write_number(bird_profile.barrier_to_resume_samples);
    bird_profile_write_text(" barrier_to_resume_total_ns=");
    bird_profile_write_number(bird_profile.barrier_to_resume_total_ns);
    bird_profile_write_text(" barrier_to_resume_max_ns=");
    bird_profile_write_number(bird_profile.barrier_to_resume_max_ns);
    bird_profile_write_text(" resume_before_barrier=");
    bird_profile_write_number(bird_profile.resume_before_barrier);
    bird_profile_write_text(" barrier_to_resume_commit_ns=");
    if (bird_profile.barrier_to_resume_samples)
        bird_profile_write_number(bird_profile.barrier_to_resume_total_ns);
    else if (bird_profile.resume_before_barrier)
        bird_profile_write_text("unavailable:commit-before-barrier");
    else
        bird_profile_write_text("unavailable");
    bird_profile_write_text(" selection_to_launcher_exit_ns=");
    if (bird_profile.selection_pending)
        bird_profile_write_number(bird_profile.selection_to_exit_ns);
    else
        bird_profile_write_text("unavailable");
    bird_profile_write_text(" syscalls=");
    bird_profile_write_number(bird_profile.syscalls);
    bird_profile_write_text(" filesystem_namespace_ops=");
    bird_profile_write_number(bird_profile.filesystem_ops);
    bird_profile_write_text(" diagnostic_writes=");
    bird_profile_write_number(bird_profile.diagnostic_writes);
    bird_profile_write_text(" diagnostic_bytes=");
    bird_profile_write_number(bird_profile.diagnostic_bytes);
    bird_profile_write_text("\n");
    bird_profile_emit_syscall_totals();
    bird_profile_emit_event_syscall_totals();
    bird_profile_emit_render_totals();
#ifdef BIRD_PROFILE_DEEP
    bird_profile.output_records++;
    bird_profile_write_text("bird_profile_deep string_calls=");
    bird_profile_write_number(bird_profile_deep.string_calls);
    bird_profile_write_text(" string_bytes=");
    bird_profile_write_number(bird_profile_deep.string_bytes);
    bird_profile_write_text(" catalog_iterations=");
    bird_profile_write_number(bird_profile_deep.catalog_iterations);
    bird_profile_write_text(" glyph_lookups=");
    bird_profile_write_number(bird_profile_deep.glyph_lookups);
    bird_profile_write_text(" glyph_scan_iterations=");
    bird_profile_write_number(bird_profile_deep.glyph_scan_iterations);
    bird_profile_write_text(" rectangle_calls=");
    bird_profile_write_number(bird_profile_deep.rectangle_calls);
    bird_profile_write_text(" clipped_pixels=");
    bird_profile_write_number(bird_profile_deep.clipped_pixels);
    bird_profile_write_text(" fast_rectangle_calls=");
    bird_profile_write_number(bird_profile_deep.fast_rectangle_calls);
    bird_profile_write_text(" fast_row_spans=");
    bird_profile_write_number(bird_profile_deep.fast_row_spans);
    bird_profile_write_text(" fast_u32_stores=");
    bird_profile_write_number(bird_profile_deep.fast_u32_stores);
    bird_profile_write_text(" fast_u64_stores=");
    bird_profile_write_number(bird_profile_deep.fast_u64_stores);
    bird_profile_write_text(" fallback_rectangle_calls=");
    bird_profile_write_number(bird_profile_deep.fallback_rectangle_calls);
    bird_profile_write_text(" fallback_pixel_checks=");
    bird_profile_write_number(bird_profile_deep.fallback_pixel_checks);
    bird_profile_write_text(" fallback_pixel_stores=");
    bird_profile_write_number(bird_profile_deep.fallback_pixel_stores);
    bird_profile_write_text(" fallback_byte_stores=");
    bird_profile_write_number(bird_profile_deep.fallback_byte_stores);
    bird_profile_write_text("\n");
#endif
    bird_profile.emitting = 0;
}
#endif

/*
 * Charging is owned by the AXP717 kernel driver. Bird reads its fixed sysfs
 * contract directly and blocks on kernel uevents, so the indicator needs no
 * polling timer, helper daemon or dependency on the later ROCKNIX service
 * graph. The second path keeps the launcher useful with an unpatched kernel.
 */
static int read_charging_state(void) {
    static const char *paths[] = {
        "/sys/class/power_supply/battery/status",
        "/sys/class/power_supply/axp20x-battery/status",
    };
    char value[32];
    u32 index;

    for (index = 0; index < sizeof(paths) / sizeof(paths[0]); index++) {
        long fd = fixed_open(paths[index], O_RDONLY | O_NONBLOCK);
        long count;
        if (fd < 0) continue;
        count = sys_read((int)fd, value, sizeof(value) - 1U);
        sys_close((int)fd);
        if (count <= 0) continue;
        value[count] = 0;
        return string_starts_with(value, "Charging") ? 1 : 0;
    }
    return -1;
}

static int read_battery_percent(void) {
    static const char *paths[] = {
        "/sys/class/power_supply/battery/capacity",
        "/sys/class/power_supply/axp20x-battery/capacity",
    };
    char value[16];
    u32 index;

    for (index = 0; index < sizeof(paths) / sizeof(paths[0]); index++) {
        long fd = fixed_open(paths[index], O_RDONLY | O_NONBLOCK);
        long count;
        long offset = 0;
        int result = 0;
        int digits = 0;
        if (fd < 0) continue;
        count = sys_read((int)fd, value, sizeof(value));
        sys_close((int)fd);
        if (count <= 0) continue;
        while (offset < count && (value[offset] == ' ' || value[offset] == '\t'))
            offset++;
        while (offset < count && value[offset] >= '0' && value[offset] <= '9') {
            result = result * 10 + (value[offset++] - '0');
            digits++;
        }
        if (digits && result <= 100) return result;
    }
    return -1;
}

static int open_power_events(void) {
    struct sockaddr_nl address;
    long fd = sys_socket(AF_NETLINK, SOCK_DGRAM | SOCK_NONBLOCK,
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

static u64 next_retry_delay(u64 delay) {
    if (delay >= AUX_RETRY_MAX_MS / 2UL) return AUX_RETRY_MAX_MS;
    return delay * 2UL;
}

static int classify_poll_result(long result) {
    if (result >= 0) return POLL_RESULT_READY;
    if (result == -EINTR) return POLL_RESULT_INTERRUPTED;
    return POLL_RESULT_FAILED;
}

static int poll_descriptor_failed(short revents) {
    return (revents & (POLLERR | POLLHUP | POLLNVAL)) != 0;
}

static u64 next_poll_retry_ms(u64 delay) {
    if (delay >= POLL_RETRY_MAX_MS / 2UL) return POLL_RETRY_MAX_MS;
    return delay * 2UL;
}

static u64 recover_poll_delay(u64 delay) {
    sys_nanosleep((s64)(delay * 1000000UL));
    return next_poll_retry_ms(delay);
}

static void schedule_power_event_retry(const char *reason) {
    if (power_event_fd >= 0) sys_close(power_event_fd);
    power_event_fd = -1;
    if (power_event_retry_count >= AUX_RETRY_LIMIT) {
        power_event_disabled = 1;
        log_text("power_uevent result=degraded reason=");
        log_text(reason);
        log_text("\n");
        return;
    }
    next_power_event_retry = boot_ms() + power_event_retry_ms;
    power_event_retry_count++;
    log_text("power_uevent result=retry reason=");
    log_text(reason);
    log_text(" delay_ms=");
    log_number(power_event_retry_ms);
    log_text(" attempt=");
    log_number(power_event_retry_count);
    log_text("\n");
    power_event_retry_ms = next_retry_delay(power_event_retry_ms);
}

static void try_power_event_open(void) {
    u64 now;
    int reopened;
    if (power_event_fd >= 0 || power_event_disabled) return;
    now = boot_ms();
    if (now < next_power_event_retry) return;
    reopened = open_power_events();
    if (reopened < 0) {
        schedule_power_event_retry("open-failed");
        return;
    }
    power_event_fd = reopened;
    if (power_event_retry_count)
        log_text("power_uevent result=recovered\n");
    next_power_event_retry = 0;
}

static void schedule_storage_signal_retry(const char *reason) {
    if (storage_signal_fd >= 0) sys_close(storage_signal_fd);
    storage_signal_fd = -1;
    if (!STORAGE_READY_SIGNAL[0] || storage_ready ||
        storage_signal_retry_count >= AUX_RETRY_LIMIT) {
        storage_signal_disabled = 1;
        log_text("storage_signal result=degraded reason=");
        log_text(reason);
        log_text("\n");
        return;
    }
    next_storage_signal_retry = boot_ms() + storage_signal_retry_ms;
    storage_signal_retry_count++;
    log_text("storage_signal result=retry reason=");
    log_text(reason);
    log_text(" delay_ms=");
    log_number(storage_signal_retry_ms);
    log_text(" attempt=");
    log_number(storage_signal_retry_count);
    log_text("\n");
    storage_signal_retry_ms = next_retry_delay(storage_signal_retry_ms);
}

static void try_storage_signal_open(void) {
    u64 now;
    long reopened;
    if (storage_signal_fd >= 0 || storage_signal_disabled || storage_ready)
        return;
    if (!STORAGE_READY_SIGNAL[0]) {
        storage_signal_disabled = 1;
        return;
    }
    now = boot_ms();
    if (now < next_storage_signal_retry) return;
    reopened = fixed_open(STORAGE_READY_SIGNAL, O_RDWR | O_NONBLOCK);
    if (reopened < 0) {
        schedule_storage_signal_retry("open-failed");
        return;
    }
    storage_signal_fd = (int)reopened;
    if (storage_signal_retry_count)
        log_text("storage_signal result=recovered\n");
    next_storage_signal_retry = 0;
}

static int is_power_supply_uevent(const char *event, u64 length) {
    u64 offset = 0;
    while (offset < length) {
        const char *field = event + offset;
        u64 field_length = string_length(field);
        if (string_equal(field, "SUBSYSTEM=power_supply")) return 1;
        offset += field_length + 1U;
    }
    return 0;
}

static void mark_first_frame(void) {
    long fd = fixed_create(FIRST_FRAME_MARKER,
                           O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) {
        sys_close((int)fd);
        BIRD_PROFILE_FIRST_FRAME_MARKED();
    }
}

static int write_exact(int fd, const char *buffer, u64 length) {
    while (length) {
        long written = sys_write(fd, buffer, length);
        if (written <= 0) return -1;
        buffer += written;
        length -= (u64)written;
    }
    return 0;
}

static int path_matches(const char *line, u32 length, const char *path) {
    u32 i;
    for (i = 0; i < length; i++) {
        BIRD_PROFILE_DEEP_STRING_BYTE();
        BIRD_PROFILE_DEEP_STRING_BYTE();
        if (!path[i] || path[i] != line[i]) return 0;
    }
    BIRD_PROFILE_DEEP_STRING_BYTE();
    return path[length] == 0;
}

static int bitmap_is_favorite(const u8 *bitmap, u32 catalog_index) {
    return (bitmap[catalog_index >> 3] &
            (u8)(1U << (catalog_index & 7U))) != 0;
}

static void bitmap_set_favorite(u8 *bitmap, u32 catalog_index, int enabled) {
    u8 mask = (u8)(1U << (catalog_index & 7U));
    if (enabled)
        bitmap[catalog_index >> 3] |= mask;
    else
        bitmap[catalog_index >> 3] &= (u8)~mask;
}

static int is_favorite(u32 catalog_index) {
    return bitmap_is_favorite(favorites, catalog_index);
}

static void set_favorite(u32 catalog_index, int enabled) {
    bitmap_set_favorite(favorites, catalog_index, enabled);
}

static u32 favorite_catalog_index(u32 ordinal) {
    u32 catalog_index;
    for (catalog_index = 0; catalog_index < CATALOG_ENTRY_COUNT; catalog_index++) {
        BIRD_PROFILE_DEEP_CATALOG_ITERATION();
        if (!is_favorite(catalog_index)) continue;
        if (!ordinal) return catalog_index;
        ordinal--;
    }
    return CATALOG_ENTRY_COUNT;
}

static int match_favorite_path(const char *line, u32 length, u8 *bitmap,
                               u32 *count) {
    u32 catalog_index;
    for (catalog_index = 0; catalog_index < CATALOG_ENTRY_COUNT; catalog_index++) {
        BIRD_PROFILE_DEEP_CATALOG_ITERATION();
        if (!path_matches(line, length, catalog_entries[catalog_index].path)) continue;
        if (!bitmap_is_favorite(bitmap, catalog_index)) {
            bitmap_set_favorite(bitmap, catalog_index, 1);
            (*count)++;
        }
        return 1;
    }
    return 0;
}

static void log_favorite_line_issue(u64 line_number, const char *reason,
                                    u64 path_bytes) {
    log_text("favorites_line line=");
    log_number(line_number);
    log_text(" result=ignored reason=");
    log_text(reason);
    log_text(" bytes=");
    log_number(path_bytes);
    log_text("\n");
}

static int favorite_line_well_formed(const char *line, u32 length) {
    u32 i;
    if (!length || line[0] != '/') return 0;
    for (i = 0; i < length; i++) {
        u8 byte = (u8)line[i];
        if (byte < 32U || byte == 127U) return 0;
    }
    return 1;
}

static void load_favorite_line(const char *line, u32 stored_length,
                               u64 raw_length, u64 line_number,
                               int overflow, char last_byte, u8 *bitmap,
                               u32 *count) {
    u64 path_bytes = raw_length;
    u32 path_length = stored_length;

    /* Accept a single CR only as the terminator of a CRLF file. */
    if (path_bytes && last_byte == '\r') path_bytes--;
    if (!overflow && path_length && line[path_length - 1U] == '\r')
        path_length--;

    if (overflow || path_bytes > CATALOG_PATH_MAX_BYTES) {
        log_favorite_line_issue(line_number, "over-limit", path_bytes);
        return;
    }
    if (!favorite_line_well_formed(line, path_length)) {
        log_favorite_line_issue(line_number,
                                path_length ? "malformed" : "empty",
                                path_bytes);
        return;
    }
    if (!match_favorite_path(line, path_length, bitmap, count))
        log_favorite_line_issue(line_number, "not-in-catalog", path_bytes);
}

static void clear_favorites(void) {
    u32 i;
    for (i = 0; i < sizeof(favorites); i++) favorites[i] = 0;
    favorite_count = 0;
}

static void schedule_favorites_retry(const char *stage, long error) {
    u64 now = boot_ms();

    clear_favorites();
    favorites_loaded = 0;
    next_favorites_retry = now + favorites_retry_ms;
    if (favorites_retry_count != (u32)-1) favorites_retry_count++;
    log_text("favorites_load boot_ms=");
    log_number(now);
    log_text(" result=retry stage=");
    log_text(stage);
    log_text(" errno=");
    log_number((u64)-error);
    log_text(" delay_ms=");
    log_number(favorites_retry_ms);
    log_text(" attempt=");
    log_number(favorites_retry_count);
    log_text("\n");
    if (favorites_retry_ms < FAVORITES_RETRY_MAX_MS / 2UL)
        favorites_retry_ms *= 2UL;
    else
        favorites_retry_ms = FAVORITES_RETRY_MAX_MS;
}

static void finish_favorites_load(const u8 *bitmap, u32 count,
                                  const char *result) {
    u32 i;
    for (i = 0; i < sizeof(favorites); i++) favorites[i] = bitmap[i];
    favorite_count = count;
    favorites_loaded = 1;
    next_favorites_retry = 0;
    favorites_retry_ms = FAVORITES_RETRY_INITIAL_MS;
    favorites_retry_count = 0;
    log_text("favorites_load boot_ms=");
    log_number(boot_ms());
    log_text(" result=");
    log_text(result);
    log_text(" count=");
    log_number(favorite_count);
    log_text("\n");
}

static void load_favorites(void) {
    char chunk[512];
    /* One extra byte permits a maximum-sized CRLF line. Paths need no NUL. */
    char line[CATALOG_PATH_MAX_BYTES + 1U];
    u8 candidate[(CATALOG_ENTRY_COUNT + 7U) / 8U];
    u32 candidate_count = 0;
    u32 line_length = 0;
    u64 raw_length = 0;
    u64 line_number = 1;
    int overflow = 0;
    char last_byte = 0;
    u32 i;
    u64 now;
    long fd;
    long count;

    if (favorites_loaded) return;
    if (!storage_ready) {
        log_text("favorites_load boot_ms=");
        log_number(boot_ms());
        log_text(" result=deferred-storage\n");
        return;
    }
    now = boot_ms();
    if (now < next_favorites_retry) return;
    for (i = 0; i < sizeof(candidate); i++) candidate[i] = 0;

    fd = fixed_open(FAVORITES_PATH, O_RDONLY);
    if (fd < 0) {
        if (fd == -ENOENT) {
            finish_favorites_load(candidate, 0, "new");
            return;
        }
        schedule_favorites_retry("open", fd);
        return;
    }

    for (;;) {
        long offset;
        count = sys_read((int)fd, chunk, sizeof(chunk));
        if (count == -EINTR) continue;
        if (count <= 0) break;
        for (offset = 0; offset < count; offset++) {
            char c = chunk[offset];
            if (c == '\n') {
                load_favorite_line(line, line_length, raw_length, line_number,
                                   overflow, last_byte, candidate,
                                   &candidate_count);
                line_length = 0;
                raw_length = 0;
                overflow = 0;
                last_byte = 0;
                line_number++;
            } else {
                raw_length++;
                last_byte = c;
                if (line_length < sizeof(line))
                    line[line_length++] = c;
                else
                    overflow = 1;
            }
        }
    }
    if (count < 0) {
        sys_close((int)fd);
        schedule_favorites_retry("read", count);
        return;
    }
    if (raw_length || overflow)
        load_favorite_line(line, line_length, raw_length, line_number,
                           overflow, last_byte, candidate, &candidate_count);
    sys_close((int)fd);
    finish_favorites_load(candidate, candidate_count, "ready");
}

static int save_ui_resume(void) {
    struct ui_resume_state state;
    long fd;
    state.magic = UI_RESUME_MAGIC;
    state.view = view;
    if (view == VIEW_MEDIA_ENTRIES)
        state.active_index = active_media_category;
    else if (view == VIEW_MEDIA_CATEGORIES)
        state.active_index = media_section;
    else
        state.active_index = active_system;
    state.selection = selection;

    fd = fixed_create(UI_RESUME_PATH, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return -1;
    if (write_exact((int)fd, (const char *)&state, sizeof(state)) < 0) {
        sys_close((int)fd);
        fixed_unlink(UI_RESUME_PATH);
        return -1;
    }
    sys_close((int)fd);
    BIRD_PROFILE_RESUME_COMMITTED();
    log_text("ui_resume_save boot_ms=");
    log_number(boot_ms());
    log_text(" view=");
    log_number(view);
    log_text(" active_index=");
    log_number(state.active_index);
    log_text(" selection=");
    log_number(selection);
    log_text(" result=ready\n");
    return 0;
}

static void preserve_early_handoff_state(void) {
#ifdef PERSIST_UI_STATE
    (void)save_ui_resume();
#endif
}

static void write_handoff_action(int action) {
#ifdef HANDOFF_ACTION_PATH
    char value[3];
    long fd;
    if (action < ACTION_LAUNCH || action > ACTION_PORTMASTER) return;
    value[0] = (char)('0' + action / 10);
    value[1] = (char)('0' + action % 10);
    value[2] = '\n';
    fd = fixed_create(HANDOFF_ACTION_PATH,
                      O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return;
    (void)sys_write((int)fd, value, sizeof(value));
    sys_close((int)fd);
#else
    (void)action;
#endif
}

static u32 media_category_count(void);

static int load_ui_resume(void) {
    struct ui_resume_state state;
    long fd = fixed_open(UI_RESUME_PATH, O_RDONLY);
    long count;
    if (fd < 0) return 0;
    count = sys_read((int)fd, &state, sizeof(state));
    sys_close((int)fd);
    fixed_unlink(UI_RESUME_PATH);

    if (count != (long)sizeof(state) || state.magic != UI_RESUME_MAGIC)
        return 0;
    if (state.view == VIEW_MAIN || state.view == VIEW_PLAY) {
        if (state.selection >= 4U) return 0;
    } else if (state.view == VIEW_SYSTEMS) {
        if (state.selection >= CATALOG_SYSTEM_COUNT) return 0;
    } else if (state.view == VIEW_GAMES) {
        if (state.active_index >= CATALOG_SYSTEM_COUNT ||
            state.selection >= catalog_systems[state.active_index].count)
            return 0;
    } else if (state.view == VIEW_FAVORITES) {
        load_favorites();
        if (favorites_loaded) {
            if (!favorite_count) state.selection = 0;
            else if (state.selection >= favorite_count)
                state.selection = favorite_count - 1U;
        }
    } else if (state.view == VIEW_MEDIA_ENTRIES) {
        if (state.active_index >= CATALOG_MEDIA_CATEGORY_COUNT ||
            state.selection >= catalog_media_categories[state.active_index].count)
            return 0;
    } else if (state.view == VIEW_MEDIA_CATEGORIES) {
        if (state.active_index < CATALOG_MEDIA_SECTION_LISTEN ||
            state.active_index > CATALOG_MEDIA_SECTION_WATCH)
            return 0;
        media_section = state.active_index;
        if (state.selection >= media_category_count()) return 0;
    } else {
        return 0;
    }

    view = state.view;
    if (view == VIEW_GAMES)
        active_system = state.active_index;
    else if (view == VIEW_MEDIA_ENTRIES) {
        active_media_category = state.active_index;
        media_section = catalog_media_categories[active_media_category].section;
    } else if (view == VIEW_MEDIA_CATEGORIES)
        media_section = state.active_index;
    selection = state.selection;
    selected_status = "RETURNED TO PREVIOUS SCREEN";
    log_text("ui_resume_load boot_ms=");
    log_number(boot_ms());
    log_text(" view=");
    log_number(view);
    log_text(" active_index=");
    log_number(state.active_index);
    log_text(" selection=");
    log_number(selection);
    log_text(" result=ready\n");
    return 1;
}

static int save_favorites(void) {
    u32 catalog_index;
    long fd;

    /* Never replace a known-good file from an empty or partially read view. */
    if (!favorites_loaded) {
        log_text("favorites_save result=blocked reason=load-incomplete\n");
        return -1;
    }
    fd = fixed_create(FAVORITES_TEMP,
                      O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return -1;

    for (catalog_index = 0; catalog_index < CATALOG_ENTRY_COUNT; catalog_index++) {
        const char *path;
        BIRD_PROFILE_DEEP_CATALOG_ITERATION();
        if (!is_favorite(catalog_index)) continue;
        path = catalog_entries[catalog_index].path;
        if (!catalog_path_supported(path)) {
            sys_close((int)fd);
            fixed_unlink(FAVORITES_TEMP);
            return -1;
        }
        if (write_exact((int)fd, path, string_length(path)) < 0 ||
            write_exact((int)fd, "\n", 1) < 0) {
            sys_close((int)fd);
            fixed_unlink(FAVORITES_TEMP);
            return -1;
        }
    }
    if (sys_fsync((int)fd) < 0) {
        sys_close((int)fd);
        fixed_unlink(FAVORITES_TEMP);
        return -1;
    }
    sys_close((int)fd);
    if (fixed_rename(FAVORITES_TEMP, FAVORITES_PATH) < 0) {
        fixed_unlink(FAVORITES_TEMP);
        return -1;
    }
    return 0;
}

static void save_recent(const struct catalog_entry *entry) {
    long fd;
    int result = -1;
    if (!catalog_path_supported(entry->path)) {
        log_text("recent_save boot_ms=");
        log_number(boot_ms());
        log_text(" result=unsupported-path\n");
        return;
    }
    fd = fixed_create(RECENT_TEMP, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) {
        if (write_exact((int)fd, entry->path, string_length(entry->path)) == 0 &&
            write_exact((int)fd, "\n", 1) == 0)
            result = 0;
        sys_close((int)fd);
    }
    if (!result && fixed_rename(RECENT_TEMP, RECENT_PATH) == 0) {
        log_text("recent_save boot_ms=");
        log_number(boot_ms());
        log_text(" result=ready path=");
        log_text(entry->path);
        log_text("\n");
        return;
    }
    fixed_unlink(RECENT_TEMP);
    log_text("recent_save boot_ms=");
    log_number(boot_ms());
    log_text(" result=failed\n");
}

static int framebuffer_field_is(struct fb_bitfield field, u32 offset,
                                u32 length) {
    return field.offset == offset && field.length == length &&
           field.msb_right == 0U;
}

static void configure_framebuffer_path(void) {
    framebuffer_path = FRAMEBUFFER_PATH_DIAGNOSTIC;
    if (fb_var.xres != RG34XX_FB_WIDTH ||
        fb_var.yres != RG34XX_FB_HEIGHT ||
        fb_var.xres_virtual != RG34XX_FB_WIDTH ||
        fb_var.yres_virtual != RG34XX_FB_HEIGHT ||
        fb_var.xoffset != 0U || fb_var.yoffset != 0U ||
        fb_var.bits_per_pixel != 32U || fb_var.grayscale != 0U ||
        fb_var.nonstd != 0U ||
        !framebuffer_field_is(fb_var.red, 16U, 8U) ||
        !framebuffer_field_is(fb_var.green, 8U, 8U) ||
        !framebuffer_field_is(fb_var.blue, 0U, 8U) ||
        !framebuffer_field_is(fb_var.transp, 24U, 8U) ||
        fb_fix.type != FB_TYPE_PACKED_PIXELS ||
        fb_fix.visual != FB_VISUAL_TRUECOLOR ||
        fb_fix.xpanstep != 1U || fb_fix.ypanstep != 1U ||
        fb_fix.ywrapstep != 0U ||
        fb_fix.line_length != RG34XX_FB_STRIDE ||
        fb_fix.smem_len != RG34XX_FB_BYTES)
        return;
    framebuffer_path = FRAMEBUFFER_PATH_RG34XX_XRGB8888;
}

static u32 scale_component(u8 value, struct fb_bitfield field) {
    if (!field.length) return 0;
    u64 maximum = field.length >= 32 ? 0xffffffffUL : ((1UL << field.length) - 1UL);
    return (u32)((((u64)value * maximum + 127UL) / 255UL) << field.offset);
}

static u32 color(u8 red, u8 green, u8 blue) {
    if (framebuffer_path == FRAMEBUFFER_PATH_RG34XX_XRGB8888)
        return 0xff000000U | ((u32)red << 16) | ((u32)green << 8) |
               (u32)blue;
    return scale_component(red, fb_var.red) | scale_component(green, fb_var.green) |
           scale_component(blue, fb_var.blue) | scale_component(255, fb_var.transp);
}

static void store_pixel(int x, int framebuffer_y, u32 value) {
    u32 bytes = (fb_var.bits_per_pixel + 7U) / 8U;
    u64 offset = (u64)framebuffer_y * fb_fix.line_length + (u64)(x + (int)fb_var.xoffset) * bytes;
    if (offset + bytes > fb_fix.smem_len) return;
    BIRD_PROFILE_DEEP_FALLBACK_PIXEL_STORE(bytes);
    if (bytes == 2) {
        fb[offset] = (u8)value;
        fb[offset + 1] = (u8)(value >> 8);
    } else if (bytes == 3) {
        fb[offset] = (u8)value;
        fb[offset + 1] = (u8)(value >> 8);
        fb[offset + 2] = (u8)(value >> 16);
    } else if (bytes == 4) {
        fb[offset] = (u8)value;
        fb[offset + 1] = (u8)(value >> 8);
        fb[offset + 2] = (u8)(value >> 16);
        fb[offset + 3] = (u8)(value >> 24);
    }
}

static void pixel(int x, int y, u32 value) {
    BIRD_PROFILE_DEEP_FALLBACK_PIXEL_CHECK();
    if (x < 0 || y < 0 || (u32)x >= fb_var.xres || (u32)y >= fb_var.yres) return;

    /* Preserve the recovery path's historical all-pages write when a
     * noncanonical framebuffer exposes multiple pages or a selected offset. */
    store_pixel(x, y, value);
    if (fb_var.yres_virtual >= fb_var.yres * 2U)
        store_pixel(x, y + (int)fb_var.yres, value);
    else if (fb_var.yoffset)
        store_pixel(x, y + (int)fb_var.yoffset, value);
}

static void rg34xx_fill_span(volatile u32 *target, u32 pixels, u32 value) {
    u64 pair = (u64)value | ((u64)value << 32);
    volatile u64 *wide;

    if (((u64)target & 7UL) && pixels) {
        *target++ = value;
        pixels--;
        BIRD_PROFILE_DEEP_FAST_U32_STORES(1U);
    }

    wide = (volatile u64 *)target;
    while (pixels >= 8U) {
        wide[0] = pair;
        wide[1] = pair;
        wide[2] = pair;
        wide[3] = pair;
        wide += 4;
        pixels -= 8U;
        BIRD_PROFILE_DEEP_FAST_U64_STORES(4U);
    }
    while (pixels >= 2U) {
        *wide++ = pair;
        pixels -= 2U;
        BIRD_PROFILE_DEEP_FAST_U64_STORES(1U);
    }
    if (pixels) {
        *(volatile u32 *)wide = value;
        BIRD_PROFILE_DEEP_FAST_U32_STORES(1U);
    }
}

static void rg34xx_rectangle(int x, int y, int width, int height, u32 value) {
    int first_x = x < 0 ? 0 : x;
    int first_y = y < 0 ? 0 : y;
    int last_x = x + width > (int)RG34XX_FB_WIDTH
                     ? (int)RG34XX_FB_WIDTH : x + width;
    int last_y = y + height > (int)RG34XX_FB_HEIGHT
                     ? (int)RG34XX_FB_HEIGHT : y + height;
    volatile u8 *row;
    u32 pixels;

    if (width <= 0 || height <= 0 || first_x >= last_x || first_y >= last_y)
        return;
    pixels = (u32)(last_x - first_x);
    row = fb + (u64)(u32)first_y * RG34XX_FB_STRIDE +
          (u64)(u32)first_x * RG34XX_FB_BYTES_PER_PIXEL;
    BIRD_PROFILE_DEEP_FAST_RECTANGLE((u64)(u32)(last_y - first_y));
    while (first_y++ < last_y) {
        rg34xx_fill_span((volatile u32 *)row, pixels, value);
        row += RG34XX_FB_STRIDE;
    }
}

static void rectangle(int x, int y, int width, int height, u32 value) {
    int yy;
    int xx;
    BIRD_PROFILE_RECTANGLE(x, y, width, height);
    BIRD_PROFILE_DEEP_RECTANGLE();
    if (framebuffer_path == FRAMEBUFFER_PATH_RG34XX_XRGB8888) {
        rg34xx_rectangle(x, y, width, height, value);
        return;
    }
    BIRD_PROFILE_DEEP_FALLBACK_RECTANGLE();
    for (yy = y; yy < y + height; yy++)
        for (xx = x; xx < x + width; xx++) pixel(xx, yy, value);
}

static const struct glyph *find_glyph(char c) {
    u64 index;
    BIRD_PROFILE_DEEP_GLYPH_LOOKUP();
    for (index = 0; index < sizeof(font) / sizeof(font[0]); index++) {
        BIRD_PROFILE_DEEP_GLYPH_SCAN();
        if (font[index].c == c) return &font[index];
    }
    return &font[0];
}

static void draw_character(int x, int y, char c, int scale, u32 value) {
    const struct glyph *glyph = find_glyph(c);
    int row;
    int column;
    for (row = 0; row < 7; row++) {
        for (column = 0; column < 5; column++) {
            if (glyph->row[row] & (1U << (4 - column)))
                rectangle(x + column * scale, y + row * scale, scale, scale, value);
        }
    }
}

static void draw_text(int x, int y, const char *text, int scale, u32 value) {
    while (*text) {
        draw_character(x, y, *text++, scale, value);
        x += 6 * scale;
    }
}

static void draw_text_limited(int x, int y, const char *text, int scale, u32 value, u32 limit) {
    while (*text && limit) {
        draw_character(x, y, *text++, scale, value);
        x += 6 * scale;
        limit--;
    }
}

static void draw_battery_percent(u32 charging, u32 idle) {
    char label[5];
    u32 length = 0;
    int value = battery_percent;
    if (value < 0 || value > 100) return;
    if (value == 100) {
        label[length++] = '1';
        label[length++] = '0';
        label[length++] = '0';
    } else if (value >= 10) {
        label[length++] = (char)('0' + value / 10);
        label[length++] = (char)('0' + value % 10);
    } else {
        label[length++] = (char)('0' + value);
    }
    label[length++] = '%';
    label[length] = 0;
    draw_text((int)fb_var.xres - 32 - (int)(length * 12U), 30, label, 2,
              charging_state == 1 ? charging : idle);
}

static u32 media_category_first(void) {
    if (media_section == CATALOG_MEDIA_SECTION_LISTEN)
        return CATALOG_LISTEN_CATEGORY_FIRST;
    if (media_section == CATALOG_MEDIA_SECTION_READ)
        return CATALOG_READ_CATEGORY_FIRST;
    return CATALOG_WATCH_CATEGORY_FIRST;
}

static u32 media_category_count(void) {
    if (media_section == CATALOG_MEDIA_SECTION_LISTEN)
        return CATALOG_LISTEN_CATEGORY_COUNT;
    if (media_section == CATALOG_MEDIA_SECTION_READ)
        return CATALOG_READ_CATEGORY_COUNT;
    return CATALOG_WATCH_CATEGORY_COUNT;
}

static const char *media_section_name(void) {
    if (media_section == CATALOG_MEDIA_SECTION_LISTEN) return "LISTEN";
    if (media_section == CATALOG_MEDIA_SECTION_READ) return "READ";
    return "WATCH";
}

static const char *empty_media_text(void) {
    if (media_section == CATALOG_MEDIA_SECTION_LISTEN) return "NOTHING TO LISTEN TO YET";
    if (media_section == CATALOG_MEDIA_SECTION_READ) return "NOTHING TO READ YET";
    return "NOTHING TO WATCH YET";
}

static u32 current_count(void) {
    if (view == VIEW_MAIN) return 4U;
    if (view == VIEW_PLAY) return 4U;
    if (view == VIEW_SYSTEMS) return CATALOG_SYSTEM_COUNT;
    if (view == VIEW_GAMES) return catalog_systems[active_system].count;
    if (view == VIEW_FAVORITES) return favorite_count;
    if (view == VIEW_MEDIA_CATEGORIES) return media_category_count();
    if (view == VIEW_MEDIA_ENTRIES)
        return catalog_media_categories[active_media_category].count;
    return 0U;
}

#ifdef BIRD_PROFILE
static u32 bird_profile_viewport_first(u32 current_view,
                                       u32 current_selection) {
    u32 rows = (current_view == VIEW_SYSTEMS ||
                current_view == VIEW_MEDIA_CATEGORIES)
                   ? SYSTEM_ROWS : GAME_ROWS;
    if (current_view != VIEW_SYSTEMS && current_view != VIEW_GAMES &&
        current_view != VIEW_FAVORITES &&
        current_view != VIEW_MEDIA_CATEGORIES &&
        current_view != VIEW_MEDIA_ENTRIES)
        return 0U;
    return current_selection < rows ? 0U : current_selection - rows + 1U;
}
#endif

static u32 current_catalog_index(void) {
    if (view == VIEW_GAMES) {
        const struct catalog_system *system = &catalog_systems[active_system];
        if (selection < system->count) return system->first + selection;
    }
    if (view == VIEW_FAVORITES && selection < favorite_count)
        return favorite_catalog_index(selection);
    return CATALOG_ENTRY_COUNT;
}

static void draw_screen(void) {
    u32 background = color(10, 14, 20);
    u32 panel = color(19, 26, 36);
    u32 selected = color(232, 166, 48);
    u32 primary = color(244, 246, 248);
    u32 muted = color(139, 151, 166);
    u32 i;

    rectangle(0, 0, (int)fb_var.xres, (int)fb_var.yres, background);
    rectangle(0, 0, (int)fb_var.xres, 92, panel);
    rectangle(0, (int)fb_var.yres - 66, (int)fb_var.xres, 66, panel);
    rectangle(32, 86, 656, 3, selected);

    if (view == VIEW_MAIN || view == VIEW_PLAY) {
        const char **items = view == VIEW_MAIN ? menu_item : play_item;
        draw_text(32, 22, view == VIEW_MAIN ? "BIRDOS // RG34-SP" : "PLAY", 4, primary);
        draw_text(34, 62,
                  view == VIEW_MAIN ? "BESPOKE CONSOLE" : "LIBRARY // TOOLS // POWER",
                  2, muted);
        for (i = 0; i < 4U; i++) {
            int y = 122 + (int)i * 64;
            if (i == selection) {
                rectangle(92, y - 10, 492, 52, selected);
                draw_text(108, y + 4, ">", 3, background);
                draw_text(148, y, items[i], 4, background);
            } else {
                draw_text(148, y, items[i], 4, primary);
            }
        }
    } else if (view == VIEW_SYSTEMS) {
        u32 first = selection < SYSTEM_ROWS ? 0U : selection - SYSTEM_ROWS + 1U;
        draw_text(32, 22, "GAMES", 4, primary);
        draw_text(34, 62, "EMBEDDED CATALOG // NO SCAN", 2, muted);
        for (i = 0; i < SYSTEM_ROWS && first + i < CATALOG_SYSTEM_COUNT; i++) {
            u32 system_index = first + i;
            int y = 102 + (int)i * 38;
            if (system_index == selection) {
                rectangle(32, y - 7, 656, 31, selected);
                draw_text(44, y, ">", 2, background);
                draw_text_limited(72, y, catalog_systems[system_index].name,
                                  2, background, 50U);
            } else {
                draw_text_limited(72, y, catalog_systems[system_index].name,
                                  2, primary, 50U);
            }
        }
    } else if (view == VIEW_GAMES || view == VIEW_FAVORITES) {
        u32 count = current_count();
        u32 first = selection < GAME_ROWS ? 0U : selection - GAME_ROWS + 1U;
        if (view == VIEW_GAMES) {
            const struct catalog_system *system = &catalog_systems[active_system];
            draw_text(32, 22, system->name, 4, primary);
            draw_text(34, 62, "CACHED GAMES // STORAGE ASYNC", 2, muted);
        } else {
            draw_text(32, 22, "FAVORITES", 4, primary);
            draw_text(34, 62, "EXACT PATH CACHE // NO SCAN", 2, muted);
        }
        if (view == VIEW_FAVORITES && !count)
            draw_text(72, 160, favorites_loaded ? "NO FAVORITES YET" : "LOADING FAVORITES", 3, primary);
        for (i = 0; i < GAME_ROWS && first + i < count; i++) {
            u32 catalog_index = view == VIEW_GAMES
                                    ? catalog_systems[active_system].first + first + i
                                    : favorite_catalog_index(first + i);
            const struct catalog_entry *entry = &catalog_entries[catalog_index];
            int y = 102 + (int)i * 38;
            if (first + i == selection) {
                rectangle(32, y - 7, 656, 31, selected);
                draw_text(44, y, ">", 2, background);
                draw_text_limited(72, y, entry->name, 2, background, 50U);
            } else {
                draw_text_limited(72, y, entry->name, 2, primary, 50U);
            }
            if (view == VIEW_GAMES && is_favorite(catalog_index))
                draw_text(654, y, "*", 2, first + i == selection ? background : selected);
        }
    } else if (view == VIEW_MEDIA_CATEGORIES) {
        u32 count = current_count();
        u32 section_first = media_category_first();
        u32 first = selection < SYSTEM_ROWS ? 0U : selection - SYSTEM_ROWS + 1U;
        draw_text(32, 22, media_section_name(), 4, primary);
        draw_text(34, 62, "EMBEDDED MEDIA CATALOG // NO SCAN", 2, muted);
        if (!count) draw_text(72, 160, empty_media_text(), 3, primary);
        for (i = 0; i < SYSTEM_ROWS && first + i < count; i++) {
            u32 category_index = section_first + first + i;
            int y = 102 + (int)i * 38;
            if (first + i == selection) {
                rectangle(32, y - 7, 656, 31, selected);
                draw_text(44, y, ">", 2, background);
                draw_text_limited(72, y, catalog_media_categories[category_index].name,
                                  2, background, 50U);
            } else {
                draw_text_limited(72, y, catalog_media_categories[category_index].name,
                                  2, primary, 50U);
            }
        }
    } else if (view == VIEW_MEDIA_ENTRIES) {
        const struct catalog_media_category *category =
            &catalog_media_categories[active_media_category];
        u32 first = selection < GAME_ROWS ? 0U : selection - GAME_ROWS + 1U;
        draw_text(32, 22, category->name, 4, primary);
        draw_text(34, 62, "CACHED MEDIA // STORAGE ASYNC", 2, muted);
        for (i = 0; i < GAME_ROWS && first + i < category->count; i++) {
            const struct catalog_media_entry *entry =
                &catalog_media_entries[category->first + first + i];
            int y = 102 + (int)i * 38;
            if (first + i == selection) {
                rectangle(32, y - 7, 656, 31, selected);
                draw_text(44, y, ">", 2, background);
                draw_text_limited(72, y, entry->name, 2, background, 50U);
            } else {
                draw_text_limited(72, y, entry->name, 2, primary, 50U);
            }
        }
    }

    draw_battery_percent(selected, muted);

    draw_text(32, (int)fb_var.yres - 54, selected_status, 2, muted);
    if (view == VIEW_MAIN)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE   A SELECT   B RELOAD", 2, primary);
    else if (view == VIEW_PLAY)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE   A SELECT   B BACK", 2, primary);
    else if (view == VIEW_GAMES)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE  L1 R1 PAGE  A LAUNCH  Y FAV  B BACK", 2, primary);
    else if (view == VIEW_FAVORITES)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE  L1 R1 PAGE  A LAUNCH  Y REMOVE  B BACK", 2, primary);
    else if (view == VIEW_SYSTEMS)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE  L1 R1 PAGE  A OPEN  B BACK", 2, primary);
    else if (view == VIEW_MEDIA_CATEGORIES)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE  L1 R1 PAGE  A OPEN  B BACK", 2, primary);
    else if (view == VIEW_MEDIA_ENTRIES)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE  L1 R1 PAGE  A PLAY  B BACK", 2, primary);
    else
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE   A OPEN   B BACK", 2, primary);
#ifndef BIRD_HOST_TEST
    __asm__ volatile("dmb ishst" ::: "memory");
#endif
    BIRD_PROFILE_BARRIER();
}

static int write_content_request(u8 launch_kind, const char *core,
                                 const char *name, const char *path,
                                 const char *status) {
    char kind[2];
    long fd;
    if (!catalog_path_supported(path)) {
        selected_status = "UNSUPPORTED CONTENT PATH";
        log_text("launch_request result=unsupported-path\n");
        return ACTION_NONE;
    }
    fd = fixed_create(LAUNCH_REQUEST, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        selected_status = "LAUNCH REQUEST FAILED";
        log_text("launch_request result=open-failed\n");
        return ACTION_NONE;
    }

    kind[0] = (char)('0' + launch_kind);
    kind[1] = '\n';
    if (sys_write((int)fd, kind, sizeof(kind)) != (long)sizeof(kind) ||
        sys_write((int)fd, core, string_length(core)) != (long)string_length(core) ||
        sys_write((int)fd, "\n", 1) != 1 ||
        sys_write((int)fd, name, string_length(name)) != (long)string_length(name) ||
        sys_write((int)fd, "\n", 1) != 1 ||
        sys_write((int)fd, path, string_length(path)) != (long)string_length(path) ||
        sys_write((int)fd, "\n", 1) != 1) {
        sys_close((int)fd);
        selected_status = "LAUNCH REQUEST WRITE FAILED";
        log_text("launch_request result=write-failed\n");
        return ACTION_NONE;
    }
    sys_close((int)fd);
    if (save_ui_resume() < 0) {
        fixed_unlink(LAUNCH_REQUEST);
        selected_status = "RETURN STATE SAVE FAILED";
        log_text("launch_request result=resume-save-failed\n");
        return ACTION_NONE;
    }
    selected_status = status;
    log_text("launch_request boot_ms=");
    log_number(boot_ms());
    log_text(" kind=");
    log_number(launch_kind);
    log_text(" core=");
    log_text(core);
    log_text(" path=");
    log_text(path);
    log_text(" result=ready\n");
    return ACTION_LAUNCH;
}

static int launch_catalog_entry(u32 catalog_index) {
    const struct catalog_entry *entry;
    const struct catalog_system *system;
    const char *path;
    long fd;
    int action;
    if (catalog_index >= CATALOG_ENTRY_COUNT) return ACTION_NONE;
    entry = &catalog_entries[catalog_index];
    system = &catalog_systems[entry->system];
    path = resolve_live_path(entry->path);
    fd = path ? fixed_open(path, O_RDONLY | O_NONBLOCK) : -1;
    log_text("rom_test boot_ms=");
    log_number(boot_ms());
    log_text(" path=");
    log_text(entry->path);
    if (path != entry->path) {
        log_text(" live=");
        log_text(path ? path : "path-too-long");
    }
    if (fd >= 0) {
        sys_close((int)fd);
        log_text(" result=ready\n");
        action = write_content_request(system->launch_kind, system->core,
                                       entry->name, entry->path, "STARTING GAME");
        if (action == ACTION_LAUNCH) save_recent(entry);
        return action;
    }
    selected_status = "WAITING FOR ROM STORAGE";
    log_text(" result=not-ready\n");
    return ACTION_NONE;
}

static int launch_media_entry(u32 category_index, u32 item_index) {
    const struct catalog_media_category *category;
    const struct catalog_media_entry *entry;
    const char *path;
    u32 entry_index;
    long fd;
    if (category_index >= CATALOG_MEDIA_CATEGORY_COUNT)
        return ACTION_NONE;
    category = &catalog_media_categories[category_index];
    if (item_index >= category->count) return ACTION_NONE;
    entry_index = category->first + item_index;
    entry = &catalog_media_entries[entry_index];
    path = resolve_live_path(entry->path);
    fd = path ? fixed_open(path, O_RDONLY | O_NONBLOCK) : -1;
    log_text("media_test boot_ms=");
    log_number(boot_ms());
    log_text(" path=");
    log_text(entry->path);
    if (path != entry->path) {
        log_text(" live=");
        log_text(path ? path : "path-too-long");
    }
    if (fd >= 0) {
        sys_close((int)fd);
        log_text(" result=ready\n");
        return write_content_request(category->launch_kind, category->core,
                                     entry->name, entry->path, "STARTING MEDIA");
    }
    selected_status = "WAITING FOR MEDIA STORAGE";
    log_text(" result=not-ready\n");
    return ACTION_NONE;
}

static void log_pending_identity(const struct pending_launch_state *pending) {
    if (pending->kind == PENDING_LAUNCH_GAME) {
        log_text(" kind=game catalog_index=");
        log_number(pending->index);
    } else if (pending->kind == PENDING_LAUNCH_MEDIA) {
        log_text(" kind=media category_index=");
        log_number(pending->active_index);
        log_text(" selection=");
        log_number(pending->index);
    }
}

static void queue_game_launch(u32 catalog_index) {
    pending_launch.kind = PENDING_LAUNCH_GAME;
    pending_launch.index = catalog_index;
    pending_launch.active_index = 0U;
    selected_status = "GAME QUEUED // STORAGE MOUNTING";
    log_text("pending_launch boot_ms=");
    log_number(boot_ms());
    log_text(" event=queued");
    log_pending_identity(&pending_launch);
    log_text("\n");
}

static void queue_media_launch(u32 category_index, u32 item_index) {
    pending_launch.kind = PENDING_LAUNCH_MEDIA;
    pending_launch.index = item_index;
    pending_launch.active_index = category_index;
    selected_status = "MEDIA QUEUED // STORAGE MOUNTING";
    log_text("pending_launch boot_ms=");
    log_number(boot_ms());
    log_text(" event=queued");
    log_pending_identity(&pending_launch);
    log_text("\n");
}

static void cancel_pending_launch(const char *reason) {
    if (pending_launch.kind == PENDING_LAUNCH_NONE) return;
    log_text("pending_launch boot_ms=");
    log_number(boot_ms());
    log_text(" event=cancelled reason=");
    log_text(reason);
    log_pending_identity(&pending_launch);
    log_text("\n");
    pending_launch.kind = PENDING_LAUNCH_NONE;
    pending_launch.index = 0U;
    pending_launch.active_index = 0U;
}

static int dispatch_pending_launch(void) {
    struct pending_launch_state request;
    int action;
    if (pending_launch.kind == PENDING_LAUNCH_NONE) return ACTION_NONE;
    request = pending_launch;
    pending_launch.kind = PENDING_LAUNCH_NONE;
    pending_launch.index = 0U;
    pending_launch.active_index = 0U;
    log_text("pending_launch boot_ms=");
    log_number(boot_ms());
    log_text(" event=dispatch");
    log_pending_identity(&request);
    log_text("\n");
    if (request.kind == PENDING_LAUNCH_GAME)
        action = launch_catalog_entry(request.index);
    else if (request.kind == PENDING_LAUNCH_MEDIA)
        action = launch_media_entry(request.active_index, request.index);
    else
        action = ACTION_NONE;
    if (action == ACTION_NONE) BIRD_PROFILE_CANCEL_SELECTION();
    log_text("pending_launch boot_ms=");
    log_number(boot_ms());
    log_text(" event=dispatch-result action=");
    log_number((u64)action);
    log_text("\n");
    return action;
}

static void toggle_current_favorite(void) {
    u32 catalog_index = current_catalog_index();
    int was_favorite;
    if (catalog_index >= CATALOG_ENTRY_COUNT) {
        selected_status = "NO FAVORITE SELECTED";
        BIRD_PROFILE_RENDER(PROFILE_RENDER_STATUS);
        draw_screen();
        return;
    }
    if (!storage_ready || !favorites_loaded) {
        selected_status = "WAITING FOR FAVORITES STORAGE";
        BIRD_PROFILE_RENDER(PROFILE_RENDER_STATUS);
        draw_screen();
        return;
    }
    if (!catalog_path_supported(catalog_entries[catalog_index].path)) {
        selected_status = "UNSUPPORTED FAVORITE PATH";
        log_text("favorite_toggle result=unsupported-path\n");
        BIRD_PROFILE_RENDER(PROFILE_RENDER_STATUS);
        draw_screen();
        return;
    }

    was_favorite = is_favorite(catalog_index);
    set_favorite(catalog_index, !was_favorite);
    if (was_favorite)
        favorite_count--;
    else
        favorite_count++;

    if (save_favorites() < 0) {
        set_favorite(catalog_index, was_favorite);
        if (was_favorite)
            favorite_count++;
        else
            favorite_count--;
        selected_status = "FAVORITES SAVE FAILED";
        log_text("favorite_toggle result=save-failed path=");
    } else {
        selected_status = was_favorite ? "FAVORITE REMOVED" : "FAVORITE ADDED";
        log_text(was_favorite ? "favorite_toggle result=removed path="
                              : "favorite_toggle result=added path=");
        if (view == VIEW_FAVORITES && selection >= favorite_count)
            selection = favorite_count ? favorite_count - 1U : 0U;
    }
    log_text(catalog_entries[catalog_index].path);
    log_text("\n");
    preserve_early_handoff_state();
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STATUS);
    draw_screen();
}

static int select_current(void) {
    int action = ACTION_NONE;
#ifdef BIRD_PROFILE
    u32 profile_original_view = view;
#endif
    if (view == VIEW_MAIN) {
        if (selection == 0U) {
            view = VIEW_PLAY;
            selection = 0U;
            selected_status = "PLAY LIBRARY READY";
        } else if (selection == 1U) {
            media_section = CATALOG_MEDIA_SECTION_LISTEN;
            view = VIEW_MEDIA_CATEGORIES;
            selection = 0U;
            selected_status = "AUDIO CATALOG READY FROM FIRMWARE";
        } else if (selection == 2U) {
            media_section = CATALOG_MEDIA_SECTION_READ;
            view = VIEW_MEDIA_CATEGORIES;
            selection = 0U;
            selected_status = "READING LIBRARY READY FROM FIRMWARE";
        } else {
            media_section = CATALOG_MEDIA_SECTION_WATCH;
            view = VIEW_MEDIA_CATEGORIES;
            selection = 0U;
            selected_status = "VIDEO CATALOG READY FROM FIRMWARE";
        }
    } else if (view == VIEW_PLAY) {
        if (selection == 0U) {
            view = VIEW_SYSTEMS;
            selection = 0U;
            selected_status = "CATALOG READY FROM FIRMWARE";
        } else if (selection == 1U) {
            view = VIEW_FAVORITES;
            selection = 0U;
            selected_status = favorites_loaded ? "FAVORITES READY" : "FAVORITES LOAD WITH STORAGE";
        } else if (selection == 2U) {
            selected_status = "CONNECTING PORTMASTER";
            if (save_ui_resume() == 0)
                action = ACTION_PORTMASTER;
            else
                selected_status = "RETURN STATE SAVE FAILED";
        } else {
            selected_status = "SHUTTING DOWN";
            action = ACTION_SHUTDOWN;
        }
    } else if (view == VIEW_SYSTEMS) {
        active_system = selection;
        view = VIEW_GAMES;
        selection = 0U;
        selected_status = storage_ready ? "ROM STORAGE READY" : "CATALOG READY // ROMS MOUNTING";
    } else if (view == VIEW_GAMES || view == VIEW_FAVORITES) {
        u32 catalog_index = current_catalog_index();
        if (catalog_index < CATALOG_ENTRY_COUNT) {
            /* A retained initramfs process normally learns storage through the
             * FIFO. Revalidate synchronously on selection as a recovery path:
             * a missed/stale readiness edge must never strand a real file. */
            if (!storage_ready) {
                next_storage_probe = 0;
                probe_storage();
            }
            if (storage_ready) {
                cancel_pending_launch("direct-selection");
                action = launch_catalog_entry(catalog_index);
            } else {
                queue_game_launch(catalog_index);
            }
        } else {
            selected_status = "NO GAME SELECTED";
        }
    } else if (view == VIEW_MEDIA_CATEGORIES) {
        if (selection < media_category_count()) {
            active_media_category = media_category_first() + selection;
            view = VIEW_MEDIA_ENTRIES;
            selection = 0U;
            selected_status = storage_ready ? "MEDIA STORAGE READY" : "CATALOG READY // MEDIA MOUNTING";
        } else {
            selected_status = empty_media_text();
        }
    } else if (view == VIEW_MEDIA_ENTRIES) {
        if (active_media_category < CATALOG_MEDIA_CATEGORY_COUNT &&
            selection < catalog_media_categories[active_media_category].count) {
            if (!storage_ready) {
                next_storage_probe = 0;
                probe_storage();
            }
            if (storage_ready) {
                cancel_pending_launch("direct-selection");
                action = launch_media_entry(active_media_category, selection);
            } else {
                queue_media_launch(active_media_category, selection);
            }
        }
    }
    if (action == ACTION_NONE) preserve_early_handoff_state();
    BIRD_PROFILE_RENDER(view != profile_original_view
                            ? PROFILE_RENDER_VIEW_CHANGE
                            : PROFILE_RENDER_STATUS);
    draw_screen();
    return action;
}

static void move_selection(int direction, u32 steps) {
    u32 count = current_count();
#ifdef BIRD_PROFILE
    u32 profile_old_first = bird_profile_viewport_first(view, selection);
#endif
    cancel_pending_launch("navigation");
    BIRD_PROFILE_CANCEL_SELECTION();
    if (!count) return;
    while (steps--) {
        if (direction < 0) selection = selection > 0U ? selection - 1U : count - 1U;
        if (direction > 0) selection = selection + 1U < count ? selection + 1U : 0U;
    }
    selected_status = "DIRECT EVDEV INPUT READY";
    preserve_early_handoff_state();
    BIRD_PROFILE_RENDER(profile_old_first !=
                                bird_profile_viewport_first(view, selection)
                            ? PROFILE_RENDER_VIEWPORT_CHANGE
                            : PROFILE_RENDER_SELECTION_MOVEMENT);
    draw_screen();
}

static int handle_direction(int direction) {
    move_selection(direction, 1U);
    return 0;
}

static int handle_back(void) {
    cancel_pending_launch("back");
    BIRD_PROFILE_CANCEL_SELECTION();
    if (view == VIEW_FAVORITES) {
        view = VIEW_PLAY;
        selection = 1U;
        selected_status = "PLAY LIBRARY READY";
        preserve_early_handoff_state();
        BIRD_PROFILE_RENDER(PROFILE_RENDER_VIEW_CHANGE);
        draw_screen();
        return 0;
    }
    if (view == VIEW_GAMES) {
        view = VIEW_SYSTEMS;
        selection = active_system;
        selected_status = "CATALOG READY FROM FIRMWARE";
        preserve_early_handoff_state();
        BIRD_PROFILE_RENDER(PROFILE_RENDER_VIEW_CHANGE);
        draw_screen();
        return 0;
    }
    if (view == VIEW_SYSTEMS) {
        view = VIEW_PLAY;
        selection = 0U;
        selected_status = "PLAY LIBRARY READY";
        preserve_early_handoff_state();
        BIRD_PROFILE_RENDER(PROFILE_RENDER_VIEW_CHANGE);
        draw_screen();
        return 0;
    }
    if (view == VIEW_PLAY) {
        view = VIEW_MAIN;
        selection = 0U;
        selected_status = "DIRECT FRAMEBUFFER READY";
        preserve_early_handoff_state();
        BIRD_PROFILE_RENDER(PROFILE_RENDER_VIEW_CHANGE);
        draw_screen();
        return 0;
    }
    if (view == VIEW_MEDIA_ENTRIES) {
        view = VIEW_MEDIA_CATEGORIES;
        selection = active_media_category - media_category_first();
        selected_status = "MEDIA CATALOG READY FROM FIRMWARE";
        preserve_early_handoff_state();
        BIRD_PROFILE_RENDER(PROFILE_RENDER_VIEW_CHANGE);
        draw_screen();
        return 0;
    }
    if (view == VIEW_MEDIA_CATEGORIES) {
        view = VIEW_MAIN;
        selection = media_section == CATALOG_MEDIA_SECTION_LISTEN
                        ? 1U
                        : (media_section == CATALOG_MEDIA_SECTION_READ ? 2U : 3U);
        selected_status = "DIRECT FRAMEBUFFER READY";
        preserve_early_handoff_state();
        BIRD_PROFILE_RENDER(PROFILE_RENDER_VIEW_CHANGE);
        draw_screen();
        return 0;
    }
    return ACTION_RELOAD;
}

static void reset_input_latches(void) {
    axis_x = 0;
    axis_y = 0;
}

static void abandon_input(void) {
    reset_input_latches();
    if (input_fd >= 0) sys_close(input_fd);
    input_fd = -1;
}

static int update_axis_latch(int *latch, int value) {
    int next = value < 0 ? -1 : (value > 0 ? 1 : 0);
    int direction = next && !*latch ? next : 0;
    *latch = next;
    return direction;
}

static int handle_event(const struct input_event *event) {
    if (event->type == EV_KEY && event->value == 1) {
        u16 select_button = h700_input ? BTN_EAST : BTN_SOUTH;
        u16 back_button = h700_input ? BTN_SOUTH : BTN_EAST;
        u16 favorite_button = h700_input ? BTN_NORTH : BUTTON_Y;
        u16 page_up_button = h700_input ? H700_BTN_TL : MUOS_BTN_TL;
        u16 page_down_button = h700_input ? H700_BTN_TR : MUOS_BTN_TR;

        if (event->code == select_button) {
#ifdef BIRD_PROFILE
            int action;
            BIRD_PROFILE_MARK_SELECTION();
            action = select_current();
            if (action == ACTION_NONE &&
                pending_launch.kind == PENDING_LAUNCH_NONE)
                BIRD_PROFILE_CANCEL_SELECTION();
            return action;
#else
            return select_current();
#endif
        }
        if (event->code == back_button) return handle_back();
        if (h700_input && (event->code == BTN_DPAD_UP ||
                           event->code == BTN_DPAD_LEFT)) {
            return handle_direction(-1);
        }
        if (h700_input && (event->code == BTN_DPAD_DOWN ||
                           event->code == BTN_DPAD_RIGHT)) {
            return handle_direction(1);
        }
        if ((view == VIEW_GAMES || view == VIEW_FAVORITES) &&
            event->code == favorite_button) {
            toggle_current_favorite();
            return 0;
        }
        if ((view == VIEW_SYSTEMS || view == VIEW_GAMES || view == VIEW_FAVORITES ||
             view == VIEW_MEDIA_CATEGORIES || view == VIEW_MEDIA_ENTRIES) &&
            event->code == page_up_button) {
            move_selection(-1,
                           view == VIEW_SYSTEMS || view == VIEW_MEDIA_CATEGORIES
                               ? SYSTEM_ROWS
                               : GAME_ROWS);
            return 0;
        }
        if ((view == VIEW_SYSTEMS || view == VIEW_GAMES || view == VIEW_FAVORITES ||
             view == VIEW_MEDIA_CATEGORIES || view == VIEW_MEDIA_ENTRIES) &&
            event->code == page_down_button) {
            move_selection(1,
                           view == VIEW_SYSTEMS || view == VIEW_MEDIA_CATEGORIES
                               ? SYSTEM_ROWS
                               : GAME_ROWS);
            return 0;
        }
    }

    if (event->type == EV_ABS) {
        if (event->code == ABS_HAT0X) {
            int direction = update_axis_latch(&axis_x, event->value);
            if (direction) handle_direction(direction);
        }
        if (event->code == ABS_HAT0Y) {
            int direction = update_axis_latch(&axis_y, event->value);
            if (direction) handle_direction(direction);
        }
    }
    return 0;
}

static void probe_storage(void) {
    long fd;
    u64 now;
    if (storage_ready) return;
    now = boot_ms();
    if (now < next_storage_probe) return;
    next_storage_probe = now + 50UL;
    refresh_path_anchors();
    /*
     * An initramfs-owned Bird must retain both directory descriptors before
     * the special-mount handoff and switch_root. The marker is the bounded
     * readiness acknowledgement consumed by bird-early.sh; it never makes the
     * already-interactive menu wait for storage. The initramfs process opens
     * the final tree below /sysroot after prepare_sysroot moves it; a normal
     * root process uses the ordinary absolute paths.
     */
    if (storage_dir_fd < 0 || config_dir_fd < 0) return;
    fd = fixed_open(ROM_ROOT, O_RDONLY | O_NONBLOCK);
    if (fd < 0) return;
    sys_close((int)fd);
    if (STORAGE_ANCHOR_MARKER[0]) {
        fd = fixed_create(STORAGE_ANCHOR_MARKER,
                          O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0) return;
        (void)sys_write((int)fd, "ready\n", 6U);
        sys_close((int)fd);
        log_text("storage_anchor_ready boot_ms=");
        log_number(now);
        log_text("\n");
    }
    storage_ready = 1;
    storage_signal_disabled = 1;
    if (storage_signal_fd >= 0) {
        sys_close(storage_signal_fd);
        storage_signal_fd = -1;
    }
    {
#ifdef BIRD_PROFILE
        int profile_was_favorites_loaded = favorites_loaded;
#endif
        load_favorites();
        if (view == VIEW_FAVORITES) {
            if (!favorite_count)
                selection = 0U;
            else if (selection >= favorite_count)
                selection = favorite_count - 1U;
            BIRD_PROFILE_RENDER(!profile_was_favorites_loaded && favorites_loaded
                                    ? PROFILE_RENDER_FAVORITES_COMPLETION
                                    : PROFILE_RENDER_STATUS);
            draw_screen();
        }
    }
    log_text("storage_ready boot_ms=");
    log_number(now);
    log_text(" path=" ROM_ROOT " ui_redraw=");
    log_text(view == VIEW_FAVORITES ? "favorites" : "deferred");
    log_text("\n");
}

static void set_input_path(int index) {
    static const char prefix[] = "/dev/input/event";
    int position = 0;
    while (prefix[position]) {
        input_path[position] = prefix[position];
        position++;
    }
    if (index >= 10) input_path[position++] = (char)('0' + index / 10);
    input_path[position++] = (char)('0' + index % 10);
    input_path[position] = 0;
}

static int open_fixed_input(void) {
    char name[128];
    u64 deadline = boot_ms() + DEVICE_WAIT_MS;
    int index;

    while (boot_ms() < deadline) {
        for (index = 0; index < INPUT_EVENT_SCAN_COUNT; index++) {
            set_input_path(index);
            input_fd = (int)fixed_open(input_path, O_RDONLY | O_NONBLOCK);
            if (input_fd < 0) continue;

            name[0] = 0;
            sys_ioctl(input_fd, EVIOCGNAME_128, name);
            name[127] = 0;
            if (string_equal(name, "muOS-Keys")) {
                h700_input = 0;
                goto found;
            }
            if (string_equal(name, "H700 Gamepad")) {
                h700_input = 1;
                goto found;
            }
            sys_close(input_fd);
            input_fd = -1;
        }
        sys_nanosleep(1000000L);
    }
    if (input_fd < 0) {
        log_text("error wait fixed RG34XX-SP input\n");
        return -1;
    }

found:
    BIRD_PROFILE_INPUT_OPENED();
    reset_input_latches();
    log_text("input ");
    log_text(input_path);
    log_text(" name=");
    log_text(name[0] ? name : "unknown");
    log_text(" map=");
    log_text(h700_input ? "mainline-h700" : "vendor-muos");
    log_text(" ready_boot_ms=");
    log_number(boot_ms());
    log_text("\n");

    return 0;
}

static int application(void) {
#ifdef BIRD_PROFILE
    u64 profile_started_ns = bird_profile_now_ns();
#endif
    u64 started = boot_ms();
    u64 deadline;
    u64 poll_retry_ms = POLL_RETRY_INITIAL_MS;
    u32 poll_error_count = 0;
    int exit_action = ACTION_NONE;
    BIRD_PROFILE_APPLICATION_ENTRY(profile_started_ns);
    log_text("direct launcher start boot_ms=");
    log_number(started);
    log_text("\n");

    refresh_path_anchors();
    log_text("path_anchors runtime=");
    log_text(runtime_dir_fd >= 0 ? "ready" : "missing");
    log_text(" input=");
    log_text(input_dir_fd >= 0 ? "ready" : "missing");
    log_text(" power=");
    log_text(power_dir_fd >= 0 ? "ready" : "missing");
    log_text(" storage=");
    log_text(storage_dir_fd >= 0 ? "ready" : "missing");
    log_text(" config=");
    log_text(config_dir_fd >= 0 ? "ready" : "missing");
    log_text("\n");

    deadline = boot_ms() + DEVICE_WAIT_MS;
    while (boot_ms() < deadline) {
        fb_fd = (int)sys_open("/dev/fb0", O_RDWR);
        if (fb_fd >= 0) break;
        sys_nanosleep(1000000L);
    }
    if (fb_fd < 0) {
        log_text("error wait /dev/fb0\n");
        return 2;
    }
    if (sys_ioctl(fb_fd, FBIOGET_VSCREENINFO, &fb_var) < 0 ||
        sys_ioctl(fb_fd, FBIOGET_FSCREENINFO, &fb_fix) < 0) {
        log_text("error framebuffer ioctl\n");
        sys_close(fb_fd);
        return 3;
    }
    configure_framebuffer_path();

    log_text("framebuffer visible=");
    log_number(fb_var.xres);
    log_text("x");
    log_number(fb_var.yres);
    log_text(" virtual=");
    log_number(fb_var.xres_virtual);
    log_text("x");
    log_number(fb_var.yres_virtual);
    log_text(" bpp=");
    log_number(fb_var.bits_per_pixel);
    log_text(" stride=");
    log_number(fb_fix.line_length);
    log_text(" bytes=");
    log_number(fb_fix.smem_len);
    log_text(framebuffer_path == FRAMEBUFFER_PATH_RG34XX_XRGB8888
                 ? " path=rg34xx-xrgb8888 page=fixed-0\n"
                 : " path=diagnostic-fallback\n");

    if (fb_var.bits_per_pixel != 16 && fb_var.bits_per_pixel != 24 && fb_var.bits_per_pixel != 32) {
        log_text("error unsupported framebuffer depth\n");
        sys_close(fb_fd);
        return 4;
    }

    fb = (volatile u8 *)sys_mmap(fb_fix.smem_len);
    if ((u64)fb >= (u64)-4095L) {
        log_text("error framebuffer mmap\n");
        sys_close(fb_fd);
        return 5;
    }

    /*
     * Paint before input discovery so an absent or late joypad can never keep
     * the kernel boot logo on screen.  The ready marker remains below the
     * input gate: the watchdog is cancelled only when the menu is usable.
    */
    load_ui_resume();
#ifdef PERSIST_UI_STATE
    /* load_ui_resume consumes its file. Keep the bridge transaction armed
     * even when no button is pressed between two process owners or a device
     * reconnect causes the supervisor to recover Bird. */
    (void)save_ui_resume();
#endif
    try_power_event_open();
    charging_state = read_charging_state();
    battery_percent = read_battery_percent();
    log_text("power battery_state=");
    log_text(charging_state == 1 ? "charging" :
             (charging_state == 0 ? "not-charging" : "unavailable"));
    log_text(" uevent=");
    log_text(power_event_fd >= 0 ? "ready" :
             (power_event_disabled ? "degraded" : "retrying"));
    log_text(" percent=");
    if (battery_percent >= 0)
        log_number((u64)battery_percent);
    else
        log_text("unavailable");
    log_text(" boot_ms=");
    log_number(boot_ms());
    log_text("\n");
    BIRD_PROFILE_RENDER(PROFILE_RENDER_STARTUP_FULL);
    draw_screen();
    log_text("first_frame_visible boot_ms=");
    log_number(boot_ms());
    log_text(" input_ready=0\n");

    if (open_fixed_input() < 0) {
        sys_munmap((void *)fb, fb_fix.smem_len);
        sys_close(fb_fd);
        return 6;
    }
    if (STORAGE_READY_SIGNAL[0]) {
        try_storage_signal_open();
        log_text("storage_signal=");
        log_text(storage_signal_fd >= 0 ? "ready" :
                 (storage_signal_disabled ? "degraded" : "retrying"));
        log_text(" boot_ms=");
        log_number(boot_ms());
        log_text("\n");
    }
    mark_first_frame();
    BIRD_PROFILE_EMIT_STARTUP();
    log_text("first_frame boot_ms=");
    log_number(boot_ms());
    log_text(" input_ready=1 catalog_entries=");
    log_number(CATALOG_ENTRY_COUNT);
    log_text(" media_entries=");
    log_number(CATALOG_MEDIA_ENTRY_COUNT);
    log_text("\n");

    while (exit_action == ACTION_NONE) {
        struct pollfd polls[3];
        struct timespec poll_timeout;
        struct timespec *timeout = 0;
        struct input_event event;
        long count;
        long poll_result;
        u64 timeout_ms = (u64)-1;
        u64 now;
        u64 poll_count = 1;
        int power_index = -1;
        int storage_index = -1;

        probe_storage();
        if (storage_ready && !favorites_loaded) {
            int was_loaded = favorites_loaded;
            load_favorites();
            if (!was_loaded && favorites_loaded && view == VIEW_FAVORITES) {
                if (!favorite_count)
                    selection = 0U;
                else if (selection >= favorite_count)
                    selection = favorite_count - 1U;
                BIRD_PROFILE_RENDER(PROFILE_RENDER_FAVORITES_COMPLETION);
                draw_screen();
            }
        }
        if (!storage_ready) try_storage_signal_open();
        try_power_event_open();
        polls[0].fd = input_fd;
        polls[0].events = POLLIN;
        polls[0].revents = 0;
        if (power_event_fd >= 0) {
            power_index = (int)poll_count;
            polls[poll_count].fd = power_event_fd;
            polls[poll_count].events = POLLIN;
            polls[poll_count].revents = 0;
            poll_count++;
        }
        if (storage_ready && pending_launch.kind != PENDING_LAUNCH_NONE) {
            /* Sample already-buffered B/navigation before automatic dispatch. */
            timeout_ms = 0;
        } else if (!storage_ready) {
            if (storage_signal_fd >= 0) {
                storage_index = (int)poll_count;
                polls[poll_count].fd = storage_signal_fd;
                polls[poll_count].events = POLLIN;
                polls[poll_count].revents = 0;
                poll_count++;
            }
            /* The FIFO remains the immediate path. A bounded probe also runs
             * until success so a lost writer edge cannot create a permanent
             * "queued" state. It stops forever once storage is retained. */
            timeout_ms = 50UL;
        }
        now = boot_ms();
        if (power_event_fd < 0 && !power_event_disabled) {
            u64 retry_wait = next_power_event_retry > now
                                 ? next_power_event_retry - now : 0;
            if (retry_wait < timeout_ms) timeout_ms = retry_wait;
        }
        if (!storage_ready && storage_signal_fd < 0 &&
            !storage_signal_disabled) {
            u64 retry_wait = next_storage_signal_retry > now
                                 ? next_storage_signal_retry - now : 0;
            if (retry_wait < timeout_ms) timeout_ms = retry_wait;
        }
        if (storage_ready && !favorites_loaded) {
            u64 retry_wait = next_favorites_retry > now
                                 ? next_favorites_retry - now : 0;
            if (retry_wait < timeout_ms) timeout_ms = retry_wait;
        }
        if (timeout_ms != (u64)-1) {
            poll_timeout.sec = (s64)(timeout_ms / 1000UL);
            poll_timeout.nsec = (s64)((timeout_ms % 1000UL) * 1000000UL);
            timeout = &poll_timeout;
        }
        poll_result = sys_ppoll(polls, poll_count, timeout);
        if (classify_poll_result(poll_result) == POLL_RESULT_INTERRUPTED)
            continue;
        if (classify_poll_result(poll_result) == POLL_RESULT_FAILED) {
            if (power_index >= 0)
                schedule_power_event_retry("ppoll-error");
            if (storage_index >= 0)
                schedule_storage_signal_retry("ppoll-error");
            poll_error_count++;
            log_text("ppoll result=error errno=");
            log_number((u64)-poll_result);
            log_text(" retry_ms=");
            log_number(poll_retry_ms);
            log_text(" attempt=");
            log_number(poll_error_count);
            log_text("\n");
            if (poll_error_count >= AUX_RETRY_LIMIT) {
                log_text("ppoll result=fatal action=reload\n");
                exit_action = ACTION_RECOVER;
                break;
            }
            poll_retry_ms = recover_poll_delay(poll_retry_ms);
            continue;
        }
        poll_retry_ms = POLL_RETRY_INITIAL_MS;
        poll_error_count = 0;
        if (power_index >= 0 &&
            !poll_descriptor_failed(polls[power_index].revents)) {
            power_event_retry_count = 0;
            power_event_retry_ms = AUX_RETRY_INITIAL_MS;
        }
        if (storage_index >= 0 &&
            !poll_descriptor_failed(polls[storage_index].revents)) {
            storage_signal_retry_count = 0;
            storage_signal_retry_ms = AUX_RETRY_INITIAL_MS;
        }

        if (poll_descriptor_failed(polls[0].revents)) {
            log_text("input reconnect boot_ms=");
            log_number(boot_ms());
            log_text("\n");
            abandon_input();
            if (open_fixed_input() < 0) {
                exit_action = ACTION_RECOVER;
                break;
            }
            continue;
        }

        if (storage_index >= 0 &&
            poll_descriptor_failed(polls[storage_index].revents)) {
            schedule_storage_signal_retry(
                (polls[storage_index].revents & POLLNVAL) ? "poll-nval" :
                ((polls[storage_index].revents & POLLHUP) ? "poll-hup" :
                                                           "poll-error"));
        } else if (storage_index >= 0 &&
                   (polls[storage_index].revents & POLLIN)) {
            char storage_event[32];
            for (;;) {
                count = sys_read(storage_signal_fd, storage_event,
                                 sizeof(storage_event));
                if (count > 0) continue;
                if (count == -EINTR) continue;
                if (count < 0 && count != -EAGAIN)
                    schedule_storage_signal_retry("read-error");
                break;
            }
            next_storage_probe = 0;
            log_text("storage_signal_received boot_ms=");
            log_number(boot_ms());
            log_text("\n");
            probe_storage();
        }

        if (power_index >= 0 &&
            poll_descriptor_failed(polls[power_index].revents)) {
            schedule_power_event_retry(
                (polls[power_index].revents & POLLNVAL) ? "poll-nval" :
                ((polls[power_index].revents & POLLHUP) ? "poll-hup" :
                                                         "poll-error"));
        } else if (power_index >= 0 && (polls[power_index].revents & POLLIN)) {
            char uevent[2049];
            int previous = charging_state;
            int previous_percent = battery_percent;
            int power_changed = 0;
            for (;;) {
                count = sys_read(power_event_fd, uevent, sizeof(uevent) - 1U);
                if (count > 0) {
                    uevent[count] = 0;
                    if (is_power_supply_uevent(uevent, (u64)count))
                        power_changed = 1;
                    continue;
                }
                if (count == -EINTR) continue;
                if (count < 0 && count != -EAGAIN)
                    schedule_power_event_retry("read-error");
                break;
            }
            if (power_changed) {
                charging_state = read_charging_state();
                battery_percent = read_battery_percent();
            }
            if (power_changed && (charging_state != previous ||
                                  battery_percent != previous_percent)) {
                log_text("power battery_state=");
                log_text(charging_state == 1 ? "charging" :
                         (charging_state == 0 ? "not-charging" : "unavailable"));
                log_text(" boot_ms=");
                log_number(boot_ms());
                log_text(" percent=");
                if (battery_percent >= 0)
                    log_number((u64)battery_percent);
                else
                    log_text("unavailable");
                log_text("\n");
                BIRD_PROFILE_RENDER(PROFILE_RENDER_BATTERY);
                draw_screen();
            }
        }

        for (;;) {
            count = sys_read(input_fd, &event, sizeof(event));
            if (count == (long)sizeof(event)) {
                BIRD_PROFILE_BEGIN_EVENT();
                exit_action = handle_event(&event);
                BIRD_PROFILE_FINISH_EVENT();
                if (exit_action != ACTION_NONE) break;
                continue;
            }
            if (count == -EINTR) continue;
            if (count < 0 && count != -EAGAIN) {
                log_text("input read-error errno=");
                log_number((u64)-count);
                log_text("\n");
                abandon_input();
                if (open_fixed_input() < 0)
                    exit_action = ACTION_RECOVER;
            } else if (count > 0) {
                log_text("input read-error reason=partial-event\n");
            }
            if (exit_action != ACTION_NONE)
                break;
            break;
        }
        if (exit_action == ACTION_NONE && storage_ready &&
            pending_launch.kind != PENDING_LAUNCH_NONE)
            exit_action = dispatch_pending_launch();
    }

    if (exit_action == ACTION_LAUNCH)
        log_text("exit reason=launch-request boot_ms=");
    else if (exit_action == ACTION_SHUTDOWN)
        log_text("exit reason=shutdown-request boot_ms=");
    else if (exit_action == ACTION_PORTMASTER)
        log_text("exit reason=portmaster-request boot_ms=");
    else if (exit_action == ACTION_RELOAD)
        log_text("exit reason=b-button boot_ms=");
    else
        log_text("exit reason=runtime-recovery boot_ms=");
    log_number(boot_ms());
    log_text("\n");
    write_handoff_action(exit_action);
    if (power_event_fd >= 0) sys_close(power_event_fd);
    if (storage_signal_fd >= 0) sys_close(storage_signal_fd);
    sys_close(input_fd);
    sys_munmap((void *)fb, fb_fix.smem_len);
    sys_close(fb_fd);
    if (config_dir_fd >= 0) sys_close(config_dir_fd);
    if (storage_dir_fd >= 0) sys_close(storage_dir_fd);
    if (power_dir_fd >= 0) sys_close(power_dir_fd);
    if (input_dir_fd >= 0) sys_close(input_dir_fd);
    if (runtime_dir_fd >= 0) sys_close(runtime_dir_fd);
    BIRD_PROFILE_EXIT_AND_EMIT();
    if (exit_action == ACTION_LAUNCH || exit_action == ACTION_SHUTDOWN ||
        exit_action == ACTION_PORTMASTER || exit_action == ACTION_RELOAD ||
        exit_action == ACTION_RECOVER)
        return exit_action;
    return 0;
}

#ifndef BIRD_HOST_TEST
__attribute__((noreturn, visibility("default"))) void _start(void) {
    sys_exit(application());
}
#endif
