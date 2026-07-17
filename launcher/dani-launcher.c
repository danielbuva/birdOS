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
#define BTN_TL 308
#define BTN_TR 309
#define ABS_HAT0X 16
#define ABS_HAT0Y 17

#define CLOCK_BOOTTIME 7
#define STOCK_FALLBACK_TIMEOUT_MS 120000UL
#define DEVICE_WAIT_MS 5000UL
#define INPUT_PATH "/dev/input/event1"
#define ROM_ROOT "/mnt/mmc/ROMS"
#define LAUNCH_REQUEST "/run/muos/dani-launch-request"

#define VIEW_MAIN 0U
#define VIEW_SYSTEMS 1U
#define VIEW_GAMES 2U
#define GAME_ROWS 8U
#define ACTION_NONE 0
#define ACTION_STOCK 1
#define ACTION_LAUNCH 10

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
static u64 next_storage_probe;
static u32 captured_events;
static const char *selected_status = "DIRECT FRAMEBUFFER READY";

static const char *menu_item[4] = {"GAMES", "FAVORITES", "PORTMASTER", "SHUTDOWN"};

/* Five-wide uppercase bitmap alphabet plus the exact punctuation this UI uses. */
static const struct glyph font[] = {
    {' ', {0, 0, 0, 0, 0, 0, 0}},       {'!', {4, 4, 4, 4, 4, 0, 4}},
    {'\'', {4, 4, 0, 0, 0, 0, 0}},      {'(', {2, 4, 8, 8, 8, 4, 2}},
    {')', {8, 4, 2, 2, 2, 4, 8}},       {'&', {12, 18, 20, 8, 21, 18, 13}},
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
    return catalog_systems[active_system].count;
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
        draw_text(32, 22, "GAMES", 4, primary);
        draw_text(34, 62, "EMBEDDED CATALOG // NO SCAN", 2, muted);
        for (i = 0; i < CATALOG_SYSTEM_COUNT; i++) {
            int y = 122 + (int)i * 64;
            if (i == selection) {
                rectangle(92, y - 10, 492, 52, selected);
                draw_text(108, y + 4, ">", 3, background);
                draw_text(148, y, catalog_systems[i].name, 4, background);
            } else {
                draw_text(148, y, catalog_systems[i].name, 4, primary);
            }
        }
    } else {
        const struct catalog_system *system = &catalog_systems[active_system];
        u32 first = selection < GAME_ROWS ? 0U : selection - GAME_ROWS + 1U;
        draw_text(32, 22, system->name, 4, primary);
        draw_text(34, 62, "CACHED GAMES // STORAGE ASYNC", 2, muted);
        for (i = 0; i < GAME_ROWS && first + i < system->count; i++) {
            const struct catalog_entry *entry = &catalog_entries[system->first + first + i];
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

    draw_text(32, (int)fb_var.yres - 54, selected_status, 2, muted);
    if (view == VIEW_MAIN)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE   A SELECT   B STOCK", 2, primary);
    else if (view == VIEW_GAMES)
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE   L1 R1 PAGE   A LAUNCH   B BACK", 2, primary);
    else
        draw_text(32, (int)fb_var.yres - 28, "DPAD MOVE   A OPEN   B BACK", 2, primary);
    __asm__ volatile("dmb ishst" ::: "memory");
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
    selected_status = "STARTING GAME";
    log_text("launch_request boot_ms=");
    log_number(boot_ms());
    log_text(" kind=");
    log_number(system->launch_kind);
    log_text(" path=");
    log_text(entry->path);
    log_text(" result=ready\n");
    return ACTION_LAUNCH;
}

static int select_current(void) {
    int action = ACTION_NONE;
    if (view == VIEW_MAIN) {
        if (selection == 0U) {
            view = VIEW_SYSTEMS;
            selection = 0U;
            selected_status = "CATALOG READY FROM FIRMWARE";
        } else if (selection == 1U) {
            selected_status = "FAVORITES CACHE COMING NEXT";
        } else if (selection == 2U) {
            selected_status = "PORTMASTER HANDOFF COMING NEXT";
        } else {
            selected_status = "SHUTDOWN HANDOFF COMING NEXT";
        }
    } else if (view == VIEW_SYSTEMS) {
        active_system = selection;
        view = VIEW_GAMES;
        selection = 0U;
        selected_status = storage_ready ? "ROM STORAGE READY" : "CATALOG READY // ROMS MOUNTING";
    } else {
        const struct catalog_system *system = &catalog_systems[active_system];
        const struct catalog_entry *entry = &catalog_entries[system->first + selection];
        long fd = sys_open(entry->path, O_RDONLY | O_NONBLOCK);
        log_text("rom_test boot_ms=");
        log_number(boot_ms());
        log_text(" path=");
        log_text(entry->path);
        if (fd >= 0) {
            sys_close((int)fd);
            log_text(" result=ready\n");
            action = write_launch_request(system, entry);
        } else {
            selected_status = "WAITING FOR ROM STORAGE";
            log_text(" result=not-ready\n");
        }
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

    if (event->type == EV_KEY && event->value == 1) {
        if (event->code == BTN_SOUTH) {
            return select_current();
        }
        if (event->code == BTN_EAST) return handle_back();
        if (view == VIEW_GAMES && event->code == BTN_TL) {
            move_selection(-1, GAME_ROWS);
            return 0;
        }
        if (view == VIEW_GAMES && event->code == BTN_TR) {
            move_selection(1, GAME_ROWS);
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
    selected_status = "ROM STORAGE READY";
    log_text("storage_ready boot_ms=");
    log_number(now);
    log_text(" path=" ROM_ROOT "\n");
    draw_screen();
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
    draw_screen();
    log_text("first_frame boot_ms=");
    log_number(boot_ms());
    log_text(" input_ready=1 catalog_entries=");
    log_number(CATALOG_ENTRY_COUNT);
    log_text("\n");

    deadline = boot_ms() + STOCK_FALLBACK_TIMEOUT_MS;
    while (boot_ms() < deadline && exit_action == ACTION_NONE) {
        struct input_event event;
        long count;
        while ((count = sys_read(input_fd, &event, sizeof(event))) == (long)sizeof(event)) {
            exit_action = handle_event(&event);
            if (exit_action != ACTION_NONE) {
                break;
            }
        }
        probe_storage();
        sys_nanosleep(4000000L);
    }

    if (exit_action == ACTION_LAUNCH)
        log_text("exit reason=launch-request boot_ms=");
    else if (exit_action == ACTION_STOCK)
        log_text("exit reason=b-button boot_ms=");
    else
        log_text("exit reason=stock-fallback-timeout boot_ms=");
    log_number(boot_ms());
    log_text(" captured_events=");
    log_number(captured_events);
    log_text("\n");
    sys_close(input_fd);
    sys_munmap((void *)fb, fb_fix.smem_len);
    sys_close(fb_fd);
    return exit_action == ACTION_LAUNCH ? ACTION_LAUNCH : 0;
}

__attribute__((noreturn, visibility("default"))) void _start(void) {
    sys_exit(application());
}
