vsim -t ps or1300DualCore 
add wave -hex cpu1/execute/theMultiplier/*
add wave -hex cpu1/execute/*
#add wave -hex uart1/*
#add wave -hex cpu1/debug/*
#add wave -hex cpu1/decoder/*
#add wave -hex cpu1/execute/*
#add wave -hex cpu1/branch/*
#add wave -hex cpu1/execute/isJump
#add wave -hex cpu1/execute/isJumpIn
#add wave -hex cpu1/execute/jumpRegister
#add wave -hex cpu1/theIcache/*
#add wave -hex cpu1/execute/instructionAddress
#add wave -hex cpu1/forward/*
#add wave -hex cpu1/decoder/*
#add wave -hex cpu1/datacache/*
#add wave -hex cpu1/datacache/s_weDataCacheVector
#add wave -hex cpu1/datacache/s_rwDataCache
#add wave -hex cpu1/datacache/s_rwDataIndex
#add wave -hex cpu1/datacache/s_dataToCache
#add wave -hex cpu1/datacache/s_dataFromCache1
#add wave -hex cpu1/datacache/memoryAddress
#add wave -hex cpu1/datacache/memoryStore
#add wave -hex cpu1/datacache/cachedWrite
#add wave -hex cpu1/datacache/s_stage2MemoryAddressReg
#add wave -hex cpu1/datacache/s_busAddressReg
#add wave -hex cpu1/datacache/s_dataIndexAddr
#add wave -hex cpu1/datacache/s_weBusRegs
#add wave -hex cpu1/datacache/s_busAddressNext
#add wave -hex cpu1/datacache/s_busTransactionTypeReg
#add wave -hex cpu1/datacache/requestBus
#add wave -hex cpu1/datacache/busAccessGranted
#add wave -hex cpu1/datacache/s_writeThroughRequired
#add wave -hex cpu1/datacache/s_writeThroughDoneReg
#add wave -hex cpu1/datacache/s_busTransactionTypeReg
#add wave -hex cpu1/datacache/s_cacheStateReg
#add wave -hex cpu1/datacache/s_stage2CWriteReg
#add wave -hex cpu1/datacache/s_stage2Hit1Reg
#add wave -hex cpu1/datacache/s_stage2Hit2Reg
#add wave -hex cpu1/datacache/s_stage2Hit3Reg
#add wave -hex cpu1/datacache/s_stage2Hit4Reg
#add wave -hex cpu1/datacache/s_stage2State1Reg
#add wave -hex cpu1/datacache/s_stage2State2Reg
#add wave -hex cpu1/datacache/s_stage2State3Reg
#add wave -hex cpu1/datacache/s_stage2State4Reg
#add wave -hex cpu1/datacache/*
#add wave -hex spm1/*
#add wave -hex spm1/dma/*
#add wave s_busError
#add wave -hex sevenSeg/*
#add wave -hex s_systemClock
#add wave -hex s_resetCountReg
#add wave -hex s_softResetCountReg
#add wave -hex s_reset
#add wave -hex s_performSoftReset
#add wave -hex s_softBios
add wave -hex cpu1/registers/s_weEpcr
add wave -hex cpu1/registers/writeSpr
add wave -hex cpu1/registers/s_supervisionMode
add wave -hex cpu1/registers/writeSprIndex
add wave -hex cpu1/registers/stall
add wave -hex cpu1/registers/s_epcrNext
add wave -hex cpu1/registers/s_epcrSpr
#add wave -hex cpu1/registers/pllReset
#add wave -hex cpu1/registers/s_softBiosNext
#add wave -hex cpu1/registers/s_softBiosReg
#add wave -hex cpu1/registers/s_previosSoftBiosReg
#add wave -hex flash/quad/*
#add wave -hex flash/*
#add wave -hex sdram/*
force clock12MHz 0 0 , 1 1 -repeat 2
force clock50MHz 0 0 , 1 1 -repeat 2
force nReset 0 0 , 1 10
force RxD 1
force spiSoIo1 1
force sdramData 16#1122
#run 30000
run 80000
#run 1500000
