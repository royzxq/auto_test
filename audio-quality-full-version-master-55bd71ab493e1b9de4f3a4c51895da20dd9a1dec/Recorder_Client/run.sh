#!/bin/bash

if [ $# -eq 0 ]
  then
    sudo /Applications/MATLAB_R2014a.app/bin/matlab -nodesktop -r StartClientRecorder
else
	sudo /Applications/MATLAB_R2014a.app/bin/matlab -nodesktop -r "StartClientRecorder('$1')"
fi