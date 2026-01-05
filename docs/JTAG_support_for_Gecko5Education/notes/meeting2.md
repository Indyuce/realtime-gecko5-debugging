# Meeting 2

## Understanding the IP core

The IP core is connected to the JTAGG interface and has two chains inside (here cahin is just one of the two (instructions ) set we want to enter)
Then the IP core define those two instructions set to do something with them initially just light some lights 

to use the JTAGG concretely the idea would be to instantiate it and the linker will set up everything for me
like the DLP, that changes clock frequency

For the architecture for now the VP is not with the good version of the openRISC, no debug interface implemented
But for the first parts of this project no need to have the good version of the openRISC

## Goal for this week

1. Set the timeline no need to be exhaustive especially for the last part
2. Understand perfectly how does the JATGG component works and how to use it, how to select the data, how to select the chain, how to send the data ....

![see the picture on the phone for the global architecture](image/IPCORE.png)
