FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://bsp.cfg"
KERNEL_FEATURES:append = " bsp.cfg"

# Quad SFP28 FMC (MRMAC): MRMAC has no PHY/phylink and no link-change IRQ, so the stock
# axienet driver only checks RX block lock once at open() and fails if the link
# isn't already up (needs a manual "ip link" bounce; never recovers if the peer
# comes up later). Add a 1 Hz carrier monitor that drives netdev carrier from
# block-lock so the link comes up automatically whenever both ends are lasing.
SRC_URI:append = " file://0002-net-axienet-mrmac-carrier-link-monitor.patch"

# MRMAC RX has no backpressure: the MCDMA S2MM drops whole frames whenever the
# RX descriptor ring is empty (measured: TCP retransmits /200 at 10G with 1024
# instead of 128 RX descriptors). Default MRMAC ports to 1024 RX descriptors
# ("ethtool -g"), and show the MCDMA S2MM drop count as "rx_dma_pkt_drop" in
# "ethtool -S". Same patches as the other BSP (Yocto/PetaLinux).
SRC_URI:append = " \
    file://0003-net-axienet-default-to-1024-RX-descriptors-on-MRMAC-.patch \
    file://0004-net-axienet-report-the-MCDMA-S2MM-packet-drop-count-.patch \
"
