#!/bin/bash

if [ $# -eq 0 ]
  then
    sudo /Applications/MATLAB_R2014a.app/bin/matlab -nodesktop -r StartServerPlayer
else
    sudo /Applications/MATLAB_R2014a.app/bin/matlab -nodesktop -r "StartServerPlayer($1)"
fi
