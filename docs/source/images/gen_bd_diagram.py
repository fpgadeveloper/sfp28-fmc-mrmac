#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Opsero Electronic Design Inc.
"""
Generate the per-port block-design (Vivado) diagram for the Opsero Quad SFP28 FMC
(MRMAC) reference design docs.

Where versal-mrmac-quad-sfp28-block-diagram.png (gen_block_diagram.py) is the
conceptual view of the whole design, this one zooms into ONE port: the
`sfp_port<N>` hierarchy that Vivado/src/bd/bd_versal.tcl (proc create_sfp_port)
builds once per SFP28 port, with the cells it connects to at the top level
(NoC, CIPS, MRMAC, GT quad). Every box is a real cell of the block design and
every number a real property of the built design:

  RX: mrmac port N client -> rx_axis_adapter (64 KB store-and-forward frame
      FIFO, whole-frame drop, drop counters) -> rx_dwidth -> rx_cdc_fifo
      -> axi_mcdma S2MM
  TX: axi_mcdma MM2S -> tx_cdc_fifo -> tx_dwidth -> tx_axis_adapter
      -> mrmac port N client
  control: axi_smc_lite -> axi_mcdma S_AXI_LITE + axi_gpio_gt
      (CH1 = GT resets, CH2 = reset-done + RX drop counters)

It reuses the palette and drawing helpers of gen_block_diagram.py so that both
diagrams look the same.

The output PNG is written next to this script (i.e. into docs/source/images/):
    versal-mrmac-sfp-port-bd-diagram.png

Usage (from anywhere):
    python3 docs/source/images/gen_bd_diagram.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_block_diagram as g                                   # noqa: E402
from gen_block_diagram import (box, titled_box, harrow, route,  # noqa: E402
                               plt)
from matplotlib.patches import FancyBboxPatch                   # noqa: E402

TXT = g.TXT
C_CTRL_LINE = "#8C8C8C"                 # AXI-Lite / control nets
C_RST_LINE = "#7B5AA6"                  # GT reset / reset-done nets (purple)
C_SYS_DOM = "#F4F7FB"                   # 100 MHz domain shading
C_AXIS_DOM = "#FBF7EE"                  # 390.625 MHz domain shading
C_HIER_EDGE = "#8C8CC0"


def region(ax, x0, y0, x1, y1, label, lab_fs=9.0, fc="none", ec=C_HIER_EDGE,
           ls=(0, (5, 3)), lw=1.2, z=1.1, lab_color="#404040", lab_ha="left"):
    """Dashed rounded region with a bold label at its top edge."""
    ax.add_patch(FancyBboxPatch((x0, y0), x1 - x0, y1 - y0,
                                boxstyle="round,pad=0.0,rounding_size=0.8",
                                fc=fc, ec=ec, lw=lw, ls=ls, zorder=z))
    if label:
        lx = x0 + 1.0 if lab_ha == "left" else (x0 + x1) / 2
        ax.text(lx, y1 - 1.6, label, ha=lab_ha, va="center",
                fontsize=lab_fs, weight="bold", color=lab_color, zorder=3)


def small(ax, x, y, s, fs=6.8, ha="center", color="#404040", weight="normal",
          z=4, va="center"):
    ax.text(x, y, s, ha=ha, va=va, fontsize=fs, color=color, zorder=z,
            linespacing=1.3, weight=weight)


def main():
    fig, ax = plt.subplots(figsize=(20.0, 13.0), dpi=120)
    ax.set_xlim(0, 200)
    ax.set_ylim(0, 130)
    ax.axis("off")

    ax.text(100, 128.5,
            "Block design  mrmac  -  one SFP28 port: hierarchy  sfp_port<N>   "
            "(Vivado/src/bd/bd_versal.tcl, proc create_sfp_port)",
            ha="center", va="top", fontsize=12.5, weight="bold", color=TXT)

    # ---- rows and columns -----------------------------------------------------
    rx_y0, rx_y1 = 94.0, 116.0          # RX row (flows right to left)
    tx_y0, tx_y1 = 70.0, 86.0           # TX row (flows left to right)
    rx_yc = 104.0                       # RX data arrows
    tx_yc = (tx_y0 + tx_y1) / 2
    noc_x0, noc_x1 = 2.0, 19.0
    dma_x0, dma_x1 = 27.0, 44.0
    cdc_x0, cdc_x1 = 51.0, 67.0         # CDC FIFOs straddle the domain border
    dom_x = 59.0                        # 100 MHz | 390.625 MHz border
    dw_x0, dw_x1 = 73.0, 87.0
    ad_x0, ad_x1 = 94.0, 148.0          # adapters
    hier_x0, hier_x1 = 23.0, 151.0
    mac_x0, mac_x1 = 157.0, 179.0
    gt_x0, gt_x1 = 183.0, 198.0

    # ---- top-level cells on the left: NoC + CIPS -------------------------------
    titled_box(ax, noc_x0, 66.0, noc_x1 - noc_x0, 50.0, g.C_PS_FILL, g.C_PS_EDGE,
               "axi_noc_0",
               "three slave ports\nper SFP28 port:\n\nS(6+3N)  SG\n→ MC_0\n\n"
               "S(7+3N)  MM2S\n→ MC_1\n\nS(8+3N)  S2MM\n→ MC_2\n\naclk6 = 100 MHz\n\n"
               "→ DDR4 (one\nmemory controller)", body_fs=6.9, title_fs=9.5)
    titled_box(ax, noc_x0, 14.0, noc_x1 - noc_x0, 46.0, g.C_PS_FILL, g.C_PS_EDGE,
               "versal_cips_0",
               "M_AXI_LPD\n→ axi_smc\n→ M0(N+1)\n\npl_ps_irq 2N\n← MCDMA mm2s\n\n"
               "pl_ps_irq 2N+1\n← MCDMA s2mm\n\npl0_ref_clk\n→ clock wizards\n\n"
               "pl0_resetn\n→ rst_100m,\n   rst_390m625", body_fs=6.9, title_fs=9.5)

    # ---- the hierarchy and its two clock domains ------------------------------
    region(ax, hier_x0, 10.0, hier_x1, 123.0,
           "sfp_port<N>   (one hierarchy per SFP28 port, N = 0..3)",
           fc="#FAFAFD", lab_fs=9.6)
    ax.add_patch(plt.Rectangle((hier_x0 + 1, 66.0), dom_x - hier_x0 - 1, 52.5,
                               fc=C_SYS_DOM, ec="none", zorder=1.2))
    ax.add_patch(plt.Rectangle((dom_x, 66.0), hier_x1 - 1 - dom_x, 52.5,
                               fc=C_AXIS_DOM, ec="none", zorder=1.2))
    ax.plot([dom_x, dom_x], [66.0, 118.5], color="#B5B5B5", lw=1.0,
            ls=(0, (3, 3)), zorder=1.3)
    small(ax, (hier_x0 + dom_x) / 2, 117.0, "sys_clk  100 MHz", fs=7.6,
          weight="bold", color="#5A6E8C")
    small(ax, (dom_x + hier_x1) / 2, 117.0, "axis_clk  390.625 MHz  (MRMAC client)",
          fs=7.6, weight="bold", color="#8A6D12")

    # ---- axi_mcdma ------------------------------------------------------------
    titled_box(ax, dma_x0, rx_y0 - 24.0, dma_x1 - dma_x0, 46.0, g.C_DMA_FILL,
               g.C_DMA_EDGE, "axi_mcdma",
               "1 S2MM + 1 MM2S\nchannel\n256-bit data\n64-bit addresses\nDRE on\n\n"
               "@ 0x8005_0000\n+ N × 0x2_0000\n\nS2MM packet drop\ncount (+0x514)\n"
               "= ethtool -S\nrx_dma_pkt_drop", txtcolor="#FFFFFF", body_fs=6.9)
    # NoC <-> MCDMA (SG, MM2S, S2MM)
    for i, (lab, yc) in enumerate((("SG", 110.0), ("MM2S", 96.0), ("S2MM", 82.0))):
        harrow(ax, noc_x1, dma_x0, yc, lab, g.C_AXARR_FILL, g.C_AXARR_EDGE,
               bh=1.5, hh=2.6, hl=1.8, fs=6.8)

    # ---- RX row (right to left) -----------------------------------------------
    titled_box(ax, cdc_x0, rx_y0 + 2, cdc_x1 - cdc_x0, 16.0, g.C_BRIDGE_FILL,
               g.C_BRIDGE_EDGE, "rx_cdc_fifo",
               "axis_data_fifo\n512 × 256 bit\nasync clocks\npacket mode",
               body_fs=6.7, title_fs=8.4)
    titled_box(ax, dw_x0, rx_y0 + 2, dw_x1 - dw_x0, 16.0, g.C_BRIDGE_FILL,
               g.C_BRIDGE_EDGE, "rx_dwidth",
               "axis_dwidth_\nconverter\n4 B (10G) / 8 B\n(25G) → 32 B",
               body_fs=6.7, title_fs=8.4)
    # the RX adapter with its internals
    box(ax, ad_x0, rx_y0 - 4.0, ad_x1 - ad_x0, rx_y1 - rx_y0 + 4.0,
        g.C_MAC_FILL, g.C_MAC_EDGE, "", lw=1.3)
    small(ax, (ad_x0 + ad_x1) / 2, rx_y1 - 1.8,
          "rx_axis_adapter   (mrmac_port_rx_axis_adapter, Vivado/src/hdl)",
          fs=8.2, weight="bold", color=TXT)
    titled_box(ax, ad_x1 - 11.5, 98.0, 10.5, 13.5, "#FFFFFF", g.C_MAC_EDGE,
               "input reg", "err flag =\ntkeep_user[8]\non TLAST\n\nkeep forced\nfull mid-frame",
               body_fs=6.2, title_fs=7.4, title_dy=2.0)
    titled_box(ax, ad_x0 + 1.5, 98.0, 38.5, 13.5, g.C_FIFO_FILL, g.C_FIFO_EDGE,
               "frame FIFO  64 KB  (block RAM, store-and-forward)",
               "write: a frame is committed at its TLAST if not flagged bad\n"
               "FIFO full → partial frame rolled back, rest of frame discarded\n"
               "MAC error flag → frame rolled back   (DROP_ERR_FRAMES = 1)\n"
               "read: committed frames only, honours m_axis_tready",
               body_fs=6.2, title_fs=7.4, title_dy=2.0)
    titled_box(ax, ad_x0 + 1.5, rx_y0 - 3.0, 38.5, 5.6, "#FFFFFF", g.C_CNT_LINE,
               "", "drop counters: overflow 24 bit, error 6 bit (wrap)\n"
               "→ xpm_cdc_gray → sys_clk → rx_drop_status[29:0]",
               body_fs=6.1, title_dy=0.0)
    harrow(ax, ad_x1 - 11.5, ad_x0 + 40.0, 104.8, "", g.C_AXARR_FILL,
           g.C_AXARR_EDGE, double=False, bh=1.0, hh=1.9, hl=1.5)
    # RX data arrows: MRMAC -> adapter -> dwidth -> cdc -> MCDMA
    harrow(ax, mac_x0, ad_x1, rx_yc + 0.8, "RX client\nno tready", g.C_AXARR_FILL,
           g.C_AXARR_EDGE, double=False, bh=1.5, hh=2.6, hl=1.8, fs=6.3)
    harrow(ax, ad_x0 + 1.5, dw_x1, rx_yc, "", g.C_AXARR_FILL,
           g.C_AXARR_EDGE, double=False, bh=1.5, hh=2.6, hl=1.8)
    harrow(ax, dw_x0, cdc_x1, rx_yc, "", g.C_AXARR_FILL, g.C_AXARR_EDGE,
           double=False, bh=1.5, hh=2.6, hl=1.6)
    harrow(ax, cdc_x0, dma_x1, rx_yc, "S2MM", g.C_AXARR_FILL, g.C_AXARR_EDGE,
           double=False, bh=1.5, hh=2.6, hl=1.6, fs=6.3)
    small(ax, (ad_x0 + dw_x1) / 2 + 1.0, rx_yc + 4.6, "AXIS\n32/64 b", fs=6.2)
    small(ax, (dw_x0 + cdc_x1) / 2, rx_yc + 4.6, "256 b", fs=6.2)

    # ---- TX row (left to right) -----------------------------------------------
    titled_box(ax, cdc_x0, tx_y0, cdc_x1 - cdc_x0, tx_y1 - tx_y0, g.C_BRIDGE_FILL,
               g.C_BRIDGE_EDGE, "tx_cdc_fifo",
               "axis_data_fifo\n512 × 256 bit\nasync, packet mode",
               body_fs=6.7, title_fs=8.4)
    titled_box(ax, dw_x0, tx_y0, dw_x1 - dw_x0, tx_y1 - tx_y0, g.C_BRIDGE_FILL,
               g.C_BRIDGE_EDGE, "tx_dwidth",
               "32 B → 4 B (10G)\n/ 8 B (25G)", body_fs=6.7, title_fs=8.4)
    titled_box(ax, ad_x0, tx_y0, ad_x1 - ad_x0, tx_y1 - tx_y0, g.C_MAC_FILL,
               g.C_MAC_EDGE, "tx_axis_adapter   (mrmac_port_tx_axis_adapter)",
               "combinational: AXIS → MRMAC client lane tx_axis_tdata<2N>\n"
               "tkeep → tkeep_user<2N>;  backpressure from tx_axis_tready_N",
               body_fs=6.7, title_fs=8.2)
    harrow(ax, dma_x1, cdc_x0, tx_yc, "MM2S", g.C_AXARR_FILL, g.C_AXARR_EDGE,
           double=False, bh=1.5, hh=2.6, hl=1.6, fs=6.3)
    harrow(ax, cdc_x1, dw_x0, tx_yc, "", g.C_AXARR_FILL, g.C_AXARR_EDGE,
           double=False, bh=1.5, hh=2.6, hl=1.6)
    harrow(ax, dw_x1, ad_x0, tx_yc, "", g.C_AXARR_FILL, g.C_AXARR_EDGE,
           double=False, bh=1.5, hh=2.6, hl=1.6)
    harrow(ax, ad_x1, mac_x0, tx_yc, "TX client", g.C_AXARR_FILL, g.C_AXARR_EDGE,
           double=False, bh=1.5, hh=2.6, hl=1.8, fs=6.3)

    # ---- control band ---------------------------------------------------------
    titled_box(ax, dma_x0, 38.0, dma_x1 - dma_x0, 22.0, g.C_CTRL_FILL,
               g.C_CTRL_EDGE, "axi_smc_lite",
               "SmartConnect\n\nS00 ← axi_smc\nM0(N+1)\n\nM00 → axi_mcdma\nM01 → axi_gpio_gt",
               body_fs=6.7, title_fs=8.6)
    route(ax, [(dma_x0 + 6.0, 60.0), (dma_x0 + 6.0, 66.0)], C_CTRL_LINE)
    route(ax, [(dma_x1, 49.0), (cdc_x0, 49.0)], C_CTRL_LINE)
    route(ax, [(noc_x1, 30.0), (22.0, 30.0), (22.0, 46.0), (dma_x0, 46.0)],
          C_CTRL_LINE)
    small(ax, 21.0, 27.5, "AXI-Lite", fs=6.2, ha="left")

    titled_box(ax, cdc_x0, 18.0, dw_x1 - cdc_x0, 42.0, "#FFFFFF", g.C_CNT_LINE,
               "axi_gpio_gt   @ 0x8004_0000 + N × 0x2_0000",
               "dual channel AXI GPIO, 100 MHz\n\n"
               "CH1  GPIO_DATA  (+0x0)  5 outputs\n"
               "[0] gt_reset_all\n[1] gt_reset_tx_datapath\n"
               "[2] gt_reset_rx_datapath\n[4:3] spare (gt-ctrl-rate)\n\n"
               "CH2  GPIO2_DATA  (+0x8)  32 inputs\n"
               "[0] gt_tx_reset_done   [1] gt_rx_reset_done\n"
               "[7:2] RX frames dropped: MAC error\n"
               "[31:8] RX frames dropped: FIFO overflow",
               body_fs=6.8, title_fs=8.2)
    # drop counters -> GPIO CH2 (red)
    route(ax, [(ad_x0 + 1.5, rx_y0 - 0.2), (91.0, rx_y0 - 0.2), (91.0, 45.0),
               (dw_x1, 45.0)], g.C_CNT_LINE, lw=1.7)
    small(ax, 92.0, 60.0, "rx_drop_status\n[29:0] → CH2\n[31:2]", fs=6.2,
          ha="left", color=g.C_CNT_LINE)

    # GT resets / reset-done <-> MRMAC (purple)
    route(ax, [(dw_x1, 28.0), (153.0, 28.0), (153.0, 62.0), (mac_x0, 62.0)],
          C_RST_LINE, lw=1.5)
    route(ax, [(mac_x0, 59.0), (155.0, 59.0), (155.0, 24.0), (dw_x1, 24.0)],
          C_RST_LINE, lw=1.5)
    small(ax, 118.0, 29.6, "CH1 [2:0] → mrmac gt_reset_*_in[N]  (via gt_ctrl_passthru)",
          fs=6.4, color=C_RST_LINE)
    small(ax, 118.0, 22.4, "mrmac gt_tx/rx_reset_done_out[N] → CH2 [1:0]",
          fs=6.4, color=C_RST_LINE)

    # SFP sideband
    titled_box(ax, ad_x0, 34.0, ad_x1 - ad_x0 - 6.0, 18.0, g.C_CTRL_FILL,
               g.C_CTRL_EDGE, "SFP sideband   (inline logic, no software)",
               "TX_DISABLE = 0 (transmitter on)\n"
               "RS0 / RS1 = 0 on 10G targets, 1 on 25G targets\n"
               "green LED = module present AND stat_rx_status_N\n"
               "red LED = module present AND link down\n"
               "MOD_ABS → LEDs + shared axi_gpio_modabs",
               body_fs=6.6, title_fs=7.8)

    # ---- MRMAC + GT quad + FMC on the right -----------------------------------
    titled_box(ax, mac_x0, 56.0, mac_x1 - mac_x0, 62.0, g.C_MAC_FILL, g.C_MAC_EDGE,
               "mrmac",
               "MRMAC_X0Y0\n4x10GE / 4x25GE Wide\n\nport N client\n(loose pins):\n"
               "rx_axis_tdata<2N>\nrx_axis_tkeep_user<2N>\nrx_axis_tvalid_N\n"
               "rx_axis_tlast_N\nNO rx tready\n\ntx_axis_tdata<2N>\ntx_axis_tkeep_user<2N>\n"
               "tx_axis_tready_N\n\nstat_rx_status_N\n→ LEDs\n\ns_axi port page\n"
               "0x8001_0000\n+ N × 0x1000", body_fs=6.7, title_fs=9.5)
    titled_box(ax, gt_x0, 76.0, gt_x1 - gt_x0, 40.0, g.C_GT_FILL, g.C_GT_EDGE,
               "gt_quad_base_0",
               "lane N\n\n10.3125 or\n25.78125 Gb/s\n\nRAW, LCPLL\nrefclk\n"
               "322.265625 MHz\n(GBTCLK0 from\nthe FMC Si5328)", body_fs=6.6,
               title_fs=7.6)
    harrow(ax, mac_x1, gt_x0, 100.0, "", g.C_AXARR_FILL, g.C_AXARR_EDGE,
           bh=1.4, hh=2.4, hl=1.5)
    box(ax, gt_x0, 58.0, gt_x1 - gt_x0, 12.0, g.C_FMC_FILL, g.C_FMC_EDGE,
        "FMC DPN\n→ SFP28\ncage N", fs=7.4, weight="bold")
    # serial lane: GT quad -> FMC (short down arrow)
    ax.add_patch(plt.Polygon([(189.0, 76.0), (192.0, 76.0), (192.0, 73.0),
                              (193.5, 73.0), (190.5, 70.0), (187.5, 73.0),
                              (189.0, 73.0)], closed=True, fc=g.C_LINKARR_FILL,
                             ec=g.C_LINKARR_EDGE, lw=1.0, zorder=2))

    # ---- clocks / shared cells / legend (bottom right) ------------------------
    titled_box(ax, mac_x0, 10.0, gt_x1 - mac_x0, 42.0, g.C_CLK_FILL, g.C_CLK_EDGE,
               "Clocks, resets, shared cells (top level)",
               "sys_clk = clk_wizard_0/clk_100m\n(AXI-Lite, MCDMA, NoC, GPIO)\n\n"
               "axis_clk = axis_clk_wiz/clk_390m625\n(MRMAC client, adapters,\n"
               "dwidth converters)\n\n"
               "rst_100m, rst_390m625 ← pl0_resetn\n(the drop counters clear only\n"
               "with rst_390m625)\n\n"
               "axi_iic_0 @ 0x8003_0000 → PCA9548\naxi_gpio_modabs @ 0x8002_0000\n"
               "gt_quad APB3 @ 0x8000_0000", body_fs=6.6, title_fs=7.8)

    # ---- GPIO2_DATA bit field strip -------------------------------------------
    by0, bh = 1.0, 6.0
    x_l, x_r = 30.0, 148.0
    span = x_r - x_l
    fields = [(31, 8, "[31:8]  overflow drops (24 bit, wraps)", "#FBE3E0"),
              (7, 2, "[7:2]  MAC-error drops\n(6 bit, wraps)", "#FDF0D8"),
              (1, 1, "[1]\nrx_rst\ndone", "#E9EEF6"),
              (0, 0, "[0]\ntx_rst\ndone", "#E9EEF6")]
    x = x_l
    for hi, lo, lab, fc in fields:
        w = span * (hi - lo + 1) / 32.0
        w = max(w, 7.0) if hi - lo < 2 else w
        box(ax, x, by0, w, bh, fc, g.C_CNT_LINE, lab, fs=6.4, lw=1.0)
        x += w
    small(ax, x_l - 0.8, by0 + bh / 2, "GPIO2_DATA\n(axi_gpio_gt\n+ 0x8)", fs=6.6,
          ha="right", weight="bold", color=g.C_CNT_LINE)

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "versal-mrmac-sfp-port-bd-diagram.png")
    fig.savefig(out, bbox_inches="tight", pad_inches=0.15, facecolor="white")
    print("wrote", out)


if __name__ == "__main__":
    main()
