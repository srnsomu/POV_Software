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
   
    */

/* Things will be simpler if PULSE_REV == M */
#define PULSE_REV 120 //Pulses/ticks per revolution from the encoder
#define NUM_LEDS 120 //Number of LEDs on the rotating frame
#define M 90 //Number of columns in the perceived display, i.e. width of display (used to be 240, but reduced to 120 so it can compile with 120 LEDS)
#define DELAY 2//Delay in microseconds between switching on each MOSFET
#define HARD_DELAY 1
#define IDLE_THRESHOLD 180000



//Color masks to help read states
#define REDM B100
#define GREENM B010
#define BLUEM B1

#define CURSOR_DIM 3 //The length of the cursor block in pixels (e.g. 3x3)
#define CURSOR_DELAY 250 //How many ms before toggling the cursor after no input

#define RING_HEIGHT 16
#define RING_DELAY 100
#define SPACING M/6

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
char lastColor = B00000111;
int shiftDelay = 1000;
int shiftDir = 0;


int blastHeight = 4;
int prevBlastHeight = 4;
int sliderDir = 0;
int prevSliderDir = 0;

int blockTime = 1000;
unsigned int lastChange;
int encBlock = 0;
unsigned int encoderPos = 0;
unsigned int prevEncoderPos = 0;
int curX = 0; //Cursor coordinates - 0,0 is bottom left corner (or right)
int curY = NUM_LEDS/2;//NUM_LEDS/2; //Cursor will be 3x3 block...?

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

char extraByte;

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
  char statusByte;
  char tempByte;
  Serial.begin(115200);//For debugging with the serial terminal
  Serial2.begin(115200); //Pin 17 RX2, Pin 16 TX2
  

  for(int i = 0; i < 24; i++) {
    pinMode(ledPins[i], OUTPUT);  
  }
  for(int i = 0; i < 5; i++) {
    pinMode(rfetPins[i], OUTPUT); 
    pinMode(gfetPins[i], OUTPUT);
    pinMode(bfetPins[i], OUTPUT);
  }
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
      if(i < M/4) {
        ledState[i][j] = B00000100; 
      } else if (i < M/2) {
        ledState[i][j] = B00000010; 
      } else if (i < (3*M)/4) {
        ledState[i][j] = B00000110; 
      } else {
        ledState[i][j] = B00000001; 
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

  int curPos;
  unsigned int receivedData = 0;
  char statusByte;
  byte xByte;
  char yByte;
  
  char state1;
  char tempStates[M];
  
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

  }
  Serial.print("");
  temp2 = millis()-lastChange;
  encoderPos = temp2/blockTime;
  encoderPos %= M;
  
  
  
  if((millis() - startTime)%1000 == 0) {
    Serial.print("Ms since start: ");
    Serial.print(millis()-startTime);
    Serial.print("\tTotal number of loop iterations: ");
    Serial.println(count);
    //printLEDState();

  }
  
  //Encoder testing stuff - talk to UNO
  if(encoderPos != prevEncoderPos) {
    prevEncoderPos = encoderPos; 
  }
  curPos = encoderPos;
  
 
  
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

    blastHeight = map(xByte, 0, 255, 8, 32);
    //Serial.println(prevSliderDir);
     prevSliderDir = sliderDir;
        if(prevBlastHeight - blastHeight > 0) {
          prevBlastHeight = blastHeight;
        curX = blastHeight;
          sliderDir = -1;  
        } else if(prevBlastHeight - blastHeight < 0){
          prevBlastHeight = blastHeight;
        curX = blastHeight;
          sliderDir = 1;
        } else {
         sliderDir = 0; 
        }
     //   Serial.println(sliderDir);
    if(sliderDir != prevSliderDir && sliderDir != 0) {
      Serial.println("CHANGE");
      extraByte++;
    }
    for(int i = 0; i < M; i++) {
      ledState[i][76+prevBlastHeight] = 0;
      ledState[i][76-prevBlastHeight] = 0;
    }
    prevBlastHeight = blastHeight;
        
    


    
    
    //Reset cursor action if any movment/button presses occur
      if (statusByte&0xF != 0) {
        lastActTime = millis();
        ringCount = 0;
        ringBot = 0;
        ringTop = RING_HEIGHT;
        ringDir = 1;
        color = 1;
        cursorFlag = 0;
       
      }
    
    /* If clear button has been preseed, then flash the screen and clear the array*/
    if((statusByte & B00001000) != 0) {
      //Serial.println("-------CLEAR");
      lastColor = statusByte & B00000111;
      if(lastColor == 0)
        lastColor = B00000111;
      for(int i = 0; i < M; i++) {
        for(int j = 0; j < NUM_LEDS; j++) {
          ledState[i][j] = lastColor;
        }
      }
      //lastColor = B00000111;
      clearTime = millis();
      clearingFlag = 1;
      


    } else {
      /* Update LEDs under cursor to appropriate colors */

      statusByte = (statusByte & B00000111);
      
      //Only overwrite the state if the user pressed a color button
      if (statusByte != 0 && clearingFlag == 0) {
        //For 3x3 cursor - need to hardcode any changes to cursor size here
        lastColor = statusByte;
        extraByte = (~lastColor)&B00000111;
        
        
       
        
        curX = blastHeight;
        
        // + random(0,4);
        
        for(int i = 0; i < M; i++) {
            for(int j = 76-blastHeight; j < 76+blastHeight+1; j++) {
              ledWrite(j, i, statusByte);
            }

        }
      }  
    }
  }

  if(count % 100 == 0) {
    for(int i = 0; i < M; i++) {
      ledState[i][76+curX] = B00000000;
      ledState[i][76-curX] = B00000000; 
    }
    
    
    //Serial.println(curX);
    curX--;
    if(curX < 0)
      curX = 0;   
  }
  for(int i = 0; i < M; i++) {
    
    if(extraByte == 0)
      extraByte = B00000111;
    ledState[i][76+prevBlastHeight] = 0;
    ledState[i][76-prevBlastHeight] = 0;
    ledState[i][76+blastHeight] = extraByte;
    ledState[i][76-blastHeight] = extraByte;
    
    
    ledState[i][76+blastHeight+1] = 0;
    ledState[i][76-blastHeight-1] = 0;
    ledState[i][76+blastHeight-1] = 0;
    ledState[i][76-blastHeight+1] = 0;
    
    ledState[i][76+blastHeight+2] = 0;
    ledState[i][76-blastHeight-2] = 0;
    ledState[i][76+blastHeight-2] = 0;
    ledState[i][76-blastHeight+2] = 0;
    
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
    if(color == 0 || color == 8)
      color = 1;
    
    for(int m = 0; m < M; m++) {
      for(int i = ringBot; i < ringTop; i++) {
        ledWrite(i, m, color);
      
      }  
    } 
  }

  newCol = curPos;
  for(int j = 1; j < 5; j++) {
    digitalWrite(rfetPins[j], LOW);
    for(int i = j*24; i < (j+1)*24; i++) {
      digitalWrite(ledPins[i%24], (ledState[newCol][i])&REDM);
    }
    delayMicroseconds(DELAY);
    
    digitalWrite(rfetPins[j], HIGH);
  }
  
  for(int j = 1; j < 5; j++) {
    digitalWrite(gfetPins[j], LOW);
    for(int i = j*24; i < (j+1)*24; i++) {
      digitalWrite(ledPins[i%24], (ledState[newCol][i])&GREENM);
    }
    delayMicroseconds(DELAY);
    
    digitalWrite(gfetPins[j], HIGH);
  }
  
  for(int j = 1; j < 5; j++) {
    digitalWrite(bfetPins[j], LOW);
    for(int i = j*24; i < (j+1)*24; i++) {
      digitalWrite(ledPins[i%24], (ledState[newCol][i])&BLUEM);
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
  
  for(int j = 1; j < 5; j++) {
    digitalWrite(rfetPins[j], LOW);
    for(int i = 0; i < 24; i++) {
      digitalWrite(ledPins[i], HIGH);
      delay(450);
      digitalWrite(ledPins[i], LOW);  
    }
    digitalWrite(rfetPins[j], HIGH);
  }
  
  for(int j = 1; j < 5; j++) {
    digitalWrite(gfetPins[j], LOW);
    for(int i = 0; i < 24; i++) {
      digitalWrite(ledPins[i], HIGH);
      delay(450);
      digitalWrite(ledPins[i], LOW);  
    }
    digitalWrite(gfetPins[j], HIGH);
  }
  
  for(int j = 1; j < 5; j++) {
    digitalWrite(bfetPins[j], LOW);
    for(int i = 0; i < 24; i++) {
      digitalWrite(ledPins[i], HIGH);
      delay(450);
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
  
  
