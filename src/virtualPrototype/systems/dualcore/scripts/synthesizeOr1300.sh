#!/bin/bash
rm or1300DualCore.*
yosys -D GECKO5Education -s ../scripts/yosysOr1300.script 
nextpnr-ecp5 --threads 12 --timing-allow-fail --85k --package CABGA381 --json or1300DualCore.json --lpf ../scripts/gecko5.lpf --textcfg or1300DualCore.config
ecppack --compress --freq 62.0 --input or1300DualCore.config --bit or1300DualCore.bit
openFPGALoader or1300DualCore.bit
