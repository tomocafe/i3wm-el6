#!/bin/bash

# tomocafe/i3wm-el6
# build.sh
# 
# See README.md for documentation

### |parameters|

# If you change these, you may want to update .gitignore
PREFIX="i3-4.8"
SRCDIR="src"
BLDDIR="build"
DEBUG=false
I3STATUS=true
I3BLOCKS=true
DUNST=true

### |subroutines|

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
o_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
function fixenv () {
    # PKG_CONFIG_PATH
    PKG_CONFIG_PATH=$o_PKG_CONFIG_PATH
    while read -r dir; do
        PKG_CONFIG_PATH=${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$dir
    done < <(find $bldpath $prepath -type d -name pkgconfig)
    export PKG_CONFIG_PATH
    # ACLOCAL_PATH
    ACLOCAL_PATH=$o_ACLOCAL_PATH
    while read -r dir; do
        ACLOCAL_PATH=${ACLOCAL_PATH:+$ACLOCAL_PATH:}$dir
    done < <(find $bldpath $prepath -type d -name aclocal)
    export ACLOCAL_PATH
    # ACLOCAL (for compatibility)
    export ACLOCAL="aclocal${ACLOCAL_PATH:+ -I}${ACLOCAL_PATH//:/ -I}"
    # PATH
    PATH=$o_PATH
    while read -r dir; do
        PATH=${PATH:+$PATH:}$dir
    done < <(find $bldpath $prepath -type d -name bin)
    export PATH
    # CFLAGS
    CFLAGS=$o_CFLAGS
    while read -r dir; do
        CFLAGS=${CFLAGS:+$CFLAGS }-I$dir
    done < <(find $bldpath $prepath -type d -name include)
    export CFLAGS
    # LDFLAGS
    LDFLAGS=$o_LDFLAGS
    LD_LIBRARY_PATH=$o_LD_LIBRARY_PATH
    while read -r dir; do
        ls $dir/*.so &> /dev/null || continue # ignore directories not containing shared library files
        LDFLAGS=${LDFLAGS:+$LDFLAGS }-L$dir
        LD_LIBRARY_PATH=${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$dir
    done < <(find $bldpath $prepath -type d -name lib -o -name lib64 -o -name libexec)
    export LDFLAGS
    if $DEBUG; then
        log "export PKG_CONFIG_PATH=\"$PKG_CONFIG_PATH\"" | tee $BLDDIR.env
        log "export ACLOCAL_PATH=\"$ACLOCAL_PATH\"" | tee -a $BLDDIR.env
        log "export ACLOCAL=\"$ACLOCAL\"" | tee -a $BLDDIR.env
        log "export PATH=\"$PATH\"" | tee -a $BLDDIR.env
        log "export CFLAGS=\"$CFLAGS\"" | tee -a $BLDDIR.env
        log "export LDFLAGS=\"$LDFLAGS\"" | tee -a $BLDDIR.env
        log "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\"" | tee -a $BLDDIR.env
    fi
}

### |main|

baserepo="http://mirror.centos.org/centos/6/os/$(uname -i)"
epelrepo="https://dl.fedoraproject.org/pub/epel/6/$(uname -i)"
corepkgs="coreutils pkgconfig libtool make patch"
basepkgs="pcre-devel gperf xorg-x11-proto-devel xorg-x11-util-macros xcb-util-devel xcb-util-keysyms-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel startup-notification-devel alsa-lib-devel wireless-tools-devel ruby cmake"
$DUNST && basepkgs+=" libXScrnSaver-devel libffi-devel gdk-pixbuf2-devel cairo-devel libXinerama-devel"
epelpkgs="libev-devel libconfuse-devel dmenu"

# Initialize log
$DEBUG && LOG=${LOG:-$PWD/$BLDDIR.log} || LOG=/dev/null
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
for dir in "$SRCDIR" "$BLDDIR" "$PREFIX"; do
    if [[ -d $dir ]]; then
        log "Removing existing $dir directory"
        check "rm -rf $dir" "failed to remove existing directory $dir"
    fi
    check "mkdir -p $dir" "failed to create directory $dir"
done
rootpath=$PWD
srcpath=$(readlink -f $SRCDIR); $DEBUG && log "srcpath=$srcpath"
bldpath=$(readlink -f $BLDDIR); $DEBUG && log "bldpath=$bldpath"
prepath=$(readlink -f $PREFIX); $DEBUG && log "prepath=$prepath"

# Query dependencies of required packages recursively
# Download rpm binaries of missing packages and extract them
log "Analyzing dependencies..."
check "cd $bldpath" \
    "failed to enter BLDDIR=$BLDDIR directory ($bldpath)"
for pkg in $(getdeps $basepkgs); do
    pkgname=${pkg%%-[0-9]*}
    if ! rpm -q $pkgname &> /dev/null; then
        log "Fetching $pkg"
        check "curl -s $baserepo/Packages/$pkg.rpm | rpm2cpio | cpio -idv" "failed to download and extract $pkgname"
    elif $DEBUG; then
        log "System satisfies $pkg dependency"
    fi
done
for pkg in $(RQARGS="--repofrompath=epel-i3wm-el6,$epelrepo --repoid=epel-i3wm-el6" getdeps $epelpkgs); do
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
for broken in $(find $bldpath -xtype l); do
    [[ $(readlink $broken) =~ ^/ ]] && continue
    fixed="$(dirname ${broken#$bldpath})/$(readlink $broken)"
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
if $I3STATUS; then
    log "Checking out i3status"
    check "git clone https://github.com/i3/i3status.git" \
        "failed to clone i3status source"
fi
if $I3BLOCKS; then
    log "Checking out i3blocks"
    check "git clone https://github.com/vivien/i3blocks.git" \
        "failed to clone i3blocks source"
fi
if $DUNST; then
    log "Checking out glib2"
    check "git clone https://github.com/GNOME/glib.git" \
        "failed to clone glib2 source"
    log "Checking out dunst"
    check "git clone https://github.com/dunst-project/dunst.git" \
        "failed to clone dunst source"
fi

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
check "./configure --prefix=$bldpath/usr XCB{,_RENDER,_RENDERUTIL,_IMAGE}_CFLAGS=-I$bldpath/usr/include XCB{,_RENDER,_RENDERUTIL,_IMAGE}_LIBS=-L$bldpath/usr/lib64" \
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
[[ -d $bldpath/usr/lib/ruby/1.8 ]] && export RUBYLIB="$bldpath/usr/lib/ruby/1.8"
check "./configure --prefix $bldpath/usr" \
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
check "make DEBUG=0 LIBSN_CFLAGS+=-I{$bldpath,}/usr/include/startup-notification-1.0 LIBEV_CFLAGS+=-I${bldpath,}/usr/include/libev XCURSOR_LIBS+=\"-lxcb-image -lxcb-render-util -lxcb-cursor -lxcb\"" \
    "failed to compile i3"
check "make PREFIX=$prepath install" \
    "failed to install i3"

# i3status
if $I3STATUS; then
    log "Compiling i3status"
    check "cd $srcpath/i3status" \
        "failed to enter i3status source directory"
    check "git checkout 2.9" \
        "failed to check out i3status 2.9"
    fixenv
    # TODO: fix manpage generation, a2x errors (remember to add back asciidoc to basepkgs)
    check "sed -i -e 's/manpage$//' Makefile" \
        "failed to adjust configuration to disable manpage generation"
    check "sed -i -e '/install.*man/ s/^/#/' Makefile" \
        "failed to adjust configuration to disable manpage installation"
    check "make" \
        "failed to compile i3status"
    check "make PREFIX=$prepath install" \
        "failed to install i3status"
fi

# i3blocks
if $I3BLOCKS; then
    log "Compiling i3blocks"
    check "cd $srcpath/i3blocks" \
        "failed to enter i3blocks source directory"
    # Last known working checkout, feel free to modify
    # Prefer newer build setup compared to latest release at time of writing (1.4)
    check "git checkout ec050e79ad8489a6f8deb37d4c20ab10729c25c3" \
        "failed to check out i3blocks"
    fixenv
    check "./autogen.sh" \
        "failed to autogen i3blocks"
    check "./configure --prefix=$prepath LIBS=-lrt" \
        "failed to configure i3blocks"
    check "make" \
        "failed to compile i3blocks"
    check "make install" \
        "failed to install i3blocks"
fi

# dunst
if $DUNST; then
    # glib2 2.44.1
    log "Compiling glib2"
    check "cd $srcpath/glib" \
        "failed to enter glib2 source directory"
    check "git checkout 2.36.4" \
        "failed to check out glib2 2.36.4"
    fixenv
    check "./autogen.sh" \
        "failed to autogen glib2"
    check "./configure --prefix=$bldpath/usr" \
        "failed to configure glib2"
    check "make" \
        "failed to compile glib2"
    check "make install" \
        "failed to install glib2"

    # dunst 1.3.2
    log "Compiling dunst"
    check "cd $srcpath/dunst" \
        "failed to enter dunst source directory"
    check "git checkout v1.3.2" \
        "failed to check out dunst 1.3.2"
    fixenv
    check "patch config.mk < ../../patch/dunst/config.mk.diff" \
        "failed to patch config.mk"
    check "patch src/x11/screen.c < ../../patch/dunst/screen.c.diff" \
        "failed to patch src/x11/screen.c"
    check "patch src/settings.c < ../../patch/dunst/settings.c.diff" \
        "failed to patch src/settings.c"
    check "patch dunstify.c < ../../patch/dunst/dunstify.c.diff" \
        "failed to patch dunstify.c"
    check "CPPFLAGS=-DFORCE_XINERAMA make" \
        "failed to compile dunst"
    check "make dunstify" \
        "failed to compile dunstify"
    check "make PREFIX=$prepath SERVICEDIR_DBUS=$prepath/share/dbus-1/services install" \
        "failed to install dunst"
fi

log "Packaging $PREFIX..."
check "mkdir -p $prepath/lib" \
    "failed to create directory $prepath/lib"
for ex in $prepath/bin/{i3,i3bar,i3status,i3blocks,dunst,dunstify}; do
    [[ -e $ex ]] || continue
    while read -r line; do
        lib=${line%% => *}
        lib=${lib%%.so*}.so
        [[ $lib =~ ^/ ]] && continue
        for bldlib in $(find $bldpath -name $lib*); do
            check "cp -d $bldlib $prepath/lib" \
                "failed to copy library from intermediary build output area to package area"
        done
    done < <(ldd $ex)
done
# Patch and copy dmenu
check "sed -i -e 's/test -x \"$file\"/test -f \"$file\" \&\& test -x \"$file\"/' $bldpath/usr/bin/dmenu_path" \
    "failed to patch dmenu"
check "cp $bldpath/usr/bin/dmenu* $prepath/bin" \
    "failed to copy dmenu"
# Copy dunstify
check "cp $bldpath/src/dunst/dunstify $prepath/bin" \
    "failed to copy dunstify"

if $DEBUG; then
    log "Skipping cleanup of $srcpath for debug build"
    log "Skipping cleanup of $bldpath for debug build"
else
    log "Cleaning up..."
    check "rm -rf $srcpath" \
        "Failed to clean up source area"
    check "rm -rf $bldpath" \
        "Failed to clean up intermediary build output area"
fi

log "Done!"

