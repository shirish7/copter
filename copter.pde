
#include <Servo.h>
#include "header.h"

// for main loop timing
uint32_t timer_200Hz, timer_50Hz, timer_10Hz, timer_2Hz;
uint32_t time;
uint8_t counter_10Hz, divider_1Hz, alt_armed;
unsigned long armtime;
uint8_t battindex;

// flight mode stuff
uint8_t flightMode = STABILIZE;



void setup()
{
	// do quick start
	quick_start();
	// see if a ground start is ok to do?
#if DEBUG
	SERIAL_DEBUG.print("Version: ");
	SERIAL_DEBUG.println(VERSION);
#endif
}


void loop()
{
	// 200Hz loop
	// update IMU info
	// calculate stability
	// set motor speed (if armed)
	
	time = micros();
	if (time-timer_200Hz > 5000)
	{
#if TIMING
		SERIAL_DEBUG.print("200\t");
		SERIAL_DEBUG.println(time-timer_200Hz);
#endif
		// check the IMU serial comm for data
		checkIMU();
		// use PID controller to compare targets to actual values
		PID_update();
		PID_calcForces();
		// use PID controller suggestions to set motor speed
		set_motorspeed();

		// need to call this very frequently?
		update_altitude();

		timer_200Hz = time;
	}

	// 10Hz loop
	// check wireless data
	// update flight mode (consider heartbeat)
	
	time = micros();
	if (time-timer_10Hz > 100000)
	{
#if TIMING
//		SERIAL_DEBUG.print("10\t");
//		SERIAL_DEBUG.println(time-timer_10Hz);
#endif
		// check wireless, run operation
		// actually runs at 5Hz
		if (counter_10Hz) checkWireless();
		else if (wirelessOpcode) parseCommand();

		// check to see if i've flipped over
		// if i have, kill motors and let me die gracefully
		if (abs(roll) + abs(pitch) > KILL_ANGLE)
		{
			disarm_motors();
			caution(CAUTION_ANGLE_KILL);
		}

#if DEBUG
//		for (int i=0; i<6; i++)
//		{
//			SERIAL_DEBUG.print(motorval[i]);
//			SERIAL_DEBUG.print("\t");
//		}
//		SERIAL_DEBUG.println();
#endif

		timer_10Hz = time;
		counter_10Hz = !counter_10Hz;
	}
	
	// 2Hz loop
	// check wireless heartbeat timeout
	// get GPS info

	time = micros();
	if (time-timer_2Hz > 500000)
	{
		// check wireless heartbeat
		
		if (heartbeat && time-lastHeartbeat > HEARTBEAT_TIMEOUT)
		{
			// no heartbeat detected from base station
			heartbeat = 0;
			changeFlightmode(SAFEMODE);
#if DEBUG
			SERIAL_DEBUG.println("heartbeat died");
#endif
			caution(CAUTION_COMM_LOST);
		}

		// decay the safemode lift is necessary
		if (flightMode == SAFEMODE)
			safemodeLift = safemodeLift*0.99;

		if (debugmode > 0)
			sendDebug();
		if (dosendPID > 0)
			sendPID();
		// run this at 1Hz
		if (divider_1Hz)
			sendHeartbeat();

		// check physical arming
#if ALLOW_PHYSICAL_ARMING
		if (armed)
		{
			if (digitalRead(PIN_ARM_BUTTON) == HIGH)
			{
				disarm_motors();
				armtime = millis();
			}
		} else {
			if (digitalRead(PIN_ARM_BUTTON) == HIGH)
			{
				if (millis() - armtime > 2000)
				{
					// arm!
					arm_motors();
					while (digitalRead(PIN_ARM_BUTTON) == HIGH) {}
				}
			} else {
				armtime = millis();
			}
		}
#endif

		// check a battery
		checkBattery(battindex);
		battindex++;
		if (battindex == 6) battindex = 0;

		divider_1Hz = !divider_1Hz;
		timer_2Hz = time;
	}
	
}


// main init function
// perform quick start in case of in-air failure
// 
static void quick_start()
{
	// init the main loop timers
	time = micros();
	timer_200Hz = time;
	timer_50Hz = time;
	timer_10Hz = time;
	timer_2Hz = time;
	armtime = 0;
	counter_10Hz = 0;
	divider_1Hz = 0;
	alt_armed = 0;
	commtimer = 0;

	init_motors();
	// initialize PID controller

	// start serial ports
	SERIAL_WIRELESS.begin(WIRELESS_BAUD);
	SERIAL_IMU.begin(IMU_BAUD);
	SERIAL_IMU.setTimeout(10);
#if DEBUG
	SERIAL_DEBUG.begin(DEBUG_BAUD);
#endif
        PID_init();
	// start I2C, SPI if needed here
	// set pinmodes and states
	pinMode(LED_STATUS, OUTPUT);
	pinMode(LED_ARMED, OUTPUT);
	pinMode(PIN_ARM_BUTTON, INPUT);
	// send quick hello over wireless
	SERIAL_WIRELESS.write(COMM_START);
	SERIAL_WIRELESS.write(COMM_MODE_HELLO);
	SERIAL_WIRELESS.write(COMM_END);

	alt_init();

	// should be ready to enter main loop now
#if DEBUG
	SERIAL_DEBUG.print("Quickstart complete after ");
	SERIAL_DEBUG.print(micros());
	SERIAL_DEBUG.println(" us");
#endif
	battindex = 0;
}
