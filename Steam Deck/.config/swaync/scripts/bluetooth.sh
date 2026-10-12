#!/bin/bash

bluetoothctl power $(bluetoothctl show | grep -q "Powered: yes" && echo off || echo on)