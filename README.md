# 10G/25G Ethernet (MRMAC) Reference Designs for the Quad SFP28 FMC

## Description

This project demonstrates the use of the Opsero [Quad SFP28 FMC] (OP081) with 10G/25G Ethernet
SFP+/SFP28 modules on AMD Versal adaptive SoC development boards. All four SFP28 ports are
clients of a single Versal [Integrated 100G Multirate Ethernet MAC (MRMAC)] hard block,
configured for four independent 10GbE or 25GbE channels (one GTY lane per port), with packet
data moved to/from DDR by per-port AXI MCDMAs and driven under PetaLinux by the AXI Ethernet
driver. A bare-metal echo-server test application is also included.

![Quad SFP28 FMC with the VCK190](docs/source/images/vck190-with-op081_03.jpg)

Important links:

* The user guide for these reference designs is hosted here: [10G/25G Ethernet (MRMAC) for Quad SFP28 FMC docs](https://sfp28-mrmac.ethernetfmc.com "10G/25G Ethernet (MRMAC) for Quad SFP28 FMC docs")
* To report a bug: [Report an issue](https://github.com/fpgadeveloper/sfp28-fmc-mrmac/issues "Report an issue").
* For technical support: [Contact Opsero](https://opsero.com/contact-us "Contact Opsero").
* To purchase the mezzanine card: [Quad SFP28 FMC order page](https://opsero.com/product/quad-sfp28-fmc "Quad SFP28 FMC order page").

## Requirements

This project is designed for version 2025.2 of the Xilinx tools (Vivado/Vitis/PetaLinux).
If you are using an older version of the Xilinx tools, then refer to the
[release tags](https://github.com/fpgadeveloper/sfp28-fmc-mrmac/tags "releases")
to find the version of this repository that matches your version of the tools.

In order to test this design on hardware, you will need the following:

* Vivado 2025.2
* Vitis 2025.2
* PetaLinux Tools 2025.2
* [Quad SFP28 FMC]
* One of the target platforms listed below
* [AMD Versal Integrated MRMAC License](https://www.amd.com/en/products/adaptive-socs-and-fpgas/intellectual-property/mrmac.html) (free)

## Target designs

This repo contains designs that target the supported development boards and their
FMC connectors. The table below lists the target design name, the link speed, the SFP28 ports
supported by the design and the FMC connector on which to connect the Quad SFP28 FMC.

<!-- updater start -->
### 10G designs

| Target board          | Target design      | Link speeds <br> supported | SFP28 ports | FMC Slot    | Vivado<br> Edition |
|-----------------------|--------------------|------------|-------------|-------------|-------|
| [VCK190]              | `vck190_fmcp1`     | 10G        | 4x          | FMCP1       | Enterprise |

### 25G designs

| Target board          | Target design      | Link speeds <br> supported | SFP28 ports | FMC Slot    | Vivado<br> Edition |
|-----------------------|--------------------|------------|-------------|-------------|-------|
| [VCK190]              | `vck190_fmcp1_25g` | 25G        | 4x          | FMCP1       | Enterprise |

[VCK190]: https://www.xilinx.com/vck190
<!-- updater end -->

Notes:
1. The Vivado Edition column indicates which designs are supported by the Vivado *Standard* Edition, the
   FREE edition which can be used without a license. Vivado *Enterprise* Edition requires
   a license however a 30-day evaluation license is available from the AMD Xilinx Licensing site.
2. The Versal Integrated MRMAC requires a (free) license to generate a bitstream.
3. All of the 25G designs have the `_25g` postfix in the target label.

## Software

These reference designs can be driven within a PetaLinux environment, or by the included
bare-metal echo-server test application. The repository includes all necessary scripts and code
to build both environments. The table below outlines the corresponding applications available
in each environment:

| Environment      | Available Applications  |
|------------------|-------------------------|
| Standalone       | Raw-Ethernet echo server (ARP, ICMP ping, UDP echo on all 4 ports) |
| PetaLinux        | Built-in Linux commands<br>Additional tools: ethtool, iperf3, phytool<br>Bundled self-test: `mrmac-loopback-test` |

## Build instructions

Clone the repo:
```
git clone https://github.com/fpgadeveloper/sfp28-fmc-mrmac.git
```

Source Vivado and PetaLinux tools:

```
source <path-to-petalinux>/2025.2/settings.sh
source <path-to-xilinx-tools>/2025.2/Vivado/settings64.sh
```

Build all (Vivado project, PetaLinux and the bare-metal echo server), and gather the boot
images into `bootimages/`:

```
cd sfp28-fmc-mrmac
make bootimage TARGET=vck190_fmcp1
```

To build a single stage, use the Makefile in the corresponding subdirectory, for example:

```
cd sfp28-fmc-mrmac/PetaLinux
make petalinux TARGET=vck190_fmcp1
```

## Troubleshooting

### PetaLinux build fails with `bitbake petalinux-image-minimal failed` and sstate fetch errors

If a `make petalinux TARGET=<target>` run ends with errors like

```
ERROR: <package>-<ver>-r0 do_..._setscene: Fetcher failure: Unable to find file file://.../sstate:...
[ERROR] Command bitbake petalinux-image-minimal failed
```

the actual build is not broken. These `_setscene` errors come from
bitbake trying to pull prebuilt artifacts from the public Xilinx
sstate-cache mirror, which occasionally returns 404 for individual
packages. Bitbake falls back to building those packages locally and
succeeds, but still exits non-zero because of the failed fetches —
so the Makefile stops before the `petalinux-package` step that
produces `BOOT.BIN`.

**Fix: just re-run the same command.** The second attempt finds the
missing packages in the local sstate cache (populated by the first
run) and completes cleanly, producing `BOOT.BIN`. The reference
design itself is fine; this is a transient issue with the public
mirror.

## Contribute

We strongly encourage community contribution to these projects. Please make a pull request if you
would like to share your work:
* if you've spotted and fixed any issues
* if you've added designs for other target platforms

Thank you to everyone who supports us!

## About us

This project was developed by [Opsero Inc.](https://opsero.com "Opsero Inc."),
a tight-knit team of FPGA experts delivering FPGA products and design services to start-ups and tech companies.
Follow our blog, [FPGA Developer](https://www.fpgadeveloper.com "FPGA Developer"), for news, tutorials and
updates on the awesome projects we work on.

[Quad SFP28 FMC]: https://docs.opsero.com/op081/datasheet/overview/
[Integrated 100G Multirate Ethernet MAC (MRMAC)]: https://www.amd.com/en/products/adaptive-socs-and-fpgas/intellectual-property/mrmac.html
