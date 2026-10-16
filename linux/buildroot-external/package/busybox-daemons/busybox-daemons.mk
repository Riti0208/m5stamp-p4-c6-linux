################################################################################
#
# busybox-daemons
#
################################################################################

# Same source and Buildroot patches as the main BusyBox; only the config
# (busybox-daemons.config, applied over allnoconfig) differs.
BUSYBOX_DAEMONS_VERSION = $(BUSYBOX_VERSION)
BUSYBOX_DAEMONS_SITE = $(BUSYBOX_SITE)
BUSYBOX_DAEMONS_SOURCE = $(BUSYBOX_SOURCE)
BUSYBOX_DAEMONS_DL_SUBDIR = busybox
BUSYBOX_DAEMONS_LICENSE = GPL-2.0
BUSYBOX_DAEMONS_LICENSE_FILES = LICENSE
BUSYBOX_DAEMONS_DEPENDENCIES = busybox

define BUSYBOX_DAEMONS_APPLY_BUSYBOX_PATCHES
	$(APPLY_PATCHES) $(@D) $(BUSYBOX_PKGDIR) \*.patch
endef
BUSYBOX_DAEMONS_POST_PATCH_HOOKS += BUSYBOX_DAEMONS_APPLY_BUSYBOX_PATCHES

# allnoconfig in this kconfig does not keep the values from allno.config,
# so drop the listed symbols from its output, append the list and let
# oldconfig settle the dependencies.
define BUSYBOX_DAEMONS_CONFIGURE_CMDS
	$(BUSYBOX_MAKE_ENV) $(MAKE) $(BUSYBOX_MAKE_OPTS) -C $(@D) allnoconfig
	sed -n 's/^\(# \)\{0,1\}\(CONFIG_[A-Z0-9_]*\)[= ].*/\2/p' \
		$(BUSYBOX_DAEMONS_PKGDIR)/busybox-daemons.config > $(@D)/.daemons-keys
	grep -v -w -F -f $(@D)/.daemons-keys $(@D)/.config > $(@D)/.config.base
	cat $(@D)/.config.base $(BUSYBOX_DAEMONS_PKGDIR)/busybox-daemons.config \
		> $(@D)/.config
	yes "" | $(BUSYBOX_MAKE_ENV) $(MAKE) $(BUSYBOX_MAKE_OPTS) -C $(@D) oldconfig
	for opt in INIT INETD SYSLOGD UDHCPD NOMMU STATIC; do \
		grep -qx "CONFIG_$${opt}=y" $(@D)/.config || { \
			echo "busybox-daemons: CONFIG_$${opt} is not set" >&2; exit 1; }; \
	done
endef

define BUSYBOX_DAEMONS_BUILD_CMDS
	$(BUSYBOX_MAKE_ENV) $(MAKE) $(BUSYBOX_MAKE_OPTS) -C $(@D) busybox
endef

define BUSYBOX_DAEMONS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/busybox $(TARGET_DIR)/bin/busybox-daemons
endef

$(eval $(generic-package))
