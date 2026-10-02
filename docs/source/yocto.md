# Yocto

The Yocto / EDF flow (AMD's Embedded Development Framework) is the announced successor to
PetaLinux. It can be built for the 10G/25G Ethernet (MRMAC) reference designs with the
cross-platform `build.py` runner at the root of the repository, and produces a Linux image that
drives the SFP28 / MRMAC ports with the same kernel driver, patches and test tools as the
PetaLinux image.

```{note}
For 2025.2 both the PetaLinux and Yocto flows are supported and produce an equivalent
image. From the next tool version onward, the PetaLinux flow for this repository will be retired
and Yocto will be the only supported flow.
```

The Yocto flow is supported for both targets: `vck190_fmcp1` (4x 10GbE) and `vck190_fmcp1_25g`
(4x 25GbE).

## Requirements

To build the Yocto projects you will need:

* A physical or virtual machine running one of the [supported Linux distributions].
* Vivado 2025.2 and Vitis 2025.2. The flow uses `xsct`/`sdtgen`, which ship with Vitis, to
  generate a System Device Tree from the Vivado XSA.
* [Google's repo tool](https://gerrit.googlesource.com/git-repo/) on your `PATH`, plus the
  usual Yocto host packages (the list for Ubuntu is in `Yocto/README.md` of the repository).
* An internet connection for the first build (it downloads several GB of layers and sources), or
  a local sstate-cache mirror (see [Offline builds](#offline-builds)), and enough free disk
  space: a target's Yocto workspace takes several tens of GB.
* The (free) MRMAC license, to generate the bitstream — see the
  [build instructions](build_instructions.md#license-requirements).

```{attention}
You cannot build the Yocto projects in the Windows operating system. Windows users
are advised to use a Linux virtual machine to build the Yocto projects.
```

## How to build

The build runner locates and sources the Vivado and Vitis settings itself, so there is no
need to source them by hand.

1. From a command terminal, clone the Git repository and `cd` into it:
   ```
   git clone https://github.com/fpgadeveloper/sfp28-fmc-mrmac.git
   cd sfp28-fmc-mrmac
   ```
2. Build the Yocto image for your target by running the following command, replacing
   `<target>` with one of the target design labels listed in the
   [build instructions](build_instructions.md#target-designs):
   ```
   ./build.sh yocto --target <target>
   ```
3. Gather the files you need for the SD card into a zip in `bootimages/`:
   ```
   ./build.sh package --target <target>
   ```

The `yocto` command builds the Vivado project and exports the hardware first if that has not
already been done. The first build of a target downloads several GB of sources (`repo sync`) and
runs bitbake from scratch, so it takes a while; subsequent builds are incremental.
`./build.sh all --target <target>` builds the Vivado project, the standalone application, the
PetaLinux image and the Yocto image, and then packages all of them.

### Build outputs

The output products are gathered into `Yocto/<target>/images/linux/`:

| File | Description |
| --- | --- |
| `BOOT.BIN` | Boot image (PLM + the `.pdi` device image incl. the bitstream + PSM + TF-A + U-Boot) |
| `Image` | Linux kernel (aarch64) |
| `system.dtb` | Linux device tree |
| `u-boot.elf` | U-Boot |
| `rootfs.wic.xz` | Full SD-card disk image — this is what you flash |
| `rootfs.wic.bmap` | Block map for `bmaptool` (fast flashing) |
| `rootfs.tar.gz` | Root filesystem tarball |

`./build.sh package` writes `bootimages/sfp28-fmc-mrmac_<target>_yocto-2025-2.zip`, which holds
everything needed to write an SD card:

| File in the zip | Description |
| --- | --- |
| `rootfs.wic.xz`, `rootfs.wic.bmap` | the SD-card disk image and its block map |
| `BOOT.BIN` | the boot image, to copy onto the first partition |
| `BOOTAA64.EFI` | the systemd-boot EFI loader, to copy into `EFI/BOOT/` on the first partition |
| `readme.txt` | short version of the instructions below |

## Boot from SD card

The Yocto flow produces a **full SD-card disk image** (`rootfs.wic.xz`) with three partitions:
`esp` (FAT, the boot partition), `storage` (FAT) and `root` (ext4). The root partition is
expanded to fill the card on the first boot.

The disk image does **not** contain the two files the Versal needs to start booting from it, so
after flashing you must copy them onto the first partition by hand:

* `BOOT.BIN` — the Versal BootROM loads it from the first FAT partition;
* `BOOTAA64.EFI` (systemd-boot) into `EFI/BOOT/` — U-Boot starts it to boot Linux. Without it,
  the boot stops at the U-Boot prompt.

Both files are in the zip from `./build.sh package`. (If you work from
`Yocto/<target>/images/linux/` instead, `BOOTAA64.EFI` is
`usr/lib/systemd/boot/efi/systemd-bootaa64.efi` inside `rootfs.tar.gz`.)

### Prepare the SD card

```{warning}
Flashing writes directly to a raw block device and cannot be undone. Be absolutely
certain you have identified the SD card's device node before running the commands below — if you
use the wrong device you risk destroying data on one of your hard drives.
```

The commands below assume you have extracted the zip from `bootimages/` into the current
directory.

1. Identify the SD card device. With the card **un**plugged, run `lsblk -o NAME,SIZE,RM,TYPE`,
   insert the card, and run it again. The new entry — typically `/dev/sdX`, with `RM=1`
   (removable) and a size matching your card — is your target. Replace `sdX` with that device
   below.
2. Unmount any partitions the desktop auto-mounted:
   ```
   for p in /dev/sdX?*; do sudo umount "$p" 2>/dev/null; done
   ```
3. Flash the disk image to the raw device (not to a partition). With `bmaptool` (fast — only
   writes the used blocks):
   ```
   sudo bmaptool copy --bmap rootfs.wic.bmap rootfs.wic.xz /dev/sdX
   ```
   Or, as a fallback with `dd`:
   ```
   xzcat rootfs.wic.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   ```
4. Copy `BOOT.BIN` and `BOOTAA64.EFI` onto the first partition (`esp`):
   ```
   sudo partprobe /dev/sdX
   sudo mkdir -p /mnt/sd_esp
   sudo mount /dev/sdX1 /mnt/sd_esp
   sudo cp BOOT.BIN /mnt/sd_esp/
   sudo mkdir -p /mnt/sd_esp/EFI/BOOT
   sudo cp BOOTAA64.EFI /mnt/sd_esp/EFI/BOOT/
   sync
   sudo umount /mnt/sd_esp && sudo rmdir /mnt/sd_esp
   ```
5. Eject the card cleanly so pending writes flush: `sudo eject /dev/sdX`.

### Boot

1. Plug the SD card into the VCK190 and set it to boot from SD card:
   * **VCK190:** DIP switch SW1 is set to 1000 (1=ON,2=OFF,3=OFF,4=OFF)
2. Connect the [Quad SFP28 FMC] to the board's FMCP1 connector and insert your SFP+/SFP28
   modules.
3. Connect the USB-UART to your PC and open a terminal emulator at 115200 baud (8N1) — see
   [UART terminal](petalinux.md#uart-terminal). Optionally connect the board's RJ45 port
   (`end0`) to your network for SSH access.
4. Connect and power your hardware.

The boot goes through the PLM (which also configures the PL with the design), U-Boot, the
systemd-boot menu and the Linux kernel. Before it boots, U-Boot switches on the FMC's VADJ
supply (1.5 V) — the `Setting bus to 1` line below is that step. systemd-boot shows a menu
(`EDF Linux` / `EDF Xen`) and starts `EDF Linux` after 5 seconds. An excerpt of a 25G target
boot log:

```
U-Boot 2025.01-...
CPU:   Versal
...
Bootmode: LVL_SHFT_SD_MODE1
Net:
ZYNQ GEM: ff0c0000, mdio bus ff0c0000, phyaddr 1, interface rgmii-id
...
eth1: ethernet@ff0d0000, eth2: mrmac@80010000, eth3: mrmac@80011000, eth4: mrmac@80012000, eth5: mrmac@80013000
Hit any key to stop autoboot:  0
Setting bus to 1
switch to partitions #0, OK
mmc0 is current device
Scanning mmc 0:1...
Booting: mmc 0
...
EFI stub: Booting Linux Kernel...
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x410fd083]
[    0.000000] Linux version 6.12.40-xilinx-...
...
[    0.000000] Kernel command line: console=ttyAMA0 earlycon=pl011,mmio32,0xFF000000,115200n8 root=PARTUUID=... ro rootwait uio_pdrv_genirq.of_id=generic-uio clk_ignore_unused cma=1536M
...
[    4.564841] si5324 7-0068: si5328 probed
[    4.627592] si5324 7-0068: si5328 probe successful
...
[    5.548655] sfp sfp-eth1: module OEM              SFP-25G-SR-S-MST rev 1.0  ...
...
Welcome to AMD Embedded Development Framework Linux distribution 25.11.1+release-... (scarthgap)!
...
[   13.893612] xilinx_axienet 80011000.mrmac eth1: MRMAC setup at 25000 (link monitored)
[   13.896067] xilinx_axienet 80011000.mrmac eth1: MRMAC link up at 25000 (0 recovery resets)
...
vck190-mrmac-2025-2 login:
```

(U-Boot's `ethN` numbering is its own; in Linux the MRMAC ports are `eth0`–`eth3` and the board
RJ45 ports `end0`/`end1`.)

### Log in

Log in as **`amd-edf`**. The first login does not ask for a password, but you must set a new
one straight away. `amd-edf` can run commands as root with `sudo`.

```
vck190-mrmac-2025-2 login: amd-edf
You are required to change your password immediately (administrator enforced).
New password:
Retype new password:
...
vck190-mrmac-2025-2:~$
```

The image runs an SSH server, and every Ethernet interface — the board RJ45 ports and the SFP28
ports — runs a DHCP client, so you can also log in over the network once the password is set.

## Using the SFP28 ports

The SFP28 / MRMAC ports work exactly as in the PetaLinux image, with the same interface names
(`eth0`–`eth3` = SFP28 ports 0–3) and MAC addresses. Link bring-up, `ethtool`, the drop counters,
`iperf3` with expected numbers and the loopback self-test are described in
[Testing the design](testing).

Tools added to the image for this design: `ethtool`, `iperf3`, `nstat` (iproute2), `phytool`,
`mtd-utils`, `can-utils`, `nfs-utils`, `pciutils` and the `mrmac-loopback-test` self-test.
`devmem2` (for reading registers such as the [drop counters](registers)) is part of the EDF
image.

## What the Yocto BSP adds

The Yocto BSP lives under `Yocto/bsp/`. It is applied on top of a Yocto machine configuration
that is generated from the design's XSA, so the PL hardware (MRMAC ports, MCDMAs, GPIOs, I2C)
comes from the hardware design itself; the BSP adds what the XSA cannot describe:

* **SFP28 / MRMAC port wiring (`port-config.dtsi`).** The off-chip Quad SFP28 FMC peripherals
  are not described by the XSA, so each target applies a port-config overlay
  (`bsp/port-configs/ports-versal-0123` for the 10G design, `ports-versal-0123-25g` for the 25G
  design) that adds, for each of the four MRMAC ports, the MAC address, line rate (`max-speed`)
  and GT-control GPIO, plus the FMC I2C tree (PCA9548 mux → SFP module I2C + Si5328 GT reference
  clock) and the four SFP cage descriptors. It also overrides each port's AXI MCDMA
  `compatible` to `"xlnx,eth-dma"` so that the AXI Ethernet driver — not the standalone
  `xilinx_dma` dmaengine driver — claims the datapath (otherwise the probe fails with `-EBUSY`).
  The two overlays differ only in the per-port `max-speed` (`10000` vs `25000`).
* **Kernel patches** (shared with the PetaLinux BSP, in
  `bsp/vck190/meta-user/recipes-kernel/linux/linux-xlnx/`):
  * `0002-net-axienet-mrmac-carrier-link-monitor.patch` — the link monitor described in
    [Testing the design](testing.md#link-bring-up-and-the-link-monitor);
  * `0003-net-axienet-default-to-1024-RX-descriptors-on-MRMAC-.patch` — 1024 RX descriptors on
    the MRMAC ports;
  * `0004-net-axienet-report-the-MCDMA-S2MM-packet-drop-count-.patch` — `rx_dma_pkt_drop` in
    `ethtool -S`.
* **Kernel configuration (`bsp.cfg`):** the AXI Ethernet driver with MCDMA support, the AXI
  GPIO and AXI IIC drivers, the PCA954x I2C mux and the kernel SFP framework.
* **FMC VADJ in U-Boot.** On the VCK190 the FMC VADJ rail comes from a regulator that U-Boot
  programs over I2C before it boots Linux (`recipes-bsp/u-boot/files/vck190-vadj-bootcmd.cfg`).
  Without it VADJ can still be off when Linux probes the FMC, and the FMC's I2C devices, Si5328
  and GT lanes are dead. A second U-Boot fragment (`large-dtb-sp-bss.cfg`) makes room for this
  design's large device tree.
* **Board RJ45 ports (`system-user.dtsi`).** Describes the VCK190's two TI DP83867 Ethernet PHYs
  (RGMII delays) so the board RJ45 ports pass traffic, and gives them fixed MAC addresses. It
  also adds the `zyxclmm_drm` (zocl) node.
* **Kernel command line and hostname (`conf/local.conf.append`).** `clk_ignore_unused cma=1536M`
  are added to the kernel command line (through the systemd-boot entry, which is where the EDF
  boot flow takes the command line from), and the hostname is set to `vck190-mrmac-2025-2`.
* **Image packages** (`recipes-core/images/edf-linux-disk-image.bbappend`): the tools listed in
  [Using the SFP28 ports](#using-the-sfp28-ports).

The `Yocto/README.md` file of the repository describes the flow and the BSP layout in more
detail.

## Offline builds

To build without downloading the sstate cache, place the absolute path of a directory holding an
extracted AMD sstate-cache mirror (the "sstate-cache & Downloads - 2025.2" archives from the AMD
Embedded Design Tools download page) in a one-line text file `Yocto/offline.txt`. The directory
should contain `aarch64/` and `microblaze/` (both are needed: the platform firmware is built for
MicroBlaze) and optionally `downloads/`.

[Quad SFP28 FMC]: https://docs.opsero.com/op081/datasheet/overview/
[supported Linux distributions]: https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Setting-Up-Your-Environment
