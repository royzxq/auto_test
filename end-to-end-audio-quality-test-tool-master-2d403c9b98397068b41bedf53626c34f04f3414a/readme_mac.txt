====== End-to-End Audio Quality Testing Tool for Mac OSX ========

1. Run-Time Library for MATLAB 

This tool was developed and compiled by MATLAB and thus needs the 
MATLAB Compiler Runtime (MCR) installed before execution. Make sure   
you have installed version 8.3 (R2014a). If the MCR is not installed,
download the Macintosh version of the MCR for R2014a from the MathWorks 
Web site by navigating to

   http://www.mathworks.com/products/compiler/mcr/index.html
   
For more information about the MCR and the MCR Installer, see 
Distribution to End Users in the MATLAB Compiler documentation  
in the MathWorks Documentation Center.    

NOTE: You will need administrator rights to run MCRInstaller. 


2. Fix the Curl Bugs on MCR

The program uses curl command to get the scores from the POLQA server. However
It has been known that MCR 8.3 has bugs when using curl. To fix this, just delete
libcurl files in the MCR directory to force the program to use default curl.

First, determine <mcr_root> where MCR is installed, the default could be 
	
    /Applications/MATLAB/MATLAB_Compiler_Runtime/v83/

Then, do as follows:

    sudo rm <mcr_root>/bin/maci64/libcurl.dylib
    sudo rm <mcr_root>/bin/maci64/libcurl.4.dylib

	
3. Install Virtual Cable

If you want to use this program to play reference audio to the local 
WebEx or/and to record the sound from the local WebEx, you need to 
install a Virtual Cable software Sound Siphone available at:

    http://staticz.com/soundsiphon/


4. Usage of Playback Server

You may find four files in the Playback_Server package:

   (1) run.sh -> The entry to run ServerPlayer
   (2) ServerPlayer -> The main program, but not directly executable
   (3) test.wav -> The example audio file for measuring the player delay, 
                   as the player delay is variable on different machines
   (4) readme.txt -> Information about how to use the tool

Example on Terminal prompt: 

   >> sudo sh run.sh <mcr_root>

   opening a server with default port 12999 and default audio device: 
   Sound Siphon

   >> sudo sh run.sh <mcr_root> 11111 

   opening a server with the specified port 11111 but using the 
   default audio device: Sound Siphon


   
5. Usage of Recorder Client

You may find five files in the Recorder_Client package:

  (1) run.sh -> The entry to run ClientRecorder
  (2) ClientRecorder -> The main program, but not directly executable
  (3) speech.wav -> The examplar reference audio file for testing the 
                    audio quality, you may change the file
  (4) config_temp -> A default template for the configuration, below you 
                     will find how to edit the file
  (5) readme.txt -> Information about how to use the tool

ClientRecorder should be executed after the server is open. It by default 
loads the configuration file "config_temp"

   config_temp (configuration template):

     IP = '127.0.0.1';  % IP address of the server
     Port = 12999;  % port number
     ref_audio_name = 'speech.wav';  % Reference audio file name
     max_play_count = 10;  % Number of playback repeats
     sil_duration_between_playbacks = 2;  % in second, duration between two repeats
     record_device_name = ''; % Name of the local recording device, leave empty as using the default
     playback_device_name = ''; % Name of the server playback device, leave empty as using the default
	 
	 NOTE: audio device name can be any sub-string in the name of the device you want to use. 
	 For example, for Mac built-in audio device, you may use "built-in" as the name.

Example on Terminal prompt: 

   >> sudo sh run.sh <mcr_root>

   opening a client with default configuration file "config_temp"

   >> sudo sh run.sh <mcr_root> config1.txt 

   opening a client with the optional configuration file "config1.txt"

