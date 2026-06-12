# Revision History

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
