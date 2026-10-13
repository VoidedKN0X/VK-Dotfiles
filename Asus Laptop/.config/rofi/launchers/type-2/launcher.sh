#!/usr/bin/env bash

## Author : Aditya Shakya (adi1090x)
## Github : @adi1090x
#
## Rofi   : Launcher (Modi Drun, Run, File Browser, Window)
#
## Available Styles
#
## style-1 (only style shipped with these dotfiles)

dir="$HOME/.config/rofi/launchers/type-2"
theme='style-1'

## Run
rofi \
    -show drun \
    -theme "${dir}/${theme}.rasi" \
    -no-levenshtein-sort
