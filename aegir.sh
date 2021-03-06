#!/bin/sh
version=0.22

echo " `basename $0` $version"

#Instructions from http://community.aegirproject.org/installing/manual

#this script is only for redhat based systems
#this script has only been tested on CentOS 5 & 6 systems

if ! [ -s /etc/redhat-release ] #assuming this is sufficient
then 
	echo " ERROR: This is _NOT_ a Redhat based distribution. Quitting"
	exit 1
fi
echo "بسم الله الرحمن الرحيم"

#variables
export WEBHOME=/var/aegir

if [ -s /etc/centos-release ] 
then
        os=centos
        grep 6 /etc/centos-release > /dev/null && version=6 || version=5
else
        os=rhel
        grep 6 /etc/redhat-release > /dev/null && version=6 || version=5
fi

interface=eth0

[ "$version" -eq "5" ] && yum -y erase php php-common
[ "$version" -eq "5" ] && yum -y install httpd postfix sudo unzip mysql-server php53 php53-pdo php53-process php53-mysql git php53-mbstring bzr cvs php53-gd php53-xml || yum -y install httpd postfix sudo unzip mysql-server php php-pdo php-process php-mysql git php-mbstring bzr cvs php-gd php-xml

echo " INFO: Raising PHP's memory limit to 512M"
sed -i 's/^memory_limit = .*$/memory_limit = 512M/g' /etc/php.ini 
export city=`cat /etc/sysconfig/clock | grep ZONE | cut -d= -f2 | sed -s 's/"//g'`
sed -i 's+;date.timezone =+date.timezone = '$city' +g' /etc/php.ini

echo " INFO: Restarting httpd and mysqld"
service httpd restart
service mysqld restart

chkconfig httpd on
chkconfig mysqld on

mysql -uroot -e 'show databases;' > /dev/null 2>&1
if [ $? -eq 0 ]
then 
	/usr/bin/mysql_secure_installation
else
	echo " INFO: MySQL previous configured. Skipping"
fi

echo " INFO: Disabling SElinux"
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
echo 0 >/selinux/enforce

echo " INFO: AEgir User creation"
useradd --home-dir $WEBHOME aegir
gpasswd -a aegir apache
chmod -R 755 $WEBHOME

! [ -d $WEBHOME ] && mkdir $WEBHOME 
chown aegir.apache $WEBHOME

grep aegir /etc/sudoers > /dev/null
if ! [ $? -eq 0 ]
then
        echo "aegir ALL=NOPASSWD: /usr/sbin/apachectl" >> /etc/sudoers
        sed -i 's/^Defaults    requiretty/#Defaults    requiretty/g' /etc/sudoers
fi

if ! [ -d /etc/httpd/conf.d/aegir.conf ]
then 
        ln -s $WEBHOME/config/apache.conf /etc/httpd/conf.d/aegir.conf
fi

#dns configuration - add to /etc/hosts
hostfile(){
echo " INFO: Adding `hostname` entry to /etc/hosts"
ip=`ifconfig $interface | grep -w inet | awk '{print $2}' | cut -d: -f2`
echo "$ip\t`hostname`" >> /etc/hosts
}

host `hostname` > /dev/null
if ! [ $? -eq 0 ]
then
	grep `hostname` /etc/hosts > /dev/null
	if ! [ $? -eq 0 ]
	then
		hostfile
	else
		echo " ERROR: `hostname` does not resolve even though it is /etc/hosts"
	fi
fi

echo " INFO: Switching to aegir user"
su -c -l aegir '
#the below line enables bash debugging
#set -x

export DRUSH_VERSION=7.x-4.5
#export DRUSH_VERSION=7.x-4.6
export WEBHOME=/var/aegir
export HOME=$WEBHOME
export drush="$HOME/bin/drush/drush" 
export DRUPAL_VER=6.x

#the following is the fqdn of the aegir front end
export AEGIR_HOST=`hostname`
export AEGIR_DB_PASS=password
export EMAIL=root@`hostname`

#downloading drush
mkdir ~/bin/
cd $HOME/bin
wget http://ftp.drupal.org/files/projects/drush-$DRUSH_VERSION.tar.gz 
gunzip -c drush-$DRUSH_VERSION.tar.gz | tar -xf -
rm -rf drush-$DRUSH_VERSION.tar.gz

#set up the alias for drush
grep drush $HOME/.bashrc > /dev/null
if ! [ $? -eq 0 ]
then
	echo "alias drush='$WEBHOME/bin/drush/drush'" >> $HOME/.bashrc
fi

grep vi $HOME/.bashrc > /dev/null
if ! [ $? -eq 0 ]
then
cat >> $HOME/.bashrc << EOF
alias vi=vim
alias grep="grep --colour=auto"
EOF
fi

. $HOME/.bashrc

cd $HOME
#get the latest version of drush before starting 
$drush -y self-update

#echo " INFO: Installing Drupal $DRUPAL_VER"
#$drush --destination=$HOME dl drupal-$DRUPAL_VER

echo " INFO: Installing drupal module : provision"
$drush -y dl --destination=$HOME/.drush provision-6.x

echo  " INFO: Running hostmaster install"
$drush -y hostmaster-install $AEGIR_HOST --aegir_db_pass=$AEGIR_DB_PASS --client_email=$EMAIL

ln -s $HOME/hostmaster* hostmaster

#prepare crontab
echo " INFO: Updating crontab"
crontab -l | grep up > /dev/null 2>&1
if ! [ $? -eq 0 ]
then
	crontab -l > /tmp/cron.aegir
	echo "0 3 * * * /var/aegir/bin/drush/drush -y @hostmaster up" >> /tmp/cron.aegir
	echo "29 * * * * /var/aegir/bin/drush/drush -y @hostmaster cron" >> /tmp/cron.aegir
	echo "45 1 * * * /var/aegir/bin/drush/drush -y @sites up" >> /tmp/cron.aegir
	crontab /tmp/cron.aegir
	rm -rf /tmp/cron.aegir
fi

echo "************************************************************************"
echo " INFO: Updating Drupal installation"
#enable the update module
#$drush -y -r /var/aegir/hostmaster -l http://$AEGIR_HOST en update
$drush -y @hostmaster en update
#do the update
#$drush -y -r /var/aegir/hostmaster -l http://$AEGIR_HOST up
$drush -y @hostmaster up

echo "************************************************************************"
echo " INFO: Installation complete. Please read email for $EMAIL to continue"
echo "************************************************************************"
'
