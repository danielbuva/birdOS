# Fixed storage stages

The RG34XX-SP profile has one content source: the OS card's exFAT partition at
`/dev/mmcblk0p6`, mounted at `/mnt/mmc`. Generic muOS nevertheless probes ROM,
secondary-SD and USB storage, then leaves two UnionFS-FUSE processes resident
to merge sources that do not exist in this fixed experience.

`fixed-union.sh` is the first narrow proof. It preserves the compatibility
paths `/mnt/union/ROMS` and `/mnt/union/ports`, but implements each as a kernel
bind mount directly from `/mnt/mmc`. It does not yet change the exFAT mount,
the `/run/muos/storage` compatibility binds or boot-partition handling. This
isolates removal of the two resident UnionFS processes from later storage work.

`device-install-fixed-union.sh` accepts only the measured stock `union.sh`
checksum, preserves it, and atomically installs the candidate. Run
`stage-fixed-union.sh /Volumes/dani-sp` on the Mac to deliver it. The first boot
installs the candidate; the following cold boot exercises it.

Acceptance requires the custom menu, every game wrapper, save/load, ports,
PortMaster, media, stock fallback, Favorites, global controls and shutdown to
remain functional. The diagnostic collector records bind timing, final mount
types and any remaining `unionfs` PIDs.

