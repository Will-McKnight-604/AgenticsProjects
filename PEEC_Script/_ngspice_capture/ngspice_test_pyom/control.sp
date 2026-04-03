* Control script for batch simulation
.include C:\tmp\ngspice_test_pyom\circuit.cir

.control
set filetype=ascii
run
write C:\tmp\ngspice_test_pyom\output.raw all
wrdata C:\tmp\ngspice_test_pyom\output.csv all
quit
.endc
.end
