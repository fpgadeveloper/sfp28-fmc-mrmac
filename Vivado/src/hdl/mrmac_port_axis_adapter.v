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
// The TX adapter is purely combinational glue (the MRMAC TX client HAS
// backpressure, tx_axis_tready). The RX adapter is NOT: the MRMAC RX client
// has no backpressure at all (no rx tready pin on the IP), so every beat it
// presents must be taken on that cycle or it is lost. The RX adapter
// therefore contains a store-and-forward frame FIFO with whole-frame drop
// (see mrmac_port_rx_axis_adapter below) - it is the ONLY place in the RX
// path where frames may be discarded, and it discards them whole.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps

// RX: MRMAC port client (64b pins, DATA_W active) -> standard DATA_W AXIS
// master, through a store-and-forward frame FIFO in the MRMAC client clock
// domain (aclk).
//
// Why: the MRMAC RX client cannot be stalled, but everything downstream can
// (dwidth converter -> CDC FIFO -> AXI MCDMA S2MM -> NoC -> DDR, plus the
// S2MM waiting for free descriptors). Previously the MRMAC beats went
// straight into the dwidth converter with m_axis_tready ignored, so whenever
// the CDC FIFO filled up, individual beats (including TLAST beats) silently
// vanished mid-frame: truncated and MERGED frames reached the DMA while the
// MAC counters stayed clean.
//
// Behaviour of this FIFO:
//  * A frame is released downstream only after its TLAST beat has been
//    written and it was not flagged bad (store-and-forward, "commit").
//  * If the FIFO fills up while a frame is being written, the partial frame
//    is rolled back and the remainder of that frame is discarded: frames are
//    dropped WHOLE, never truncated or merged. Frames that cannot fit at all
//    (> FIFO_BYTES) are dropped the same way.
//  * Frames the MAC flags as errored (tkeep_user[8] on the TLAST beat: FCS
//    error, undersize, ... - see the decode above) are rolled back when
//    DROP_ERR_FRAMES = 1.
//  * After reset, input is ignored up to and including the first TLAST so
//    the FIFO never starts in the middle of a frame.
//  * The output honours m_axis_tready (full AXI4-Stream compliance).
//
// Drop counters (free-running, wrap around), synchronised into sys_clk with
// xpm_cdc_gray so they can be sampled by an AXI GPIO clocked by sys_clk:
//   rx_drop_status[29:6] = frames dropped because the FIFO was full / oversize
//   rx_drop_status[5:0]  = frames dropped because the MAC flagged an error
//
// Memory: FIFO_BYTES of payload (default 64 KB = 6 x 9600-byte jumbo frames
// or 43 x 1518-byte frames), inferred as block RAM, one write + one read port
// in aclk, read path with the BRAM output register enabled.
module mrmac_port_rx_axis_adapter #(
  parameter integer DATA_W          = 64,    // active client width: 32 (10G) or 64 (25G)
  parameter integer FIFO_BYTES      = 65536, // frame FIFO size (power of 2)
  parameter integer DROP_ERR_FRAMES = 1      // 1 = drop frames with the MAC error flag set
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
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXIS, ASSOCIATED_RESET aresetn" *)
  input wire aclk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire aresetn,
  // Drop-counter read-out clock (the AXI GPIO's s_axi_aclk)
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 SYS_CLK CLK" *)
  input wire sys_clk,
  output wire [29:0] rx_drop_status
);
  localparam integer KW    = DATA_W / 8;
  localparam integer DEPTH = FIFO_BYTES / KW;
  localparam integer AW    = $clog2(DEPTH);
  localparam integer MW    = DATA_W + KW + 1;   // {tlast, tkeep, tdata}

  // -------------------------------------------------------------------------
  // Input register (decouples the MRMAC hard-block pins from the FIFO logic)
  // -------------------------------------------------------------------------
  reg              in_valid = 1'b0;
  reg              in_last;
  reg              in_err;
  reg [KW-1:0]     in_keep;
  reg [DATA_W-1:0] in_data;
  always @(posedge aclk) begin
    in_valid <= aresetn & rx_axis_tvalid;
    in_last  <= rx_axis_tlast;
    in_err   <= rx_axis_tkeep_user[8];
    // tkeep_user[7:0] is only valid on the last beat; every other beat is
    // full. Forcing all-ones on non-last beats avoids propagating the
    // undefined tkeep_user value the MRMAC drives mid-frame.
    in_keep  <= rx_axis_tlast ? rx_axis_tkeep_user[KW-1:0] : {KW{1'b1}};
    in_data  <= rx_axis_tdata[DATA_W-1:0];
  end

  // -------------------------------------------------------------------------
  // Frame FIFO storage
  // -------------------------------------------------------------------------
  (* ram_style = "block" *) reg [MW-1:0] mem [0:DEPTH-1];

  reg [AW:0] wr_ptr        = 0;   // speculative write pointer
  reg [AW:0] wr_ptr_commit = 0;   // end of the last complete, good frame
  reg [AW:0] rd_ptr        = 0;

  // -------------------------------------------------------------------------
  // Write side
  // -------------------------------------------------------------------------
  // full_r is registered from the previous cycle's pointers. The fill level
  // can grow by at most one per cycle, so "fill >= DEPTH-1 last cycle" is a
  // safe (one entry conservative) full flag for this cycle's write.
  reg        full_r   = 1'b0;
  reg        synced   = 1'b0;     // a TLAST has been seen since reset
  reg        dropping = 1'b0;     // discarding the rest of the current frame
  reg [23:0] ovf_cnt  = 24'd0;
  reg [5:0]  err_cnt  = 6'd0;

  wire [AW:0] fill = wr_ptr - rd_ptr;   // AW+1 bits: modulo pointer difference

  wire wr_en  = in_valid & synced & ~dropping & ~full_r;
  wire is_bad = (DROP_ERR_FRAMES != 0) & in_err;

  always @(posedge aclk) begin
    if (wr_en)
      mem[wr_ptr[AW-1:0]] <= {in_last, in_keep, in_data};
  end

  always @(posedge aclk) begin
    if (!aresetn) begin
      wr_ptr        <= 0;
      wr_ptr_commit <= 0;
      full_r        <= 1'b0;
      synced        <= 1'b0;
      dropping      <= 1'b0;
      ovf_cnt       <= 24'd0;
      err_cnt       <= 6'd0;
    end else begin
      full_r <= (fill >= DEPTH - 1);
      if (in_valid) begin
        if (!synced) begin
          // Skip the (possibly partial) frame in flight at reset release.
          if (in_last)
            synced <= 1'b1;
        end else if (dropping) begin
          if (in_last) begin
            dropping <= 1'b0;
            ovf_cnt  <= ovf_cnt + 24'd1;
          end
        end else if (full_r) begin
          // No room: roll back the partial frame, discard its remainder.
          wr_ptr <= wr_ptr_commit;
          if (in_last)
            ovf_cnt  <= ovf_cnt + 24'd1;
          else
            dropping <= 1'b1;
        end else if (in_last) begin
          if (is_bad) begin
            wr_ptr  <= wr_ptr_commit;              // roll back bad frame
            err_cnt <= err_cnt + 6'd1;
          end else begin
            wr_ptr        <= wr_ptr + 1'b1;        // commit good frame
            wr_ptr_commit <= wr_ptr + 1'b1;
          end
        end else begin
          wr_ptr <= wr_ptr + 1'b1;
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // Read side: 2-stage pipeline (BRAM read register A, BRAM output register
  // B), full throughput, honours m_axis_tready. Only committed data is read.
  // -------------------------------------------------------------------------
  reg          va = 1'b0, vb = 1'b0;
  reg [MW-1:0] qa, qb;

  wire out_ready = m_axis_tready | ~vb;
  wire load_a    = out_ready | ~va;
  wire rd_avail  = (rd_ptr != wr_ptr_commit);

  always @(posedge aclk) begin
    if (load_a)
      qa <= mem[rd_ptr[AW-1:0]];
    if (out_ready)
      qb <= qa;
  end

  always @(posedge aclk) begin
    if (!aresetn) begin
      va     <= 1'b0;
      vb     <= 1'b0;
      rd_ptr <= 0;
    end else begin
      if (out_ready)
        vb <= va;
      if (load_a) begin
        va <= rd_avail;
        if (rd_avail)
          rd_ptr <= rd_ptr + 1'b1;
      end
    end
  end

  assign m_axis_tvalid = vb;
  assign m_axis_tlast  = qb[MW-1];
  assign m_axis_tkeep  = qb[MW-2 -: KW];
  assign m_axis_tdata  = qb[DATA_W-1:0];

  // -------------------------------------------------------------------------
  // Drop counters -> sys_clk domain (Gray-code CDC; counters change by at
  // most one per aclk cycle, as xpm_cdc_gray requires)
  // -------------------------------------------------------------------------
  wire [23:0] ovf_cnt_sys;
  wire [5:0]  err_cnt_sys;

  xpm_cdc_gray #(
    .DEST_SYNC_FF (3),
    .INIT_SYNC_FF (0),
    .REG_OUTPUT   (1),
    .WIDTH        (24)
  ) ovf_cnt_cdc (
    .src_clk      (aclk),
    .src_in_bin   (ovf_cnt),
    .dest_clk     (sys_clk),
    .dest_out_bin (ovf_cnt_sys)
  );

  xpm_cdc_gray #(
    .DEST_SYNC_FF (3),
    .INIT_SYNC_FF (0),
    .REG_OUTPUT   (1),
    .WIDTH        (6)
  ) err_cnt_cdc (
    .src_clk      (aclk),
    .src_in_bin   (err_cnt),
    .dest_clk     (sys_clk),
    .dest_out_bin (err_cnt_sys)
  );

  assign rx_drop_status = {ovf_cnt_sys, err_cnt_sys};
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
