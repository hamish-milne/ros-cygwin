#!/usr/bin/bash

##
# ROS Cygwin Installer -Hamish Milne 2016
#
# Usage: Simply run ./ros-cygwin.sh and follow the prompts.
# You can add command-line arguments to set the value of the configuration
#    variables listed below. Use the form `--<NAME>=<VALUE>`
# For instance, you may want to set --ROS_DISTRO=jade, or --ROS_TYPE=desktop
#    *however, this currently is completely untested*.
#
# The purpose of this script is to fix and work around the various problems
#    that ROS has on Cygwin, such as a very platform-specific way of finding
#    dependencies, and assumptions about the type of system it's compiling on.
##

# Exit on error. If there's a problem there's no point in pressing on.
set -e

# Some colour definitions to make the output look nice
CYAN='\033[1;36m'
RED='\033[1;31m'
GREEN='\033[1;32m'
PURPLE='\033[1;35m'
NC='\033[0m'

# Configuration variables
WSDIR=ros_catkin_ws
ROS_TYPE=ros_comm
ROS_DISTRO=kinetic
SKIP_UPDATEDB=

# User interaction
function info { # 1:log
	echo -e "${CYAN}  => $1${NC}"
}
function warn { # 1:log
	echo -e "${RED}  !! $1${NC}"
}
function succ { # 1:log
	echo -e "${GREEN}  ^^ $1${NC}"
}
function ques { # 1:prompt ret:entered_yes
	echo -en "${PURPLE}  ?? $1${NC} (Y/n):"
	read -n 1 yn
	echo ""
	if [ "${yn,,}" == 'n' ]; then
		return 1
	fi
	return 0
}

# Outputs the first file with the given name in /bin, /usr or /lib
function locate_lib { # 1:file out:path ret:found_file
	locate -r "^/\(bin\|usr\|lib\)/\(.*\|/\)$(echo $1 | sed 's/\./\\\./g')$" -l 1
}

# Checks if the given file is installed in the system or not
function missing { # 1:file ret:is_missing
	if locate_lib "$1" > /dev/null; then
		return 1
	else
		return 0
	fi
}

# Prepends the file with the given line, if it doesn't already start with it
# If comment_token is provided, add a comment about why the line is there.
function prepend { # 1:file 2:line 3:comment_token
	line="$2"
	if [ "$3" != "" ]; then
		line="$line $3 Added for Cygwin compatibility"
	fi
	if [ "$(head -1 $1)" != "$line" ]; then
		if [ "$4" != "" ]; then
			echo -e "$line\n$4\n$(cat $1)" > "$1"
		else
			echo -e "$line\n$(cat $1)" > "$1"
		fi
	fi
}

# The following functions use % as their delimiter. So remember to escape those!
# Appends text to the given line in a file
function append_line { # 1:file 2:line 3:append
	sed -i 's%'"$2"'[[:space:]]*$%'"$2 $3"'%' "$1"
}
# Inserts text between two patterns in a file
function insert { # 1:file 2:pattern_before 3:pattern_after 4:insertion
	sed -i "s%$2[[:space:]][[:space:]]*$3%$2 $4 $3%g" "$1"
}

echo -e "${GREEN}"
echo "  ROS Cygwin Installer v0.1"
echo "  2016 Hamish Milne"
echo "  ========================="
echo -e "${NC}"

# Set any config variables from the command line
for var in "$@"; do
	if [[ "$var" =~ --([A-Za-z0-9_-]+)(=(.*))? ]]; then
		if [ "${BASH_REMATCH[2]}" == "" ]; then
			declare "${BASH_REMATCH[1]}"=1
		else
			declare "${BASH_REMATCH[1]}"="${BASH_REMATCH[3]}"
		fi
	else
		warn "Invalid argument: $var"
		exit 1
	fi
done

info "We're going to install ${ROS_TYPE} ${ROS_DISTRO}"
info "Our working directory, where we'll be downloading stuff to, is $(pwd)"
if ! ques "Continue"; then
	warn "Exiting"
	exit 1
fi

# Ensure that apt-cyg exists
info "Checking for apt-cyg..."
if ! type apt-cyg > /dev/null; then
	warn "apt-cyg not installed."
	info "Checking for wget..."
	if ! type wget > /dev/null; then
		warn "wget not found."
		warn "Please install the 'wget' package to continue."
		exit 1
	else
		wget rawgit.com/transcode-open/apt-cyg/master/apt-cyg -O apt-cyg
		install apt-cyg /bin
		succ "apt-cyg installed"
	fi
else
	info "apt-cyg found"
fi
echo ""

# Fix the path. This makes sure when we call 'python' or 'pip', we're running the
# cygwin version and not the windows one.
info "Path is $(echo $PATH | sed 's/:/\n     /g')"
if [[ "$PATH" =~ "/cygdrive/" ]]; then
	warn "It looks like your path references the host drive. This can cause issues where the wrong executable is run by the installer"
	if ques "Is it OK to fix this temporarily?"; then
		export PATH=/usr/local/bin:/usr/bin:/bin
	else
		info "OK, but don't say we didn't warn you"
	fi
fi
echo ""

# Figure out the install space
OPT_PATH="/opt/ros/${ROS_DISTRO}"
INSTALL_ARG=""
INSTALL_SPACE="$(pwd)/${WSDIR}/install_isolated"
info "If you're serious about installing ROS, you'll want to put everything in ${OPT_PATH}, rather than in ${WSDIR}/install_isolated"
if ques "Install into ${OPT_PATH}?"; then
	INSTALL_ARG="--install-space ${OPT_PATH}"
	INSTALL_SPACE="$OPT_PATH"
fi
echo ""

info "Installing Cygwin packages. This could take a while..."
# git isn't needed by ros, but we will need it the first time to get some libraries
apt-cyg install liblz4-devel libbz2-devel clisp python python-devel python-setuptools libboost-devel gcc-core gcc-g++ make cmake git
succ "Cygwin packages installed"
echo ""

# Ensure pip exists
info "Checking for pip..."
if ! type pip > /dev/null; then
	info "Installing pip..."
	easy_install-2.7 pip
	succ "pip installed"
else
	info "pip found"
fi
info "Installing Python packages. This could take a while..."
pip install rosdep rosinstall_generator wstool rosinstall pyyaml rospkg nose coverage mock defusedxml empy
succ "Python packages installed"
echo ""

# Ensure that our calls to 'locate' actually work
if [ ! "$SKIP_UPDATEDB" ]; then
	info "Make sure that the locate DB is up to date"
	updatedb --localpaths='/usr /lib /bin'
	echo ""
fi
	
info "Now we'll install the extra dependencies we can't find in package managers:"
export CMAKE_LEGACY_CYGWIN_WIN32=0 # This hides a few useless errors
info "...googletest (gtest)..."
if missing libgtest.a || missing gtest.h; then
	if ! [ -d googletest ]; then
		git clone https://github.com/google/googletest.git
	fi
	cd googletest/googletest
	prepend CMakeLists.txt 'set(CMAKE_CXX_FLAGS ${CMAKE_CXX_FLAGS} "-D_DEFAULT_SOURCE")' '#'
	cmake .
	make install
	cd ../..
	succ "googletest installed"
fi

info "...tinyxml..."
if missing libtinyxml.dll.a || missing tinyxml.h || missing tinystr.h; then  
	if ! [ -d tinyxml-git ]; then
		git clone git://git.code.sf.net/p/tinyxml/git tinyxml-git
	fi
	cd tinyxml-git
	make
	ar rcs /usr/lib/libtinyxml.dll.a tinyxml.o tinystr.o tinyxmlerror.o tinyxmlparser.o
	cp tinyxml.h /usr/include
	cp tinystr.h /usr/include
	cd ..
	succ "tinyxml installed"
fi

info "...console-bridge..."
if missing libconsole_bridge.dll.a || missing console_bridge/console.h; then
	if ! [ -d console_bridge ]; then
		git clone https://github.com/ros/console_bridge.git
	fi
	cd console_bridge
	cmake . -DEXTRA_CMAKE_CXX_FLAGS:STRING="-D _DEFAULT_SOURCE"
	make install
	prepend /usr/local/include/console_bridge/console.h '#include <stdio.h>' '//'
	cd ..
	succ "console-bridge installed"
fi
echo ""

# I'm not sure if this is exactly needed or not, but we might as well do it
# just in case. Maybe later down the line it can be used to dynamically find
# dependencies.
info "Updating the rosdep cache..."
if [ ! -f "/etc/ros/rosdep/sources.list.d/20-default.list" ]; then
	rosdep init
fi
if [ ! "$SKIP_UPDATEDB" ]; then
	rosdep update
fi

info "Entering workspace"
mkdir -p "$WSDIR"
cd "$WSDIR"
if [ -f 'src/.rosinstall' ]; then
	warn "Source installation already exists. Delete 'src' to start from scratch"
else
	info "Creating ROS installer..."
	ROS_INSTALLER="${ROS_DISTRO}-${ROS_TYPE}-wet.rosinstall"
	rosinstall_generator "$ROS_TYPE" --rosdistro "$ROS_DISTRO" --deps --wet-only --tar > "$ROS_INSTALLER"
	info "Fetching sources..."
	wstool init -j8 src "$ROS_INSTALLER"
fi
info "Checking dependencies (for completeness)..."
# rosdep is the program that's supposed to install all the dependencies we
# just had to deal with, but it can't deal with cygwin at all and relies on
# obscure packages existing for the distro.
set +e # We pretty much expect this part to fail, so disable error checking for a bit
rosdep install --from-paths src --ignore-src --rosdistro kinetic -y
set -e
info "rosdep probably spewed out some errors there, but this is fine; we hopefully installed everything already"
echo ""

info "Adding some fixes to the ROS code and build files..."

# A couple of packages don't reference each others' CMake files correctly, so we fix that here
# Copying the files to the install path manually is 'better', but it would need to be done mid-install,
# so instead just set the <package>_DIR variable appropriately.
function fix_package_path {
	dir_dest="build_isolated/$2/devel/share/$2/cmake"
	mkdir -p "$dir_dest"
	dir_rel=$(realpath --relative-to="$1" "$dir_dest")
	prepend "$1/CMakeLists.txt" "set($2_DIR \${CMAKE_SOURCE_DIR}/${dir_rel})" '#'
}
fix_package_path src/ros/roslib rospack
fix_package_path src/ros_comm/rosbag rosbag_storage
fix_package_path src/ros_comm/rosout roscpp
fix_package_path src/ros_comm/message_filters roscpp
fix_package_path src/ros_comm/topic_tools roscpp
fix_package_path src/ros_comm/rosbag roscpp

# At least one version of CMake doesn't like to install LIBRARY without RUNTIME and ARCHIVE
append_line src/ros_comm/roslz4/CMakeLists.txt 'install(TARGETS roslz4_py' 'LIBRARY DESTINATION ${CATKIN_PACKAGE_PYTHON_DESTINATION} ARCHIVE DESTINATION ${CATKIN_PACKAGE_PYTHON_DESTINATION}'

# For some reason, rosbag_storage does not like to link to the roslz4 static libraries,
# so here we link it to the dynamic one instead.
insert src/ros_comm/rosbag_storage/CMakeLists.txt 'target_link_libraries(rosbag_storage' '${' "\"${INSTALL_SPACE}/lib/roslz4/cygroslz4.dll\""

# This is a cygwin edge case where something isn't defined by its standard headers
append_line src/ros_comm/xmlrpcpp/src/XmlRpcSocket.cpp '# include <arpa/inet.h>' "// Cygwin compatibility\ntypedef uint16_t u_short;"

# Either cygwin's compiler is special, or ROS makes a lot of assumptions about how std=c++11 works
# In any case, we need to define _DEFAULT_SOURCE for the headers to define a few weird POSIX functions.
# If you get a bunch of function undefined errors, this will probably fix them.
sed -i 's/-std=c++11;-Wall/-std=c++11;-D_DEFAULT_SOURCE;-Wall/g' src/ros_comm/roscpp/CMakeLists.txt

# rospack doesn't use TinyXML correctly, and is also missing the FILE definition
prepend src/rospack/include/rospack/rospack.h '#define TIXML_USE_STL' '//' '#include <stdio.h>'

echo ""

info "This is the big one. Now building ROS..."
if ./src/catkin/bin/catkin_make_isolated --install -DCMAKE_BUILD_TYPE=Release $INSTALL_ARG; then
	succ "... Looks like we did it! Check the log for errors just to be sure, then run ${INSTALL_SPACE}/setup.bash to use ROS."
else
	warn "Oh no! Looks like we hit a snag. Check the log for errors and read through the script to find a fix."
fi
