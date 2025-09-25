#!/bin/bash

# Exit if this isn't being run on a Raspberry Pi
rpi=`cat /proc/device-tree/model | grep -c "Raspberry Pi"`
if [ $rpi -eq 0 ]; then
    echo ">>> WARNING: This is not a Raspberry Pi. <<<"
    echo ">>> Manual installation of ShootPoints-Web is advised. <<<"
    exit 1
fi

# Create a local WiFi network named "shootpoints"
sudo raspi-config nonint do_wifi_country US
sudo apt-get update
sudo apt-get install -y ifupdown hostapd dnsmasq

echo 'cat << EOF > /etc/hostapd/hostapd.conf
country_code=US
interface=wlan0
ssid=shootpoints
hw_mode=g
channel=11
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
rsn_pairwise=CCMP
EOF' | sudo -s

sudo sed -i -e 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd\.conf"/g' /etc/default/hostapd

echo 'cat << EOF >> /etc/dhcpcd.conf
interface eth0

interface wlan0
static ip_address=192.168.111.1
static routers=192.168.111.1
static domain_name_servers=192.168.111.1
EOF' | sudo -s

echo 'cat << EOF >> /etc/dnsmasq.conf
interface=wlan0
domain-needed
bogus-priv
dhcp-range=192.168.111.100,192.168.111.200,48h
server=8.8.8.8
no-hosts
addn-hosts=/etc/dnsmasq.hosts
EOF' | sudo -s

echo 'echo '192.168.111.1 shootpoints' > /etc/dnsmasq.hosts' | sudo -s

echo 'cat << EOF > /etc/network/interfaces.d/wlan0
auto wlan0
iface wlan0 inet static
  address 192.168.111.1
  netmask 255.255.255.0
  broadcast 192.168.111.255
  dns-nameservers 192.168.111.1
EOF' | sudo -s

sudo sed -rie 's/(ExecStart.*)/\1\nExecStartPre=\/usr\/bin\/sleep 15/g' /lib/systemd/system/hostapd.service
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl start hostapd


# Enable external LED for activity indicator
echo 'cat << EOF >> /boot/firmware/config.txt
dtparam=act_led_trigger=default-on
dtparam=act_led_gpio=26
EOF' | sudo -s


# Install python and git
sudo apt-get -y install python3-pip git


# Add shootpoints user to group with serial port access
sudo usermod -a -G dialout shootpoints


# Install ShootPoints and its dependencies
echo 'export PATH=/home/shootpoints/.local/bin:$PATH' >> /home/shootpoints/.bashrc
export PATH=/home/shootpoints/.local/bin:$PATH
git clone --recurse-submodules https://github.com/Lugal-PCZ/ShootPoints-Web.git
cd /home/shootpoints/ShootPoints-Web
git submodule foreach git switch main
python3 -m pip config set global.break-system-packages true
pip3 install -r api/requirements.txt


# Set ShootPoints to start automatically on boot
echo 'cat << EOF > /etc/systemd/system/shootpoints.service
[Unit]
Description=ShootPoints Web Service
After=network-online.target

[Service]
ExecStart=/home/shootpoints/.local/bin/uvicorn api:app --host 0.0.0.0
WorkingDirectory=/home/shootpoints/ShootPoints-Web/api
StandardOutput=inherit
StandardError=inherit
Restart=always
User=shootpoints

[Install]
WantedBy=multi-user.target
EOF' | sudo -s

sudo systemctl enable shootpoints
sudo systemctl start shootpoints


# Create ShootPoints-Web updater script
echo 'cd /home/shootpoints/ShootPoints-Web
git pull --recurse-submodules
git submodule foreach git switch main
git submodule foreach git pull
sudo systemctl restart shootpoints' > /home/shootpoints/update-shootpoints.sh
chmod +x /home/shootpoints/update-shootpoints.sh


# Indicate that the script is finished running
echo ">>> ShootPoints-Web is installed. <<<"
echo ">>> Restart the Raspberry Pi with “sudo reboot” then in a minute or so:"
echo ">>>  - Connect to the shootpoints WiFi network <<<"
echo ">>>  - Open a browser to http://shootpoints.local:8000 <<<"
