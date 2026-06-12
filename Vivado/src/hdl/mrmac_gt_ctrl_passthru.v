// ---------------------------------------------------------------------------
// Opaque passthrough for the MRMAC GT reset-request buses
//
// Opsero Quad SFP28 FMC (MRMAC) reference design.
//
// Purely combinational feed-through of the three 4-bit GT reset-request
// buses (one bit per port, gathered from the four per-port GT-control
// GPIOs). It exists ONLY to make the connection opaque to the system
// device tree (SDT) generator: when the MRMAC's gt_reset_*_in pins are
// reachable from AXI GPIOs through nothing but inline slice/concat
// primitives, sdtgen tries to auto-emit a gt-ctrl-gpios property on the
// MRMAC nodes and produces *syntactically invalid* phandles when the four
// bits come from four DIFFERENT GPIOs ("<& 32 0>"), which breaks every
// downstream device tree compile (Vitis platform and PetaLinux). The
// correct per-port gt-*-gpios properties are set in the design's
// port-config.dtsi instead.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps

module mrmac_gt_ctrl_passthru (
  (* X_INTERFACE_IGNORE = "true" *) input  wire [3:0] rst_all_in,
  (* X_INTERFACE_IGNORE = "true" *) input  wire [3:0] rst_tx_dp_in,
  (* X_INTERFACE_IGNORE = "true" *) input  wire [3:0] rst_rx_dp_in,
  (* X_INTERFACE_IGNORE = "true" *) output wire [3:0] rst_all_out,
  (* X_INTERFACE_IGNORE = "true" *) output wire [3:0] rst_tx_dp_out,
  (* X_INTERFACE_IGNORE = "true" *) output wire [3:0] rst_rx_dp_out
);

  assign rst_all_out   = rst_all_in;
  assign rst_tx_dp_out = rst_tx_dp_in;
  assign rst_rx_dp_out = rst_rx_dp_in;

endmodule
