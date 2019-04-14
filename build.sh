#!/bin/bash

### **parameters**

PREFIX="build"
SRCDIR="src"
DEBUG=true

### **subroutines**

function log () {
    echo "$@" | tee -a $LOG
}

function check () {
    echo "$1" >> $LOG
    if ! eval "$1" &>> $LOG; then
        echo "Error: $2" 1>&2
        echo "* The failed command: $1" 1>&2
        echo "* in directory: $PWD" 1>&2
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

o_PKG_CONFIG_PATH=$PKG_CONFIG_PATH
o_ACLOCAL_PATH=$ACLOCAL_PATH
o_PATH=$PATH
o_CFLAGS=$CFLAGS
o_LDFLAGS=$LDFLAGS
function fixenv () {
    # PKG_CONFIG_PATH
    PKG_CONFIG_PATH=$o_PKG_CONFIG_PATH
    while read -r dir; do
        PKG_CONFIG_PATH=${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$dir
    done < <(find $prepath -type d -name pkgconfig)
    export PKG_CONFIG_PATH
    # ACLOCAL_PATH
    ACLOCAL_PATH=$o_ACLOCAL_PATH
    while read -r dir; do
        ACLOCAL_PATH=${ACLOCAL_PATH:+$ACLOCAL_PATH:}$dir
    done < <(find $prepath -type d -name aclocal)
    export ACLOCAL_PATH
    # PATH
    PATH=$o_PATH
    while read -r dir; do
        PATH=${PATH:+$PATH:}$dir
    done < <(find $prepath -type d -name bin)
    export PATH
    # CFLAGS
    CFLAGS=$o_CFLAGS
    while read -r dir; do
        CFLAGS=${CFLAGS:+$CFLAGS }-I$dir
    done < <(find $prepath -type d -name include)
    export CFLAGS
    # LDFLAGS
    LDFLAGS=$o_LDFLAGS
    while read -r dir; do
        ls $dir/*.so &> /dev/null || continue # ignore directories not containing shared library files
        LDFLAGS=${LDFLAGS:+$LDFLAGS }-L$dir
    done < <(find $prepath -type d -name lib -o -name lib64 -o -name libexec)
    export LDFLAGS
    if $DEBUG; then
        log "PKG_CONFIG_PATH=\"$PKG_CONFIG_PATH\"" | tee $PREFIX.env
        log "ACLOCAL_PATH=\"$ACLOCAL_PATH\"" | tee -a $PREFIX.env
        log "PATH=\"$PATH\"" | tee -a $PREFIX.env
        log "CFLAGS=\"$CFLAGS\"" | tee -a $PREFIX.env
        log "LDFLAGS=\"$LDFLAGS\"" | tee -a $PREFIX.env
    fi
}

### **main**

baserepo="http://mirror.centos.org/centos/6/os/$(uname -i)"
epelrepo="https://dl.fedoraproject.org/pub/epel/6/$(uname -i)"
corepkgs="coreutils pkgconfig libtool make patch"
basepkgs="pcre-devel gperf xorg-x11-proto-devel xorg-x11-util-macros xcb-util-devel xcb-util-keysyms-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel startup-notification-devel alsa-lib-devel wireless-tools-devel asciidoc"
epelpkgs="libev-devel libconfuse-devel"

# Initialize log
$DEBUG && LOG=${LOG:-$PWD/$PREFIX.log} || LOG=/dev/null
echo "Build started at $(date)" > $LOG

log "Checking system and build setup..."

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
        log "Removing existing $dir directory"
        check "rm -rf $dir" "failed to remove existing directory $dir"
    fi
    check "mkdir -p $dir" "failed to create directory $dir"
done
rootpath=$PWD
srcpath=$(readlink -f $SRCDIR); $DEBUG && log "srcpath=$srcpath"
prepath=$(readlink -f $PREFIX); $DEBUG && log "prepath=$prepath"

# Query dependencies of required packages recursively
# Download rpm binaries of missing packages and extract them
log "Analyzing dependencies..."
check "cd $prepath" \
    "failed to enter PREFIX=$PREFIX directory ($prepath)"
for pkg in $(getdeps $basepkgs); do
    pkgname=${pkg%%-[0-9]*}
    if ! rpm -q $pkgname &> /dev/null; then
        log "Fetching $pkg"
        check "curl -s $baserepo/Packages/$pkg.rpm | rpm2cpio | cpio -idv" "failed to download and extract $pkgname"
    elif $DEBUG; then
        log "System satisfies $pkg dependency"
    fi
done
for pkg in $(RQARGS="--repofrompath=epel,$epelrepo --repoid=epel" getdeps $epelpkgs); do
    pkgname=${pkg%%-[0-9]*}
    if ! rpm -q $pkgname &> /dev/null; then
        log "Fetching $pkg"
        check "curl -s $epelrepo/Packages/${pkgname:0:1}/$pkg.rpm | rpm2cpio | cpio -idv" "failed to download and extract $pkgname"
    elif $DEBUG; then
        log "System satisfies $pkg dependency"
    fi
done

# When locally extracting *-devel packages but using system installed base packages,
# the symlink to libraries created by -devel will be broken. Correct them here.
for broken in $(find $prepath -xtype l); do
    [[ $(readlink $broken) =~ ^/ ]] && continue
    fixed="$(dirname ${broken#$prepath})/$(readlink $broken)"
    check "test -e $fixed" "Cannot locate system library $fixed"
    unlink $broken
    ln -s $fixed $broken
    $DEBUG && log "Fixed symlink $broken -> $fixed"
done

# Check out source (rpms are not readily available for these packages on el6)
log "Checking out source..."
check "cd $srcpath" \
    "failed to enter SRCDIR=$SRCDIR directory ($srcpath)"
log "Checking out xcb-util-cursor"
check "git clone http://anongit.freedesktop.org/git/xcb/util-cursor.git --recursive" \
    "failed to clone xcb-util-cursor source"
log "Checking out yajl"
check "git clone https://github.com/lloyd/yajl.git" \
    "failed to clone yajl source"
log "Checking out i3"
check "git clone https://github.com/i3/i3.git" \
    "failed to clone i3 source"
log "Checking out i3status"
check "git clone https://github.com/i3/i3status.git" \
    "failed to clone i3status source"

# Compile source
log "Compiling source..."

# xcb-util-cursor
log "Compiling xcb-util-cursor"
check "cd $srcpath/util-cursor" \
    "failed to enter xcb-util-cursor source directory"
check "git checkout 0.1.0" \
    "failed to check out xcb-util-cursor 0.1.0"
fixenv # update build environment variables based on previously extracted/built packages
check "./autogen.sh" \
    "failed to autogen xcb-util-cursor"
check "./configure --prefix=$prepath/usr XCB{,_RENDER,_RENDERUTIL,_IMAGE}_CFLAGS=-I$prepath/usr/include XCB{,_RENDER,_RENDERUTIL,_IMAGE}_LIBS=-L$prepath/usr/lib64" \
    "failed to configure xcb-util-cursor"
check "make" \
    "failed to compile xcb-util-cursor"
check "make install" \
    "failed to install xcb-util-cursor"

# yajl
log "Compiling yajl"
check "cd $srcpath/yajl" \
    "failed to enter yajl source directory"
check "git checkout 2.0.4" \
    "failed to check out yajl 2.0.4"
fixenv
check "./configure --prefix $prepath/usr" \
    "failed to configure yajl"
check "make" \
    "failed to compile yajl"
check "make install" \
    "failed to install yajl"

# i3
log "Compiling i3"
check "cd $srcpath/i3" \
    "failed to enter i3 source directory"
check "git checkout 4.8" \
    "failed to check out i3 4.8"
fixenv
check "sed -i -e '/PANGO/ s/^/#/' common.mk" \
    "failed to adjust configuration to disable pango"
check "make DEBUG=0 LIBSN_CFLAGS=-I$prepath/usr/include/startup-notification-1.0 LIBEV_CFLAGS=-I$prepath/usr/include/libev XCURSOR_LIBS+=\"-lxcb-image -lxcb-render-util -lxcb-cursor -lxcb\"" \
    "failed to compile i3"
check "make PREFIX=$prepath/usr install" \
    "failed to install i3"

# i3status
log "Compiling i3status"
check "cd $srcpath/i3status" \
    "failed to enter i3status source directory"
check "git checkout 2.9" \
    "failed to check out i3status 2.9"
fixenv
check "make" \
    "failed to compile i3status"
check "make PREFIX=$prepath/usr install" \
    "failed to install i3status"

