################################################################################
#
# busybox-tools
#
################################################################################

# Same source and Buildroot patches as the main BusyBox; only the config
# (busybox-tools.config, applied over allnoconfig) differs.
BUSYBOX_TOOLS_VERSION = $(BUSYBOX_VERSION)
BUSYBOX_TOOLS_SITE = $(BUSYBOX_SITE)
BUSYBOX_TOOLS_SOURCE = $(BUSYBOX_SOURCE)
BUSYBOX_TOOLS_DL_SUBDIR = busybox
BUSYBOX_TOOLS_LICENSE = GPL-2.0
BUSYBOX_TOOLS_LICENSE_FILES = LICENSE
BUSYBOX_TOOLS_DEPENDENCIES = busybox

define BUSYBOX_TOOLS_APPLY_BUSYBOX_PATCHES
	$(APPLY_PATCHES) $(@D) $(BUSYBOX_PKGDIR) \*.patch
endef
BUSYBOX_TOOLS_POST_PATCH_HOOKS += BUSYBOX_TOOLS_APPLY_BUSYBOX_PATCHES

# As in busybox-daemons: allnoconfig drops the listed symbols, so remove them
# from its output, append the list and let oldconfig settle the dependencies.
define BUSYBOX_TOOLS_CONFIGURE_CMDS
	$(BUSYBOX_MAKE_ENV) $(MAKE) $(BUSYBOX_MAKE_OPTS) -C $(@D) allnoconfig
	sed -n 's/^\(# \)\{0,1\}\(CONFIG_[A-Z0-9_]*\)[= ].*/\2/p' \
		$(BUSYBOX_TOOLS_PKGDIR)/busybox-tools.config > $(@D)/.tools-keys
	grep -v -w -F -f $(@D)/.tools-keys $(@D)/.config > $(@D)/.config.base
	cat $(@D)/.config.base $(BUSYBOX_TOOLS_PKGDIR)/busybox-tools.config \
		> $(@D)/.config
	yes "" | $(BUSYBOX_MAKE_ENV) $(MAKE) $(BUSYBOX_MAKE_OPTS) -C $(@D) oldconfig
	grep '^\(# \)\{0,1\}CONFIG_' $(BUSYBOX_TOOLS_PKGDIR)/busybox-tools.config | \
		while IFS= read -r line; do \
			grep -qxF -- "$$line" $(@D)/.config || { \
				echo "busybox-tools: oldconfig dropped: $$line" >&2; exit 1; }; \
		done
endef

define BUSYBOX_TOOLS_BUILD_CMDS
	$(BUSYBOX_MAKE_ENV) $(MAKE) $(BUSYBOX_MAKE_OPTS) -C $(@D) busybox busybox.links
endef

# Link every applet the main BusyBox lacks.  A real file of the same name
# (another package's binary) wins; a symlink left by an earlier config is
# replaced.
define BUSYBOX_TOOLS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/busybox $(TARGET_DIR)/bin/busybox-tools
	while IFS= read -r path; do \
		name=$${path##*/}; \
		grep -q "/$$name\$$" $(BUSYBOX_DIR)/busybox.links && continue; \
		skip=; \
		for d in bin sbin usr/bin usr/sbin; do \
			f=$(TARGET_DIR)/$$d/$$name; \
			if [ -e "$$f" ] && [ ! -L "$$f" ]; then skip=1; fi; \
		done; \
		[ -z "$$skip" ] || continue; \
		case "$$path" in \
			/usr/*) target=../../bin/busybox-tools ;; \
			/bin/*) target=busybox-tools ;; \
			*) target=../bin/busybox-tools ;; \
		esac; \
		mkdir -p $(TARGET_DIR)$${path%/*}; \
		ln -sfn "$$target" $(TARGET_DIR)$$path; \
	done < $(@D)/busybox.links
endef

$(eval $(generic-package))
