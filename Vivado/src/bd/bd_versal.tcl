################################################################
# Block design build script for Versal Quad SFP28 FMC designs (MRMAC 10G/25G)
#
# Opsero Quad SFP28 FMC (MRMAC) reference design.
#
# This script is sourced by build.tcl, which sets:
#   block_name = mrmac
#   board_name = vck190
#   ports      = { 0 1 2 3 }  (SFP28 ports to populate)
#   line_rate  = 10 | 25      (Gb/s per port)
#
# All four SFP28 ports are clients of a SINGLE Versal MRMAC hard block
# (MRMAC_X0Y0) in its 4x10GE Wide or 4x25GE Wide configuration, one GTY lane
# per port (FMC DP0-3, one gt_quad_base). Each port gets an AXI MCDMA datapath
# to DDR via the NoC, mirroring the structure of the 2x QSFP28 FMC (100G)
# design. GT and clocking configuration replicate the Vivado 2025.2 MRMAC
# example designs (see gt_settings.tcl and the mrmac_mbufg_gt wrapper).
################################################################

# CHECKING IF PROJECT EXISTS
if { [get_projects -quiet] eq "" } {
   puts "ERROR: Please open or create a project!"
   return 1
}

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

create_bd_design $block_name
current_bd_design $block_name

set parentCell [get_bd_cells /]
set parentObj [get_bd_cells $parentCell]
if { $parentObj == "" } {
   puts "ERROR: Unable to find parent cell <$parentCell>!"
   return
}
set parentType [get_property TYPE $parentObj]
if { $parentType ne "hier" } {
   puts "ERROR: Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."
   return
}

set oldCurInst [current_bd_instance .]
current_bd_instance $parentObj

# Returns true if str contains substr
proc str_contains {str substr} {
  if {[string first $substr $str] == -1} { return 0 } else { return 1 }
}

# Target board checks
set is_vck190 [str_contains $board_name "vck190"]

# Number of ports
set num_ports [llength $ports]

# MRMAC configuration preset for the requested line rate
if {$line_rate == "25"} {
  set mrmac_preset "4x25GE Wide"
} else {
  set mrmac_preset "4x10GE Wide"
}

# List of interrupt pins
set intr_list {}

# Add the CIPS
create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips versal_cips_0

# Configure the CIPS using automation feature (vck190 = DDR branch)
apply_bd_automation -rule xilinx.com:bd_rule:cips -config { \
  board_preset {Yes} \
  boot_config {Custom} \
  configure_noc {Add new AXI NoC} \
  debug_config {JTAG} \
  design_flow {Full System} \
  mc_type {DDR} \
  num_mc_ddr {1} \
  num_mc_lpddr {None} \
  pl_clocks {None} \
  pl_resets {None} \
}  [get_bd_cells versal_cips_0]

# Extra PS PMC config for this design (vck190 branch from 2x-qsfp28 reference)
# - PL CLK0 = 100MHz, PL CLK1 = 50MHz
# - M_AXI_LPD enable, PL-to-PS interrupts IRQ0-15, one fabric reset
set_property -dict [list \
  CONFIG.CLOCK_MODE {Custom} \
  CONFIG.PS_BOARD_INTERFACE {Custom} \
  CONFIG.PS_PL_CONNECTIVITY_MODE {Custom} \
  CONFIG.PS_PMC_CONFIG { \
    CLOCK_MODE {Custom} \
    DDR_MEMORY_MODE {Connectivity to DDR via NOC} \
    DEBUG_MODE {JTAG} \
    DESIGN_MODE {1} \
    PMC_CRP_PL0_REF_CTRL_FREQMHZ {100} \
    PMC_CRP_PL1_REF_CTRL_FREQMHZ {50} \
    PMC_GPIO0_MIO_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 0 .. 25}}} \
    PMC_GPIO1_MIO_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 26 .. 51}}} \
    PMC_MIO37 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA high} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
    PMC_OSPI_PERIPHERAL {{ENABLE 0} {IO {PMC_MIO 0 .. 11}} {MODE Single}} \
    PMC_QSPI_COHERENCY {0} \
    PMC_QSPI_FBCLK {{ENABLE 1} {IO {PMC_MIO 6}}} \
    PMC_QSPI_PERIPHERAL_DATA_MODE {x4} \
    PMC_QSPI_PERIPHERAL_ENABLE {1} \
    PMC_QSPI_PERIPHERAL_MODE {Dual Parallel} \
    PMC_REF_CLK_FREQMHZ {33.3333} \
    PMC_SD1 {{CD_ENABLE 1} {CD_IO {PMC_MIO 28}} {POW_ENABLE 1} {POW_IO {PMC_MIO 51}} {RESET_ENABLE 0} {RESET_IO {PMC_MIO 12}} {WP_ENABLE 0} {WP_IO {PMC_MIO 1}}} \
    PMC_SD1_COHERENCY {0} \
    PMC_SD1_DATA_TRANSFER_MODE {8Bit} \
    PMC_SD1_PERIPHERAL {{CLK_100_SDR_OTAP_DLY 0x3} {CLK_200_SDR_OTAP_DLY 0x2} {CLK_50_DDR_ITAP_DLY 0x36} {CLK_50_DDR_OTAP_DLY 0x3} {CLK_50_SDR_ITAP_DLY 0x2C} {CLK_50_SDR_OTAP_DLY 0x4} {ENABLE 1} {IO {PMC_MIO 26 .. 36}}} \
    PMC_SD1_SLOT_TYPE {SD 3.0} \
    PMC_USE_PMC_NOC_AXI0 {1} \
    PS_BOARD_INTERFACE {Custom} \
    PS_ENET0_MDIO {{ENABLE 1} {IO {PS_MIO 24 .. 25}}} \
    PS_ENET0_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 0 .. 11}}} \
    PS_ENET1_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 12 .. 23}}} \
    PS_GEN_IPI0_ENABLE {1} \
    PS_GEN_IPI0_MASTER {A72} \
    PS_GEN_IPI1_ENABLE {1} \
    PS_GEN_IPI2_ENABLE {1} \
    PS_GEN_IPI3_ENABLE {1} \
    PS_GEN_IPI4_ENABLE {1} \
    PS_GEN_IPI5_ENABLE {1} \
    PS_GEN_IPI6_ENABLE {1} \
    PS_HSDP_EGRESS_TRAFFIC {JTAG} \
    PS_HSDP_INGRESS_TRAFFIC {JTAG} \
    PS_HSDP_MODE {NONE} \
    PS_I2C0_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 46 .. 47}}} \
    PS_I2C1_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 44 .. 45}}} \
    PS_IRQ_USAGE {{CH0 1} {CH1 1} {CH10 1} {CH11 1} {CH12 1} {CH13 1} {CH14 1} {CH15 1} {CH2 1} {CH3 1} {CH4 1} {CH5 1} {CH6 1} {CH7 1} {CH8 1} {CH9 1}} \
    PS_NUM_FABRIC_RESETS {1} \
    PS_PCIE_EP_RESET1_IO {PMC_MIO 38} \
    PS_PCIE_EP_RESET2_IO {PMC_MIO 39} \
    PS_PCIE_RESET {ENABLE 1} \
    PS_PL_CONNECTIVITY_MODE {Custom} \
    PS_UART0_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 42 .. 43}}} \
    PS_USB3_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 13 .. 25}}} \
    PS_USE_FPD_CCI_NOC {1} \
    PS_USE_FPD_CCI_NOC0 {1} \
    PS_USE_M_AXI_LPD {1} \
    PS_USE_NOC_LPD_AXI0 {1} \
    PS_USE_PMCPL_CLK0 {1} \
    PS_USE_PMCPL_CLK1 {1} \
    PS_USE_PMCPL_CLK2 {0} \
    PS_USE_PMCPL_CLK3 {0} \
    SMON_ALARMS {Set_Alarms_On} \
    SMON_ENABLE_TEMP_AVERAGING {0} \
    SMON_TEMP_AVERAGING_SAMPLES {0} \
  } \
] [get_bd_cells versal_cips_0]

# Add clock wizard to generate the system clock (100MHz)
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard clk_wizard_0
set_property -dict [list \
  CONFIG.CLKOUT_DRIVES {BUFG,BUFG,BUFG,BUFG,BUFG,BUFG,BUFG} \
  CONFIG.CLKOUT_DYN_PS {None,None,None,None,None,None,None} \
  CONFIG.CLKOUT_GROUPING {Auto,Auto,Auto,Auto,Auto,Auto,Auto} \
  CONFIG.CLKOUT_MATCHED_ROUTING {false,false,false,false,false,false,false} \
  CONFIG.CLKOUT_PORT {clk_100m,clk_out2,clk_out3,clk_out4,clk_out5,clk_out6,clk_out7} \
  CONFIG.CLKOUT_REQUESTED_DUTY_CYCLE {50.000,50.000,50.000,50.000,50.000,50.000,50.000} \
  CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {100.000,100.000,100.000,100.000,100.000,100.000,100.000} \
  CONFIG.CLKOUT_REQUESTED_PHASE {0.000,0.000,0.000,0.000,0.000,0.000,0.000} \
  CONFIG.CLKOUT_USED {true,false,false,false,false,false,false} \
] [get_bd_cells clk_wizard_0]
connect_bd_net [get_bd_pins versal_cips_0/pl0_ref_clk] [get_bd_pins clk_wizard_0/clk_in1]

# System clock (100MHz) - used for all AXI-Lite control and MCDMA/NoC datapath
set sys_clk "clk_wizard_0/clk_100m"

# AXIS client clock wizard: 100MHz -> 390.625MHz (drives MRMAC tx_axi_clk/rx_axi_clk).
# 390.625MHz exceeds the minimum client frequency of the 64-bit Wide interface
# at both line rates (10G needs >=161.133MHz, 25G needs >=390.625MHz) and is the
# same client clock the AMD VCK190 Ethernet TRD uses for its 4-port MRMAC.
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard axis_clk_wiz
set_property -dict [list \
  CONFIG.CLKOUT_DRIVES {BUFG,BUFG,BUFG,BUFG,BUFG,BUFG,BUFG} \
  CONFIG.CLKOUT_DYN_PS {None,None,None,None,None,None,None} \
  CONFIG.CLKOUT_GROUPING {Auto,Auto,Auto,Auto,Auto,Auto,Auto} \
  CONFIG.CLKOUT_MATCHED_ROUTING {false,false,false,false,false,false,false} \
  CONFIG.CLKOUT_PORT {clk_390m625,clk_out2,clk_out3,clk_out4,clk_out5,clk_out6,clk_out7} \
  CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {390.625,100.000,100.000,100.000,100.000,100.000,100.000} \
  CONFIG.CLKOUT_USED {true,false,false,false,false,false,false} \
] [get_bd_cells axis_clk_wiz]
connect_bd_net [get_bd_pins versal_cips_0/pl0_ref_clk] [get_bd_pins axis_clk_wiz/clk_in1]
set axis_clk "axis_clk_wiz/clk_390m625"

# Configure the NoC. The CIPS automation pre-connects S00..S05 (FPD/LPD/PMC)
# and aclk0..5. Each SFP port's MCDMA adds 3 AXI slave ports (SG/MM2S/S2MM) on
# aclk6 (system clock); their per-SI memory-controller CONNECTIONS are set in
# the per-port loop below. So NUM_SI = 6 (CIPS) + 3 per SFP port.
set_property -dict [list CONFIG.NUM_CLKS {7} CONFIG.NUM_SI [expr {6 + 3 * $num_ports}]] [get_bd_cells axi_noc_0]
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins axi_noc_0/aclk6]
set noc_port_index 6
set noc_clk_index 6

# Connect the AXI interface clocks
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins versal_cips_0/m_axi_lpd_aclk]

# Proc system reset for main clock
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_100m
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins rst_100m/slowest_sync_clk]
connect_bd_net [get_bd_pins versal_cips_0/pl0_resetn] [get_bd_pins rst_100m/ext_reset_in]

# Proc system reset for the 390.625MHz AXIS client clock
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_390m625
connect_bd_net [get_bd_pins $axis_clk] [get_bd_pins rst_390m625/slowest_sync_clk]
connect_bd_net [get_bd_pins versal_cips_0/pl0_resetn] [get_bd_pins rst_390m625/ext_reset_in]

# AXI SmartConnect for the AXI-Lite control interfaces. Masters are allocated
# with a running counter (smc_mi): one per SFP port (port control aggregate =
# MCDMA + GT-control GPIO), plus the shared MRMAC s_axi, the shared I2C
# (PCA9548 mux to the SFP modules and Si5328), the MOD_ABS GPIO, and the GT
# quad's APB3 bridge. So NUM_MI = num_ports + 4.
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect axi_smc
set_property -dict [list CONFIG.NUM_MI [expr {$num_ports + 4}] CONFIG.NUM_SI {1} ] [get_bd_cells axi_smc]
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_pins rst_100m/interconnect_aresetn] [get_bd_pins axi_smc/aresetn]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/M_AXI_LPD] [get_bd_intf_pins axi_smc/S00_AXI]
set smc_mi 0

# GT ref clock (322.265625 MHz, from the FMC Si5328 via GBTCLK0) and utility
# buffer. 322.265625 MHz + LCPLL integer-N is the GT reference configuration of
# the 2025.2 MRMAC example designs at both 10G and 25G (and of the AMD VCK190
# Ethernet TRD). The Si5328 is programmed to this frequency over I2C.
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 gt_ref_clk
set_property CONFIG.FREQ_HZ 322265625 [get_bd_intf_ports /gt_ref_clk]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf util_ds_buf_0
set_property CONFIG.C_BUF_TYPE {IBUFDSGTE} [get_bd_cells util_ds_buf_0]
connect_bd_intf_net [get_bd_intf_ports gt_ref_clk] [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]

# GT Quad base (Transceiver wizard), GTY. The quad is NOT configured manually:
# with MRMAC_IS_GT_WIZ_OLD=1, IP integrator's parameter propagation derives the
# complete per-lane GT configuration from the connected MRMAC serdes
# interfaces - four independent single-lane Ethernet RAW protocols (10G or 25G
# line rate, LCPLL, 322.265625 MHz refclk, TX/RXPROGDIV outclks at
# 644.531 MHz), identical to the 2025.2 MRMAC example design GT settings.
# Setting the same values manually (USER strength) fights the propagation and
# breaks the quad's refclk grouping across lanes ("QUAD_PACK_SUCCESS FAIL").
create_bd_cell -type ip -vlnv xilinx.com:ip:gt_quad_base gt_quad_base_0

connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins gt_quad_base_0/GT_REFCLK0]
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins gt_quad_base_0/apb3clk]
connect_bd_net [get_bd_pins rst_100m/peripheral_aresetn] [get_bd_pins gt_quad_base_0/apb3presetn]

# SFP28 GT interface (4-lane serial: FMC DP0-3 = SFP slots 0-3)
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 sfp_gt
connect_bd_intf_net [get_bd_intf_pins gt_quad_base_0/GT_Serial] [get_bd_intf_ports sfp_gt]

# APB3 bridge to drive the GT quad's dynamic reconfiguration port
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_apb_bridge axi_apb_bridge_0
set_property -dict [list CONFIG.C_APB_NUM_SLAVES {1} CONFIG.C_M_APB_PROTOCOL {apb3}] [get_bd_cells axi_apb_bridge_0]
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins axi_apb_bridge_0/s_axi_aclk]
connect_bd_net [get_bd_pins rst_100m/peripheral_aresetn] [get_bd_pins axi_apb_bridge_0/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_apb_bridge_0/APB_M] [get_bd_intf_pins gt_quad_base_0/APB3_INTF]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M[format "%02d" $smc_mi]_AXI] [get_bd_intf_pins axi_apb_bridge_0/AXI4_LITE]
incr smc_mi

#########################################################
# MRMAC (4x10GE or 4x25GE, one client per SFP28 port)
#########################################################
create_bd_cell -type ip -vlnv xilinx.com:ip:mrmac mrmac
# ORDER MATTERS for the next three set_property calls:
#  1. MRMAC_IS_GT_WIZ_OLD first - the "old" GT wizard model exposes the
#     gt_*_serdes_interface_* pins that connect directly to gt_quad_base
#     TXn/RXn_GT_IP_Interface. Setting this parameter AFTER the preset
#     RESETS the whole MRMAC configuration back to its 1x100GE default.
#  2. The configuration preset (4x10GE Wide / 4x25GE Wide) - cascades
#     MRMAC_SPEED, MRMAC_CLIENTS=4, all MAC_PORTn_RATE and the per-port
#     64-bit Wide client data path selections.
#  3. Location + GT refclk frequency overrides.
set_property CONFIG.MRMAC_IS_GT_WIZ_OLD {1} [get_bd_cells mrmac]
set_property CONFIG.MRMAC_PRESET_C0 $mrmac_preset [get_bd_cells mrmac]
# Pin the MRMAC to the integrated-MAC site in the clock region of the FMC
# DP0-3 GT quad (GTY_QUAD_X1Y1, region X9Y1) - same site as port 0 of the
# 2x QSFP28 FMC design on this slot.
# GT reference clock = 322.265625 MHz (the FMC Si5328 output). Set it (and the
# per-channel refclks) explicitly so the MRMAC and gt_quad_base agree.
set_property -dict [list \
  CONFIG.MRMAC_LOCATION_C0 {MRMAC_X0Y0} \
  CONFIG.GT_REF_CLK_FREQ_C0 {322.265625} \
  CONFIG.GT_CH0_RX_REFCLK_FREQUENCY_C0 {322.265625} \
  CONFIG.GT_CH0_TX_REFCLK_FREQUENCY_C0 {322.265625} \
  CONFIG.GT_CH1_RX_REFCLK_FREQUENCY_C0 {322.265625} \
  CONFIG.GT_CH1_TX_REFCLK_FREQUENCY_C0 {322.265625} \
  CONFIG.GT_CH2_RX_REFCLK_FREQUENCY_C0 {322.265625} \
  CONFIG.GT_CH2_TX_REFCLK_FREQUENCY_C0 {322.265625} \
  CONFIG.GT_CH3_RX_REFCLK_FREQUENCY_C0 {322.265625} \
  CONFIG.GT_CH3_TX_REFCLK_FREQUENCY_C0 {322.265625} \
] [get_bd_cells mrmac]
# Guard: the preset must have survived the subsequent set_property calls
# (see ORDER MATTERS above) - fail fast here rather than build a 100G MAC.
if {[get_property CONFIG.MRMAC_PRESET_C0 [get_bd_cells mrmac]] ne $mrmac_preset} {
  puts "ERROR: MRMAC preset was reset to [get_property CONFIG.MRMAC_PRESET_C0 [get_bd_cells mrmac]]"
  return 1
}

# NOTE: mrmac/s_axi (and s_axi_aclk, 100MHz) is connected at the very END of
# this script, after the AXIS datapath converters are wired. Connecting the
# 100MHz control clock while the 390MHz AXIS client domain is already set
# makes the MRMAC client interface report a multi-segment PHASE; wiring the
# converters first (while the PHASE is still single-segment) avoids a
# PHASE-mismatch error at validate (same workaround as the 2x QSFP28 design).

# GT power good
connect_bd_net [get_bd_pins gt_quad_base_0/gtpowergood] [get_bd_pins mrmac/gtpowergood_in]

# GT serdes interfaces (carry data + per-channel reset handshake)
foreach ch {0 1 2 3} {
  connect_bd_intf_net [get_bd_intf_pins mrmac/gt_tx_serdes_interface_$ch] [get_bd_intf_pins gt_quad_base_0/TX${ch}_GT_IP_Interface]
  connect_bd_intf_net [get_bd_intf_pins mrmac/gt_rx_serdes_interface_$ch] [get_bd_intf_pins gt_quad_base_0/RX${ch}_GT_IP_Interface]
}

#########################################################
# Per-channel user clock buffers (GT outclk -> usrclk + usrclk2)
#########################################################
# Per-lane BUFG_GT user-clock buffers: each GT channel's txoutclk and
# rxoutclk feeds a full-rate buffer and a /2 buffer (BUFG_GT divides by
# gt_bufgtdiv+1, so the constant 1 gives /2). In the 4-port independent
# configuration every port is clocked by its OWN lane on both directions
# (unlike 100G CAUI-4 where all four TX lanes share the ch0 clock):
#   tx_core_clk[n]                  = ch<n> TX full-rate
#   tx_alt_serdes_clk[n]            = ch<n> TX half-rate
#   rx_core_clk[n], rx_serdes_clk[n] = ch<n> RX full-rate
#   rx_alt_serdes_clk[n]            = ch<n> RX half-rate
#   GT ch<n>_txusrclk / _rxusrclk    = ch<n> half-rate
#
# The buffers FREE-RUN (clears at their inactive defaults), exactly like the
# hardware-validated MRMAC references for the Linux axienet driver (the
# 2x QSFP28 FMC design and the AMD VCK190 Ethernet TRD). Two topologies were
# tried and rejected during hardware bring-up:
#   - MBUFG_GT with CLR/CLRB_LEAF driven from the MRMAC's clr/clrb_leaf
#     outputs (the 2025.2 MRMAC example design topology): under the axienet
#     driver's software reset sequence the MRMAC holds the clears asserted,
#     stopping every GT user clock - RX never block-locks and the frozen TX
#     serial stream makes the SFP28 module's TX CDR squelch its laser.
#   - MBUFG_GT with the clears tied off: rejected by DRC REQP-2090 at
#     write_device_image (free-running clears are only legal on BUFG_GT).
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant bufg_gt_div_val
set_property -dict [list CONFIG.CONST_WIDTH {3} CONFIG.CONST_VAL {1}] [get_bd_cells bufg_gt_div_val]
foreach ch {0 1 2 3} {
  foreach dir {tx rx} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:bufg_gt bufg_gt_${dir}$ch
    connect_bd_net [get_bd_pins gt_quad_base_0/ch${ch}_${dir}outclk] [get_bd_pins bufg_gt_${dir}$ch/outclk]
    create_bd_cell -type ip -vlnv xilinx.com:ip:bufg_gt bufg_gt_${dir}_div2_$ch
    connect_bd_net [get_bd_pins gt_quad_base_0/ch${ch}_${dir}outclk] [get_bd_pins bufg_gt_${dir}_div2_$ch/outclk]
    connect_bd_net [get_bd_pins bufg_gt_div_val/dout] [get_bd_pins bufg_gt_${dir}_div2_$ch/gt_bufgtdiv]
    # GT chN usrclk input takes the per-lane HALF-rate clock
    connect_bd_net [get_bd_pins bufg_gt_${dir}_div2_$ch/usrclk] [get_bd_pins gt_quad_base_0/ch${ch}_${dir}usrclk]
  }
}

# MRMAC TX core clock = per-lane FULL-rate, 4-bit bus {ch3,ch2,ch1,ch0}
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 tx_core_clk_cat
set_property CONFIG.NUM_PORTS {4} [get_bd_cells tx_core_clk_cat]
foreach ch {0 1 2 3} {
  connect_bd_net [get_bd_pins bufg_gt_tx$ch/usrclk] [get_bd_pins tx_core_clk_cat/In$ch]
}
connect_bd_net [get_bd_pins tx_core_clk_cat/dout] [get_bd_pins mrmac/tx_core_clk]

# MRMAC TX alt-serdes clock = per-lane HALF-rate
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 tx_alt_serdes_clk_cat
set_property CONFIG.NUM_PORTS {4} [get_bd_cells tx_alt_serdes_clk_cat]
foreach ch {0 1 2 3} {
  connect_bd_net [get_bd_pins bufg_gt_tx_div2_$ch/usrclk] [get_bd_pins tx_alt_serdes_clk_cat/In$ch]
}
connect_bd_net [get_bd_pins tx_alt_serdes_clk_cat/dout] [get_bd_pins mrmac/tx_alt_serdes_clk]

# MRMAC RX core + serdes clocks = per-lane FULL-rate
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 rx_serdes_clk_cat
set_property CONFIG.NUM_PORTS {4} [get_bd_cells rx_serdes_clk_cat]
foreach ch {0 1 2 3} {
  connect_bd_net [get_bd_pins bufg_gt_rx$ch/usrclk] [get_bd_pins rx_serdes_clk_cat/In$ch]
}
connect_bd_net [get_bd_pins rx_serdes_clk_cat/dout] [get_bd_pins mrmac/rx_core_clk]
connect_bd_net [get_bd_pins rx_serdes_clk_cat/dout] [get_bd_pins mrmac/rx_serdes_clk]

# MRMAC RX alt-serdes clock = per-lane HALF-rate
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 rx_alt_serdes_clk_cat
set_property CONFIG.NUM_PORTS {4} [get_bd_cells rx_alt_serdes_clk_cat]
foreach ch {0 1 2 3} {
  connect_bd_net [get_bd_pins bufg_gt_rx_div2_$ch/usrclk] [get_bd_pins rx_alt_serdes_clk_cat/In$ch]
}
connect_bd_net [get_bd_pins rx_alt_serdes_clk_cat/dout] [get_bd_pins mrmac/rx_alt_serdes_clk]

#########################################################
# MRMAC AXIS client clocks (390.625MHz) - tx_axi_clk/rx_axi_clk (4-bit bus,
# driven from the single scalar axis_clk net).
#########################################################
connect_bd_net [get_bd_pins $axis_clk] [get_bd_pins mrmac/tx_axi_clk]
connect_bd_net [get_bd_pins $axis_clk] [get_bd_pins mrmac/rx_axi_clk]

#########################################################
# MRMAC core/serdes resets (4-bit) - released by GT reset-done
#########################################################
# rx_core_reset / rx_serdes_reset = ~gt_rx_reset_done_out
# tx_core_reset / tx_serdes_reset = ~gt_tx_reset_done_out
# (same scheme as the 2025.2 MRMAC example design and the 2x QSFP28 design)
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 logic_rx_reset
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {4}] [get_bd_cells logic_rx_reset]
connect_bd_net [get_bd_pins mrmac/gt_rx_reset_done_out] [get_bd_pins logic_rx_reset/Op1]
connect_bd_net [get_bd_pins logic_rx_reset/Res] [get_bd_pins mrmac/rx_core_reset]
connect_bd_net [get_bd_pins logic_rx_reset/Res] [get_bd_pins mrmac/rx_serdes_reset]

create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 logic_tx_reset
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {4}] [get_bd_cells logic_tx_reset]
connect_bd_net [get_bd_pins mrmac/gt_tx_reset_done_out] [get_bd_pins logic_tx_reset/Op1]
connect_bd_net [get_bd_pins logic_tx_reset/Res] [get_bd_pins mrmac/tx_core_reset]
connect_bd_net [get_bd_pins logic_tx_reset/Res] [get_bd_pins mrmac/tx_serdes_reset]

# rx_flexif_reset (4-bit) = ~periph_rstn on all four lanes (no PTP/flex used).
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 periph_rstn_cat
set_property CONFIG.NUM_PORTS {4} [get_bd_cells periph_rstn_cat]
foreach ch {0 1 2 3} {
  connect_bd_net [get_bd_pins rst_100m/peripheral_aresetn] [get_bd_pins periph_rstn_cat/In$ch]
}
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 logic_not_rstn
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {4}] [get_bd_cells logic_not_rstn]
connect_bd_net [get_bd_pins periph_rstn_cat/dout] [get_bd_pins logic_not_rstn/Op1]
connect_bd_net [get_bd_pins logic_not_rstn/Res] [get_bd_pins mrmac/rx_flexif_reset]

#########################################################
# Tie off unused MRMAC clocks (flexif/ts) and pm_tick to 0 (no PTP)
#########################################################
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 const_zero4
set_property -dict [list CONFIG.CONST_WIDTH {4} CONFIG.CONST_VAL {0}] [get_bd_cells const_zero4]
connect_bd_net [get_bd_pins const_zero4/dout] [get_bd_pins mrmac/tx_flexif_clk]
connect_bd_net [get_bd_pins const_zero4/dout] [get_bd_pins mrmac/rx_flexif_clk]
connect_bd_net [get_bd_pins const_zero4/dout] [get_bd_pins mrmac/tx_ts_clk]
connect_bd_net [get_bd_pins const_zero4/dout] [get_bd_pins mrmac/rx_ts_clk]
connect_bd_net [get_bd_pins const_zero4/dout] [get_bd_pins mrmac/pm_tick]

#########################################################
# GT control GPIO concats (per-port reset bits -> 4-bit MRMAC GT reset buses)
#########################################################
# Each SFP port's GT-control GPIO (inside the port hierarchy) drives ONE bit
# of the MRMAC's 4-bit gt_reset_*_in buses - its own GT lane - unlike the
# 100G design where one GPIO bit fans out to all four bonded lanes. Lanes of
# unpopulated ports are tied 0 (never reset requests).
#
# The buses reach the MRMAC through mrmac_gt_ctrl_passthru, a combinational
# feed-through whose only purpose is to be OPAQUE to the SDT generator: with
# four different GPIOs visible behind plain slice/concat primitives, sdtgen
# auto-emits a gt-ctrl-gpios property with syntactically invalid phandles
# ("<& 32 0>") on the MRMAC nodes, breaking every downstream device tree
# compile (Vitis platform and PetaLinux). The real per-port gt-*-gpios
# bindings live in the design's port-config.dtsi.
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 const_zero1
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells const_zero1]
create_bd_cell -type module -reference mrmac_gt_ctrl_passthru gt_ctrl_passthru
connect_bd_net [get_bd_pins gt_ctrl_passthru/rst_all_out]   [get_bd_pins mrmac/gt_reset_all_in]
connect_bd_net [get_bd_pins gt_ctrl_passthru/rst_tx_dp_out] [get_bd_pins mrmac/gt_reset_tx_datapath_in]
connect_bd_net [get_bd_pins gt_ctrl_passthru/rst_rx_dp_out] [get_bd_pins mrmac/gt_reset_rx_datapath_in]
foreach {nm pin} {
  gt_rst_all rst_all_in
  gt_rst_tx  rst_tx_dp_in
  gt_rst_rx  rst_rx_dp_in
} {
  create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 cat_${nm}
  set_property CONFIG.NUM_PORTS {4} [get_bd_cells cat_${nm}]
  foreach ch {0 1 2 3} {
    if {[lsearch -exact $ports $ch] < 0} {
      connect_bd_net [get_bd_pins const_zero1/dout] [get_bd_pins cat_${nm}/In$ch]
    }
  }
  connect_bd_net [get_bd_pins cat_${nm}/dout] [get_bd_pins gt_ctrl_passthru/$pin]
}

#########################################################
# SFP ports
#########################################################
#
# Each SFP port hierarchy contains the AXI MCDMA datapath for one MRMAC
# client: MCDMA <-> CDC FIFO <-> dwidth converter (256b<->64b) <-> MRMAC
# client adapter, plus the GT-control GPIO that lets the Linux axienet driver
# reset this port's GT lane and read reset-done, and the SFP I/O logic.
#
# User LED behavior (driven from the MRMAC RX link status + MOD_ABS):
#   * Both LEDs OFF when no SFP module is present
#   * Green LED ON when module present and the MRMAC RX link is up
#   * Red LED ON when module present but the link is down
#
proc create_sfp_port {label line_rate} {

  # Active client width: the MRMAC lane pins are always 64-bit but a 10GE
  # port only drives/samples tdata[31:0] ("Independent 32b Non-Segmented");
  # a 25GE port uses the full 64 bits. The adapters and dwidth converters
  # are sized to the ACTIVE width.
  if {$line_rate == "25"} {
    set client_bytes 8
  } else {
    set client_bytes 4
  }

  set hier_obj [create_bd_cell -type hier sfp_port$label]
  current_bd_instance $hier_obj

  # Pins
  create_bd_pin -dir I sys_clk
  create_bd_pin -dir I axis_clk
  create_bd_pin -dir I periph_rstn
  create_bd_pin -dir I intercon_rstn
  create_bd_pin -dir I axis_rstn
  create_bd_pin -dir O dma_mm2s_introut
  create_bd_pin -dir O dma_s2mm_introut
  # MRMAC client (loose ports, connected to the MRMAC at the top level)
  create_bd_pin -dir O -from 63 -to 0 tx_axis_tdata
  create_bd_pin -dir O -from 10 -to 0 tx_axis_tkeep_user
  create_bd_pin -dir O tx_axis_tvalid
  create_bd_pin -dir O tx_axis_tlast
  create_bd_pin -dir I tx_axis_tready
  create_bd_pin -dir I -from 63 -to 0 rx_axis_tdata
  create_bd_pin -dir I -from 10 -to 0 rx_axis_tkeep_user
  create_bd_pin -dir I rx_axis_tvalid
  create_bd_pin -dir I rx_axis_tlast
  # GT control (one bit of the MRMAC 4-bit GT reset buses = this port's lane)
  create_bd_pin -dir O gt_rst_all
  create_bd_pin -dir O gt_rst_tx_dp
  create_bd_pin -dir O gt_rst_rx_dp
  create_bd_pin -dir I gt_tx_done
  create_bd_pin -dir I gt_rx_done
  # SFP I/O
  create_bd_pin -dir I link_up
  create_bd_pin -dir I mod_abs
  create_bd_pin -dir I rx_los
  create_bd_pin -dir I tx_fault
  create_bd_pin -dir O tx_disable
  create_bd_pin -dir O rate_sel0
  create_bd_pin -dir O rate_sel1
  create_bd_pin -dir O grn_led
  create_bd_pin -dir O red_led

  # Interfaces
  create_bd_intf_pin -mode Slave  -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_LITE
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 m_axi_sg
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 m_axi_mm2s
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 m_axi_s2mm

  #########################################################
  # AXI MCDMA datapath
  #########################################################
  # 256-bit memory/stream width at the 100MHz system clock = 25.6 Gb/s,
  # covering the line rate of a single port at both 10G and 25G.
  create_bd_cell -type ip -vlnv xilinx.com:ip:axi_mcdma axi_mcdma
  set_property -dict [list \
    CONFIG.c_num_mm2s_channels {1} \
    CONFIG.c_num_s2mm_channels {1} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_mm2s_dre {1} \
    CONFIG.c_include_s2mm_dre {1} \
    CONFIG.c_sg_length_width {14} \
    CONFIG.c_addr_width {64} \
    CONFIG.c_m_axi_mm2s_data_width {256} \
    CONFIG.c_m_axi_s2mm_data_width {256} \
    CONFIG.c_m_axis_mm2s_tdata_width {256} \
  ] [get_bd_cells axi_mcdma]
  connect_bd_net [get_bd_pins sys_clk] [get_bd_pins axi_mcdma/s_axi_lite_aclk]
  connect_bd_net [get_bd_pins sys_clk] [get_bd_pins axi_mcdma/s_axi_aclk]
  connect_bd_net [get_bd_pins periph_rstn] [get_bd_pins axi_mcdma/axi_resetn]
  connect_bd_net [get_bd_pins axi_mcdma/mm2s_ch1_introut] [get_bd_pins dma_mm2s_introut]
  connect_bd_net [get_bd_pins axi_mcdma/s2mm_ch1_introut] [get_bd_pins dma_s2mm_introut]

  # MCDMA memory-mapped interfaces (to NoC)
  connect_bd_intf_net [get_bd_intf_pins axi_mcdma/M_AXI_SG]   -boundary_type upper [get_bd_intf_pins m_axi_sg]
  connect_bd_intf_net [get_bd_intf_pins axi_mcdma/M_AXI_MM2S] -boundary_type upper [get_bd_intf_pins m_axi_mm2s]
  connect_bd_intf_net [get_bd_intf_pins axi_mcdma/M_AXI_S2MM] -boundary_type upper [get_bd_intf_pins m_axi_s2mm]

  #########################################################
  # AXI-Lite SmartConnect (mcdma s_axi_lite + gt-ctrl gpio)
  #########################################################
  create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect axi_smc_lite
  set_property CONFIG.NUM_MI {2} [get_bd_cells axi_smc_lite]
  connect_bd_net [get_bd_pins sys_clk] [get_bd_pins axi_smc_lite/aclk]
  connect_bd_net [get_bd_pins intercon_rstn] [get_bd_pins axi_smc_lite/aresetn]
  connect_bd_intf_net [get_bd_intf_pins S_AXI_LITE] [get_bd_intf_pins axi_smc_lite/S00_AXI]
  connect_bd_intf_net [get_bd_intf_pins axi_smc_lite/M00_AXI] [get_bd_intf_pins axi_mcdma/S_AXI_LITE]

  #########################################################
  # GT control GPIO (lets the Linux axienet driver reset this port's GT lane
  # and read reset-done). Dual-channel AXI GPIO -> ONE Linux gpiochip:
  #   Channel 1 (5 outputs): bit0=gt_reset_all, bit1=gt_reset_tx_datapath,
  #                          bit2=gt_reset_rx_datapath, bits3-4=gt-ctrl-rate (spare)
  #   Channel 2 (2 inputs):  bit0=gt_tx_reset_done, bit1=gt_rx_reset_done
  #########################################################
  create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_gt
  set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {5} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_GPIO2_WIDTH {2} \
    CONFIG.C_ALL_INPUTS_2 {1} \
  ] [get_bd_cells axi_gpio_gt]
  connect_bd_net [get_bd_pins sys_clk] [get_bd_pins axi_gpio_gt/s_axi_aclk]
  connect_bd_net [get_bd_pins periph_rstn] [get_bd_pins axi_gpio_gt/s_axi_aresetn]
  connect_bd_intf_net [get_bd_intf_pins axi_smc_lite/M01_AXI] [get_bd_intf_pins axi_gpio_gt/S_AXI]

  # Channel 1 outputs -> per-port GT reset request bits
  foreach {nm bit pin} {
    gt_rst_all 0 gt_rst_all
    gt_rst_tx  1 gt_rst_tx_dp
    gt_rst_rx  2 gt_rst_rx_dp
  } {
    create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilslice:1.0 slice_${nm}
    set_property -dict [list CONFIG.DIN_WIDTH {5} CONFIG.DIN_FROM $bit CONFIG.DIN_TO $bit CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_${nm}]
    connect_bd_net [get_bd_pins axi_gpio_gt/gpio_io_o] [get_bd_pins slice_${nm}/Din]
    connect_bd_net [get_bd_pins slice_${nm}/Dout] [get_bd_pins $pin]
  }

  # Channel 2 inputs <- this port's GT reset-done bits
  create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 gt_rst_done_cat
  set_property CONFIG.NUM_PORTS {2} [get_bd_cells gt_rst_done_cat]
  connect_bd_net [get_bd_pins gt_tx_done] [get_bd_pins gt_rst_done_cat/In0]
  connect_bd_net [get_bd_pins gt_rx_done] [get_bd_pins gt_rst_done_cat/In1]
  connect_bd_net [get_bd_pins gt_rst_done_cat/dout] [get_bd_pins axi_gpio_gt/gpio2_io_i]

  #########################################################
  # TX datapath: MCDMA(256b, sys_clk) -> CDC fifo -> dwidth(256->64) -> MRMAC client(64b, axis_clk)
  #########################################################
  create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo tx_cdc_fifo
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {512} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.FIFO_MODE {2} \
  ] [get_bd_cells tx_cdc_fifo]
  connect_bd_intf_net [get_bd_intf_pins axi_mcdma/M_AXIS_MM2S] [get_bd_intf_pins tx_cdc_fifo/S_AXIS]
  connect_bd_net [get_bd_pins sys_clk]  [get_bd_pins tx_cdc_fifo/s_axis_aclk]
  connect_bd_net [get_bd_pins periph_rstn] [get_bd_pins tx_cdc_fifo/s_axis_aresetn]
  connect_bd_net [get_bd_pins axis_clk] [get_bd_pins tx_cdc_fifo/m_axis_aclk]

  # TX dwidth: 32 bytes (256b, MCDMA side) -> the port's active client width.
  create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter tx_dwidth
  set_property -dict [list \
    CONFIG.S_TDATA_NUM_BYTES {32} \
    CONFIG.M_TDATA_NUM_BYTES $client_bytes \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TKEEP {1} \
  ] [get_bd_cells tx_dwidth]
  connect_bd_net [get_bd_pins axis_clk] [get_bd_pins tx_dwidth/aclk]
  connect_bd_net [get_bd_pins axis_rstn] [get_bd_pins tx_dwidth/aresetn]
  connect_bd_intf_net [get_bd_intf_pins tx_cdc_fifo/M_AXIS] [get_bd_intf_pins tx_dwidth/S_AXIS]
  # TX adapter: standard 64b AXIS (from tx_dwidth) -> MRMAC port client.
  # The MRMAC axis_tx_portN BD interface is handshake-only (TDATA_NUM_BYTES=0);
  # the data rides on loose ports tx_axis_tdata<2N> + tx_axis_tkeep_user<2N>, so
  # we cannot connect tx_dwidth straight to axis_tx_portN (that mis-delineates
  # frames). The adapter maps the 64b AXIS onto the MRMAC client lane.
  create_bd_cell -type module -reference mrmac_port_tx_axis_adapter tx_axis_adapter
  set_property CONFIG.DATA_W [expr {8 * $client_bytes}] [get_bd_cells tx_axis_adapter]
  connect_bd_net [get_bd_pins axis_clk] [get_bd_pins tx_axis_adapter/aclk]
  connect_bd_intf_net [get_bd_intf_pins tx_dwidth/M_AXIS] [get_bd_intf_pins tx_axis_adapter/S_AXIS]
  connect_bd_net [get_bd_pins tx_axis_adapter/tx_axis_tdata]      [get_bd_pins tx_axis_tdata]
  connect_bd_net [get_bd_pins tx_axis_adapter/tx_axis_tkeep_user] [get_bd_pins tx_axis_tkeep_user]
  connect_bd_net [get_bd_pins tx_axis_adapter/tx_axis_tlast]  [get_bd_pins tx_axis_tlast]
  connect_bd_net [get_bd_pins tx_axis_adapter/tx_axis_tvalid] [get_bd_pins tx_axis_tvalid]
  connect_bd_net [get_bd_pins tx_axis_tready] [get_bd_pins tx_axis_adapter/tx_axis_tready]

  #########################################################
  # RX datapath: MRMAC client(64b, axis_clk) -> dwidth(64->256) -> CDC fifo -> MCDMA(256b, sys_clk)
  #########################################################
  # RX adapter: MRMAC port client -> standard 64b AXIS (into rx_dwidth).
  # axis_rx_portN is handshake-only; data is on loose ports rx_axis_tdata<2N> +
  # rx_axis_tkeep_user<2N>. The adapter passes the single per-frame TLAST
  # through and forces full tkeep on non-last beats.
  create_bd_cell -type module -reference mrmac_port_rx_axis_adapter rx_axis_adapter
  set_property CONFIG.DATA_W [expr {8 * $client_bytes}] [get_bd_cells rx_axis_adapter]
  connect_bd_net [get_bd_pins axis_clk] [get_bd_pins rx_axis_adapter/aclk]
  connect_bd_net [get_bd_pins rx_axis_tdata]      [get_bd_pins rx_axis_adapter/rx_axis_tdata]
  connect_bd_net [get_bd_pins rx_axis_tkeep_user] [get_bd_pins rx_axis_adapter/rx_axis_tkeep_user]
  connect_bd_net [get_bd_pins rx_axis_tlast]  [get_bd_pins rx_axis_adapter/rx_axis_tlast]
  connect_bd_net [get_bd_pins rx_axis_tvalid] [get_bd_pins rx_axis_adapter/rx_axis_tvalid]

  # RX dwidth: the port's active client width -> 32 bytes (256b, MCDMA side).
  create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter rx_dwidth
  set_property -dict [list \
    CONFIG.S_TDATA_NUM_BYTES $client_bytes \
    CONFIG.M_TDATA_NUM_BYTES {32} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TKEEP {1} \
  ] [get_bd_cells rx_dwidth]
  connect_bd_net [get_bd_pins axis_clk] [get_bd_pins rx_dwidth/aclk]
  connect_bd_net [get_bd_pins axis_rstn] [get_bd_pins rx_dwidth/aresetn]
  connect_bd_intf_net [get_bd_intf_pins rx_axis_adapter/M_AXIS] [get_bd_intf_pins rx_dwidth/S_AXIS]

  create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo rx_cdc_fifo
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {512} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.FIFO_MODE {2} \
  ] [get_bd_cells rx_cdc_fifo]
  connect_bd_intf_net [get_bd_intf_pins rx_dwidth/M_AXIS] [get_bd_intf_pins rx_cdc_fifo/S_AXIS]
  connect_bd_net [get_bd_pins axis_clk] [get_bd_pins rx_cdc_fifo/s_axis_aclk]
  connect_bd_net [get_bd_pins axis_rstn] [get_bd_pins rx_cdc_fifo/s_axis_aresetn]
  connect_bd_net [get_bd_pins sys_clk]  [get_bd_pins rx_cdc_fifo/m_axis_aclk]
  connect_bd_intf_net [get_bd_intf_pins rx_cdc_fifo/M_AXIS] [get_bd_intf_pins axi_mcdma/S_AXIS_S2MM]

  #########################################################
  # SFP I/O
  #########################################################
  # Create constants HIGH and LOW for the SFP I/Os
  set const_high [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 const_high ]
  set_property -dict [list CONFIG.CONST_VAL {1}] $const_high
  set const_low [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 const_low ]
  set_property -dict [list CONFIG.CONST_VAL {0}] $const_low

  # TX_DISABLE tied low: module transmitter enabled from configuration
  connect_bd_net [get_bd_pins const_low/dout] [get_bd_pins tx_disable]
  # SFP28 rate select: RS0/RS1 high for the full 25G receiver/transmitter
  # bandwidth, low for reduced (10G) bandwidth
  if {$line_rate == "25"} {
    connect_bd_net [get_bd_pins const_high/dout] [get_bd_pins rate_sel0]
    connect_bd_net [get_bd_pins const_high/dout] [get_bd_pins rate_sel1]
  } else {
    connect_bd_net [get_bd_pins const_low/dout] [get_bd_pins rate_sel0]
    connect_bd_net [get_bd_pins const_low/dout] [get_bd_pins rate_sel1]
  }

  # User LEDs: green = module present AND link up; red = module present AND
  # link down. MOD_ABS is high when no module is present.
  create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 logic_not_mod_abs
  set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1} ] [get_bd_cells logic_not_mod_abs]
  connect_bd_net [get_bd_pins mod_abs] [get_bd_pins logic_not_mod_abs/Op1]

  create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 logic_not_link_up
  set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1} ] [get_bd_cells logic_not_link_up]
  connect_bd_net [get_bd_pins link_up] [get_bd_pins logic_not_link_up/Op1]

  create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 logic_and_grn_led
  set_property -dict [list CONFIG.C_OPERATION {and} CONFIG.C_SIZE {1} ] [get_bd_cells logic_and_grn_led]
  connect_bd_net [get_bd_pins logic_not_mod_abs/Res] [get_bd_pins logic_and_grn_led/Op1]
  connect_bd_net [get_bd_pins link_up] [get_bd_pins logic_and_grn_led/Op2]
  connect_bd_net [get_bd_pins logic_and_grn_led/Res] [get_bd_pins grn_led]

  create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 logic_and_red_led
  set_property -dict [list CONFIG.C_OPERATION {and} CONFIG.C_SIZE {1} ] [get_bd_cells logic_and_red_led]
  connect_bd_net [get_bd_pins logic_not_mod_abs/Res] [get_bd_pins logic_and_red_led/Op1]
  connect_bd_net [get_bd_pins logic_not_link_up/Res] [get_bd_pins logic_and_red_led/Op2]
  connect_bd_net [get_bd_pins logic_and_red_led/Res] [get_bd_pins red_led]

  current_bd_instance \
}

# Create each SFP port
foreach label $ports {
  create_sfp_port $label $line_rate

  # Connect clocks/resets
  connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins sfp_port$label/sys_clk]
  connect_bd_net [get_bd_pins $axis_clk] [get_bd_pins sfp_port$label/axis_clk]
  connect_bd_net [get_bd_pins rst_100m/peripheral_aresetn] [get_bd_pins sfp_port$label/periph_rstn]
  connect_bd_net [get_bd_pins rst_100m/interconnect_aresetn] [get_bd_pins sfp_port$label/intercon_rstn]
  connect_bd_net [get_bd_pins rst_390m625/peripheral_aresetn] [get_bd_pins sfp_port$label/axis_rstn]

  # MRMAC client (port N rides on loose ports tdata<2N>/tkeep_user<2N> with
  # per-port handshakes _N - see PG314 and the AMD VCK190 Ethernet TRD)
  set lane [expr {2 * $label}]
  connect_bd_net [get_bd_pins sfp_port$label/tx_axis_tdata]      [get_bd_pins mrmac/tx_axis_tdata$lane]
  connect_bd_net [get_bd_pins sfp_port$label/tx_axis_tkeep_user] [get_bd_pins mrmac/tx_axis_tkeep_user$lane]
  connect_bd_net [get_bd_pins sfp_port$label/tx_axis_tvalid] [get_bd_pins mrmac/tx_axis_tvalid_$label]
  connect_bd_net [get_bd_pins sfp_port$label/tx_axis_tlast]  [get_bd_pins mrmac/tx_axis_tlast_$label]
  connect_bd_net [get_bd_pins mrmac/tx_axis_tready_$label] [get_bd_pins sfp_port$label/tx_axis_tready]
  connect_bd_net [get_bd_pins mrmac/rx_axis_tdata$lane]      [get_bd_pins sfp_port$label/rx_axis_tdata]
  connect_bd_net [get_bd_pins mrmac/rx_axis_tkeep_user$lane] [get_bd_pins sfp_port$label/rx_axis_tkeep_user]
  connect_bd_net [get_bd_pins mrmac/rx_axis_tvalid_$label] [get_bd_pins sfp_port$label/rx_axis_tvalid]
  connect_bd_net [get_bd_pins mrmac/rx_axis_tlast_$label]  [get_bd_pins sfp_port$label/rx_axis_tlast]

  # GT control: this port's reset request bits into the 4-bit concats
  foreach nm {gt_rst_all gt_rst_tx gt_rst_rx} pin {gt_rst_all gt_rst_tx_dp gt_rst_rx_dp} {
    connect_bd_net [get_bd_pins sfp_port$label/$pin] [get_bd_pins cat_${nm}/In$label]
  }
  # GT reset-done: slice this port's lane out of the 4-bit done buses
  create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilslice:1.0 slice_gt_tx_done$label
  set_property -dict [list CONFIG.DIN_WIDTH {4} CONFIG.DIN_FROM $label CONFIG.DIN_TO $label CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_gt_tx_done$label]
  connect_bd_net [get_bd_pins mrmac/gt_tx_reset_done_out] [get_bd_pins slice_gt_tx_done$label/Din]
  connect_bd_net [get_bd_pins slice_gt_tx_done$label/Dout] [get_bd_pins sfp_port$label/gt_tx_done]
  create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilslice:1.0 slice_gt_rx_done$label
  set_property -dict [list CONFIG.DIN_WIDTH {4} CONFIG.DIN_FROM $label CONFIG.DIN_TO $label CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_gt_rx_done$label]
  connect_bd_net [get_bd_pins mrmac/gt_rx_reset_done_out] [get_bd_pins slice_gt_rx_done$label/Din]
  connect_bd_net [get_bd_pins slice_gt_rx_done$label/Dout] [get_bd_pins sfp_port$label/gt_rx_done]

  # MRMAC RX link status -> port LEDs
  connect_bd_net [get_bd_pins mrmac/stat_rx_status_$label] [get_bd_pins sfp_port$label/link_up]

  # MCDMA MM interfaces to NoC (SG, MM2S, S2MM)
  # SG / MM2S / S2MM each take a NoC slave port, mapped to memory-controller
  # ports MC_0 / MC_1 / MC_2. All SFP ports share the same MC ports (the
  # single DDR controller); the NoC arbitrates. CONNECTIONS must be set per SI.
  foreach {intf mc} {m_axi_sg MC_0 m_axi_mm2s MC_1 m_axi_s2mm MC_2} {
    set index_padded [format "%02d" $noc_port_index]
    set_property -dict [list CONFIG.CONNECTIONS [list $mc {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}]] [get_bd_intf_pins /axi_noc_0/S${index_padded}_AXI]
    connect_bd_intf_net [get_bd_intf_pins sfp_port$label/$intf] [get_bd_intf_pins axi_noc_0/S${index_padded}_AXI]
    set noc_port_index [expr {$noc_port_index + 1}]
  }

  # All MCDMA NoC ports share aclk6 (system clock), already connected above.

  # AXI-Lite control interface (port control aggregate: mcdma + gt gpio)
  connect_bd_intf_net [get_bd_intf_pins sfp_port$label/S_AXI_LITE] [get_bd_intf_pins axi_smc/M[format "%02d" $smc_mi]_AXI]
  incr smc_mi

  # External SFP I/O ports
  create_bd_port -dir O tx_disable_sfp$label
  create_bd_port -dir O rate_sel0_sfp$label
  create_bd_port -dir O rate_sel1_sfp$label
  create_bd_port -dir I mod_abs_sfp$label
  create_bd_port -dir I rx_los_sfp$label
  create_bd_port -dir I tx_fault_sfp$label
  create_bd_port -dir O grn_led_sfp$label
  create_bd_port -dir O red_led_sfp$label
  connect_bd_net [get_bd_pins sfp_port$label/tx_disable] [get_bd_ports tx_disable_sfp$label]
  connect_bd_net [get_bd_pins sfp_port$label/rate_sel0] [get_bd_ports rate_sel0_sfp$label]
  connect_bd_net [get_bd_pins sfp_port$label/rate_sel1] [get_bd_ports rate_sel1_sfp$label]
  connect_bd_net [get_bd_ports mod_abs_sfp$label] [get_bd_pins sfp_port$label/mod_abs]
  connect_bd_net [get_bd_ports rx_los_sfp$label] [get_bd_pins sfp_port$label/rx_los]
  connect_bd_net [get_bd_ports tx_fault_sfp$label] [get_bd_pins sfp_port$label/tx_fault]
  connect_bd_net [get_bd_pins sfp_port$label/grn_led] [get_bd_ports grn_led_sfp$label]
  connect_bd_net [get_bd_pins sfp_port$label/red_led] [get_bd_ports red_led_sfp$label]

  # Interrupts
  lappend intr_list "sfp_port$label/dma_mm2s_introut"
  lappend intr_list "sfp_port$label/dma_s2mm_introut"
}

#########################################################
# Shared I2C bus (PCA9548 mux on the FMC card)
#########################################################
# One AXI IIC reaches all card I2C devices through the PCA9548 mux:
# channels 0-3 = SFP module I2C (slots 0-3), channel 4 = Si5328 clock
# generator (programmed to output 322.265625 MHz on GBTCLK0).
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic axi_iic_0
connect_bd_intf_net [get_bd_intf_pins axi_smc/M[format "%02d" $smc_mi]_AXI] [get_bd_intf_pins axi_iic_0/S_AXI]
incr smc_mi
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins axi_iic_0/s_axi_aclk]
connect_bd_net [get_bd_pins rst_100m/peripheral_aresetn] [get_bd_pins axi_iic_0/s_axi_aresetn]
lappend intr_list "axi_iic_0/iic2intc_irpt"
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 i2c
connect_bd_intf_net [get_bd_intf_ports i2c] [get_bd_intf_pins axi_iic_0/IIC]

#########################################################
# SFP MOD_ABS GPIO (module presence detection, one bit per SFP slot)
#########################################################
# Read by the Linux SFP framework (sff,sfp mod-def0-gpios, active-low).
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_modabs
set_property -dict [list \
  CONFIG.C_GPIO_WIDTH {4} \
  CONFIG.C_ALL_INPUTS {1} \
] [get_bd_cells axi_gpio_modabs]
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins axi_gpio_modabs/s_axi_aclk]
connect_bd_net [get_bd_pins rst_100m/peripheral_aresetn] [get_bd_pins axi_gpio_modabs/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M[format "%02d" $smc_mi]_AXI] [get_bd_intf_pins axi_gpio_modabs/S_AXI]
incr smc_mi
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 mod_abs_cat
set_property CONFIG.NUM_PORTS {4} [get_bd_cells mod_abs_cat]
foreach ch {0 1 2 3} {
  if {[lsearch -exact $ports $ch] >= 0} {
    connect_bd_net [get_bd_ports mod_abs_sfp$ch] [get_bd_pins mod_abs_cat/In$ch]
  } else {
    connect_bd_net [get_bd_pins const_zero1/dout] [get_bd_pins mod_abs_cat/In$ch]
  }
}
connect_bd_net [get_bd_pins mod_abs_cat/dout] [get_bd_pins axi_gpio_modabs/gpio_io_i]

#########################################################
# MRMAC AXI-Lite control (connected last - see note at MRMAC creation)
#########################################################
connect_bd_net [get_bd_pins $sys_clk] [get_bd_pins mrmac/s_axi_aclk]
connect_bd_net [get_bd_pins rst_100m/peripheral_aresetn] [get_bd_pins mrmac/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M[format "%02d" $smc_mi]_AXI] [get_bd_intf_pins mrmac/s_axi]
incr smc_mi

# Connect the interrupts to CIPS
set intr_index 0
foreach intr $intr_list {
  connect_bd_net [get_bd_pins $intr] [get_bd_pins versal_cips_0/pl_ps_irq$intr_index]
  set intr_index [expr {$intr_index+1}]
}

# First validation pass: parameter propagation derives the full GT quad
# configuration from the connected MRMAC serdes interfaces. That config groups
# PROT0/1 (lanes 0/1, HSCLK0) on GT_REFCLK0 and PROT2/3 (lanes 2/3, HSCLK1) on
# GT_REFCLK1 - and only then does the quad's GT_REFCLK1 pin exist, so this
# pass fails on the unconnected pin. Catch it, wire GT_REFCLK1 to the same
# Si5328 output, and re-validate.
catch {validate_bd_design}
if {[get_bd_pins -quiet gt_quad_base_0/GT_REFCLK1] ne ""} {
  connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins gt_quad_base_0/GT_REFCLK1]
}

# Assign addresses
assign_bd_address

# Layout and validate
regenerate_bd_layout
save_bd_design
validate_bd_design
save_bd_design
