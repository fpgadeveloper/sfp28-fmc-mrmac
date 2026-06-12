/*
 * mrmac.c — Bare-metal MRMAC port bring-up for the Quad SFP28 FMC design
 *
 * Opsero Quad SFP28 FMC (MRMAC) reference design.
 *
 * There is no embeddedsw driver for the Versal MRMAC hard block, so this
 * module drives its per-port registers directly. The register offsets, bit
 * masks and the reset/configuration sequence replicate the Linux
 * xilinx_axienet driver's MRMAC support (the same sequence the PetaLinux
 * flow of this design uses), which in turn follows PG314:
 *
 *   1. one-time GT lane reset through the port's GT-control AXI GPIO
 *      (channel 1 bit 0 = gt_reset_all, channel 2 = tx/rx reset-done)
 *   2. assert the MAC port's TX/RX serdes + core resets
 *   3. program the MODE register (data rate, AXIS config, serdes width)
 *   4. release the resets
 *   5. enable TX (with FCS insertion) and RX (with FCS deletion)
 *
 * Each of the four MAC ports has its own 4KB register page inside the
 * MRMAC's 64KB s_axi window: port N at base + N*0x1000.
 */

#include <stdio.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xgpio.h"
#include "sleep.h"
#include "mrmac.h"

/* Per-port register offsets (PG314 / Linux xilinx_axienet.h) */
#define MRMAC_REV_OFFSET           0x00000000
#define MRMAC_RESET_OFFSET         0x00000004
#define MRMAC_MODE_OFFSET          0x00000008
#define MRMAC_CONFIG_TX_OFFSET     0x0000000C
#define MRMAC_CONFIG_RX_OFFSET     0x00000010
#define MRMAC_TICK_OFFSET          0x0000002C
#define MRMAC_TX_STS_OFFSET        0x00000740
#define MRMAC_RX_STS_OFFSET        0x00000744
#define MRMAC_STATRX_BLKLCK_OFFSET 0x00000754

/* RESET register */
#define MRMAC_RX_SERDES_RST_MASK   (0xF << 0)
#define MRMAC_TX_SERDES_RST_MASK   (1 << 4)
#define MRMAC_RX_RST_MASK          (1 << 5)
#define MRMAC_TX_RST_MASK          (1 << 6)

/* MODE register */
#define MRMAC_CTL_DATA_RATE_MASK   0x7
#define MRMAC_CTL_DATA_RATE_10G    0
#define MRMAC_CTL_DATA_RATE_25G    1
#define MRMAC_CTL_AXIS_CFG_MASK    (0x7 << 9)
#define MRMAC_CTL_AXIS_CFG_SHIFT   9
#define MRMAC_CTL_AXIS_CFG_10G_IND 1
#define MRMAC_CTL_AXIS_CFG_25G_IND_64 1
#define MRMAC_CTL_SERDES_WIDTH_MASK  (0x7 << 4)
#define MRMAC_CTL_SERDES_WIDTH_SHIFT 4
#define MRMAC_CTL_SERDES_WIDTH_10G_WIDE 4
#define MRMAC_CTL_SERDES_WIDTH_25G_WIDE 6
#define MRMAC_CTL_RATE_CFG_MASK    (MRMAC_CTL_DATA_RATE_MASK | \
                                    MRMAC_CTL_AXIS_CFG_MASK | \
                                    MRMAC_CTL_SERDES_WIDTH_MASK)
#define MRMAC_CTL_PM_TICK_MASK     (1u << 30)

/* CONFIG_TX / CONFIG_RX registers */
#define MRMAC_TX_EN_MASK           (1 << 0)
#define MRMAC_TX_INS_FCS_MASK      (1 << 1)
#define MRMAC_RX_EN_MASK           (1 << 0)
#define MRMAC_RX_DEL_FCS_MASK      (1 << 1)

/* Status bits (sticky: write-1-to-clear, then read) */
#define MRMAC_STS_ALL_MASK         0xFFFFFFFF
#define MRMAC_RX_BLKLCK_MASK       (1 << 0)
#define MRMAC_RX_STATUS_MASK       (1 << 0)

#define MRMAC_TICK_TRIGGER         (1 << 0)

/* GT-control GPIO: channel 1 outputs, channel 2 inputs */
#define GT_CTRL_RESET_ALL          (1 << 0)
#define GT_DONE_TX                 (1 << 0)
#define GT_DONE_RX                 (1 << 1)

static inline u32 rd(UINTPTR base, u32 off)        { return Xil_In32(base + off); }
static inline void wr(UINTPTR base, u32 off, u32 v) { Xil_Out32(base + off, v); }

/*
 * One-time GT lane reset through the port's GT-control GPIO. As per PG314
 * the GT reset must only be issued once after power-on; the MAC port reset
 * (mrmac_port_init) is what gets repeated to re-attempt lock.
 * Returns 0 on success, -1 if reset-done did not assert.
 */
int mrmac_gt_reset(UINTPTR gpio_base)
{
	XGpio gpio;
	XGpio_Config *cfg;
	u32 done;
	int timeout = 100; /* x 10ms */

	cfg = XGpio_LookupConfig(gpio_base);
	if (cfg == NULL)
		return -1;
	XGpio_CfgInitialize(&gpio, cfg, cfg->BaseAddress);

	/* Pulse gt_reset_all */
	XGpio_DiscreteWrite(&gpio, 1, GT_CTRL_RESET_ALL);
	usleep(1000);
	XGpio_DiscreteWrite(&gpio, 1, 0);

	/* Wait for tx/rx reset done */
	do {
		done = XGpio_DiscreteRead(&gpio, 2);
		if ((done & (GT_DONE_TX | GT_DONE_RX)) == (GT_DONE_TX | GT_DONE_RX))
			return 0;
		usleep(10000);
	} while (--timeout);

	xil_printf("mrmac: GT reset-done timeout (done=0x%02x)\r\n", (unsigned)done);
	return -1;
}

/*
 * Reset and configure one MRMAC port (axienet_mrmac_reset equivalent).
 * rate_25g: 0 = 10GE (32-bit client), 1 = 25GE (64-bit client); both use
 * the GT "Wide" serdes mode of this design.
 */
void mrmac_port_init(UINTPTR port_base, int rate_25g)
{
	u32 val, reg;

	/* Assert serdes + core resets */
	val = rd(port_base, MRMAC_RESET_OFFSET);
	val |= (MRMAC_RX_SERDES_RST_MASK | MRMAC_TX_SERDES_RST_MASK |
		MRMAC_RX_RST_MASK | MRMAC_TX_RST_MASK);
	wr(port_base, MRMAC_RESET_OFFSET, val);
	usleep(1000);

	/* Rate / AXIS configuration / serdes width */
	reg = rd(port_base, MRMAC_MODE_OFFSET);
	reg &= ~MRMAC_CTL_RATE_CFG_MASK;
	if (rate_25g) {
		reg |= MRMAC_CTL_DATA_RATE_25G;
		reg |= (MRMAC_CTL_AXIS_CFG_25G_IND_64 << MRMAC_CTL_AXIS_CFG_SHIFT);
		reg |= (MRMAC_CTL_SERDES_WIDTH_25G_WIDE << MRMAC_CTL_SERDES_WIDTH_SHIFT);
	} else {
		reg |= MRMAC_CTL_DATA_RATE_10G;
		reg |= (MRMAC_CTL_AXIS_CFG_10G_IND << MRMAC_CTL_AXIS_CFG_SHIFT);
		reg |= (MRMAC_CTL_SERDES_WIDTH_10G_WIDE << MRMAC_CTL_SERDES_WIDTH_SHIFT);
	}
	reg |= MRMAC_CTL_PM_TICK_MASK;
	wr(port_base, MRMAC_MODE_OFFSET, reg);

	/* Release resets */
	val = rd(port_base, MRMAC_RESET_OFFSET);
	val &= ~(MRMAC_RX_SERDES_RST_MASK | MRMAC_TX_SERDES_RST_MASK |
		 MRMAC_RX_RST_MASK | MRMAC_TX_RST_MASK);
	wr(port_base, MRMAC_RESET_OFFSET, val);

	/* Enable TX (insert FCS) and RX (delete FCS) */
	wr(port_base, MRMAC_CONFIG_TX_OFFSET, MRMAC_TX_EN_MASK | MRMAC_TX_INS_FCS_MASK);
	wr(port_base, MRMAC_CONFIG_RX_OFFSET, MRMAC_RX_EN_MASK | MRMAC_RX_DEL_FCS_MASK);

	/* Latch the statistics counters once so they start clean */
	wr(port_base, MRMAC_TICK_OFFSET, MRMAC_TICK_TRIGGER);
}

/*
 * Return 1 if the port has RX block lock AND RX status good (link up).
 * The status registers are sticky: write-1-to-clear, then read the live state.
 */
int mrmac_port_link_up(UINTPTR port_base)
{
	u32 blklck, rxsts;

	wr(port_base, MRMAC_STATRX_BLKLCK_OFFSET, MRMAC_STS_ALL_MASK);
	blklck = rd(port_base, MRMAC_STATRX_BLKLCK_OFFSET);
	if (!(blklck & MRMAC_RX_BLKLCK_MASK))
		return 0;

	wr(port_base, MRMAC_RX_STS_OFFSET, MRMAC_STS_ALL_MASK);
	rxsts = rd(port_base, MRMAC_RX_STS_OFFSET);
	return !!(rxsts & MRMAC_RX_STATUS_MASK);
}
