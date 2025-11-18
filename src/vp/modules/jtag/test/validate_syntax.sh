cd ../verilog
iverilog -o syntax_is_ok *.v ./../../adv_debug_if/verilog/*.v  ../test/jtag_tap.v ../test/JTAGG.v -I./../../adv_debug_if/verilog
rm -f syntax_is_ok
echo "syntax is ok"