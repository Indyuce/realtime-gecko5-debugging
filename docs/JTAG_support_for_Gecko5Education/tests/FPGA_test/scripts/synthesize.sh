yosys -s yosis.script
if  [ $? -eq 0 ]; then 
echo "Synthesis completed sucessfully"
	nextpnr-ecp5 --timing-allow-fail --85k --package CABGA381 --json ./button_led.json --lpf fpga.lpf --textcfg button_led.config
	ecppack --compress --freq 62.0 --input button_led.config --bit button_led.bit
	openFPGALoader button_led.bit
else 
	echo "Error in synthesis" 
fi