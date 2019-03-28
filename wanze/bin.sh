#!/bin/bash

set -e

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
  if [ ! -e "/etc/cjdroute.conf" ]; then
    prompt cjd_custom "Eigenen CJDNS Knoten verwenden" "n" "yesno"

    if $CJD_CUSTOM; then
      prompt cjd_server "CJDNS Knoten Addresse"
      prompt cjd_user "CJDNS Knoten Benutzer"
      prompt cjd_password "CJDNS Knoten Passwort"
      prompt cjd_publickey "CJDNS Knoten Schlüssel"
      d "Werte können nachher manuell in der Datei /etc/cjdroute.conf geändert werden"
    else
      CJD_SERVER="138.201.254.83:26117"
      CJD_USER="justmeandmynsaproofserverconnectingtocjdns"
      CJD_PASSWORD="9c5k76qjydr7jmmw5h7glh5m52zjn4q"
      CJD_PUBLICKEY="27n9q61k7zlr4luwrjcvzjcmf30mwjmkp8c3qq14b68c0fbgrtq0"
    fi

    i "CJDNS Knoten-Schlüssel wird erstellt..."
    /opt/cjdns/cjdroute > /etc/cjdroute.conf

    i "Externer CJDNS Knoten wird eingetragen..."
    sed 's|// Ask somebody who is already connected.|
        "'"$CJD_SERVER"'": {
            "login": "'"$CJD_LOGIN"'",
            "password":"'"$CJD_PASSWORD"'",
            "publicKey":"'"$CJD_PUBLICKEY"'",
            "peerName":"hauptknoten"
        },
|' -i /etc/cjdroute.conf

    systemctl restart cjdns
  fi
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
  done
}

gen_webroots() {
  i "Aktualisiere Konfigurationsdateien und Installer..."

  rm -rf /var/wanze/www/
  mkdir -p /var/wanze/www
  cp -rp "$MAIN/wanze/webroot" /var/wanze/www/generic

  _db_get wg_pub

  for peer in /var/wanze/clients/*/db; do
    pushdb "$peer"
    _db_get peer_cjd
    mkdir "/var/wanze/www/$peer_cjd"
    envsubst <"$MAIN/wanze/client.html" > "/var/wanze/www/$peer_cjd/index.html"
    envsubst <"$MAIN/wanze/client.json" > "/var/wanze/www/$peer_cjd/myconf.json"
  done
}

setup_wireguard() {
  i "Stoppe WireGuard Dienst..."
  # TODO: check if wanze0 on and stop
  i "Aktualisiere Konfiguration..."
  wg_genconf > /etc/wireguard/wanze0.conf
  i "Starte WireGuard Dienst..."
  wg-quick up wanze0
  # TODO: setup systemd autostart
}

add() {
  pushdb
  prompt peer_name "Name" "$1"
  prompt peer_cjd "CJDNS Adresse" "$2"
  prompt peer_wgpub "WireGuard Public Key" "$3"
  mv "$DB" "/tmp/newclient"
  popdb

  # TODO: other stuff
  ufw allow port 4999 proto udp from "$PEER_CJD" comment "Client $PEER_NAME"
  ufw allow port 19999 proto tcp from "$PEER_CJD" comment "Netdata $PEER_NAME"

  OUTF="/var/wanze/clients/$PEER_NAME"
  mkdir -p "$OUTF"
  mv "/tmp/newclient" "$OUTF/db"

  gen_webroots
}

setup() {
  setup_net

  prompt ""

  setup_wireguard
  setup_web
  gen_webroots

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
