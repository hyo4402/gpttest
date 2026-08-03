#!/usr/bin/env python3
"""Adapt two broken/redundant SUSFS 1.4.2 namei hooks to V55 Linux 4.4.302.

SUS_PATH remains enabled. The authoritative checks already run in may_open()
and may_delete(); the removed post-checks reference variables/APIs absent from
this source and one would return while holding target->i_mutex.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "kernel")
p = root / "fs/namei.c"
s = p.read_text()

bad_do_last = '''#ifdef CONFIG_KSU_SUSFS_SUS_PATH
\tif (!IS_ERR(dentry) && dentry->d_inode && unlikely(dentry->d_inode->i_state & 16777216) && likely(current_cred()->user->android_kabi_reserved1 & 16777216)) {
\t\tdput(dentry);
\t\tinode_unlock_shared(inode);
\t\treturn ERR_PTR(-ENOENT);
\t}
#endif
'''

bad_unlink = '''#ifdef CONFIG_KSU_SUSFS_SUS_PATH
\t\t// we deal with sus sub path here
\t\tif (nd->inode && unlikely(nd->inode->i_state & 16777216) && likely(current_cred()->user->android_kabi_reserved1 & 16777216)) {
\t\t\treturn 0;
\t\t}
#endif
'''

for label, block in (("do_last post-check", bad_do_last), ("vfs_unlink2 post-check", bad_unlink)):
    count = s.count(block)
    if count != 1:
        raise SystemExit(f"expected exactly one {label}, found {count}")
    s = s.replace(block, f"/* V55 SUSFS compatibility: {label} is redundant; may_open/may_delete enforce SUS_PATH. */\n", 1)

p.write_text(s)
print("Adapted SUSFS namei hooks for V55 while retaining CONFIG_KSU_SUSFS_SUS_PATH=y")
