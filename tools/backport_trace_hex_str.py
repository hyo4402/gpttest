#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "kernel")

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

print("Backported upstream Linux commit 2acae0d5b0f7 trace __print_hex_str support")
