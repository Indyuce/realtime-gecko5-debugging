import os
import sys

if len(sys.argv) < 3:
    print("Usage: python3 create_script.py <directory> <top_module>")
    sys.exit(1)
directory = sys.argv[1]
top_module = sys.argv[2]

files = os.listdir(directory)
files = [file for file in files if file.endswith(".v")]
print(files)
try :
    os.mkdir(f"{directory}/scripts")
except FileExistsError:
    pass
with open(f"{directory}/scripts/yosis.script", "w") as f:
    for file in files:
        f.write(f"read_verilog -sv ../{file}\n")
    f.write(f"synth_ecp5 -top {top_module} -json {top_module}.json")

with open(f"{directory}/scripts/synthesize.sh", "w") as f:
    f.write("yosys -s yosis.script\n")
    f.write("if  [ $? -eq 0 ]; then \necho \"Synthesis completed sucessfully\"\n")
    f.write(f"\tnextpnr-ecp5 --timing-allow-fail --85k --package CABGA381 --json ./{top_module}.json --lpf fpga.lpf --textcfg {top_module}.config\n")

    f.write(f"\tecppack --compress --freq 62.0 --input {top_module}.config --bit {top_module}.bit\n")


    f.write(f"\topenFPGALoader {top_module}.bit\n")
    f.write("else \n\techo \"Error in synthesis\" \nfi")

os.chmod(f"{directory}/scripts/synthesize.sh", 0o755)




