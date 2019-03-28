build:
	VM_NAME=vpn-wanze make -C ./shared build
dist:
	VM_NAME=vpn-wanze make -C ./shared dist

prepare:
	touch /tmp/g
