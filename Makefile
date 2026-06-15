KERNELS ?= 5.0 5.1 5.2 5.3 5.4 5.5 5.6 5.7 5.8 5.9 5.10 5.11 5.12 5.13 5.14 5.15 5.16 5.17 5.18 5.19 6.0 6.1 6.2 6.3 6.4 6.5 6.6 6.7 6.8 6.9 6.10 6.11 6.12 6.13 6.14 6.15 6.16 6.17 6.18 6.19 7.0 7.1-rc3
VERSION ?= 5.0
SCRIPTS := $(shell pwd)/scripts
PYTHON = $(if $(wildcard .venv/bin/python3),.venv/bin/python3,python3)

.PHONY: all clean download initramfs lebench patched plot run setup

all: setup lebench initramfs run plot

clean:
	rm -rf build/ kernels/ logs/ plots/ results/ staging/ initrd.gz

download:
	@bash $(SCRIPTS)/download.sh $(VERSION)

initramfs: lebench
	@bash $(SCRIPTS)/initramfs.sh

kernels/vmlinuz-%:
	@bash $(SCRIPTS)/download.sh $*

lebench:
	@bash $(SCRIPTS)/lebench.sh

plot:
	@$(PYTHON) plot.py

run: initramfs
	@set -e; mkdir -p results logs; 					  \
	for v in $(KERNELS); do 							  \
		echo ""; 										  \
		echo "========================================";  \
		echo " Benchmarking kernel $$v"; 				  \
		echo "========================================";  \
		bash $(SCRIPTS)/download.sh $$v; 				  \
		bash $(SCRIPTS)/benchmark.sh $$v; 				  \
	done

patched: initramfs
	@bash $(SCRIPTS)/patch.sh --kernels "$(KERNELS)"

setup:
	@bash $(SCRIPTS)/setup.sh
