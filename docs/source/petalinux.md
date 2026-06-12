# PetaLinux

PetaLinux can be built for this reference design by using the Makefile in the `PetaLinux` directory
of the repository.

## Requirements

To build the PetaLinux project, you will need a physical or virtual machine running one of the 
[supported Linux distributions] with Vivado 2025.2 and PetaLinux Tools 2025.2 installed.

```{attention}
You cannot build the PetaLinux project in the Windows operating system. Windows
users are advised to use a Linux virtual machine to build the PetaLinux project.
```

## How to build

1. From a command terminal, clone the Git repository and `cd` into it.
   ```
   git clone https://github.com/fpgadeveloper/sfp28-fmc-mrmac.git
   cd sfp28-fmc-mrmac
   ```
2. Launch PetaLinux by sourcing the `settings.sh` bash script, eg:
   ```
   source <path-to-petalinux-install>/2025.2/settings.sh
   ```
3. Launch Vivado by sourcing the `settings64.sh` bash script, eg:
   ```
   source <path-to-xilinx-tools>/2025.2/Vivado/settings64.sh
   ```
4. Build the Vivado and PetaLinux project for your specific target platform by running the following
   commands and replacing `<target>` with one of the target design labels listed in build instructions.
   ```
   cd PetaLinux
   make petalinux TARGET=<target>
   ```
   
The last command will launch the build process for the corresponding Vivado project if that project
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

The default login is username `petalinux`; on first login you will be prompted to set a password.

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
(`cat /sys/kernel/debug/clk/clk_summary | grep clk0`). A port with a link partner connected then
prints `MRMAC link up at 25000` — see [Link bring-up and
monitoring](#link-bring-up-and-monitoring) below.

### SFP module management

The four SFP28 cages are exposed through the kernel SFP framework as `sfp-eth0` through
`sfp-eth3`: module presence is detected through the MOD_ABS GPIO, and an inserted module's
EEPROM and diagnostics (hwmon) are accessible over the I2C mux. Note that because the MRMAC
ports are driven by the `xilinx_axienet` driver (which has no phylink), the cages are standalone
management devices — they are **not** linked to the MACs, and module insertion/removal does not
affect the carrier state of the `ethN` interfaces.

## Example Usage

The examples below were captured on a `vck190_fmcp1_25g` build (25GbE) with an SFP28 optical
module in slot 0. On a `vck190_fmcp1` build the reported speed is 10000Mb/s instead. Substitute
your own interface name (see the [Port configurations](#port-configurations) section above for
the mapping).

### Loopback self-test

The rootfs includes a bundled self-test, `mrmac-loopback-test`, that validates a port's full
datapath (MRMAC ↔ AXIS adapter ↔ MCDMA ↔ DDR) without needing a link partner. Plug an **SFP28
passive loopback module** into the port under test, then run the test as root:

```
# mrmac-loopback-test eth0
```

The script uses the kernel `pktgen` module to blast frames out the interface to its own MAC
address (which loop back through the passive module), then checks that the received frame count
matches the transmitted count and that frames arrive intact (full-size, no errors). A passing
run ends like this:

```
---------------------------------------------------------------------------
 TX frames : 1000000    (bytes 1500000000)
 RX frames : 1000000    (bytes 1500000000)
 RX avg frame size : 1500 bytes  (expect ~1500; ~48 = beat-fragmentation bug)
 RX errors : 0    RX dropped : 0
---------------------------------------------------------------------------
 VERDICT: PASS
===========================================================================
```

`TX frames == RX frames` with an RX average frame size of ~1500 bytes and zero errors confirms
that frames traverse the datapath and return intact. (A tiny RX average frame size would indicate
a frame-delineation problem in the client datapath.) Repeat for the other ports with a loopback
module in their slots:

```
# mrmac-loopback-test eth1
```

### Link bring-up and monitoring

Each MRMAC port carries no PHY and emits no link-change interrupt, so the
`xilinx_axienet` driver in this design runs a background **carrier monitor** (see the
*Modifications layered on the stock BSP* section of [advanced](advanced)). With a link
partner connected — an optical module, AOC or DAC to another 10G/25G device at the matching
rate — the port comes up **automatically**; no `ip link` bounce or manual reset is needed:

```
[   13.092047] xilinx_axienet 80010000.mrmac eth0: MRMAC setup at 25000 (link monitored)
[   13.101062] xilinx_axienet 80010000.mrmac eth0: MRMAC link up at 25000
```

Carrier tracks the physical link, so the port reads `UP` in `ip link` only while a partner is
present, and the monitor follows cable events — unplug and re-seat the module and the link drops
and recovers on its own:

```
[   73.074149] xilinx_axienet 80010000.mrmac eth0: MRMAC link down
[   79.026154] xilinx_axienet 80010000.mrmac eth0: MRMAC link up at 25000
```

```{note}
The MRMAC ports run with **no auto-negotiation and no FEC**, so the link partner must be
configured to match: fixed 10G (or 25G on the `_25g` targets), auto-negotiation off, FEC off.
The module itself must also support the line rate — a 25G-only SFP28 module (e.g. a single-rate
SFP-25G-SR) will **not** link up on the 10G targets, because its CDR cannot lock at the
10.3125 Gb/s line rate. See [troubleshooting](troubleshooting).
```

### Assign an IP address

The link itself comes up on its own (above); to pass IP traffic, give the port an address. Each
port must be on its own subnet.

```
# ip addr add 192.168.1.10/24 dev eth0
# ping 192.168.1.1
PING 192.168.1.1 (192.168.1.1): 56 data bytes
64 bytes from 192.168.1.1: seq=0 ttl=64 time=0.216 ms
64 bytes from 192.168.1.1: seq=1 ttl=64 time=0.130 ms
```

`eth0` also attempts DHCP at boot, so if it is connected to a network with a DHCP server it may
already have an address (`ip -br addr`).

### Inspect port settings with ethtool

```
# ethtool eth0
Settings for eth0:
        Speed: 25000Mb/s
        Duplex: Full
        Link detected: yes
```

`Link detected: yes` along with the expected speed confirms the port's GT lane has acquired
block lock and the link is up.

### Throughput test with iperf3

`iperf3` is the standard tool for measuring TCP/UDP throughput over a link. Run it as a server on
one end and a client on the other; data flows from client to server by default (use `-R` to
reverse). Single-stream throughput on these embedded SoCs is **CPU-bound** — the path traverses
the kernel TCP/IP stack and the single-queue `xilinx_axienet` MCDMA driver on a Cortex-A72 — so
the measured figures fall short of line rate, particularly at 25G.

#### On the host PC (server side)

```
$ sudo apt install iperf3
$ iperf3 -s
-----------------------------------------------------------
Server listening on 5201 (test #1)
-----------------------------------------------------------
```

#### On the PetaLinux target (client side)

A single TCP stream is limited by one CPU core, so use several parallel streams (`-P`), e.g.
with the target's `eth0` connected to a host PC's NIC at `192.168.1.1`:

```
# iperf3 -c 192.168.1.1 -P 8 -t 20
```

Reversing the direction (`-R`, host → target) or switching to UDP (`-u -b <rate>`) exercises
the other paths, but all are bounded by the same embedded-CPU ceiling, not by the link. The
link layer itself operates at the full line rate, as confirmed by `ethtool eth0` and by the
`mrmac-loopback-test` self-test (which moves full-size frames through the MRMAC and MCDMA with
zero errors). Designs that need sustained line-rate traffic on all four ports keep the bulk
datapath in the fabric (parsing at the MRMAC client interface and processing in PL/AI Engines)
and pass only low-volume control traffic up the MCDMA path to Linux.

[Quad SFP28 FMC]: https://docs.opsero.com/op081/datasheet/overview/
[supported Linux distributions]: https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Setting-Up-Your-Environment
