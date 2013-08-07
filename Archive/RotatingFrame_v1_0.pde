/* Team XGearhead (still need a name) Rotating Frame MAX32 code. 
   Author: Alex Shie  Latest Revision: 4/2/13
   

    */

/* Things will be simpler if PULSE_REV == M */
#define PULSE_REV 240 //Pulses/ticks per revolution from the encoder
#define NUM_LEDS 90 //Number of LEDs on the rotating frame
#define M 240 //Number of columns in the perceived display, i.e. width of display

int encoderPos = 0;
unsigned int curX = M/2; //Cursor coordinates - 0,0 is bottom left corner (or right)
unsigned int curY = NUM_LEDS/2;

/* LED state will be represented by the 3 least significant bits, each bit representing
   red on, green on, blue on (blue on is LSB)*/
unsigned char ledState1[M/2][NUM_LEDS/2]; //Contains on/off info for each LED
unsigned char ledState2[M/2][NUM_LEDS/2]; //Contains on/off info for each LED

unsigned long clearTime;
char clearingFlag = 0;

/* ledNum needs to be from 0 to NUM_LEDS - 1, col needs to be from 0 to M-1,
   and the most significant 5 bits of state ought to be 0. */
void ledWrite(int ledNum, int col, char state) {
  char shiftState = state;
  char newState = 0;
  int newCol; 
  if(col < M/2) {
    if(ledNum % 2 == 0) {
      newState = (ledState1[col][ledNum/2] & B11110000)+shiftState;
    } else {
      newState = (ledState1[col][ledNum/2] & B00001111)+(shiftState<<4);
    }
    ledState1[col][ledNum/2] = newState;  
  } else {
    newCol = col - M/2;
    if(ledNum % 2 == 0) {
      newState = (ledState2[newCol][ledNum/2] & B11110000)+shiftState;
    } else {
      newState = (ledState2[newCol][ledNum/2] & B00001111)+(shiftState<<4);
    }
    ledState2[newCol][ledNum/2] = newState; 
  }
}


void setup()
{
  
  Serial1.begin(9600); //Pin 19 RX1, Pin 18 TX1
  attachInterrupt(0, doEncoder, CHANGE);  // encoder pin on interrupt 0 - pin 3
  
  /* Change this accordingly to set the LED pins to outputs*/
  for(int i = 5; i < 50; i++)
    pinMode(i, OUTPUT);
  /* Initializes led states to all off */
  for(int i = 0; i < M/2; i++) {
    for(int j = 0; j < NUM_LEDS/2; j++) {
      ledState1[i][j] = 0;
      ledState2[i][j] = 0;
    }
  }
  /*Time when the last clear command has been received*/
  clearTime = millis();
}


void loop()
{
  /* A non-volatile copy of encoderPos must be used so that the position value
     doesn't change halfway through the loop if there is an encoder tick during
     the loop. This will result in proper behavior if the loop can run entirely at 
     least once between each encoder tick.*/
  int curPos = encoderPos;
  unsigned int receivedData = 0;
  char byte1;
  char byte2;
  char byte3;
  char byte4;
  char color = 0;
  char state1 = 0;
  char state2 = 0;
  char newCol;
  
  /* After "flashing" the screen for 500ms, clear all pixels*/
  if(clearingFlag && millis()-clearTime > 500) {
    for(int i = 0; i < M/2; i++) {
        for(int j = 0; j < NUM_LEDS/2; j++) {
          ledState1[i][j] = 0;
          ledState2[i][j] = 0;
        }
      }
    clearingFlag = 0;
  }
  /* Expecting the Uno to send 4 bytes to the MAX32*/
  if(Serial1.available() > 3 && !clearingFlag) {
    byte1 = Serial1.read(); //Status byte
    byte2 = Serial1.read(); //X vel
    byte3 = Serial1.read(); //Y vel
    byte4 = Serial1.read(); //Extra byte, currently unused but could be used for checksum 
    
    receivedData = byte1 + (byte2 << 8) + (byte3 << 16) + (byte4 << 24);
    Serial1.write(receivedData);//Echo data back to Uno
    
    /* If clear button has been preseed, then flash the screen and clear the array*/
    if((byte1 & B00001000)) {
      for(int i = 0; i < M/2; i++) {
        for(int j = 0; j < NUM_LEDS/2; j++) {
          ledState1[i][j] = (unsigned int)(-1);
          ledState2[i][j] = (unsigned int)(-1);
        }
      }
      clearTime = millis();
      clearingFlag = 1;
    } else {
      /* Update LEDs under cursor to appropriate colors */
      
      
      /* INCOMPLETE SECTION */
      
    }
    
  }
  
  /* Display LED column in accordance to encoder position
     ASSUMES THAT M == PULSE_REV */
  if(curPos < M/2) {
    for(int i = 0; i < NUM_LEDS/2; i++) {
      /* state1 is the state for LED 2*i */
      state1 = ledState1[curPos][i];
      /* state2 is the state for LED 2*i + 1*/
      state2 = (state1 >> 4);
      /* Remember, you only care about the least 3 significant bits of the states*/
      
      /*---------------------------------------------------------
        this is the part where you turn on/off the right I/O pins 
        according to the LED states
        ---------------------------------------------------------*/
    }
  } else {
    newCol = curPos - M/2;
    for(int i = 0; i < NUM_LEDS/2; i++) {
      /* state1 is the state for LED 2*i */
      state1 = ledState2[newCol][i];
      /* state2 is the state for LED 2*i + 1*/
      state2 = (state1 >> 4);
      /* Remember, you only care about the least 3 significant bits of the states*/
      
      /*---------------------------------------------------------
        this is the part where you turn on/off the right I/O pins 
        according to the LED states
        ---------------------------------------------------------*/
    }
    
  }

  
}

void doEncoder() {
  encoderPos++;
  encoderPos %= PULSE_REV;
}

