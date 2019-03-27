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

setup_cjdns() {
  if [ ! -e "/etc/cjdroute.conf" ]; then
    prompt cjd_custom "Eigenen CJDNS Knoten verwenden" "n" "yesno"

    if $CJD_CUSTOM; then
      prompt cjd_server "CJDNS Knoten Addresse"
      prompt cjd_user "CJDNS Knoten Benutzer"
      prompt cjd_password "CJDNS Knoten passwort"
      prompt cjd_publickey "CJDNS Knoten Schlüssel"
      o "Werte können nachher manuell in der Datei /etc/cjdroute.conf geändert werden"
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
    _db wg_priv
    _db wg_pub
  fi

  _db_get wg_priv
  _db_get wg_pub
  echo "[Interface]"
  echo "Address = 10.8.1.1/24"
  echo "Address = fd80:8888:8888::1/64"
  echo "ListenPort = 4999"
  echo "PrivateKey = $WG_PRIV"
  echo
  for peer in /var/wanze/clients/*/db; do
    pushdb "$peer"
    echo "[Peer]"
    _db_get peer_wgpub
    echo "PublicKey = $PEER_WGPUBQ"
    echo "AllowedIPs = 10.8.1.0/24, fd80:8888:8888::/64"
  done
}

gen_webroots() {
  rm -rf /var/wanze/www/
  mkdir -p /var/wanze/www
  cp -rp "$MAIN/wanze/webroot" /var/wanze/www/generic

  _db_get wg_pub

  for peer in /var/wanze/clients/*/db; do
    pushdb "$peer"
    _db_get peer_cjd
    mkdir "/var/wanze/www/$peer_cjd"
    envsubst <"$MAIN/wanze/client.html" > "/var/wanze/www/$peer_cjd/index.html"
}

setup_wireguard() {
  # TODO: check if wanze0 on and stop
  wg_genconf > /etc/wireguard/wanze0.conf
  wg-quick up wanze0
}

add() {
  pushdb
  prompt peer_name "Name"
  prompt peer_cjd "CJDNS Adresse"
  prompt peer_wgpub "WireGuard Public Key"
  mv "$DB" "/tmp/newclient"
  popdb

  

  OUTF="/var/wanze/clients/$PEER_NAME"
  mkdir -p "$OUTF"
  mv "$DB" "$OUTF/db"
}

setup() {
  setup_net

  # prompt email "E-Mail für Zertifikatsablaufbenarichtigungen"
  prompt domain "Haupt Domain-Name (z.B. ihre-schule.de)"
  prompt ip "paedML Ziel-Server IP-Addresse oder DNS (IPv6 Addressen umklammert angeben)"
  prompt sub "Subdomains (mit leerzeichen getrennt angeben)" "server mail vibe filr"
  prompt usemain "Maindomain verwenden (j=ja, n=nein)" j

  setup_web

  echo "[!] Fertig"
}

main() {
  case "$1" in
    setup|status|cron|help)
      "$1"
      ;;
    *)
      help
      ;;
  esac
}

main "$@"
