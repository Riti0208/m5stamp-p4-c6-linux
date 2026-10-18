# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only
# Switches the Tab5 C6 supply on before ESP-Hosted's constructor runs.
# WHOLE_ARCHIVE keeps the constructor although nothing calls into it.
idf_component_register(
    SRCS "tab5_c6_power_ctor.c" "tab5_power.c"
    INCLUDE_DIRS "."
    REQUIRES esp_driver_gpio log esp_rom
    WHOLE_ARCHIVE
)
