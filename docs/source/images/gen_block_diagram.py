#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Opsero Electronic Design Inc.
"""
Generate the block diagram for the Opsero Quad SFP28 FMC (MRMAC) reference design docs.

The design drives all four SFP28 ports as clients of a SINGLE Versal Integrated
100G Multirate Ethernet MAC (MRMAC) hard block, configured 4x10GE Wide or
4x25GE Wide (one GTY lane per port, one gt_quad_base). Each port has its own
AXI MCDMA datapath to DDR via the Versal NoC:

  RX: MRMAC port client (no backpressure) -> RX adapter with a 64 KB
      store-and-forward frame FIFO (whole-frame drop, drop counters)
      -> width converter (32/64 -> 256 bit) -> CDC FIFO -> MCDMA S2MM
  TX: MCDMA MM2S -> CDC FIFO -> width converter (256 -> 32/64 bit)
      -> TX adapter -> MRMAC port client

The Si5328 jitter-attenuating clock generator lives on the FMC card behind a
PCA9548 I2C mux (channels 0-3 = SFP module I2C, channel 4 = Si5328); its output
(GBTCLK0) comes through the FMC connector to clock the GT quad's reference-clock
input at 322.265625 MHz.

This file also holds the palette and drawing helpers shared with
gen_bd_diagram.py (the per-port Vivado block-design view).

The output PNG is written next to this script (i.e. into docs/source/images/):
    versal-mrmac-quad-sfp28-block-diagram.png

Usage (from anywhere):
    python3 docs/source/images/gen_block_diagram.py
"""

import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, FancyBboxPatch, FancyArrowPatch

# ---- palette (sampled to match the sfp28-fmc-xxv block diagrams) -------------
C_PS_FILL      = "#D9D9D9"; C_PS_EDGE      = "#7F7F7F"   # PS / NoC column
C_FAB_FILL     = "#F2F2F2"; C_FAB_EDGE     = "#BFBFBF"   # FPGA fabric container
C_DMA_FILL     = "#808080"; C_DMA_EDGE     = "#404040"   # AXI MCDMA (dark grey)
C_BRIDGE_FILL  = "#D6D6D6"; C_BRIDGE_EDGE  = "#7F7F7F"   # datapath bridge (grey)
C_FIFO_FILL    = "#E4F0D0"; C_FIFO_EDGE    = "#7F9A2E"   # RX frame FIFO (green)
C_MAC_FILL     = "#E8E8F2"; C_MAC_EDGE     = "#8C8CC0"   # MRMAC (lavender)
C_GT_FILL      = "#F3EFE2"; C_GT_EDGE      = "#BFB585"   # GT quad (cream)
C_FMC_FILL     = "#DCE6F2"; C_FMC_EDGE     = "#9DB7D4"   # external FMC (blue-grey)
C_CAGE_FILL    = "#FFFFFF"                                # SFP cage (white on FMC)
C_CLK_FILL     = "#FDE9D9"; C_CLK_EDGE     = "#E0B090"   # Si5328 / PCA9548 (peach)
C_CTRL_FILL    = "#ECECEC"; C_CTRL_EDGE    = "#BFBFBF"   # control-plane caption
C_AXARR_FILL   = "#EDF3D4"; C_AXARR_EDGE   = "#A6B85A"   # data arrows (pale green)
C_LINKARR_FILL = "#DAE8F5"; C_LINKARR_EDGE = "#6F9FCF"   # link arrows (pale blue)
C_REFCLK_LINE  = "#C8823C"                                # refclk arrows (orange)
C_CNT_LINE     = "#B03A2E"                                # drop counters (red)
TXT = "#1A1A1A"


def box(ax, x, y, w, h, fc, ec, label, fs=10, rot=0, lw=1.2, weight="normal",
        round_=False, txtcolor=None, ls="-", z=2):
    if round_:
        p = FancyBboxPatch((x + 0.4, y + 0.4), w - 0.8, h - 0.8,
                           boxstyle="round,pad=0.0,rounding_size=1.2",
                           fc=fc, ec=ec, lw=lw, ls=ls, zorder=z)
    else:
        p = plt.Rectangle((x, y), w, h, fc=fc, ec=ec, lw=lw, ls=ls, zorder=z)
    ax.add_patch(p)
    if label:
        ax.text(x + w / 2, y + h / 2, label, ha="center", va="center",
                fontsize=fs, rotation=rot, color=txtcolor or TXT, weight=weight,
                zorder=z + 1, linespacing=1.25)


def titled_box(ax, x, y, w, h, fc, ec, title, body, title_fs=9.5, body_fs=7.6,
               lw=1.2, txtcolor=None, title_dy=2.4, ls="-"):
    """A box() with a bold title line at the top and a smaller body below it."""
    box(ax, x, y, w, h, fc, ec, "", lw=lw, ls=ls)
    cx = x + w / 2
    ax.text(cx, y + h - title_dy, title, ha="center", va="center",
            fontsize=title_fs, weight="bold", color=txtcolor or TXT, zorder=3)
    ax.text(cx, y + (h - title_dy * 1.9) / 2, body, ha="center", va="center",
            fontsize=body_fs, color=txtcolor or TXT, zorder=3, linespacing=1.3)


def harrow(ax, x0, x1, yc, label, fc, ec, double=True, bh=2.0, hh=3.4, hl=3.2,
           fs=8.5, lw=1.1, lab_dy=0.0, lab_color=None, weight="normal"):
    """Horizontal block arrow from x0 to x1.

    double=True  : double-headed (requires x0 < x1).
    double=False : single-headed with the head at x1; works in either
                   direction (x1 may be < x0 for a leftward arrow).
    """
    if double:
        pts = [(x0, yc), (x0 + hl, yc + hh), (x0 + hl, yc + bh),
               (x1 - hl, yc + bh), (x1 - hl, yc + hh), (x1, yc),
               (x1 - hl, yc - hh), (x1 - hl, yc - bh),
               (x0 + hl, yc - bh), (x0 + hl, yc - hh)]
    else:
        s = 1.0 if x1 >= x0 else -1.0   # direction from tail (x0) to head (x1)
        neck = x1 - s * hl              # base of the arrowhead
        pts = [(x0, yc + bh), (neck, yc + bh), (neck, yc + hh),
               (x1, yc), (neck, yc - hh), (neck, yc - bh), (x0, yc - bh)]
    ax.add_patch(Polygon(pts, closed=True, fc=fc, ec=ec, lw=lw, zorder=2))
    if label:
        ax.text((x0 + x1) / 2, yc + lab_dy, label, ha="center", va="center",
                fontsize=fs, color=lab_color or TXT, zorder=3, linespacing=1.15,
                weight=weight)


def route(ax, pts, color, lw=1.6, head=True, ls="-", z=3):
    """Thin poly-line through pts with an arrowhead at the last point."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    if head and len(pts) >= 2:
        ax.plot(xs[:-1], ys[:-1], color=color, lw=lw, ls=ls, zorder=z,
                solid_capstyle="butt")
        ax.add_patch(FancyArrowPatch(pts[-2], pts[-1], arrowstyle="-|>",
                                     mutation_scale=11, lw=lw, color=color,
                                     ls=ls, zorder=z, shrinkA=0, shrinkB=0))
    else:
        ax.plot(xs, ys, color=color, lw=lw, ls=ls, zorder=z)


def refclk_arrow(ax, p0, p1, label, lab_xy, fs=7.8, lw=1.9):
    """Thin single-line arrow (head at p1) for a single clock net, at any angle.

    A reference clock is one net (not a wide bus), so a thin arrow distinguishes
    it from the fat AXI/AXIS/serial bus arrows.
    """
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=13,
                                 lw=lw, color=C_REFCLK_LINE, zorder=3,
                                 shrinkA=0, shrinkB=0))
    ax.text(lab_xy[0], lab_xy[1], label, ha="center", va="center",
            fontsize=fs, color=C_REFCLK_LINE, zorder=4, weight="bold")


def main():
    fig, ax = plt.subplots(figsize=(15.0, 9.6), dpi=120)
    ax.set_xlim(0, 150)
    ax.set_ylim(0, 100)
    ax.axis("off")

    # ---- containers ----------------------------------------------------------
    # PS / NoC column
    box(ax, 3, 6, 16, 88, C_PS_FILL, C_PS_EDGE,
        "Versal PS\n(CIPS)\n\n+\n\nNoC\n+\nDDR4", fs=11, weight="bold")
    # FPGA fabric container
    fab_x0, fab_x1 = 21, 117
    ax.add_patch(plt.Rectangle((fab_x0, 4), fab_x1 - fab_x0, 92,
                               fc=C_FAB_FILL, ec=C_FAB_EDGE, lw=1.3, zorder=1))
    ax.text((fab_x0 + fab_x1) / 2, 97.0, "FPGA Fabric (PL)", ha="center",
            va="bottom", fontsize=13, weight="bold", color=TXT)
    # External FMC block (carries the four SFP28 cages, the PCA9548 I2C mux
    # and the Si5328 clock generator)
    fmc_x0, fmc_x1 = 125, 146
    ax.add_patch(plt.Rectangle((fmc_x0, 4), fmc_x1 - fmc_x0, 92,
                               fc=C_FMC_FILL, ec=C_FMC_EDGE, lw=1.3, zorder=1))
    ax.text((fmc_x0 + fmc_x1) / 2, 97.0, "External to Versal", ha="center",
            va="bottom", fontsize=12, weight="bold", color=TXT)
    ax.text((fmc_x0 + fmc_x1) / 2, 91.5, "Quad SFP28 FMC\n(OP081)", ha="center",
            va="center", fontsize=10.5, weight="bold", color=TXT)

    # ---- column x-coordinates (shared by all four port rows) -----------------
    dma_x, dma_w = 26, 12
    br_x,  br_w  = 45, 24
    mac_x, mac_w = 76, 13   # single MRMAC spanning all rows
    gt_x,  gt_w  = 97, 11   # single GT quad spanning all rows
    box_h = 13.5

    # (port label, box bottom y) - port 0 on top
    rows = [("0", 74.5), ("1", 57.5), ("2", 40.5), ("3", 23.5)]
    top_y = rows[0][1] + box_h + 2
    bot_y = rows[-1][1] - 2
    gt_right = gt_x + gt_w

    # ---- single MRMAC + single GT quad, spanning the four port rows ----------
    box(ax, mac_x, bot_y, mac_w, top_y - bot_y, C_MAC_FILL, C_MAC_EDGE,
        "MRMAC\n\n4x10GbE /\n4x25GbE\n\n4 MAC port\nclients\n\n(MRMAC_\nX0Y0)",
        fs=9.5, weight="bold")
    box(ax, gt_x, bot_y, gt_w, top_y - bot_y, C_GT_FILL, C_GT_EDGE,
        "GT Quad\n(GTY)\n\n4 lanes\n\n10.3125 /\n25.78125\nGb/s",
        fs=8.6, weight="bold")

    # ---- FMC sub-blocks: an SFP28 cage per port -------------------------------
    sub_x, sub_w = 128, 15
    for plabel, by in rows:
        yc = by + box_h / 2
        box(ax, sub_x, yc - 5.5, sub_w, 11, C_CAGE_FILL, C_FMC_EDGE,
            "SFP28\ncage %s" % plabel, fs=9.0, weight="bold")

    # PCA9548 I2C mux + Si5328 clock generator at the bottom of the FMC
    box(ax, sub_x, 13.5, sub_w, 6.5, C_CLK_FILL, C_CLK_EDGE,
        "PCA9548 I2C mux", fs=7.8)
    box(ax, sub_x, 5.5, sub_w, 7, C_CLK_FILL, C_CLK_EDGE,
        "Si5328 clock gen\n322.27 MHz", fs=7.8)

    # ---- per-port datapath rows ----------------------------------------------
    small = dict(bh=1.15, hh=2.1, hl=2.0, fs=6.9, lab_dy=0.0)
    for plabel, by in rows:
        yc = by + box_h / 2
        rx_y0, rx_h = by + 7.1, 6.4          # upper half: RX
        tx_y0, tx_h = by, 6.4                # lower half: TX
        rx_yc = rx_y0 + rx_h / 2
        tx_yc = tx_y0 + tx_h / 2
        # NoC <-> MCDMA  (3x AXI)
        harrow(ax, 19, dma_x, yc, "3x AXI\n256-bit",
               C_AXARR_FILL, C_AXARR_EDGE, lab_dy=0.2, fs=7.6)
        # AXI MCDMA
        box(ax, dma_x, by, dma_w, box_h, C_DMA_FILL, C_DMA_EDGE,
            "AXI\nMCDMA", fs=10, weight="bold", txtcolor="#FFFFFF")
        # RX (S2MM, leftward) and TX (MM2S, rightward) AXIS 256-bit
        harrow(ax, br_x, dma_x + dma_w, rx_yc, "S2MM", C_AXARR_FILL,
               C_AXARR_EDGE, double=False, **small)
        harrow(ax, dma_x + dma_w, br_x, tx_yc, "MM2S", C_AXARR_FILL,
               C_AXARR_EDGE, double=False, **small)
        # RX path: frame FIFO + width conv + CDC
        box(ax, br_x, rx_y0, br_w, rx_h, C_FIFO_FILL, C_FIFO_EDGE,
            "RX: 64 KB frame FIFO (drops whole\nframes) + width conv + CDC FIFO",
            fs=6.9)
        # TX path: CDC + width conv + adapter
        box(ax, br_x, tx_y0, br_w, tx_h, C_BRIDGE_FILL, C_BRIDGE_EDGE,
            "TX: CDC FIFO + width conv\n+ MRMAC port AXIS adapter", fs=6.9)
        # MRMAC client: RX has no backpressure (one-way), TX is AXIS
        harrow(ax, mac_x, br_x + br_w, rx_yc, "RX %s" % plabel, C_AXARR_FILL,
               C_AXARR_EDGE, double=False, **small)
        harrow(ax, br_x + br_w, mac_x, tx_yc, "TX %s" % plabel, C_AXARR_FILL,
               C_AXARR_EDGE, double=False, **small)
        # MRMAC <-> GT quad : one serdes lane per port
        harrow(ax, mac_x + mac_w, gt_x, yc, "lane %s" % plabel,
               C_AXARR_FILL, C_AXARR_EDGE, bh=1.4, hh=2.5, hl=2.0,
               fs=7.4, lab_dy=0.0)
        # GT quad -> SFP28 cage : serial link (pale blue, double headed)
        harrow(ax, gt_right, fmc_x0 + 3, yc, "10G/25G\nDP%s" % plabel,
               C_LINKARR_FILL, C_LINKARR_EDGE, bh=2.2, hh=3.6, hl=3.4,
               fs=7.8, lab_dy=0.2)

    # client width note under the MRMAC client arrows
    ax.text((br_x + br_w + mac_x) / 2, bot_y - 1.2,
            "client: 32-bit (10G)\n64-bit (25G)\n@ 390.625 MHz",
            ha="center", va="top", fontsize=6.6, color="#404040", zorder=3)

    # ---- GBTCLK0 reference clock: Si5328 (on the FMC) -> the GT quad ----------
    # The clock comes through the FMC connector to the GT quad refclk input.
    refclk_arrow(ax, (sub_x, 9), (gt_right, bot_y), "GBTCLK0", (119.5, 13.5))

    # ---- control-plane caption strip -----------------------------------------
    box(ax, 23, 6.0, 62, 10.0, C_CTRL_FILL, C_CTRL_EDGE,
        "AXI-Lite control  |  AXI-IIC -> PCA9548 (ch0-3: SFP module mgmt, ch4: Si5328)\n"
        "per-port GT-control GPIO: ch1 GT resets, ch2 reset-done + RX drop counters\n"
        "MOD_ABS GPIO  |  user LEDs (link status)",
        fs=7.6)

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "versal-mrmac-quad-sfp28-block-diagram.png")
    fig.savefig(out, bbox_inches="tight", pad_inches=0.15, facecolor="white")
    print("wrote", out)


if __name__ == "__main__":
    main()
