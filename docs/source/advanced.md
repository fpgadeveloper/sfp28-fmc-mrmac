# Advanced: project structure and customization

This section is intended for users who want to modify the reference
design — adding IP to the block design, changing constraints, adding
packages or drivers to the PetaLinux project, and so on. It describes
how the repository is laid out, how the Make-driven build flow works,
how the block design assembles the MRMAC subsystem, how the PetaLinux
BSP is composed from layered fragments, and what modifications have been
added on top of the stock AMD BSP.

The actual *build* instructions are in [build_instructions](build_instructions);
this section is about understanding the project well enough to modify
it.

## Repository layout

```
.
├── Makefile                   <- Top-level build entry point
├── README.md
├── config/                    <- Source-of-truth design metadata and auto-generation
│   ├── data.json
│   └── update.py
├── docs/                      <- This documentation (Sphinx + Read the Docs)
├── PetaLinux/
│   ├── Makefile               <- PetaLinux build orchestration
│   └── bsp/                   <- Board and port-config BSP fragments
│       ├── vck190/                 <-   board-specific overlay
│       ├── ports-versal-0123/      <-   port-config overlay: 10G targets
│       └── ports-versal-0123-25g/  <-   port-config overlay: 25G targets
├── Vitis/
│   ├── Makefile               <- Vitis workspace build orchestration
│   ├── build-vitis.bat        <- Windows workspace-creation helper
│   ├── py/                    <- Vitis Python build driver (args.json config)
│   └── common/src/            <- Echo server sources (main.c, mrmac.c, si5328.c, vadj.c)
└── Vivado/
    ├── Makefile               <- Vivado build orchestration
    ├── build-vivado.bat       <- Windows project-creation helper
    ├── scripts/
    │   ├── build.tcl          <- Project creation + block design assembly
    │   └── xsa.tcl            <- Synthesis, implementation, XSA export
    └── src/
        ├── bd/
        │   └── bd_versal.tcl  <- Block design for all (Versal) targets
        ├── constraints/
        │   └── <target>.xdc   <- One XDC per target (pin assignments)
        └── hdl/
            ├── mrmac_gt_ctrl_passthru.v  <- GT-control feed-through (SDT generator workaround)
            └── mrmac_port_axis_adapter.v <- MRMAC port client ↔ AXI4-Stream adapters
```

Per-target build outputs are written to `Vivado/<target>/`,
`Vitis/<target>_workspace/` and `PetaLinux/<target>/`; packaged
boot-image zips are written to `bootimages/`. None of these are
committed.

## Target naming

A `TARGET` is the canonical handle for a single design and is the only
parameter passed through the build flow. It encodes the board, the FMC
connector and (for the 25G variants) the line rate:

```
<board>_<connector>[_25g]
```

For this repo the targets are `vck190_fmcp1` (4x 10GbE) and
`vck190_fmcp1_25g` (4x 25GbE). The first underscore-delimited token
(`vck190`) is taken as the *target board* and is what
`PetaLinux/Makefile` uses to select the BSP under
`PetaLinux/bsp/<board>/`.

The complete list of valid targets is in the `UPDATER START` block of
each Makefile and is generated from `config/data.json` (see below).

## `config/data.json` and `config/update.py`

`config/data.json` is the canonical source of truth for the set of
supported designs and their per-target metadata (board name, board URL,
line rate, FMC connector, etc.). `config/update.py` reads `data.json`
and regenerates the auto-managed sections of the Makefiles, the Vivado
`build.tcl` target dictionary, the top-level `README.md`, and
`.gitignore` — the sections delimited by `UPDATER START` / `UPDATER END`
(or `<!-- updater start -->` / `<!-- updater end -->`) comment markers.
The Sphinx documentation also reads `data.json` directly to render the
supported-board and target-design tables.

```{note}
The `lanes` field of each design holds the list of SFP28 ports the
design instantiates (`["0","1","2","3"]` for all four). Each port is one
MAC client of the single MRMAC hard block and uses one GTY lane (FMC
DP0–3). The `linkspeed` field (`"10"` or `"25"`) selects the MRMAC
configuration preset and the active client data width.
```

When adding or modifying a target, edit `data.json` and re-run
`update.py` (from the `config/` directory). Do not hand-edit content
between the updater markers; it will be overwritten on the next
regeneration. Note that `update.py` derives the PetaLinux port-config
overlay name from the populated ports and the line rate:
`lanes=["0","1","2","3"]` with `linkspeed="10"` selects
`bsp/ports-versal-0123/`; `linkspeed="25"` selects
`bsp/ports-versal-0123-25g/`.

## Make-driven build flow

There are four Makefiles in the repository, each scoped to a stage of
the build:

| Makefile               | Scope                                                                                  |
|------------------------|----------------------------------------------------------------------------------------|
| `./Makefile`           | Top-level orchestration; assembles boot-image zips for one or all targets.             |
| `./Vivado/Makefile`    | Creates the Vivado project, runs synthesis and implementation, exports the XSA.        |
| `./Vitis/Makefile`     | Creates the Vitis workspace from the XSA, builds the echo server, packages BOOT.BIN.   |
| `./PetaLinux/Makefile` | Creates the PetaLinux project from the XSA, applies BSP overlays, builds, packages.    |

A `make bootimage TARGET=<t>` invocation at the top level cascades:

```
make bootimage TARGET=t
  -> ensures PetaLinux build output exists
       PetaLinux/Makefile petalinux TARGET=t
         -> ensures Vivado XSA exists
              Vivado/Makefile xsa TARGET=t
                -> vivado -mode batch -source scripts/build.tcl   (creates project + block design)
                -> vivado -mode batch -source scripts/xsa.tcl     (synth, impl, device image, XSA export)
         -> petalinux-create --template versal --name t
         -> petalinux-config --get-hw-description <XSA>
         -> copy bsp/<board>/project-spec/* into the project
         -> copy bsp/<port-config>/project-spec/* into the project   (overlay)
         -> petalinux-config --silentconfig
         -> petalinux-build
         -> petalinux-package boot --plm --psmfw --u-boot --dtb
  -> ensures Vitis boot file exists (standalone echo server)
       Vitis/Makefile bootfile TARGET=t
  -> zip the resulting boot files into bootimages/
```

The dependency chain means a clean `make bootimage TARGET=t` from
scratch will perform every step in order. Re-running after an
intermediate step has succeeded picks up where the previous run left
off. Per-target lock files (`.<target>.lock`) prevent two concurrent
builds of the same target from clobbering each other.

```{tip}
`make project TARGET=<t>` (in `Vivado/`) creates the block design and
runs `validate_bd_design` **without** synthesis — use it to catch
block-design wiring errors fast before committing to the long XSA build.
```

## Vivado side

### Block design

There is one block-design TCL, `Vivado/src/bd/bd_versal.tcl`. It is
parameterised by the `ports` list and the `line_rate` (passed in from
`build.tcl`'s `target_dict`), and builds the design as follows:

1. **CIPS + NoC + DDR.** The Versal CIPS is added and configured by the
   `xilinx.com:bd_rule:cips` automation (DDR branch, one DDR memory
   controller), then extended with a per-board `PS_PMC_CONFIG` (M_AXI_LPD
   enabled, 16 PL→PS interrupts, two PL clocks).
2. **Clocking.** A clock wizard generates the 100 MHz system clock (all
   AXI-Lite control and the MCDMA/NoC datapath), and a second clock
   wizard generates the 390.625 MHz MRMAC AXIS client clock — a single
   client clock domain shared by all four ports, the same client clock
   the AMD VCK190 Ethernet TRD uses for its 4-port MRMAC.
3. **GT quad.** One `gt_quad_base` (GTY) serves all four ports: FMC
   DP0–3 = SFP28 slots 0–3. Its reference clock is GBTCLK0 from the FMC
   Si5328, and an APB3 bridge drives its DRP.
4. **MRMAC.** A single MRMAC hard block is configured with the
   `4x10GE Wide` or `4x25GE Wide` preset and pinned to `MRMAC_X0Y0`,
   then connected to the GT quad's four per-lane serdes interfaces and
   to the per-lane user-clock buffers (see below).
5. **Per-port subsystem.** The `create_sfp_port` proc (called once per
   port) builds an `sfp_port<N>` hierarchy containing the MRMAC client
   AXIS adapters, the width-converter/CDC-FIFO datapath, the AXI MCDMA,
   an AXI-Lite SmartConnect, the GT-control GPIO, and the SFP sideband
   and LED logic.
6. **Shared peripherals.** One AXI IIC reaches every I2C device on the
   card through the PCA9548 mux, and a 4-bit input GPIO reads the four
   MOD_ABS (module presence) lines. Structural counts (NoC slave ports,
   control SmartConnect masters, interrupts) are derived from the number
   of ports.

After sourcing the BD script, `build.tcl` runs `validate_bd_design`,
which triggers parameter propagation and connection automation. To see
the netlist as actually built, inspect the saved `.bd` under
`Vivado/<target>/<target>.srcs/sources_1/bd/mrmac/` or use
`write_bd_tcl`.

`build.tcl` checks `XILINX_VIVADO` against the `version_required` constant
(`2025.2`) and refuses to build with a different Vivado version — the BD
TCL APIs are not stable across major releases.

### The MRMAC datapath, in detail

These are the design choices that are specific to driving the four
SFP28 ports as independent 10G/25G clients of one MRMAC. If you modify
the block design, these are the parts most likely to need care.

#### MRMAC configuration — order matters

The MRMAC is configured by three `set_property` calls whose **order is
load-bearing**:

1. `MRMAC_IS_GT_WIZ_OLD = 1` first — the "old" GT wizard model exposes
   the `gt_*_serdes_interface_*` pins that connect directly to the
   `gt_quad_base` `TXn/RXn_GT_IP_Interface` ports. Setting this
   parameter *after* the preset resets the whole MRMAC configuration
   back to its 1x100GE default.
2. The configuration preset (`4x10GE Wide` / `4x25GE Wide`) — cascades
   `MRMAC_SPEED`, `MRMAC_CLIENTS=4`, all `MAC_PORTn_RATE` and the
   per-port 64-bit Wide client data path selections.
3. Location (`MRMAC_X0Y0`) and the GT reference-clock frequency
   overrides (322.265625 MHz on every channel, so the MRMAC and
   `gt_quad_base` agree).

The script guards this by re-reading the preset afterwards and failing
fast if it was reset.

#### GT Quad configuration — derived, not set

Unlike the 2x QSFP28 (100G CAUI-4) design, the GT quad here is **not**
configured manually. With `MRMAC_IS_GT_WIZ_OLD=1`, IP integrator's
parameter propagation derives the complete per-lane GT configuration
from the connected MRMAC serdes interfaces: four independent
single-lane Ethernet RAW protocols (10G or 25G line rate, LCPLL,
322.265625 MHz reference clock, TX/RXPROGDIV output clocks at
644.531 MHz) — identical to the 2025.2 MRMAC example design GT settings.
Setting the same values manually (USER strength) fights the propagation
and breaks the quad's refclk grouping across lanes
(`QUAD_PACK_SUCCESS FAIL`).

One wrinkle: the derived configuration groups lanes 0/1 (HSCLK0) on
`GT_REFCLK0` and lanes 2/3 (HSCLK1) on `GT_REFCLK1` — and the quad's
`GT_REFCLK1` pin only exists *after* propagation has run. The BD script
therefore runs a first `validate_bd_design` pass (caught), wires
`GT_REFCLK1` to the same Si5328 refclk buffer, and re-validates.

#### Per-lane user clocking

Each GT channel's `txoutclk` and `rxoutclk` is buffered by a pair of
**free-running BUFG_GT** primitives — one full-rate, one half-rate
(BUFG_GT divides by `gt_bufgtdiv`+1, so the constant 1 gives /2), with
the buffer clears left at their inactive defaults. This matches the
hardware-validated MRMAC references for the Linux `xilinx_axienet`
driver (the 2x QSFP28 FMC design and the AMD VCK190 Ethernet TRD). In
this 4-port independent configuration every port is clocked by its
**own** lane in both directions (unlike 100G CAUI-4, where all four TX
lanes share the ch0 clock):

* `tx_core_clk[n]` = ch*n* TX full-rate; `tx_alt_serdes_clk[n]` = ch*n*
  TX half-rate
* `rx_core_clk[n]`, `rx_serdes_clk[n]` = ch*n* RX full-rate;
  `rx_alt_serdes_clk[n]` = ch*n* RX half-rate
* GT `ch<n>_txusrclk` / `ch<n>_rxusrclk` = ch*n* half-rate

The AXIS *client* clocks `tx_axi_clk`/`rx_axi_clk` are a separate,
single 390.625 MHz domain shared by all four ports — do not confuse the
two clock buses. 390.625 MHz exceeds the minimum client frequency of
the 64-bit Wide interface at both line rates (10G needs ≥161.133 MHz,
25G needs ≥390.625 MHz).

```{warning}
The user-clock buffers must **free-run** under the Linux `xilinx_axienet`
driver. Two other topologies were tried and rejected during hardware
bring-up:

* **MBUFG_GT with `CLR`/`CLRB_LEAF` driven from the MRMAC's
  `clr`/`clrb_leaf` outputs** (the 2025.2 MRMAC example design
  topology): under the driver's software reset sequence the MRMAC holds
  the clears asserted, stopping every GT user clock. RX then never
  achieves block lock, and the frozen TX serial stream makes the SFP28
  module's TX CDR squelch its laser — the link partner sees no light
  even though the module's DOM diagnostics still report nominal TX
  power. GT reset-done still asserts, so the failure masquerades as a
  link or optics problem.
* **MBUFG_GT with the clears tied off**: rejected by DRC REQP-2090 at
  device-image generation — free-running clears are only legal on plain
  BUFG_GT.
```

#### MRMAC port client AXIS adapters

The MRMAC per-port "Independent Non-Segmented" client is **not** a
standard AXI4-Stream bus. In the block design its `axis_rx_portN` /
`axis_tx_portN` interfaces are handshake-only (they map only
TVALID/TLAST/TREADY, so IP integrator reports `TDATA_NUM_BYTES=0`). The
data actually rides on loose 64-bit lane pins (port *N* uses
`rx`/`tx_axis_tdata<2N>`) plus an 11-bit `tkeep_user<2N>` control word.
Feeding that handshake-only interface straight into a stock
`axis_dwidth_converter` mis-delineates frames.

`Vivado/src/hdl/mrmac_port_axis_adapter.v` provides two adapters
(`mrmac_port_tx_axis_adapter`, `mrmac_port_rx_axis_adapter`) that map
one port's client lane onto a single standard AXIS stream at the port's
**active width**: a 10GE port only drives/samples `tdata[31:0]`
("Independent 32b Non-Segmented"), a 25GE port uses the full 64 bits.
The adapters and the dwidth converters are sized to the active width by
the `DATA_W` parameter, set from the target's line rate.

#### Width conversion, CDC and MCDMA

The MRMAC client runs at 390.625 MHz at the port's active width; the
MCDMA and NoC run at the 100 MHz system clock / 256-bit. Each direction
has an `axis_dwidth_converter` (active width ↔ 256 bit) and an
asynchronous `axis_data_fifo` for the clock-domain crossing. The
per-port AXI MCDMA (`c_num_mm2s_channels`/`c_num_s2mm_channels` = 1,
256-bit, 64-bit addressing) moves packet data to/from DDR over three NoC
AXI slave ports (scatter-gather, MM2S, S2MM). 256 bits at 100 MHz =
25.6 Gb/s, covering the line rate of a single port at both 10G and 25G.

#### GT-control GPIO

Each port has a dual-channel AXI GPIO (`sfp_port<N>/axi_gpio_gt`) that
lets software reset that port's GT lane and read reset-done:

* **Channel 1 (5 outputs):** bit 0 = `gt_reset_all`, bit 1 =
  `gt_reset_tx_datapath`, bit 2 = `gt_reset_rx_datapath`, bits 3–4 =
  spare (`gt-ctrl-rate`).
* **Channel 2 (2 inputs):** bit 0 = `gt_tx_reset_done`, bit 1 =
  `gt_rx_reset_done`.

Each port's reset request bits drive only that port's bit of the
MRMAC's 4-bit `gt_reset_*_in` buses — its own GT lane — unlike the 100G
design where one GPIO bit fans out to four bonded lanes. The MRMAC's
4-bit `gt_tx/rx_reset_done_out` buses are sliced per port back into the
GPIO inputs, and (inverted) release the MRMAC core/serdes resets.

The concatenated reset buses reach the MRMAC through
`mrmac_gt_ctrl_passthru` (`Vivado/src/hdl/`), a combinational
feed-through whose only purpose is to be *opaque to the SDT generator*:
with four different GPIOs visible behind plain slice/concat primitives,
`sdtgen` auto-emits a `gt-ctrl-gpios` property with syntactically
invalid phandles (`<& 32 0>`) on the MRMAC nodes, breaking every
downstream device-tree compile (Vitis platform and PetaLinux). The real
per-port `gt-*-gpios` bindings live in `port-config.dtsi`.

#### SFP sideband and LEDs

The SFP sideband signals are handled in fabric, with no software in the
loop:

* **TX_DISABLE** is tied low — the module transmitter is enabled from
  configuration.
* **RS0/RS1** (SFP28 rate select) are tied low on the 10G targets
  (reduced bandwidth) and high on the 25G targets (full 25G bandwidth).
* **User LEDs** are driven from the MRMAC's per-port `stat_rx_status`
  and the slot's MOD_ABS: green = module present *and* link up, red =
  module present *and* link down, both off when no module is present.
* **MOD_ABS** (active-high absence) additionally feeds the shared 4-bit
  input GPIO read by the Linux SFP framework, and **RX_LOS** /
  **TX_FAULT** are routed into each port hierarchy.

### Address and interrupt maps

The control peripherals are mapped from `M_AXI_LPD` (addresses as
assigned in the released projects):

| Peripheral                | Port 0       | Port 1       | Port 2       | Port 3       |
|---------------------------|--------------|--------------|--------------|--------------|
| GT-control GPIO           | `0x80040000` | `0x80060000` | `0x80080000` | `0x800A0000` |
| AXI MCDMA                 | `0x80050000` | `0x80070000` | `0x80090000` | `0x800B0000` |

| Shared peripheral         | Address      |
|---------------------------|--------------|
| GT quad APB3 bridge       | `0x80000000` |
| MRMAC `s_axi`             | `0x80010000` |
| MOD_ABS GPIO              | `0x80020000` |
| AXI IIC (PCA9548 mux)     | `0x80030000` |

Each MAC port owns a 4 KB register page inside the MRMAC `s_axi`
window (port *N* at `0x80010000 + N*0x1000`).

Interrupts are connected to `pl_ps_irq0..8` (GIC SPI = 84 + index):

| `pl_ps_irq` | SPI | Source               |
|-------------|-----|----------------------|
| 0           | 84  | Port 0 MCDMA `mm2s`  |
| 1           | 85  | Port 0 MCDMA `s2mm`  |
| 2           | 86  | Port 1 MCDMA `mm2s`  |
| 3           | 87  | Port 1 MCDMA `s2mm`  |
| 4           | 88  | Port 2 MCDMA `mm2s`  |
| 5           | 89  | Port 2 MCDMA `s2mm`  |
| 6           | 90  | Port 3 MCDMA `mm2s`  |
| 7           | 91  | Port 3 MCDMA `s2mm`  |
| 8           | 92  | AXI IIC (PCA9548)    |

### Constraints

`Vivado/src/constraints/<target>.xdc` contains the pin assignments. For
the VCK190 targets it covers the four GTY lanes (DP0–3 = SFP28 slots
0–3), the GT reference clock (GBTCLK0), the I2C bus to the PCA9548 mux
(LA11), and the per-slot SFP sideband I/O and user LEDs on LA pins (all
LVCMOS15 — the FMC VADJ rail runs at 1.5V on these boards). The 10G and
25G XDCs are identical apart from the file header.

### Modifying the block design

Edit `Vivado/src/bd/bd_versal.tcl`. Most per-port logic lives in the
`create_sfp_port` proc, which is called once per entry in `ports`;
structural counts (NoC slave ports, control SmartConnect masters,
interrupts) are derived from the number of ports, so adding or removing
a port is largely a matter of changing the `lanes` list in `data.json`.
The line rate is selected by the `linkspeed` field, which switches the
MRMAC preset, the adapter/dwidth widths and the rate-select pin levels.
After editing, delete the existing project directory and rebuild:

```
rm -rf Vivado/<target>
cd Vivado
make xsa TARGET=<target>
```

## Vitis side

The bare-metal echo server is built by the universal Vitis Python build
driver (`Vitis/py/build-vitis.py`, configured by `Vitis/py/args.json`).
It creates a platform from the target's XSA and an application
(`echo_server`) from the sources in `Vitis/common/src/` — there is no
lwIP or BSP-library dependency, since the app drives the MRMAC, MCDMA,
I2C (Si5328) and VADJ directly through the standalone driver layer. See
[echo_server](echo_server) for what the application does and how to run
it.

## PetaLinux side

### BSP composition

The PetaLinux project is composed at build time from two BSP fragments
copied into the target's project directory:

1. A **board BSP** at `PetaLinux/bsp/vck190/`. Provides the board kernel
   and U-Boot configuration, `system-user.dtsi` (which includes
   `port-config.dtsi`), the kernel patches, and the rootfs configuration.
2. A **port-config overlay** at `PetaLinux/bsp/ports-versal-0123/` (10G)
   or `PetaLinux/bsp/ports-versal-0123-25g/` (25G). Provides
   `port-config.dtsi` — the device-tree fragment that wires up the four
   MRMAC ports, their MCDMAs, the GT-control GPIOs, the I2C mux, the
   Si5328 and the SFP cages. The two overlays differ only in the
   `max-speed` values (10000 vs 25000).

The mapping from target to (board BSP, port-config overlay) is encoded
in `PetaLinux/Makefile`'s `UPDATER` block, for example:

```
vck190_fmcp1_target := versal 0 0 ports-versal-0123
```

The first column is the PetaLinux template (`versal`); the last is the
port-config overlay name. The board BSP is derived from the first token
of the target name (`vck190`). At build time both `project-spec/` trees
are copied in, with the port-config overlay copied *after* the board BSP.

### The `port-config.dtsi` overlay

This is the device-tree fragment that makes the MRMAC ports work. The
SDT generator emits one DT node per MAC port from the single MRMAC
instance, in port order: `mrmac` (port 0), `mrmac_1`, `mrmac_2`,
`mrmac_3`. Per port the overlay sets, on that node:

* `axistream-connected` → the port's MCDMA node
  (`sfp_port<N>_axi_mcdma`), plus the MCDMA channel interrupts
  (`mm2s_ch1_introut`/`s2mm_ch1_introut`) and their GIC `interrupts`.
  The `xilinx_axienet` MCDMA probe looks the interrupts up *by name on
  the MRMAC node*, so both `interrupt-names` and the matching
  `interrupt-parent`/`interrupts` must be present here.
* `local-mac-address` (`00:0a:35:00:00:0N`), `xlnx,channel-ids`,
  `xlnx,num-queues`, `xlnx,addrwidth`.
* `max-speed = <10000>` (or `<25000>` on the 25G overlay) — the line
  rate the driver programs into the port.
* `gt-ctrl-gpios`, `gt-tx-dpath-gpios`, `gt-rx-dpath-gpios`,
  `gt-ctrl-rate-gpios`, `gt-tx-rst-done-gpios`, `gt-rx-rst-done-gpios`
  (all on the port's GT-control AXI GPIO, lines 0–6) and
  `xlnx,gtlane = <N>`. These let the driver reset the port's GT lane and
  poll reset-done (see below).

It also overrides each MCDMA node's `compatible` to `"xlnx,eth-dma"`,
instantiates the PCA9548 mux and the Si5328 on the shared I2C bus, and
adds the four SFP cage nodes (see below).

### Modifications layered on the stock BSP

The board BSP started as the stock AMD VCK190 reference BSP. This list is
the answer to *"what would I lose if I overwrote the BSP with the stock
one?"*

* **AXI Ethernet + MCDMA driver.** Kernel configs enable the
  `xilinx_axienet` driver with MCDMA support
  (`CONFIG_XILINX_AXI_EMAC`, `CONFIG_AXIENET_HAS_MCDMA`,
  `CONFIG_GPIO_XILINX`, `CONFIG_I2C_XILINX`). The four MRMAC ports bind
  to `xilinx_axienet` and appear as `eth0`–`eth3`.

* **MCDMA `compatible` override (device tree).** `xilinx_axienet`
  ioremaps the MCDMA registers itself, but the standalone `xilinx_dma`
  dmaengine driver also matches the MCDMA node and claims the region
  first, so axienet's probe fails with `-EBUSY`. Because
  `CONFIG_XILINX_AXI_EMAC` *depends on* `XILINX_DMA`, the dmaengine
  driver cannot simply be disabled. The fix is the
  `compatible = "xlnx,eth-dma"` override in `port-config.dtsi`:
  `xilinx_dma`'s of-match table does not bind `eth-dma`, and axienet
  finds the MCDMA via the `axistream-connected` phandle (not by
  compatible), so the region is left for axienet.

* **GT-control GPIO binding.** The `xilinx_axienet` MRMAC driver needs to
  reset the GT lane and read reset-done/PLL status from the PS. The block
  design exposes a dual-channel AXI GPIO per port
  (`sfp_port<N>/axi_gpio_gt`): five outputs (gt_reset_all,
  gt_reset_tx_datapath, gt_reset_rx_datapath, plus two spare
  gt-ctrl-rate lines) and two inputs (gt_tx/rx_reset_done). The
  `gt-*-gpios` properties in `port-config.dtsi` point the driver at these
  GPIO lines. Without this, the driver fails with `unable to get GT PLL
  resource`.

* **Si5328 clock generator (device tree).** `port-config.dtsi`
  instantiates a `silabs,si5328` `clock-generator@68` node on channel 4
  of the PCA9548 mux, with a fixed-clock 114.285 MHz crystal input and a
  `clk0@0` output programmed to 322.265625 MHz (the GT reference clock
  on GBTCLK0). The Linux `clk-si5324` driver programs the device from
  this node on probe.

* **SFP cages through the kernel SFP framework.** Kernel configs
  (`CONFIG_SFP`, `CONFIG_MDIO_I2C`, `CONFIG_I2C_MUX`,
  `CONFIG_I2C_MUX_PCA954x`) plus the four `sff,sfp` cage nodes in
  `port-config.dtsi` (module presence via the MOD_ABS GPIO's
  `mod-def0-gpios`, module I2C via mux channels 0–3) give module
  presence detection, EEPROM access and diagnostics (hwmon). The
  axienet/MRMAC driver has no phylink, so the cages are standalone
  management devices — they are *not* linked to the MACs.

* **MRMAC link carrier-monitor kernel patch.** The MRMAC has no
  PHY/phylink and gives no link-change interrupt, and the stock
  `xilinx_axienet` driver checks RX block lock only once in
  `axienet_open()` (a 1 ms poll), failing the open with `-ENODEV` if the
  link is not already up. On a cold bring-up the GT/PCS take longer than
  that to lock, so the open loses the race and the port needs a manual
  `ip link` bounce; a link partner that powers on later never brings the
  port up; and the driver never sets the netdev carrier (`ip link` shows
  `state UNKNOWN`). The patch
  `recipes-kernel/linux/linux-xlnx/0002-net-axienet-mrmac-carrier-link-monitor.patch`
  adds a delayed-work monitor that drives the netdev carrier from RX
  block-lock + status. `open()` now brings the interface up with carrier
  *off* and starts the monitor instead of failing. While the link is down
  the monitor re-issues the MRMAC core/serdes reset (`axienet_mrmac_reset`)
  each cycle to re-attempt lock — the Versal GTY RX does not re-acquire
  block lock on a partner signal that stabilises *after* its last reset,
  and the GT reset is one-shot, so the MRMAC reset is the part that
  re-aligns the lane — and once up it polls for loss. The net effect is
  that a port comes up automatically at boot and recovers on cable re-seat
  or partner power-on, with link state reflected in the netdev carrier
  (`MRMAC link up at 10000` / `MRMAC link down`). It is registered via
  `SRC_URI:append` in `recipes-kernel/linux/linux-xlnx_%.bbappend`.

* **Loopback self-test app.** The `mrmac-loopback-test` recipe
  (`recipes-apps/mrmac-loopback-test/`) installs the self-test script
  described in [petalinux](petalinux); it is force-installed via
  `IMAGE_INSTALL:append` in `meta-user/conf/petalinuxbsp.conf`.

* **Root filesystem additions.** `ethtool`, `iperf3` and `phytool`.

### Adding a kernel config option, patch, package or device-tree node

The mechanisms are the standard PetaLinux ones:

* **Kernel config:** append `CONFIG_<name>=y` to
  `bsp/vck190/project-spec/meta-user/recipes-kernel/linux/linux-xlnx/bsp.cfg`.
* **Kernel patch:** drop the `.patch` into
  `recipes-kernel/linux/linux-xlnx/` and add a `SRC_URI:append` line to
  `linux-xlnx_%.bbappend`. Force a re-patch with
  `petalinux-build -c kernel -x cleansstate && petalinux-build`.
* **Rootfs package:** add `CONFIG_<package>=y` to
  `configs/rootfs_config` (and declare it in
  `meta-user/conf/user-rootfsconfig` if it is not in the default menu).
* **Per-board device tree:** edit
  `meta-user/recipes-bsp/device-tree/files/system-user.dtsi`.
* **Per-port device tree:** edit the
  `bsp/ports-versal-0123[-25g]/…/port-config.dtsi` overlay.

```{tip}
After a *structurally-changed* XSA (new peripherals/addresses), a
`petalinux-config --get-hw-description` on an existing project keeps the
stale SDT ("workspace already set up, leaving as-is"). Remove
`<target>/components/plnx_workspace` before re-importing to force a fresh
SDT, then rebuild (this reuses the sstate cache, so it is incremental).
```

## Where build outputs land

| Path                                | Contents                                                  |
|-------------------------------------|-----------------------------------------------------------|
| `Vivado/<target>/`                  | Vivado project. `mrmac_wrapper.xsa` is the export.        |
| `Vivado/<target>/<target>.runs/impl_1/mrmac_wrapper.bit` | Device image / bitstream.            |
| `Vivado/logs/`                      | Per-target Vivado build logs (xpr + xsa).                 |
| `Vitis/<target>_workspace/`         | Vitis workspace (platform + `echo_server` application).   |
| `Vitis/boot/<target>/`              | Standalone `BOOT.BIN` (echo server).                      |
| `PetaLinux/<target>/`               | PetaLinux project. All Yocto build state lives here.      |
| `PetaLinux/<target>/images/linux/`  | `BOOT.BIN`, `image.ub`, `boot.scr`, `rootfs.tar.gz`, etc. |
| `bootimages/`                       | Per-target zipped boot files (`<prj>_<target>_petalinux-<ver>.zip` and `<prj>_<target>_standalone-<ver>.zip`). |

None of these directories are committed to the repository.
