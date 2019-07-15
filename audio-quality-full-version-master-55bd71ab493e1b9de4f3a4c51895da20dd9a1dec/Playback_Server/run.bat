@echo off
if [%1]==[] ( goto NO_ARG )
    matlab -nosplash -nodesktop -r StartServerPlayer(%1)
goto :eof 
:NO_ARG
matlab -nosplash -nodesktop -r StartServerPlayer
goto :eof