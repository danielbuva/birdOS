# Vendor U-Boot to mainline-DT handoff audit

Audit date: 2026-07-21.

The accepted device still uses its vendor Allwinner U-Boot while the kernel is
replaced. This audit defines the compatibility boundary between them.

## Evidence

The captured TOC1 U-Boot DTB is 137,756 bytes. The public
`v2018.05-sun50iw9` lineage at commit
`273096252caa7682773f9be91930c84dc91bf5ed` shows that U-Boot adds 4 KiB of
FDT padding and aligns the working buffer to 32 bytes. The resulting 141,856
bytes exactly matches both DTBs captured from `/sys/firmware/fdt` on the
device.

That lineage's Android boot path:

1. validates the DTB carried after the kernel and ramdisk;
2. rejects it only if it exceeds the padded U-Boot working buffer;
3. copies it into that buffer and makes it the kernel FDT;
4. enables the path named by the `mmc0` alias for SD boot;
5. writes 24 detected DRAM-training cells under `/dram`;
6. continues through the ordinary ARM64 boot path.

The installed 2025 vendor binary contains the matching
`sunxi_update_fdt_para_for_kernel` and `update dts` identities, but is newer
than the public source. The earlier DTB-only experiment proves it performs
additional board mutations: all 20 disabled vendor nodes arrived enabled in
Linux. The public tree is therefore behavioral lineage, not a claim of exact
source correspondence.

## Fixed-device contract

The mainline DTB is 35,197 bytes, far below the 141,856-byte working limit. It
provides `mmc0 = /soc/mmc@4020000`, keeps that controller enabled, and includes
an inert `/dram` handoff node. Linux ignores the vendor scratch node; it exists
only so U-Boot can complete its known DRAM fixup instead of returning early.

`kernel/audit-mainline-uboot-handoff.sh` copies the compiled DTB, performs the
known MMC status write, writes all 24 DRAM cells with libfdt tools, verifies the
results and enforces the captured capacity limit. This simulation passes.

Unknown mutations in the later installed U-Boot may still report missing
vendor-only paths. That is a hardware-test risk, not a reason to import the
vendor DT structure into mainline. All known libfdt mutations fail by return
code rather than by blindly dereferencing a missing node, and the accepted
boot image remains externally restorable if the kernel never reaches PID 1.
