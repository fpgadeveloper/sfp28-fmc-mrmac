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

| Target board          | Target design      | Link speeds <br> supported | SFP28 ports | FMC Slot    | Vivado<br> Edition | IP<br>License |
|-----------------------|--------------------|------------|-------------|-------------|-------|-------|
| [VCK190]              | `vck190_fmcp1`     | 10G        | 4x          | FMCP1       | Enterprise | Required |

### 25G designs

| Target board          | Target design      | Link speeds <br> supported | SFP28 ports | FMC Slot    | Vivado<br> Edition | IP<br>License |
|-----------------------|--------------------|------------|-------------|-------------|-------|-------|
| [VCK190]              | `vck190_fmcp1_25g` | 25G        | 4x          | FMCP1       | Enterprise | Required |

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

Clone the repo and change into its directory:
```
git clone https://github.com/fpgadeveloper/sfp28-fmc-mrmac.git
cd sfp28-fmc-mrmac
```

### Cross-platform build runner

All builds are driven by `build.py` at the repo root, on both Windows
(git bash) and Linux. The `build.sh` / `build.bat` shim finds a suitable
Python 3 automatically (including the one bundled with the AMD tools).
Pick a target design label from the tables above (or run `./build.sh
list`), then run the build command for the stage(s) you want — each
command builds whatever it depends on automatically and skips anything
already built. On Windows without git bash, run the same commands from
Command Prompt or PowerShell using `build.bat` (e.g. `build.bat xsa
--target <target>`).

You don't need to source the AMD tools first — the build runner finds
Vivado, Vitis and PetaLinux automatically in their standard install
locations and sets up the environment each stage needs. If your tools
are installed somewhere non-standard and the runner can't find them,
source the tool settings yourself before running the build.

#### Build the Vivado project (bitstream + XSA)

```
./build.sh xsa --target <target>
```

#### Build the standalone application

Builds the Vitis workspace and the baremetal boot file (`BOOT.BIN`):

```
./build.sh standalone --target <target>
```

#### Build PetaLinux (Linux only)

```
./build.sh petalinux --target <target>
```

#### Build everything

Builds all of the above that the target supports, then gathers the boot
images into `bootimages/*.zip`:

```
./build.sh all --target <target>
./build.sh all --target all          # every target in the repo
```

Also available: `status`, `clean`, `project` — see
`./build.sh --help`. On Windows, the PetaLinux and Yocto stages require a
Linux machine; the runner says so and prints the hand-off command. The
legacy `make` interface still works on Linux (each Makefile now wraps
`build.sh`) but is deprecated and will be removed at the next version
update.

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
