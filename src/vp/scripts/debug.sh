#src https://openrisc.io/tutorials/docs/Debugging.html

# command for starting openocd when connecting to openrisc on the altera de0 nano
#  -s specifies the files source path
#  -f specifies config files to load

OPENOCD=/opt/oss-cad-suite/share/openocd/scripts
openocd --debug -f configs/interface_ftdi.cfg -f configs/target_or1k.cfg -l openocd.log