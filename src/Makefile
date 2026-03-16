# Makefile calls gen_inputs.py to generate the input files for the testbench
# then it calls testbench to actually compile and run the systolic array simulation

# EXAMPLE USAGE

# make clean
# cleans up working_dir

# make sim or make sim N=0 or make sim N=0 I=0
# just does a check with N=4 to make sure the verilog files compiles correctly
# this does not run any tests or generate any input files

# make sim I=? or make sim N=0 I=?
# this will generate the input files but it still won't run any tests

# make sim N=4 or make sim N=4 I=0
# N=4, I=[4,4,4,0]
# executes a 4x4 identity multiply on a 4x4 array to verify M(4x4) x I(4x4) = M(4x4)
# (this tests correctness for a simple matrix multiply)

# make sim N=4 I=8 OR make sim N=4 I=8,0
# N=4, I=[8,8,8,0]
# executes a 8x8 identity multiply on a 4x4 array to verify M(8x8) x I(8x8) = M(8x8)
# (this tests tiling for square matrices that are differently sized than the array)

# make sim N=4 I=8,4 OR make sim N=4 I=8,4,0
# N=4, I=[8,4,4,0]
# executes a 8x4 identity multiply on a 4x4 array to verify M(8x4) x I(4x4) = M(8x4)
# (this tests tiling for non-square matrices)

# make sim N=4 I=8,4,2,16 OR make sim N=4 I=8,4,2,16,0
# N=4, I=[8,4,2,16,0]
# executes (8x4) x (4x2) x (2x16) = (8x16) on a 4x4 array
# (this actually tests non-identity MMM chains on the systolic array)

# you can also do N=A,B,C,... to run multiple tests with different array sizes (0 terminator is optional for N as well)
# instructions are only generated once, but each test will use a new binary for each N
# there are also -seed and -wdir arguments

# REQUIRED TESTS
# make sim N=4,8 I=32,16,64,8,16,0

N    ?=
I    ?=
SEED ?= 42

WDIR   = ../working_dir
SRC    = instr_mem.v data_mem.v output_mem.v systolic_pe.v systolic_array.v state_machine.v top.v
TB     = testbench.v
SIM    = $(WDIR)/sim_n$(N)/sim_n$(N)

# macros passed to iverilog so testbench knows where the hex/vcd files live
DMACROS = -DN=$(N) \
          -DWORKDIR_A=\"$(WDIR)/mem_a.hex\" \
          -DWORKDIR_B=\"$(WDIR)/mem_b.hex\" \
          -DWORKDIR_I=\"$(WDIR)/mem_i.hex\" \
          -DWORKDIR_REF=\"$(WDIR)/ref_out.hex\" \
          -DWORKDIR_OUT=\"$(WDIR)/sim_n$(N)/sim_out_n$(N).hex\" \
          -DWORKDIR_VCD=\"$(WDIR)/sim_n$(N)/sim_n$(N).vcd\" \
          -DWORKDIR_LOG=\"$(WDIR)/sim_n$(N)/sim_cycles_n$(N).log\" \
          -DWORKDIR_INSTR=\"$(if $(I),$(I),$(N),$(N),$(N),0)\"

# pick up exact word counts written by gen_inputs.py to params.mk to suppress $readmemh warnings
# defaults cover make clean where params.mk doesn't exist
MEM_A_WORDS   ?= 4096
MEM_B_WORDS   ?= 4096
MEM_I_WORDS   ?= 256
MEM_REF_WORDS ?= 4096
TEST_TYPE     ?= 0
TEST_IDENTITY_M ?= $(N)
TEST_IDENTITY_I ?= $(N)
TEST_MAC_TOTAL ?= 0
TEST_MMM_TOTAL ?= 1
TEST_MMM_CHAIN ?= unknown
-include $(WDIR)/params.mk

SIZE_MACROS = -DMEM_A_WORDS=$(MEM_A_WORDS) \
              -DMEM_B_WORDS=$(MEM_B_WORDS) \
              -DMEM_I_WORDS=$(MEM_I_WORDS) \
              -DMEM_REF_WORDS=$(MEM_REF_WORDS) \
              -DTEST_TYPE=$(TEST_TYPE) \
              -DTEST_IDENTITY_M=$(TEST_IDENTITY_M) \
              -DTEST_IDENTITY_I=$(TEST_IDENTITY_I) \
              -DTEST_MAC_TOTAL=$(TEST_MAC_TOTAL) \
              -DTEST_MMM_TOTAL=$(TEST_MMM_TOTAL) \
              -DTEST_MMM_CHAIN='"$(TEST_MMM_CHAIN)"'

.PHONY: sim _compile _run _yosys clean

sim:
	@mkdir -p $(WDIR)
	@if [ -n "$(N)" ] && [ "$(N)" != "0" ]; then \
		for n in $$(echo "$(N)" | tr "," " "); do \
			[ "$$n" = "0" ] && continue; \
			mkdir -p $(WDIR)/sim_n$$n; \
		done; \
	fi
	@echo ""
	@if [ -z "$(N)" ] || [ "$(N)" = "0" ]; then \
		FIRST_I=$$(echo "$(I)" | cut -d, -f1); \
		if [ -z "$$FIRST_I" ] || [ "$$FIRST_I" = "0" ]; then \
			echo "=== Compile Check ==="; \
			mkdir -p $(WDIR)/sim_n4; \
			$(MAKE) --no-print-directory _compile N=4; \
			echo "Verilog compilation successful"; \
		else \
			echo "=== Systolic Array Instructions ==="; \
			python3 gen_inputs.py --N 4 --I "$(I)" --seed $(SEED) --wdir $(WDIR); \
		fi; \
	else \
		echo "=== Systolic Array Instructions ==="; \
		FIRST_N=$$(echo "$(N)" | cut -d, -f1); \
		FIRST_I=$$(echo "$(I)" | cut -d, -f1); \
		if [ -z "$$FIRST_I" ] || [ "$$FIRST_I" = "0" ]; then \
			python3 gen_inputs.py --N $$FIRST_N --seed $(SEED) --wdir $(WDIR); \
		else \
			python3 gen_inputs.py --N $$FIRST_N --I "$(I)" --seed $(SEED) --wdir $(WDIR); \
		fi; \
		echo ""; \
		FIRST=1; \
		for n in $$(echo "$(N)" | tr "," " "); do \
			[ "$$n" = "0" ] && continue; \
			if [ $$FIRST -eq 1 ]; then \
				FIRST=0; \
			else \
				echo ""; \
			fi; \
			$(MAKE) --no-print-directory _run N=$$n I=$(I) SEED=$(SEED); \
		done; \
		echo ""; \
	fi

_compile:
	@iverilog -g2012 $(DMACROS) $(SIZE_MACROS) -o $(SIM) $(TB) $(SRC)

_run:
	@iverilog -g2012 $(DMACROS) $(SIZE_MACROS) -o $(SIM) $(TB) $(SRC)
	@$(MAKE) --no-print-directory _yosys N=$(N)
	@GATES=$$(awk 'BEGIN{g=""} \
	    /^[[:space:]]*Number of cells:/ { g=$$NF } \
	    /^[[:space:]]*[0-9]+ cells$$/ { g=$$1 } \
	    END{print g}' $(WDIR)/sim_n$(N)/sim_cells_n$(N).log 2>/dev/null | tail -1); \
	if [ -z "$$GATES" ]; then GATES="unknown"; fi; \
	vvp $(SIM) | awk -v g="$$GATES" '{ \
		if ($$0 ~ /^  [0-9]+ cycles$$/) { \
			print $$0 ", " g " gates"; \
		} else if ($$0 !~ /VCD info/) { \
			print $$0; \
		} \
	}' || true

_yosys:
	@if ! command -v yosys >/dev/null 2>&1; then \
		echo "yosys not found" > $(WDIR)/sim_n$(N)/sim_cells_n$(N).log; \
		exit 0; \
	fi
	@yosys -p 'read_verilog -lib data_mem.v output_mem.v instr_mem.v; read_verilog systolic_pe.v systolic_array.v state_machine.v top.v; hierarchy -top top -chparam N $(N); synth -top top; stat' 2>&1 | awk '/^11\. Printing statistics\./{p=1} p' > $(WDIR)/sim_n$(N)/sim_cells_n$(N).log

clean:
	@mkdir -p $(WDIR)
	rm -rf $(WDIR)/*
