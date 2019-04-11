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
corepkgs="coreutils pkgconfig libtool make patch"
basepkgs="pcre-devel xorg-x11-util-macros xcb-util-keysyms-devel xcb-util-wm-devel startup-notification-devel alsa-lib-devel wireless-tools-devel asciidoc"
# xorg-x11-proto-devel xcb-util-renderutil-devel xcb-util-image-devel
epelpkgs="libev-devel libconfuse-devel"

echo "Checking system and build setup..."

# Check required helper commands
for cmd in rpm repoquery curl rpm2cpio git; do
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

# Query dependencies of required packages recursively
# Download rpm binaries of missing packages and extract them
echo "Analyzing dependencies..."
check "cd $prepath" \
    "failed to enter PREFIX=$PREFIX directory ($prepath)"
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
#pkg=$(repoquery --archlist=$(uname -i) --envra zlib)
#pkg=${pkg#*:} # strip out epoch
#echo "Fetching $pkg"
#check "curl -s $baserepo/Packages/$pkg.rpm | rpm2cpio | cpio -idv" \
#    "failed to download and extract zlib"

# Check out source (rpms are not readily available for these packages on el6)
echo "Checking out source..."
check "cd $srcpath" \
    "failed to enter SRCDIR=$SRCDIR directory ($srcpath)"

#function mt_checkout () {
#    echo "Checking out $1"
#    git clone --branch $2 $3
#}
#export -f mt_checkout
#
#echo \
#    "xcb-util-cursor" "0.1.0"  "http://anongit.freedesktop.org/git/xcb/util-cursor.git" \
#    "yajl"            "2.0.4"  "https://github.com/lloyd/yajl.git" \
#    #"cairo"          "1.12.4" "http://anongit.freedesktop.org/git/cairo" \
#    #"pango"          "1.30.0" "https://github.com/GNOME/pango.git" \
#    "i3"              "4.8"    "https://github.com/i3/i3.git" \
#    "i3status"        "2.9"    "https://github.com/i3/i3status.git" \
#    | xargs -n3 -P$threads -I{} bash -c "mt_checkout {} {} {}"
#
#check "test -d $srcpath/util-cursor" "Failed to check out xcb-util-cursor"
#check "test -d $srcpath/yajl" "Failed to check out yajl"
#check "test -d $srcpath/i3" "Failed to check out i3"
#check "test -d $srcpath/i3status" "Failed to check out i3status"

echo "Checking out xcb-util-cursor"
check "git clone --branch 0.1.0 http://anongit.freedesktop.org/git/xcb/util-cursor.git --recursive" \
    "failed to clone xcb-util-cursor 0.1.0 source"
echo "Checking out yajl"
check "git clone --branch 2.0.4 https://github.com/lloyd/yajl.git" \
    "failed to clone yajl 2.0.4 source"
#echo "Checking out cairo"
## Using 1.12.4 instead of 1.12.2 since it allows missing gtk-doc (skips documentation build instead of failing autogen)
#check "git clone --branch 1.12.4 http://anongit.freedesktop.org/git/cairo" \
#    "failed to clone cairo 1.12.4 source"
#echo "Checking out pango"
#check "git clone --branch 1.30.0 https://github.com/GNOME/pango.git" \
#    "failed to clone pango 1.30.0 source"
echo "Checking out i3"
check "git clone --branch 4.8 https://github.com/i3/i3.git" \
    "failed to clone i3 4.8 source"
echo "Checking out i3status"
check "git clone --branch 2.9 https://github.com/i3/i3status.git" \
    "failed to clone i3status 2.9 source"

# Set up for compilation
echo "Setting up for compilation..."

# Adjust environment variables for compilation to point to files from locally extracted rpms
# PKG_CONFIG_PATH (.pc)
while read -r dir; do
    PKG_CONFIG_PATH=${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$dir
done < <(find $prepath -type d -name pkgconfig)
export PKG_CONFIG_PATH
# ACLOCAL_PATH (.m4)
while read -r dir; do
    ACLOCAL_PATH=${ACLOCAL_PATH:+$ACLOCAL_PATH:}$dir
done < <(find $prepath -type d -name aclocal)
export ACLOCAL_PATH
# PATH
while read -r dir; do
    PATH=${PATH:+$PATH:}$dir
done < <(find $prepath -type d -name bin)
export PATH
# CFLAGS
while read -r dir; do
    CFLAGS=${CFLAGS:+$CFLAGS }-I$dir
done < <(find $prepath -type d -name include)
# LDFLAGS
while read -r dir; do
    LDFLAGS=${LDFLAGS:+$LDFLAGS }-L$dir
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
check "./configure --prefix=$prepath/usr" \
    "failed to configure yajl"
check "make" \
    "failed to compile yajl"
check "make install" \
    "failed to install yajl"

# cairo
#echo "Compiling cairo"
#check "cd $srcpath/cairo" \
#    "failed to enter cairo source directory"
#check "./autogen.sh" \
#    "failed to autogen cairo"
#check "./configure --prefix=$prepath/usr {xcb,png,FREETYPE,FONTCONFIG,pixman}_CFLAGS=-I$prepath/usr/include {xcb,png,FREETYPE,FONTCONFIG,pixman}_LIBS=\"-L$prepath/usr/lib64 -L$prepath/usr/lib\"" \
#    "failed to configure cairo"
#check "make" \
#    "failed to compile cairo"
#check "make install" \
#    "failed to install cairo"

# pango

# i3

# i3status

