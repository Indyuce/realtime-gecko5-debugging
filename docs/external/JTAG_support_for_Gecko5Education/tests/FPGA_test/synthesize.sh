# Synthesis 
yosys -s yosis.script
# Place and route
if  [ $? -eq 0 ]; then
    echo "Synthesis completed sucessfully"
    nextpnr-ecp5 --timing-allow-fail --85k --package CABGA381 --json ./test_button_light.json \
        --lpf fpga.lpf --textcfg test_button_light.config

    # Create the bit file
    ecppack --compress --freq 62.0 --input test_button_light.config --bit test_button_light.bit

    # Load on the board

    openFPGALoader test_button_light.bit
else 
    echo "Error in synthesis"
fi