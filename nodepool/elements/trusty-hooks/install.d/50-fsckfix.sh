#!/bin/bash

if [ 'trusty' == $DIB_RELEASE ]; then
    echo Automatically repair filesystems with inconsistencies during boot
    echo FSCKFIX=yes > /etc/default/rcS

    echo Trace /etc/default/rcS
    cat /etc/default/rcS
fi