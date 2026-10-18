// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only
/*
 * ESP32-P4 Slot 1 GPIO-matrix/clock bootstrap for the C6 (Stamp-AddOn C6,
 * or the C6 on an M5Stack Tab5 with EASYSTICK_BOARD_TAB5).
 *
 * Linux's board port does not yet have an upstream P4 pinctrl/clock
 * controller, so the boot shim leaves the controller clocked and routes the
 * six SDIO signals before jumping to the kernel.  The constants mirror the
 * locked ESP-IDF 5.5.3 ESP32-P4 v1 register definitions.  This is an M2
 * experiment: it must be validated on the assembled carrier at 20 MHz before
 * any higher-speed or DMA setting is attempted.
 */

#include <stdint.h>
#include <stdbool.h>

#include "esp_log.h"
#include "esp_rom_sys.h"

#ifdef EASYSTICK_BOARD_TAB5
#include "driver/rtc_io.h"
#include "tab5_power.h"
#endif

static const char *TAG = "easystick-m2-sdio";

#define HP_SYS_CLKRST_BASE 0x500e6000u
#define HP_SOC_CLK_CTRL1 (HP_SYS_CLKRST_BASE + 0x18u)
#define HP_PERI_CLK_CTRL01 (HP_SYS_CLKRST_BASE + 0x34u)
#define HP_PERI_CLK_CTRL02 (HP_SYS_CLKRST_BASE + 0x38u)
#define LP_CLKRST_BASE 0x50111000u
#define LP_SDMMC_RESET (LP_CLKRST_BASE + 0x4cu)

#define GPIO_BASE 0x500e0000u
#define GPIO_OUT_W1TS (GPIO_BASE + 0x08u)
#define GPIO_OUT_W1TC (GPIO_BASE + 0x0cu)
#define GPIO_ENABLE_W1TS (GPIO_BASE + 0x24u)
#define GPIO_ENABLE_W1TC (GPIO_BASE + 0x28u)
#define GPIO_OUT1_W1TS (GPIO_BASE + 0x14u)
#define GPIO_OUT1_W1TC (GPIO_BASE + 0x18u)
#define GPIO_ENABLE1_W1TS (GPIO_BASE + 0x30u)
#define GPIO_ENABLE1_W1TC (GPIO_BASE + 0x34u)
#define GPIO_FUNC_IN_SEL_BASE (GPIO_BASE + 0x158u)
#define GPIO_FUNC_OUT_SEL_BASE (GPIO_BASE + 0x558u)
#define IO_MUX_BASE 0x500e1000u

#define SDMMC_SYS_CLK_EN (1u << 14)
#define SDIO_HS_MODE (1u << 22)
#define SDIO_LS_CLK_SRC_SEL (1u << 23)
#define SDIO_LS_CLK_EN (1u << 24)
#define SDIO_EDGE_CFG_UPDATE (1u << 8)
#define SDIO_EDGE_L_SHIFT 9
#define SDIO_EDGE_H_SHIFT 13
#define SDIO_EDGE_N_SHIFT 17
#define SDIO_SLF_EDGE_SEL_SHIFT 21
#define SDIO_DRV_EDGE_SEL_SHIFT 23
#define SDIO_SAM_EDGE_SEL_SHIFT 25
#define SDIO_SLF_CLK_EN (1u << 27)
#define SDIO_DRV_CLK_EN (1u << 28)
#define SDIO_SAM_CLK_EN (1u << 29)
#define SDMMC_RESET_EN (1u << 28)

/* M5Stack's Stamp-P4 ESP-Hosted configuration waits 1500 ms after the
 * active-high C6 EN/reset sequence before starting SDIO card init.  Keep the
 * same board-proven readiness window in the Linux handoff. */
#define C6_RESET_ASSERT_US 10000u
#define C6_RESET_INACTIVE_US 10000u
#define C6_RESET_READY_DELAY_US 1500000u

#define IOMUX_FUN_PD (1u << 7)
#define IOMUX_FUN_PU (1u << 8)
#define IOMUX_FUN_IE (1u << 9)
#define IOMUX_FUN_DRV_MASK (3u << 10)
#define IOMUX_MCU_SEL_MASK (7u << 12)
#define PIN_FUNC_GPIO 1u

/*
 * C6 wiring.  Stamp-AddOn C6: CLK=43, CMD=44, DAT0..3=45..48, EN=42.
 * Tab5 (schematic SDIO2_*, SOC_EXTRF_RST): CLK=12, CMD=13, DAT0=11,
 * DAT1=10, DAT2=9, DAT3=8, EN=15.
 */
struct c6_sdio_pins {
	uint32_t clk, cmd, d0, d1, d2, d3, en;
};

#ifdef EASYSTICK_BOARD_TAB5
static const struct c6_sdio_pins c6_pins = { 12u, 13u, 11u, 10u, 9u, 8u, 15u };
#else
static const struct c6_sdio_pins c6_pins = { 43u, 44u, 45u, 46u, 47u, 48u, 42u };
#endif

static inline volatile uint32_t *reg32(uint32_t addr)
{
	return (volatile uint32_t *)(uintptr_t)addr;
}

static inline void set_bits(uint32_t addr, uint32_t mask)
{
	*reg32(addr) |= mask;
}

static inline void clear_set_bits(uint32_t addr, uint32_t clear, uint32_t set)
{
	uint32_t value = *reg32(addr);
	*reg32(addr) = (value & ~clear) | set;
}

static void configure_iomux_gpio(uint32_t gpio, bool pullup)
{
	/*
	 * ESP32-P4's IO_MUX register map is not gpio_number * 4: the pad
	 * registers start at offset 4 (GPIO0 0x04, GPIO8 0x24, GPIO26 0x6c,
	 * GPIO42 0xac).  Using gpio * 4 here configured the preceding pad
	 * (GPIO43 wrote GPIO42's register), leaving the data path unreliable.
	 */
	if (gpio > 54u)
		return;
	uint32_t offset = (gpio + 1u) * 4u;
#ifdef EASYSTICK_BOARD_TAB5
	/* GPIO0..15 are LP-capable pads; make sure the HP IO_MUX owns them. */
	if (rtc_gpio_is_valid_gpio((gpio_num_t)gpio))
		rtc_gpio_deinit((gpio_num_t)gpio);
#endif
	uint32_t clear = IOMUX_FUN_PD | IOMUX_FUN_PU | IOMUX_FUN_IE |
			 IOMUX_FUN_DRV_MASK | IOMUX_MCU_SEL_MASK;
	uint32_t set = IOMUX_FUN_IE | (3u << 10) | (PIN_FUNC_GPIO << 12);
	if (pullup)
		set |= IOMUX_FUN_PU;
	clear_set_bits(IO_MUX_BASE + offset, clear, set);
}

static void route_output(uint32_t gpio, uint32_t signal)
{
	/* OEN_SEL=0 delegates output-enable to the SDMMC peripheral. */
	clear_set_bits(GPIO_FUNC_OUT_SEL_BASE + (gpio * 4u),
			       0x1ffu | (1u << 10) | (1u << 11), signal & 0x1ffu);
}

static void route_input(uint32_t signal, uint32_t gpio)
{
	/* SIG_IN_SEL=1 selects the GPIO matrix rather than the direct bypass. */
	*reg32(GPIO_FUNC_IN_SEL_BASE + (signal * 4u)) = (gpio & 0x3fu) | (1u << 7);
}

#ifdef EASYSTICK_BOARD_TAB5
/*
 * The Tab5 schematic wires GPIO15 through 1 k straight to the C6 EN (10 k
 * pull-up, 1 uF), i.e. low = reset, and a Tab5 checked on 2026-10-18 agrees:
 * ESP-Hosted-MCU answered over SDIO only with its reset set active-high.
 * Its Tab5 board option defaults to the opposite polarity, so a board
 * revision may differ.  A released line lets the C6 run either way (the EN
 * pull-up), so pulse low, then high, then release: whichever level is the
 * reset level is applied once for 10 ms and the C6 starts on release.
 */
static void pulse_c6_reset(void)
{
	const uint32_t gpio = c6_pins.en;
	const uint32_t bit = 1u << gpio;

	configure_iomux_gpio(gpio, false);
	*reg32(GPIO_OUT_W1TC) = bit;
	*reg32(GPIO_ENABLE_W1TS) = bit;
	esp_rom_delay_us(C6_RESET_ASSERT_US);
	*reg32(GPIO_OUT_W1TS) = bit;
	esp_rom_delay_us(C6_RESET_ASSERT_US);
	*reg32(GPIO_ENABLE_W1TC) = bit;
	esp_rom_delay_us(C6_RESET_READY_DELAY_US);
	ESP_LOGI(TAG, "C6 reset GPIO%u pulsed both ways and released", (unsigned)gpio);
}
#else
static void pulse_c6_reset(void)
{
	const uint32_t gpio = c6_pins.en;
	const uint32_t bit = 1u << (gpio & 31u);
	const uint32_t out_set = gpio < 32u ? GPIO_OUT_W1TS : GPIO_OUT1_W1TS;
	const uint32_t out_clr = gpio < 32u ? GPIO_OUT_W1TC : GPIO_OUT1_W1TC;
	const uint32_t en_set = gpio < 32u ? GPIO_ENABLE_W1TS : GPIO_ENABLE1_W1TS;

	configure_iomux_gpio(gpio, false);
	*reg32(en_set) = bit;
	*reg32(out_set) = bit;
	esp_rom_delay_us(C6_RESET_ASSERT_US);
	*reg32(out_clr) = bit;
	esp_rom_delay_us(C6_RESET_INACTIVE_US);
	*reg32(out_set) = bit;
	esp_rom_delay_us(C6_RESET_READY_DELAY_US);
	ESP_LOGI(TAG, "C6 reset GPIO%u released", (unsigned)gpio);
}
#endif

static void enable_sdmmc_clock(void)
{
	set_bits(HP_SOC_CLK_CTRL1, SDMMC_SYS_CLK_EN);
	set_bits(LP_SDMMC_RESET, SDMMC_RESET_EN);
	clear_set_bits(LP_SDMMC_RESET, SDMMC_RESET_EN, 0);

	/* PLL_F160M / host divider 4 gives a conservative 40 MHz LS clock. */
	clear_set_bits(HP_PERI_CLK_CTRL01,
			       SDIO_LS_CLK_SRC_SEL | SDIO_HS_MODE, SDIO_LS_CLK_EN);

	uint32_t clear = (0xfu << SDIO_EDGE_L_SHIFT) |
			 (0xfu << SDIO_EDGE_H_SHIFT) |
			 (0xfu << SDIO_EDGE_N_SHIFT) |
			 (0x3u << SDIO_SLF_EDGE_SEL_SHIFT) |
			 (0x3u << SDIO_DRV_EDGE_SEL_SHIFT) |
			 (0x3u << SDIO_SAM_EDGE_SEL_SHIFT);
	uint32_t set = (3u << SDIO_EDGE_L_SHIFT) |
			 (1u << SDIO_EDGE_H_SHIFT) |
			 (3u << SDIO_EDGE_N_SHIFT) |
			 (1u << SDIO_DRV_EDGE_SEL_SHIFT) |
			 SDIO_SLF_CLK_EN | SDIO_DRV_CLK_EN | SDIO_SAM_CLK_EN;
	clear_set_bits(HP_PERI_CLK_CTRL02, clear, set);
	set_bits(HP_PERI_CLK_CTRL02, SDIO_EDGE_CFG_UPDATE);
	clear_set_bits(HP_PERI_CLK_CTRL02, SDIO_EDGE_CFG_UPDATE, 0);
}

void easystick_m2_sdmmc_init(void)
{
#ifdef EASYSTICK_BOARD_TAB5
	/* The Tab5 C6 has its own load switch; nothing answers SDIO until it is on. */
	tab5_c6_power_on();
#endif
	enable_sdmmc_clock();

	const uint32_t pins[] = { c6_pins.clk, c6_pins.cmd, c6_pins.d0,
				  c6_pins.d1, c6_pins.d2, c6_pins.d3 };
	for (uint32_t i = 0; i < 6u; ++i)
		configure_iomux_gpio(pins[i], i != 0u);

	route_output(c6_pins.clk, 0u); /* SD_CARD_CCLK_2_PAD_OUT_IDX */
	route_output(c6_pins.cmd, 1u); /* SD_CARD_CCMD_2_PAD_OUT_IDX */
	route_output(c6_pins.d0, 2u);
	route_output(c6_pins.d1, 3u);
	route_output(c6_pins.d2, 4u);
	route_output(c6_pins.d3, 5u);
	route_input(1u, c6_pins.cmd); /* CMD */
	route_input(2u, c6_pins.d0); /* DAT0 */
	route_input(3u, c6_pins.d1); /* DAT1 / SDIO interrupt */
	route_input(4u, c6_pins.d2); /* DAT2 */
	route_input(5u, c6_pins.d3); /* DAT3 */
	/*
	 * P4 gates the in-band DAT1 interrupt with a separate per-slot
	 * card_int matrix input. Slot 1 has no separate pin on either board, so
	 * match ESP-IDF's SDMMC host setup and hold that input high.
	 */
	route_input(129u, 0x3fu); /* SD_CARD_INT_N_2_PAD_IN_IDX <- constant one */

	/*
	 * Reset before Linux enumerates the card. ESP-IDF's working SDIO host does
	 * this, whereas the Linux ESP-Hosted module cannot drive the EN pin through its
	 * current legacy gpiolib mapping. This avoids resetting an enumerated card.
	 * M5Stack's official Stamp-P4 ESP-Hosted configuration waits 1500 ms after
	 * a 10 ms active-high / 10 ms inactive / active-high sequence; keep the
	 * same readiness window before handoff.
	 */
	pulse_c6_reset();
	ESP_LOGI(TAG, "Slot 1 SDIO GPIO matrix ready; C6 reset before Linux handoff");
}
