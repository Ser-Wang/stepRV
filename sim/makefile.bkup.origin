all: filelist com_fsdb sim verdi
#---------------------------------------------------------------
CORE_VERSION ?= 00_rv32i_basic
filelist:
	find ../$(CORE_VERSION)/de ../$(CORE_VERSION)/dv -name "*.v" -o -name "*.sv" > filelist.f
#---------------------------------------------------------------
com_vpd:
	vcs -f filelist.f \
		-timescale=1ns/100ps \
		-full64 +v2k -sverilog -Mupdate +define+DUMP_VPD \
		-debug_all \
		|tee vcs.log
#---------------------------------------------------------------
com_fsdb:
	vcs -f filelist.f \
		-timescale=1ns/100ps \
		-full64 +v2k -sverilog -Mupdate +define+DUMP_FSDB \
		-debug_acc+all -debug_region+cell+encrypt \
		|tee vcs.log
#---------------------------------------------------------------
sim:
	./simv |tee sim.log
#---------------------------------------------------------------
dve:
	dve -vpd vcdplus.vpd -script ./scripts/dve.tcl &
#---------------------------------------------------------------
verdi:
	verdi -f filelist.f -ssf tb_top.fsdb -play ./scripts/verdi.tcl &
#---------------------------------------------------------------
clean:
	rm -rf csrc DVEfiles novas* *.log simv* *fsdb* ucli.key *.vpd verdiLog

