#!/usr/bin/python3
import time
import subprocess
import re
import sys
from decimal import *

# Setup bash command
command = "vcgencmd measure_temp"
fanPin = 7
tempThreshold = 60 # Rated in degrees Celsius

try:
  import RPi.GPIO as GPIO
  GPIO.setwarnings(False)
  GPIO.setmode(GPIO.BOARD)
  GPIO.setup(fanPin, GPIO.OUT)
except RuntimeError:
  print("Server Platform not Supported")
  sys.exit()

# Repeat forever
while True:
  # Read 10 values in
  totalTemp = 0
  for i in range(10):
    # Read latest temperature from shell
    process = subprocess.Popen(command.split(), stdout=subprocess.PIPE)
    output, error = process.communicate()
    output = str(output) # Convert to a string so string operations work
    output = output[7:11] # Strip out all else but the temperature number
    totalTemp += Decimal(output)

    # Delay for an eighth of a second
    time.sleep(0.125)

  # Average the values taken in
  avgTemp = totalTemp / 10
  # print("avg: " + str(avgTemp))

  # If the temperature is too high, turn the fan on
  if avgTemp > tempThreshold:
    GPIO.output(fanPin, True)
    # print("on")
  else:
    GPIO.output(fanPin, False)
    # print("off")

  # Don't do any more until another 5 seconds. We don't want the fan to be constantly turned on and off repeatedly
  time.sleep(5)