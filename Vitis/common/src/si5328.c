/*
 * si5328.c — Program the Quad SFP28 FMC's Si5328 clock generator
 *
 * Opsero Quad SFP28 FMC (MRMAC) reference design.
 *
 * The Si5328 sources the GT reference clock (GBTCLK0 -> CKOUT1). It sits
 * behind channel 4 of the FMC's PCA9548 I2C mux, reached through the
 * design's AXI IIC. This module programs it for FREE-RUN operation from the
 * card's 114.285 MHz crystal, with CKOUT1 = 322.265625 MHz — the MRMAC GT
 * reference (LCPLL integer-N) used at both the 10G and 25G line rates.
 *
 * Divider plan (same algorithm as the Linux clk-si5324/si5324drv driver,
 * precomputed here for the single fixed frequency; all values EXACT):
 *
 *   fin  = 114.285000 MHz (XA/XB crystal, routed to CKIN2 in free-run mode)
 *   f3   = fin / N3          = 114285000 / 7619    = 15.000 kHz
 *   fosc = f3 * N2           = 15000 * (11*31250)  = 5156.250 MHz
 *   fout = fosc / (N1_HS*NC1) = 5156250000 / (8*2) = 322.265625 MHz
 *
 *   N1_HS = 8, NC1_LS = 2, N2_HS = 11, N2_LS = 31250, N3 = 7619
 *
 * Register encodings follow the Si5328 datasheet (and the Linux driver):
 * N1_HS/N2_HS are stored as value-4, NC1_LS/N2_LS/N3 as value-1. BWSEL = 6
 * (the value the Xilinx si5324drv uses for all plans). The register write
 * sequence mirrors the Linux driver's probe + set_rate path, ending with an
 * internal calibration (ICAL) which the device needs to start its outputs.
 */

#include <stdio.h>
#include "xil_printf.h"
#include "xparameters.h"
#include "xiic_l.h"
#include "sleep.h"
#include "si5328.h"

#define PCA9548_ADDR        0x70
#define PCA9548_CH_SI5328   (1 << 4)   /* mux channel 4 */
#define SI5328_ADDR         0x68

typedef struct { u8 reg; u8 val; } reg_write_t;

/* Free-run, CKIN2 (XA/XB), CKOUT1 = 322.265625 MHz, CKOUT2 disabled */
static const reg_write_t si5328_init_writes[] = {
	{ 0,   0x54 },  /* FREE_RUN = 1 (XA/XB -> CKIN2) */
	{ 2,   0x62 },  /* BWSEL = 6 */
	{ 3,   0x55 },  /* CKSEL_REG = CKIN2, SQ_ICAL = 1 */
	{ 4,   0x12 },  /* AUTOSEL_REG = manual */
	{ 6,   0x0F },  /* SFOUT1 = LVDS, SFOUT2 disabled */
	{ 10,  0x08 },  /* DSBL_CLKOUT2 = 1 (only CKOUT1 used) */
	{ 11,  0x41 },  /* PD_CK1 = 1: power down CKIN1 (free-run uses CKIN2) */
	{ 19,  0x23 },  /* FOS defaults */
	{ 21,  0xFC },  /* CKSEL_PIN = 0: ignore CS_CA pin, select input from
			 * CKSEL_REG. Without this the input selection follows
			 * the (floating/strapped) CS_CA pin and can sit on the
			 * powered-down CKIN1: ICAL never completes and CKOUT1
			 * stays squelched (no GT refclk). */
	{ 25,  0x80 },  /* N1_HS  = 8      -> (8-4)<<5 */
	{ 31,  0x00 },  /* NC1_LS = 2      -> 1 = 0x000001 */
	{ 32,  0x00 },
	{ 33,  0x01 },
	{ 34,  0x00 },  /* NC2_LS = 2 (output disabled; keep legal value) */
	{ 35,  0x00 },
	{ 36,  0x01 },
	{ 40,  0xE0 },  /* N2_HS  = 11     -> (11-4)<<5 ; N2_LS[19:16] = 0 */
	{ 41,  0x7A },  /* N2_LS  = 31250  -> 31249 = 0x007A11 */
	{ 42,  0x11 },
	{ 43,  0x00 },  /* N31 = 7619 -> 7618 = 0x001DC2 (CKIN1; unused, legal) */
	{ 44,  0x1D },
	{ 45,  0xC2 },
	{ 46,  0x00 },  /* N32 = 7619 (CKIN2 = XA/XB in free-run: the active input) */
	{ 47,  0x1D },
	{ 48,  0xC2 },
	{ 137, 0x01 },  /* FASTLOCK = 1 */
	{ 136, 0x40 },  /* ICAL: start internal calibration (must be LAST) */
};

/*
 * Program the Si5328 for 322.265625 MHz on CKOUT1.
 * iic_base: base address of the AXI IIC connected to the FMC PCA9548 mux.
 * Returns 0 on success, -1 on I2C failure.
 */
int si5328_init(UINTPTR iic_base)
{
	u8 buf[2];
	unsigned int sent, i;

	/* Select PCA9548 channel 4 (Si5328) */
	buf[0] = PCA9548_CH_SI5328;
	sent = XIic_Send(iic_base, PCA9548_ADDR, buf, 1, XIIC_STOP);
	if (sent != 1) {
		xil_printf("si5328: failed to select PCA9548 channel (sent %u)\r\n", sent);
		return -1;
	}

	/* Full device reset first (RST_ALL, reg 136 bit 7), as the Linux
	 * clk-si5324 driver does: makes programming deterministic regardless
	 * of prior state (e.g. JTAG re-runs without a power cycle). */
	buf[0] = 136; buf[1] = 0x80;
	sent = XIic_Send(iic_base, SI5328_ADDR, buf, 2, XIIC_STOP);
	if (sent != 2) {
		xil_printf("si5328: device reset write failed (sent %u)\r\n", sent);
		return -1;
	}
	usleep(20000);
	buf[0] = 136; buf[1] = 0x00;
	sent = XIic_Send(iic_base, SI5328_ADDR, buf, 2, XIIC_STOP);
	if (sent != 2) {
		xil_printf("si5328: device reset release failed (sent %u)\r\n", sent);
		return -1;
	}
	usleep(20000);

	for (i = 0; i < sizeof(si5328_init_writes) / sizeof(si5328_init_writes[0]); i++) {
		buf[0] = si5328_init_writes[i].reg;
		buf[1] = si5328_init_writes[i].val;
		sent = XIic_Send(iic_base, SI5328_ADDR, buf, 2, XIIC_STOP);
		if (sent != 2) {
			xil_printf("si5328: write reg %u failed (sent %u)\r\n",
				   si5328_init_writes[i].reg, sent);
			return -1;
		}
	}

	/* Allow the internal calibration to complete (datasheet: ~1s worst
	 * case for low f3; typically much less). The GT won't see a stable
	 * refclk until ICAL is done. */
	sleep(1);

	return 0;
}
