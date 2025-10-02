#!/bin/bash
echo "--- Running Icinga Agent Setup for kafka1.external.tpf-i-ost-test.e21x.de ---"

# Stop Icinga2 if running to prevent issues
systemctl stop icinga2

# Run the node setup command
icinga2 node setup \
--ticket 3b1142961ae597e3624cdb48844c67b33f7ed7f8 \
--listen 0.0.0.0,5665 \
--cn kafka1.external.tpf-i-ost-test.e21x.de \
--zone kafka1.external.tpf-i-ost-test.e21x.de \
--endpoint deployment.external.tpf-i-noo-test.e21x.de,172.29.36.50,5665 \
--parent_zone master \
--parent_host deployment.external.tpf-i-noo-test.e21x.de \
--trustedcert /var/lib/icinga2/certs/trusted-parent.crt \
--accept-config \
--accept-commands \
--disable-confd > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Node setup command completed successfully."
else
    echo "Node setup command failed. Please check the output above."
    exit 1
fi
