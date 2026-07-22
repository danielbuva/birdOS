/*
 * The old muOS applications carry a redundant DT_NEEDED for libmali.so.0 in
 * addition to EGL/GLES. Mesa supplies their actual symbols; this empty SONAME
 * lets the dynamic linker accept those unchanged binaries without loading the
 * vendor driver that requires /dev/mali0 and /dev/ion.
 */
__attribute__((visibility("default"))) void bird_mali_compatibility_stub(void) {}
