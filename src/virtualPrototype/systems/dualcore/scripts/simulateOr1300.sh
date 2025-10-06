#!/bin/bash
rm -rf work
vlib work
cat ../scripts/projectOr1300.files | while read filename; do vlog +define+GECKO5Education $filename; done
vlog ../verilog/ehxpllSimulator.v
vsim -do ../scripts/toplevelOr1300.do

