/* Team XGearhead (still need a name) Control Box Arduino Uno code. 
   Author: Alex Shie  Latest Revision: 4/1/13
   
   This code first sets up communications with the PS2 device, which will
   be the trackball hooked up with three arcade buttons. Together, these 
   compoenents will appear as a mouse to the Arduino. In the main loop the
   Uno polls the trackball for data, polls the state of the white button,
   and polls the slider pot for its analog value. The analog value of the pot
   is used to change the speed of the motor. The trackball data is combined
   into an unsigned int and is written to serial using the software serial 
   library because using serial comms with pins 0 and 1 is always a bit risky. 
   
   To do (maybe - if it's wanted):
   -Parity bit/checksum for detecting communication failures with the MAX32
   -Slowing the motor down automatically after a period of user inactivity
   -Ramping the motor output over multiple iterations of the loop to a desired
    PWM value so as to prevent large changes in voltage that may damage the motor.
   -Adjust the motor PWM range so that the upper limit is 1000 RPM (or whatever we
    want it to be) and the lower limit is around 6 RPM (so long as it's not 0 RPM).  
    
   Note: the PS/2 library had to be changed slightly to compile correctly. 
         See: http://nootropicdesign.com/forum/viewtopic.php?t=2434
         
         PS/2 Wires 
         Orange -> 3 -> GND
         Blue  -> 4 -> +5V
         White -> 5 -> Clock
         Green -> 1 -> Data
    */

#include <SoftwareSerial.h>
#include <ps2.h>

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
  
  Serial.begin(9600);
  //Serial.println("Control Box Startup");
  //mySerial.begin(4800);
  mouse_init();
  pinMode(MOTOR_PIN, OUTPUT);
  pinMode(WHITE_BUTTON_PIN, INPUT);
  
}


void loop()
{
  int mstat;
  int mx;
  int my;
  int ex = 0;
  int sig = 0x30;
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
  
  /* Control speed of motor according to slider, will have to change
     the mapping after experimentation. Make sure that at the lowest value the
     motor is still spinning slowly. */
  motorOutput = map(potValue, 0, 1023, 20, 255);
  analogWrite(MOTOR_PIN, motorOutput);

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

  /* Add a delay if things are going too fast for debugging*/
  delay(20);


  Serial.write(sig);//sig is used to declare the start of a message
  Serial.write(mstat);
  Serial.write(mx);
  Serial.write(my);
  //Serial.write(ex);
  
  //Uncomment this stuff when you can do serial communications with both the MAX32 and a computer
  /*
  
  numPacketsSent++;
  
  if (mySerial.available()) {
    
    
    echoedData = mySerial.read();
    // Just checks for exact match, can do parity/checksum stuff later 
    
    if (echoedData != combinedData) {
      numCommErrors++;
      failureRate = ((double)(numCommErrors))/numPacketsSent;
      Serial.print("Serial data inconsistent! Current failure rate: ");
      Serial.print(failureRate, DEC);
      Serial.print("\tPackets sent: ");
      Serial.print(numPacketsSent, DEC);
      Serial.print("\tPackets inconsistent: ");
      Serial.println(numCommErrors, DEC);
    }
  }*/
    
  
  
}
