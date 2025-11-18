yosys -s yosis.script
if  [ $? -eq 0 ]; then 
echo "Synthesis completed sucessfully"
	nextpnr-ecp5 --timing-allow-fail --85k --package CABGA381 --json ./test_module.json --lpf fpga.lpf --textcfg test_module.config
	ecppack --compress --freq 62.0 --input test_module.config --bit test_module.bit
	openFPGALoader test_module.bit
else 
	echo "Error in synthesis" 
fi