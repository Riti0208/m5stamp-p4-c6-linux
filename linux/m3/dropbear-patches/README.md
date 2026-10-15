# Dropbear fixes for SSH images

Buildroot global patches for Dropbear **2026.91**, staged into
`BR2_GLOBAL_PATCH_DIR/dropbear/` for every SSH profile (`m3` and `m3-lab`).
They are numbered after the m3-lab ledger series
(`../../m3-lab/dropbear-patches/0001`–`0004`, applied only with
`EASYSTICK_SSH_LEDGER=1`) and apply with or without it.

| Patch | Fixes |
| --- | --- |
| `0010-easystick-vfork-child-shared-memory.patch` | A command run over SSH ended with `Bad packet length` / `Connection corrupted` instead of its exit status. |

## 0010: the vfork() child rewrote the server's memory

On NOMMU Dropbear starts the session command with `vfork()`, so the child
runs in the server's memory until it execs. uClibc's LinuxThreads `signal()`
keeps the real handler in a table in that memory and installs its own
`pthread_sighandler` in the kernel. The child's `signal(SIGCHLD, SIG_DFL)`
cleared the server's table entry, and the SIGCHLD sent when the command
exited made the server jump to address 0. Its SIGSEGV handler printed
"Aiee, segfault!" to stderr, which is the SSH socket under inetd, so the
client saw a corrupt packet.

Evidence (2026-10-15, CI v0.2.2 image, STA): a debug build whose SIGSEGV
handler saved the registers showed `pc=0`, `s1=17` (SIGCHLD) and a return
address in `pthread_sighandler`. With the patch, `ssh m5@… 'id'` exits 0 and
`ssh m5@… 'exit 7'` exits 7.

The patch also makes `svr_dropbear_exit()` leave a vfork child (exec, dup2
or chdir failed) with `_exit()` before it frees the host key and addresses
or runs `exit()`, both of which act on the server's memory.

A check for "it worked" must include the client's exit status: the remote
`echo rc=$?` prints before the crash, so `id` output plus `rc=0` alone does
not show that the session ended cleanly.
