#!/bin/bash

set -e

shopt -s nullglob

MAIN=$(dirname $(dirname $(readlink -f $0)))
SHARED="$MAIN/shared"

. "$SHARED/modules/basic.sh"
_module _root
_module db
_module ui
_module net

init_db "/var/lib/wanze-config"

help() {
  echo "Wanzen Konfigurations Tool"
  echo
  echo "Befehle:"
  echo " setup: Initielle Konfiguration durchführen (kann auch erneut ausgeführt werden um die Werte zu ändern)"
  echo " status: Wireguard & CJDNS Status"
  echo " add: Rechner hinzufügen"
  echo " rm <name>: Rechner entfernen"
  echo " list: Alle rechner auflisten"
  echo
  exit 2
}

status() {
  d "CJDNS Status"
  /opt/cjdns/tools/peerStats 2>&1 | grep -v "DeprecationWarning" # TODO: rm when fixed upstream
  d "WireGuard Status"
  wg
}

setup_cjdns() {
  if [ ! -e /usr/bin/cjdroute ]; then
    i "Kompiliere CJDNS für diesen Server..."
    cd /opt/cjdns
    git clean -dxf
    ./do
    cp /opt/cjdns/cjdroute /usr/bin/cjdroute
    cd "$MAIN"
  fi

  i "Aktualisieren der CJDNS-Konfiguration..."

  if [ ! -e /etc/cjdroute.conf ]; then
    systemctl restart cjdns
    sleep 1s
  fi

  echo '#!/usr/bin/gawk -f

BEGIN {
  skip = 0
  ok = 0
}

{
  if ($1 == "//" && $2 == "Ask" && $3 == "somebody" && !skip && !ok) {
    skip = 1
    print $0
    next
  }
  if (skip && !$0) {
    print ENVIRON["CJDNS_CONFIG"]
    print ""
    skip = 0
    ok = 1
    next
  }
  if (skip) {
    next
  }
  print $0
}' > /tmp/.cjdns.awk

  if ! grep "// Ask somebody who is already connected.." /etc/cjdroute.conf > /dev/null; then
    sed "s|// Ask somebody who is already connected.|// Ask somebody who is already connected..\\n|" -i /etc/cjdroute.conf
  fi

  export CJDNS_CONFIG='// config
        "138.201.254.83:26117": {
            "login": "justmeandmynsaproofserverconnectingtocjdns",
            "password":"9c5k76qjydr7jmmw5h7glh5m52zjn4q",
            "publicKey":"27n9q61k7zlr4luwrjcvzjcmf30mwjmkp8c3qq14b68c0fbgrtq0.k",
            "peerName":"pub@argon.mkg20001.io"
        },
'

  gawk -f /tmp/.cjdns.awk -i inplace /etc/cjdroute.conf
  rm /tmp/.cjdns.awk

  echo "[*] Neustarten von CJDNS..."

  systemctl restart cjdns

  _db local_cjd "$(cat /etc/cjdroute.conf | grep -o "fc[a-z0-9]*:[a-z0-9:]*")"
}

wg_genconf() {
  if ! _db_exists wg_priv; then
    WG_PRIV=$(wg genkey)
    _db wg_priv "$WG_PRIV"
    _db wg_pub "$(echo "$WG_PRIV" | wg pubkey)"
  fi

  _db_get wg_priv
  _db_get wg_pub
  echo "[Interface]"
  echo "Address = 10.8.1.1/24"
  echo "Address = fd80:8888:8888::1/64" # TODO: seems wrong
  echo "ListenPort = 4999"
  echo "PrivateKey = $WG_PRIV"
  echo
  for peer in /var/wanze/clients/*/db; do
    pushdb "$peer"
    echo "[Peer]"
    _db_get peer_wgpub
    echo "PublicKey = $PEER_WGPUB"
    echo "AllowedIPs = 10.8.1.0/24, fd80:8888:8888::/64"
    popdb
  done
}

gen_webroots() {
  i "Aktualisiere Konfigurationsdateien und Installer..."

  rm -rf /var/wanze/www/
  mkdir -p /var/wanze/www
  cp -rp "$MAIN/wanze/webroot" /var/wanze/www/generic

  _db_get wg_pub
  _db_get local_cjd

  for peer in /var/wanze/clients/*/db; do
    pushdb "$peer"
    _db_get peer_cjd
    _db_get peer_v4id
    _db_get peer_v6id
    mkdir "/var/wanze/www/$PEER_CJD"
    envsubst <"$MAIN/wanze/client.html" > "/var/wanze/www/$PEER_CJD/index.html"
    envsubst <"$MAIN/wanze/client.json" > "/var/wanze/www/$PEER_CJD/myconf.json"
    popdb
  done
}

setup_wireguard() {
  i "Stoppe WireGuard Dienst..."
  wg-quick down wanze0 || /bin/true # TODO: make better
  i "Aktualisiere Konfiguration..."
  wg_genconf > /etc/wireguard/wanze0.conf
  i "Starte WireGuard Dienst..."
  wg-quick up wanze0
  systemctl enable wg-quick@wanze0
}

add() {
  pushdb
  prompt peer_name "Name" "$1"
  prompt peer_cjd "CJDNS Adresse" "$2"
  prompt peer_wgpub "WireGuard Public Key" "$3"
  mv "$DB" "/tmp/newclient"
  popdb

  # TODO: other stuff
  ufw allow from "$PEER_CJD" to any port 4999 proto udp comment "Client $PEER_NAME"
  ufw allow from "$PEER_CJD" to any port 19999 proto tcp comment "Netdata $PEER_NAME"

  OUTF="/var/wanze/clients/$PEER_NAME"
  mkdir -p "$OUTF"
  mv -v "/tmp/newclient" "$OUTF/db"

  pushdb "$OUTF/db"
  V4="3" # TODO: automatically assign
  _db peer_v4id "$V4"
  _db peer_v6id "$(printf '%x\n' "$V4")"
  popdb

  setup_wireguard
  setup_web
}

setup_web() {
  gen_webroots
}

setup() {
  setup_net
  setup_cjdns
  setup_wireguard
  setup_web

  echo "[!] Fertig"
}

main() {
  case "$1" in
    setup|status|gen_webroots|add|rm|list|help)
      "$@"
      ;;
    *)
      help
      ;;
  esac
}

main "$@"
