build:
	make -C ./shared build
dist:
	make -C ./shared dist

prepare:
	touch /tmp/g
