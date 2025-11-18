import sys
import time
import subprocess
import socket


MAGENTA = {"RGB": [0, 1, 0], "name": 'M'}
RED = {"RGB": [1, 1, 0], "name": 'R'}
GREEN = {"RGB": [1, 0, 1], "name": 'G'}
BLUE = {"RGB": [0, 1, 1], "name": 'B'}
WHITE = {"RGB": [0, 0, 0], "name": 'W'}
BLACK = {"RGB": [1, 1, 1], "name": 'K'}
YELLOW = {"RGB": [1, 0, 0], "name": 'Y'}
CYAN = {"RGB": [0, 0, 1], "name": 'C'}

def telenet_send(sock, cmd):
    sock.sendall((cmd + "\n").encode())
    output = b""
    while not output.endswith(b"> "):
        output += sock.recv(1024)
    # print(output.decode(), end="")

def read_command():
    inputed_command = input("Enter command: ")
    command = inputed_command.split(" ")
    return command

def display_help():
        print("Available commands:")
        print(" - led <number/all> <color> - Set the color of the LED")
        print("\t R, Red - Red")
        print("\t G, Green - Green")
        print("\t B, Blue - Blue")
        print("\t W, White - White")
        print("\t K, Black - Black")
        print("\t Y, Yellow - Yellow")
        print("\t C, Cyan - Cyan")
        print("\t M, Magenta - Magenta")
        print(" - column <number> - Set the column number")
        print(" - exit - Exit the program")
        print(" - help - Display this help message")

def updtae_led(led_number, color, status):
    status["LEDS_READABLE"][led_number] = color["name"]
    # print(status["LEDS_READABLE"])
    status["LEDS"][led_number] = color["RGB"][0]
    status["LEDS"][led_number + 10] = color["RGB"][1]
    status["LEDS"][led_number + 20] = color["RGB"][2]
    # print(status["LEDS"])

def send_leds(sock, status):
    led_value = int("".join(map(str, status["LEDS"])), 2)
    if (status["instruction"] != 0x32):
        status["instruction"] = 0x32
        telenet_send(sock, "irscan ecp5.tap 0x32")
    telenet_send(sock, f"drscan ecp5.tap 31 {led_value}")


def send_column(sock, status):
    column_value = status["column"]
    if (status["instruction"] != 0x38):
        status["instruction"] = 0x38
        telenet_send(sock, "irscan ecp5.tap 0x38")
    telenet_send(sock, f"drscan ecp5.tap 5 {column_value}")

def handle_command(command, sock, status):
    if command[0].lower() == "led":
        if len(command) != 3:
            print("Invalid command")
            display_help()
            return
        led_number = command[1]
        color = command[2].lower()
        all_leds = False
        if led_number == "all":
            all_leds = True
        else:
            try :
                led_number = int(led_number)
            except ValueError:
                print("Invalid LED number must be between 0 and 9 or 'all'")
                return
            if led_number < 0 or led_number >= 10:
                print("Invalid LED number must be between 0 and 9 or 'all'")
                return
        if color == "r" or color == "red":
            color = RED
        elif color == "g" or color == "green":
            color = GREEN
        elif color == "b" or color == "blue":
            color = BLUE
        elif color == "w" or color == "white":
            color = WHITE
        elif color == "k" or color == "black":
            color = BLACK
        elif color == "y" or color == "yellow":
            color = YELLOW
        elif color == "c" or color == "cyan":
            color = CYAN
        elif color == "m" or color == "magenta":
            color = MAGENTA
        else:
            print("Invalid color")
            display_help()
            return
        
        if all_leds:
            for i in range(10):
                updtae_led(i, color, status)
        else:
            updtae_led(led_number, color, status)
        send_leds(sock, status)
        
    elif (command[0].lower() == "column"):
        if len(command) != 2:
            print("Invalid command")
            display_help()
            return
        try:
            column = int(command[1])
        except ValueError:
            print("Invalid column number must be between 0 and 11")
            return
        if column < 0 or column > 11:
            print("Invalid column number must be between 0 and 11")
            return
        status["column"] = column
        send_column(sock, status)
    else :
        if (command[0].lower() != "help"):
            print("Invalid command")
        display_help()

def print_status(status):
    print("====================")
    print("Column: ", status["column"])
    print("Indexes: ", end="")
    for i in range(len(status["LEDS_READABLE"])):
        print(f"{i}", end=" ")

    print("\nColors:  ", end="")
    for i in range(len(status["LEDS_READABLE"])):
        print(f"{status['LEDS_READABLE'][i]}", end=" ")
    print("\n====================")
    print()


if __name__ == "__main__": 
    print("Not available with this milestone")
    exit(1)
    SERVER_IP = "127.0.0.1"
    SERVER_PORT = 4444

    path_to_config = "./config.cfg"
    if len(sys.argv) > 1:
        if sys.argv[1] == "-h":
            print("Usage: python jtag_led.py [path_to_config]")
            sys.exit(0)
        else:
            path_to_config = sys.argv[1]
        
    # Launching the server
    # Start the server
    print("Starting the server...")
    try:
        server_process = subprocess.Popen(f"openocd -f {path_to_config}", shell=True, stdout=None, stderr=None, start_new_session=True)
    except Exception as e:
        print(f"Failed to start the server process: {e}")
        sys.exit(1)


    time.sleep(1)  # Wait for the server to start
    print("Server started.\n")
    print("Connecting to the server...")

    HOST = "localhost"
    PORT = 4444  # Change this if needed

    LEDS = [0 for i in range(30)]
    LEDS_READABLE = ["W" for i in range(10)]
    column = 0
    instruction = 0x0
    status = {"LEDS" : LEDS, "column": column, "instruction": instruction, "LEDS_READABLE": LEDS_READABLE}

    try:
        # Connect to the server using socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((HOST, PORT))

        # Read and print the server's response
        response = b""
        while not response.endswith(b"> "):
            response += sock.recv(1024)
        print("Connected to the server.\n")

        print("Start sending commands.")
        print("Type 'help' for available commands.")
        print_status(status)

        while True:
            command = read_command()
            if command[0].lower() == "exit":
                break
            handle_command(command, sock, status)
            print_status(status)

        sock.close()  # Close the connection
    except Exception as e:
        print(f"Error: {e}")
    finally:
        server_process.terminate()
        print("Disconnected.")
