#!/bin/bash

### **parameters**

PREFIX="build"
SRCDIR="src"
DEBUG=true

### **subroutines**

function check () {
    if ! eval "$1" &>/dev/null; then
        echo "Error: $2" 1>&2
        echo "The failed command: $1" 1>&2
        echo "in directory: $PWD" 1>&2
        exit 1
    fi
}

function extracturl () {
    local url
    for url in $@; do
        case $url in
            *.rpm)
                curl -sL $url | rpm2cpio | cpio -idv
                ;;
            *.tar.gz)
                curl -sL $url | tar xzf - 
                ;;
            *.tar.bz2)
                curl -sL $url | tar xjf -
                ;;
        esac
    done
}

function getdeps () {
    local pkg dep
    for pkg in $@; do
        while read -r dep; do
            dep=${dep%% [*}
            dep=${dep##* }
            dep=${dep#[0-9]*:}
            echo $dep
        done < <(repoquery $RQARGS --archlist=$(uname -i),noarch --tree-requires $pkg)
    done | sort | uniq
}

### **main**

baserepo="http://mirror.centos.org/centos/6/os/$(uname -i)"
epelrepo="https://dl.fedoraproject.org/pub/epel/6/$(uname -i)"
corepkgs="coreutils pkgconfig libtool make patch pcre"
basepkgs="pcre-devel xorg-x11-proto-devel xorg-x11-util-macros xcb-util-keysyms-devel xcb-util-wm-devel startup-notification-devel yajl2-devel xcb-util-cursor-devel xcb-util-renderutil-devel xcb-util-image-devel zlib-devel freetype-devel fontconfig-devel libpng-devel pixman-devel libconfuse-devel alsa-lib-devel wireless-tools-devel asciidoc"
epelpkgs="libev-devel"

echo "Checking system and build setup..."

# Check required helper commands
for cmd in rpm repoquery curl rpm2cpio git ruby cmake; do
    check "command -v $cmd" "command $cmd not found"
done

# Required packages (basic system setup for development)
check "rpm -q $corepkgs" \
    "missing required core package(s)"

# Make sure we have access to the repositories
check "curl -s --head --connect-timeout 5 $baserepo | grep 'HTTP/1.[01] [23]..'" \
    "no access to base rpm repository"
check "curl -s --head --connect-timeout 5 $epelrepo | grep 'HTTP/1.[01] [23]..'" \
    "no access to EPEL rpm repository"

# Clean and create directories for source and build output
for dir in "$SRCDIR" "$PREFIX"; do
    if [[ -d $dir ]]; then
        echo "Removing existing $dir directory"
        check "rm -rf $dir" "failed to remove existing directory $dir"
    fi
    check "mkdir -p $dir" "failed to create directory $dir"
done
rootpath=$PWD
srcpath=$(readlink -f $SRCDIR)
prepath=$(readlink -f $PREFIX)

# Check how many threads we can use
threads=1
maxthreads=4
if command -v nproc &>/dev/null; then
    threads=$(nproc)
    [[ $threads -gt $maxthreads ]] && threads=$maxthreads
fi
if [[ $threads -gt 1 ]]; then
    echo "Using $threads threads for compiling source"
fi

# Query dependencies of required packages recursively
# Download rpm binaries of missing packages and extract them
echo "Analyzing dependencies..."
check "cd $PREFIX" \
    "failed to enter PREFIX=$PREFIX directory"
for pkg in $(getdeps $basepkgs); do
    pkgname=${pkg%%-[0-9]*}
    if ! rpm -q $pkgname &> /dev/null; then
        echo "Fetching $pkg"
        check "curl -s $baserepo/Packages/$pkg.rpm | rpm2cpio | cpio -idv" "failed to download and extract $pkgname"
    fi
done
for pkg in $(RQARGS="--repofrompath=epel,$epelrepo --repoid=epel" getdeps $epelpkgs); do
    pkgname=${pkg%%-[0-9]*}
    if ! rpm -q $pkgname &> /dev/null; then
        echo "Fetching $pkg"
        check "curl -s $epelrepo/Packages/${pkgname:0:1}/$pkg.rpm | rpm2cpio | cpio -idv" "failed to download and extract $pkgname"
    fi
done
# Always check out zlib, otherwise issues arise in cairo build
pkg=$(repoquery --archlist=$(uname -i) --envra zlib)
pkg=${pkg#*:} # strip out epoch
echo "Fetching $pkg"
check "curl -s $baserepo/Packages/$pkg.rpm | rpm2cpio | cpio -idv" \
    "failed to download and extract zlib"
check "cd $rootpath" \
    "failed to re-enter the root directory $rootpath"

# Check out source (rpms are not readily available for these packages on el6)
echo "Checking out source..."
check "cd $SRCDIR" \
    "failed to enter SRCDIR=$SRCDIR directory"

#function mt_checkout () {
#    echo "Checking out $1"
#    check "git clone $2" "failed to clone $1"
#}
#export -f mt_checkout
#
#echo \
#    "xcb-util-cursor" "http://anongit.freedesktop.org/git/xcb/util-cursor.git --recursive" \
#    "yajl"            "https://github.com/lloyd/yajl.git" \
#    "cairo"           "http://anongit.freedesktop.org/git/cairo" \
#    "pango"           "https://github.com/GNOME/pango.git" \
#    "i3"              "https://github.com/i3/i3.git" \
#    "i3status"        "https://github.com/i3/i3status.git" \
#    | xargs -n2 -P$threads mt_checkout

echo "Checking out xcb-util-cursor"
check "git clone http://anongit.freedesktop.org/git/xcb/util-cursor.git --recursive" \
    "failed to clone xcb-util-cursor source"
echo "Checking out yajl"
check "git clone https://github.com/lloyd/yajl.git" \
    "failed to clone yajl source"
echo "Checking out cairo"
check "git clone http://anongit.freedesktop.org/git/cairo" \
    "failed to clone cairo source"
echo "Checking out pango"
check "git clone https://github.com/GNOME/pango.git" \
    "failed to clone pango source"
echo "Checking out i3"
check "git clone https://github.com/i3/i3.git" \
    "failed to clone i3 source"
echo "Checking out i3status"
check "git clone https://github.com/i3/i3status.git" \
    "failed to clone i3status source"

check "cd $rootpath" \
    "failed to re-enter the root directory $rootpath"

# Set up for compilation
echo "Setting up for compilation..."

# Point to .pc files from locally extracted rpms
while read -r dir; do
    PKG_CONFIG_PATH=${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$dir
done < <(find $prepath -type d -name pkgconfig)
export PKG_CONFIG_PATH
# Same for .m4 files
while read -r dir; do
    ACLOCAL_PATH=${ACLOCAL_PATH:+$ACLOCAL_PATH:}$dir
done < <(find $prepath -type d -name aclocal)
export ACLOCAL_PATH
# Some packages need executables from local rpm to build, add them to the PATH here
export PATH="$PATH:$prepath/usr/bin"
# Set include and library linkage paths
while read -r dir; do
    CFLAGS=${CFLAGS:+ }-I$dir
done < <(find $prepath -type d -name include)
while read -r dir; do
    LDFLAGS=${LDFLAGS:+ }-I$dir
done < <(find $prepath -type d -name *lib*)

if $DEBUG; then
    echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH" | tee $PREFIX.env
    echo "ACLOCAL_PATH=$ACLOCAL_PATH" | tee -a $PREFIX.env
    echo "PATH=$PATH" | tee -a $PREFIX.env
    echo "CFLAGS=$CFLAGS" | tee -a $PREFIX.env
    echo "LDFLAGS=$LDFLAGS" | tee -a $PREFIX.env
fi

# Compile source
echo "Compiling source..."

# xcb-util-cursor
echo "Compiling xcb-util-cursor"
check "cd $srcpath/util-cursor" \
    "failed to enter xcb-util-cursor source directory"
check "git checkout 0.1.0" \
    "failed to check out xcb-util-cursor tag 0.1.0"
check "./autogen.sh" \
    "failed to autogen xcb-util-cursor"
check "./configure --prefix=$prepath/usr XCB{,_RENDER,_RENDERUTIL,_IMAGE}_CFLAGS=-I$prepath/usr/include XCB{,_RENDER,_RENDERUTIL,_IMAGE}_LIBS=-L$prepath/usr/lib64" \
    "failed to configure xcb-util-cursor"
check "make" \
    "failed to compile xcb-util-cursor"
check "make install" \
    "failed to install xcb-util-cursor"

# yajl
echo "Compiling yajl"
check "cd $srcpath/yajl" \
    "failed to enter yajl source directory"
check "git checkout 2.0.4" \
    "failed to check out yajl tag 2.0.4"
check "./configure --prefix=$prepath/usr" \
    "failed to configure yajl"
check "make" \
    "failed to compile yajl"
check "make install" \
    "failed to install yajl"

# cairo
echo "Compiling cairo"
check "cd $srcpath/cairo" \
    "failed to enter cairo source directory"
# Using 1.12.4 instead of 1.12.2 since the former resolves missing gtkdocize causing autogen to fail
# The latter version just skips building documentation if gtk-doc is missing
check "git checkout 1.12.4" \
    "failed to check out cairo tag 1.12.4"
check "./autogen.sh" \
    "failed to autogen cairo"
check "./configure --prefix=$prepath/usr {xcb,png,FREETYPE,FONTCONFIG,pixman}_CFLAGS=-I$prepath/usr/include {xcb,png,FREETYPE,FONTCONFIG,pixman}_LIBS=\"-L$prepath/usr/lib64 -L$prepath/usr/lib\"" \
    "failed to configure cairo"
check "make" \
    "failed to compile cairo"
check "make install" \
    "failed to install cairo"

# pango

# i3

# i3status

