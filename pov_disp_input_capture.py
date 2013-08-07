import serial
import sys
from sys import argv
import time



if __name__ == '__main__':

	if len(argv) == 1:
		comport = 0
	elif len(argv) == 2:
		comport = int(argv[2])
	else:
		print("Usage: python pov_disp_input_capture.py <comport number>")
		print("<comport number> is used for /dev/ttyACM<comport number>")
		print("If no comport number is specified, then 0 is used.")
		sys.exit(1)

	device = '/dev/ttyACM'
	device += str(comport)
	timestamp = time.strftime("%a_%d_%b_%Y_%H.%M.%S", time.localtime())
	print(device)
	print(timestamp)

	#Will crash (throws an un-caught exception) if the connection fails
	ser = serial.Serial(device,115200)
	count = 0
	filename = './data/POV_Raw_Input_'
	filename += timestamp
	filename += '.txt'
	f = open(filename, 'w')
	while 1:

		data = ser.readline()

		print(data)

		data = data.split(" ")

		state = int(data[0])

		stateWds = ''

		if state & 1 != 0:
			stateWds += 'BLUE '
		if state & 2 != 0:
			stateWds += 'GREEN '
		if state & 4 != 0:
			stateWds += 'RED '
		if state & 8 != 0:
			stateWds += 'CLEAR '
		if state & 15 == 0:
			stateWds = 'NOP '

		if len(data) != 5:
			dataString = 'CORRUPTED/INCOMPLETE DATA'
		else:
			dataString = stateWds + '\t' + data[1] + '\tdeltaX: ' + data[2] + '\tdeltaY: ' + data[3] + '\tAuto-slow on: ' + data[4] + '\n'
		f.write(dataString)

		if count > 20*60*15:
			f.close()
			timestamp = time.strftime("%a_%d_%b_%Y_%H.%M.%S", time.localtime())
			filename = './data/POV_Raw_Input_'
			filename += timestamp
			filename += '.txt'
			f = open(filename, 'w')
			count = 0

			



	sys.exit(0)