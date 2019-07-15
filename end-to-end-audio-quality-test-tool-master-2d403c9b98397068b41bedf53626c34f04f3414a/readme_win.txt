====== End-to-End Audio Quality Testing Tool for Windows ========

1. Run-Time Library for MATLAB 

This tool was developed and compiled by MATLAB and thus needs the 
MATLAB Compiler Runtime (MCR) installed before execution. Make sure   
you have installed MCR version 8.1. If the MCR is not installed, 
download the Windows 64-bit version of the MCR for R2013a from the 
MathWorks Web site by navigating to

   http://www.mathworks.com/products/compiler/mcr/index.html
   
For more information about the MCR and the MCR Installer, see 
Distribution to End Users in the MATLAB Compiler documentation  
in the MathWorks Documentation Center.    

NOTE: You will need administrator rights to run MCRInstaller. 


2. Install Virtual Cable

If you want to use this program to play reference audio to the local 
WebEx or/and to record the sound from the local WebEx, you need to 
install a Virtual Cable software: VB-Audio Virtual Cable available at:

	http://vb-audio.pagesperso-orange.fr/Cable/

	
3. Usage of Playback Server

You may find three files in the Playback_Server package:

   (1) ServerPlayer.exe -> The main program
   (2) test.wav -> The example audio file for measuring the player delay, 
                   as the player delay is variable on different machines
   (3) readme.txt -> Information about how to use the tool


Example on Windows command prompt: 

   >> ServerPlayer 

   opening a server with default port 12999 and default audio device: 
      VB-Audio Virtual Cable

   >> ServerPlayer 11111 

   opening a server with the specified port 11111 but using the 
   default audio device: VB-Audio Virtual Cable

	  
4. Usage of Recorder Client

You may find five files in the Recorder_Client package:

  (1) ClientRecorder.exe -> The main program
  (2) speech.wav -> The examplar reference audio file for testing the 
                    audio quality, you may change the file
  (3) config_temp -> A default template for the configuration, below you 
                     will find how to edit the file
  (4) curl.exe -> The curl program used for obtaining the scores
  (5) readme.txt -> Information about how to use the tool

ClientRecorder should be executed after the server is open. It by default 
loads the configuration file "config_temp"

   >> ClientRecorder <optional configuration file name>
	
   config_temp (configuration template):

     IP = '127.0.0.1';  % IP address of the server
     Port = 12999;  % port number
     ref_audio_name = 'speech.wav';  % Reference audio file name
     max_play_count = 10;  % Number of playback repeats
     sil_duration_between_playbacks = 2;  % in second, duration between two repeats
	 record_device_name = ''; % Name of the local recording device, leave empty as using the default
	 playback_device_name = ''; % Name of the server playback device, leave empty as using the default

	 NOTE: audio device name can be any sub-string in the name of the device you want to use. 
	 For example, using an audio device by specifying "Realtek High Definition"
	 
Example on Windows command prompt: 

   >> ClientRecorder

   opening a client with default configuration file "config_temp"

   >> ClientRecorder config1.txt 

   opening a client with configuration file "config1.txt"