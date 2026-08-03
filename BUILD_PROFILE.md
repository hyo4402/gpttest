# ALice S8 Plus SUSFS build profile

Target: Samsung Galaxy S8 Plus dream2lte / Exynos 8895.

Final integration constraints:

- preserve the uploaded One UI 8 boot ramdisk, header and SEANDROIDENFORCE tail;
- compile real KernelSU SUSFS support into the kernel Image;
- keep GPU maximum at 546 MHz; no new GPU OPP and no voltage increase;
- preserve the V55 CPU/thermal DTB profile and battery current caps during local repack;
- do not rewrite fuel-gauge capacity to 2700 mAh; use 2700 mAh only as a conservative tuning assumption;
- retain rollback image, checksums and validation evidence.
