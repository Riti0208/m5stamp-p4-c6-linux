// The unix "standard" feature level, which has the modules a Pico-style
// main.py expects (time, socket, select, json, re, asyncio, ...).  The
// "minimal" variant had only os and sys: no time.sleep (#34).
//
// The binary is loaded whole into RAM (bFLT -r), so it must stay under the
// 512 KB NOMMU allocation with its data, bss and stack (build-m1.sh checks
// the size).  These are left out to make room:
#define MICROPY_PY_FRAMEBUF            (0)
#define MICROPY_PY_CMATH               (0)
#define MICROPY_PY_DEFLATE             (0)
#define MICROPY_PY_UCTYPES             (0)
#define MICROPY_PY_BUILTINS_COMPLEX    (0)
#define MICROPY_PY_BUILTINS_HELP_MODULES (0)
#define MICROPY_PY_BTREE               (0)
#define MICROPY_ENABLE_DOC_STRING      (0)

#define MICROPY_CONFIG_ROM_LEVEL (MICROPY_CONFIG_ROM_LEVEL_EXTRA_FEATURES)

#include "../mpconfigvariant_common.h"
