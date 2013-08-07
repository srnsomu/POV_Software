/* Team XGearhead (still need a name) Encoder + Serial comms test with MAX32 and UNO
   Author: Alex Shie  Latest Revision: 4/19/13
   
    */

#include <SoftwareSerial.h>

#define SOFT_SERIAL_RX_PIN 10
#define SOFT_SERIAL_TX_PIN 11

SoftwareSerial mySerial(SOFT_SERIAL_RX_PIN, SOFT_SERIAL_TX_PIN); // RX, TX


void setup()
{
  
  Serial.begin(115200);
  mySerial.begin(115200);

  pinMode(SOFT_SERIAL_RX_PIN, INPUT);
  pinMode(SOFT_SERIAL_TX_PIN, OUTPUT);
  Serial.println("MAX32 to UNO encoder values: ");

  
}


void loop()
{
  int encoderVal;
  //Only print updated encoder values
  if (mySerial.available()) {
    encoderVal = mySerial.read();
    Serial.println(encoderVal);
  }
  
}
