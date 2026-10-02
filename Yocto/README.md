# Yocto / EDF builds

This folder builds Linux images for the Quad SFP28 FMC (MRMAC) reference designs
using the AMD Yocto / Embedded Development Framework (EDF) flow — the announced
successor to PetaLinux Tools. These designs target the AMD Versal VCK190, at
either 10G or 25G line rate.

## How it works: the parse-sdt flow

The build generates a **custom Yocto MACHINE directly from the Vivado XSA** —
there is no dependency on an AMD-provided machine config. This lets a customer
change the PS in Vivado and have it flow through automatically:

```
XSA  --sdtgen-->  System Device Tree  --gen-machineconf parse-sdt-->  MACHINE + DTS
```

`scripts/configure-build.sh` runs `xsct`/`sdtgen` on the XSA to produce a System
Device Tree (which includes `pl.dtsi`, the PL hardware extracted from the
design), then runs `gen-machineconf parse-sdt` to emit
`conf/machine/mrmac-<target>.conf` plus the lopper-pruned per-domain device
trees (`cortexa72-linux.dts` on Versal). The PL **MRMAC** and the four per-port
**AXI MCDMA** datapaths therefore come from the design's own SDT — no
hand-curated PL device tree. Because no PL overlay is requested, the Vivado boot
artifact (the Versal `.pdi`) is embedded into `BOOT.BIN` (the PLM programs the PL
at boot).

The off-chip Quad SFP28 FMC peripherals, however, are **not** in the XSA, so two
small hand-written device-tree files are layered on top of the generated tree:

* **`bsp/vck190/…/system-user.dtsi`** — SoC-side board quirks (see "Per-board
  fixups").
* **`bsp/port-configs/<ports-versal-*>/…/port-config.dtsi`** — the per-target
  SFP28 / MRMAC port wiring: the four MRMAC port nodes' MAC address, line rate
  and GT-control GPIO, the FMC I2C tree (PCA9548 mux → SFP module I2C + Si5328
  GT reference clock) and the four SFP cage descriptors (see "Port-config
  overlays").

## Prerequisites

Host packages on Ubuntu 22.04 / 24.04:

```
sudo apt-get install repo gawk wget git diffstat unzip texinfo gcc \
    build-essential chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    python3-subunit zstd liblz4-tool file locales libacl1 bmap-tools
```

Plus Vivado 2025.2 (used to produce the XSA this flow consumes) and Vitis
2025.2 — `sdtgen`/`xsct` (used to turn the XSA into a System Device Tree)
ship with Vitis, not Vivado, in 2025.2. The build runner locates and sources
the Vivado and Vitis environment itself; sourcing it manually is only needed
when running the `scripts/` engine by hand:

```
source <xilinx-install>/2025.2/Vivado/settings64.sh
source <xilinx-install>/2025.2/Vitis/settings64.sh
```

The Versal Integrated MRMAC requires a (free) license to generate the bitstream
the XSA carries; see the repository [README](../README.md) for the license link.

## Build

Yocto images are built with the cross-platform build runner at the repo root
(this stage requires a native Linux machine; on Windows the runner refuses
it up front and prints the hand-off command):

```
./build.sh yocto --target vck190_fmcp1    # or any target from `./build.sh list`
```

The runner builds the Vivado XSA first if one isn't already present, then
sequences the four scripts in `scripts/` — the engine of the flow
(init-workspace, configure-build, build-image, package-output). The legacy
`cd Yocto && make yocto TARGET=<target>` still works on Linux (the Makefile
is now a thin wrapper around `build.sh`) but is deprecated.

The first build for a target:

1. Builds the Vivado project and exports the XSA if one isn't already
   present.
2. Initializes a manifest workspace under `Yocto/<TARGET>/` with
   `repo init -u https://github.com/Xilinx/yocto-manifests.git -b rel-v2025.2 -m default-edf.xml`
   and `repo sync` (≈5 GB of git history).
3. Sources `edf-init-build-env` to set up the bitbake environment.
4. Generates the System Device Tree from the XSA and runs
   `gen-machineconf parse-sdt` to create `MACHINE = "mrmac-<target>"`
   (gen-machineconf builds its own native helpers — `kconfig-frontends-native`,
   `lopper`, etc. — via bitbake on first run).
5. Layers `bsp/vck190/conf/local.conf.append` (hostname, kernel cmdline) and
   `bsp/vck190/meta-user/` (kernel config, `system-user.dtsi` board fixups,
   image bbappend) over the EDF default config, plus — when the target has a
   port config — the `bsp/port-configs/<ports-versal-*>/meta-user/` overlay
   layer.
6. Runs `bitbake edf-linux-disk-image`.
7. Gathers `BOOT.BIN` (with the `.pdi` bitstream embedded), `Image`,
   `system.dtb`, `boot.scr`, `u-boot.elf`, `rootfs.tar.gz`, `rootfs.wic.xz`, and
   `rootfs.wic.bmap` into `Yocto/<TARGET>/images/linux/`.

Subsequent builds skip `repo sync`. To force a re-config (e.g. after editing
`bsp/vck190/conf/local.conf.append`), remove `Yocto/<TARGET>/configdone.txt`.

`./build.sh yocto --target all` builds every target; `./build.sh status --target all`
reports which are built.

## Port-config overlays (`port-config.dtsi`)

The off-chip Quad SFP28 FMC peripherals are board knowledge the XSA does not
carry, and the per-port line rate differs between the 10G and 25G targets, so
the wiring is factored into per-config overlay **layers** rather than into the
board BSP:

```
bsp/port-configs/
  ports-versal-0123/meta-user/       10G — all four SFP28 ports (max-speed 10000)
  ports-versal-0123-25g/meta-user/   25G — all four SFP28 ports (max-speed 25000)
```

Each overlay is a small Yocto layer whose `device-tree.bbappend` adds its
`port-config.dtsi` to the Linux device tree via `EXTRA_DT_INCLUDE_FILES`. Which
overlay applies is selected per target by `build.py`, which derives the
port-config name from the design's populated ports and line rate in
`config/data.json` (the four-port 10G target → `ports-versal-0123`, the 25G
target → `ports-versal-0123-25g`); `configure-build.sh` adds
`bsp/port-configs/<that-config>/meta-user` to `bblayers.conf` alongside the
board layer. The two overlays differ only in the per-port `max-speed` (10000 vs
25000), which sets the MRMAC line rate.

For each of the four MRMAC ports (the SDT emits one DT node per MAC port from
the single MRMAC hard block: `&mrmac`, `&mrmac_1`, `&mrmac_2`, `&mrmac_3`),
`port-config.dtsi` sets the `local-mac-address`, `max-speed`,
`axistream-connected` (the port's AXI MCDMA), and the `gt-*-gpios` that reset
and bring up the port's GT lane; it also overrides each port's MCDMA
`compatible` to `"xlnx,eth-dma"` so the AXI Ethernet driver (not the standalone
`xilinx_dma` dmaengine driver) claims the datapath. The shared FMC peripherals
— the `axi_iic_0` → PCA9548 mux (channels 0–3 = SFP module I2C, channel 4 =
the Si5328 GT-refclk clock generator) and the four `sff,sfp` cage descriptors
(module presence via the `axi_gpio_modabs` MOD_ABS GPIO, EEPROM + diagnostics
over the mux) — are added here too. The `&mrmac*` / `&sfp_port*` nodes the
overlay references come from the SDT's `pl.dtsi`.

## Per-board fixups (`system-user.dtsi`)

`bsp/vck190/meta-user/recipes-bsp/device-tree/files/system-user.dtsi` is layered
onto the generated Linux device tree (via `EXTRA_DT_INCLUDE_FILES`, guarded so
it only applies to the Linux/APU domain DT — the FSBL/PLM/PSM domain DTs don't
define the SoC peripheral labels). For the VCK190 it carries only the SoC-side
board quirk the XSA/sdtgen output doesn't encode: the `zyxclmm_drm` node
(`compatible = "xlnx,zocl-versal"`) under `&amba`. PL hardware and SFP28/MRMAC
port wiring are not here — that is the SDT (`pl.dtsi`) and the port-config
overlay respectively.

Kernel config fragments live in
`bsp/vck190/meta-user/recipes-kernel/linux/linux-xlnx/bsp.cfg`:

* **AXI Ethernet + MCDMA**: `CONFIG_XILINX_AXI_EMAC`, `CONFIG_AXIENET_HAS_MCDMA`
  — the driver the MRMAC ports bind to, plus its MCDMA datapath.
* **FMC peripherals**: `CONFIG_GPIO_XILINX` (GT control + MOD_ABS),
  `CONFIG_I2C_XILINX` and `CONFIG_I2C_MUX_PCA954x` (the FMC PCA9548 mux).
* **SFP framework**: `CONFIG_SFP`, `CONFIG_MDIO_I2C` — the four SFP cages
  (module presence, EEPROM and diagnostics). The MRMAC/axienet driver has no
  phylink, so the cages are standalone management devices, not linked to the
  MACs.

## Flashing to SD card

The build produces a full wic disk image (`rootfs.wic.xz`). Flash it to the SD
card's raw device; per-partition file copies do **not** work because the boot
script boots from the device it finds itself on.

The Versal EDF wks uses a 3-partition layout (`esp` (vfat), `storage` (vfat),
`root` (ext4)). The Versal BootROM (SD mode) FAT-boots `BOOT.BIN` from the first
FAT partition (`esp`), so after flashing you must drop `BOOT.BIN` — and the
`boot.scr` U-Boot reads to load the kernel — onto `esp` by hand.

### 1. Identify the SD card device — carefully

`dd`-style writes to a block device cannot be undone. With the SD card
**un**plugged, run `lsblk -o NAME,SIZE,RM,TYPE,MOUNTPOINT`; insert the card and
re-run it. The new entry (typically `/dev/sdX`, `RM=1`, size matching your card)
is your target. Confirm with
`udevadm info --query=property --name=/dev/sdX | grep -E "ID_BUS|ID_MODEL"`
(`ID_BUS=usb`). **Do not proceed until you are certain `/dev/sdX` is your SD card
and not an internal disk.**

### 2. Unmount any auto-mounted partitions

```
for p in /dev/sdX?*; do sudo umount "$p" 2>/dev/null; done
```

### 3. Flash the wic image to the raw device

```
sudo bmaptool copy \
    --bmap Yocto/<TARGET>/images/linux/rootfs.wic.bmap \
          Yocto/<TARGET>/images/linux/rootfs.wic.xz \
          /dev/sdX
```

Fallback (slower): `xzcat …/rootfs.wic.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync`.

### 4. Install BOOT.BIN and boot.scr on the esp partition

```
sudo partprobe /dev/sdX
sudo mkdir -p /mnt/sd_esp
sudo mount /dev/sdX1 /mnt/sd_esp
sudo cp Yocto/<TARGET>/images/linux/BOOT.BIN  /mnt/sd_esp/BOOT.BIN
sudo cp Yocto/<TARGET>/images/linux/boot.scr  /mnt/sd_esp/boot.scr
sync
sudo umount /mnt/sd_esp && sudo rmdir /mnt/sd_esp
```

(If your desktop auto-mounted `esp`, copy the two files straight onto its
mountpoint instead.)

### 5. Eject and boot

Eject the card cleanly (`sudo eject /dev/sdX`) so pending writes flush. Insert it
into the board, set the boot-mode switches to SD (see
[Boot PetaLinux](../docs/source/petalinux.md) for the VCK190 switch settings),
power-cycle, and attach a UART terminal at 115200 8N1. The Versal `boot.scr`
mounts the rootfs from `/dev/mmcblk0p3`.

## Offline / faster builds

Place the absolute path to a directory containing an extracted AMD sstate-cache
mirror in `Yocto/offline.txt` — `configure-build.sh` auto-detects which
architecture subdirs exist under it and wires one `SSTATE_MIRRORS` entry per
arch (plus `SOURCE_MIRROR_URL` if a `downloads/` dir is present).

Expected layout under that path:

```
<sstate root>/
  aarch64/      (Versal Linux)
  microblaze/   (the Versal PLM / PSM firmware multiconfig)
  downloads/    (optional — the source-mirror tarballs)
```

Both `aarch64` and `microblaze` are needed: the generated MACHINE builds the
Versal platform firmware (PLM/PSM) as a MicroBlaze multiconfig. The sstate-cache
and downloads archives are available behind login at the AMD Embedded Design
Tools download page under "sstate-cache & Downloads - 2025.2".

## Layout

```
Yocto/
  Makefile                  deprecated thin wrapper around ../build.sh
  README.md                 this file
  .gitignore                excludes per-target workspaces + local state
  offline.txt               (optional, gitignored) path to an extracted sstate mirror
  scripts/
    init-workspace.sh       repo init + sync
    configure-build.sh      sdtgen + gen-machineconf parse-sdt + apply BSP (+ overlay) + sstate
    build-image.sh          bitbake the image recipe
    package-output.sh       gather deploy artifacts into images/linux/
  bsp/
    vck190/                 the VCK190 board BSP (shared by the 10G + 25G targets)
      conf/local.conf.append   board overrides (hostname, kernel cmdline)
      meta-user/               Yocto layer: kernel cfg, system-user.dtsi, image bbappend
    port-configs/
      ports-versal-0123/, ports-versal-0123-25g/   per-target MRMAC/SFP28 overlay layers
  <TARGET>/                 (gitignored) per-target workspace built by the runner
  logs/                     (gitignored) build logs
```

## Architectural notes

* **The four scripts are universal** — identical across all of our
  reference repos. The per-repo data (target list, `BD_NAME`, each target's
  template and optional port config) lives in `config/data.json`, which
  `build.py` reads at runtime — nothing is generated into this folder.

* **The MACHINE is generated from the XSA** by `gen-machineconf parse-sdt` (the
  flow AMD recommends; `parse-xsa` is deprecated). There is no pinned
  AMD-validated MACHINE and no per-target flow selection. The custom machine is
  named `${BD_NAME}-<target>` (i.e. `mrmac-<target>`); `configure-build.sh`
  takes `BD_NAME` as an argument so the script stays repo-agnostic.

* **The bitstream lives in BOOT.BIN**, not loaded at runtime via FPGA manager.
  Because no PL overlay is requested, the `.pdi` `sdtgen` extracted from the XSA
  is embedded into `BOOT.BIN` and the PLM programs the PL during boot.

* **`system-user.dtsi` and `port-config.dtsi` are scoped to the Linux device
  tree** (via a guard on `CONFIG_DTFILE`). The FSBL/PLM/PSM domain device-trees
  don't define the SoC peripheral / `mrmac` / `sfp_port*` labels the overrides
  reference, so including them there makes `dtc` fail with "Label or path …
  not found".

* **Adding a target**: set `"yocto": true` for the design in `config/data.json`
  and run `config/update.py` (regenerates the README table), then create the
  board BSP under `bsp/<board>/` following `bsp/vck190`. If the target uses a
  port count or line rate not already covered, add a
  `bsp/port-configs/<ports-versal-XXXX>/` overlay.
```
