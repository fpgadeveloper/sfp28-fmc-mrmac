# PetaLinux

PetaLinux can be built for this reference design with the cross-platform `build.py`
runner at the root of the repository.

## Requirements

To build the PetaLinux project, you will need a physical or virtual machine running one of the 
[supported Linux distributions] with Vivado 2025.2 and PetaLinux Tools 2025.2 installed.

```{attention}
You cannot build the PetaLinux project in the Windows operating system. Windows
users are advised to use a Linux virtual machine to build the PetaLinux project.
```

## How to build

The build runner locates and sources the PetaLinux and Vivado settings itself, so there
is no need to source them by hand. See the [build instructions](build_instructions) for
the full description of the runner.

1. From a command terminal, clone the Git repository and `cd` into it:
   ```
   git clone https://github.com/fpgadeveloper/sfp28-fmc-mrmac.git
   cd sfp28-fmc-mrmac
   ```
2. Build the PetaLinux image for your target by running the following command and replacing
   `<target>` with one of the target design labels found in the build instructions:
   ```
   ./build.sh petalinux --target <target>
   ```

This will also launch the build process for the corresponding Vivado project if that project
has not already been built and its hardware exported.

## Boot from SD card

### Prepare the SD card

Once the build process is complete, you must prepare the SD card for booting PetaLinux.

1. The SD card must first be prepared with two partitions: one for the boot files and another 
   for the root file system.

   * Plug the SD card into your computer and find its device name using the `dmesg` command.
     The SD card should be found at the end of the log, and its device name should be something
     like `/dev/sdX`, where `X` is a letter such as a,b,c,d, etc. Note that you should replace
     the `X` in the following instructions.
     
```{warning}
Do not continue these steps until you are certain that you have found the correct
device name for the SD card. If you use the wrong device name in the following steps, you risk
losing data on one of your hard drives.
```
   * Run `fdisk` by typing the command `sudo fdisk /dev/sdX`
   * Make the `boot` partition: typing `n` to create a new partition, then type `p` to make 
     it primary, then use the default partition number and first sector. For the last sector, type 
     `+1G` to allocate 1GB to this partition.
   * Make the `boot` partition bootable by typing `a`
   * Make the `root` partition: typing `n` to create a new partition, then type `p` to make 
     it primary, then use the default partition number, first sector and last sector.
   * Save the partition table by typing `w`
   * Format the `boot` partition (FAT32) by typing `sudo mkfs.vfat -F 32 -n boot /dev/sdX1`
   * Format the `root` partition (ext4) by typing `sudo mkfs.ext4 -L root /dev/sdX2`

2. Copy the following files to the `boot` partition of the SD card:
   Assuming the `boot` partition was mounted to `/media/user/boot`, follow these instructions:
   ```
   $ cd /media/user/boot/
   $ sudo cp /<petalinux-project>/images/linux/BOOT.BIN .
   $ sudo cp /<petalinux-project>/images/linux/boot.scr .
   $ sudo cp /<petalinux-project>/images/linux/image.ub .
   ```

3. Create the root file system by extracting the `rootfs.tar.gz` file to the `root` partition.
   Assuming the `root` partition was mounted to `/media/user/root`, follow these instructions:
   ```
   $ cd /media/user/root/
   $ sudo cp /<petalinux-project>/images/linux/rootfs.tar.gz .
   $ sudo tar xvf rootfs.tar.gz -C .
   $ sync
   ```
   
   Once the `sync` command returns, you will be able to eject the SD card from the machine.

```{tip}
The `bootimages/` directory of the repo (and the release zip) contains the boot files
already arranged into `boot/` and `root/` folders, so you can simply copy the contents of `boot/`
to the FAT32 partition and extract `root/rootfs.tar.gz` to the ext4 partition.
```

### Boot PetaLinux

1. Plug the SD card into your target board.
2. Ensure that the target board is configured to boot from SD card:
   * **VCK190:** DIP switch SW1 is set to 1000 (1=ON,2=OFF,3=OFF,4=OFF)
3. Connect the [Quad SFP28 FMC] to the FMCP1 connector of the target board.
4. Connect the USB-UART to your PC and then open a UART terminal set to 115200 baud and the 
   comport that corresponds to your target board.
5. Connect and power your hardware.

Before booting Linux, U-Boot switches on the FMC's VADJ supply (1.5 V) by programming the
VCK190's VADJ regulator over I2C (the `vadj_1v5_en` command in the board BSP's U-Boot
configuration), so that the FMC's I2C devices, the Si5328 clock generator and the GT lanes are
powered when Linux probes them. The kernel command line is

```
console=ttyAMA0 earlycon=pl011,mmio32,0xFF000000,115200n8 clk_ignore_unused root=/dev/mmcblk0p2 rw rootwait rootfs=ext4 uio_pdrv_genirq.of_id=generic-uio
```

The default login is username `petalinux`; no password is asked at the first login, but you must
set a new one straight away. The hostname is `vck190-sfp28-2025-2`.

## Boot via JTAG

```{tip}
You need to install the cable drivers before being able to boot via JTAG.
Note that the Vitis installer does not automatically install the cable drivers, it must be done separately.
For instructions, read section 
[installing the cable drivers](https://docs.amd.com/r/en-US/ug973-vivado-release-notes-install-license/Installing-Cable-Drivers) 
from the Vivado release notes.
```

```{warning}
The Versal design stores the root filesystem on the SD card, so you must still
prepare and connect the SD card before booting via JTAG. If you boot via JTAG without the SD card,
the boot will hang at a message similar to: `Waiting for root device /dev/mmcblk0p2...`
```

### Setup hardware

1. Prepare the SD card according to the [instructions above](#prepare-the-sd-card) and plug the SD card 
   into your target board.
2. Ensure that the target board is configured to boot from JTAG:
   * **VCK190:** DIP switch SW1 is set to 1111 (1=ON,2=ON,3=ON,4=ON)
3. Connect the [Quad SFP28 FMC] to the FMCP1 connector of the target board.
4. Connect the USB-UART to your PC and then open a UART terminal set to 115200 baud and the 
   comport that corresponds to your target board.
5. Connect and power your hardware.

### Boot PetaLinux

To boot PetaLinux on hardware via JTAG, use the following commands in a Linux command terminal:

1. Change current directory to the PetaLinux project directory for your target design:
   ```
   cd <project-dir>/PetaLinux/<target>
   ```
2. Download the device image to the Versal device and boot the kernel:
   ```
   petalinux-boot --jtag --kernel
   ```

## UART terminal

You will need to setup a terminal emulator to use the PetaLinux command line over the USB-UART connection.
Connect with a baud rate of 115200.

### In Windows

You will need to find the comport for the USB-UART in Windows Device Manager. As a terminal emulator, you
can use the open source and free [Putty](https://www.putty.org/).

### In Linux

The VCK190 presents a multi-port FTDI USB-UART; the PetaLinux console is on the second interface
(typically `/dev/ttyUSB1`). You can find the tty devices by running `dmesg | grep tty`. To open a
terminal emulator, you can use the following command:

```
sudo screen /dev/ttyUSB1 115200
```

## Port configurations

The four SFP28 ports are driven by the MRMAC and appear as `eth0` through `eth3`. The VCK190's two
built-in PS Ethernet (GEM) ports use persistent `endN` names. The numbering arises from how the
network interfaces are renamed at boot:

| Interface | Driver           | Connector                       | MAC address         |
|-----------|------------------|---------------------------------|---------------------|
| `end0`    | macb             | VCK190 built-in Ethernet (GEM0) | (board-assigned)    |
| `end1`    | macb             | VCK190 built-in Ethernet (GEM1) | (board-assigned)    |
| `eth0`    | xilinx_axienet   | Quad SFP28 FMC port 0           | `00:0a:35:00:00:00` |
| `eth1`    | xilinx_axienet   | Quad SFP28 FMC port 1           | `00:0a:35:00:00:01` |
| `eth2`    | xilinx_axienet   | Quad SFP28 FMC port 2           | `00:0a:35:00:00:02` |
| `eth3`    | xilinx_axienet   | Quad SFP28 FMC port 3           | `00:0a:35:00:00:03` |

> **Note on the mixed `endN` / `ethN` names.** The PS GEM ports have their MAC address assigned at
> netdev-creation time, so they pick up the persistent `endN` rename. The four MRMAC ports get
> their MAC addresses later, from the `port-config.dtsi` overlay, after the udev rename rule has
> already run, so they keep their kernel-default `ethN` names. The interfaces work identically;
> only the names differ. Use `ethtool -i <name>` to confirm which driver is behind each interface
> (`xilinx_axienet` = a Quad SFP28 FMC port; `macb` = a VCK190 built-in GEM).

### Identifying the mapping at runtime

`ip -br link` lists the interfaces (including those that are `DOWN`, which a bare `ifconfig`
hides), and `ethtool -i <name>` or the kernel bring-up messages in `dmesg` tell you which driver
is behind each one:

```sh
$ ip -br link
end0    DOWN    xx:xx:xx:xx:xx:xx <NO-CARRIER,BROADCAST,MULTICAST,UP>
end1    DOWN    xx:xx:xx:xx:xx:xx <NO-CARRIER,BROADCAST,MULTICAST,UP>
eth0    UP      00:0a:35:00:00:00 <BROADCAST,MULTICAST,UP,LOWER_UP>
eth1    DOWN    00:0a:35:00:00:01 <NO-CARRIER,BROADCAST,MULTICAST,UP>
eth2    DOWN    00:0a:35:00:00:02 <NO-CARRIER,BROADCAST,MULTICAST,UP>
eth3    DOWN    00:0a:35:00:00:03 <NO-CARRIER,BROADCAST,MULTICAST,UP>
lo      UNKNOWN 00:00:00:00:00:00 <LOOPBACK,UP,LOWER_UP>

$ ethtool -i eth0 | head -1
driver: xilinx_axienet      # -> Quad SFP28 FMC port

$ dmesg | grep -iE "mrmac|axienet|si53|block lock|link"
```

(In this capture only slot 0 has a module and a link partner, so only `eth0` shows carrier.)

A healthy bring-up prints `MRMAC setup at 25000 (link monitored)` for each port (`10000` on the
10G targets) and the Si5328 clock at 322265625 Hz
(`sudo cat /sys/kernel/debug/clk/clk_summary | grep clk0`). A port with a link partner connected
then prints `MRMAC link up at 25000 (0 recovery resets)` — see
[Link bring-up and the link monitor](testing.md#link-bring-up-and-the-link-monitor).

### SFP module management

The four SFP28 cages are exposed through the kernel SFP framework as `sfp-eth0` through
`sfp-eth3`: module presence is detected through the MOD_ABS GPIO, and an inserted module's
EEPROM and diagnostics (hwmon) are accessible over the I2C mux. Note that because the MRMAC
ports are driven by the `xilinx_axienet` driver (which has no phylink), the cages are standalone
management devices — they are **not** linked to the MACs, and module insertion/removal does not
affect the carrier state of the `ethN` interfaces.

## Using and testing the ports

How to configure a link partner, bring the ports up, read the counters (`ethtool -S`, the RX
drop counters), measure throughput with `iperf3` (with the numbers to expect) and run the bundled
`mrmac-loopback-test` self-test is described in [Testing the design](testing). The PetaLinux and
Yocto images behave the same; the PetaLinux image has `devmem` (BusyBox) instead of `devmem2`
and does not include `nstat`.

[Quad SFP28 FMC]: https://docs.opsero.com/op081/datasheet/overview/
[supported Linux distributions]: https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Setting-Up-Your-Environment
