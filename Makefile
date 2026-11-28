# t27-lamb-labs — one-command DX over the lab's acceptance gates.
#
# Every target is host-verifiable (iverilog/yosys/python3/t27c on PATH).
# Board-side work (Vivado Tcl, Kria probes) stays manual by design: see EXECUTE_NOW.md.
# Targets never write inside the tracked tree (logs go to /tmp, synth outputs to a
# /tmp stack root) so `make regress` G5 tree-drift stays meaningful.

SHELL := /bin/bash
DATE := $(shell date +%Y%m%d_%H%M%S)
STACK_TMP := /tmp/fpga_stack_$(DATE)

.PHONY: help regress verilog conformance verify test-reports stack-synth stack-bestimate clean

help:
	@echo "make regress       - all 5 acceptance gates G1-G5 (log -> /tmp, verdict tail)"
	@echo "make verilog       - t27c_lite.py: .t27 spec -> Verilog, bit-exact, yosys clean"
	@echo "make conformance   - conformance pack (Tier A RTL, Tier B golden, Tier B2 dot27)"
	@echo "make verify        - portfolio acceptance rules (verify_portfolio.py)"
	@echo "make test-reports  - t27c test-report over every specs/**/*.t27"
	@echo "make stack-synth   - yosys synth_xilinx over fpga/stack rtl (counter, fir4) in /tmp"
	@echo "make clean         - remove /tmp scratch roots created by this Makefile"

regress:
	OUT=/tmp/regress_$(DATE).log bash scripts/regress_all.sh
	@echo "--- verdict ---"
	@grep -E "G[0-9]+: (PASS|FAIL)|REGRESSION" /tmp/regress_$(DATE).log

verilog:
	python3 t27c_lite.py

conformance:
	python3 conformance/run_conformance.py

verify:
	python3 scripts/verify_portfolio.py

test-reports:
	@set -euo pipefail; fail=0; n=0; \
	while IFS= read -r -d '' f; do n=$$(($$n+1)); \
	  if ! timeout 90 t27c test-report "$$f" >/tmp/t27c_report_$$(basename $$f).log 2>&1; then \
	    fail=$$(($$fail+1)); echo "FAIL ($$?) $$f"; else \
	    echo "PASS $$f"; fi; \
	done < <(find specs -name '*.t27' -print0); \
	echo "test-reports: $$((n-fail))/$$n specs green"; [ $$fail -eq 0 ]

stack-synth:
	@rm -rf $(STACK_TMP) && mkdir -p $(STACK_TMP)
	@cp -r fpga/stack/rtl fpga/stack/scripts $(STACK_TMP)/
	@bash fpga/stack/scripts/run_stack.sh $(STACK_TMP) $(CURDIR)/fpga/stack/rtl/counter.v counter
	@bash fpga/stack/scripts/run_stack.sh $(STACK_TMP) $(CURDIR)/fpga/stack/rtl/fir4.v fir4
	@echo "results in $(STACK_TMP)/results (untracked scratch, not repo evidence)"

stack-bestimate:
	t27c gen specs/fpga/bestimate_stat.t27 > /tmp/bestimate_stat.zig
	zig build-exe /tmp/bestimate_stat.zig -lc -femit-bin=/tmp/bestimate_stat
	@for f in fpga/stack/results/*.stat; do \
	  /tmp/bestimate_stat < "$$f" > "$${f%.stat}.bestimate.json"; \
	  echo "$$f -> $$(cat $${f%.stat}.bestimate.json)"; \
	done
	@echo "evidence updated in fpga/stack/results/ (commit with manifest refresh)"

clean:
	rm -rf /tmp/fpga_stack_* /tmp/regress_*.log /tmp/t27c_report_*.log
