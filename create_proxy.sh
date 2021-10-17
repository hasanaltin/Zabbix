#!/bin/bash

#Proxy installation starts here.

function safe_mkdir {
    if [ ! -d "$1" ]; then
      mkdir "$1"
    fi
}

#    .---------- constant part!
#    vvvv vvvv-- the code from above
RED='\033[0;31m'
NC='\033[0m' # No Color
printf "You are there to install a new proxy server for ${RED}ERY BILISIM LTD. STI.${NC} \n"


HOSTNAME=`hostname`


read -p "Would you like to use the hostname '${HOSTNAME}' as proxy hostname (Y/n)?" -n 1 -r
echo
if [[ ${REPLY} =~ ^[nN]$ ]]; then
  read -p "Enter the proxy hostname: " HOSTNAME
fi

read -p "Would you like to use active proxy (Y/n)?" -n 1 -r
echo
if [[ ${REPLY} =~ ^[nN]$ ]]; then
  # Passive proxy
  echo "Configuring passive proxy"
  PASSIVE_PROXY="1"
else
  read -p "Enter Zabbix server hostname: " SERVER_HOST
  read -p "Enter Zabbix server port: " SERVER_PORT
fi

read -p "Enable SNMP traps (Y/n)?" -n 1 -r
echo
if [[ ${REPLY} =~ ^[nN]$ ]]; then
  echo "ZBX_ENABLE_SNMP_TRAPS=false" >>env.list
else
  echo "ZBX_ENABLE_SNMP_TRAPS=true" >>env.list
fi

safe_mkdir zabbix
safe_mkdir zabbix/enc
safe_mkdir zabbix/externalscripts
safe_mkdir zabbix/mibs
safe_mkdir zabbix/modules
safe_mkdir zabbix/odbc
safe_mkdir zabbix/snmptraps
safe_mkdir zabbix/ssh_keys
safe_mkdir zabbix/ssl
safe_mkdir zabbix/ssl/certs
safe_mkdir zabbix/ssl/keys
safe_mkdir zabbix/ssl/ssl_ca

touch zabbix/odbcinst.ini
touch zabbix/odbc.ini

echo "alpine-5.4-latest" >zabbix/container.version

echo "ZBX_HOSTNAME=${HOSTNAME}" >>env.list
if [ -z "$PASSIVE_PROXY" ]; then
  echo "ZBX_SERVER_HOST=${SERVER_HOST}" >>env.list
  echo "ZBX_SERVER_PORT=${SERVER_PORT}" >>env.list
else
  echo "ZBX_PROXYMODE=1" >>env.list
  echo "ZBX_SERVER_HOST=0.0.0.0/0" >>env.list
fi
echo "ZBX_CONFIGFREQUENCY=300" >>env.list
echo "ZBX_CACHESIZE=600M" >>env.list
echo "ZBX_STARTHTTPPOLLERS=10" >>env.list
echo "ZBX_TIMEOUT=30" >>env.list
echo "ZBX_JAVAGATEWAY_ENABLE=true" >>env.list
echo "ZBX_JAVAGATEWAYPORT=10052" >>env.list
echo "ZBX_STARTJAVAPOLLERS=20" >>env.list
echo "ZBX_STARTPOLLERSUNREACHABLE=20" >>env.list
echo "ZBX_STARTPOLLERS=20" >>env.list
echo "ZBX_STARTTRAPPERS=30" >>env.list
echo "ZBX_LOGSLOWQUERIES=3000" >>env.list
echo "ZBX_ENABLEREMOTECOMMANDS=1" >>env.list
echo "ZBX_PROXYHEARTBEATFREQUENCY=60" >>env.list
echo "ZBX_DATASENDERFREQUENCY=1" >>env.list
echo "ZBX_HOUSEKEEPINGFREQUENCY=1" >>env.list


set -e

export CONTAINER_VERSION=`cat zabbix/container.version`
export CONTAINER_IMAGE=`cat zabbix/container.image`
if [ -z "$CONTAINER_IMAGE" ]; then
  CONTAINER_IMAGE="zabbix/zabbix-proxy-sqlite3"
fi

if [ "$1" == "-help" ]; then
  echo "Usage: $(basename $0) [ <container-name> [ <container-version> ] ]"
  echo
  echo "Default for container name is 'zabbix-proxy' and version is '${CONTAINER_VERSION}'"
  echo
  exit 0
fi

DIR=`realpath $(dirname $0)`
NAME=${1:-zabbix-proxy}
CONTAINER_VERSION=${2:-${CONTAINER_VERSION}}
PSK_FILE=zabbix/enc/zabbix_proxy.psk
CERT_FILE=zabbix/enc/zabbix_proxy_cert.pem
KEY_FILE=zabbix/enc/zabbix_proxy_key.pem
CA_FILE=zabbix/enc/zabbix_proxy.ca
START_CMD="docker-entrypoint.sh"

if [ "$(docker ps -aq -f name=${NAME})" ]; then
  echo "Container with name '${NAME}' already exists. Stop and remove old container before creating new one."
  exit 1
elif [ "$(docker ps -aq -f name="zabbix-java-gateway")" ]; then
  echo "Container with name 'zabbix-java-gateway' already exists. Stop and remove old container before creating new one."
  exit 1
elif [ "$(docker ps -aq -f name="zabbix-snmptraps")" ]; then
  echo "Container with name 'zabbix-snmptraps' already exists. Stop and remove old container before creating new one."
  exit 1
fi

echo "Creating container [${NAME}] using image [${CONTAINER_IMAGE}:${CONTAINER_VERSION}]."

touch zabbix/snmptraps/snmptraps.log
chmod g+w zabbix/snmptraps/snmptraps.log

docker-compose up --no-start

#Proxy installation ends here.

#Containers start here.
#    .---------- constant part!
#    vvvv vvvv-- the code from above
RED='\033[0;31m'
NC='\033[0m' # No Color
printf "You are there to install a new proxy server for ${RED}Installation is done, your containers are starting.${NC} \n"

docker start zabbix-java-gateway zabbix-proxy zabbix-snmptraps

#Containers start here.

#Secure connection beetwen zabbix server and server starts here using pre shared key.

# Usage: opt_replace <key> <value> <file>
# Add or replace option in file. Key and value must not contain pipe character.
function opt_replace {
  grep -q "^$1" "$3" && sed -i "s|^$1.*|$1=$2|" "$3" || echo "$1=$2" >>"$3"
}

PSK_IDENTITY=PSK_001
PSK_FILE=zabbix_proxy.psk

# Obtain PSK identity
read -p "Enter PSK identity [${PSK_IDENTITY}]: " input
PSK_IDENTITY=${input:-$PSK_IDENTITY}

# Obtain PSK key
read -p "Enter pre-generated PSK key - leave empty to generate one now: " PSK_KEY
if [ "${PSK_KEY}" == "" ]; then
  PSK_KEY=`openssl rand -hex 32`

  echo "Generated PSK: ${PSK_KEY}"
  echo
fi

# Check for PSK file
if [ -e "zabbix/enc/${PSK_FILE}" ]; then
  read -p "Old PSK key file exists - remove [y/N]?" -n 1 -r
  echo
  if [[ "$REPLY" =~ ^[yY]$ ]]; then
    rm "zabbix/enc/${PSK_FILE}"
  else
    echo "PSK setup terminated."
    exit 0
  fi
fi

# Create PSK file
echo "${PSK_KEY}" >"zabbix/enc/${PSK_FILE}"

# Given the right rights
chown 1997:1995  "zabbix/enc/${PSK_FILE}"
chmod 0600  "zabbix/enc/${PSK_FILE}"

# Setup environment options
opt_replace ZBX_TLSCONNECT psk env.list
opt_replace ZBX_TLSACCEPT psk env.list
opt_replace ZBX_TLSPSKIDENTITY "${PSK_IDENTITY}" env.list
opt_replace ZBX_TLSPSKFILE "${PSK_FILE}" env.list

#Secure connection beetwen zabbix server and server ends here using pre shared key.
