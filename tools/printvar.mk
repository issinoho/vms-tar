# Used as an extra makefile to print a fully expanded make variable:
#   make -f Makefile -f printvar.mk print-VAR
print-%:
	@echo $($*)
