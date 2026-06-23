# Build instructions

## Source code

The source code for the reference designs is managed on this Github repository:

* [https://github.com/fpgadeveloper/sfp28-fmc-mrmac](https://github.com/fpgadeveloper/sfp28-fmc-mrmac)

To get the code, you can follow the link and use the **Download ZIP** option, or you can clone it
using this command:
```
git clone https://github.com/fpgadeveloper/sfp28-fmc-mrmac.git
```

## License requirements

The designs use the Versal Integrated MRMAC, which requires a (free, no-cost) license to generate
a bitstream. The license can be obtained from the AMD Xilinx Licensing site. The VCK190 target
also requires the Vivado *Enterprise* Edition (a 30-day evaluation license is available from the
AMD Xilinx Licensing site).

Additionally, some designs use IP cores that are licensed separately from the Vivado edition itself (for example: MRMAC, TEMAC, XXV Ethernet). The **IP License** column in the tables below indicates the designs that require such a license to generate a bitstream; evaluation licenses are generally available from AMD for testing.

## Target designs

This repo contains designs that target the supported development board(s) and their FMC
connectors. The table below lists the target design name, the link speed, the SFP28 ports
supported by the design and the FMC connector on which to connect the mezzanine card.

{% for linkspeed in ["10","25"] %}
### {{ linkspeed }}G designs

These designs drive each SFP28 port as an independent {{ linkspeed }}GbE channel of the MRMAC.

| Target board        | Target design     | Ports   | FMC Slot    | Vivado<br> Edition | IP<br>License |
|---------------------|-------------------|---------|-------------|-----|-----|
{% for design in data.designs %}{% if design.linkspeed == linkspeed and design.publish %}| [{{ design.board }}]({{ design.link }}) | `{{ design.label }}` | {{ design.lanes | length }}x | {{ design.connector }} | {{ "Enterprise" if design.license else "Standard 🆓" }} | {{ "Required" if design.ip_license else "-" }} |
{% endif %}{% endfor %}
{% endfor %}

Notes:

1. The Vivado Edition column indicates which designs are supported by the Vivado *Standard*
   Edition, the FREE edition which can be used without a license. Vivado *Enterprise* Edition
   requires a license, however a 30-day evaluation license is available from the AMD Xilinx
   Licensing site.
2. Regardless of the Vivado Edition, the Versal Integrated MRMAC requires a (free) license to
   generate a bitstream.
3. All of the 25G designs have the `_25g` postfix in the target label. The 10G and 25G variants
   build the same architecture; they differ only in the MRMAC configuration preset, the active
   client data width and the SFP28 rate-select pin levels.

## Cross-platform build runner

All builds are driven by the `build.py` runner at the root of the repository,
on **both Windows and Linux** — the build instructions are the same for the
two operating systems. Each command builds whatever it depends on
automatically, skips anything that is already built, and locates the AMD
tools itself, so there is no need to source the settings scripts beforehand.

On Linux and on Windows (git bash), commands are run with the `build.sh`
shim, which finds a suitable Python 3 automatically (including the
interpreter bundled with the AMD tools). Windows users who prefer not to
use git bash can run the same commands from Command Prompt or PowerShell
using `build.bat` instead — the commands and arguments are otherwise
identical, for example `build.bat xsa --target <target>`.

To see the available targets and the state of a build:

```
./build.sh list                       # list the targets and their attributes
./build.sh status --target <target>   # show the per-stage artifact state
./build.sh clean --target <target>    # delete a target's generated outputs
```

```{note}
The embedded Linux images (PetaLinux) can only be built on a
native Linux machine; everything else builds on Windows too. On Windows, the
runner refuses the Linux-only stages up front and prints the exact command
to run on the Linux machine. For Versal targets on Windows, the runner also
verifies that the project path fits within the 260-character Windows path
limit before building, and explains the `subst` workaround if it does not.
```

```{attention}
The legacy `make` interface described in previous versions of
this documentation still works on Linux — each Makefile is now a thin
wrapper around `build.sh` — but it is deprecated and will be removed at the
next version update.
```

### Build Vivado project

This single command creates the Vivado project, generates the bitstream and
exports the hardware to an XSA file:

```
./build.sh xsa --target <target>
```

Valid targets are:
{% for design in data.designs if design.publish %} `{{ design.label }}`{{ ", " if not loop.last else "." }} {% endfor %}

If you want the Vivado project and block design without generating a
bitstream — for example, to explore or modify the design in the Vivado GUI —
run `./build.sh project --target <target>` instead, then open the project
from `Vivado/<target>/`.

### Build Vitis workspace

This creates the Vitis workspace and compiles the bare-metal
[echo server](echo_server), producing the boot file (`BOOT.BIN`). The Vivado
XSA is built first if it does not already exist:

```
./build.sh standalone --target <target>
```

Valid targets for the standalone application are:
{% for design in data.designs if design.baremetal and design.publish %} `{{ design.label }}`{{ ", " if not loop.last else "." }} {% endfor %}

The workspace is created in `Vitis/<target>_workspace` and the boot files
are gathered in `Vitis/boot/<target>/`.

### Build PetaLinux

The PetaLinux build requires a native Linux machine (one of the [supported
Linux distributions]) with PetaLinux Tools 2025.2 installed. The runner
locates and sources the PetaLinux `settings.sh` itself, and builds the
Vivado XSA first if it does not already exist:

```
./build.sh petalinux --target <target>
```

Valid targets for PetaLinux are:
{% for design in data.designs if design.petalinux and design.publish %} `{{ design.label }}`{{ ", " if not loop.last else "." }} {% endfor %}

The output products are written to `PetaLinux/<target>/images/linux/`.

#### PetaLinux offline build

If you need to build the PetaLinux project offline (without an internet
connection), you can follow these instructions.

1. Download the sstate-cache artefacts from the Xilinx downloads site (the
   same page where you downloaded PetaLinux tools). For this Versal design
   you need:
   * aarch64 sstate-cache
   * Downloads (for all designs)
2. Extract the contents of those files to a single location on your hard
   drive, for this example we'll say `/home/user/petalinux-sstate`. That
   should leave you with the following directory structure:
   ```
   /home/user/petalinux-sstate
                             +---  aarch64
                             +---  downloads
   ```
3. Create a text file called `offline.txt` in the `PetaLinux` directory of
   the project repository. The file should contain a single line of text
   specifying the path where you extracted the sstate-cache files. In this
   example, the contents of the file would be:
   ```
   /home/user/petalinux-sstate
   ```
   It is important that the file contain only one line and that the path is
   written with NO TRAILING FORWARD SLASH.

The PetaLinux build will then be configured for offline build.

### Build everything

This builds everything that the target supports — the Vivado project and XSA,
the standalone application and the PetaLinux image — and gathers the boot
images into `bootimages/*.zip`:

```
./build.sh all --target <target>
./build.sh all --target all      # every target in the repo
```

On Windows, `all` builds everything that the host can build and reports the
Linux-only stages as `BLOCKED` rather than failing.

[supported Linux distributions]: https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Setting-Up-Your-Environment
