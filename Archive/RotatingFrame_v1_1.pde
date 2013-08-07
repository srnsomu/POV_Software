/* Team XGearhead (still need a name) Rotating Frame MAX32 code. 
   Author: Alex Shie  Latest Revision: 4/4/13
   
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
#define PULSE_REV 240 //Pulses/ticks per revolution from the encoder
#define NUM_LEDS 120 //Number of LEDs on the rotating frame
#define M 120 //Number of columns in the perceived display, i.e. width of display (used to be 240, but reduced to 120 so it can compile with 120 LEDS)
#define DELAY 10//Delay in microseconds between switching on each MOSFET

/* Use PORTD (full 16 bits) and PORTE (first 8 bits) for cathode (darlington array) 
         and use PORTF (B0011 0001 0011 1111) and PORTG (B1111 0011 1100 1111) for the 15 
         MOSFETs for the anodes. */
//PORTF - MOSFETS
#define RED1 0x0001
#define RED2 0x0002
#define RED3 0x0004
#define RED4 0x0008
#define RED5 0x0010
#define GREEN1 0x0020
#define GREEN2 0x0100
#define GREEN3 0x1000
#define GREEN4 0x2000

//PORTG - MOSFETS
#define GREEN5 0x0001
#define BLUE1 0x0002
#define BLUE2 0x0004
#define BLUE3 0x0008
#define BLUE4 0x0040
#define BLUE5 0x0080

//Color masks to help read states
#define REDM B100
#define GREENM B010
#define BLUEM B1

#define CURSOR_DIM 3 //The length of the cursor block in pixels (e.g. 3x3)
#define CURSOR_DELAY 1000 //How many iterations the main loop goes through before toggling the cursor

int encoderPos = 0;
unsigned int curX = M/2; //Cursor coordinates - 0,0 is bottom left corner (or right)
unsigned int curY = NUM_LEDS/2; //Cursor will be 3x3 block...?

/* LED state will be represented by the 3 least significant bits, each bit representing
   red on, green on, blue on (blue on is LSB)*/
unsigned char ledState1[M/2][NUM_LEDS/2]; //Contains on/off info for each LED
unsigned char ledState2[M/2][NUM_LEDS/2]; //Contains on/off info for each LED

unsigned long clearTime; //Timestamp of when the clear button was pressed
char clearingFlag = 0; //1 means clearing mode is on (flashing and clearing the display)
unsigned long count = 0; //Number of times the main loop has run - used for mod purposes
char cursorFlag = 0; //Non-zero means that the cursor is "on" (i.e. the block is all white)

/* The cursor will periodically flash white and then revert to the colors that are supposed
   to be under the cursor. This array stores those colors/states. */
unsigned char cursorState[CURSOR_DIM][CURSOR_DIM];

/* Overwrites LED states - ledNum needs to be from 0 to NUM_LEDS-1*/
void ledWrite(int ledNum, int col, char state) {
  char shiftState = state;
  char newState = 0;
  int newCol; 
  
  if(col < 0){
    newCol = col + M;
  } else if (col > M-1) {
    newCol = col - M;
  }
  
  //Don't need to check for y bounds (i.e. ledNum) since the cursor is always whole
  
  if(newCol < M/2) {
    if(ledNum % 2 == 0) {
      newState = (ledState1[newCol][ledNum/2] & B11110000)+shiftState;
    } else {
      newState = (ledState1[newCol][ledNum/2] & B00001111)+(shiftState<<4);
    }
    ledState1[newCol][ledNum/2] = newState;  
  } else {
    newCol = newCol - M/2;
    if(ledNum % 2 == 0) {
      newState = (ledState2[newCol][ledNum/2] & B11110000)+shiftState;
    } else {
      newState = (ledState2[newCol][ledNum/2] & B00001111)+(shiftState<<4);
    }
    ledState2[newCol][ledNum/2] = newState; 
  }
}

char ledRead(int ledNum, int col) {
  char state = 0;
  int newCol; 
  
  if(col < 0){
    newCol = col + M;
  } else if (col > M-1) {
    newCol = col - M;
  }
  
  //Don't need to check for y bounds (i.e. ledNum) since the cursor is always whole
  
  if(newCol < M/2) {
    if(ledNum % 2 == 0) {
      state = (ledState1[newCol][ledNum/2] & B00001111);
    } else {
      state = (ledState1[newCol][ledNum/2] & B11110000);
    } 
  } else {
    newCol = newCol - M/2;
    if(ledNum % 2 == 0) {
      state = (ledState2[newCol][ledNum/2] & B00001111);
    } else {
      state = (ledState2[newCol][ledNum/2] & B11110000);
    } 
  }
  return state;
}


void setup()
{
  
  Serial1.begin(9600); //Pin 19 RX1, Pin 18 TX1
  attachInterrupt(0, doEncoder, CHANGE);  // encoder pin on interrupt 0 - pin 3
  
  /* Set LED pins to outputs*/
  //D and E are for darlington arrays
  TRISDCLR = 0xFFFF;
  TRISECLR = 0xFF;
  //F and G are for MOSFETs
  TRISFCLR = 0x313F;
  TRISGCLR = 0xCF;
  
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
  
  char xVel;
  char yVel;
  
  /* These variables will contain the bits to be pushed to the PORT registers connected to the
     darlington arrays. The least significant 8 bits will be to PORTE, the middle 16 bits will 
     be to PORTD, and the most significant 8 bits will be empty.*/
  unsigned int red[5] = {0,0,0,0,0};
  unsigned int green[5] = {0,0,0,0,0};
  unsigned int blue[5] = {0,0,0,0,0};
  
  
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
  if(Serial1.available() > 3) {
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
      
      byte1 = byte1 & B00000111;
      
      //Only overwrite the state if the user pressed a color button
      if (byte1 > 0 && !clearingFlag) {
        //For 3x3 cursor - need to hardcode any changes to cursor size here
        ledWrite(curY-1, curX-1, byte1);
        ledWrite(curY-1, curX, byte1);
        ledWrite(curY-1, curX+1, byte1);
        ledWrite(curY, curX-1, byte1);
        ledWrite(curY, curX, byte1);
        ledWrite(curY, curX+1, byte1);
        ledWrite(curY+1, curX-1, byte1);
        ledWrite(curY+1, curX, byte1);
        ledWrite(curY+1, curX+1, byte1);
      }
      
      /* Adjust the velocities to displacements - a max displacement of the length of the
         cursor is needed to prevent skipping rows/columns when trying to draw a line quickly */
      if(abs(byte2) > 60) {
        xVel = 3; 
      } else if (abs(byte2) > 30) {
        xVel = 2;
      } else {
        xVel = 1;
      }
      
      if(byte2 < 0) {
        xVel = -xVel;
      }
      
      if(abs(byte3) > 60) {
        yVel = 3; 
      } else if (abs(byte3) > 30) {
        yVel = 2;
      } else {
        yVel = 1;
      }
      
      if(byte3 < 0) {
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
      if(curY < CURSOR_DIM/2) {
        curY = CURSOR_DIM/2; //No wraparound the y-axis
      } else if (curY > NUM_LEDS - CURSOR_DIM/2 - 1) {
        curY = NUM_LEDS - CURSOR_DIM/2 - 1;
      }
    }
    
    //Store the colors under the cursor so they aren't lost when the cursor flashes
    for(int i = 0; i < CURSOR_DIM; i++) {
      for(int j = 0; j < CURSOR_DIM; j++) {
        cursorState[i][j] = ledRead(curY-1+i, curX-1+j);
      }
    }
    
  }
  //Handle cursor flashing
  if(count % CURSOR_DELAY == 0) {
    cursorFlag = ~cursorFlag; //Toggles cursor on/off
  }
  
  if(!clearingFlag) {
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
  
  /* Display LED column in accordance to encoder position
     ASSUMES THAT M == PULSE_REV */
  
  /* Use PORTD (full 16 bits) and PORTE (first 8 bits) for cathode (darlington array) 
         and use PORTF (B0011 0001 0011 1111) and PORTG (B1111 0011 1100 1111) for the 15 
         MOSFETs for the anodes. The bits that are 0's represent pins in the ports that aren't
         actually connected to the female headers on the board (i.e. they can't be used). */
  
  /*In the first group of 24 leds (0-23), note that LED #0 is in the MSB of PORTD and LED#15 is 
    in the 8th LSB of PORTE (i.e. bit #7). Wiring just got more complicated. */
  if(curPos < M/2) {
    newCol = curPos;
    for(int m = 0; m < 5; m++) {
      for(int i = m*12; i < (m+1)*12; i++) {
        state1 = ledState1[newCol][i];
        state2 = (state1 >> 4);
        
        red[m] = (red[m] << 2) + ((state1&REDM)>>1) + ((state2&REDM)>>2);
        green[m] = (green[m] << 2) + (state1&GREENM) + ((state2&GREENM)>>1);
        blue[m] = (blue[m] << 2) + ((state1&BLUEM)<<1) + (state2&BLUEM);
      }
    }
  } else {
    newCol = curPos-M/2;
    for(int m = 0; m < 5; m++) {
      for(int i = m*12; i < (m+1)*12; i++) {
        state1 = ledState2[newCol][i];
        state2 = (state1 >> 4);
        
        red[m] = (red[m] << 2) + ((state1&REDM)>>1) + ((state2&REDM)>>2);
        green[m] = (green[m] << 2) + (state1&GREENM) + ((state2&GREENM)>>1);
        blue[m] = (blue[m] << 2) + ((state1&BLUEM)<<1) + (state2&BLUEM);
      }
    }
  }
  
  /* Remember: all red and green MOSFETs (except green5) use PORTF, the rest use PORTG */
  
  //Turn on the first red MOSFET
  PORTF = RED1;
  //Activate the darlington arrays corresponding to the first group of 24 red LEDs
  PORTD = red[1]>>8;
  PORTE = (red[1] & 0xFF);
  delayMicroseconds(DELAY);
  //Turn off the first red MOSFET
  LATFCLR = RED1;
  
  //Turn on the first blue MOSFET, etc.
  PORTG = BLUE1;
  PORTD = blue[1]>>8;
  PORTE = (blue[1] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = BLUE1;
  
  PORTF = GREEN1;
  PORTD = green[1]>>8;
  PORTE = (green[1] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = GREEN1;
  
  //Group 2
  PORTF = RED2;
  PORTD = red[2]>>8;
  PORTE = (red[2] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = RED2;
  
  PORTG = BLUE2;
  PORTD = blue[2]>>8;
  PORTE = (blue[2] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = BLUE2;
  
  PORTF = GREEN2;
  PORTD = green[2]>>8;
  PORTE = (green[2] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = GREEN2;
  
  //Group 3
  PORTF = RED3;
  PORTD = red[3]>>8;
  PORTE = (red[3] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = RED3;
  
  PORTG = BLUE3;
  PORTD = blue[3]>>8;
  PORTE = (blue[3] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = BLUE3;
  
  PORTF = GREEN3;
  PORTD = green[3]>>8;
  PORTE = (green[3] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = GREEN3;
  
  //Group 4
  PORTF = RED4;
  PORTD = red[4]>>8;
  PORTE = (red[4] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = RED4;
  
  PORTG = BLUE4;
  PORTD = blue[4]>>8;
  PORTE = (blue[4] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = BLUE4;
  
  PORTF = GREEN4;
  PORTD = green[4]>>8;
  PORTE = (green[4] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = GREEN4;
  
  //Group 5
  PORTF = RED5;
  PORTD = red[5]>>8;
  PORTE = (red[5] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = RED5;
  
  PORTG = BLUE5;
  PORTD = blue[5]>>8;
  PORTE = (blue[5] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = BLUE5;
  
  PORTG = GREEN5; //Green5 goes to PORTG instead of PORTF
  PORTD = green[5]>>8;
  PORTE = (green[5] & 0xFF);
  delayMicroseconds(DELAY);
  LATFCLR = GREEN5;
  
  count++;
}

void doEncoder() {
  encoderPos++;
  encoderPos %= PULSE_REV;
}

