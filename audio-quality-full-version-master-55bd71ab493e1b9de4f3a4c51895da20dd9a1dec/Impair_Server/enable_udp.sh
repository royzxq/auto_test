# !/bin/bash

# pj1 mmp02
sudo iptables -D FORWARD -p udp -d 10.194.247.50 -j DROP
sudo iptables -D FORWARD -p udp -s 10.194.247.50 -j DROP

# pj1 mmp01
sudo iptables -D FORWARD -p udp -d 10.194.255.248 -j DROP
sudo iptables -D FORWARD -p udp -s 10.194.255.248 -j DROP
sudo iptables -D FORWARD -p udp -d 10.194.255.250 -j DROP
sudo iptables -D FORWARD -p udp -s 10.194.255.250 -j DROP

# pj2 mmp09
sudo iptables -D FORWARD -p udp -d 172.24.93.167 -j DROP
sudo iptables -D FORWARD -p udp -s 172.24.93.167 -j DROP

# pj2 mmp10
sudo iptables -D FORWARD -p udp -d 172.24.93.170 -j DROP
sudo iptables -D FORWARD -p udp -s 172.24.93.170 -j DROP

sudo iptables -L -n --line-numbers

