#!/bin/bash

set -e

# update motd
echo -e "'VPN Wanze' VPN-Server - Entwickelt von Maciej Krüger\n\nVerwaltung:\n\tsudo wanze setup - Server einrichten\n\tsudo proxy status - Server Status anzeigen\n\tsudo wanze-update - Server software aktualisieren\n" > /etc/motd

wanze refresh
