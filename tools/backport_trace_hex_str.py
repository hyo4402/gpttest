#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "kernel")

# Backport upstream Linux commit 2acae0d5b0f7: trace __print_hex_str.
p = root / "include/linux/trace_events.h"
s = p.read_text()
old = "const char *trace_print_hex_seq(struct trace_seq *p,\n\t\t\t\tconst unsigned char *buf, int len);"
new = "const char *trace_print_hex_seq(struct trace_seq *p,\n\t\t\t\tconst unsigned char *buf, int len,\n\t\t\t\tbool spacing);"
if old not in s:
    raise SystemExit(f"prototype anchor missing: {p}")
p.write_text(s.replace(old, new, 1))

p = root / "include/trace/trace_events.h"
s = p.read_text()
old = "#undef __print_hex\n#define __print_hex(buf, buf_len) trace_print_hex_seq(p, buf, buf_len)"
new = "#undef __print_hex\n#define __print_hex(buf, buf_len) trace_print_hex_seq(p, buf, buf_len, true)\n\n#undef __print_hex_str\n#define __print_hex_str(buf, buf_len) trace_print_hex_seq(p, buf, buf_len, false)"
if old not in s:
    raise SystemExit(f"macro anchor missing: {p}")
s = s.replace(old, new, 1)
old = "#undef __print_symbolic\n#undef __print_hex\n#undef __get_dynamic_array"
new = "#undef __print_symbolic\n#undef __print_hex\n#undef __print_hex_str\n#undef __get_dynamic_array"
if old not in s:
    raise SystemExit(f"undef anchor missing: {p}")
p.write_text(s.replace(old, new, 1))

p = root / "kernel/trace/trace_output.c"
s = p.read_text()
old = "trace_print_hex_seq(struct trace_seq *p, const unsigned char *buf, int buf_len)\n{\n\tint i;\n\tconst char *ret = trace_seq_buffer_ptr(p);\n\n\tfor (i = 0; i < buf_len; i++)\n\t\ttrace_seq_printf(p, \"%s%2.2x\", i == 0 ? \"\" : \" \", buf[i]);"
new = "trace_print_hex_seq(struct trace_seq *p, const unsigned char *buf, int buf_len,\n\t\t    bool spacing)\n{\n\tint i;\n\tconst char *ret = trace_seq_buffer_ptr(p);\n\n\tfor (i = 0; i < buf_len; i++)\n\t\ttrace_seq_printf(p, \"%s%2.2x\", !spacing || i == 0 ? \"\" : \" \",\n\t\t\t\t buf[i]);"
if old not in s:
    raise SystemExit(f"implementation anchor missing: {p}")
p.write_text(s.replace(old, new, 1))

# Adapt two redundant SUSFS 1.4.2 post-checks to V55 Linux 4.4.302.
# SUS_PATH remains enabled: may_open() and may_delete() already perform the
# authoritative hidden-inode checks. The original post-checks reference
# variables/APIs absent in V55; the unlink block could also return while the
# target inode mutex is held.
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

print("Backported trace __print_hex_str and adapted SUSFS namei hooks for V55")
