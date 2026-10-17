# Unix "standard" without the parts this NOMMU image cannot use or afford:
# no libffi, threads (no MMU), TLS or btree.  asyncio is frozen in.

FROZEN_MANIFEST ?= $(VARIANT_DIR)/manifest.py

MICROPY_PY_BTREE = 0
MICROPY_PY_FFI = 0
MICROPY_PY_THREAD = 0
MICROPY_PY_SSL = 0
MICROPY_PY_SOCKET = 1
MICROPY_PY_TERMIOS = 1
MICROPY_USE_READLINE = 1

MICROPY_VFS_FAT = 0
MICROPY_VFS_LFS1 = 0
MICROPY_VFS_LFS2 = 0
