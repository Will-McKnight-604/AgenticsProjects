.include test.sp
.control
set filetype=ascii
op
write output.raw
wrdata output.csv v(1)
quit
.endc
