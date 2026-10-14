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
all: dance atlas duel tanks motion listening
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

.PHONY: duel duel-disk run-duel run-duel-disk
duel: $(BUILD_DIR)/bannerfall.prg
duel-disk: $(BUILD_DIR)/bannerfall.d64

$(BUILD_DIR)/duel:
	mkdir -p $@

$(BUILD_DIR)/duel/assets.inc: tools/generate_duel_assets.py tools/generate_atlas_assets.py | $(BUILD_DIR)/duel
	$(PYTHON) tools/generate_duel_assets.py

$(BUILD_DIR)/duel/%.o: src/duel/%.s $(BUILD_DIR)/duel/assets.inc
	$(CA65) -g -I $(BUILD_DIR)/duel -l $(BUILD_DIR)/duel/$*.lst -o $@ $<

$(BUILD_DIR)/duel/bannerfall.bin: $(BUILD_DIR)/duel/engine.o $(BUILD_DIR)/duel/game.o $(BUILD_DIR)/duel/arena.o $(BUILD_DIR)/duel/input.o $(BUILD_DIR)/duel/sound.o $(BUILD_DIR)/duel/ai.o duel.cfg
	$(LD65) -C duel.cfg -m $(BUILD_DIR)/duel/bannerfall.map -Ln $(BUILD_DIR)/duel/bannerfall.lbl --dbgfile $(BUILD_DIR)/duel/bannerfall.dbg -o $@ $(filter %.o,$^)

$(BUILD_DIR)/bannerfall.prg: $(BUILD_DIR)/duel/bannerfall.bin tools/make_prg.py
	$(PYTHON) tools/make_prg.py $< $@

$(BUILD_DIR)/bannerfall.d64: $(BUILD_DIR)/bannerfall.prg
	$(C1541) -format 'BANNERFALL,03' d64 $@ -write $< bannerfall

run-duel: $(BUILD_DIR)/bannerfall.prg
	$(PYTHON) tools/run_vice.py --vice $(VICE) $<

run-duel-disk: $(BUILD_DIR)/bannerfall.d64
	$(PYTHON) tools/run_vice.py --vice $(VICE) $<

.PHONY: tanks tanks-disk run-tanks run-tanks-disk
tanks: $(BUILD_DIR)/ironveil.prg
tanks-disk: $(BUILD_DIR)/ironveil.d64

$(BUILD_DIR)/tanks:
	mkdir -p $@

$(BUILD_DIR)/tanks/assets.inc: tools/generate_tank_assets.py tools/generate_atlas_assets.py | $(BUILD_DIR)/tanks
	$(PYTHON) tools/generate_tank_assets.py

$(BUILD_DIR)/tanks/title.inc: tools/generate_tank_title.py tools/generate_atlas_assets.py | $(BUILD_DIR)/tanks
	$(PYTHON) tools/generate_tank_title.py

$(BUILD_DIR)/tanks/%.o: src/tanks/%.s $(BUILD_DIR)/tanks/assets.inc $(BUILD_DIR)/tanks/title.inc
	$(CA65) -g -I $(BUILD_DIR)/tanks -l $(BUILD_DIR)/tanks/$*.lst -o $@ $<

TANK_OBJECTS := $(addprefix $(BUILD_DIR)/tanks/,engine.o game.o world.o ai.o input.o sense.o sound.o)
$(BUILD_DIR)/tanks/ironveil.bin: $(TANK_OBJECTS) tanks.cfg
	$(LD65) -C tanks.cfg -m $(BUILD_DIR)/tanks/ironveil.map -Ln $(BUILD_DIR)/tanks/ironveil.lbl --dbgfile $(BUILD_DIR)/tanks/ironveil.dbg -o $@ $(TANK_OBJECTS)

$(BUILD_DIR)/ironveil.prg: $(BUILD_DIR)/tanks/ironveil.bin tools/make_prg.py
	$(PYTHON) tools/make_prg.py $< $@

$(BUILD_DIR)/ironveil.d64: $(BUILD_DIR)/ironveil.prg
	$(C1541) -format 'IRONVEIL,04' d64 $@ -write $< ironveil

run-tanks: $(BUILD_DIR)/ironveil.prg
	$(PYTHON) tools/run_vice.py --vice $(VICE) $<

run-tanks-disk: $(BUILD_DIR)/ironveil.d64
	$(PYTHON) tools/run_vice.py --vice $(VICE) $<

.PHONY: motion motion-disk run-motion run-motion-disk
motion: $(BUILD_DIR)/borrowed-motion.prg
motion-disk: $(BUILD_DIR)/borrowed-motion.d64

$(BUILD_DIR)/motion:
	mkdir -p $@

$(BUILD_DIR)/motion/assets.inc: tools/generate_motion_assets.py tools/generate_atlas_assets.py | $(BUILD_DIR)/motion
	$(PYTHON) $<

$(BUILD_DIR)/motion/levels.inc: tools/generate_motion_levels.py tools/motion_chapter_middle.py tools/motion_chapter_expert.py tools/motion_chapter_finale.py | $(BUILD_DIR)/motion
	$(PYTHON) $<

$(BUILD_DIR)/motion/%.o: src/motion/%.s $(BUILD_DIR)/motion/assets.inc $(BUILD_DIR)/motion/levels.inc
	$(CA65) -g -I $(BUILD_DIR)/motion -l $(BUILD_DIR)/motion/$*.lst -o $@ $<

MOTION_OBJECTS := $(addprefix $(BUILD_DIR)/motion/,engine.o input.o sound.o)
$(BUILD_DIR)/motion/borrowed-motion.bin: $(MOTION_OBJECTS) motion.cfg
	$(LD65) -C motion.cfg -m $(BUILD_DIR)/motion/borrowed-motion.map -Ln $(BUILD_DIR)/motion/borrowed-motion.lbl --dbgfile $(BUILD_DIR)/motion/borrowed-motion.dbg -o $@ $(MOTION_OBJECTS)

$(BUILD_DIR)/borrowed-motion.prg: $(BUILD_DIR)/motion/borrowed-motion.bin tools/make_prg.py
	$(PYTHON) tools/make_prg.py $< $@

$(BUILD_DIR)/borrowed-motion.d64: $(BUILD_DIR)/borrowed-motion.prg
	$(C1541) -format 'BORROWED MOTION,05' d64 $@ -write $< borrowed-motion

run-motion: $(BUILD_DIR)/borrowed-motion.prg
	$(PYTHON) tools/run_vice.py --vice $(VICE) --monitor-port 6560 $<

run-motion-disk: $(BUILD_DIR)/borrowed-motion.d64
	$(PYTHON) tools/run_vice.py --vice $(VICE) --monitor-port 6560 $<

.PHONY: listening listening-disk run-listening run-listening-disk
listening: $(BUILD_DIR)/the-shape-of-listening.prg
listening-disk: $(BUILD_DIR)/the-shape-of-listening.d64

$(BUILD_DIR)/listening:
	mkdir -p $@

$(BUILD_DIR)/listening/score.inc: tools/compose_listening.py | $(BUILD_DIR)/listening
	$(PYTHON) $<

$(BUILD_DIR)/listening/art.inc: tools/generate_listening_art.py | $(BUILD_DIR)/listening
	$(PYTHON) $<

$(BUILD_DIR)/listening/%.o: src/listening/%.s $(BUILD_DIR)/listening/score.inc $(BUILD_DIR)/listening/art.inc
	$(CA65) -g -I $(BUILD_DIR)/listening -l $(BUILD_DIR)/listening/$*.lst -o $@ $<

$(BUILD_DIR)/listening/listening.bin: $(BUILD_DIR)/listening/engine.o $(BUILD_DIR)/listening/visual.o listening.cfg
	$(LD65) -C listening.cfg -m $(BUILD_DIR)/listening/listening.map -Ln $(BUILD_DIR)/listening/listening.lbl --dbgfile $(BUILD_DIR)/listening/listening.dbg -o $@ $(filter %.o,$^)

$(BUILD_DIR)/the-shape-of-listening.prg: $(BUILD_DIR)/listening/listening.bin tools/make_prg.py
	$(PYTHON) tools/make_prg.py $< $@

$(BUILD_DIR)/the-shape-of-listening.d64: $(BUILD_DIR)/the-shape-of-listening.prg
	$(C1541) -format 'SHAPE LISTENING,06' d64 $@ -write $< listening

run-listening: $(BUILD_DIR)/the-shape-of-listening.prg
	$(PYTHON) tools/run_vice.py --vice $(VICE) --monitor-port 6590 $<

run-listening-disk: $(BUILD_DIR)/the-shape-of-listening.d64
	$(PYTHON) tools/run_vice.py --vice $(VICE) --monitor-port 6590 $<

clean:
	rm -rf $(BUILD_DIR)
