/*
 * main.c — Bare-metal echo server for the Quad SFP28 FMC (MRMAC) design
 *
 * Opsero Quad SFP28 FMC (MRMAC) reference design.
 *
 * lwIP has no adapter for the Versal MRMAC, so this app implements a small
 * raw-Ethernet echo server on each of the four SFP28 ports instead of using
 * the usual lwIP echo-server template. Per port it answers:
 *
 *   - ARP requests for the port's IP address
 *   - ICMP echo requests (ping)
 *   - UDP datagrams to ANY port: payload echoed back to the sender
 *
 * Port N has MAC 00:0a:35:00:0e:0N and IP 192.168.<(N+1)*10>.10/24, so the
 * standard test is:
 *
 *   host$ ping 192.168.10.10                 (port 0)
 *   host$ echo hello | nc -u 192.168.20.10 7 (port 1, any UDP port works)
 *
 * Bring-up sequence: VADJ rail (board specific) -> Si5328 (322.265625 MHz GT
 * refclk) -> per-port GT lane reset -> MRMAC port reset/configure -> MCDMA
 * rings -> poll loop. Link state is re-checked continuously: while a port
 * has no RX block lock the MRMAC port reset is re-issued each second to
 * re-attempt lock (same strategy as the design's Linux carrier monitor).
 */

#include <stdio.h>
#include <string.h>
#include "xil_printf.h"
#include "xil_cache.h"
#include "xil_mmu.h"
#include "xparameters.h"
#include "xmcdma.h"
#include "sleep.h"
#include "board.h"
#include "vadj.h"
#include "si5328.h"
#include "mrmac.h"

/* ------------------------------------------------------------------ */
/* Design configuration                                               */
/* ------------------------------------------------------------------ */

#define NUM_PORTS        4

/* Set by the build flow / target: 10G targets use the 32-bit client and
 * 10GE MAC rate; the _25g targets use 64-bit/25GE. The MODE register is
 * the only software difference, selected here. */
#ifndef LINE_RATE_25G
#define LINE_RATE_25G    0
#endif

/* Peripheral base addresses (SDT-generated names in xparameters.h) */
#define IIC_BASE         XPAR_AXI_IIC_0_BASEADDR
#define MRMAC_BASE       XPAR_MRMAC_BASEADDR

static const UINTPTR mcdma_base[NUM_PORTS] = {
	XPAR_SFP_PORT0_AXI_MCDMA_BASEADDR,
	XPAR_SFP_PORT1_AXI_MCDMA_BASEADDR,
	XPAR_SFP_PORT2_AXI_MCDMA_BASEADDR,
	XPAR_SFP_PORT3_AXI_MCDMA_BASEADDR,
};

static const UINTPTR gpio_gt_base[NUM_PORTS] = {
	XPAR_SFP_PORT0_AXI_GPIO_GT_BASEADDR,
	XPAR_SFP_PORT1_AXI_GPIO_GT_BASEADDR,
	XPAR_SFP_PORT2_AXI_GPIO_GT_BASEADDR,
	XPAR_SFP_PORT3_AXI_GPIO_GT_BASEADDR,
};

/* DMA memory map (DDR low region). The BD space is marked non-cacheable;
 * frame buffers are cached with explicit flush/invalidate. */
#define BD_SPACE_BASE    0x40000000UL              /* 2MB, non-cacheable     */
#define BUF_SPACE_BASE   0x40200000UL              /* frame buffers (cached) */
#define BLOCK_SIZE_2MB   0x200000U

#define RING_BDS         32                        /* BDs per direction      */
#define BUF_SIZE         2048                      /* one frame per buffer   */

#define PORT_BD_STRIDE   0x10000UL                 /* per-port BD space      */
#define PORT_BUF_STRIDE  0x100000UL                /* per-port buffer space  */

/* ------------------------------------------------------------------ */
/* Network protocol bits (big-endian on the wire)                     */
/* ------------------------------------------------------------------ */

#define ETHERTYPE_IP     0x0800
#define ETHERTYPE_ARP    0x0806
#define ARP_REQUEST      1
#define ARP_REPLY        2
#define IPPROTO_ICMP_N   1
#define IPPROTO_UDP_N    17
#define ICMP_ECHO_REQ    8
#define ICMP_ECHO_REPLY  0

typedef struct {
	XMcdma mcdma;
	XMcdma_ChanCtrl *rx_chan;
	XMcdma_ChanCtrl *tx_chan;
	UINTPTR rx_buf_base;
	UINTPTR tx_buf_base;
	u32 rx_idx;            /* next RX buffer index to be completed */
	u32 tx_idx;            /* next TX buffer index to use          */
	u8  mac[6];
	u8  ip[4];
	int link_up;
	u32 rx_frames;
	u32 tx_frames;
} port_ctx_t;

static port_ctx_t ports[NUM_PORTS];

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */

static u16 rd16(const u8 *p)        { return ((u16)p[0] << 8) | p[1]; }
static void wr16(u8 *p, u16 v)      { p[0] = v >> 8; p[1] = v & 0xFF; }

/* RFC1071 checksum over buf[0..len), with optional initial sum */
static u16 ip_checksum(const u8 *buf, int len)
{
	u32 sum = 0;
	while (len > 1) {
		sum += ((u32)buf[0] << 8) | buf[1];
		buf += 2;
		len -= 2;
	}
	if (len)
		sum += (u32)buf[0] << 8;
	while (sum >> 16)
		sum = (sum & 0xFFFF) + (sum >> 16);
	return (u16)~sum;
}

/* ------------------------------------------------------------------ */
/* MCDMA ring setup                                                   */
/* ------------------------------------------------------------------ */

static int port_dma_init(int n)
{
	port_ctx_t *p = &ports[n];
	XMcdma_Config *cfg;
	UINTPTR bd_base = BD_SPACE_BASE + n * PORT_BD_STRIDE;
	int status;
	u32 i;

	cfg = XMcdma_LookupConfig(mcdma_base[n]);
	if (!cfg) {
		xil_printf("port %d: no MCDMA config found\r\n", n);
		return XST_FAILURE;
	}
	status = XMcDma_CfgInitialize(&p->mcdma, cfg);
	if (status != XST_SUCCESS)
		return status;

	p->rx_buf_base = BUF_SPACE_BASE + n * PORT_BUF_STRIDE;
	p->tx_buf_base = p->rx_buf_base + RING_BDS * BUF_SIZE;
	p->rx_idx = 0;
	p->tx_idx = 0;

	/* RX ring: pre-submit every buffer */
	p->rx_chan = XMcdma_GetMcdmaRxChan(&p->mcdma, 1);
	XMcdma_IntrDisable(p->rx_chan, XMCDMA_IRQ_ALL_MASK);
	status = XMcDma_ChanBdCreate(p->rx_chan, bd_base, RING_BDS);
	if (status != XST_SUCCESS)
		return status;
	for (i = 0; i < RING_BDS; i++) {
		UINTPTR buf = p->rx_buf_base + i * BUF_SIZE;
		status = XMcDma_ChanSubmit(p->rx_chan, buf, BUF_SIZE);
		if (status != XST_SUCCESS)
			return status;
		Xil_DCacheInvalidateRange(buf, BUF_SIZE);
	}
	status = XMcDma_ChanToHw(p->rx_chan);
	if (status != XST_SUCCESS)
		return status;

	/* TX ring: BDs created up-front, buffers submitted on demand */
	p->tx_chan = XMcdma_GetMcdmaTxChan(&p->mcdma, 1);
	XMcdma_IntrDisable(p->tx_chan, XMCDMA_IRQ_ALL_MASK);
	status = XMcDma_ChanBdCreate(p->tx_chan, bd_base + 0x8000, RING_BDS);
	if (status != XST_SUCCESS)
		return status;

	return XST_SUCCESS;
}

/* Reclaim completed TX BDs, then queue one frame for transmit. */
static void port_send(port_ctx_t *p, const u8 *frame, u32 len)
{
	XMcdma_Bd *bd, *tx_bd;
	UINTPTR buf = p->tx_buf_base + (p->tx_idx % RING_BDS) * BUF_SIZE;
	int done;

	done = XMcdma_BdChainFromHW(p->tx_chan, RING_BDS, &bd);
	if (done > 0)
		XMcdma_BdChainFree(p->tx_chan, done, bd);

	if (len < 60)
		len = 60;   /* pad runt frames (FCS added by the MAC) */

	memcpy((void *)buf, frame, len);
	Xil_DCacheFlushRange(buf, len);

	/* Grab the BD that ChanSubmit will populate, submit, then mark it
	 * Start-of-Frame AND End-of-Frame. ChanSubmit only writes the length;
	 * without SOF/EOF the MM2S engine never asserts TLAST, so the MRMAC
	 * sees no frame boundary and nothing is transmitted (RX needs no such
	 * flags, which is why receive worked while transmit was silent). One
	 * BD per frame, so the same BD carries both SOF and EOF. */
	tx_bd = (XMcdma_Bd *)XMcdma_GetChanCurBd(p->tx_chan);
	if (XMcDma_ChanSubmit(p->tx_chan, buf, len) != XST_SUCCESS)
		return;
	XMcDma_BdSetCtrl(tx_bd, XMCDMA_BD_CTRL_SOF_MASK | XMCDMA_BD_CTRL_EOF_MASK);
	XMCDMA_CACHE_FLUSH((UINTPTR)tx_bd);
	XMcDma_ChanToHw(p->tx_chan);
	p->tx_idx++;
	p->tx_frames++;
}

/* ------------------------------------------------------------------ */
/* Frame processing: ARP / ICMP echo / UDP echo                       */
/* ------------------------------------------------------------------ */

static void process_frame(port_ctx_t *p, u8 *f, u32 len)
{
	u16 ethertype;

	if (len < 42)
		return;
	ethertype = rd16(f + 12);

	if (ethertype == ETHERTYPE_ARP) {
		/* ARP request for our IP? */
		if (rd16(f + 20) != ARP_REQUEST)
			return;
		if (memcmp(f + 38, p->ip, 4) != 0)
			return;
		/* Build the reply in place */
		memcpy(f + 0, f + 6, 6);            /* dst = requester */
		memcpy(f + 6, p->mac, 6);           /* src = us        */
		wr16(f + 20, ARP_REPLY);
		memcpy(f + 32, f + 22, 10);         /* target = requester (mac+ip) */
		memcpy(f + 22, p->mac, 6);          /* sender mac = us */
		memcpy(f + 28, p->ip, 4);           /* sender ip = us  */
		port_send(p, f, 42);
		return;
	}

	if (ethertype != ETHERTYPE_IP)
		return;
	/* IPv4, no options, addressed to us */
	if ((f[14] & 0xF0) != 0x40 || (f[14] & 0x0F) != 5)
		return;
	if (memcmp(f + 30, p->ip, 4) != 0)
		return;

	if (f[23] == IPPROTO_ICMP_N && f[34] == ICMP_ECHO_REQ) {
		u16 ip_len = rd16(f + 16);
		u32 icmp_len = ip_len - 20;
		if ((u32)ip_len + 14 > len)
			return;
		/* Ethernet: swap */
		memcpy(f + 0, f + 6, 6);
		memcpy(f + 6, p->mac, 6);
		/* IP: swap addresses, clear+recompute checksum */
		memcpy(f + 30, f + 26, 4);
		memcpy(f + 26, p->ip, 4);
		f[22] = 64;                          /* TTL */
		wr16(f + 24, 0);
		wr16(f + 24, ip_checksum(f + 14, 20));
		/* ICMP: echo reply, recompute checksum */
		f[34] = ICMP_ECHO_REPLY;
		wr16(f + 36, 0);
		wr16(f + 36, ip_checksum(f + 34, icmp_len));
		port_send(p, f, 14 + ip_len);
		return;
	}

	if (f[23] == IPPROTO_UDP_N) {
		u16 ip_len = rd16(f + 16);
		if ((u32)ip_len + 14 > len)
			return;
		/* Ethernet: swap */
		memcpy(f + 0, f + 6, 6);
		memcpy(f + 6, p->mac, 6);
		/* IP: swap addresses, recompute checksum */
		memcpy(f + 30, f + 26, 4);
		memcpy(f + 26, p->ip, 4);
		f[22] = 64;
		wr16(f + 24, 0);
		wr16(f + 24, ip_checksum(f + 14, 20));
		/* UDP: swap ports, zero the (optional) checksum */
		{
			u16 sport = rd16(f + 34), dport = rd16(f + 36);
			wr16(f + 34, dport);
			wr16(f + 36, sport);
			wr16(f + 40, 0);
		}
		port_send(p, f, 14 + ip_len);
		return;
	}
}

/* Poll one port's RX ring, echo whatever needs echoing, recycle the BDs. */
static void port_poll(port_ctx_t *p)
{
	XMcdma_Bd *bd, *first_bd;
	int done, i;

	done = XMcdma_BdChainFromHW(p->rx_chan, RING_BDS, &first_bd);
	if (done <= 0)
		return;

	/* RX buffers complete strictly in ring order (BDs were submitted in
	 * buffer-index order), so buffer index = rx_idx for each completed BD. */
	bd = first_bd;
	for (i = 0; i < done; i++) {
		u32 idx = p->rx_idx % RING_BDS;
		UINTPTR buf = p->rx_buf_base + idx * BUF_SIZE;
		u32 len = XMcDma_BdGetActualLength(bd, 0x00FFFFFF);

		Xil_DCacheInvalidateRange(buf, BUF_SIZE);
		p->rx_frames++;
		process_frame(p, (u8 *)buf, len);

		bd = (XMcdma_Bd *)XMcdma_BdChainNextBd(p->rx_chan, bd);
		p->rx_idx++;
	}

	/* Recycle: release the processed BDs back to the ring, then resubmit
	 * the same buffers (in the same order) and hand them to hardware. */
	XMcdma_BdChainFree(p->rx_chan, done, first_bd);
	for (i = done; i > 0; i--) {
		u32 idx = (p->rx_idx - i) % RING_BDS;
		UINTPTR buf = p->rx_buf_base + idx * BUF_SIZE;
		Xil_DCacheInvalidateRange(buf, BUF_SIZE);
		XMcDma_ChanSubmit(p->rx_chan, buf, BUF_SIZE);
	}
	XMcDma_ChanToHw(p->rx_chan);
}

/* ------------------------------------------------------------------ */
/* Main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
	int n, i;
	u32 loops = 0;

	xil_printf("\r\n-------------------------------------------------\r\n");
	xil_printf("Quad SFP28 FMC (MRMAC) echo server - %s\r\n", BOARD_NAME);
	xil_printf("Line rate: %dG per port\r\n", LINE_RATE_25G ? 25 : 10);
	xil_printf("-------------------------------------------------\r\n");

	/* Mark the BD space as non-cacheable */
	Xil_SetTlbAttributes(BD_SPACE_BASE, NORM_NONCACHE);

#if defined(BOARD_VCK190) || defined(BOARD_VMK180) || defined(BOARD_VPK120) || \
    defined(BOARD_VHK158) || defined(BOARD_VPK180)
	/* FMC I/Os on this design are LVCMOS15: VADJ = 1.5V */
	if (vadj_enable(VADJ_1V5) != 0)
		xil_printf("WARNING: failed to enable VADJ\r\n");
	else
		xil_printf("VADJ enabled (1.5V)\r\n");
	sleep(1);
#endif

	/* Program the FMC Si5328: 322.265625 MHz GT refclk on GBTCLK0 */
	if (si5328_init(IIC_BASE) != 0) {
		xil_printf("ERROR: Si5328 programming failed - no GT refclk\r\n");
		return -1;
	}
	xil_printf("Si5328 programmed: GT refclk 322.265625 MHz\r\n");

	for (n = 0; n < NUM_PORTS; n++) {
		port_ctx_t *p = &ports[n];

		p->mac[0] = 0x00; p->mac[1] = 0x0a; p->mac[2] = 0x35;
		p->mac[3] = 0x00; p->mac[4] = 0x0e; p->mac[5] = (u8)n;
		p->ip[0] = 192; p->ip[1] = 168; p->ip[2] = (u8)((n + 1) * 10); p->ip[3] = 10;

		/* One-time GT lane reset, then configure the MAC port */
		if (mrmac_gt_reset(gpio_gt_base[n]) != 0)
			xil_printf("port %d: GT reset-done timeout (no refclk?)\r\n", n);
		mrmac_port_init(MRMAC_BASE + n * MRMAC_PORT_STRIDE, LINE_RATE_25G);

		if (port_dma_init(n) != XST_SUCCESS) {
			xil_printf("port %d: MCDMA init failed\r\n", n);
			return -1;
		}

		xil_printf("port %d: MAC 00:0a:35:00:0e:%02x  IP %d.%d.%d.%d\r\n",
			   n, n, p->ip[0], p->ip[1], p->ip[2], p->ip[3]);
	}

	xil_printf("Echo server running: answers ARP, ICMP ping and UDP echo\r\n\r\n");

	while (1) {
		for (n = 0; n < NUM_PORTS; n++)
			port_poll(&ports[n]);

		/* Roughly once a second: update link state; while a port is
		 * down, re-issue the MRMAC port reset to re-attempt RX block
		 * lock (the GTY does not re-acquire lock on a partner signal
		 * that appears after our last reset). */
		if (++loops >= 100000) {
			loops = 0;
			for (n = 0; n < NUM_PORTS; n++) {
				port_ctx_t *p = &ports[n];
				UINTPTR base = MRMAC_BASE + n * MRMAC_PORT_STRIDE;
				int up = mrmac_port_link_up(base);
				if (up && !p->link_up)
					xil_printf("port %d: link UP\r\n", n);
				else if (!up && p->link_up)
					xil_printf("port %d: link DOWN\r\n", n);
				else if (!up)
					mrmac_port_init(base, LINE_RATE_25G);
				p->link_up = up;
			}
		}
		for (i = 0; i < 10; i++)
			;   /* small pacing delay */
	}

	return 0;
}
