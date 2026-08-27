#!/usr/bin/python

import os
import sys
import termios
import time
import tty


def main():
    output = sys.argv[1]
    fd = sys.stdin.fileno()
    previous = termios.tcgetattr(fd)
    received = bytearray()
    try:
        tty.setraw(fd)
        while b"\r" not in received and len(received) < 128:
            received.extend(os.read(fd, 32))
        with open(output, "w", encoding="ascii") as stream:
            stream.write(received.hex() + "\n")
        time.sleep(30)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, previous)


if __name__ == "__main__":
    main()
