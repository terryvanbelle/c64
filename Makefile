CA65 ?= ca65
LD65 ?= ld65
PYTHON ?= python3
VICE ?= x64sc

BUILD_DIR := build
OBJECT := $(BUILD_DIR)/demo.o
RAW := $(BUILD_DIR)/demo.bin
PROGRAM := $(BUILD_DIR)/demo.prg

.PHONY: all run clean

all: $(PROGRAM)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(OBJECT): src/demo.s | $(BUILD_DIR)
	$(CA65) -o $@ $<

$(RAW): $(OBJECT) c64.cfg
	$(LD65) -C c64.cfg -o $@ $(OBJECT)

$(PROGRAM): $(RAW) tools/make_prg.py
	$(PYTHON) tools/make_prg.py $(RAW) $@

run: $(PROGRAM)
	$(VICE) -autostartprgmode 1 -autostart-delay 2 $(PROGRAM)

clean:
	rm -rf $(BUILD_DIR)
