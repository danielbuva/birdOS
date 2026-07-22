#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef uint32_t drm_magic_t;

typedef struct {
    int count_fbs;
    uint32_t *fbs;
    int count_crtcs;
    uint32_t *crtcs;
    int count_connectors;
    uint32_t *connectors;
    int count_encoders;
    uint32_t *encoders;
    uint32_t min_width;
    uint32_t max_width;
    uint32_t min_height;
    uint32_t max_height;
} BirdDrmModeResources;

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t patch;
} BirdSdlVersion;

typedef int (*BirdDrmSetMaster)(int);
typedef int (*BirdDrmDropMaster)(int);
typedef int (*BirdDrmAuthMagic)(int, drm_magic_t);
typedef BirdDrmModeResources *(*BirdDrmModeGetResources)(int);
typedef void (*BirdDrmModeFreeResources)(BirdDrmModeResources *);
typedef int (*BirdSdlGetNumVideoDrivers)(void);
typedef const char *(*BirdSdlGetVideoDriver)(int);
typedef int (*BirdSdlVideoInit)(const char *);
typedef void (*BirdSdlVideoQuit)(void);
typedef const char *(*BirdSdlGetCurrentVideoDriver)(void);
typedef const char *(*BirdSdlGetError)(void);
typedef void (*BirdSdlGetVersion)(BirdSdlVersion *);

static void print_symbol_path(const char *name, void *symbol) {
    Dl_info info;

    memset(&info, 0, sizeof(info));
    if (symbol != NULL && dladdr(symbol, &info) != 0 && info.dli_fname != NULL)
        printf("%s=%s\n", name, info.dli_fname);
    else
        printf("%s=unknown\n", name);
}

static void *load_symbol(void *handle, const char *name) {
    void *symbol;
    const char *error;

    dlerror();
    symbol = dlsym(handle, name);
    error = dlerror();
    if (error != NULL)
        printf("symbol %s unavailable: %s\n", name, error);
    return symbol;
}

static void probe_dependency(const char *name) {
    void *handle;

    dlerror();
    handle = dlopen(name, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        printf("dependency %s: FAIL: %s\n", name, dlerror());
        return;
    }
    printf("dependency %s: ready\n", name);
    dlclose(handle);
}

static void probe_drm(void) {
    void *handle;
    BirdDrmSetMaster set_master;
    BirdDrmDropMaster drop_master;
    BirdDrmAuthMagic auth_magic;
    BirdDrmModeGetResources get_resources;
    BirdDrmModeFreeResources free_resources;
    BirdDrmModeResources *resources = NULL;
    int fd;
    int set_result;
    int set_errno;
    int auth_result;
    int auth_errno;

    fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        printf("drm card0 open: FAIL: errno=%d %s\n", errno, strerror(errno));
        return;
    }
    printf("drm card0 open: ready fd=%d\n", fd);

    dlerror();
    handle = dlopen("libdrm.so.2", RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        printf("drm libdrm load: FAIL: %s\n", dlerror());
        close(fd);
        return;
    }
    set_master = (BirdDrmSetMaster)load_symbol(handle, "drmSetMaster");
    drop_master = (BirdDrmDropMaster)load_symbol(handle, "drmDropMaster");
    auth_magic = (BirdDrmAuthMagic)load_symbol(handle, "drmAuthMagic");
    get_resources =
        (BirdDrmModeGetResources)load_symbol(handle, "drmModeGetResources");
    free_resources =
        (BirdDrmModeFreeResources)load_symbol(handle, "drmModeFreeResources");
    print_symbol_path("drm library", (void *)get_resources);

    if (get_resources != NULL) {
        errno = 0;
        resources = get_resources(fd);
        if (resources == NULL) {
            printf("drm resources: FAIL: errno=%d %s\n", errno,
                   strerror(errno));
        } else {
            printf("drm resources: crtcs=%d connectors=%d encoders=%d "
                   "framebuffers=%d bounds=%ux%u..%ux%u\n",
                   resources->count_crtcs, resources->count_connectors,
                   resources->count_encoders, resources->count_fbs,
                   resources->min_width, resources->min_height,
                   resources->max_width, resources->max_height);
        }
    }

    if (set_master != NULL) {
        errno = 0;
        set_result = set_master(fd);
        set_errno = errno;
        printf("drm set-master: result=%d errno=%d %s\n", set_result,
               set_errno, strerror(set_errno));
        if (auth_magic != NULL) {
            errno = 0;
            auth_result = auth_magic(fd, 0);
            auth_errno = errno;
            printf("drm auth-magic-zero: result=%d errno=%d %s\n",
                   auth_result, auth_errno, strerror(auth_errno));
        }
        if (set_result == 0 && drop_master != NULL) {
            errno = 0;
            printf("drm drop-master: result=%d", drop_master(fd));
            printf(" errno=%d %s\n", errno, strerror(errno));
        }
    }

    if (resources != NULL && free_resources != NULL)
        free_resources(resources);
    dlclose(handle);
    close(fd);
}

static void probe_sdl(void) {
    void *handle;
    BirdSdlGetNumVideoDrivers get_num_drivers;
    BirdSdlGetVideoDriver get_driver;
    BirdSdlVideoInit video_init;
    BirdSdlVideoQuit video_quit;
    BirdSdlGetCurrentVideoDriver current_driver;
    BirdSdlGetError get_error;
    BirdSdlGetVersion get_version;
    BirdSdlVersion version = {0, 0, 0};
    int count;
    int index;
    int result;

    dlerror();
    handle = dlopen("libSDL2-2.0.so.0", RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        printf("sdl load: FAIL: %s\n", dlerror());
        return;
    }
    get_num_drivers =
        (BirdSdlGetNumVideoDrivers)load_symbol(handle,
                                              "SDL_GetNumVideoDrivers");
    get_driver = (BirdSdlGetVideoDriver)load_symbol(handle,
                                                    "SDL_GetVideoDriver");
    video_init = (BirdSdlVideoInit)load_symbol(handle, "SDL_VideoInit");
    video_quit = (BirdSdlVideoQuit)load_symbol(handle, "SDL_VideoQuit");
    current_driver = (BirdSdlGetCurrentVideoDriver)load_symbol(
        handle, "SDL_GetCurrentVideoDriver");
    get_error = (BirdSdlGetError)load_symbol(handle, "SDL_GetError");
    get_version = (BirdSdlGetVersion)load_symbol(handle, "SDL_GetVersion");
    print_symbol_path("sdl library", (void *)video_init);

    if (get_version != NULL) {
        get_version(&version);
        printf("sdl version=%u.%u.%u\n", version.major, version.minor,
               version.patch);
    }
    if (get_num_drivers != NULL && get_driver != NULL) {
        count = get_num_drivers();
        printf("sdl video driver count=%d\n", count);
        for (index = 0; index < count; index++)
            printf("sdl video driver[%d]=%s\n", index,
                   get_driver(index) != NULL ? get_driver(index) : "unknown");
    }
    if (video_init != NULL) {
        result = video_init("kmsdrm");
        printf("sdl kmsdrm init: result=%d current=%s error=%s\n", result,
               current_driver != NULL && current_driver() != NULL
                   ? current_driver()
                   : "none",
               get_error != NULL ? get_error() : "unavailable");
        if (result == 0 && video_quit != NULL)
            video_quit();
    }
    dlclose(handle);
}

int main(void) {
    printf("bird graphics probe v1\n");
    printf("environment SDL_VIDEODRIVER=%s SDL_KMSDRM_DEVICE_INDEX=%s "
           "LD_LIBRARY_PATH=%s\n",
           getenv("SDL_VIDEODRIVER") != NULL ? getenv("SDL_VIDEODRIVER") : "",
           getenv("SDL_KMSDRM_DEVICE_INDEX") != NULL
               ? getenv("SDL_KMSDRM_DEVICE_INDEX")
               : "",
           getenv("LD_LIBRARY_PATH") != NULL ? getenv("LD_LIBRARY_PATH") : "");
    probe_dependency("libdrm.so.2");
    probe_dependency("libgbm.so.1");
    probe_dependency("libEGL.so.1");
    probe_drm();
    probe_sdl();
    return 0;
}
