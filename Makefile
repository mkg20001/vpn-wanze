build:
	VM_NAME=vpn-wanze make -C ./shared build
dist:
	VM_NAME=vpn-wanze make -C ./shared dist
dev:
	VM_NAME=vpn-wanze make -C ./shared dev

prepare:
	touch /tmp/g
