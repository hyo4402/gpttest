# One UI 8 compatibility lock

The final boot image must retain the exact uploaded One UI 8 ramdisk and boot header. The GitHub workflow builds only the kernel Image. Device-tree and ramdisk integration are performed locally with rollback and checksum verification.
