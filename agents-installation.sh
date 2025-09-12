#icinga on agents

#On k8s-master
kubectl get nodes -o wide | awk '{print $1,$6}'

#On all icinga-agents
apt update -y && apt list --upgradable

DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt -y install apt-transport-https wget gnupg

wget -O - https://packages.icinga.com/icinga.key | gpg --dearmor -o /usr/share/keyrings/icinga-archive-keyring.gpg

. /etc/os-release; if [ ! -z ${UBUNTU_CODENAME+x} ]; then DIST="${UBUNTU_CODENAME}"; else DIST="$(lsb_release -c| awk '{print $2}')"; fi; \
echo "deb [signed-by=/usr/share/keyrings/icinga-archive-keyring.gpg] https://packages.icinga.com/ubuntu icinga-${DIST} main" > /etc/apt/sources.list.d/${DIST}-icinga.list

echo "deb-src [signed-by=/usr/share/keyrings/icinga-archive-keyring.gpg] https://packages.icinga.com/ubuntu icinga-${DIST} main" >> /etc/apt/sources.list.d/${DIST}-icinga.list

DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt update -y && DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt install icinga2 -y


#On icinga-master. Just one time to copy to all icinga-agents so they can authinticate againt icinga-master
ll /var/lib/icinga2/certs
icinga2 pki save-cert --trustedcert /var/lib/icinga2/certs/trusted-parent.crt --host $(hostname -f)
cat /var/lib/icinga2/certs/trusted-parent.crt

icinga2 pki ticket --cn master1.d.c2vba.heuboe.hbintern


#On all icinga-agents
mkdir -p /var/lib/icinga2/certs && touch /var/lib/icinga2/certs/trusted-parent.crt && chown -R nagios:nagios /var/lib/icinga2/certs && ll /var/lib/icinga2/certs

cat > /var/lib/icinga2/certs/trusted-parent.crt << EOF
-----BEGIN CERTIFICATE-----
MIIFDTCCAvWgAwIBAgIVAL/rgytBJAeNKWL0VziZZVWVo89VMA0GCSqGSIb3DQEB
CwUAMBQxEjAQBgNVBAMMCUljaW5nYSBDQTAeFw0yNTA0MjUwODMyMzBaFw0yNjA1
MjcwODMyMzBaMCwxKjAoBgNVBAMMIWljaW5nYS5tb25pdG9yaW5nLmhldWJvZS5o
YmludGVybjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALnijJ8VUNmP
zJAPcRcCOiw8BFdpLTiPRX3R7ThJBWzCnUJAqKyeKsUMqVSvNPbgUxHL5IW+nOhc
zS/F+zU9NKfqzdlHfK/mtVl4RHXvyCxzc0XToj2FmQsDWYhIgJNxxocGWeS5vUdp
PldJhIvSjCnugaJZ83BQgmTpH/Hoh5NK53gBHsvNspgzCqRs6Fd4ZRE6+YP3qHRy
g2hFQdtdoiNML6KPTD/I9TzEntp7ay+fNlNZ8j2Spd5ikWGgYAVDT0xIb3wUVFSd
0aSKvryZYTXgi/VT3jlxEvmQKBnmJz5lMWm3VZ85Zj2tbL9OZ7sLaXYghPqDyFZ1
1uWPnCUa7K9PrW0wKhpcF4TFJVb2LUjfV6sH0/83qqxWyZwH65MDy00kiM5Vmcfl
8j7ux9Qt6w/bRYW2HBah7Bq4BWCJwRmxwnsp7ZtizLMdVtG48YR1lhBdmFMgZu+X
CD1GrhevF0WW5gIbr4gnDk75ttS2456vXhoiawlmX/K4Yqr2umqZjkFtY3d5lkPz
8J8mBVM3nlpTuUJEndVkeLcC3IGwlkC/tX8TgOIDLQPBLH2SIBvTsKl3AzlHh0U2
4DwVxNdYGZ1fzwXcy5RoFgKW4zKuYh3jiZsW2+GFGxsa9NPya6EaFak9tSF8Glx7
XU0SOa3fqihhKk848QxzlzXAgzkfgsrhAgMBAAGjPjA8MAwGA1UdEwEB/wQCMAAw
LAYDVR0RBCUwI4IhaWNpbmdhLm1vbml0b3JpbmcuaGV1Ym9lLmhiaW50ZXJuMA0G
CSqGSIb3DQEBCwUAA4ICAQBNSX5RWx2KedfqnQPrlUFDX1bUm+o4Jw5yMHFQgU06
0vxUER0WPVnpHGACGqKXriVce0F4aF8wafZ+KNX4EHrzdFiudC5otUzqsl2M4LH6
NnzmevFzgSieo4s/UGq4wcsghE3Xnr83x/2Tiz13dK7eIUc5Ucv4Y+W3OLuptDpH
wp5FD14LE3jwoEOxaFzUmPXl6GGK3UddyjNGGk3Fkh9/D93oWERJn48cNdsbUA3J
gQZaK22U5eAu5wIj82qIoFjwf4x0hh45+GBjFPG/S6emcFBC1J++Pg0ELze1sx9M
6AsfHZxOonrjx3ZoTg0pXs048DsfMUwE8bXcCjajZwxlFDXU9FE3hdpa+GzodlH5
vqCpcUuRabARZ6TlpPcuSMA1MtNOY1X+uTphB1DkLe0IxPi4U/oQD+BZcILJZ6gH
bW8MJARnB+ignFCTaMUdJkGLcA8/9V5J+6iIe+ZxtCWMdvIAoPjazTNutMcRRYXA
b2DcwwVmTbhcnSnvNsfhX1l8nkjj9Wrq42AP40/TiUSeMmkYY0i8X6IJulGZckcO
6ADbYmilV4sewTpnl9HrTp4Sdh91qGPrGe311VKTHGMyM2ck+3CbRuTMOZOaLox1
SmdMFXbk4pgtCk+Cb+ZZn6jjPHXu8HkjjfOd+orDcIQrxVecRIgtrx0+iJY3p7R+
0w==
-----END CERTIFICATE-----
EOF

ll /var/lib/icinga2/certs/trusted-parent.crt && cat /var/lib/icinga2/certs/trusted-parent.crt

icinga2 node setup \
--ticket 98346b93f2c9c125f91eb9709cee9ba1c4d89989 \
--listen 0.0.0.0,5665 \
--cn $(cat /etc/hostname) \
--zone $(cat /etc/hostname) \
--endpoint icinga.monitoring.heuboe.hbintern,192.168.195.100,5665 \
--parent_host icinga.monitoring.heuboe.hbintern \
--parent_zone master \
--trustedcert /var/lib/icinga2/certs/trusted-parent.crt \
--accept-config \
--accept-commands \
--disable-confd

openssl verify -CAfile /var/lib/icinga2/certs/ca.crt /var/lib/icinga2/certs/$(cat /etc/hostname).crt
icinga2 pki verify --cn $(cat /etc/hostname) --cert /var/lib/icinga2/certs/$(cat /etc/hostname).crt

cat /etc/icinga2/zones.conf

echo -e "\n\n//Added BY M.T@HeuBoe at $(date)\ninclude \"conf.d/commands.conf\"" >> /etc/icinga2/icinga2.conf

icinga2 daemon --validate && systemctl restart icinga2 && systemctl status icinga2 && less /var/log/icinga2/icinga2.log && ll /var/lib/icinga2/certs


#On icinga-master. Try first to add agents without this method directly using director and check if you really need to create these extra zones and endpoints
  #This didnt work in compenation with the icingaweb2 director. And there is no reason to put any more effort in this.
nano /etc/icinga2/zones.conf
object Zone "c2vba-d" {
        global = true
}

include_recursive "zones.d", "c2vba-p"
include_recursive "zones.d", "c2vba-d" # You can add as many includes as you want under each other


mkdir -p /etc/icinga2/zones.d/c2vba-d/

# === master1.d.c2vba.heuboe.hbintern.conf ===
cat << EOF > /etc/icinga2/zones.d/c2vba-d/master1.d.c2vba.heuboe.hbintern.conf
//-- Added BY M.T@HeuBoe at $(date)
object Endpoint "master1.d.c2vba.heuboe.hbintern" {
    host = "172.31.246.1"
    port = 5665
    log_duration = 0s
}

object Zone "master1.d.c2vba.heuboe.hbintern" {
    parent = "master"
    endpoints = [ "master1.d.c2vba.heuboe.hbintern" ]
}
EOF

# === worker1.d.c2vba.heuboe.hbintern.conf ===
cat << EOF > /etc/icinga2/zones.d/c2vba-d/worker1.d.c2vba.heuboe.hbintern.conf
//-- Added BY M.T@HeuBoe at $(date)
object Endpoint "worker1.d.c2vba.heuboe.hbintern" {
    host = "172.31.246.11"
    port = 5665
    log_duration = 0s
}

object Zone "worker1.d.c2vba.heuboe.hbintern" {
    parent = "master"
    endpoints = [ "worker1.d.c2vba.heuboe.hbintern" ]
}
EOF

chown -R nagios:nagios /etc/icinga2/zones.d/c2vba-d/


# You have to consider also deleteing all created zonesdirectories from here.
ls -halt /var/lib/icinga2/api/zones/

icingacli director kickstart run && icingacli director config deploy
icinga2 daemon --validate && systemctl restart icinga2.service


# Delete all created endpoints and zones
    # first delete all endpoints using icingaweb2
rm -r /etc/icinga2/zones.d/c2vba-p /var/lib/icinga2/api/zones/c2vba-p /var/lib/icinga2/api/zones/master1.p.c2vba.heuboe.hbintern /var/lib/icinga2/api/zones/worker1.p.c2vba.heuboe.hbintern \
    /var/lib/icinga2/api/zones/worker2.p.c2vba.heuboe.hbintern /var/lib/icinga2/api/zones/worker3.p.c2vba.heuboe.hbintern

icingacli director zone delete c2vba-p
icingacli director zone delete master1.p.c2vba.heuboe.hbintern
icingacli director zone delete worker1.p.c2vba.heuboe.hbintern
icingacli director zone delete worker2.p.c2vba.heuboe.hbintern
icingacli director zone delete worker3.p.c2vba.heuboe.hbintern


================================================================================================================================================================================================================================================================
================================================================================================================================================================================================================================================================

## Install cpu and memory checks

less /etc/icinga2/conf.d/commands.conf

icinga2 daemon --validate
systemctl restart icinga2.service
systemctl restart icinga-director.service

icingacli director kickstart run
icingacli director config deploy



echo "$(stat -c "%U" /etc/icinga2/icinga2.conf) ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$(stat -c "%U" /etc/icinga2/icinga2.conf)-nopasswd
chmod 440 /etc/sudoers.d/$(stat -c "%U" /etc/icinga2/icinga2.conf)-nopasswd

echo -e "\n\n//Added BY M.T@HeuBoe at $(date)\ninclude \"conf.d/commands.conf\"" >> /etc/icinga2/icinga2.conf

curl -k https://gitlab.heuboe.hbintern/Mohammedt/icinga2-monitoring-scripts/-/raw/main/check-memory/check_memory.sh -o /etc/icinga2/scripts/check_memory.sh && chmod +x /etc/icinga2/scripts/check_memory.sh
curl -k https://gitlab.heuboe.hbintern/Mohammedt/icinga2-monitoring-scripts/-/raw/main/check-memory/check_memory.ini -o /tmp/check_memory.ini && echo "" >> /etc/icinga2/conf.d/commands.conf && cat /tmp/check_memory.ini >> /etc/icinga2/conf.d/commands.conf && rm -f /tmp/check_memory.ini

curl -k https://gitlab.heuboe.hbintern/Mohammedt/icinga2-monitoring-scripts/-/raw/main/check-cpu/check_cpu.sh -o /etc/icinga2/scripts/check_cpu.sh && chmod +x /etc/icinga2/scripts/check_cpu.sh
curl -k https://gitlab.heuboe.hbintern/Mohammedt/icinga2-monitoring-scripts/-/raw/main/check-cpu/check_cpu.ini -o /tmp/check_cpu.ini && cat /tmp/check_cpu.ini >> /etc/icinga2/conf.d/commands.conf && rm -f /tmp/check_cpu.ini

curl -k https://gitlab.heuboe.hbintern/Mohammedt/icinga2-monitoring-scripts/-/raw/main/check-process/check_process.sh -o /etc/icinga2/scripts/check_process.sh && chmod +x /etc/icinga2/scripts/check_process.sh
curl -k https://gitlab.heuboe.hbintern/Mohammedt/icinga2-monitoring-scripts/-/raw/main/check-process/check_process.ini -o /tmp/check_process.ini && cat /tmp/check_process.ini >> /etc/icinga2/conf.d/commands.conf && rm -f /tmp/check_cpu.ini

#On openSUSE you have to add :/usr/local/bin to /etc/sudoers, so sudo can execute k3s and rke2 commands
if ! grep -q "^Defaults[[:space:]]\+secure_path=.*:/usr/local/bin" /etc/sudoers; then sudo sed -i '/^Defaults[[:space:]]\+secure_path=/ s~"$~:/usr/local/bin"~' /etc/sudoers; fi


icinga2 feature list
icinga2 feature enable command
systemctl restart icinga2.service

ps aux --no-headers --sort=-%cpu | head -3 | awk '
        {
            # Print PID, %CPU, %MEM, and then the rest of the command string
            printf "%s %s %s ", $2, $3, $4;
            for (i=11; i<=NF; i++) printf "%s%s", $i, (i==NF?"":" ");
            printf "\n";
        }
    '

================================================================================================================================================================================================================================================================
================================================================================================================================================================================================================================================================

## Install VSphereDB

mysql -e "CREATE DATABASE vspheredb CHARACTER SET 'utf8mb4' COLLATE utf8mb4_bin;
   CREATE USER vspheredb@localhost IDENTIFIED BY 'vspheredbpasswd';
   GRANT ALL ON vspheredb.* TO vspheredb@localhost;"


# You can customize these settings, but we suggest to stick with our defaults:
MODULE_VERSION="1.7.1"
DAEMON_USER="icingavspheredb"
DAEMON_GROUP="icingaweb2"
ICINGAWEB_MODULEPATH="/usr/share/icingaweb2/modules"
REPO_URL="https://github.com/icinga/icingaweb2-module-vspheredb"
TARGET_DIR="${ICINGAWEB_MODULEPATH}/vspheredb"
URL="${REPO_URL}/archive/refs/tags/v${MODULE_VERSION}.tar.gz"

# systemd defaults:
SOCKET_PATH=/run/icinga-vspheredb
TMPFILES_CONFIG=/etc/tmpfiles.d/icinga-vspheredb.conf

getent passwd "${DAEMON_USER}" > /dev/null || useradd -r -g "${DAEMON_GROUP}" \
  -d /var/lib/${DAEMON_USER} -s /bin/false ${DAEMON_USER}
install -d -o "${DAEMON_USER}" -g "${DAEMON_GROUP}" -m 0750 /var/lib/${DAEMON_USER}
install -d -m 0755 "${TARGET_DIR}"

test -d "${TARGET_DIR}_TMP" && rm -rf "${TARGET_DIR}_TMP"
test -d "${TARGET_DIR}_BACKUP" && rm -rf "${TARGET_DIR}_BACKUP"
install -d -o root -g root -m 0755 "${TARGET_DIR}_TMP"
wget -q -O - "$URL" | tar xfz - -C "${TARGET_DIR}_TMP" --strip-components 1 \
  && mv "${TARGET_DIR}" "${TARGET_DIR}_BACKUP" \
  && mv "${TARGET_DIR}_TMP" "${TARGET_DIR}" \
  && rm -rf "${TARGET_DIR}_BACKUP"

echo "d ${SOCKET_PATH} 0755 ${DAEMON_USER} ${DAEMON_GROUP} -" > "${TMPFILES_CONFIG}"
cp -f "${TARGET_DIR}/contrib/systemd/icinga-vspheredb.service" /etc/systemd/system/
systemd-tmpfiles --create "${TMPFILES_CONFIG}"

icingacli module enable vspheredb
systemctl daemon-reload
systemctl enable icinga-vspheredb.service
systemctl restart icinga-vspheredb.service


================================================================================================================================================================================================================================================================
================================================================================================================================================================================================================================================================

## Install x509

mysql -e "CREATE DATABASE x509;
    CREATE USER x509@localhost IDENTIFIED BY 'x509passwd';
    GRANT ALL ON x509.* TO x509@localhost;"

mysql -u root x509 < /usr/share/icingaweb2/modules/x509/schema/mysql.schema.sql 

apt install icinga-x509 -y

icingacli x509 import --file icingacli x509 import --file /root/icingaweb2-certs/CA-HB-AD.crt  #Import the CA certificate
icingacli x509 import --file /root/icingaweb2-certs/icinga.monitoring.heuboe.hbintern.crt

Using Icingaweb2 >  Certificated Monitoring > Configuration > New Job > Name: c2vba-d > CIDRs: 172.31.246.0/24 > Ports: 443 > Exclude Targets: 172.31.246.11, 172.31.246.12, 172.31.246.13

icingacli x509 scan --job c2vba-d --full
ulimit -n 4096
icingacli x509 scan --job hb-intern --full --parallel=1000

icingacli x509 check --ip 172.31.246.11 --port 443 --host worker1.d.c2vba.heuboe.hbintern --warning 1M --critical 15D --allow-self-signed

icingacli x509 check --ip 192.168.195.100 --port 443 --host icinga.monitoring.heuboe.hbintern --warning 1M --critical 15D --allow-self-signed  #Must e defined in the job

icingacli x509 cleanup --since-last-scan="1 minute"  #Cleanup all certificates that hasnt been scanned in the last minute

================================================================================================================================================================================================================================================================
================================================================================================================================================================================================================================================================

## K8s pods and services check script 

curl -s http://master1.d.c2vba.heuboe.hbintern:32751/actuator/health | jq '.status'  #Funktioniert nicht für MongoDB und Kafka