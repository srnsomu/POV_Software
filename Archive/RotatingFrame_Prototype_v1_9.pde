/* Team XGearhead (still need a name) Rotating Frame MAX32 code. 
   Author: Alex Shie  Latest Revision: 4/16/13
   
   Initial state: the columns of LEDs alternate in color from red to green to 
   orange/yellow. 
   
   MAX32 code for the rotating frame. The setup function sets the used pins to outputs and 
   initializes the LED states to 0. 
   
   The main loop takes the clearing process as the highest priority. When the clear button is pressed
   the entire display will turn white for .5s (this can obviously be changed) and then revert to a
   clear state. While the display is white no drawing can occur. 
   
   Serial communications with the Uno aren't/can't be handled with interrupts, so the main loop
   checks for at least 4 bytes of data in its serial buffer from the Uno. After reading 4 bytes, 
   the program will look to see if the clearing button has been pressed. If it has been pressed, 
   then the state of the LEDs become all 1's -> white. If the clearing button hasn't been pressed,
   but at least one of the color buttons has been pressed, then the LED state is changed accordingly.
   Regardless of what buttons are pressed (if at all), the cursor's position is updated afterwards. 
   The cursor can wrap around the x-axis (horizontally), but not around the y-axis (vertically). 
   The cursor is a nxn (currently 3x3) block of pixels that periodically flashes white and then back
   to whatever colors are under the cursor. 
   
   Every iteration of the main loop ends with pushing the LED states to the pins so as to drive the 
   LEDs in accordance to the state corresponding to the current position/orientation of the rotating
   frame according to the encoder. The LEDs are multiplexed and there is currently a 10 microsecond 
   delay between switching groups of LEDs. Note: the I/O pin choices are unintuitive since the PORT
   registers lead to pins in the female headers that aren't at all contiguous or in any particular 
   order. 

    */

/* Things will be simpler if PULSE_REV == M */
#define PULSE_REV 120 //Pulses/ticks per revolution from the encoder
#define NUM_LEDS 120 //Number of LEDs on the rotating frame
#define M 45 //Number of columns in the perceived display, i.e. width of display (used to be 240, but reduced to 120 so it can compile with 120 LEDS)
#define DELAY 2//Delay in microseconds between switching on each MOSFET
#define HARD_DELAY 1
#define IDLE_THRESHOLD 600000

/* Use PORTD (full 16 bits) and PORTE (first 8 bits) for cathode (darlington array) 
         and use PORTF (B0011 0001 0011 1111) and PORTG (B1111 0011 1100 1111) for the 15 
         MOSFETs for the anodes. */
//PORTF - MOSFETS
#define RED1 0x0001
#define RED2 0x0002
//#define RED3 0x0004
#define RED4 0x0008
//#define RED5 0x0010
//#define GREEN1 0x0020
//#define GREEN2 0x0100
#define GREEN3 0x1000
#define GREEN4 0x2000

//PORTG - MOSFETS
#define GREEN5 0x0001
#define BLUE1 0x0002
#define BLUE2 0x8000
#define BLUE3 0x4000
#define BLUE4 0x0040
#define BLUE5 0x0080
//Also in PORTG to prevent UART conflicts
#define RED3 0x0100
#define RED5 0x0200
#define GREEN1 0x1000
#define GREEN2 0x2000

//Color masks to help read states
#define REDM B100
#define GREENM B010
#define BLUEM B1

#define CURSOR_DIM 3 //The length of the cursor block in pixels (e.g. 3x3)
#define CURSOR_DELAY 250 //How many ms before toggling the cursor after no input

#define RING_HEIGHT 16
#define RING_DELAY 100

int ledPins[] = {18,19,76,8,49,38,74,48,77,47,39,10,9,6,5,3,30,31,32,33,34,35,36,37};
int rfetPins[] = {45,46,43,25,53};
int gfetPins[] = {83,84,15,14,79};
int bfetPins[] = {78,28,82,52,29};

int encState = 0;
int prevEncState = 0;

int ringCount = 0;
int ringBot = 0;
int ringTop = RING_HEIGHT;
int ringDir = 1;
char color = 1;

int blockTime = 1000;
unsigned int lastChange;
int encBlock = 0;
unsigned int encoderPos = 0;
unsigned int prevEncoderPos = 0;
int curX = M/2; //Cursor coordinates - 0,0 is bottom left corner (or right)
int curY = NUM_LEDS-4;//NUM_LEDS/2; //Cursor will be 3x3 block...?

/* LED state will be represented by the 3 least significant bits, each bit representing
   red on, green on, blue on (blue on is LSB)*/

unsigned char ledState[M][NUM_LEDS];

unsigned long startTime;//Timestamp of the start of the 
unsigned long clearTime; //Timestamp of when the clear button was pressed
unsigned long lastActTime; //Timestamp of last user input: button press or trackball movement
char clearingFlag = 0; //1 means clearing mode is on (flashing and clearing the display)
unsigned long count = 0; //Number of times the main loop has run - used for mod purposes
char cursorFlag = 0; //Non-zero means that the cursor is "on" (i.e. the block is all white)

/* The cursor will periodically flash white and then revert to the colors that are supposed
   to be under the cursor. This array stores those colors/states. */
unsigned char cursorState[CURSOR_DIM][CURSOR_DIM];

void startupRoutine();
void printCursorState();
void printLEDState();

/* Overwrites LED states - ledNum needs to be from 0 to NUM_LEDS-1. This function exists only
   because it makes it easier to implement a wraparound for the x-axis. */
void ledWrite(int ledNum, int col, char state) {
  char shiftState = state;
  char newState = 0;
  int newCol = col; 
  
  //Wraparound if necessary 
  if(col < 0){
    newCol = col + M;
  } else if (col > M-1) {
    newCol = col - M;
  }
  
  //Don't need to check for y bounds (i.e. ledNum) since the cursor is always whole
  
  ledState[newCol][ledNum] = state;
  
}

/* Returns the state of a particular LED. This function exists only because it makes it easier
   to implement a wraparound for the x-axis.*/
char ledRead(int ledNum, int col) {
  int newCol = col; 
  //Wraparound if necessary
  if(col < 0){
    newCol = col + M;
  } else if (col > M-1) {
    newCol = col - M;
  }
  
  //Don't need to check for y bounds (i.e. ledNum) since the cursor is always whole
  
  return ledState[newCol][ledNum];
}


void setup()
{
  Serial.begin(115200);//For debugging with the serial terminal
  Serial2.begin(115200); //Pin 17 RX2, Pin 16 TX2
  //attachInterrupt(2, doEncoder, FALLING);  // encoder pin on interrupt 2 - pin 7
  
  /* Set LED pins to outputs*/
  //D and E are for darlington arrays
  TRISDCLR = 0xFFFF;
  TRISECLR = 0x2FF; //to test out pin 2
  //F and G are for MOSFETs
  TRISFCLR = 0x300B;//0x300B;
  TRISGCLR = 0xF3C3;
  pinMode(7, INPUT);
  
  //startupRoutine();
  
  
  
  /* Initializes led states so that the colors of each column alternate between green, red, and orange */
  for(int i = 0; i < M; i++) {
    for(int j = 0; j < NUM_LEDS; j++) {
      /*
      if(i%3 == 0) {
        ledState[i][j] = B00000100;
      } else if (i%3 == 1) {
        ledState[i][j] = B00000010;
      } else {
        ledState[i][j] = B00000001; 
      }*/
      
      //Red, green, blue, orange, teal, purple, white, repeat
      /*
      switch (i%7) {
        case 0:
          ledState[i][j] = B00000100;
          break;
        case 1:
          ledState[i][j] = B00000010;
          break;
        case 2:
          ledState[i][j] = B00000001;
          break;
        case 3:
          ledState[i][j] = B00000110;
          break;
        case 4:
          ledState[i][j] = B00000011;
          break;
        case 5:
          ledState[i][j] = B00000101;
          break;
        default:
          ledState[i][j] = B00000111;
          break;
      }*/
      /*
      if(i < 40) {
        ledState[i][j] = B00000100;  
      } else if (i < 80) {
        ledState[i][j] = B00000001; 
      } else {
        ledState[i][j] = B00000010;
      }*/
      /*
      if(i == 0) {
        ledState[i][j] = B00000001;
      } else if (i == M/2){
        ledState[i][j] = B00000100; 
      } else {
        ledState[i][j] = 0; 
      }*/
      
      if(i > 10 && i < 16 && j < NUM_LEDS-5 && j > NUM_LEDS-11) {
        ledState[i][j] = B00000010;
      } else {
        ledState[i][j] = 0;  
      }
      
      //ledState[i][j] = B00000111;
    }
  }
  for(int i = 0; i < CURSOR_DIM; i++) {
    for(int j = 0; j < CURSOR_DIM; j++) {
      cursorState[i][j] = ledRead(curY-1+i, curX-1+j);
    }
  }
  /*Time when the last clear command has been received*/
  clearTime = millis();
  lastActTime = millis();
  startTime = millis();
  lastChange = millis();
}


void loop()
{
  /* A non-volatile copy of encoderPos must be used so that the position value
     doesn't change halfway through the loop if there is an encoder tick during
     the loop. This will result in proper behavior if the loop can run entirely at 
     least once between each encoder tick.*/
  int curPos;// = encoderPos;
  unsigned int receivedData = 0;
  char statusByte;
  char xByte;
  char yByte;
  char extraByte;
  char state1;
  char state2;
  char state3;
  char state4;
  char state5;
  char state6;
  char state7;
  char state8;
  
  int newCol;
  
  char xVel;
  char yVel;
  
  unsigned long temp;
  int temp2;
  int temp3;
  double dtemp;
  
  
  //Serial.println(analogRead(A0));
  //if(digitalRead(7) == HIGH) {
  //if((PORTE & 0x200) != 0) {
  temp3 = analogRead(A0);
  if(temp3/100 > 7) {
    //Serial.println("HIGH");
    encState = 1;  
  } else if(temp3/100 < 6){
    //Serial.println("LOW");
    encState = 0; 
  }
  
  if(encState != prevEncState) {
    if(encState == 0 && prevEncState == 1) {
      temp = millis()-lastChange;
      blockTime = temp/M;
      if(blockTime == 0)
        blockTime = 1;
      lastChange = millis();
      //encoderPos++;
      //encoderPos %= PULSE_REV;
      Serial.println("MARK");
    }
    prevEncState = encState;
    
    
    //Serial.print("LATE: ");
    //Serial.println(LATE, BIN);
    //Serial.print("PORTE: ");
    //Serial.println(PORTE & 0x200, BIN);
    //Serial.println(encState);
  }
  Serial.print("");
  temp2 = millis()-lastChange;
  encoderPos = temp2/blockTime;
  encoderPos %= M;
  
  
  
  /*
  if(millis() - lastChange > HARD_DELAY) {
   
    encoderPos++;
    encoderPos %= PULSE_REV;
   lastChange = millis(); 
  }*/
  
  if((millis() - startTime)%1000 == 0) {
    Serial.print("Ms since start: ");
    Serial.print(millis()-startTime);
    Serial.print("\tTotal number of loop iterations: ");
    /*
    Serial.println(count);
    Serial.print("X: ");
    Serial.println(curX);
    Serial.print("Y: ");
    Serial.println(curY);*/
    printLEDState();

  }
  
  //Encoder testing stuff - talk to UNO
  if(encoderPos != prevEncoderPos) {
    //Serial.println("WRITE");
    //Serial2.write(encoderPos);
    prevEncoderPos = encoderPos; 
  }
  curPos = encoderPos;
  
  /* These variables will contain the bits to be pushed to the PORT registers connected to the
     darlington arrays. The least significant 8 bits will be to PORTE, the middle 16 bits will 
     be to PORTD, and the most significant 8 bits will be empty.*/
  unsigned int red[5] = {0,0,0,0,0};
  unsigned int green[5] = {0,0,0,0,0};
  unsigned int blue[5] = {0,0,0,0,0};
  
  
  /* After "flashing" the screen for 500ms, clear all pixels*/
  if(clearingFlag == 1 && millis()-clearTime > 500) {
    for(int i = 0; i < M; i++) {
        for(int j = 0; j < NUM_LEDS; j++) {
          ledState[i][j] = 0;
        }
      }
    clearingFlag = 0;
  }
  

  /* Expecting the Uno to send 4 bytes to the MAX32*/
  if(Serial2.available() > 3) {
    
    while((statusByte = Serial2.read()) != 0x30) {}//Find message start byte
    statusByte = Serial2.read();//Status byte
    xByte = Serial2.read(); //X vel
    yByte = Serial2.read(); //Y vel
    /*The two if statements below may not be necessary - it depends on how the MAX32
      interprets the bits. Uncomment if you can only move in positive x/y directions*/
     /*
    if(xByte > 127) {
      xByte -= 256;
    }
    if(yByte > 127) {
      yByte -= 256; 
    }*/
    /*
    Serial.print(statusByte, BIN);
  Serial.print("\tX=");
  Serial.print(xByte, DEC);
  Serial.print("\tY=");
  Serial.println(yByte, DEC);*/
    
    extraByte = 0x30;
    //Uncomment the lines below if you want to send data back to the Uno
    /*Serial2.write(extraByte);
      Serial2.write(statusByte);
      Serial2.write(xByte);
      Serial2.write(yByte);*/
    
    
    //Reset cursor action if any movment/button presses occur
      if (xByte != 0 || yByte != 0 || statusByte&0xF != 0) {
        lastActTime = millis();
        ringCount = 0;
        ringBot = 0;
        ringTop = RING_HEIGHT;
        ringDir = 1;
        color = 1;
        cursorFlag = 0;
        
        //Display the colors under the cursor
        for(int i = 0; i < CURSOR_DIM; i++) {
          for(int j = 0; j < CURSOR_DIM; j++) {
            ledWrite(curY-1+i, curX-1+j, cursorState[i][j]);
          }
        }
      }
    
    /* If clear button has been preseed, then flash the screen and clear the array*/
    if((statusByte & B00001000) != 0) {
      //Serial.println("-------CLEAR");
      for(int i = 0; i < M; i++) {
        for(int j = 0; j < NUM_LEDS; j++) {
          ledState[i][j] = 0x07;
        }
      }
      clearTime = millis();
      clearingFlag = 1;
      
      //Reset cursor position
      curX = M/2;
      curY = NUM_LEDS-4;

    } else {
      /* Update LEDs under cursor to appropriate colors */
      temp2 = statusByte;
      statusByte = (statusByte & B00000111);
      
      //Only overwrite the state if the user pressed a color button
      if (statusByte != 0 && clearingFlag == 0) {
        //For 3x3 cursor - need to hardcode any changes to cursor size here
        /*
        Serial.print("PAINT: ");
        Serial.print(statusByte, BIN);
        Serial.print("     RAW: ");
        Serial.println(temp2, BIN);*/
        ledWrite(curY-1, curX-1, statusByte);
        ledWrite(curY-1, curX, statusByte);
        ledWrite(curY-1, curX+1, statusByte);
        ledWrite(curY, curX-1, statusByte);
        ledWrite(curY, curX, statusByte);
        ledWrite(curY, curX+1, statusByte);
        ledWrite(curY+1, curX-1, statusByte);
        ledWrite(curY+1, curX, statusByte);
        ledWrite(curY+1, curX+1, statusByte);
 
      } 
      
      
      /* Adjust the velocities to displacements - a max displacement of the length of the
         cursor is needed to prevent skipping rows/columns when trying to draw a line quickly.
         Not sure if any of this is really necessary. We'll see.  */
      if(abs(xByte) > 60) {
        xVel = 3;//3; 
      } else if (abs(xByte) > 30) {
        xVel = 2;//2;
      } else if (abs(xByte) > 0){
        xVel = 1;
      } else {
        xVel = 0;  
      }
      
      if(xByte < 0) {
        xVel = -xVel;
      }
      
      if(abs(yByte) > 60) {
        yVel = 3;//3; 
      } else if (abs(yByte) > 30) {
        yVel = 2;//2;
      } else if (abs(yByte) > 0) {
        yVel = 1;
      } else {
        yVel = 0;  
      }
      
      if(yByte < 0) {
        yVel = -yVel;
      }
      
       /* Move cursor position */
      curX += xVel;
      curY += yVel;
      
      if(curX < 0){
        curX += M; //Support wraparound the x-axis since it's a cylinder
      } else if (curX > M-1) {
        curX -= M;
      }
      
      
      //CURSOR_DIM/2 is used to make sure the whole cursor is within bounds - not just the center
      if(curY < CURSOR_DIM/2+32) {
        curY = CURSOR_DIM/2+32; //No wraparound the y-axis
      } else if (curY > NUM_LEDS - CURSOR_DIM/2 - 1) {
        curY = NUM_LEDS - CURSOR_DIM/2 - 1;
      }

      if(cursorFlag == 0) {
        //Store the colors under the cursor so they aren't lost when the cursor flashes
        for(int i = 0; i < CURSOR_DIM; i++) {
          for(int j = 0; j < CURSOR_DIM; j++) {
            cursorState[i][j] = ledRead(curY-1+i, curX-1+j);
          }
        }
      }
    }
  }

  //Handle cursor flashing
  if((millis() - lastActTime) % CURSOR_DELAY == 0 ) {
    //Serial.println("Toggle cursor");
    cursorFlag = ~cursorFlag; //Toggles cursor on/off
    //lastActTime = millis();
  }

  
  if(clearingFlag == 0 && (millis()-lastActTime) < IDLE_THRESHOLD) {
    if(cursorFlag == 0) {
      //Display the colors under the cursor
      for(int i = 0; i < CURSOR_DIM; i++) {
        for(int j = 0; j < CURSOR_DIM; j++) {
          ledWrite(curY-1+i, curX-1+j, cursorState[i][j]);
        }
      }
    } else {
      //Display the cursor as a white block
      for(int i = 0; i < CURSOR_DIM; i++) {
        for(int j = 0; j < CURSOR_DIM; j++) {
          ledWrite(curY-1+i, curX-1+j, B00000111);
        }
      }
    }
  }
  
  //Start the idle sequence
  if((millis()-lastActTime) >= IDLE_THRESHOLD) {
    temp = millis()-lastActTime;
    if(temp % RING_DELAY == 0) {
      if(ringDir == 0) {
        if(ringBot == 32) {
          for(int m = 0; m < M; m++) {
            ledWrite(ringBot,m,0); 
          }
          ringDir = 1;
          ringBot++;
          ringTop++;
          color++;
        } else {
          for(int m = 0; m < M; m++) {
            ledWrite(ringTop-1,m,0); 
          }
          ringBot--;
          ringTop--;
        }  
      } else {
        if(ringTop == NUM_LEDS) {
          for(int m = 0; m < M; m++) {
            ledWrite(ringTop-1,m,0); 
          }
          ringDir = 0;
          ringBot--;
          ringTop--;
          color++;  
        } else {
          for(int m = 0; m < M; m++) {
            ledWrite(ringBot,m,0); 
          }
          ringBot++;
          ringTop++;
        }  
        
      }
    }
    if(color == 0)
      color = 1;
    
    for(int m = 0; m < M; m++) {
      for(int i = ringBot; i < ringTop; i++) {
        ledWrite(i, m, color);
      
      }  
    }
    
    
  }

  
  /* Display LED column in accordance to encoder position
     ASSUMES THAT M == PULSE_REV */
  
  
  /*In the first group of 24 leds (0-23), note that LED #0 is in the MSB of PORTD and LED#15 is 
    in the 8th LSB of PORTE (i.e. bit #7). Wiring just got more complicated. */
  newCol = curPos;
  for(int j = 1; j < 5; j++) {
    digitalWrite(rfetPins[j], LOW);
    for(int i = j*24; i < (j+1)*24; i++) {
      digitalWrite(ledPins[i%24], ledState[newCol][i]&REDM);
    }
    delayMicroseconds(DELAY);
    digitalWrite(rfetPins[j], HIGH);
  }
  
  for(int j = 1; j < 5; j++) {
    digitalWrite(gfetPins[j], LOW);
    for(int i = j*24; i < (j+1)*24; i++) {
      digitalWrite(ledPins[i%24], ledState[newCol][i]&GREENM);
    }
    delayMicroseconds(DELAY);
    digitalWrite(gfetPins[j], HIGH);
  }
  
  for(int j = 1; j < 5; j++) {
    digitalWrite(bfetPins[j], LOW);
    for(int i = j*24; i < (j+1)*24; i++) {
      digitalWrite(ledPins[i%24], ledState[newCol][i]&BLUEM);
    }
    delayMicroseconds(DELAY);
    digitalWrite(bfetPins[j], HIGH);
  }
  
  count++;
  
  
}

void startupRoutine() {
  
  for(int i = 0; i < 24; i++) {
    digitalWrite(ledPins[i], LOW);
  }
  
  for(int i = 2; i < 5; i++) {
    digitalWrite(rfetPins[i], HIGH);
    digitalWrite(gfetPins[i], HIGH);  
    digitalWrite(bfetPins[i], HIGH);
  }
  
  for(int j = 2; j < 5; j++) {
    digitalWrite(rfetPins[j], LOW);
    for(int i = 0; i < 24; i++) {
      digitalWrite(ledPins[i], HIGH);
      delay(900);
      digitalWrite(ledPins[i], LOW);  
    }
    digitalWrite(rfetPins[j], HIGH);
  }
  
  for(int j = 2; j < 5; j++) {
    digitalWrite(gfetPins[j], LOW);
    for(int i = 0; i < 24; i++) {
      digitalWrite(ledPins[i], HIGH);
      delay(900);
      digitalWrite(ledPins[i], LOW);  
    }
    digitalWrite(gfetPins[j], HIGH);
  }
  
  for(int j = 2; j < 5; j++) {
    digitalWrite(bfetPins[j], LOW);
    for(int i = 0; i < 24; i++) {
      digitalWrite(ledPins[i], HIGH);
      delay(900);
      digitalWrite(ledPins[i], LOW);  
    }
    digitalWrite(bfetPins[j], HIGH);
  }
   
}

void printCursorState() {
   for(int i = 0; i < CURSOR_DIM; i++) {
     for(int j = 0; j < CURSOR_DIM; j++) {
         Serial.print(cursorState[i][j], BIN);
         Serial.print("\t");
     }
     Serial.println("");
   }
}

void printLEDState() {
   for(int i = NUM_LEDS-1; i > NUM_LEDS-100; i--) {
     for(int j = 0; j < M; j++) {
         Serial.print(ledState[j][i], BIN);
         Serial.print("\t");
     }
     Serial.println("");
   }
}
  
  
