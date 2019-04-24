prgmFASTER
prgmFASTEST
10 June 2015

    This minor utility will make your calculator slightly faster, about 15 to
30 %, depending on whether you run FASTER or FASTEST.  Turning the calculator
off will cancel the effect.  It also enables entering lower-case letters.  If
you don't like lower-case, you can disable it by opening the program in the
program editor and changing it from FDCB24DE to FDCB249E, or by deleting the
fourth line entirely.

    To run the program, on the homescreen, press 2nd+0 to bring up the Catalog
menu, and then select Asm( from the menu to paste it to the homescreen.  Then
select prgmFASTER from the PRGM menu to get
Asm(prgmFASTER
on the homescreen, and then run it.

    There is a chance that FASTEST will cause random crashes on some calculators
due to flash read failures if the flash chip happens to be on the low end of the
specified performance range.  If you think FASTEST is causing crashes, try using
FASTER instead.

    The speed boost comes from changing the wait-states setting for the flash.
The calculator's CPU actually runs fairly fast for a Z80-compatible CPU, but the
OS is located in flash memory (which also contains your archive space), and all
code executing there is severely hobbled by a 9 wait-state penalty, reducing the
effective clock speed by nearly a factor of 10.  This program decreases the
wait-states to 6.  (The hardware allows a minimum of 5, but that crashes my
calculator.  4 should work according to the flash chip's datasheet, but only if
you make some assumptions about signal hold times and TI's designed bus topology
which are apparently not true.)


Change log:
10 June 2015
 - Update now has two programs.  The maximum speed boost is now provided by
   FASTEST, while a new FASTER program sets 7 wait states instead of 6.
7 April 2015
 - Initial release.  First community assembly program.