# `sed` Quick Reference

## Command Keywords

- `''`: pattern
- `-n`: don't print by default
- `-e`: separates patterns

## Pattern commands

- `;`: separate commands within a pattern
- `s/[TEXT1]/[TEXT2]/`: substitute instances of TEXT1 with TEXT2
  - `[s EXPRESSION]/p`: print lines affected by substitution
  - `[s EXPRESSION]/I`: ignore case in substitution
- `y/[TEXT1]/[TEXT2]/`: substitute instances of TEXT1 with TEXT2 at a character level
- `{}`: group commands
- `$`: range to the end of the file
- `=`: print line number and line
- `n`: goto next line
- `p`: print contents of pattern space
- `d`: delete contents of pattern space
- `N`: pull next line into pattern space
- `P`: print first line of pattern space
- `D`: delete first line of pattern space
- `q`: stop execution of all patterns

## Examples

`sed -e 's/volt.*//' -e 's/^.*estimated_left_p/left_p/'`

***OR***

`sed 's/volt.*//; s/^.*estimated_left_p/left_p/'`
Remove all instances of "volt", replace all instances of "estimated_left_p" with "left_p"

`sed -n 'p'`
Print all lines

`sed -n '1,2p'`
Print first two lines

`sed -n '1,2d'`
Print all but first two lines

`sed -n 'd; p'`
Nothing: delete all in pattern space and then print pattern space

`sed -n 's/this/thing/'`
Replace this with thing

`sed -n 's/this//'`
Remove all instances of this

`sed -n 'y/ab/cd/'`
Replace a with c nd b with d

`sed -n '1,2s/this/thing/'`
Replace this with thing on lines 1 and 2

`sed -n '1,2 {s/this/thing/; p}'`
Replace this with thing on lines 1 and 2 and print those lines

`sed -n '1,2 {s/this/thing/p}'`
Replace this with thing on lines 1 and 2 and print lines that were modified

`sed '='`
Print all lines with line numbers

`sed '$='`
Print number of lines in current file

`sed '=; n'`
Alternate printing line numbers and not with the lines

`sed -n '=; n'`
Alternate printing line numbers

`sed -n '=; n; p'`
alternate printing line numbers and line