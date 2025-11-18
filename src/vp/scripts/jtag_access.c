#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <stdarg.h>

#define SERVER_PORT 4444
#define SERVER_ADDR "127.0.0.1"
#define BUFFER_SIZE 1024
#define DEFAULT_ADDRESS "0x0000000"
#define DEFAULT_BURST_SIZE 16
#define DEFAULT_SIZE 1
#define USED_INSTRUCTION "0x32"
#define TAP_NAME "ecp5.tap"
#define MAX_BLOCK_SIZE 128
#define SHIFT_VALUE 37
#define DEFAULT_COMMAND "drscan ecp5.tap 37 0\n"

#define SET_ADDRESS 1
#define SET_BURST 3

#define WRITE_BUFFER 8
#define READ_BUFFER 9


#define LAUNCH_WRITE 10
#define LAUNCH_READ 11
#define SWITCH_BUFFER 12

typedef struct {
    char *address;
    size_t burst_size;
    size_t size;
    int read_not_write_flag;
} jtag_options_t;


int debug_mode = 0; // Global debug mode flag

void print_debug(const char *fmt, ...) {
    if (debug_mode) {
        va_list args;
        va_start(args, fmt);
        printf("DEBUG: ");
        vprintf(fmt, args);
        va_end(args);
    }
}

int ask_user_hex_value() {
    char input[BUFFER_SIZE];
    int value;
    char *endptr;

    while (1) {
        printf("Enter a 32-bit hex value (without 0x prefix): ");
        if (fgets(input, sizeof(input), stdin) != NULL) {
            value = strtol(input, &endptr, 16);
            // Check for valid conversion, only newline after number, and 32-bit range
            if (endptr != input && (*endptr == '\n' || *endptr == '\0')) {
                return value & 0xFFFFFFFF; // Ensure value is within 32-bit range
            }
        }
        fprintf(stderr, "Invalid hex value. Please enter a 32-bit value (0 to FFFFFFFF).\n");
    }
}

long extract_middle_number(const char *response) {
    char buffer[1024];
    strncpy(buffer, response, sizeof(buffer));
    buffer[sizeof(buffer) - 1] = '\0';  // Ensure null termination

    char *line = strtok(buffer, "\n");
    int line_index = 0;

    while (line != NULL) {
        if (line_index == 1) {
            // Line 1 is the second line (indexing from 0)
            return strtol(line, NULL, 16);  // Base 10
        }
        line = strtok(NULL, "\n");
        line_index++;
    }

    return -1;  // Return -1 if the second line wasn't found
}

int get_DMA_busy(int status){
    return (status >> 12) & 0x1; 
}

int get_DMA_block_size(int status) {
    return (status>>4) & 0xFF; // Extract the lower 16 bits
}

long receive_data(int sock, char *buffer, size_t size) {
    char temp[BUFFER_SIZE + 1];
    size_t total_received = 0;
    buffer[0] = '\0'; // Initialize buffer

    while (total_received < size) {
        ssize_t byte_received = recv(sock, temp, BUFFER_SIZE-1, 0);
        if (byte_received <= 0) {
            perror("Receive failed or connection closed");
            return 1;
        }
        temp[byte_received] = '\0'; // Null-terminate temp

        if (total_received + byte_received < size) {
            strncat(buffer, temp, size - total_received - 1);
            total_received += byte_received;
        } else {
            fprintf(stderr, "Response too large\n");
            break;
        }
        // printf("Temp: %s\n", temp);
        // printf("Response: %s\n", buffer);

        // Check for prompt indicating end of response
        if (strstr(buffer, "\n> ") != NULL || strstr(buffer, "> ") != NULL) {
            break;
        }
    }
    
    return extract_middle_number(buffer);
}

void send_command(int sock, const char *command){
    print_debug("Sending command: %s\n", command);
    ssize_t sent_bytes = send(sock, command, strlen(command), 0);
    if (sent_bytes < 0) {
        perror("Send failed");
    }
}

long shift_data(int sock, int opcode, const char *data, size_t size) {
    char command[BUFFER_SIZE];
    if (data == NULL || size == 0) {
        snprintf(command, sizeof(command), "drscan %s %d %#x\n", TAP_NAME, SHIFT_VALUE, opcode);
    } else {
        snprintf(command, sizeof(command), "drscan %s %d %s%x\n", TAP_NAME, SHIFT_VALUE, data, opcode);
    }
    send_command(sock, command);
    char response[BUFFER_SIZE];
    ssize_t received_bytes = receive_data(sock, response, BUFFER_SIZE);
    if (received_bytes < 0) {
        fprintf(stderr, "Failed to receive data after sending command: %s\n", command);
        exit(EXIT_FAILURE);
    }
    return extract_middle_number(response);
}

void run_idle(int sock, size_t cycles) {
    char command[BUFFER_SIZE];
    snprintf(command, sizeof(command), "runtest %zu\n", cycles);
    send_command(sock, command);
    char answer[BUFFER_SIZE];
    receive_data(sock, answer, BUFFER_SIZE);
}

void select_instruction(int sock, const char *instruction) {
    char command[BUFFER_SIZE];
    char answer[BUFFER_SIZE];
    snprintf(command, sizeof(command), "irscan %s %s\n", TAP_NAME, instruction);
    send_command(sock, command);
    receive_data(sock, answer, BUFFER_SIZE);
}

void setup_transaction(int sock, const char *address, size_t burst_size) {
    char burst_size_str[BUFFER_SIZE]; 
    shift_data(sock, SET_ADDRESS, address, strlen(address));
    snprintf(burst_size_str, sizeof(burst_size_str), "%#zx", burst_size);
    shift_data(sock, SET_BURST, burst_size_str, strlen(burst_size_str));

    long res = shift_data(sock, 0, NULL, 0); // Shift to the next state
    printf("Transaction setup complete with address %s and burst size %zu\n", address, burst_size);
    print_debug("Response: %ld\n", res);
    
}

void print_usage() {
    printf("Connects to OpenOCD Tcl server at %s:%d\n", SERVER_ADDR, SERVER_PORT);
    printf("Usage: ");
    printf("\t-h \t\t Show this help message\n");
    printf("\t-addr <address>  Set base address for the operation (default: %s)\n", DEFAULT_ADDRESS);
    printf("\t-bs <size> \t Set the burst size (default: %d)\n", DEFAULT_BURST_SIZE);
    printf("\t-s <size> \t Set the size of the data to read/write (default: %d)\n", DEFAULT_SIZE);
    printf("\t-r \t\t Read data from the target, default operation (excludes -w)\n");
    printf("\t-w \t\t Write data to the target (excludes -r)\n");
    printf("\t-d \t\t Debug mode, prints additional information\n");
    return;
}

void wait_DMA(int sock){
    int dma_operation_running = 0;
    while (dma_operation_running) {
        long res = shift_data(sock, 0, NULL, 0);
        dma_operation_running = get_DMA_busy(res);
    }
    print_debug("DMA operation completed\n");
}

int do_read(int sock, jtag_options_t options) {
    // Select the instruction for reading
    select_instruction(sock, USED_INSTRUCTION);
    size_t remaining_size = options.size;
    int address = strtol(options.address, NULL, 16);
    setup_transaction(sock, options.address, options.burst_size-1);

    while (remaining_size > 0) {
        char address_str[BUFFER_SIZE];
        snprintf(address_str, sizeof(address_str), "%#x", address);
        shift_data(sock, SET_ADDRESS, address_str, strlen(address_str));
        size_t read_size = remaining_size < MAX_BLOCK_SIZE ? remaining_size : MAX_BLOCK_SIZE;
        remaining_size -= read_size;
        print_debug("Reading %zu bytes from address %#x\n", read_size, address);

        char str_read_size[10];
        snprintf(str_read_size, sizeof(str_read_size), "%#zx", read_size);
        // Send the read command
        shift_data(sock, LAUNCH_READ, str_read_size, 10);
        run_idle(sock, 5); // Run idle for 1 cycle

        wait_DMA(sock); // Wait for the DMA operation to complete

        // Wait for the DMA operation to complete
        print_debug("Ready to switch buffer\n");
        
        // Switch to the next buffer
        shift_data(sock, SWITCH_BUFFER, NULL, 0);
        run_idle(sock, 5); 

        // Read the status and get the block size
        long res = shift_data(sock, 0, NULL, 0);
        print_debug("DMA operation done Block size: %d\n", get_DMA_block_size(res));

        // Read the data back
        for (int i = 0; i < read_size; i++) {
            res = shift_data(sock, READ_BUFFER, NULL, 0);
            if (i != 0){
                printf("0x%08x : \t0x%08lx\n", address, res);
                address += 4; // Increment address by 4 bytes
            }
            run_idle(sock, 3); // Run idle for 1 cycle
        }
        res = shift_data(sock, 0, NULL, 0); // Shift to the next state
        printf("0x%08x : \t0x%08lx\n", address, res);
        address += 4; // Increment address by 4 bytes
    }
    return 0;
}

int do_write(int sock, jtag_options_t options) {
    select_instruction(sock, USED_INSTRUCTION);
    size_t remaining_size = options.size;
    int address = strtol(options.address, NULL, 16);
    setup_transaction(sock, options.address, options.burst_size-1);

    while (remaining_size > 0) {
        char buffer[BUFFER_SIZE];
        snprintf(buffer, sizeof(buffer), "%#x", address);
        shift_data(sock, SET_ADDRESS, buffer, strlen(buffer));
        size_t write_size = remaining_size < MAX_BLOCK_SIZE ? remaining_size : MAX_BLOCK_SIZE;
        remaining_size -= write_size;

        print_debug("Writing %zu bytes to address %#x\n", write_size, address);

        for (size_t i = 0; i < write_size; i++) {
            int data_to_write = ask_user_hex_value();
            snprintf(buffer, sizeof(buffer), "0x%x", data_to_write);
            long res = shift_data(sock, WRITE_BUFFER, buffer, strlen(buffer));
            print_debug("Data in the buffer: %ld\n", get_DMA_block_size(res) + 1);
        }

        //wait for the DMA operation to complete
        wait_DMA(sock);
        // Launch the write operation
        shift_data(sock, LAUNCH_WRITE, NULL, 0);
        run_idle(sock, 5); // Run idle for 1 cycle
    }
    wait_DMA(sock); // Wait for the DMA operation to complete
    return 0;
} 

int main(int argc, char *argv[]) {
    // Parse command line arguments

    jtag_options_t options = {
        .address = DEFAULT_ADDRESS,
        .burst_size = DEFAULT_BURST_SIZE,
        .size = DEFAULT_SIZE,
        .read_not_write_flag = 1, // Default to read operation
    };

    for (size_t i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0) {
            print_usage();
            return 0;
        } else if (strcmp(argv[i], "-addr") == 0 && i + 1 < argc) {
            options.address = argv[++i];
        } else if (strcmp(argv[i], "-bs") == 0 && i + 1 < argc) {
            options.burst_size = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
            options.size = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-r") == 0) {
            options.read_not_write_flag = 1;
        } else if (strcmp(argv[i], "-w") == 0) {
            options.read_not_write_flag = 0;
        } else if (strcmp(argv[i], "-d") == 0) {
            // Debug mode, can be used to print additional information
            printf("Debug mode enabled\n");
            debug_mode = 1;
            
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage();
            return 1;
        }
    }


    // Initialize socket and connect to OpenOCD Tcl server
    int sock;
    struct sockaddr_in server;
    char command[BUFFER_SIZE];

    // Create socket
    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("Socket creation failed");
        return 1;
    }

    // Setup server address
    server.sin_family = AF_INET;
    server.sin_port = htons(SERVER_PORT);
    if (inet_pton(AF_INET, SERVER_ADDR, &server.sin_addr) <= 0) {
        perror("Invalid address");
        close(sock);
        return 1;
    }

    // Connect to OpenOCD Tcl server
    if (connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        perror("Connection to server failed");
        close(sock);
        return 1;
    }

    printf("Connected to OpenOCD Tcl server at %s:%d\n", SERVER_ADDR, SERVER_PORT);

    ssize_t response_size = BUFFER_SIZE * 4;
    char response[response_size]; 
    int total_bytes = 0;
    //Receive initial data
    memset(response, 0, sizeof(response));
    total_bytes = receive_data(sock, response, response_size);
    if (total_bytes < 0) {
        fprintf(stderr, "Failed to receive initial data\n");
        close(sock);
        return 1;
    }

    // Reset the JTAG interface
    send_command(sock, "pathmove reset\n");
    receive_data(sock, response, response_size);

    if (options.read_not_write_flag) {
        do_read(sock, options);
    } else {
        do_write(sock, options);
    }


cleanup:
    close(sock);
    return 0;
}
