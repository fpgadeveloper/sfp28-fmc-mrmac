# Stand-alone Echo Server

The repository includes a bare-metal test application that runs an echo server on **all four
SFP28 ports at once**. Note that this is *not* the usual lwIP echo-server template that ships
with Vitis — lwIP has no adapter for the Versal MRMAC — so this design implements a small
**raw-Ethernet** echo server instead (`Vitis/common/src/main.c`). Per port it answers:

* **ARP** requests for the port's IP address
* **ICMP** echo requests (ping)
* **UDP** datagrams to *any* port number: the payload is echoed back to the sender

Each port has its own MAC address and lives on its own subnet:

| SFP28 port | MAC address         | IP address         |
|------------|---------------------|--------------------|
| 0          | `00:0a:35:00:0e:00` | `192.168.10.10/24` |
| 1          | `00:0a:35:00:0e:01` | `192.168.20.10/24` |
| 2          | `00:0a:35:00:0e:02` | `192.168.30.10/24` |
| 3          | `00:0a:35:00:0e:03` | `192.168.40.10/24` |

On startup the application performs the full hardware bring-up itself: it programs the FMC
VADJ rail (1.5V, via `Vitis/common/src/vadj.c`), programs the Si5328 on the FMC to output the
322.265625 MHz GT reference clock (`si5328.c`, over the I2C mux), resets each port's GT lane
through its GT-control GPIO, configures each MRMAC port for the target's line rate (`mrmac.c`),
sets up the MCDMA buffer-descriptor rings, and then polls the four MCDMA RX rings in a loop.
Roughly once per second it re-checks link state; while a port has no RX block lock it re-issues
that port's MRMAC reset to re-attempt lock — the same strategy as the design's Linux carrier
monitor (see [advanced](advanced)).

## Building the Vitis workspace

To build the Vitis workspace and the echo server application, follow the instructions
appropriate for your operating system:

* **Windows**: Follow the [build instructions for Windows users](/build_instructions.md#windows-users)
* **Linux**: Follow the [build instructions for Linux users](/build_instructions.md#linux-users)

In short, from the `Vitis` directory:

```
make workspace TARGET=<target>
```

builds the workspace and the application; `make bootfile TARGET=<target>` additionally packages
a `BOOT.BIN` into `Vitis/boot/<target>/`. The echo server is also built and packaged as the
"standalone" boot image when you run `make bootimage TARGET=<target>` at the repo root.

## Run the application

You must have followed the build instructions before you can run the application.

1. Launch the Xilinx Vitis GUI.
2. When asked to select the workspace path, select the `Vitis/<target>_workspace` directory.
3. Power up your hardware platform and ensure that the JTAG is connected properly.
4. In the Vitis Explorer panel, double-click on the System project that you want to run -
   this will reveal the application contained in the project. The System project will have 
   the postfix "_system".
5. Now right click on the application "echo_server" then navigate the
   drop down menu to **Run As->Launch on Hardware (Single Application Debug (GDB)).**

Alternatively, copy the `BOOT.BIN` from `Vitis/boot/<target>/` (or from the standalone zip in
`bootimages/`) to an SD card and boot the board from SD.

The run configuration will first program the device, then load and run the application. The UART
output (115200 baud) of a `vck190_fmcp1` run appears as follows:

```
-------------------------------------------------
Quad SFP28 FMC (MRMAC) echo server - VCK190
Line rate: 10G per port
-------------------------------------------------
VADJ enabled (1.5V)
Si5328 programmed: GT refclk 322.265625 MHz
port 0: MAC 00:0a:35:00:0e:00  IP 192.168.10.10
port 1: MAC 00:0a:35:00:0e:01  IP 192.168.20.10
port 2: MAC 00:0a:35:00:0e:02  IP 192.168.30.10
port 3: MAC 00:0a:35:00:0e:03  IP 192.168.40.10
Echo server running: answers ARP, ICMP ping and UDP echo

port 0: link UP
```

A `port N: link UP` line is printed as each connected port acquires RX block lock; `link DOWN`
is printed if a link is subsequently lost (e.g. cable unplugged).

## Example usage

Connect an SFP28 port to a PC's 10G/25G NIC (matching the target's line rate) and configure the
PC's interface with a fixed IP address on the matching subnet — for port 0, for example,
`192.168.10.20/24`. The IP addresses are fixed (there is no DHCP client in the application).

### Ping a port

```
$ ping 192.168.10.10
PING 192.168.10.10 (192.168.10.10) 56(84) bytes of data.
64 bytes from 192.168.10.10: icmp_seq=1 ttl=64 time=0.06 ms
```

This pings port 0; use `192.168.20.10`, `192.168.30.10` or `192.168.40.10` for ports 1, 2 and 3.

### UDP echo

The echo server echoes UDP datagrams sent to **any** port number back to the sender. Using
netcat from a PC connected to SFP28 port 1:

```
$ echo hello | nc -u 192.168.20.10 7
hello
```

```{note}
The echo server answers ARP, ICMP ping and UDP only. There is no TCP stack, so a telnet
connection (as used with the lwIP echo servers of our other reference designs) will not work.
```
