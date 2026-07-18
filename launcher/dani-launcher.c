/*
 * Dani's fixed-device RG34XX-SP launcher.
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

#include "catalog.generated.h"

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_EXCL 0200
#define O_TRUNC 01000
#define O_NONBLOCK 04000
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1

#define FBIOGET_VSCREENINFO 0x4600
#define FBIOGET_FSCREENINFO 0x4602
#define EVIOCGNAME_128 0x80804506

#define EV_KEY 0x01
#define EV_ABS 0x03
#define BTN_SOUTH 304
#define BTN_EAST 305
#define BUTTON_Y 306
#define BTN_TL 308
#define BTN_TR 309
#define ABS_HAT0X 16
#define ABS_HAT0Y 17

#define CLOCK_BOOTTIME 7
#define DEVICE_WAIT_MS 5000UL
#define BOOT_ANIMATION_MS 1600UL
#define INPUT_PATH "/dev/input/event1"
#define ROM_ROOT "/mnt/mmc/ROMS"
#define LAUNCH_REQUEST "/run/muos/dani-launch-request"
#define UI_RESUME_PATH "/run/muos/dani-launcher-ui-resume"
#define UI_RESUME_MAGIC 0x44414e49U
#define FAVORITES_PATH "/mnt/mmc/MUOS/bespoke-launcher/favorites.txt"
#define FAVORITES_TEMP "/mnt/mmc/MUOS/bespoke-launcher/favorites.tmp"
#define RECENT_PATH "/mnt/mmc/MUOS/bespoke-launcher/recent.txt"
#define RECENT_TEMP "/mnt/mmc/MUOS/bespoke-launcher/recent.tmp"
#define BOOT_EFFECT_MARKER "/run/muos/dani-boot-effects-started"
#define BOOT_SOUND_CANCEL "/run/muos/dani-boot-sound-cancel"

#define VIEW_MAIN 0U
#define VIEW_SYSTEMS 1U
#define VIEW_GAMES 2U
#define VIEW_FAVORITES 3U
#define SYSTEM_ROWS 8U
#define GAME_ROWS 8U
#define ACTION_NONE 0
#define ACTION_STOCK 1
#define ACTION_LAUNCH 10
#define ACTION_SHUTDOWN 11
#define ACTION_PORTMASTER 12

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

struct glyph {
    char c;
    u8 row[7];
};

struct ui_resume_state {
    u32 magic;
    u32 view;
    u32 active_system;
    u32 selection;
};

static struct fb_var_screeninfo fb_var;
static struct fb_fix_screeninfo fb_fix;
static volatile u8 *fb;
static int fb_fd = -1;
static int input_fd = -1;
static u32 view;
static u32 selection;
static u32 active_system;
static int axis_x;
static int axis_y;
static int storage_ready;
static int favorites_loaded;
static int boot_animation_active;
static int boot_animation_complete;
static u32 favorite_count;
static u8 favorites[(CATALOG_ENTRY_COUNT + 7U) / 8U];
static u64 boot_animation_started;
static u64 next_animation_frame;
static u64 next_storage_probe;
static u32 captured_events;
static const char *selected_status = "DIRECT FRAMEBUFFER READY";

static const char *menu_item[4] = {"GAMES", "FAVORITES", "PORTMASTER", "SHUTDOWN"};

/* Five-wide uppercase bitmap alphabet plus the exact punctuation this UI uses. */
static const struct glyph font[] = {
    {' ', {0, 0, 0, 0, 0, 0, 0}},       {'!', {4, 4, 4, 4, 4, 0, 4}},
    {'\'', {4, 4, 0, 0, 0, 0, 0}},      {'(', {2, 4, 8, 8, 8, 4, 2}},
    {')', {8, 4, 2, 2, 2, 4, 8}},       {'&', {12, 18, 20, 8, 21, 18, 13}},
    {'*', {0, 21, 14, 31, 14, 21, 0}},
    {',', {0, 0, 0, 0, 0, 4, 8}},       {'-', {0, 0, 0, 31, 0, 0, 0}},
    {'.', {0, 0, 0, 0, 0, 0, 4}},       {'/', {1, 2, 4, 8, 16, 0, 0}},
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

static long syscall6(long number, long a0, long a1, long a2, long a3, long a4, long a5) {
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x3 __asm__("x3") = a3;
    register long x4 __asm__("x4") = a4;
    register long x5 __asm__("x5") = a5;
    register long x8 __asm__("x8") = number;
    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5), "r"(x8) : "memory", "cc");
    return x0;
}

static long sys_open(const char *path, int flags) {
    return syscall6(56, AT_FDCWD, (long)path, flags, 0, 0, 0);
}

static long sys_create(const char *path, int flags, int mode) {
    return syscall6(56, AT_FDCWD, (long)path, flags, mode, 0, 0);
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

static long sys_unlink(const char *path) {
    return syscall6(35, AT_FDCWD, (long)path, 0, 0, 0, 0);
}

static long sys_rename(const char *old_path, const char *new_path) {
    return syscall6(38, AT_FDCWD, (long)old_path, AT_FDCWD, (long)new_path, 0, 0);
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
    return length;
}

static void log_text(const char *text) {
    sys_write(1, text, string_length(text));
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
    sys_write(1, &buffer[position + 1], (u64)(22 - position));
}

static void log_signed(s64 value) {
    if (value < 0) {
        log_text("-");
        log_number((u64)-value);
    } else {
        log_number((u64)value);
    }
}

static u64 boot_ms(void) {
    struct timespec now;
    if (sys_clock_gettime(&now) < 0) return 0;
    return (u64)now.sec * 1000UL + (u64)(now.nsec / 1000000L);
}

static int claim_boot_effects(void) {
    long fd = sys_create(BOOT_EFFECT_MARKER, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) return 0;
    sys_close((int)fd);
    return 1;
}

static void cancel_boot_sound(void) {
    long fd = sys_create(BOOT_SOUND_CANCEL, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) sys_close((int)fd);
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
    for (i = 0; i < length; i++)
        if (!path[i] || path[i] != line[i]) return 0;
    return path[length] == 0;
}

static int is_favorite(u32 catalog_index) {
    return (favorites[catalog_index >> 3] & (u8)(1U << (catalog_index & 7U))) != 0;
}

static void set_favorite(u32 catalog_index, int enabled) {
    u8 mask = (u8)(1U << (catalog_index & 7U));
    if (enabled)
        favorites[catalog_index >> 3] |= mask;
    else
        favorites[catalog_index >> 3] &= (u8)~mask;
}

static u32 favorite_catalog_index(u32 ordinal) {
    u32 catalog_index;
    for (catalog_index = 0; catalog_index < CATALOG_ENTRY_COUNT; catalog_index++) {
        if (!is_favorite(catalog_index)) continue;
        if (!ordinal) return catalog_index;
        ordinal--;
    }
    return CATALOG_ENTRY_COUNT;
}

static void match_favorite_path(const char *line, u32 length) {
    u32 catalog_index;
    if (!length) return;
    for (catalog_index = 0; catalog_index < CATALOG_ENTRY_COUNT; catalog_index++) {
        if (!path_matches(line, length, catalog_entries[catalog_index].path)) continue;
        if (!is_favorite(catalog_index)) {
            set_favorite(catalog_index, 1);
            favorite_count++;
        }
        return;
    }
}

static void load_favorites(void) {
    char chunk[512];
    char line[512];
    u32 line_length = 0;
    int overflow = 0;
    u32 i;
    long fd;
    long count;

    if (favorites_loaded) return;
    for (i = 0; i < sizeof(favorites); i++) favorites[i] = 0;
    favorite_count = 0;
    favorites_loaded = 1;

    fd = sys_open(FAVORITES_PATH, O_RDONLY);
    if (fd < 0) {
        log_text("favorites_load boot_ms=");
        log_number(boot_ms());
        log_text(" result=new count=0\n");
        return;
    }

    while ((count = sys_read((int)fd, chunk, sizeof(chunk))) > 0) {
        long offset;
        for (offset = 0; offset < count; offset++) {
            char c = chunk[offset];
            if (c == '\n') {
                if (!overflow) match_favorite_path(line, line_length);
                line_length = 0;
                overflow = 0;
            } else if (c != '\r') {
                if (line_length < sizeof(line))
                    line[line_length++] = c;
                else
                    overflow = 1;
            }
        }
    }
    if (line_length && !overflow) match_favorite_path(line, line_length);
    sys_close((int)fd);
    log_text("favorites_load boot_ms=");
    log_number(boot_ms());
    log_text(" result=ready count=");
    log_number(favorite_count);
    log_text("\n");
}

static int save_ui_resume(void) {
    struct ui_resume_state state;
    long fd;
    state.magic = UI_RESUME_MAGIC;
    state.view = view;
    state.active_system = active_system;
    state.selection = selection;

    fd = sys_create(UI_RESUME_PATH, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return -1;
    if (write_exact((int)fd, (const char *)&state, sizeof(state)) < 0) {
        sys_close((int)fd);
        sys_unlink(UI_RESUME_PATH);
        return -1;
    }
    sys_close((int)fd);
    log_text("ui_resume_save boot_ms=");
    log_number(boot_ms());
    log_text(" view=");
    log_number(view);
    log_text(" system=");
    log_number(active_system);
    log_text(" selection=");
    log_number(selection);
    log_text(" result=ready\n");
    return 0;
}

static int load_ui_resume(void) {
    struct ui_resume_state state;
    long fd = sys_open(UI_RESUME_PATH, O_RDONLY);
    long count;
    if (fd < 0) return 0;
    count = sys_read((int)fd, &state, sizeof(state));
    sys_close((int)fd);
    sys_unlink(UI_RESUME_PATH);

    if (count != (long)sizeof(state) || state.magic != UI_RESUME_MAGIC)
        return 0;
    if (state.view == VIEW_GAMES) {
        if (state.active_system >= CATALOG_SYSTEM_COUNT ||
            state.selection >= catalog_systems[state.active_system].count)
            return 0;
    } else if (state.view == VIEW_FAVORITES) {
        load_favorites();
        if (!favorite_count) state.selection = 0;
        else if (state.selection >= favorite_count) state.selection = favorite_count - 1U;
    } else {
        return 0;
    }

    view = state.view;
    active_system = state.active_system;
    selection = state.selection;
    selected_status = "RETURNED TO PREVIOUS SCREEN";
    log_text("ui_resume_load boot_ms=");
    log_number(boot_ms());
    log_text(" view=");
    log_number(view);
    log_text(" system=");
    log_number(active_system);
    log_text(" selection=");
    log_number(selection);
    log_text(" result=ready\n");
    return 1;
}

static int save_favorites(void) {
    u32 catalog_index;
    long fd = sys_create(FAVORITES_TEMP, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return -1;

    for (catalog_index = 0; catalog_index < CATALOG_ENTRY_COUNT; catalog_index++) {
        const char *path;
        if (!is_favorite(catalog_index)) continue;
        path = catalog_entries[catalog_index].path;
        if (write_exact((int)fd, path, string_length(path)) < 0 ||
            write_exact((int)fd, "\n", 1) < 0) {
            sys_close((int)fd);
            sys_unlink(FAVORITES_TEMP);
            return -1;
        }
    }
    if (sys_fsync((int)fd) < 0) {
        sys_close((int)fd);
        sys_unlink(FAVORITES_TEMP);
        return -1;
    }
    sys_close((int)fd);
    if (sys_rename(FAVORITES_TEMP, FAVORITES_PATH) < 0) {
        sys_unlink(FAVORITES_TEMP);
        return -1;
    }
    return 0;
}

static void save_recent(const struct catalog_entry *entry) {
    long fd = sys_create(RECENT_TEMP, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    int result = -1;
    if (fd >= 0) {
        if (write_exact((int)fd, entry->path, string_length(entry->path)) == 0 &&
            write_exact((int)fd, "\n", 1) == 0)
            result = 0;
        sys_close((int)fd);
    }
    if (!result && sys_rename(RECENT_TEMP, RECENT_PATH) == 0) {
        log_text("recent_save boot_ms=");
        log_number(boot_ms());
        log_text(" result=ready path=");
        log_text(entry->path);
        log_text("\n");
        return;
    }
    sys_unlink(RECENT_TEMP);
    log_text("recent_save boot_ms=");
    log_number(boot_ms());
    log_text(" result=failed\n");
}

static u32 scale_component(u8 value, struct fb_bitfield field) {
    if (!field.length) return 0;
    u64 maximum = field.length >= 32 ? 0xffffffffUL : ((1UL << field.length) - 1UL);
    return (u32)((((u64)value * maximum + 127UL) / 255UL) << field.offset);
}

static u32 color(u8 red, u8 green, u8 blue) {
    return scale_component(red, fb_var.red) | scale_component(green, fb_var.green) |
           scale_component(blue, fb_var.blue) | scale_component(255, fb_var.transp);
}

static void store_pixel(int x, int framebuffer_y, u32 value) {
    u32 bytes = (fb_var.bits_per_pixel + 7U) / 8U;
    u64 offset = (u64)framebuffer_y * fb_fix.line_length + (u64)(x + (int)fb_var.xoffset) * bytes;
    if (offset + bytes > fb_fix.smem_len) return;
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
    if (x < 0 || y < 0 || (u32)x >= fb_var.xres || (u32)y >= fb_var.yres) return;

    /* Paint every fixed RG34XX-SP framebuffer page so a compositor page flip
     * cannot leave the proof hidden behind the previous stock splash frame. */
    store_pixel(x, y, value);
    if (fb_var.yres_virtual >= fb_var.yres * 2U)
        store_pixel(x, y + (int)fb_var.yres, value);
    else if (fb_var.yoffset)
        store_pixel(x, y + (int)fb_var.yoffset, value);
}

static void rectangle(int x, int y, int width, int height, u32 value) {
    int yy;
    int xx;
    for (yy = y; yy < y + height; yy++)
        for (xx = x; xx < x + width; xx++) pixel(xx, yy, value);
}

static const struct glyph *find_glyph(char c) {
    u64 index;
    for (index = 0; index < sizeof(font) / sizeof(font[0]); index++)
        if (font[index].c == c) return &font[index];
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

static u32 current_count(void) {
    if (view == VIEW_MAIN) return 4U;
    if (view == VIEW_SYSTEMS) return CATALOG_SYSTEM_COUNT;
    if (view == VIEW_GAMES) return catalog_systems[active_system].count;
    if (view == VIEW_FAVORITES) return favorite_count;
    return 0U;
}

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
    rectangle(32, 86, 656, 3,
              boot_animation_complete ? selected : color(48, 58, 70));

    if (view == VIEW_MAIN) {
        draw_text(32, 22, "DANI // RG34-SP", 4, primary);
        draw_text(34, 62, "BESPOKE CONSOLE", 2, muted);
        for (i = 0; i < 4U; i++) {
            int y = 122 + (int)i * 64;
            if (i == selection) {
                rectangle(92, y - 10, 492, 52, selected);
                draw_text(108, y + 4, ">", 3, background);
                draw_text(148, y, menu_item[i], 4, background);
            } else {
                draw_text(148, y, menu_item[i], 4, primary);
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
    } else {
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
    }

    draw_text(32, (int)fb_var.yres - 54, selected_status, 2, muted);
    if (view == VIEW_MAIN)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE   A SELECT   B STOCK", 2, primary);
    else if (view == VIEW_GAMES)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE  L1 R1 PAGE  A LAUNCH  Y FAV  B BACK", 2, primary);
    else if (view == VIEW_FAVORITES)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE  L1 R1 PAGE  A LAUNCH  Y REMOVE  B BACK", 2, primary);
    else if (view == VIEW_SYSTEMS)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE  L1 R1 PAGE  A OPEN  B BACK", 2, primary);
    else
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE   A OPEN   B BACK", 2, primary);
    __asm__ volatile("dmb ishst" ::: "memory");
}

static void finish_boot_animation(const char *reason) {
    if (!boot_animation_active) return;
    boot_animation_active = 0;
    boot_animation_complete = 1;
    rectangle(32, 86, 656, 3, color(232, 166, 48));
    __asm__ volatile("dmb ishst" ::: "memory");
    log_text("boot_animation end_boot_ms=");
    log_number(boot_ms());
    log_text(" reason=");
    log_text(reason);
    log_text("\n");
}

static void animate_boot(void) {
    u64 now;
    u64 elapsed;
    u32 width;
    if (!boot_animation_active) return;
    now = boot_ms();
    if (now < next_animation_frame) return;
    elapsed = now - boot_animation_started;
    if (elapsed >= BOOT_ANIMATION_MS) {
        finish_boot_animation("complete");
        return;
    }
    width = (u32)((elapsed * 656UL) / BOOT_ANIMATION_MS);
    rectangle(32, 86, 656, 3, color(48, 58, 70));
    if (width) rectangle(32, 86, (int)width, 3, color(232, 166, 48));
    if (width > 2U)
        rectangle(32 + (int)width - 2, 84, 4, 7, color(244, 246, 248));
    __asm__ volatile("dmb ishst" ::: "memory");
    next_animation_frame = now + 32UL;
}

static int write_launch_request(const struct catalog_system *system,
                                const struct catalog_entry *entry) {
    char kind[2];
    long fd = sys_create(LAUNCH_REQUEST, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        selected_status = "LAUNCH REQUEST FAILED";
        log_text("launch_request result=open-failed\n");
        return ACTION_NONE;
    }

    kind[0] = (char)('0' + system->launch_kind);
    kind[1] = '\n';
    if (sys_write((int)fd, kind, sizeof(kind)) != (long)sizeof(kind) ||
        sys_write((int)fd, system->core, string_length(system->core)) !=
            (long)string_length(system->core) ||
        sys_write((int)fd, "\n", 1) != 1 ||
        sys_write((int)fd, entry->name, string_length(entry->name)) !=
            (long)string_length(entry->name) ||
        sys_write((int)fd, "\n", 1) != 1 ||
        sys_write((int)fd, entry->path, string_length(entry->path)) !=
            (long)string_length(entry->path) ||
        sys_write((int)fd, "\n", 1) != 1) {
        sys_close((int)fd);
        selected_status = "LAUNCH REQUEST WRITE FAILED";
        log_text("launch_request result=write-failed\n");
        return ACTION_NONE;
    }
    sys_close((int)fd);
    if (save_ui_resume() < 0) {
        sys_unlink(LAUNCH_REQUEST);
        selected_status = "RETURN STATE SAVE FAILED";
        log_text("launch_request result=resume-save-failed\n");
        return ACTION_NONE;
    }
    save_recent(entry);
    selected_status = "STARTING GAME";
    log_text("launch_request boot_ms=");
    log_number(boot_ms());
    log_text(" kind=");
    log_number(system->launch_kind);
    log_text(" core=");
    log_text(system->core);
    log_text(" path=");
    log_text(entry->path);
    log_text(" result=ready\n");
    return ACTION_LAUNCH;
}

static int launch_catalog_entry(u32 catalog_index) {
    const struct catalog_entry *entry;
    const struct catalog_system *system;
    long fd;
    if (catalog_index >= CATALOG_ENTRY_COUNT) return ACTION_NONE;
    entry = &catalog_entries[catalog_index];
    system = &catalog_systems[entry->system];
    fd = sys_open(entry->path, O_RDONLY | O_NONBLOCK);
    log_text("rom_test boot_ms=");
    log_number(boot_ms());
    log_text(" path=");
    log_text(entry->path);
    if (fd >= 0) {
        sys_close((int)fd);
        log_text(" result=ready\n");
        return write_launch_request(system, entry);
    }
    selected_status = "WAITING FOR ROM STORAGE";
    log_text(" result=not-ready\n");
    return ACTION_NONE;
}

static void toggle_current_favorite(void) {
    u32 catalog_index = current_catalog_index();
    int was_favorite;
    if (catalog_index >= CATALOG_ENTRY_COUNT) {
        selected_status = "NO FAVORITE SELECTED";
        draw_screen();
        return;
    }
    if (!storage_ready || !favorites_loaded) {
        selected_status = "WAITING FOR FAVORITES STORAGE";
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
    draw_screen();
}

static int select_current(void) {
    int action = ACTION_NONE;
    if (view == VIEW_MAIN) {
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
            action = ACTION_PORTMASTER;
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
        if (catalog_index < CATALOG_ENTRY_COUNT)
            action = launch_catalog_entry(catalog_index);
        else
            selected_status = "NO GAME SELECTED";
    }
    draw_screen();
    return action;
}

static void move_selection(int direction, u32 steps) {
    u32 count = current_count();
    if (!count) return;
    while (steps--) {
        if (direction < 0) selection = selection > 0U ? selection - 1U : count - 1U;
        if (direction > 0) selection = selection + 1U < count ? selection + 1U : 0U;
    }
    selected_status = "DIRECT EVDEV INPUT READY";
    draw_screen();
}

static int handle_direction(int direction) {
    move_selection(direction, 1U);
    return 0;
}

static int handle_back(void) {
    if (view == VIEW_FAVORITES) {
        view = VIEW_MAIN;
        selection = 1U;
        selected_status = "DIRECT FRAMEBUFFER READY";
        draw_screen();
        return 0;
    }
    if (view == VIEW_GAMES) {
        view = VIEW_SYSTEMS;
        selection = active_system;
        selected_status = "CATALOG READY FROM FIRMWARE";
        draw_screen();
        return 0;
    }
    if (view == VIEW_SYSTEMS) {
        view = VIEW_MAIN;
        selection = 0U;
        selected_status = "DIRECT FRAMEBUFFER READY";
        draw_screen();
        return 0;
    }
    return ACTION_STOCK;
}

static int handle_event(const struct input_event *event) {
    if ((event->type == EV_KEY || event->type == EV_ABS) && captured_events < 300) {
        log_text("event boot_ms=");
        log_number(boot_ms());
        log_text(" type=");
        log_number(event->type);
        log_text(" code=");
        log_number(event->code);
        log_text(" value=");
        log_signed(event->value);
        log_text("\n");
        captured_events++;
    }

    if (boot_animation_active &&
        ((event->type == EV_KEY && event->value == 1) ||
         (event->type == EV_ABS && event->value != 0))) {
        finish_boot_animation("input");
    }

    if (event->type == EV_KEY && event->value == 1) {
        if (event->code == BTN_SOUTH) {
            return select_current();
        }
        if (event->code == BTN_EAST) return handle_back();
        if ((view == VIEW_GAMES || view == VIEW_FAVORITES) && event->code == BUTTON_Y) {
            toggle_current_favorite();
            return 0;
        }
        if ((view == VIEW_SYSTEMS || view == VIEW_GAMES || view == VIEW_FAVORITES) &&
            event->code == BTN_TL) {
            move_selection(-1, view == VIEW_SYSTEMS ? SYSTEM_ROWS : GAME_ROWS);
            return 0;
        }
        if ((view == VIEW_SYSTEMS || view == VIEW_GAMES || view == VIEW_FAVORITES) &&
            event->code == BTN_TR) {
            move_selection(1, view == VIEW_SYSTEMS ? SYSTEM_ROWS : GAME_ROWS);
            return 0;
        }
    }

    if (event->type == EV_ABS) {
        if (event->code == ABS_HAT0X) {
            int next = event->value < 0 ? -1 : (event->value > 0 ? 1 : 0);
            if (next && !axis_x) handle_direction(next);
            axis_x = next;
        }
        if (event->code == ABS_HAT0Y) {
            int next = event->value < 0 ? -1 : (event->value > 0 ? 1 : 0);
            if (next && !axis_y) handle_direction(next);
            axis_y = next;
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
    fd = sys_open(ROM_ROOT, O_RDONLY | O_NONBLOCK);
    if (fd < 0) return;
    sys_close((int)fd);
    storage_ready = 1;
    load_favorites();
    log_text("storage_ready boot_ms=");
    log_number(now);
    log_text(" path=" ROM_ROOT " ui_redraw=deferred\n");
}

static int open_fixed_input(void) {
    char name[128];
    u64 deadline = boot_ms() + DEVICE_WAIT_MS;

    while (boot_ms() < deadline) {
        input_fd = (int)sys_open(INPUT_PATH, O_RDONLY | O_NONBLOCK);
        if (input_fd >= 0) break;
        sys_nanosleep(1000000L);
    }
    if (input_fd < 0) {
        log_text("error wait " INPUT_PATH "\n");
        return -1;
    }

    name[0] = 0;
    sys_ioctl(input_fd, EVIOCGNAME_128, name);
    name[127] = 0;
    log_text("input " INPUT_PATH " name=");
    log_text(name[0] ? name : "unknown");
    log_text(" ready_boot_ms=");
    log_number(boot_ms());
    log_text("\n");
    return 0;
}

static int application(void) {
    u64 started = boot_ms();
    u64 deadline;
    int exit_action = ACTION_NONE;
    log_text("direct launcher start boot_ms=");
    log_number(started);
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
    log_text("\n");

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

    if (open_fixed_input() < 0) {
        sys_munmap((void *)fb, fb_fix.smem_len);
        sys_close(fb_fd);
        return 6;
    }
    load_ui_resume();
    if (claim_boot_effects()) {
        boot_animation_active = 1;
        boot_animation_started = boot_ms();
        next_animation_frame = boot_animation_started;
        log_text("boot_animation start_boot_ms=");
        log_number(boot_animation_started);
        log_text(" duration_ms=");
        log_number(BOOT_ANIMATION_MS);
        log_text(" brightness_source=firmware-default\n");
    } else {
        boot_animation_complete = 1;
    }
    draw_screen();
    log_text("first_frame boot_ms=");
    log_number(boot_ms());
    log_text(" input_ready=1 catalog_entries=");
    log_number(CATALOG_ENTRY_COUNT);
    log_text("\n");

    while (exit_action == ACTION_NONE) {
        struct input_event event;
        long count;
        while ((count = sys_read(input_fd, &event, sizeof(event))) == (long)sizeof(event)) {
            exit_action = handle_event(&event);
            if (exit_action != ACTION_NONE) {
                break;
            }
        }
        probe_storage();
        animate_boot();
        sys_nanosleep(4000000L);
    }

    cancel_boot_sound();

    if (exit_action == ACTION_LAUNCH)
        log_text("exit reason=launch-request boot_ms=");
    else if (exit_action == ACTION_SHUTDOWN)
        log_text("exit reason=shutdown-request boot_ms=");
    else if (exit_action == ACTION_PORTMASTER)
        log_text("exit reason=portmaster-request boot_ms=");
    else
        log_text("exit reason=b-button boot_ms=");
    log_number(boot_ms());
    log_text(" captured_events=");
    log_number(captured_events);
    log_text("\n");
    sys_close(input_fd);
    sys_munmap((void *)fb, fb_fix.smem_len);
    sys_close(fb_fd);
    if (exit_action == ACTION_LAUNCH || exit_action == ACTION_SHUTDOWN ||
        exit_action == ACTION_PORTMASTER)
        return exit_action;
    return 0;
}

__attribute__((noreturn, visibility("default"))) void _start(void) {
    sys_exit(application());
}
