CA65 ?= ca65
LD65 ?= ld65
PYTHON ?= python3
VICE ?= x64sc
C1541 ?= c1541

BUILD_DIR := build
DANCE_DIR := $(BUILD_DIR)/dance
DANCE_OBJECTS := $(DANCE_DIR)/engine.o $(DANCE_DIR)/music.o
DANCE_PRG := $(BUILD_DIR)/nocturne.prg

.PHONY: all dance disk demo run run-disk run-demo clean
all: dance atlas
dance: $(DANCE_PRG)
demo: $(BUILD_DIR)/demo.prg
disk: $(BUILD_DIR)/nocturne.d64

$(BUILD_DIR) $(DANCE_DIR):
	mkdir -p $@

$(DANCE_DIR)/assets.inc: tools/generate_dance_assets.py | $(DANCE_DIR)
	$(PYTHON) $<

$(DANCE_DIR)/motion.inc: tools/generate_dance_motion.py | $(DANCE_DIR)
	$(PYTHON) $<

$(DANCE_DIR)/engine.o: src/dance/engine.s $(DANCE_DIR)/assets.inc $(DANCE_DIR)/motion.inc
	$(CA65) -g -I $(DANCE_DIR) -l $(DANCE_DIR)/engine.lst -o $@ $<

$(DANCE_DIR)/music.o: src/dance/music.s | $(DANCE_DIR)
	$(CA65) -g -l $(DANCE_DIR)/music.lst -o $@ $<

$(DANCE_DIR)/nocturne.bin: $(DANCE_OBJECTS) dance.cfg
	$(LD65) -C dance.cfg -m $(DANCE_DIR)/nocturne.map -Ln $(DANCE_DIR)/nocturne.lbl --dbgfile $(DANCE_DIR)/nocturne.dbg -o $@ $(DANCE_OBJECTS)

$(DANCE_PRG): $(DANCE_DIR)/nocturne.bin tools/make_prg.py
	$(PYTHON) tools/make_prg.py $< $@

run: $(DANCE_PRG)
	$(PYTHON) tools/run_vice.py --vice $(VICE) $(DANCE_PRG)

$(BUILD_DIR)/nocturne.d64: $(DANCE_PRG)
	$(C1541) -format 'NOCTURNE,01' d64 $@ -write $< nocturne

run-disk: $(BUILD_DIR)/nocturne.d64
	$(PYTHON) tools/run_vice.py --vice $(VICE) $<

$(BUILD_DIR)/demo.o: src/demo.s | $(BUILD_DIR)
	$(CA65) -o $@ $<

$(BUILD_DIR)/demo.bin: $(BUILD_DIR)/demo.o c64.cfg
	$(LD65) -C c64.cfg -o $@ $<

$(BUILD_DIR)/demo.prg: $(BUILD_DIR)/demo.bin tools/make_prg.py
	$(PYTHON) tools/make_prg.py $< $@

run-demo: $(BUILD_DIR)/demo.prg
	$(PYTHON) tools/run_vice.py --vice $(VICE) $(BUILD_DIR)/demo.prg

.PHONY: atlas atlas-disk run-atlas run-atlas-disk
atlas: $(BUILD_DIR)/atlas.prg
atlas-disk: $(BUILD_DIR)/atlas.d64

$(BUILD_DIR)/atlas:
	mkdir -p $@

$(BUILD_DIR)/atlas/assets.inc: tools/generate_atlas_assets.py | $(BUILD_DIR)/atlas
	$(PYTHON) $<

$(BUILD_DIR)/atlas/%.o: src/atlas/%.s $(BUILD_DIR)/atlas/assets.inc
	$(CA65) -g -I $(BUILD_DIR)/atlas -l $(BUILD_DIR)/atlas/$*.lst -o $@ $<

$(BUILD_DIR)/atlas/atlas.bin: $(BUILD_DIR)/atlas/engine.o $(BUILD_DIR)/atlas/world.o $(BUILD_DIR)/atlas/input.o $(BUILD_DIR)/atlas/cache.o atlas.cfg
	$(LD65) -C atlas.cfg -m $(BUILD_DIR)/atlas/atlas.map -Ln $(BUILD_DIR)/atlas/atlas.lbl --dbgfile $(BUILD_DIR)/atlas/atlas.dbg -o $@ $(filter %.o,$^)

$(BUILD_DIR)/atlas.prg: $(BUILD_DIR)/atlas/atlas.bin tools/make_prg.py
	$(PYTHON) tools/make_prg.py $< $@

$(BUILD_DIR)/atlas.d64: $(BUILD_DIR)/atlas.prg
	$(C1541) -format 'ATLAS,02' d64 $@ -write $< atlas

run-atlas: $(BUILD_DIR)/atlas.prg
	$(PYTHON) tools/run_vice.py --vice $(VICE) $<

run-atlas-disk: $(BUILD_DIR)/atlas.d64
	$(PYTHON) tools/run_vice.py --vice $(VICE) $<

clean:
	rm -rf $(BUILD_DIR)
