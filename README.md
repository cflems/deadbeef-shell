# Weaponization Effort
===
The goal of the weaponization effort is to produce a shell code, similar to
those found on [shell-storm](http://shell-storm.org/shellcode/), injectable
directly into a buffer in the event that traditional options such as /bin/sh
become inaccessible. Shell codes are primarily used in overflow attacks, and
this project is merely an educational exercise. The authors of this project
do not condone any such attacks.

To do (lowest to highest priority):  
- Strip instructions resulting in 0x0 characters in the compiled output.
- Reduce total size and number of instructions.
