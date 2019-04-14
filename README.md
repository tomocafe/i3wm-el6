# i3wm-el6

This is a script to build the [i3 window manager](https://i3wm.org) for CentOS / RedHat 6.x (el6) in user space (no root required).

Since el6 is old and missing dependencies required by recent i3wm versions, this script builds i3 v4.8 (c. 2014) without pango support. Remember to refer only to the [v4.8 i3wm user guide](https://i3wm.org/docs/4.8/userguide.html) and not the current latest version on the main site.

## Build instructions

Run the script from the `i3wm-el6/` directory.

    $ ./build.sh

By default, the binaries will be placed in a directory named `i3-4.8`. After successful installation, you will need to set your `PATH` and `LD_LIBRARY_PATH` environment variables accordingly to point to the new installation.

    export PATH=${PATH:+$PATH:}$(readlink -f i3-4.8/bin)
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$(readlink -f i3-4.8/lib)

The first section of the `build.sh` script are configurable parameters, including `PREFIX` which controls the name of the final output directory. The `SRCDIR` and `BLDDIR` are intermediary directories that are cleaned up at the end.

If you encounter any errors that require debugging, turn on `DEBUG=true` and inspect the `$BLDDIR.log` file for details on what went wrong.

The script can build two status line generators: [`i3status`](https://github.com/i3/i3status) and [`i3blocks`](https://github.com/vivien/i3blocks). By default, both are built; you can control which ones are built by setting the `I3STATUS` and `I3BLOCKS` variables.

## Pseudocode

In essence, the script is doing this:

1. Download and extract rpm packages required by i3wm if they are not already installed on the system
2. Check out and compile source for modules required by i3wm if they are not readily available as rpm packages
3. Check out and compile i3 version 4.8
4. Package the i3 binaries and dependency library files

## Technical limitations

Version 4.8 is the last i3wm release which does not require `libxkbcommon` which is not readily available for el6.

Pango support is removed from this build due to a lack of support for `pango`/`cairo`. Theoretically this can be compiled in user space, but this is a large endeavor and a change of that magnitude should probably done system-wide.

## Motivation

This script is intended mostly for enterprise users stuck on old el6 systems who want to use i3 but don't want to bother their sysadmins, and are willing to put up with a slightly older i3wm version and lack of pango support.
