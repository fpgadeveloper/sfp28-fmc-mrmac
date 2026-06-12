SUMMARY = "MRMAC port loopback self-test script"
DESCRIPTION = "Installs /usr/bin/mrmac-loopback-test, a pktgen-based loopback \
test for an MRMAC port (run as root with a passive SFP28 loopback fitted)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://mrmac-loopback-test"

S = "${WORKDIR}"

do_install() {
	install -d ${D}${bindir}
	install -m 0755 ${WORKDIR}/mrmac-loopback-test ${D}${bindir}/mrmac-loopback-test
}

FILES:${PN} = "${bindir}/mrmac-loopback-test"

# Runtime helpers the script can use (ethtool is optional - the script guards
# for it - but install it so the detailed MAC counters are available).
RDEPENDS:${PN} += "ethtool"
