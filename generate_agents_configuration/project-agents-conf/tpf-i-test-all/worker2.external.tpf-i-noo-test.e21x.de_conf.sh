#!/bin/bash
echo "--- Running Icinga Agent Setup for worker2.external.tpf-i-noo-test.e21x.de ---"

# Stop Icinga2 if running to prevent issues
systemctl stop icinga2

# Run the node setup command
icinga2 node setup \
--ticket ab6c16870e6c975ff54994a25051e145966529c0 \
--listen 0.0.0.0,5665 \
--cn worker2.external.tpf-i-noo-test.e21x.de \
--zone worker2.external.tpf-i-noo-test.e21x.de \
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
