@echo off
if [%1]==[] goto NO_ARG 
@echo StartClientRecorder('%1'); > tmp.m
start matlab -nosplash -nodesktop -r tmp
goto :eof 
:NO_ARG
start matlab -nosplash -nodesktop -r StartClientRecorder
goto :eof