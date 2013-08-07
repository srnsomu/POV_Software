/* Team XGearhead (still need a name) Control Box Arduino Uno code. 
   Author: Alex Shie  Latest Revision: 4/16/13
   
   This code first sets up communications with the PS2 device, which will
   be the trackball hooked up with three arcade buttons. Together, these 
   compoenents will appear as a mouse to the Arduino. In the main loop the
   Uno polls the trackball for data, polls the state of the white button,
   and polls the slider pot for its analog value. The analog value of the pot
   is used to change the speed of the motor. The trackball data is sent as 3 bytes
   with an additional byte preceding the data to mark the start of a string of data. 
   The baud rate is 115200.
   
   The UNO code currently only uses the normal serial lines under the assumption that 
   they go to the MAX32. If you want to monitor the UNO’s output while it’s talking 
   to the MAX32, then you need to change the code so that the software serial lines 
   go to the MAX32 while the normal serial lines will be used automatically over USB 
   to your computer. 

   As of now the Uno doesn't wait to receive a response from the MAX32 because the 
   MAX32 doesn't echo back the data right now (speed reasons, but we can try later). 

   
   To do (maybe - if it's wanted):
   -Parity bit/checksum for detecting communication failures with the MAX32
   -Slowing the motor down automatically after a period of user inactivity
   -Ramping the motor output over multiple iterations of the loop to a desired
    PWM value so as to prevent large changes in voltage that may damage the motor.
   -Adjust the motor PWM range so that the upper limit is 1000 RPM (or whatever we
    want it to be) and the lower limit is around 6 RPM (so long as it's not 0 RPM).  
    
   Note: the PS/2 library had to be changed slightly to compile correctly. 
         See: http://nootropicdesign.com/forum/viewtopic.php?t=2434
         These numbers refer to the PS2 pinout, not the Arduino pins. 
         PS/2 Wires 
         Orange -> 3 -> GND
         Blue  -> 4 -> +5V
         White -> 5 -> Clock
         Green -> 1 -> Data
    */

#include <SoftwareSerial.h>
#include <ps2.h>

#define AUTO_SLOW_ON true //Set to true if you want the motor to automatically slow down after a lack of user input

#define PS2_CLK_PIN 6
#define PS2_DATA_PIN 5
#define WHITE_BUTTON_PIN 2
#define SOFT_SERIAL_RX_PIN 10
#define SOFT_SERIAL_TX_PIN 11
#define POT_PIN A0
#define MOTOR_PIN 9

PS2 mouse(PS2_CLK_PIN, PS2_DATA_PIN); //Clock, data
SoftwareSerial mySerial(SOFT_SERIAL_RX_PIN, SOFT_SERIAL_TX_PIN); // RX, TX
unsigned long numPacketsSent = 0;
unsigned long numCommErrors = 0;
int targetPWM = 0;
int currentPWM = 0;
int prevPot = 0;
unsigned long count = 0;
unsigned long idleTime = 0;//How long the system has been idle (i.e. time since last user input in ms)

void setPwmFrequency(int pin, int divisor);

/*
 * initialize the mouse. Reset it, and place it into remote
 * mode, so we can get the encoder data on demand.
 */
void mouse_init()
{
  mouse.write(0xff);  // reset
  mouse.read();  // ack byte
  mouse.read();  // blank */
  mouse.read();  // blank */
  mouse.write(0xf0);  // remote mode
  mouse.read();  // ack
  delayMicroseconds(100);
}

void setup()
{
  
  Serial.begin(115200);
  //Serial.println("Control Box Startup");
  mySerial.begin(115200);
  // This is here for script testing purposes
  /*
  for (int i = 0; i < 10; i++) {
    Serial.print("12");
    Serial.print(" ");
    Serial.print("80");
    Serial.print(" ");
    Serial.print(i*2);
    Serial.print(" ");
    Serial.print(200+i);
    Serial.print(" ");
    if(i % 2 == 0)
      Serial.println("T");
    else
      Serial.println("F");
  }*/
  
  mouse_init();
  pinMode(MOTOR_PIN, OUTPUT);
  pinMode(WHITE_BUTTON_PIN, INPUT);
  pinMode(SOFT_SERIAL_RX_PIN, INPUT);
  pinMode(SOFT_SERIAL_TX_PIN, OUTPUT);
  
  idleTime = millis();
  //setPwmFrequency(MOTOR_PIN, 1);//1,8,64,256,1024
  
}


void loop()
{
  int mstat;
  int mx;
  int my;
  int ex = 0;
  int sig = 0x30;
  int rSig = 0;
  int rMstat = 0;
  int rMx = 0;
  int rMy = 0;
  unsigned int potValue = 0;
  unsigned int combinedData = 0;
  unsigned int echoedData = 0;
  unsigned int motorOutput = 0;
  double failureRate = 0.0;

  //mouse_init();
  /* get a reading from the mouse */
  //Serial.print("READ");
  mouse.write(0xeb);  // give me data!
  mouse.read();      // ignore ack
  mstat = mouse.read();
  mx = mouse.read();
  my = mouse.read();
  //Serial.print("WRITE");
  potValue = analogRead(POT_PIN);
  
  
  if(digitalRead(WHITE_BUTTON_PIN) == false) {
    mstat = mstat & B11110111; 
  }
  mstat = mstat & B11001111;
  
  //If there is no user input after 20 seconds, slow down the rotor automatically
  if(mstat & B00001111 == 0 && potValue == prevPot && millis()-idleTime > 180000 && mx == 0 && my == 0 && AUTO_SLOW_ON) {
      targetPWM = 120;
  } else {
  
    /* Control speed of motor according to slider, will have to change
       the mapping after experimentation. Make sure that at the lowest value the
       motor is still spinning slowly. */
    targetPWM = map(potValue, 0, 1023, 70, 255);
    idleTime = millis();
  }
  
  if(targetPWM < 75)
    targetPWM = 0;
  
  //Ensures slower changes to motor input, is it too slow or still too fast?
  /*
  if(currentPWM < targetPWM) {
    currentPWM += 2;
  } else if (currentPWM > targetPWM) {
    currentPWM -= 2;
  }
  
  if(abs(currentPWM - targetPWM) < 2) 
    currentPWM = targetPWM;
  
  if(currentPWM > 255) {
    currentPWM = 255;
  } else if (currentPWM < 0) {
    currentPWM = 0; 
  }*/
  
  //currentPWM = targetPWM; 
  
  if(mx > 127) 
    mx /= 2;
  if(my > 127) 
    my /= 2;
    
  my = max(mx, my);
  mx = map(my, 0, 127, 70, 255);
  if(mx > currentPWM)
    currentPWM = mx;
  
  currentPWM -= 2;
  
  if(currentPWM < 81) {
   currentPWM = 0;
  }
  
  
  analogWrite(MOTOR_PIN, currentPWM);

  /* Print out PS2 data for debugging/testing */
  /*
  Serial.print(mstat, BIN);
  Serial.print("\tX=");
  Serial.print(mx, DEC);
  Serial.print("\tY=");
  Serial.print(my, DEC);
  Serial.print("\tMotor=");
  Serial.print(motorOutput, DEC);
  Serial.println();*/
  
  /*Different set of serial prints to be read by python script*/
  Serial.print(mstat, BIN);
  Serial.print(" ");
  Serial.print(mx, DEC);
  Serial.print(" ");
  Serial.print(my, DEC);
  Serial.print(" ");
  Serial.print(currentPWM);
  Serial.print(" ");
  if (AUTO_SLOW_ON) {
    Serial.println("T"); 
  } else {
    Serial.println("F");
  }

  

  mx = map(potValue, 0, 1023, 0, 255);
  mySerial.write(sig);//sig is used to declare the start of a message
  mySerial.write(mstat);
  mySerial.write(mx);
  mySerial.write(my);
  //Serial.write(ex);
  
  //Uncomment this stuff when you can do serial communications with both the MAX32 and a computer
  //The code below is obsolete, but the serial prints should still be relevant
  /*
  
  /* Add a delay if things are going too fast for debugging. This delay also limits how often
     the MAX32 needs to run the LED state update code. If the MAX32 is too slow, consider 
     raising this delay. If the MAX32 is plenty fast, then you might as well lower this delay
     for a smoother experience. */
  delay(50);
  /*
  numPacketsSent++;
  
  if (mySerial.available() > 3) {
    
    rSig = mySerial.read();
    rMstat = mySerial.read();
    rMx = mySerial.read();
    rMy = mySerial.read();
    // Just checks for exact match, can do parity/checksum stuff later 
    Serial.print(rMstat, BIN);
  Serial.print("\trX=");
  Serial.print(rMx, DEC);
  Serial.print("\trY=");
  Serial.print(rMy, DEC);
  Serial.println();
    
    if (rSig != sig || rMstat != mstat || rMx != mx || rMy != my) {
      numCommErrors++;
      failureRate = ((double)(numCommErrors))/numPacketsSent;
      Serial.print("Serial data inconsistent! Current failure rate: ");
      Serial.print(failureRate, DEC);
      Serial.print("\tPackets sent: ");
      Serial.print(numPacketsSent, DEC);
      Serial.print("\tPackets inconsistent: ");
      Serial.println(numCommErrors, DEC);
    }
  } else {
    Serial.println("No echo after delay!");
  }
    */
  prevPot = potValue;
  count++;
  
}



/**
 * Divides a given PWM pin frequency by a divisor.
 * 
 * The resulting frequency is equal to the base frequency divided by
 * the given divisor:
 *   - Base frequencies:
 *      o The base frequency for pins 3, 9, 10, and 11 is 31250 Hz.
 *      o The base frequency for pins 5 and 6 is 62500 Hz.
 *   - Divisors:
 *      o The divisors available on pins 5, 6, 9 and 10 are: 1, 8, 64,
 *        256, and 1024.
 *      o The divisors available on pins 3 and 11 are: 1, 8, 32, 64,
 *        128, 256, and 1024.
 * 
 * PWM frequencies are tied together in pairs of pins. If one in a
 * pair is changed, the other is also changed to match:
 *   - Pins 5 and 6 are paired on timer0
 *   - Pins 9 and 10 are paired on timer1
 *   - Pins 3 and 11 are paired on timer2
 * 
 * Note that this function will have side effects on anything else
 * that uses timers:
 *   - Changes on pins 3, 5, 6, or 11 may cause the delay() and
 *     millis() functions to stop working. Other timing-related
 *     functions may also be affected.
 *   - Changes on pins 9 or 10 will cause the Servo library to function
 *     incorrectly.
 * 
 * Thanks to macegr of the Arduino forums for his documentation of the
 * PWM frequency divisors. His post can be viewed at:
 *   http://www.arduino.cc/cgi-bin/yabb2/YaBB.pl?num=1235060559/0#4
 */
void setPwmFrequency(int pin, int divisor) {
  byte mode;
  if(pin == 5 || pin == 6 || pin == 9 || pin == 10) {
    switch(divisor) {
      case 1: mode = 0x01; break;
      case 8: mode = 0x02; break;
      case 64: mode = 0x03; break;
      case 256: mode = 0x04; break;
      case 1024: mode = 0x05; break;
      default: return;
    }
    if(pin == 5 || pin == 6) {
      TCCR0B = TCCR0B & 0b11111000 | mode;
    } else {
      TCCR1B = TCCR1B & 0b11111000 | mode;
    }
  } else if(pin == 3 || pin == 11) {
    switch(divisor) {
      case 1: mode = 0x01; break;
      case 8: mode = 0x02; break;
      case 32: mode = 0x03; break;
      case 64: mode = 0x04; break;
      case 128: mode = 0x05; break;
      case 256: mode = 0x06; break;
      case 1024: mode = 0x7; break;
      default: return;
    }
    TCCR2B = TCCR2B & 0b11111000 | mode;
  }
}
