# Simple simulation flow (Icarus Verilog + GTKWave)
#
# Targets:
#   make sim      Compile + run; generates build/xspi_tb.vcd
#   make wave     Open VCD in GTKWave
#   make clean    Remove build artifacts

TOP_TB    ?= xspi_stimulus
BUILD_DIR ?= build
SIM_OUT   ?= $(BUILD_DIR)/xspi_sim
VCD_FILE  ?= $(BUILD_DIR)/xspi_tb.vcd

SRC_V := \
	src/xspi_top.v \
	src/xspi_sopi_controller.v \
	src/xspi_sopi_slave.v \
	src/crc8.v \
	src/crc8_slave.v

TB_V := \
	tb/xspi_stimulus.v

.PHONY: all sim wave clean

all: sim

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Note: the testbench writes "xspi_tb.vcd" to the current working directory.
# We run vvp from inside $(BUILD_DIR) so the VCD ends up in build/.

sim: $(BUILD_DIR)
	iverilog -g2012 -o $(SIM_OUT) $(SRC_V) $(TB_V)
	cd $(BUILD_DIR) && vvp $(notdir $(SIM_OUT))
	@echo "VCD written to: $(VCD_FILE)"

wave: sim
	gtkwave $(VCD_FILE)

clean:
	rm -rf $(BUILD_DIR)
