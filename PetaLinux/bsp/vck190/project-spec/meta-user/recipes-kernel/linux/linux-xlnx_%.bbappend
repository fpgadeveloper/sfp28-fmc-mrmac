FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://bsp.cfg"
KERNEL_FEATURES:append = " bsp.cfg"

# Quad SFP28 FMC (MRMAC): MRMAC has no PHY/phylink and no link-change IRQ, so the stock
# axienet driver only checks RX block lock once at open() and fails if the link
# isn't already up (needs a manual "ip link" bounce; never recovers if the peer
# comes up later). Add a 1 Hz carrier monitor that drives netdev carrier from
# block-lock so the link comes up automatically whenever both ends are lasing.
SRC_URI:append = " file://0002-net-axienet-mrmac-carrier-link-monitor.patch"
