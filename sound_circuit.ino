/////////// code for the sound arduino to play depending on input a pure tone of various frequency or white noise ////



///////  variables to set
/// pins
int input_go_cue = 3; /// set frequency below
int input_false_alarm = 5;   /// white noise
//int input_trial_tone = 7;   /// set frequency below
int output_pin = 8;   //connected to speaker

/// others
int frequency_gocue = 6000; 
//int frequency_trial_tone = 500; 

int go_cue;
int false_alarm;
//int trial_tone; 

void setup()
{
  pinMode(input_go_cue, INPUT);
  pinMode(input_false_alarm, INPUT);
  //pinMode(input_trial_tone, INPUT);
  pinMode(output_pin, OUTPUT);

  digitalWrite(input_go_cue,LOW);
  digitalWrite(input_false_alarm,LOW);
  //digitalWrite(input_trial_tone,LOW);
  digitalWrite(output_pin, LOW);
}


void loop()
{
  
  go_cue=digitalRead(input_go_cue);
  false_alarm=digitalRead(input_false_alarm);
  //trial_tone=digitalRead(input_trial_tone);

  if (false_alarm == HIGH) {   
      if(random(2) == 0)    ///random number of 0 or 1 
          digitalWrite(output_pin,LOW);
       else digitalWrite(output_pin,HIGH);
  } 
  if (go_cue == HIGH) {   
    tone(output_pin, frequency_gocue, 1);  // needs duration - otherwise stays on
  } 

  //if (trial_tone == HIGH) {   
  //  tone(output_pin, frequency_trial_tone, 1);  // needs duration - otherwise stays on
  //} 

}


