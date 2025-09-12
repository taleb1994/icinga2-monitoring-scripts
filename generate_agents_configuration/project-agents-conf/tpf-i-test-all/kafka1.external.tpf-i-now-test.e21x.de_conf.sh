#!/bin/bash
echo "--- Running Icinga Agent Setup for kafka1.external.tpf-i-now-test.e21x.de ---"

# Stop Icinga2 if running to prevent issues
systemctl stop icinga2

# Run the node setup command
icinga2 node setup \
--ticket 89fadedf91a3c5f7b798ebef8b49d0ad2fe5c3b4 \
--listen 0.0.0.0,5665 \
--cn kafka1.external.tpf-i-now-test.e21x.de \
--zone kafka1.external.tpf-i-now-test.e21x.de \
--endpoint "deployment.external.tpf-i-noo-test.e21x.de,172.29.36.50" \
--parent_zone master \
--parent_host "deployment.external.tpf-i-noo-test.e21x.de" \
--trustedcert "/var/lib/icinga2/certs/trusted-parent.crt" \
--accept-config \
--accept-commands \
--disable-confd

if [ $? -eq 0 ]; then
    echo "Node setup command completed successfully."
else
    echo "Node setup command failed. Please check the output above."
    exit 1
fi
