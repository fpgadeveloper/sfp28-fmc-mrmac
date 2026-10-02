# Revision History

## 2025.2 update: Yocto flow and RX path fixes (September 2026)

* **Yocto / AMD EDF flow** for both targets (`./build.sh yocto --target <target>`), producing a
  full SD-card disk image. See [Yocto](yocto). The Yocto zip in `bootimages/` also carries
  `BOOT.BIN` and the systemd-boot loader `BOOTAA64.EFI`, which have to be copied onto the first
  partition of the card after flashing.
* **RX frame FIFO (hardware).** *Symptom:* under sustained receive traffic, TCP throughput
  towards the board collapsed (for example about 700 Mbit/s with tens of thousands of
  retransmits at 25G) while no error counter showed a problem. *Cause:* the MRMAC RX client has
  no backpressure, and its beats went straight into the width converter, so whenever the CDC
  FIFO filled up single beats — including end-of-frame beats — were lost and truncated or merged
  frames reached the DMA. *Change:* the RX adapter now contains a 64 KB store-and-forward frame
  FIFO per port that passes on only complete, error-free frames and drops frames **whole** when
  it is full or the MAC flags them bad. Both drop counts are readable on channel 2 of the port's
  GT-control GPIO (`GPIO2_DATA`: `[7:2]` MAC-error drops, `[31:8]` overflow drops); see
  [Registers and counters](registers). Requires a rebuild of the XSA.
* **Link monitor rework (kernel patch).** *Symptom:* under heavy receive load a port could be
  declared down and then stayed down until `ip link set down/up`. *Change:* the monitor now
  samples the latched MRMAC status only after clearing it and letting it settle, declares a link
  down only after three consecutive bad samples, and recovers with the full MRMAC + GT datapath
  reset sequence of `open()` every 500 ms. New messages: `MRMAC link up at <rate> (<n> recovery
  resets)`, `MRMAC link down (rx_sts … blk_lck … vld_ctrl …)` and `MRMAC link still down after
  <n> recovery resets (…)`.
* **RX descriptor ring of 1024 on the MRMAC ports (kernel patch).** *Symptom:* TCP retransmits
  towards the board with no visible drop counter. *Cause:* the MCDMA drops a whole frame when no
  RX descriptor is free, and the default ring of 128 descriptors was too short. *Change:* the
  MRMAC ports default to 1024 RX descriptors (`ethtool -g`); adjustable with `ethtool -G`.
* **`rx_dma_pkt_drop` in `ethtool -S` (kernel patch):** the MCDMA's S2MM packet-drop count, so
  that frames dropped for lack of a descriptor are visible.
* **Yocto BSP:** U-Boot enables the FMC VADJ supply before booting (without it the FMC's I2C
  devices, Si5328 and GT lanes can be dead at probe); the VCK190's board Ethernet PHYs are
  described (RGMII delays) so the board RJ45 ports pass traffic, with fixed MAC addresses; the
  BSP kernel arguments (`clk_ignore_unused cma=1536M`) are applied through the systemd-boot
  entry; hostname `vck190-mrmac-2025-2`; `nstat` added to the image.
* **Build runner:** `./build.sh package` rewrites a boot-image zip whose artifacts are newer
  than the zip (previously an existing zip was kept after a rebuild);
  `./build.sh clean --keep-boot` removes the intermediates but keeps the boot files.
* Known limit, documented in [Testing the design](testing.md#known-limit-residual-rx-frame-drops-under-full-rate-tcp):
  under sustained full-rate TCP towards the board at 25G, about 88 frames/s are dropped whole by
  the RX frame FIFO and recovered by TCP.
* Documentation: new pages [Testing the design](testing) and
  [Registers and counters](registers); updated block diagram and a new per-port block-design
  diagram.

## 2025.2 (June 2026)

* First revision.
* Built for Vivado / Vitis / PetaLinux 2025.2 and the AMD VCK190 (FMCP1).
* Two targets: `vck190_fmcp1` (4x 10GbE) and `vck190_fmcp1_25g`
  (4x 25GbE). All four SFP28 ports are clients of a single Versal
  Integrated MRMAC hard block (`4x10GE Wide` / `4x25GE Wide` preset,
  one GTY lane per port), each with an AXI MCDMA datapath to DDR over
  the NoC, driven under PetaLinux by the `xilinx_axienet` driver.
* Custom RTL adapters (`mrmac_port_axis_adapter.v`) that present each
  MRMAC port client (loose 64-bit lane pins, active 32-bit at 10G /
  64-bit at 25G) as a standard AXI4-Stream, and per-lane free-running
  BUFG_GT user clock buffer pairs (full-rate + half-rate per lane,
  required for link bring-up under the Linux `xilinx_axienet` driver).
* GT quad configuration derived automatically from the MRMAC serdes
  interfaces (RAW, LCPLL, 322.265625 MHz reference clock from the FMC
  Si5328, programmed over the card's PCA9548 I2C mux).
* Bare-metal echo server test application (raw Ethernet — ARP, ICMP
  ping and UDP echo on all four ports; lwIP has no MRMAC adapter).
  Port N: MAC `00:0a:35:00:0e:0N`, IP `192.168.<(N+1)*10>.10/24`.
* PetaLinux BSP composed from a board fragment (`bsp/vck190/`) plus a
  port-config overlay (`bsp/ports-versal-0123/` for 10G,
  `bsp/ports-versal-0123-25g/` for 25G). See [advanced](advanced) for
  the full layout.
* Device-tree bindings for MRMAC bring-up: GT-control GPIO
  (`gt-*-gpios`), MCDMA `compatible = "xlnx,eth-dma"` override,
  `max-speed`, and the Si5328 clock-generator node programmed by the
  `clk-si5324` driver.
* SFP cages exposed through the kernel SFP framework (module presence,
  EEPROM, hwmon) as standalone management devices.
* Kernel patch adding an MRMAC link carrier monitor: a connected port
  comes up automatically and recovers on cable re-seat or partner
  power-on (`MRMAC link up` / `MRMAC link down`), with link state
  reflected in the netdev carrier.
* Bundled `mrmac-loopback-test` rootfs self-test for validating each
  port's datapath with a passive SFP28 loopback module.
