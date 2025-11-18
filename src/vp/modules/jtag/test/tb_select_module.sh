
iverilog -o run_testbench tb_select_module.v  \
   jtag_tap.v JTAGG.v \
   ../verilog/jtag_if.v ../verilog/jtagg_patch.v \
    ./../../adv_debug_if/verilog/*.v -I./../../adv_debug_if/verilog
echo "tb compiled"
./run_testbench
echo "tb ran"