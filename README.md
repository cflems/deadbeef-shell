# deadbeef-shell
===  
The deadbeef shell is a fast, minimalist shell written in x86_64 
Assembly for Linux. Currently it contains two builtins: cd and exit. It 
can execute any program as a direct path (/path/to/program), from the PATH 
variable (progam) or as a relative path (./program). Arguments are 
separated by spaces.  
To do (lowest to highest priority):  
 - Implement environment variables, pass them to programs and provide 
 export.
 - Implement variables ($variablename).
 - Implement providing a file as an argument instead of stdin so that the 
 shell can be used as an interpreter.  
 - Implement speech marks to separate arguments.  
