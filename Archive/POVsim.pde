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
    
import processing.serial.*;

/* Things will be simpler if PULSE_REV == M */
  int PULSE_REV = 360; //Pulses/ticks per revolution from the encoder
  int NUM_LEDS =120; //Number of LEDs on the rotating frame
  int M =360; //Number of columns in the perceived display, i.e. width of display (used to be 240, but reduced to 120 so it can compile with 120 LEDS)
  int DELAY =0;//Delay in microseconds between switching on each MOSFET

/* Use PORTD (full 16 bits) and PORTE (first 8 bits) for cathode (darlington array) 
         and use PORTF (B0011 0001 0011 1111) and PORTG (B1111 0011 1100 1111) for the 15 
         MOSFETs for the anodes. */
//PORTF - MOSFETS
  int RED1 = 0x0001;
  int RED2 =0x0002;
  int RED3 =0x0004;
  int RED4 =0x0008;
  int RED5 =0x0010;
  int GREEN1 =0x0020;
  int GREEN2 =0x0100;
  int GREEN3 =0x1000;
  int GREEN4 =0x2000;

//PORTG - MOSFETS
  int GREEN5 =0x0001;
  int BLUE1 =0x0002;
  int BLUE2 =0x0004;
  int BLUE3 =0x0008;
  int BLUE4 =0x0040;
  int BLUE5 =0x0080;

//Color masks to help read states
  int REDM =4;
  int GREENM =2;
  int BLUEM =1;

  int CURSOR_DIM =3; //The length of the cursor block in pixels (e.g. 3x3)
  int CURSOR_DELAY =1000; //How many iterations the main loop goes through before toggling the cursor

int encoderPos = 0;
  int curX = M/2; //Cursor coordinates - 0,0 is bottom left corner (or right)
  int curY = NUM_LEDS/2; //Cursor will be 3x3 block...?

/* LED state will be represented by the 3 least significant bits, each bit representing
   red on, green on, blue on (blue on is LSB)*/

  int[][] ledState = new int[360][120];

  long startTime;//Timestamp of the start of the program
  long clearTime; //Timestamp of when the clear button was pressed
  long lastActTime; //Timestamp of last user input: button press or trackball movement
 int clearingFlag = 0; //1 means clearing mode is on (flashing and clearing the display)
  long count = 0; //Number of times the main loop has run - used for mod purposes
 int cursorFlag = 0; //Non-zero means that the cursor is "on" (i.e. the block is all white)

/* The cursor will periodically flash white and then revert to the colors that are supposed
   to be under the cursor. This array stores those colors/states. */
  int[][] cursorState = new int[3][3];

Serial myPort;

/* Overwrites LED states - ledNum needs to be from 0 to NUM_LEDS-1. This function exists only
   because it makes it easier to implement a wraparound for the x-axis. */
void ledWrite(int ledNum, int col, int state) {
  int shiftState = state;
   int newState = 0;
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
int ledRead(int ledNum, int col) {
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
  myPort = new Serial(this, "/dev/ttyACM0", 9600);//Change to arduino USB
  size(1500, 500);
  background(0);
  noStroke();

  /* Initializes led states to all off */
  for(int i = 0; i < M; i++) {
    for(int j = 0; j < NUM_LEDS; j++) {
      //ledState[i][j] = 0;
    }
  }
  
  for(int i = 0; i < M; i++) {
    for(int j = 0; j < NUM_LEDS; j++) {
      if(i%3 == 0) {
        ledState[i][j] = 4;
      } else if (i%3 == 1) {
        ledState[i][j] = 2;
      } else {
        ledState[i][j] = 6; 
      }
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
}


void draw()
{
  /* A non-volatile copy of encoderPos must be used so that the position value
     doesn't change halfway through the loop if there is an encoder tick during
     the loop. This will result in proper behavior if the loop can run entirely at 
     least once between each encoder tick.*/
  int curPos = encoderPos;
    int receivedData = 0;
  int statusByte;
  int xByte;
  int yByte;
  int extraByte;
   int state1;
   int state2;
   int state3;
   int state4;
   int state5;
   int state6;
   int state7;
   int state8;
  
   int newCol;
  
   int xVel;
   int yVel;
  
  /* These variables will contain the bits to be pushed to the PORT registers connected to the
     darlington arrays. The least significant 8 bits will be to PORTE, the middle 16 bits will 
     be to PORTD, and the most significant 8 bits will be empty.*/
    int[] red = {0,0,0,0,0};
    int[] green = {0,0,0,0,0};
    int[] blue = {0,0,0,0,0};
    
    int r;
    int g;
    int b;
  
  doEncoder();
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
  if(myPort.available() > 3) {
    /*
    statusByte = myPort.read(); //Status byte
    println(binary(statusByte));
    xByte = myPort.read(); //X vel
    yByte = myPort.read(); //Y vel
    extraByte = myPort.read(); //Extra byte, currently unused but could be used for checksum etc.  
    */
    
    while((statusByte = myPort.read()) != 0x30) {print("NEXT");}
    statusByte = myPort.read();//Status byte
    xByte = myPort.read(); //X vel
    yByte = myPort.read(); //Y vel
    if(xByte > 127) {
      xByte -= 256;
    }
    if(yByte > 127) {
      yByte -= 256; 
    }
    print(binary(statusByte));
    print("\tX=");
    print(xByte);
    print("\tY=");
    print(yByte);
    //print("\tEx=");
    //print(extraByte);
    println();
    //receivedData = statusByte + (xByte << 8) + (yByte << 16) + (extraByte << 24);
   // myPort.write(receivedData);//Echo data back to Uno
    
    
    //Reset cursor action if any movment/button presses occur
      if (xByte != 0 || yByte != 0 || (statusByte&0xF) > 0) {
        lastActTime = millis();
        cursorFlag = 0;
        
        //Display the colors under the cursor
        for(int i = 0; i < CURSOR_DIM; i++) {
          for(int j = 0; j < CURSOR_DIM; j++) {
            ledWrite(curY-1+i, curX-1+j, cursorState[i][j]);
          }
        }
      }
    
    // If clear button has been preseed, then flash the screen and clear the array
    if((statusByte & 0x08) != 0) {
      for(int i = 0; i < M; i++) {
        for(int j = 0; j < NUM_LEDS; j++) {
          ledState[i][j] = 0x07;
        }
      }
      //=================================================================
      for(int i = 0; i < CURSOR_DIM; i++) {
        for(int j = 0; j < CURSOR_DIM; j++) {
          cursorState[i][j] = 0;
        }
      }
      
      clearTime = millis();
      clearingFlag = 1;

    } else {
      // Update LEDs under cursor to appropriate colors 
      
      statusByte = statusByte & 0x07;
      
      //Only overwrite the state if the user pressed a color button
      if (statusByte > 0 && clearingFlag == 0) {
        //For 3x3 cursor - need to hardcode any changes to cursor size here
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
      
      
      // Adjust the velocities to displacements - a max displacement of the length of the
      //   cursor is needed to prevent skipping rows/columns when trying to draw a line quickly.
      //   Not sure if any of this is really necessary. We'll see.  
      if(abs(xByte) > 20) {
        xVel = 3; 
      } else if (abs(xByte) > 10) {
        xVel = 2;
      } else if (abs(xByte) > 0){
        xVel = 1;
      } else {
        xVel = 0; 
      }
      
      if(xByte < 0) {
        xVel = -xVel;
      }
      
      if(abs(yByte) > 20) {
        yVel = 3; 
      } else if (abs(yByte) > 10) {
        yVel = 2;
      } else if (abs(yByte) > 0) {
        yVel = 1;
      } else {
        yVel = 0;
      }
      
      if(yByte < 0) {
        yVel = -yVel;
      }
      
       // Move cursor position 
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
  if((millis() - lastActTime) > CURSOR_DELAY) {
    cursorFlag = ~cursorFlag; //Toggles cursor on/off
    lastActTime = millis();
  }
  
  if(cursorFlag == 0) {
    //Display the colors under the cursor
    for(int i = 0; i < CURSOR_DIM; i++) {
      for(int j = 0; j < CURSOR_DIM; j++) {
        ledWrite(curY-1+i, curX-1+j, cursorState[i][j]);
      }
    }
  } else {
    //Make the cursor "flash" (i.e. turn cursor white)
    for(int i = 0; i < CURSOR_DIM; i++) {
      for(int j = 0; j < CURSOR_DIM; j++) {
        ledWrite(curY-1+i, curX-1+j, 0x07);
      }
    }
  }
  
  if(clearingFlag == 0) {
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
          ledWrite(curY-1+i, curX-1+j, 0x07);
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
  newCol = curPos;
  //ASSUMES 120 LEDS
  //for(int m = 0; m < 5; m++) {
    //for(int i = m*24; i < (m+1)*24; i += 8) {
      /*Just doing some loop unrolling to take advantage of the cache
        If the number of LED changes to something not divisible by 8, then
        some of this unrolling needs to be undone. */
     /* state1 = ledState[newCol][i];
      state2 = ledState[newCol][i+1];
      state3 = ledState[newCol][i+2];
      state4 = ledState[newCol][i+3];
      state5 = ledState[newCol][i+4];
      state6 = ledState[newCol][i+5];
      state7 = ledState[newCol][i+6];
      state8 = ledState[newCol][i+7];
      
      red[m] = (red[m] << 1) + ((state1&REDM)>>2);
      red[m] = (red[m] << 1) + ((state2&REDM)>>2);
      red[m] = (red[m] << 1) + ((state3&REDM)>>2);
      red[m] = (red[m] << 1) + ((state4&REDM)>>2);
      red[m] = (red[m] << 1) + ((state5&REDM)>>2);
      red[m] = (red[m] << 1) + ((state6&REDM)>>2);
      red[m] = (red[m] << 1) + ((state7&REDM)>>2);
      red[m] = (red[m] << 1) + ((state8&REDM)>>2);
      
      green[m] = (green[m] << 1) + ((state1&GREENM)>>1);
      green[m] = (green[m] << 1) + ((state2&GREENM)>>1);
      green[m] = (green[m] << 1) + ((state3&GREENM)>>1);
      green[m] = (green[m] << 1) + ((state4&GREENM)>>1);
      green[m] = (green[m] << 1) + ((state5&GREENM)>>1);
      green[m] = (green[m] << 1) + ((state6&GREENM)>>1);
      green[m] = (green[m] << 1) + ((state7&GREENM)>>1);
      green[m] = (green[m] << 1) + ((state8&GREENM)>>1);
      
      blue[m] = (blue[m] << 1) + (state1&BLUEM);
      blue[m] = (blue[m] << 1) + (state2&BLUEM);
      blue[m] = (blue[m] << 1) + (state3&BLUEM);
      blue[m] = (blue[m] << 1) + (state4&BLUEM);
      blue[m] = (blue[m] << 1) + (state5&BLUEM);
      blue[m] = (blue[m] << 1) + (state6&BLUEM);
      blue[m] = (blue[m] << 1) + (state7&BLUEM);
      blue[m] = (blue[m] << 1) + (state8&BLUEM);
      
    }
  }  */
  
  for(int i = 0; i < NUM_LEDS; i++) {
    r = 255*((ledState[newCol][i]&REDM)>>2);
    g = 255*((ledState[newCol][i]&GREENM)>>1);
    b = 255*(ledState[newCol][i]&BLUEM);
    
    if(r == 0 && g == 0 && b == 0) {
      r = 30;
      g = 30;
      b = 30;
    }
   fill(r, g, b); 
   rect(newCol*4 + 4, height - (i*4 + 10), 2, 2);
   //delay(1);
  }
  /*
  for(int m = 0; m < 5; m++) {
    for(int i = m*24; i < (m+1)*24; i++) {
      print(ledState[newCol][i]);
      print("  ");
      println(((ledState[newCol][i]&REDM)>>2));
      fill(0);
      ellipse(newCol*4 + 4, i*4 + 10, 2, 2);
      fill(255*((ledState[newCol][i]&REDM)>>2),0,0);
      ellipse(newCol*4 + 4, i*4 + 10, 2, 2);
      delay(DELAY);
    }
    for(int i = m*24; i < (m+1)*24; i++) {
      fill(0);
      //ellipse(newCol*4 + 4, i*4 + 10, 2, 2);
      fill(0,255*((ledState[newCol][i]&GREENM)>>1),0);
      ellipse(newCol*4 + 4, i*4 + 10, 2, 2);
      delay(DELAY);
    }
    for(int i = m*24; i < (m+1)*24; i++) {
      fill(0);
      //ellipse(newCol*4 + 4, i*4 + 10, 2, 2);
      fill(0,0,255*((ledState[newCol][i]&BLUEM)));
      ellipse(newCol*4 + 4, i*4 + 10, 2, 2);
      delay(DELAY);
    }
  }*/
  
  count++;
}

void drawq() {
 //if(count%10 == 0)
 doEncoder();
 loop();
 
}

void doEncoder() {
  encoderPos++;
  encoderPos %= PULSE_REV-150;
  
  if(encoderPos < 150)
    encoderPos = 150;
}
