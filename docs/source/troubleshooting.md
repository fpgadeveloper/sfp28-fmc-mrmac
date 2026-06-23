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

## PetaLinux / hardware issues

The MRMAC bring-up messages are in the kernel log. The single most useful diagnostic is:

```
dmesg | grep -iE "mrmac|axienet|si53|block lock|link|reset done"
```

A healthy port prints `MRMAC setup at 10000 (link monitored)` (`25000` on the `_25g` targets),
and — with a link partner connected — `MRMAC link up at 10000`.

### A connected port never reports `MRMAC link up`

A port that cannot achieve block lock no longer fails its open or spams the log — the carrier
monitor (see the *Modifications layered on the stock BSP* section of [advanced](advanced)) brings
the interface up with carrier *off* and keeps re-attempting the reset in the background. You will
see

```
xilinx_axienet 80010000.mrmac eth0: MRMAC setup at 10000 (link monitored)
```

but never a matching `MRMAC link up`, and `ip -br link` shows the port `NO-CARRIER`. The port
will come up on its own the moment the cause below is resolved (no reboot needed). Check, in
order:

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
   25000` and `sudo ethtool --set-fec <iface> encoding off`).
3. **Is the Si5328 programmed?** `cat /sys/kernel/debug/clk/clk_summary | grep clk0` should show
   the GT reference clock at `322265625`. If it is wrong or zero, the Si5328 device tree node or
   the `clk-si5324` driver is not programming the clock.
4. **Is a module actually detected?** The kernel SFP framework logs module insertion (`dmesg |
   grep sfp`), and the slot's LEDs are off when no module is present. A module seated in the
   wrong slot is a common cause — port N is SFP28 slot N.
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
(item 5) — whereas bit 9 set means the *far end* is reporting a fault to us. Note that while a
port is down, the carrier monitor resets it once per second, so repeat the reads a few times and
judge by the pattern.

### A port reports `GT TX Reset Done not achieved`

```
xilinx_axienet 80010000.mrmac eth0: GT TX Reset Done not achieved (Status=0x0)
```

The port's GT lane never came out of reset, which almost always means the GT reference clock is
missing. The Si5328 on the FMC sources the reference clock (GBTCLK0) for all four lanes — check
that the `clk-si5324` driver probed and programmed it (item 3 above), and that the FMC is seated
on the correct connector (FMCP1).

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

### Ports not working under Linux (link is up)

1. **Check the interface-to-port assignment for your design.**   
   The four MRMAC ports appear as `eth0` (port 0) through `eth3` (port 3); the VCK190 built-in
   GEMs appear as `end0`/`end1`. Use `ip -br link` and `ethtool -i <name>` to confirm. The full
   mapping is documented in the *Port configurations* section of [petalinux](petalinux).

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
   exactly as for the PetaLinux case above. Watch the UART output:
   the application prints `port N: link UP` when the port acquires block lock, and re-issues the
   port reset once per second while it is down.
2. **telnet does not connect.** The echo server is a raw-Ethernet application with no TCP stack —
   it answers ARP, ICMP ping and UDP only. Use `echo hello | nc -u 192.168.10.10 7` instead (any
   UDP port number works).
