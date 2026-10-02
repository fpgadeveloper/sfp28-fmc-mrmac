# Troubleshooting

## Build failures

### PetaLinux build fails with `bitbake petalinux-image-minimal failed` and sstate fetch errors

If a `./build.sh petalinux --target <target>` run ends with errors like

```
ERROR: <package>-<ver>-r0 do_..._setscene: Fetcher failure: Unable to find file file://.../sstate:...
[ERROR] Command bitbake petalinux-image-minimal failed
```

the actual build is not broken. These `_setscene` errors come from
bitbake trying to pull prebuilt artifacts from the public Xilinx
sstate-cache mirror, which occasionally returns 404 for individual
packages. Bitbake falls back to building those packages locally and
succeeds, but still exits non-zero because of the failed fetches —
so the build runner stops before the `petalinux-package` step that
produces `BOOT.BIN`.

**Fix: just re-run the same command.** The second attempt finds the
missing packages in the local sstate cache (populated by the first
run) and completes cleanly, producing `BOOT.BIN`. The reference
design itself is fine; this is a transient issue with the public
mirror.

### General build issues

Check the following if the project fails to build or generate a bitstream:

1. **Are you using the correct version of Vivado for this version of the repository?**   
   This design is built for Vivado/Vitis/PetaLinux 2025.2. `build.tcl` checks the installed
   Vivado version and refuses to build with any other version. If you are using a different
   version of the tools, refer to the
   [release tags](https://github.com/fpgadeveloper/sfp28-fmc-mrmac/tags) to find a matching
   commit of the repository.

2. **Do you have the MRMAC license?**   
   The Versal Integrated MRMAC requires a (free, no-cost) license to generate a bitstream. If the
   implementation fails at device-image generation with a licensing error, obtain the MRMAC
   license from the AMD Xilinx Licensing site.

3. **Did you correctly follow the build instructions?**   
   Please check the build instructions carefully as you may have missed a step.

4. **Did you copy/clone the repo into a short directory structure?**   
   Windows doesn't cope well with long directory structures, so copy/clone the repo into a short
   directory structure such as `C:\projects\`. When working in long directory structures, you can
   get errors relating to missing files.

## Yocto SD card does not boot

* **Nothing on the UART after power-on, or the BootROM reports no boot image.** `BOOT.BIN` is
  missing from the first partition of the card. The Yocto disk image (`rootfs.wic.xz`) does not
  contain it; copy it onto the first (FAT) partition after flashing — see
  [Prepare the SD card](yocto.md#prepare-the-sd-card).
* **The boot stops at the U-Boot prompt** (`Scanning mmc 0:1...` and no systemd-boot menu). The
  systemd-boot loader is missing: copy `BOOTAA64.EFI` (from the Yocto zip in `bootimages/`) to
  `EFI/BOOT/` on the first partition.
* **The board does not boot from SD at all.** Check the boot-mode switch: VCK190 SW1 = 1000
  (1=ON,2=OFF,3=OFF,4=OFF).

## Linux / hardware issues

These apply to both the PetaLinux and the Yocto images. The MRMAC bring-up messages are in the
kernel log. The single most useful diagnostic is:

```
dmesg | grep -iE "mrmac|axienet|si53|sfp|reset done"
```

A healthy port prints `MRMAC setup at 10000 (link monitored)` (`25000` on the `_25g` targets),
and — with a link partner connected — `MRMAC link up at 10000 (0 recovery resets)`. The
messages are explained in
[Testing the design](testing.md#link-bring-up-and-the-link-monitor).

### A connected port never reports `MRMAC link up`

A port that cannot achieve block lock does not fail its open — the link monitor (see the
*Modifications layered on the stock BSP* section of [advanced](advanced)) brings the interface
up with carrier *off* and keeps re-attempting the reset in the background. You will see

```
xilinx_axienet 80010000.mrmac eth0: MRMAC setup at 10000 (link monitored)
xilinx_axienet 80010000.mrmac eth0: MRMAC link still down after 4 recovery resets (rx_sts 0x180 blk_lck 0x0 vld_ctrl 0x0)
```

but never a matching `MRMAC link up`, and `ip -br link` shows the port `NO-CARRIER`. (Ports
with nothing connected print the same `still down` lines; that is expected.) The port will come
up on its own the moment the cause below is resolved (no reboot needed). Check, in order:

1. **Is there a valid link at the right rate?** For a standalone test, plug an **SFP28 passive
   loopback module** into the port. For a live link, the partner must run at the same fixed rate
   as the target (10G for `vck190_fmcp1`, 25G for `vck190_fmcp1_25g`) — and the **module itself
   must support that rate**: a 25G-only SFP28 module (e.g. a single-rate SFP-25G-SR) will never
   link on the 10G target, because its CDR cannot lock at the 10.3125 Gb/s line rate. The
   module's diagnostics (`RX power` etc.) still read healthy in this case; only a 10G or
   dual-rate 10/25G module will work on `vck190_fmcp1`.
2. **Is the partner configured to match?** The MRMAC ports run with **no auto-negotiation and no
   FEC**. A NIC or switch port left in auto-negotiate mode, or configured for FEC (e.g. RS-FEC on
   a 25G port), will not link up against them — set the partner to the fixed rate with
   auto-negotiation off and FEC off (on a Linux host, `sudo ethtool -s <iface> autoneg off speed
   25000` and `sudo ethtool --set-fec <iface> encoding off`). Check with
   `ethtool --show-fec <iface>`: some NICs re-enable FEC automatically when a 25G module is
   inserted or the link is reset. An FEC mismatch typically shows as a link that is up on
   neither side, although the optical power readings are fine.
3. **Is the Si5328 programmed?** `cat /sys/kernel/debug/clk/clk_summary | grep clk0` should show
   the GT reference clock at `322265625`. If it is wrong or zero, the Si5328 device tree node or
   the `clk-si5324` driver is not programming the clock.
4. **Is a module actually detected?** The kernel SFP framework identifies each module at boot
   and logs insertions (`dmesg | grep sfp`), and the slot's LEDs are off when no module is
   present. A module seated in the wrong slot is a common cause — port N is SFP28 slot N. If
   the module is present but not identified (no `module <vendor> <part>` line), re-seat it; if
   *no* SFP cage or FMC I2C device responds at all, see
   [VADJ](#a-port-reports-gt-tx-reset-done-not-achieved) below.
5. If you have modified the block design, verify the per-lane GT user-clocking is intact (see
   the *Per-lane user clocking* part of [advanced](advanced)) and that the MRMAC configuration
   preset survived your changes (see *MRMAC configuration — order matters*).

To diagnose at the register level, read the port's MRMAC status registers directly. Port *N*'s
register page is at `0x80010000 + N*0x1000`; the status registers are **write-1-to-clear**, so
write all-ones first, then read the live state. For port 0 (as root):

```
# devmem 0x80010754 32 0xffffffff; sleep 0.5; devmem 0x80010754
0x00000000
# devmem 0x80010744 32 0xffffffff; sleep 0.5; devmem 0x80010744
0x00000180
```

Register `0x754` bit 0 is **RX block lock** (1 = locked). Register `0x744` is `STAT_RX_STATUS`:
bit 0 = RX status good, bit 7 = local fault, bit 8 = *internal* local fault, bit 9 = *received*
local fault. The `0x180` example above (internal local fault, no received fault) means our own
RX cannot make sense of the incoming bitstream — a rate mismatch (item 1) or a clocking problem
(item 5) — whereas bit 9 set means the *far end* is reporting a fault to us. The link monitor
logs the same three registers (`rx_sts` = `0x744`, `blk_lck` = `0x754`, `vld_ctrl` = `0x7B8`) in
its `link down` and `still down` messages, so the kernel log usually already tells you. Note that
while a port is down, the link monitor resets it every 500 ms and clears these registers, so
repeat the manual reads a few times and judge by the pattern. In the Yocto image use
`devmem2 <addr> w 0xffffffff` and `devmem2 <addr> w` instead of `devmem`.

### A port reports `GT TX Reset Done not achieved`

```
xilinx_axienet 80010000.mrmac eth0: GT TX Reset Done not achieved (Status=0x0)
```

The port's GT lane never came out of reset, which almost always means the GT reference clock is
missing. The Si5328 on the FMC sources the reference clock (GBTCLK0) for all four lanes — check
that the `clk-si5324` driver probed and programmed it (item 3 above), and that the FMC is seated
on the correct connector (FMCP1).

The most common reason for a missing reference clock is that the **FMC's VADJ supply was off**
when Linux started: then the FMC's I2C mux, Si5328 and SFP cages do not respond either (no
`si5328 probe successful`, no `module …` lines from `sfp sfp-ethN`). On the VCK190, U-Boot
switches VADJ on before it boots Linux — in the Yocto image the `Setting bus to 1` line just
before the boot is that step, in the PetaLinux image it is the `vadj_1v5_en` command of the boot
command. If you replaced the U-Boot environment or boot command, or boot the kernel by some other
means, make sure VADJ is enabled first. The bare-metal echo server programs VADJ itself.

### A port comes up at the wrong rate

```
xilinx_axienet 80010000.mrmac eth0: MRMAC setup at 25000
```

on a 10G build (or vice versa) means the device tree that was built into your image does not
match the bitstream: the `max-speed` property set by the port-config overlay
(`ports-versal-0123` = 10000, `ports-versal-0123-25g` = 25000) selects the rate the driver
programs. The hardware rate is fixed by the bitstream (the MRMAC preset and GT line rate), so a
mismatched device tree leaves the port dead. Rebuild the PetaLinux project for the correct
target.

### A port fails to probe with `-EBUSY` / `iormeap failed for the dma`

```
xilinx_axienet 80050000.axi_mcdma: error -16: can't request region ... iormeap failed for the dma
```

The standalone `xilinx_dma` dmaengine driver grabbed the MCDMA register region before
`xilinx_axienet` could. The `port-config.dtsi` overlay works around this by overriding the MCDMA
node's `compatible` to `"xlnx,eth-dma"` (see the *Modifications layered on the stock BSP* section
of [advanced](advanced)). If you hit this, that override is
missing from your device tree.

### Low throughput or many TCP retransmits towards the board

The throughput of an MRMAC port under Linux is limited by the CPU to roughly 3 to 3.3 Gbit/s
per TCP stream (see [Testing the design](testing.md#throughput-test-with-iperf3)). If you see far
less, or very many retransmits, find out where frames are lost:

1. Read the port's RX drop counters (`GPIO2_DATA` of its GT-control GPIO) before and after a
   test — see [Registers and counters](registers). Overflow drops mean the DMA path did not keep
   up with the line rate; MAC-error drops point at the link (cabling, optics, FEC mismatch).
2. Check `rx_dma_pkt_drop` in `ethtool -S <iface>`: these are frames dropped by the MCDMA for
   lack of an RX descriptor. Check that the RX ring is 1024 (`ethtool -g <iface>`).
3. Check the network stack: `nstat -az | grep -E "Drop|RcvbufErrors"` (Yocto image). UDP
   loss in `UdpRcvbufErrors` means the receiving application is too slow, not the hardware.

A small residual drop rate under sustained full-rate TCP towards the board is a known limit of
the design (about 88 frames/s at 25G, counted as FIFO overflow drops) — see
[Known limit](testing.md#known-limit-residual-rx-frame-drops-under-full-rate-tcp). TCP recovers
these frames; no corrupted frames are delivered.

### A port goes down under heavy receive traffic and does not come back

With the current link monitor a port recovers on its own: a `MRMAC link down` message under load
is followed by `MRMAC link up ... (<n> recovery resets)` once the link is usable again. If an
image built from an older version of this repository leaves the port down until
`ip link set <iface> down; ip link set <iface> up`, rebuild it from the current version.

### Ports not working under Linux (link is up)

1. **Check the interface-to-port assignment for your design.**   
   The four MRMAC ports appear as `eth0` (port 0) through `eth3` (port 3); the VCK190 built-in
   GEMs appear as `end0`/`end1` — in both the PetaLinux and the Yocto image. Use `ip -br link`
   and `ethtool -i <name>` to confirm. The full mapping is documented in
   [Testing the design](testing.md#network-interfaces).

2. **Each port must be assigned to a different subnet.**   
   If you assign `eth0` to 192.168.1.10, then `eth1` must be on a different subnet (e.g.
   192.168.2.10). Multiple ports managed under Linux on the same subnet will not work.

3. **Use the bundled self-test to isolate link vs. host problems.**   
   `mrmac-loopback-test eth0` (with a passive loopback module) validates the entire MRMAC → MCDMA
   → DDR datapath independently of any link partner. If the self-test passes but traffic to a real
   peer does not, the problem is in the link or the peer, not the FPGA design.

## Echo server issues

1. **No response to ping.** The echo server's IP addresses are fixed: port N answers on
   `192.168.<(N+1)*10>.10` (port 0 = `192.168.10.10`, port 1 = `192.168.20.10`, etc.). The PC's
   interface must have a static address on the *matching* subnet (e.g. `192.168.10.20/24` to reach
   port 0) and its NIC must run at the target's fixed rate with auto-negotiation and FEC off,
   exactly as for the Linux case above. Watch the UART output:
   the application prints `port N: link UP` when the port acquires block lock, and re-issues the
   port reset once per second while it is down.
2. **telnet does not connect.** The echo server is a raw-Ethernet application with no TCP stack —
   it answers ARP, ICMP ping and UDP only. Use `echo hello | nc -u 192.168.10.10 7` instead (any
   UDP port number works).
