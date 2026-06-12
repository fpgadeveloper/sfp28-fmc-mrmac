// ---------------------------------------------------------------------------
// MRMAC 4x10GE/4x25GE "Wide" client <-> standard AXI4-Stream adapters
//
// Opsero Quad SFP28 FMC (MRMAC) reference design.
//
// In the MRMAC's 4-port independent "Wide" configurations, each of the four
// MAC ports presents one client lane plus an 11-bit tkeep_user control word.
// As with the 100G client, this is NOT a standard AXI4-Stream bus: in a block
// design the data rides on loose ports (port N uses rx/tx_axis_tdata<2N> and
// rx/tx_axis_tkeep_user<2N>, with per-port handshakes rx/tx_axis_tvalid_N /
// tlast_N / tready_N).
//
// The client lane pins are always 64-bit wide, but the ACTIVE width depends
// on the port rate (PG314, confirmed by the 2025.2 example design client
// logic, which zeroes tdata[63:32] in 10G mode):
//   10GE port ("Independent 32b Non-Segmented") : tdata[31:0],  tkeep_user[3:0]
//   25GE port ("Independent 64b Non-Segmented") : tdata[63:0],  tkeep_user[7:0]
//
// These adapters present one MRMAC port as a standard AXIS stream of the
// port's ACTIVE width - DATA_W is 32 (10G) or 64 (25G) - so the stock
// dwidth-converter / CDC-FIFO / MCDMA datapath delineates frames correctly:
// one TLAST per Ethernet frame. This mirrors the mrmac_axis_adapter modules
// of the 2x QSFP28 FMC (100G) design, reduced from six bonded lanes to the
// single lane of an independent port. Unused upper data/keep bits on the
// MRMAC side are tied low (Verilog zero-extension).
//
// tkeep_user[10:0] decode (PG314, per client lane):
//   [7:0] = tkeep (per-byte valid, only meaningful on the TLAST beat;
//           only [3:0] are used by a 10G port)
//   [8]   = Err     (RX: 1 = errored frame; valid when tlast=1)
//   [9]   = Preempt (frame preemption; unused here)
//   [10]  = Resume  (TX preemption; unused here)
//
// Both modules are purely combinational glue; the downstream CDC FIFO handles
// the clock crossing and buffering. The aclk port carries no logic - it exists
// only so the AXIS interface has an associated clock (FREQ_HZ propagation) in
// IP integrator. NOTE: the MRMAC RX client has no backpressure (no rx tready),
// so the RX adapter does not honor m_axis_tready; downstream must always accept.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps

// RX: MRMAC port client (64b pins, DATA_W active) -> standard DATA_W AXIS master
module mrmac_port_rx_axis_adapter #(
  parameter integer DATA_W = 64   // active client width: 32 (10G) or 64 (25G)
)(
  // From one MRMAC port client (loose ports; not part of an AXIS interface)
  (* X_INTERFACE_IGNORE = "true" *) input wire [63:0] rx_axis_tdata,
  (* X_INTERFACE_IGNORE = "true" *) input wire [10:0] rx_axis_tkeep_user,
  (* X_INTERFACE_IGNORE = "true" *) input wire        rx_axis_tlast,
  (* X_INTERFACE_IGNORE = "true" *) input wire        rx_axis_tvalid,
  // To a standard AXIS slave (axis_dwidth_converter S_AXIS)
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA"  *) output wire [DATA_W-1:0]   m_axis_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP"  *) output wire [DATA_W/8-1:0] m_axis_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST"  *) output wire                m_axis_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output wire                m_axis_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input  wire                m_axis_tready,
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXIS" *)
  input wire aclk
);
  assign m_axis_tdata  = rx_axis_tdata[DATA_W-1:0];
  // tkeep_user[7:0] is only valid on the last beat; every other beat is full.
  // Forcing all-ones on non-last beats avoids propagating the undefined
  // tkeep_user value the MRMAC drives mid-frame.
  assign m_axis_tkeep  = rx_axis_tlast ? rx_axis_tkeep_user[DATA_W/8-1:0]
                                       : {DATA_W/8{1'b1}};
  assign m_axis_tlast  = rx_axis_tlast;
  assign m_axis_tvalid = rx_axis_tvalid;
endmodule

// TX: standard DATA_W AXIS slave -> MRMAC port client (64b pins, DATA_W active)
module mrmac_port_tx_axis_adapter #(
  parameter integer DATA_W = 64   // active client width: 32 (10G) or 64 (25G)
)(
  // From a standard AXIS master (axis_dwidth_converter M_AXIS)
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA"  *) input  wire [DATA_W-1:0]   s_axis_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TKEEP"  *) input  wire [DATA_W/8-1:0] s_axis_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST"  *) input  wire                s_axis_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *) input  wire                s_axis_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *) output wire                s_axis_tready,
  // To one MRMAC port client (loose ports; not part of an AXIS interface)
  (* X_INTERFACE_IGNORE = "true" *) output wire [63:0] tx_axis_tdata,
  (* X_INTERFACE_IGNORE = "true" *) output wire [10:0] tx_axis_tkeep_user,
  (* X_INTERFACE_IGNORE = "true" *) output wire        tx_axis_tlast,
  (* X_INTERFACE_IGNORE = "true" *) output wire        tx_axis_tvalid,
  (* X_INTERFACE_IGNORE = "true" *) input  wire        tx_axis_tready,
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXIS" *)
  input wire aclk
);
  // Continuous assignment zero-extends the narrower 10G client data/keep onto
  // the fixed 64-bit/8-bit MRMAC lane pins.
  assign tx_axis_tdata = s_axis_tdata;
  // Per-byte keep from the AXIS tkeep; upper control bits [10:8] (Err/Preempt/
  // Resume) tied 0. tkeep is full on non-last beats and partial on the last
  // beat, exactly what the MRMAC expects (it only consults keep when tlast=1).
  wire [7:0] tkeep_ext = s_axis_tkeep;
  assign tx_axis_tkeep_user = {3'b000, tkeep_ext};
  assign tx_axis_tlast  = s_axis_tlast;
  assign tx_axis_tvalid = s_axis_tvalid;
  assign s_axis_tready  = tx_axis_tready;
endmodule
