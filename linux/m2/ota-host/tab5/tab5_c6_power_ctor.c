// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only
/*
 * ESP-Hosted-MCU starts its transport from a default-priority constructor.
 * Prioritized constructors run first (ascending), so the C6 is powered
 * before ESP-Hosted resets it and initializes the SDIO card.
 */

#include "tab5_power.h"

static void __attribute__((constructor(101))) tab5_c6_power_ctor(void)
{
	tab5_c6_power_on();
}
