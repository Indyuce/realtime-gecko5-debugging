

### DC Module list

The debug controler contains four modules. The debug controler dispatches incoming instructions to one of these modules, for this reason all DR scans are always preceeded by a first DR scan to choose what module we want to communicate with.

```c
/* Definitions for the top-level debug unit.  This really just consists
 * of a single register, used to select the active debug module ("chain").
 */
#define DBG_MODULE_SELECT_REG_SIZE	2
#define DBG_MAX_MODULES			4

#define DC_NONE				-1
#define DC_WISHBONE			0
#define DC_CPU0				1
#define DC_CPU1				2
#define DC_JSP				3
```

### Choose module (example of DR scan)


A generic DR scan looks like this.
- Instanciation of `scan_field` containing the information of the scan: size of DR, in and out value. In value goes in the chip through TDI, out value goes out of the chip through TDO. 
- Call to `jtag_add_dr_scan` which queues the scan info.
- Call to `jtag_execute_queue` empties the queue and executes all queued DR scans. Notice how `scan_field` will be out of scope when the method returns, which prooves that the scan info is no longer in use

```c
// src/target/openrisc/or1k_du_adv.c
uint8_t data = chain | (1 << DBG_MODULE_SELECT_REG_SIZE);

struct scan_field field;

field.num_bits = (DBG_MODULE_SELECT_REG_SIZE + 1);
field.out_value = &data; // data written to DR
field.in_value = NULL; // buffer to read from DR
jtag_add_dr_scan(jtag_info->tap, 1, &field, TAP_IDLE); // queue DR scan

int retval = jtag_execute_queue(); // dequeue and execute all queued DR scans
if (retval != ERROR_OK)
    return retval;

// Scan done. Here there's usually code that updates the information stored in the driver
// to keep it up to date with the TAP/DC state.
```

`field.out_value` is a pointer to the data being written to the DR. Here it is a 1xx bit to indicate we want to choose one of the 4 modules.
`field.in_value` usually is an address to a buffer since we're reading data from the chip. Or NULL if we only want to write. Here the sample code is for selecting a module so there's no data to read.



## Memory read

In order to perform a memory read:
- call to `adbg_select_module`, one **dr scan** to select wishbone bus module
- call to `adbg_wb_burst_read` for each single burst read.
    - call to `adbg_burst_command` which sends a **DR scan** containing info about the incoming burst read: address and size.
    - finally, the actual **DR scan** that reads data from memory location

Total number of DR scans per memory read: `1 + 2 * <burst_nb>`

```c
static int or1k_adv_jtag_read_memory(struct or1k_jtag *jtag_info,
			    uint32_t addr, uint32_t size, int count, uint8_t *buffer)
{
	LOG_DEBUG("Reading WB%" PRIu32 " at 0x%08" PRIx32, size * 8, addr);

    // initialization code
    //...........

	retval = adbg_select_module(jtag_info, DC_WISHBONE); // Select BUS module
	if (retval != ERROR_OK)
		return retval;

	int block_count_left = count;
	uint32_t block_count_address = addr;
	uint8_t *block_count_buffer = buffer;

	while (block_count_left) {

		int blocks_this_round = (block_count_left > MAX_BURST_SIZE) ?
			MAX_BURST_SIZE : block_count_left;

		retval = adbg_wb_burst_read(jtag_info, size, blocks_this_round,
					    block_count_address, block_count_buffer); // perform single burst read, write to buffer
		if (retval != ERROR_OK)
			return retval;

		block_count_left -= blocks_this_round;
		block_count_address += size * MAX_BURST_SIZE;
		block_count_buffer += size * MAX_BURST_SIZE;
	}

    // correct endianness
    //........

	return ERROR_OK;
}

static int adbg_wb_burst_read(struct or1k_jtag *jtag_info, int size,
			      int count, uint32_t start_address, uint8_t *data)
{
	int retry_full_crc = 0;
	int retry_full_busy = 0;
	int retval;
	uint8_t opcode;

	LOG_DEBUG("Doing burst read, word size %d, word count %d, start address 0x%08" PRIx32,
		  size, count, start_address);

	/* Select the appropriate opcode */
	//...........

	int total_size_bytes = count * size;
	struct scan_field field;
	uint8_t *in_buffer = malloc(total_size_bytes + CRC_LEN + STATUS_BYTES);

retry_read_full:

	/* Send the BURST READ command, returns TAP to idle state */
	retval = adbg_burst_command(jtag_info, opcode, start_address, count);
	if (retval != ERROR_OK)
		goto out;

	field.num_bits = (total_size_bytes + CRC_LEN + STATUS_BYTES) * 8;
	field.out_value = NULL;
	field.in_value = in_buffer;

	jtag_add_dr_scan(jtag_info->tap, 1, &field, TAP_IDLE);

	retval = jtag_execute_queue();
	if (retval != ERROR_OK)
		goto out;

	// check status bit
    // .....................

	buffer_shr(in_buffer, total_size_bytes + CRC_LEN + STATUS_BYTES, shift);

    // check for crc error
	//...................

    // read and process error register
    //...........

out:
	free(in_buffer);

	return retval;
}
```

