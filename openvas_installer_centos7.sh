#!/bin/bash --

# openvas_installer_centos7.sh
#
# Copyright (C) 2017  umair siddiqui (umair siddiqui 2011 @ gmail)
#
# OpenVAS install script for RHEL/CentOS 7    
#  
#
##########################################################################
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

if [ "x$(id -u)" != 'x0' ]; then
   echo $0 requires root/sudo
   exit 1
fi


sudo yum install -y epel-release

sudo yum install -y openvas-manager openvas-scanner openvas-cli openvas-gsa redis.x86_64 bzip2 wget net-tools texlive-latex-bin nmap alien mingw32-nsis texlive-collection-xetex texlive-collection-latexrecommended texlive-collection-htmlxml.noarch texlive-thumbpdf-bin.noarch texlive-dvipdfm texlive-dvipdfmx texlive-pdfpages.noarch texlive-epstopdf.noarch

# edit redis conf
sudo sed -i -r '/unixsocket([[:space:]]+)/s/^.*/unixsocket \/run\/redis\/redis.sock/' /etc/redis.conf

sudo sed -i -r '/unixsocketperm/s/^([[:space:]]*)#([[:space:]]*)//' /etc/redis.conf


sudo sed -i -r '/^([[:space:]]*)port/s/[0-9]+/0/' /etc/redis.conf

sudo systemctl enable redis
sudo systemctl start redis

# edit openvassd.conf

if [[ "0" == $(grep -c kb_location /etc/openvas/openvassd.conf) ]]; then 
    sudo echo -e "kb_location = /run/redis/redis.sock" >> /etc/openvas/openvassd.conf
else
    sudo sed -i -r '/kb_location/s/=.*/= \/run\/redis\/redis.sock/' /etc/openvas/openvassd.conf
fi

sudo sed -i "/nasl_no_signature_check/s/yes/no/" /etc/openvas/openvassd.conf


#create SSL certificates for OpenVAS 
sudo openvas-mkcert -q

#create a client certificate for a user named "om" this stands for OpenVAS Manager.
sudo rm -rf /tmp/openvas-mkcert-client*
sudo openvas-mkcert-client -n om -i


# copy client certificate
sudo cp /tmp/openvas-mkcert-client*/key_om.pem /etc/pki/openvas/private/CA/clientkey.pem
sudo cp /tmp/openvas-mkcert-client*/cert_om.pem /etc/pki/openvas/CA/clientcert.pem


# edit this line: GSA_LISTEN=--listen=127.0.0.1

sudo sed -i -r '/GSA_LISTEN/s/^([[:space:]]*)#//' /etc/sysconfig/openvas-gsa
sudo sed -i -r '/GSA_LISTEN/s/127\.0\.0\.1/0\.0\.0\.0/' /etc/sysconfig/openvas-gsa


sudo sed -i -r '/GSA_PORT/s/[0-9]+/9392/' /etc/sysconfig/openvas-gsa

sudo sed -i -r '/MANAGER_LISTEN/s/^([[:space:]]*)#//' /etc/sysconfig/openvas-manager
sudo sed -i -r '/MANAGER_LISTEN/s/127\.0\.0\.1/0\.0\.0\.0/' /etc/sysconfig/openvas-manager

# selinux in permissive mode
sudo sed -i -r '/^SELINUX=/s/enforcing/permissive/' /etc/selinux/config
sudo setenforce 0

sudo systemctl stop openvas-manager.service
sudo systemctl stop openvas-scanner.service

sudo cp /usr/lib/systemd/system/openvas-*.service /etc/systemd/system/
sudo sed -i -r '/RestartSec/s/=.*/=10/' /etc/systemd/system/openvas-*.service

sudo systemctl disable openvas-manager.service
sudo systemctl disable openvas-scanner.service

# Update the network vulnerability tests database 
sudo openvas-nvt-sync

# 
sudo mkdir -p /etc/openvas/gnupg

sudo openvassd

sudo openvasmd --rebuild --progress

# sync security content automation protocol (scap) data 
sudo openvas-scapdata-sync

# sync cert data
sudo openvas-certdata-sync


# create acount admin
sudo openvasmd --create-user=admin --role=Admin

# set admin passwd = my_admin_passwd
sudo openvasmd --user=admin --new-password=my_admin_passwd


# open port 9392 
sudo firewall-cmd --add-port=9392/tcp --permanent
sudo firewall-cmd --reload


# add cron job
SCR_FILE=/etc/cron.daily/openvas_update.sh

(

cat<<'EOF'
#!/bin/bash

function run_cmd() {
    cmd=$1
    if [[ -t 0 || -p /dev/stdin ]] ; then
        $cmd
    else
        temp=`mktemp`
        $cmd 2>&1> $temp
        if [ $? -ne  0 ] ; then
            cat $temp
            exit 0
        fi
    fi
}

echo -e "Updating OpenVAS database..."

run_cmd openvas-nvt-sync

openvasmd --rebuild 

run_cmd openvas-scapdata-sync
run_cmd openvas-certdata-sync



systemctl restart openvas-scanner.service
systemctl restart openvas-manager.service
systemctl restart openvas-gsa.service

echo -e "OpenVAS database update...DONE"

EOF
) > $SCR_FILE

if [ -f "$SCR_FILE" ]
then
  chmod 755 $SCR_FILE
  cp $SCR_FILE /usr/local/bin
  chmod 755 /usr/local/bin/openvas_update.sh
else
  echo "Problem in creating file: \"$SCR_FILE\""
fi


# enable services
sudo systemctl enable openvas-manager.service
sudo systemctl enable openvas-gsa.service
sudo systemctl enable openvas-scanner.service


sudo systemctl start openvas-scanner.service
sudo systemctl start openvas-manager.service
sudo systemctl start openvas-gsa.service



sudo yum clean all

echo -e "=========================================================="
echo -e "-                OpenVAS Installed                       -"
echo -e "=========================================================="
echo -e "https://$(ip -4 addr show | grep -A1 'state UP' | grep inet | sed -r 's/.*inet (.*) brd/\1/' | awk -F/ '{print $1}'):9392/"
echo -e ""
echo -e "\nuserid: admin"
echo -e "\npassword: my_admin_passwd"
echo -e ""
echo -e ""
echo -e "=========================================================="
echo -e "to change Admin password"
echo -e "------------------------"
echo -e "sudo openvasmd --user=admin --new-password=YOUR_NEW_PASSWD"
echo -e "=========================================================="
echo -e ""








