#!/bin/bash
set -e
# Exit on error
###############################################################################
# Script to compile and install calimero server + tool on an Orange Pi PC
# armbian based systems or Raspberry Pi rasbian systems
#  - installs a JDK
# 
# Michael Albert info@michlstechblog.info
# 09.04.2018
# 
#
# Currently state is experimental
# Script should also run on x86/x64 devices 
#
# License: Feel free to modify. Feedback (positive or negative) is welcome
#
# Changes:
# 20180525-120000: Workaround for calimero-core => Master requires Java 9
# 20180518-120000: symlink /opt/calimero-server/calimero-core-2.4-rc2.jar -> /opt/calimero-server/calimero-core-2.4-SNAPSHOT.jar
# 20180603-230000: calimero-device switched to 2.4/release branch
#                  copy jar with wildcards
#                  delete all calimero-core-2.4-*test*.jar from server path
# 20180625-053000: Checkout release/2.4 from calimero-rxtx and calimero-tools
# 20180629-053500: changed copy calimero-tools-2.4-*.jar instead of SNAPSHOT
# 20180702-054500: Removed detach server process from console patch and instead added new --no-stdin command line option to systemd service file. Set default KNX Address to a valid coupler address
# 20180706-054000: knxtools script adjusted to calimero-tools-2.4-rc2.jar
# 20190925-121000: Oracle Java -> OpenJDK
# 20200110-054500: Orange PI PC: Script adjusted for Armbian with Mainline Kernel 5.4.x
#
# please see https://github.com/Race666/calimero-server for the latest changes
#
# version:20200110-054000 
# 
#
###############################################################################
################################## Constants ##################################
export CALIMERO_BUILD=~/calimero-build
# export JAVA_LIB_PATH=/usr/java/packages/lib/arm
export CALIMERO_SERVER_PATH=/opt/calimero-server
export CALIMERO_TOOLS_PATH=/opt/calimero-tools
export CALIMERO_CONFIG_PATH=/etc/calimero
# Bin Path
export BIN_PATH=/usr/local/bin
# export SERIAL_INTERFACE=ttyS3
export SERIAL_INTERFACE_ORANGE_PI=ttyS3
export SERIAL_INTERFACE_RASPBERRY_PI=ttyAMA0
# Default, would be overwritten from hardware detection
export SERIAL_INTERFACE=ttyS0
# KNX_ROUTING => true or false
export KNX_ROUTING=true
# If routing is enabled set a valid Coupler KNX Address x.x.0
export KNX_ADDRESS="1.1.0"
# If routing disabled, set a KNX Device Address
# export KNX_ADDRESS="1.1.128"
export KNX_CLIENT_ADDRESS_START="1.1.129"
export KNX_CLIENT_ADDRESS_COUNT=8
# Network interface calimero bind to
# export LISTEN_NETWORK_INTERFACE=eth0
# If defined this network interface is used for outgoing connections. Comment it if the tunnel target is on the same subnet
export OUTGOING_NETWORK_INTERFACE_TUNNEL=eth0
export LISTEN_NETWORK_INTERFACE=eth0
# User to run Server
export CALIMERO_SERVER_USER=knx
# Group 
export CALIMERO_SERVER_GROUP=knx
# Application data directory
export CALIMERO_SERVER_APP_DATA=/home/$CALIMERO_SERVER_USER/.calimero-server
# KNX Server Name
export KNX_SERVER_NAME="Calimero KNXnet/IP Server"
# Branch to use 
export GIT_BRANCH="master"
export GIT_BRANCH_TOOLS="master"
# Temp dir for extracting archives after building
export CALIMERO_TMP="/tmp/calimero"


###############################################################################
# Usage
if [ "$1" = "-?" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ];then
	echo Usage $0 "[tpuart|usb|tunnel ip-tunnel-endpoint|clean][--keyring <pwd>]"
	echo "    clean              deletes directories" $CALIMERO_BUILD, $CALIMERO_TOOLS_PATH and $CALIMERO_SERVER_PATH
	echo "    --keyring <pwd>    configure KNX IP Secure using keyring in current directory"
	exit 0
fi
###############################################################################
# Check for root permissions
if [ "$(id -u)" != "0" ]; then
   echo "     Attention!!!"
   echo "     Start script must run as root" 1>&2
   echo "     Start a root shell with"
   echo "     sudo su -"
   exit 1
fi
################################# Parameters ##################################
# Connection to KNX Bus
if [ "$1" = "usb" ] || [ "$1" = "--usb" ];then
    echo Configure support for USB
    export KNX_CONNECTION=USB
elif [ "$1" = "tunnel" ] || [ "$1" = "--tunnel" ];then    
    echo Configure support for TUNNELING
    if [ ! -z "$2" ];then
        export KNX_CONNECTION=TUNNEL
        export PARAM_VALUE=$2
   		echo Tunnel Endpoint: $PARAM_VALUE
    else
        echo ERROR: A tunnel endpoint address must be specified!!!
        echo Example: $0 tunnel 192.166.200.200
		exit 4
    fi
elif [ "$1" = "clean" ]; then
	# Check on zero for $CALIMERO_BUILD to avoid "cleaning" the wrong directory
	if [ ! -z $CALIMERO_BUILD ] && [ -d $CALIMERO_BUILD ]; then
		if [[ $CALIMERO_BUILD == *"calimero"* ]]; then
			rm -r $CALIMERO_BUILD
		else
			echo $CALIMERO_BUILD does not seem to be a calimero-specific directory, please clean manually
		fi
	fi
	# Check on zero for $CALIMERO_SERVER_PATH to avoid "cleaning" the wrong directory
	if [ ! -z $CALIMERO_SERVER_PATH ] && [ -d $CALIMERO_SERVER_PATH ]; then
		if [[ $CALIMERO_SERVER_PATH == *"calimero"* ]]; then
			rm -r $CALIMERO_SERVER_PATH
		else
			echo $CALIMERO_SERVER_PATH does not seem to be a calimero-specific directory, please clean manually
		fi
	fi
	# Check on zero for $CALIMERO_TOOLS_PATH to avoid "cleaning" the wrong directory
	if [ ! -z $CALIMERO_TOOLS_PATH ] && [ -d $CALIMERO_TOOLS_PATH ]; then
		if [[ $CALIMERO_TOOLS_PATH == *"calimero"* ]]; then
			rm -r $CALIMERO_TOOLS_PATH
		else
			echo $CALIMERO_TOOLS_PATH does not seem to be a calimero-specific directory, please clean manually
		fi
	fi	
	exit 0
elif [ "$1" = "tpuart" ] || [ "$1" = "--tpuart" ];then
    echo Configure support for TPUART
    export KNX_CONNECTION=TPUART    
else
    echo Configure support for TPUART
    export KNX_CONNECTION=TPUART
fi

# Keyring option for KNX IP Secure
if [ "$1" = "--keyring" ] || [ "$2" = "--keyring" ];then
	files=( ./*.knxkeys )
	export KEYRING_FILENAME=${files[0]}
	export KEYRING=$(realpath $KEYRING_FILENAME)
	echo Configure server for KNX IP Secure using $KEYRING
	export KEYRING_PWD=${*: -1}
fi

########################## Determine Hardware #################################
# Old:sun8i=OrangePi PC  
# export HARDWARE_STRING_OPI=$(dmesg|grep Machine:|cut -d":" -f 2|xargs echo -n)
export HARDWARE_STRING_OPI=$(dmesg  | grep -i "Machine model" |  grep -oi "Orange Pi")
if [ ! -z "$HARDWARE_STRING_OPI" ]; then
	if [ "$HARDWARE_STRING_OPI" = "Orange Pi" ]; then
		echo "Orange Pi PC detected"
		export HARDWARE=Orange
		export SERIAL_INTERFACE=$SERIAL_INTERFACE_ORANGE_PI
	fi 
fi
# Raspberry 
if [ -z $HARDWARE ]; then
	export MODEL_STRING=$(tr -d '\0' </proc/device-tree/model)
	set +e
	dmesg |grep -i "Raspberry Pi" >  /dev/null
	if [ $? -eq 0 ]; then
		echo Raspberry Pi found!
		export HARDWARE=Raspi
		export SERIAL_INTERFACE=$SERIAL_INTERFACE_RASPBERRY_PI
	elif [[ $MODEL_STRING == *"Raspberry Pi"* ]]; then
		echo $MODEL_STRING found!
		export HARDWARE=Raspi
		export SERIAL_INTERFACE=$SERIAL_INTERFACE_RASPBERRY_PI
	fi
	set -e
fi
# Detect RPI 3
# Disable error handling
set +e
dmesg |grep -i "Raspberry Pi 3" > /dev/null
if [ $? -eq 0 ]; then
	echo Raspberry 3 found!
	export IS_RASPBERRY_3=1
fi
# Enable error handling
set -e
# x86 PC
set +e
arch|grep -i x86 > /dev/null
if [ $? -eq 0 ]; then
	echo Standard x86 PC found!
	export HARDWARE=X86
fi
set -e
# Check if Hardware is recognized
if [ -z $HARDWARE ]; then
	echo No supported Hardware detected
	exit 1
fi
######################## CPU Architecture #####################################
set +e
arch|grep -i arm > /dev/null
if [ $? -eq 0 ]; then
	echo CPU architecture ARM
	export ARCH=ARM
fi
arch|grep -i x86_64 > /dev/null
if [ $? -eq 0 ]; then
	echo CPU architecture x64
	export ARCH=X64
fi
set -e
if [ -z $ARCH ]; then
	echo Unknown CPU architecture $(arch)
	exit 2
fi

############################ Build Directory ##################################
if [ ! -d $CALIMERO_BUILD ]; then
	mkdir -p $CALIMERO_BUILD
fi 
# Server and config path
mkdir -p $CALIMERO_SERVER_PATH
mkdir -p $CALIMERO_TOOLS_PATH
mkdir -p $CALIMERO_CONFIG_PATH

########################## Required packages #################################
if [ -z "$(find /var/cache/apt/pkgcache.bin -mmin -120)" ]; then
apt-get -y update 
apt-get -y upgrade
fi
apt-get -y install setserial
apt-get -y install git
apt-get -y install build-essential cmake
apt-get -y install automake autoconf libtool 
apt-get -y install dirmngr 
apt-get -y install net-tools software-properties-common xmlstarlet debconf-utils crudini
apt-get -y install unzip
########################### Java ##############################################
set +e

# Install JDK >= 17
# Steps according to https://adoptium.net/en-GB/blog/2021/12/eclipse-temurin-linux-installers-available/

apt-get install -y wget apt-transport-https gnupg
wget -O - https://packages.adoptium.net/artifactory/api/gpg/key/public | apt-key add -
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list

apt-get update
apt-get install -y temurin-17-jdk

set -e
export JAVA_HOME_PATH=$(readlink -e /usr/bin/javac |sed -e's/\/bin\/javac//')

# Check for Java bin
if [ ! -f $JAVA_HOME_PATH/bin/java ]; then
    echo Java not found in path $JAVA_HOME_PATH!
	exit 6
fi	
# Get JavaLibPath for libserialcom.so
cat > $CALIMERO_BUILD/GetLibraryPath.java <<EOF
/* 
 * 
 * Prints 1 Path of java.library.path
 * 
 * created: 05.04.2018  info@michlstechblog.info
 * 
 * Changes:
 * 
 */
import java.util.Properties;
import java.util.Enumeration;

public class GetLibraryPath {
  public static void main(String args[]) {
		String JavaPath=System.getProperty("java.library.path");
		if(JavaPath.split(":").length >= 1)
			System.out.println(JavaPath.split(":")[0]);
		else
			System.exit(1);
  }
}
EOF

export JAVA_LIB_PATH=$(java $CALIMERO_BUILD/GetLibraryPath.java)
if [ ! -d $JAVA_LIB_PATH ]; then
	mkdir -p $JAVA_LIB_PATH
fi 

################################ User and group ###############################
# New User $CALIMERO_SERVER_USER 
# For accessing serial devices => User $CALIMERO_SERVER_USER dialout group
set +e
getent passwd $CALIMERO_SERVER_USER
if [ $? -ne 0 ]; then
	useradd $CALIMERO_SERVER_USER -s /bin/false -U -M -G dialout -d /home/$CALIMERO_SERVER_USER
fi	
set -e

# On Raspberry add user pi to group $CALIMERO_SERVER_GROUP
set +e
getent passwd pi
if [ $? -eq 0 ]; then
	usermod -a -G $CALIMERO_SERVER_GROUP pi
fi	
usermod -a -G $CALIMERO_SERVER_GROUP $(logname)
set -e

# Create home
if [ ! -d /home/$CALIMERO_SERVER_USER ]; then
	mkdir /home/$CALIMERO_SERVER_USER
fi	
chown -R $CALIMERO_SERVER_USER:$CALIMERO_SERVER_GROUP /home/$CALIMERO_SERVER_USER

# Create app data dir
if [ ! -d $CALIMERO_SERVER_APP_DATA ]; then
	mkdir -p $CALIMERO_SERVER_APP_DATA
fi	
chown -R $CALIMERO_SERVER_USER:$CALIMERO_SERVER_GROUP $CALIMERO_SERVER_APP_DATA


################################ USB ##########################################
# !!!! Not sure if requiered to access USB devices...!!!!
# Set permissions on USB devices
# http://knx-user-forum.de/342820-post9.html to access USB Devices as $GROUP
cat > /etc/udev/rules.d/90-knxusb-devices.rules <<EOF
# Siemens KNX
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0111", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0112", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
SUBSYSTEM=="usb", ATTR{idVendor}=="0681", ATTR{idProduct}=="0014", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Merlin Gerin KNX-USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0141", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Hensel KNX-USB Interface 
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0121", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Busch-Jaeger KNX-USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="145c", ATTR{idProduct}=="1330", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
SUBSYSTEM=="usb", ATTR{idVendor}=="145c", ATTR{idProduct}=="1490", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# ABB STOTZ-KONTAKT KNX-USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="147b", ATTR{idProduct}=="5120", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Feller KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0026", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# JUNG KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0023", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Gira KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0022", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Berker KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0021", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Insta KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0020", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Weinzierl KNX-USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0104", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Weinzierl KNX-USB Interface (RS232)
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0103", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Weinzierl KNX-USB Interface (Flush mounted)
SUBSYSTEM=="usb", ATTR{idVendor}=="0e77", ATTR{idProduct}=="0102", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Tapko USB Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="16d0", ATTR{idProduct}=="0490", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Hager KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0025", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# preussen automation USB2KNX
SUBSYSTEM=="usb", ATTR{idVendor}=="16d0", ATTR{idProduct}=="0492", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Merten KNX-USB Data Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="135e", ATTR{idProduct}=="0024", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# b+b EIBWeiche USB
SUBSYSTEM=="usb", ATTR{idVendor}=="04cc", ATTR{idProduct}=="0301", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# MDT KNX_USB_Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="16d0", ATTR{idProduct}=="0491", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Siemens 148/12 KNX Interface
SUBSYSTEM=="usb", ATTR{idVendor}=="0908", ATTR{idProduct}=="02dd", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Zennio KNX Interface, e.g., ZN1SY-USBP
SUBSYSTEM=="usb", ATTR{idVendor}=="28c2", ATTR{idProduct}=="0002", ACTION=="add", GROUP="$CALIMERO_SERVER_GROUP", MODE="0664"
# Low Latency for  Busware TUL TPUART USB
ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="204b", KERNELS=="1-4", SYMLINK+="ttyTPUART", RUN+="/bin/setserial /dev/%k low_latency", GROUP="dialout", MODE="0664"
# Test rules example:
# udevadm info --query=all --attribute-walk --name=/dev/ttyS0
# udevadm test /dev/ttyS0 
# ACTION=="add",SUBSYSTEM=="tty", ATTR{port}=="0x3F8",SYMLINK+="ttyTPUART1",RUN+="/bin/setserial /dev/%k low_latency", GROUP="dialout", MODE="0664"
EOF

# clones the repo if the directory doesn't exist, otherwise pulls while preserving local changes
# $1 name of repository, $2 is the branch to checkout
clone_update_repo() {
	echo ""
	if [ -d $1 ]; then
		cd $1

		# make sure we have a user for git
		git config user.name "$(whoami)"
		git config user.email "$(whoami)@rpi"

		echo "update $1, preserve local changes"

		ts=$(date +%s) # timestamp the stash
		msg=$(git stash save $ts " local changes before updating from upstream")
		if [ ! -z $2 ]; then
			git fetch --all
			git checkout $2
		fi
		git pull

		# check if we stashed anything
		ret=$(grep -q "$ts" <<< "$msg") || true
		ret=$?
		if [ "$ret" -eq 0 ] ; then
			git stash pop || true
		fi
	else
		git clone https://github.com/calimero-project/$1 $1
		cd $1
		git fetch --all
		if [ ! -z $2 ]; then
			git checkout $2
		fi
	fi
}

############################# Build ###########################################
# calimero-core
cd $CALIMERO_BUILD
clone_update_repo calimero-core $GIT_BRANCH

# calimero device
cd $CALIMERO_BUILD
clone_update_repo calimero-device $GIT_BRANCH

# serial-native
cd $CALIMERO_BUILD
clone_update_repo serial-native $GIT_BRANCH
./gradlew assemble
cp ./build/lib/main/release/stripped/libserialcom.so $JAVA_LIB_PATH

# calimero-rxtx
cd $CALIMERO_BUILD
clone_update_repo calimero-rxtx $GIT_BRANCH

# calimero-usb
cd $CALIMERO_BUILD
clone_update_repo calimero-usb
# ./gradlew build publishToMavenLocal

# calimero-server
cd $CALIMERO_BUILD
clone_update_repo calimero-server $GIT_BRANCH
./gradlew assemble

rm -rf $CALIMERO_TMP
mkdir $CALIMERO_TMP
unzip -o build/distributions/calimero-server-*.zip -d $CALIMERO_TMP

echo "Copy libs to " $CALIMERO_SERVER_PATH
export DIST_SERVER_FOLDER="$(find $CALIMERO_TMP -name "calimero-server-*" -type d)"
if [ "$ARCH" = "ARM" ]; then
	# only keep the arm version of libusb
	find $DIST_SERVER_FOLDER/lib/ \! -name "libusb*arm*" -name "libusb*" -delete
elif [ "$ARCH" = "X64" ]; then
	# only keep the x64 version of libusb
	find $DIST_SERVER_FOLDER/lib/ \! -name "libusb*linux-x86-64*" -name "libusb*" -delete
fi
rm $DIST_SERVER_FOLDER/lib/calimero-rxtx-*.jar $DIST_SERVER_FOLDER/lib/nrjavaserial-*.jar
mv $DIST_SERVER_FOLDER/lib/* $CALIMERO_SERVER_PATH


########################## Calimero Client Tools ##############################

cd $CALIMERO_BUILD
clone_update_repo calimero-tools $GIT_BRANCH_TOOLS
./gradlew assemble

rm -rf $CALIMERO_TMP
mkdir $CALIMERO_TMP
unzip -o build/distributions/calimero-tools-*.zip -d $CALIMERO_TMP

echo "Copy libs to " $CALIMERO_TOOLS_PATH
export DIST_TOOLS_FOLDER="$(find $CALIMERO_TMP -name "calimero-tools-*" -type d)"
if [ "$ARCH" = "ARM" ]; then
	# only keep the arm version of libusb
	find $DIST_TOOLS_FOLDER/lib/ \! -name "libusb*arm*" -name "libusb*" -delete
elif [ "$ARCH" = "X64" ]; then
	# only keep the x64 version of libusb
	find $DIST_TOOLS_FOLDER/lib/ \! -name "libusb*linux-x86-64*" -name "libusb*" -delete
fi
rm $DIST_TOOLS_FOLDER/lib/calimero-rxtx-*.jar $DIST_TOOLS_FOLDER/lib/nrjavaserial-*.jar
mv $DIST_TOOLS_FOLDER/lib/* $CALIMERO_TOOLS_PATH

# Tools wrapper
export DEF_TOOL_OPTS="\
--add-reads io.calimero.tools=ALL-UNNAMED \
--add-reads io.calimero.core=io.calimero.tools \
--add-reads io.calimero.usb.provider.javax=ALL-UNNAMED \
--limit-modules io.calimero.tools,io.calimero.serial.provider.jni,io.calimero.usb.provider.javax \
-p $CALIMERO_TOOLS_PATH -cp \"$CALIMERO_TOOLS_PATH/*\""

cat > $BIN_PATH/knxtools <<EOF
#!/bin/sh
#
# This script is a wrapper to call the calimero tools simply
# from a shell without the java/maven/gradle overhead
# It sets some default parameters to known calimero tools 
#
if [ -z \$1 ]; then
    echo Please specify a command, available commands:
    echo "   discover"
    echo "   describe"
    echo "   devinfo"
    echo "   scan"
    echo "   ipconfig"
    echo "   monitor"
    echo "   read"
    echo "   write"
    echo "   groupmon"
    echo "   trafficmon"
    echo "   get"
    echo "   set"
    echo "   properties"
    echo "   info"
    echo "   baos"
    echo "   mem"
    echo "   progmode"
    echo "   restart"
    echo "   import"
    exit 1	
fi
if [ "\$1" = "properties" ]; then
    if  [ -z "\$2" ]  || [ "\$2" = "-?" ] || [ "\$2" = "-h" ]; then
        export PARAM2=--help
    else
        export PARAM2=\$2
    fi 
    java \$KNXTOOLS_JVM_OPTS $DEF_TOOL_OPTS --module io.calimero.tools \$1 \$PARAM2 \$3 \$4 \$5 \$6 \$7 \$8 \$9 \$10 \$11 \$12 \$13 \$14 \$15 \$16 \$17 \$18 \$19 \$20 \$21 \$22 \$23 \$24 \$25
elif [ "\$1" = "discover" ]; then 	
    java \$KNXTOOLS_JVM_OPTS $DEF_TOOL_OPTS --module io.calimero.tools \$@
else
    if  [ -z "\$2" ]  || [ "\$2" = "-?" ] || [ "\$2" = "-h" ]; then
        export PARAM2=--help
    else
        export PARAM2=\$2
    fi 
    java \$KNXTOOLS_JVM_OPTS $DEF_TOOL_OPTS --module io.calimero.tools \$1 \$PARAM2 \$3 \$4 \$5 \$6 \$7 \$8 \$9 \$10 \$11 \$12 \$13 \$14 \$15 \$16 \$17 \$18 \$19 \$20 \$21 \$22 \$23 \$24 \$25
fi
EOF
chmod +x $BIN_PATH/knxtools
# Test 
# knxtools monitor --medium knxip 192.168.200.1 --localhost 192.168.200.1 -c
# knxtools groupmon -m knxip 192.168.200.1 --localhost 192.168.200.1 -v

############################################ Config files #####################
echo Copy config files
# Copy config files
cp $CALIMERO_BUILD/calimero-server/resources/server-config.xml $CALIMERO_CONFIG_PATH

############################ Copy keyring file to app data directory #####################
if [ $KEYRING ]; then
	cp $KEYRING $CALIMERO_SERVER_APP_DATA

	echo Create keyfile with keyring password
	cat > $CALIMERO_SERVER_APP_DATA/keyfile <<EOF
keyring.pwd=$KEYRING_PWD
EOF
fi


############################## Configure calimero  ############################
cp $CALIMERO_CONFIG_PATH/server-config.xml $CALIMERO_CONFIG_PATH/server-config.xml.org
# Set ServerName
xmlstarlet ed --inplace -u 'knxServer/@friendlyName' -v "$KNX_SERVER_NAME"  $CALIMERO_CONFIG_PATH/server-config.xml
# Set application data directory
xmlstarlet ed --inplace -u 'knxServer/@appData' -v "$CALIMERO_SERVER_APP_DATA" \
  --insert 'knxServer[not(@appData)]' --type attr -n appData -v "$CALIMERO_SERVER_APP_DATA" $CALIMERO_CONFIG_PATH/server-config.xml
# Set own KNX Address
xmlstarlet ed --inplace -u 'knxServer/serviceContainer/knxAddress[@type="individual"]' -v $KNX_ADDRESS  $CALIMERO_CONFIG_PATH/server-config.xml
# Set Routing 
xmlstarlet ed --inplace -u 'knxServer/serviceContainer/@routing' -v $KNX_ROUTING  $CALIMERO_CONFIG_PATH/server-config.xml 
# Set Network Interface to $LISTEN_NETWORK_INTERFACE
xmlstarlet ed --inplace -u 'knxServer/serviceContainer/@listenNetIf' -v $LISTEN_NETWORK_INTERFACE  $CALIMERO_CONFIG_PATH/server-config.xml 
if [ "$KNX_CONNECTION" = "TPUART" ];then
	echo Configure calimero for TPUART connection
    # Comment USB
    sed -e's/\(<knxSubnet type="usb".*<\/knxSubnet>\)/<!-- \1 -->/g' $CALIMERO_CONFIG_PATH/server-config.xml --in-place=.bak
    # Enable TPUART, uncomment TPUART
    sed -e's/<!--\s*\(<knxSubnet type="tpuart".*<\/knxSubnet>\)\s*-->/\1/g' $CALIMERO_CONFIG_PATH/server-config.xml --in-place=.bak
elif [ "$KNX_CONNECTION" = "USB" ];then
	# Empty node -> First device is used
	echo Configure calimero for USB connection
    xmlstarlet ed  --inplace -u 'knxServer/serviceContainer/knxSubnet[@type="usb"]' -v "" $CALIMERO_CONFIG_PATH/server-config.xml
elif [ "$KNX_CONNECTION" = "TUNNEL" ];then    
    # Comment USB
    echo Configure calimero for Tunnel connection to endpoint $PARAM_VALUE
    sed -e's/\(<knxSubnet type="usb".*<\/knxSubnet>\)/<!-- \1 -->/g' $CALIMERO_CONFIG_PATH/server-config.xml --in-place=.bak
    # Enable ip, 
    xmlstarlet ed --inplace -s 'knxServer/serviceContainer' -t elem -n knxSubnet -v $PARAM_VALUE $CALIMERO_CONFIG_PATH/server-config.xml
    xmlstarlet ed --inplace -s 'knxServer/serviceContainer/knxSubnet'  -t attr -n "type" -v "ip" $CALIMERO_CONFIG_PATH/server-config.xml
    # If outgoing interface defined
    if [ ! -z $OUTGOING_NETWORK_INTERFACE_TUNNEL ]; then
		 xmlstarlet ed --inplace -s 'knxServer/serviceContainer/knxSubnet[@type="ip"]' -t attr -n netif -v $OUTGOING_NETWORK_INTERFACE_TUNNEL $CALIMERO_CONFIG_PATH/server-config.xml
    fi
else
    echo No KNX Connection specified
    exit 5
fi
# Replace serial device /dev/ttySx => $SERIAL_INTERFACE
sed -e"s/\/dev\/ttyS[[:digit:]]/\/dev\/$SERIAL_INTERFACE/g" $CALIMERO_CONFIG_PATH/server-config.xml --in-place=.bak
# Replace serial device /dev/ttyACMx => $SERIAL_INTERFACE
sed -e"s/\/dev\/ttyACM[[:digit:]]/\/dev\/$SERIAL_INTERFACE/g" $CALIMERO_CONFIG_PATH/server-config.xml --in-place=.bak
# Comment routing tag
sed -e's/[^<^!^\-^\-]\s\{1,\}\(<routing.*<\/routing>\)/<!-- \1 -->/g' $CALIMERO_CONFIG_PATH/server-config.xml  --in-place=.bak

######### Addresses assigned to KNXnet/IP Clients 
# Remove existing
xmlstarlet ed  --inplace -d 'knxServer/serviceContainer/additionalAddresses/knxAddress[@type="individual"]' $CALIMERO_CONFIG_PATH/server-config.xml
# Add $KNX_CLIENT_ADDRESS_COUNT Addresses, starting from $KNX_CLIENT_ADDRESS_START 
export KNX_ADDRESS_PREFIX=$(echo $KNX_CLIENT_ADDRESS_START|cut -d'.' -f 1-2)
export START_OCTET=$(echo $KNX_CLIENT_ADDRESS_START|cut -d'.' -f 3)
# Add new KNX Client Address elements
for ((i=0;i<$KNX_CLIENT_ADDRESS_COUNT;i++))
do
   CURRENT_OCTET=$(expr $START_OCTET + $i)
   xmlstarlet ed  --inplace -s 'knxServer/serviceContainer/additionalAddresses' -t elem  -n knxAddress -v $KNX_ADDRESS_PREFIX.$CURRENT_OCTET  $CALIMERO_CONFIG_PATH/server-config.xml
done
# Add Attribute type=individual
xmlstarlet ed  --inplace -s 'knxServer/serviceContainer/additionalAddresses/knxAddress' -t attr -n type -v individual $CALIMERO_CONFIG_PATH/server-config.xml

# If a keyring is present, add to server-config.xml
if [ $KEYRING ]; then
	xmlstarlet ed --inplace --insert 'knxServer/serviceContainer' -t attr -n keyring -v $CALIMERO_SERVER_APP_DATA/$KEYRING_FILENAME $CALIMERO_CONFIG_PATH/server-config.xml
	xmlstarlet ed --inplace --insert 'knxServer/serviceContainer' -t attr -n keyfile -v $CALIMERO_SERVER_APP_DATA/keyfile $CALIMERO_CONFIG_PATH/server-config.xml
fi


# Set owner on server and config path. Need to be discussed. Read/execute permissions should sufficient
echo Set owner
chown -R $CALIMERO_SERVER_USER:$CALIMERO_SERVER_GROUP $CALIMERO_TOOLS_PATH
chown -R $CALIMERO_SERVER_USER:$CALIMERO_SERVER_GROUP $CALIMERO_SERVER_PATH
chown -R $CALIMERO_SERVER_USER:$CALIMERO_SERVER_GROUP $CALIMERO_CONFIG_PATH


###################### Serial interface #######################################
# Configure serial devices depending on the underlying hardware
# Orange Pi
if [ $HARDWARE = "Orange" ]; then
	# Enable UART3 for connecting a TPUART module
	echo Alter Orange Hardware settings
	#bin2fex /boot/script.bin /tmp/script.fex
	#crudini --set /tmp/script.fex uart3 uart_used 1
	#fex2bin /tmp/script.fex /boot/script.bin
	grep -i overlays /boot/armbianEnv.txt 
	if [ "$?" -ge "1" ]; then
		echo Add UART3 Overlay
		echo overlays=uart3 >> /boot/armbianEnv.txt
	else
		echo Overlays already defined please add overlays=uart3 manually to /boot/armbianEnv.txt
		read -p "Press enter to continue"
	fi
elif [ $HARDWARE = "Raspi" ]; then
	# Raspberry
	echo Alter Raspberry Hardware settings
	if [ "$IS_RASPBERRY_3" == "1" ]; then
		sed -e's/ console=ttyAMA0,115200/ enable_uart=1 dtoverlay=pi3-disable-bt/g' /boot/cmdline.txt --in-place=.bak
		sed -e's/ console=serial0,115200/ enable_uart=1 dtoverlay=pi3-disable-bt/g' /boot/cmdline.txt --in-place=.bak2
		sed -e's/ console=ttyS0,115200/ enable_uart=1 dtoverlay=pi3-disable-bt/g' /boot/cmdline.txt --in-place=.bak4
		sed -e's/ console=ttyACM0,115200/ enable_uart=1 dtoverlay=pi3-disable-bt/g' /boot/cmdline.txt --in-place=.bak6
		systemctl disable hciuart
	else
		sed -e's/ console=ttyAMA0,115200//g' /boot/cmdline.txt --in-place=.bak
		sed -e's/ console=serial0,115200//g' /boot/cmdline.txt --in-place=.bak2
		sed -e's/ console=ttyS0,115200//g' /boot/cmdline.txt --in-place=.bak4
		sed -e's/ console=ttyACM0,115200//g' /boot/cmdline.txt --in-place=.bak6
	fi
	sed -e's/ kgdboc=ttyAMA0,115200//g' /boot/cmdline.txt --in-place=.bak1
	sed -e's/ kgdboc=serial0,115200//g' /boot/cmdline.txt --in-place=.bak3
	sed -e's/ kgdboc=ttyS0,115200//g' /boot/cmdline.txt --in-place=.bak5
	sed -e's/ kgdboc=ttyACM0,115200//g' /boot/cmdline.txt --in-place=.bak7

	# Disable serial console
	systemctl disable serial-getty@ttyAMA0.service > /dev/null 2>&1
	systemctl disable serial-getty@ttyS0.service > /dev/null 2>&1
	systemctl disable serial-getty@.service> /dev/null 2>&1
fi


# Systemd knx unit
echo Create systemd service

export DEF_SERVER_OPTS="\
--add-reads io.calimero.core=io.calimero.server \
--add-reads io.calimero.usb.provider.javax=ALL-UNNAMED \
--limit-modules io.calimero.server,io.calimero.serial.provider.jni,io.calimero.usb.provider.javax \
-p $CALIMERO_CONFIG_PATH:$CALIMERO_SERVER_PATH -cp \"$CALIMERO_CONFIG_PATH:$CALIMERO_SERVER_PATH/*\""

cat >  /etc/systemd/system/knx.service <<EOF
[Unit]
Description=Calimero KNX Daemon
After=network.target

[Service]
WorkingDirectory=/home/$CALIMERO_SERVER_USER
# Wait for all interfaces, systemd-networkd-wait-online.service must be enabled
#ExecStartPre=/lib/systemd/systemd-networkd-wait-online --timeout=60
# Wait for a specific interface
#ExecStartPre=/lib/systemd/systemd-networkd-wait-online --timeout=60 --interface=eth0
ExecStart=/usr/bin/java $DEF_SERVER_OPTS --module io.calimero.server --no-stdin $CALIMERO_CONFIG_PATH/server-config.xml
Type=simple
User=$CALIMERO_SERVER_USER
Group=$CALIMERO_SERVER_GROUP
#TimeoutStartSec=60
SuccessExitStatus=0 143

[Install]
WantedBy=multi-user.target network-online.target
EOF


# Enable at Startup
echo Enable systemd service
systemctl enable knx.service

echo Script finished. Please reboot your device...
