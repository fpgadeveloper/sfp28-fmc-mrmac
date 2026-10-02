# Testing the design

This page describes how to bring up, use and test the four SFP28 ports once Linux is running on
the board — whether the image was built with [PetaLinux](petalinux) or with [Yocto](yocto). The
two images use the same kernel driver and the same patches, so the commands, messages and
counters are the same; where they differ (login, tools), both variants are shown.

For the bare-metal test application, see [Stand-alone Echo Server](echo_server).

## What you need

* The VCK190 with the [Quad SFP28 FMC] on FMCP1, booted from an SD card prepared as described in
  [PetaLinux](petalinux.md#boot-from-sd-card) or [Yocto](yocto.md#boot-from-sd-card).
* A USB cable to the board's USB-UART (115200 baud, 8N1) for the console. Optionally, connect the
  board's RJ45 port (PS GEM0, `end0`) to your LAN to log in over SSH.
* For each SFP28 port you want to test, one of:
  * **A link partner** running at the target's line rate: a 10G or 25G port of a NIC in a PC
    (Linux is assumed below) or of a switch, with a matching SFP+/SFP28 module or cable on both
    ends.
  * **An SFP28 passive loopback module**, for the bundled [loopback self-test](#loopback-self-test).
* SFP modules that support the line rate of the target: 10G (or dual-rate 10/25G) modules for
  `vck190_fmcp1`, 25G modules for `vck190_fmcp1_25g`. A 25G-only module will not link on the 10G
  target.

The measurements quoted on this page were taken with the Yocto images and these set-ups:

| Target | SFP28 port | Module in the FMC | Link partner |
|--------|------------|-------------------|--------------|
| `vck190_fmcp1` (10G) | 0 (`eth0`) | 10GBASE-T copper SFP+ module (RJ45) | 10G port of a NIC in a Linux PC |
| `vck190_fmcp1_25g` (25G) | 1 (`eth1`) | 25GBASE-SR SFP28 optical module | 25G port of a NIC in a Linux PC, FEC off |

### Configure the link partner

The MRMAC ports run at a **fixed** rate with **no auto-negotiation and no FEC**. The partner must
match, or the link will not come up. On a Linux PC (replace `<iface>` with the NIC port):

```
# 25G target
sudo ethtool -s <iface> autoneg off speed 25000 duplex full
sudo ethtool --set-fec <iface> encoding off

# 10G target
sudo ethtool -s <iface> autoneg off speed 10000 duplex full
```

Check the result with `ethtool <iface>` and `ethtool --show-fec <iface>`. Many 25G NICs enable
RS-FEC or BASE-R FEC by default (or select it automatically from the module type); a 25G link
with FEC enabled on one end only does not come up.

## Log in

| Image     | Console user | First login | Hostname |
|-----------|--------------|-------------|----------|
| PetaLinux | `petalinux`  | no password asked; you must set a new one | `vck190-sfp28-2025-2` |
| Yocto     | `amd-edf`    | no password asked; you must set a new one | `vck190-mrmac-2025-2` |

Both users can run commands as root with `sudo`. Both images run an SSH server, so once you have
set the password you can also log in over the board's RJ45 port (or over an SFP28 port).

## Network interfaces

| Interface | Driver           | Connector                       | MAC address         |
|-----------|------------------|---------------------------------|---------------------|
| `eth0`    | xilinx_axienet   | Quad SFP28 FMC port 0           | `00:0a:35:00:00:00` |
| `eth1`    | xilinx_axienet   | Quad SFP28 FMC port 1           | `00:0a:35:00:00:01` |
| `eth2`    | xilinx_axienet   | Quad SFP28 FMC port 2           | `00:0a:35:00:00:02` |
| `eth3`    | xilinx_axienet   | Quad SFP28 FMC port 3           | `00:0a:35:00:00:03` |
| `end0`    | macb             | VCK190 RJ45 (PS GEM0)           | see note            |
| `end1`    | macb             | VCK190 RJ45 (PS GEM1)           | see note            |

The names are the same in both images. In the Yocto image the two board RJ45 ports use fixed MAC
addresses set in `Yocto/bsp/vck190/meta-user/recipes-bsp/device-tree/files/system-user.dtsi`;
change them there if you run more than one board on the same network. `ethtool -i <name>` tells
you which driver is behind an interface.

```
$ ip -br link | grep ^e
eth0             UP             00:0a:35:00:00:00 <BROADCAST,MULTICAST,UP,LOWER_UP>
eth1             DOWN           00:0a:35:00:00:01 <NO-CARRIER,BROADCAST,MULTICAST,UP>
eth2             DOWN           00:0a:35:00:00:02 <NO-CARRIER,BROADCAST,MULTICAST,UP>
eth3             DOWN           00:0a:35:00:00:03 <NO-CARRIER,BROADCAST,MULTICAST,UP>
end0             UP             00:0a:35:06:21:90 <BROADCAST,MULTICAST,UP,LOWER_UP>
end1             DOWN           00:0a:35:06:21:91 <NO-CARRIER,BROADCAST,MULTICAST,UP>
```

(Yocto image, 10G target, a link partner on SFP28 port 0 and the board RJ45 `end0` on the LAN.)

The four SFP28 cages also appear as `sfp-eth0` to `sfp-eth3` in the kernel SFP framework, which
reports module insertion and identifies each module at boot:

```
$ dmesg | grep "sfp sfp-eth"
...
[    5.548655] sfp sfp-eth1: module OEM              SFP-25G-SR-S-MST rev 1.0  ...
[    5.569251] sfp sfp-eth0: module OEM              SFP-10G-T        rev 02   ...
```

The cages are management devices only (module presence, EEPROM, diagnostics); they are not
linked to the MACs, so inserting or removing a module does not by itself change the carrier of
`ethN`.

## Link bring-up and the link monitor

The MRMAC has no PHY and gives no link-change interrupt, so the design's kernel runs a **link
monitor** for each MRMAC port. When the interface is opened it prints:

```
xilinx_axienet 80010000.mrmac eth0: MRMAC setup at 10000 (link monitored)
```

(`25000` on the 25G target), and from then on:

* While the link is **up**, it checks the port once per second. The carrier (`LOWER_UP` in
  `ip link`, `Link detected: yes` in `ethtool`) follows the link.
* A port is declared **down** only after three consecutive bad samples, 200 ms apart, so a
  short disturbance does not reset a working link.
* While the link is **down**, it re-runs the port's MRMAC and GT datapath reset sequence every
  500 ms until the link returns. No `ip link` bounce or reboot is needed after re-seating a
  module or cable, or when the partner is switched on later than the board.

The messages, and what they mean:

| Message | Meaning |
|---------|---------|
| `MRMAC setup at <rate> (link monitored)` | The interface was opened; the monitor is running. |
| `MRMAC link up at <rate> (<n> recovery resets)` | RX block lock, RX status and a valid control code are present: carrier on. `<n>` is the number of recovery resets it took (0 when the link was there straight away). |
| `MRMAC link down (rx_sts 0x… blk_lck 0x… vld_ctrl 0x…)` | A port that was up lost its link: carrier off. The values are the raw status registers (see [Registers and counters](registers.md#mrmac-status-registers-link-state)). |
| `MRMAC link still down after <n> recovery resets (rx_sts … )` | The port has no link yet. Printed after 1, 2, 4, 8, 16, … recovery resets, so the messages become rarer over time. |

On a healthy 10G target with a partner on port 0 only, the boot log shows:

```
[   13.479543] xilinx_axienet 80010000.mrmac eth0: MRMAC setup at 10000 (link monitored)
[   13.481243] xilinx_axienet 80010000.mrmac eth0: MRMAC link up at 10000 (0 recovery resets)
...
[   15.684732] xilinx_axienet 80011000.mrmac eth1: MRMAC link still down after 4 recovery resets (rx_sts 0x180 blk_lck 0x0 vld_ctrl 0x0)
[   17.732735] xilinx_axienet 80011000.mrmac eth1: MRMAC link still down after 8 recovery resets (rx_sts 0x180 blk_lck 0x0 vld_ctrl 0x0)
```

The `still down` lines of ports that have nothing connected are expected and harmless. If a port
that *does* have a partner keeps printing them, see [Troubleshooting](troubleshooting).

```{note}
The carrier of an MRMAC port reflects the **receive** direction only (block lock on the incoming
signal). "Link up" on the board says nothing about whether the partner receives the board's
signal — check the partner's link state as well.
```

## Assign an IP address and ping

Each SFP28 port must be on its own IP subnet.

* **Yocto:** every Ethernet interface runs a DHCP client (systemd-networkd). If the partner is a
  network or a PC that serves DHCP on that port, the port gets an address automatically
  (`ip -br addr`).
* **PetaLinux:** `eth0` attempts DHCP at boot.

Otherwise give the port a static address, and give the partner an address on the same subnet:

```
sudo ip addr add 192.168.1.10/24 dev eth0
ping -c 5 192.168.1.1
```

On both targets, pings of 56 to 1472 bytes ran with 0% loss.

## Inspect the port with ethtool

```
$ sudo ethtool eth1 | grep -E "Speed|Link"
        Speed: 25000Mb/s
        Link detected: yes
```

The RX descriptor ring of the MRMAC ports defaults to 1024 entries (`ethtool -g eth1`), and
`ethtool -S` includes the MCDMA packet-drop count `rx_dma_pkt_drop`:

```
$ sudo ethtool -S eth0 | grep -E "err|drop"
     tx_errors: 0
     rx_errors: 0
     rx_dma_pkt_drop: 0
```

## Read the RX drop counters

Each port's RX frame FIFO counts the frames it had to drop, in channel 2 of the port's
GT-control GPIO. The register layout, a ready-made shell snippet and the other drop counters are
on the [Registers and counters](registers) page. A quick check of port 0 in the Yocto image:

```
sudo devmem2 0x80040008 w
```

A value of `0x00000003` means both GT reset-done bits are set and no frame has been dropped.
Bits `[31:8]` count frames dropped because the FIFO was full, bits `[7:2]` frames the MAC
flagged as bad.

For a complete picture of where received frames went during a test, record before and after the
test:

* the FIFO drop counters (`GPIO2_DATA` of the port),
* `ethtool -S <iface>` (`rx_dma_pkt_drop`, `rx_errors`),
* `ip -s link show <iface>` (`dropped`, `errors`),
* `nstat -az | grep -E "Drop|Errors|Retrans"` (Yocto image) for drops inside the network stack.

## Throughput test with iperf3

Run the `iperf3` server on the PC and the client on the board. The client sends by default
(board → PC); `-R` reverses the direction (PC → board):

```
# on the PC
iperf3 -s

# on the board (replace the address with the PC's address on this port's subnet)
iperf3 -c 192.168.10.1 -t 30          # board -> PC
iperf3 -c 192.168.10.1 -t 30 -R       # PC -> board
```

The measured throughput is limited by the board's CPUs (the TCP/IP stack and the single-queue
`xilinx_axienet` MCDMA driver on the Cortex-A72), not by the link. Measured with the Yocto images
and the set-ups listed in [What you need](#what-you-need), single TCP stream:

| Target | Board → PC | PC → board |
|--------|------------|------------|
| 10G (`vck190_fmcp1`, port 0)     | 3.22–3.27 Gbit/s, 0 retransmits | 3.13–3.31 Gbit/s, 110–324 retransmits per 10 s run |
| 25G (`vck190_fmcp1_25g`, port 1) | 3.11 Gbit/s, 0–3 retransmits   | 3.33–3.34 Gbit/s, about 1000 retransmits per 10 s run |

UDP from the PC to the board (`iperf3 -c <board-ip> -u -b <rate>` run *on the PC*, with
`iperf3 -s` on the board):

| Offered rate | 10G: received (loss) | 25G: received (loss) |
|--------------|----------------------|----------------------|
| 500 Mbit/s   | 494 Mbit/s (1.1 %)   | 496 Mbit/s (0.7 %)   |
| 1 Gbit/s     | 989 Mbit/s (1.1 %)   | 986 Mbit/s (1.4 %)   |
| 1.5 Gbit/s   | 1.33 Gbit/s (11 %)   | 1.31 Gbit/s (13 %)   |
| 2 Gbit/s     | 1.61 Gbit/s (13 %)   | 1.90 Gbit/s (4.9 %)  |

Almost all of the UDP loss is counted by the network stack as `UdpRcvbufErrors` (the receiving
`iperf3` process does not empty its socket buffer fast enough), not by the hardware counters.
`ping`, the board's RJ45 port and the loopback self-test are unaffected.

That the link layer itself runs at full line rate is shown by the
[loopback self-test](#loopback-self-test), which moves full-size frames through the MRMAC and the
MCDMA with zero errors. Designs that need sustained line-rate traffic keep the bulk datapath in
the fabric (processing at the MRMAC client interface, in the PL or AI Engines) and pass only
low-volume traffic to Linux.

### Known limit: residual RX frame drops under full-rate TCP

With a single TCP stream from the PC to the board, a small number of received frames are dropped
whole and recovered by TCP retransmission:

* **25G target:** about 88 frames per second are dropped by the RX frame FIFO (counted in
  `GPIO2_DATA[31:8]` of the port; `rx_dma_pkt_drop` stays at 0). In a 30 s run at 3.33 Gbit/s
  this was about 2,650 FIFO drops and about 2,860 TCP retransmits. Raising the RX ring to 4096
  descriptors (`ethtool -G eth1 rx 4096`) did not remove them.
* **10G target:** no FIFO drops; about 170 frames per 30 s run were dropped by the MCDMA for lack
  of a free descriptor (`rx_dma_pkt_drop`), matching the TCP retransmits.

The MRMAC RX client cannot be paused, and at 25 Gbit/s the 64 KB frame FIFO covers a stall of the
DMA path of only about 21 µs. Every dropped frame is counted and none is passed on corrupted or
truncated; the MAC error counters and `rx_errors` stay at 0. Board → PC traffic is not affected.

## Loopback self-test

The image includes a self-test, `mrmac-loopback-test`, that checks a port's full datapath
(MRMAC ↔ AXIS adapter ↔ MCDMA ↔ DDR) without a link partner. Plug an **SFP28 passive loopback
module** into the port under test, then run the test as root:

```
sudo mrmac-loopback-test eth0
```

Usage: `mrmac-loopback-test [iface] [count] [pkt_size]` (defaults: `eth0`, 1000000 frames, 1500
bytes). The script uses the kernel `pktgen` module to send frames out of the interface to its own
MAC address; they loop back through the module and are received again. It then checks that the
received frame count matches the transmitted count (within 5 %), that the frames arrive
full-size, and that there are no RX errors. A passing run ends like this:

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

followed by the non-zero `ethtool -S` counters of the interface. The script's exit code does not
reflect the result; judge it by the `VERDICT` line. Repeat for the other ports with a loopback
module in their slots (`mrmac-loopback-test eth1`, …).

## Other checks

* **GT reference clock.** The Si5328 on the FMC must output 322.265625 MHz:
  ```
  sudo cat /sys/kernel/debug/clk/clk_summary | grep clk0
  ```
* **GT reset done.** Bits `[1:0]` of each port's `GPIO2_DATA` must read `11` (see
  [Registers and counters](registers)). A kernel message `GT TX Reset Done not achieved` means the
  GT lane did not come out of reset — see [Troubleshooting](troubleshooting).
* **Board RJ45.** The board's own Ethernet ports (`end0`, `end1`) run at 1 Gbit/s and are useful
  for SSH while the SFP28 ports are under test.

[Quad SFP28 FMC]: https://docs.opsero.com/op081/datasheet/overview/
