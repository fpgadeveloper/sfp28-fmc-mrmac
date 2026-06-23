# Yocto

The Yocto / EDF flow (AMD's Embedded Development Framework) is the announced successor to
PetaLinux. It can be built for the 10G/25G Ethernet (MRMAC) reference designs with the
cross-platform `build.py` runner at the root of the repository, and produces a Linux image that
exercises the SFP28 / MRMAC ports in exactly the same way as the PetaLinux flow.

```{note}
For 2025.2 both the PetaLinux and Yocto flows are supported and produce an equivalent
image. From the next tool version onward, the PetaLinux flow for this repository will be retired
and Yocto will be the only supported flow.
```

The Yocto flow is supported for the Versal targets (the same set that has PetaLinux support) —
both the 10G and 25G designs on the VCK190.

## Requirements

To build the Yocto projects you will need a physical or virtual machine running one of the
[supported Linux distributions], with the Vitis Core Development Kit installed — the flow uses
`xsct`/`sdtgen` (which ship with Vitis) to generate a System Device Tree from the Vivado XSA. You
also need [Google's repo tool](https://gerrit.googlesource.com/git-repo/) on your `PATH`.

```{attention}
You cannot build the Yocto projects in the Windows operating system. Windows users
are advised to use a Linux virtual machine to build the Yocto projects.
```

## How to build

The build runner locates and sources the Vivado and Vitis settings itself, so there is no
need to source them by hand; you only need [Google's repo tool](https://gerrit.googlesource.com/git-repo/)
on your `PATH` (see Requirements above).

1. From a command terminal, clone the Git repository (with its submodules) and `cd` into it:
   ```
   git clone --recurse-submodules https://github.com/fpgadeveloper/sfp28-fmc-mrmac.git
   cd sfp28-fmc-mrmac
   ```
2. Build the Yocto image for your target by running the following command, replacing
   `<target>` with one of the target design labels listed in the
   [build instructions](build_instructions.md#target-designs):
   ```
   ./build.sh yocto --target <target>
   ```

This command launches the corresponding Vivado build if that project has not already been
built and its hardware exported. The first build of a target downloads several GB of sources
(`repo sync`) and runs bitbake from scratch, so it takes a while; subsequent builds are
incremental. The output products are gathered into `Yocto/<target>/images/linux/`:

| File | Description |
| --- | --- |
| `BOOT.BIN` | Boot image (PLM + `.pdi` bitstream + FSBL + U-Boot) |
| `boot.scr` | U-Boot boot script |
| `Image` | Linux kernel (Versal, aarch64) |
| `system.dtb` | Linux device tree |
| `rootfs.wic.xz` | Full SD-card disk image — this is what you flash |
| `rootfs.wic.bmap` | Block map for `bmaptool` (fast flashing) |
| `rootfs.tar.gz` | Root filesystem tarball |

## Boot from SD card

Unlike the PetaLinux flow (which produces separate boot files for a hand-partitioned card), the
Yocto flow produces a **full SD-card disk image** (`rootfs.wic.xz`) that already contains all
partitions. You flash that image to the SD card's raw device, then copy `BOOT.BIN` and `boot.scr`
onto the first FAT partition (`esp`).

### Prepare the SD card

```{warning}
Flashing writes directly to a raw block device and cannot be undone. Be absolutely
certain you have identified the SD card's device node before running the commands below — if you
use the wrong device you risk destroying data on one of your hard drives.
```

1. Identify the SD card device. With the card **un**plugged, run `lsblk -o NAME,SIZE,RM,TYPE`,
   insert the card, and run it again. The new entry — typically `/dev/sdX`, with `RM=1`
   (removable) and a size matching your card — is your target. Replace `sdX` with that device,
   and `<target>` with your board, below.
2. Unmount any partitions the desktop auto-mounted:
   ```
   for p in /dev/sdX?*; do sudo umount "$p" 2>/dev/null; done
   ```
3. Flash the wic image to the raw device. With `bmaptool` (fast — only writes used blocks):
   ```
   sudo bmaptool copy --bmap Yocto/<target>/images/linux/rootfs.wic.bmap \
                            Yocto/<target>/images/linux/rootfs.wic.xz \
                            /dev/sdX
   ```
   Or, as a fallback with `dd`:
   ```
   xzcat Yocto/<target>/images/linux/rootfs.wic.xz \
       | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   ```
4. **Install `BOOT.BIN` and `boot.scr` on the `esp` partition.** The Versal EDF wic uses a
   3-partition layout — `esp` (vfat), `storage` (vfat), `root` (ext4). The Versal BootROM
   FAT-boots `BOOT.BIN` from the first FAT partition (`esp`) and U-Boot then loads the kernel via
   the `boot.scr`, so copy both onto `esp` by hand:
   ```
   sudo partprobe /dev/sdX
   sudo mkdir -p /mnt/sd_esp
   sudo mount /dev/sdX1 /mnt/sd_esp
   sudo cp Yocto/<target>/images/linux/BOOT.BIN  /mnt/sd_esp/BOOT.BIN
   sudo cp Yocto/<target>/images/linux/boot.scr  /mnt/sd_esp/boot.scr
   sync
   sudo umount /mnt/sd_esp && sudo rmdir /mnt/sd_esp
   ```
   (If your desktop auto-mounts the partitions, you can instead copy the two files straight onto
   the `esp` mountpoint.)
5. Eject the card cleanly so pending writes flush: `sudo eject /dev/sdX`.

### Boot

1. Plug the SD card into the VCK190 and set it to boot from SD. The boot-mode DIP-switch
   settings are the same regardless of the Linux flow — see the switch settings under
   [Boot PetaLinux](petalinux.md#boot-petalinux).
2. Connect the [Quad SFP28 FMC] to the board's FMCP1 connector and insert your SFP+/SFP28
   modules.
3. Connect the USB-UART to your PC and open a terminal emulator at 115200 baud (8N1) — see
   [UART terminal](petalinux.md#uart-terminal).
4. Connect and power your hardware.

## Using the SFP28 ports

Once Linux has booted and you have logged in at the console, the SFP28 / MRMAC ports are
exercised exactly as in the PetaLinux flow — see [Example Usage](petalinux.md#example-usage) for
the link bring-up, fixed-IP, `ethtool`, `iperf3` and loopback-self-test walkthrough.

```{note}
**Interface names may differ from the PetaLinux flow.** The EDF rootfs uses the systemd
predictable-naming scheme, so the four SFP28/MRMAC ports may appear under different names than the
PetaLinux `eth0`–`eth3`. Identify a port by its MAC address (Port 0 = `00:0a:35:00:00:00`,
Port 1 = `…:01`, Port 2 = `…:02`, Port 3 = `…:03`) or by the controller base address printed at
boot (`xilinx_axienet 80010000.mrmac …`), and substitute the appropriate name into the commands
in [Example Usage](petalinux.md#example-usage).
```

## Patches and known issues

The per-board fixups applied in the Yocto flow live under `Yocto/bsp/` — the board
`system-user.dtsi` device-tree override, the per-target `port-config.dtsi` overlays, and the
kernel `bsp.cfg` fragments (see the `Yocto/` folder README for the full list). The notable ones:

* **SFP28 / MRMAC port wiring (`port-config.dtsi`).** The off-chip Quad SFP28 FMC peripherals are
  not described by the XSA, so each target applies a port-config overlay (`ports-versal-0123` for
  the 10G design, `ports-versal-0123-25g` for the 25G design) that adds, for each of the four
  MRMAC ports, the MAC address, line rate (`max-speed`) and GT-control GPIO, plus the FMC I2C tree
  (PCA9548 mux → SFP module I2C + Si5328 GT reference clock) and the four SFP cage descriptors.
* **MCDMA datapath claim.** The overlay overrides each port's AXI MCDMA `compatible` to
  `"xlnx,eth-dma"` so the AXI Ethernet driver — not the standalone `xilinx_dma` dmaengine driver —
  claims the datapath; otherwise the axienet probe fails `-EBUSY`.
* **10G vs 25G line rate.** The two overlays differ only in the per-port `max-speed` (`10000` vs
  `25000`), which the axienet/MRMAC driver uses to configure the MAC rate.
* **zocl (Versal).** `system-user.dtsi` adds the `zyxclmm_drm` node (`xlnx,zocl-versal`) under
  `&amba` so the Xilinx OpenCL/zocl runtime node is present.

[Quad SFP28 FMC]: https://docs.opsero.com/op081/datasheet/overview/
[supported Linux distributions]: https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Setting-Up-Your-Environment
