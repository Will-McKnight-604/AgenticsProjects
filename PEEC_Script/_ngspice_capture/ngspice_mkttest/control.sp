* Control script for batch simulation
.include C:\tmp\ngspice_mkttest\circuit.cir

.control
set filetype=ascii
run
write C:\tmp\ngspice_mkttest\output.raw all
wrdata C:\tmp\ngspice_mkttest\output.csv all
quit
.endc
.end
