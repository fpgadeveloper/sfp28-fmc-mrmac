/*
 * mrmac.h — Bare-metal MRMAC port bring-up for the Quad SFP28 FMC design
 */

#ifndef MRMAC_H
#define MRMAC_H

#include "xil_types.h"

/* Each MAC port owns a 4KB register page inside the MRMAC s_axi window */
#define MRMAC_PORT_STRIDE   0x1000

int  mrmac_gt_reset(UINTPTR gpio_base);
void mrmac_port_init(UINTPTR port_base, int rate_25g);
int  mrmac_port_link_up(UINTPTR port_base);

#endif
