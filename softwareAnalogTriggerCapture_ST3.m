%% Software-Analog Triggered Data Capture
% Data Acquisition Toolbox provides functionality for hardware triggering 
% a data acquisition (DAQ) session, for example starting acquisition from a DAQ device 
% based on an external digital trigger signal (rising or falling edge).
% For some applications however, it is desirable to start capturing or logging data
% based on the analog signal being measured, allowing for capturing only the
% signal of interest out of a continuous stream of digitized measurement data 
% (such as an audio recording when the signal level passes a certain threshold).
% 
% This example shows how to implement a triggered data capture based on a 
% trigger condition defined in software. A custom graphical user interface
% (UI) is used to display a live plot of the data acquired in continuous
% mode, and allows a user to input trigger parameters values for a custom 
% trigger condition, which is based on the acquired analog input signal 
% level and slope. Captured data is displayed in the interactive UI, and 
% is saved to a MATLAB base workspace variable.
% 
% This example can be easily modified to instead use audio input channels
% with a DirectSound supported audio device, by changing the session channel 
% configuration code.
%
% The code is structured as a single program file, with a main function 
% and several local functions.
% 

% Copyright 2015 The MathWorks, Inc.

%% Hardware setup
%
% * A DAQ device (such as NI USB-6218) with analog input channels,
% supported by the session interface in background acquisition mode.
% * External signal connections to analog input channels. The data in this 
% example represents measured voltages from a series resistor-capacitor
% (RC) circuit: total voltage across RC (in this example supplied by a 
% function generator) is measured on channel AI0, and voltage across the 
% capacitor is measured on channel AI1.

%% Configure session and capture parameters (main function)
% Configure a session with two analog input channels and set acquisition parameters.
% Background continuous acquisition mode provides the acquired data by calling a
% user defined callback function (dataCapture) when DataAvailable events occur.
% A custom graphical user interface (UI) is used for live acquired
% data visualization and for interactive data capture based on user specified
% trigger parameters.

function softwareAnalogTriggerCapture_ST3
%softwareAnalogTriggerCapture DAQ data capture using software-analog triggering
%   softwareAnalogTriggerCapture launches a user interface for live DAQ data
%   visualization and interactive data capture based on a software analog
%   trigger condition.

% Configure data acquisition session and add analog input channels
default_font('Arial',12);
channels=10;
fname=strcat(datestr(now,'yymmdd_HHMMSS'),'.bin');

% DAQ settings
cd('C:\Task data');
s=daq.createSession('ni'); 
% First two channels
ch=addAnalogInputChannel(s,'Dev1',0:channels-1,'Voltage');
s.Rate=3000;
for i=1:channels
    ch(i).Range = [-1,1];
    ch(i).TerminalConfig = 'SingleEnded';
end
% % Separately set tone channel
% addAnalogInputChannel(s,'Dev1',2,'Current'); % Impossible with this daq
% card
% % The other channels
% ch2=addAnalogInputChannel(s,'Dev1',3:channels-1,'Voltage');
% for i=1:channels-3
%     ch2(i).Range = [-1,1];
%     ch2(i).TerminalConfig = 'SingleEnded';
% end
% Add rotary encoder
addCounterInputChannel(s, 'Dev1', 0, 'Position');
% ch1.ZResetValue = 0;
% ch1.ZResetCondition = 'BothLow';
% ch1.ZResetEnable = true;

% Specify the desired parameters for data capture and live plotting.
% The data capture parameters are grouped in a structure data type, 
% as this makes it simpler to pass them as a function argument.

% Specify triggered capture timespan, in seconds
capture.TimeSpan = 5;

% Specify continuous data plot timespan, in seconds
capture.plotTimeSpan = 5;

% Determine the timespan corresponding to the block of samples supplied 
% to the DataAvailable event callback function.
callbackTimeSpan = double(s.NotifyWhenDataAvailableExceeds)/s.Rate;
% Determine required buffer timespan, seconds
capture.bufferTimeSpan = max([capture.plotTimeSpan, capture.TimeSpan * 3, callbackTimeSpan * 3]);
% Determine data buffer size
capture.bufferSize =  round(capture.bufferTimeSpan * s.Rate);

% Display graphical user interface
hGui = createDataCaptureUI(s);

% Add a listener for DataAvailable events and specify the callback function
% The specified data capture parameters and the handles to the UI graphics
% elements are passed as additional arguments to the callback function.
addlistener(s, 'DataAvailable', @(src,event) dataCapture(src, event, capture, hGui));
fid1 = fopen(fname,'w');
addlistener(s,'DataAvailable',@(src, event)logData(src, event, fid1));

% Start continuous background data acquisition
s.IsContinuous = true;
startBackground(s);

end

%% Background acquisition callback function
% The dataCapture user-defined callback function is being called repeatedly,
% each time a DataAvailable event occurs.
% With each callback function execution, the latest acquired data block and 
% timestamps are added to a persistent FIFO data buffer, a continuous acquired 
% data plot is updated, latest data is analyzed to check whether the trigger
% condition is met, and -- once capture is triggered and enough data has been 
% captured for the specified timespan -- captured data is saved in a base
% workspace variable. The captured data is an N x M matrix corresponding 
% to N acquired data scans, with the timestamps as the first column, and 
% the acquired data corresponding to each channel as columns 2:M.

function dataCapture(src, event, c, hGui)
%dataCapture Process DAQ acquired data when called by DataAvailable event.
%  dataCapture (SRC, EVENT, C, HGUI) processes latest acquired data (EVENT.DATA)
%  and timestamps (EVENT.TIMESTAMPS) from session (SRC), and, based on specified 
%  capture parameters (C structure) and trigger configuration parameters from
%  the user interface elements (HGUI handles structure), updates UI plots
%  and captures data.
%
%   c.TimeSpan        = triggered capture timespan (seconds)
%   c.bufferTimeSpan  = required data buffer timespan (seconds)
%   c.bufferSize      = required data buffer size (number of scans)
%   c.plotTimeSpan    = continuous acquired data timespan (seconds)
%

% The incoming data (event.Data and event.TimeStamps) is stored in a
% persistent buffer (dataBuffer), which is sized to allow triggered data
% capture.

% Since multiple calls to dataCapture will be needed for a triggered
% capture, a trigger condition flag (trigActive) and a corresponding
% data timestamp (trigMoment) are used as persistent variables.
% Persistent variables retain their values between calls to the function.

persistent dataBuffer trigActive trigMoment

% If dataCapture is running for the first time, initialize persistent vars
if event.TimeStamps(1)==0
    dataBuffer = [];          % data buffer
    trigActive = false;       % trigger condition flag
    trigMoment = [];          % data timestamp when trigger condition met
    prevData = [];            % last data point from previous callback execution
else
    prevData = dataBuffer(end, :);
end

% Store continuous acquistion data in persistent FIFO buffer dataBuffer
ed=event.Data;
et=event.TimeStamps;

% Calculate angular speed
positionData=ed(:,end);
encoderCPR=2500;
counterNBits = 32;
signedThreshold = 2^(counterNBits-1);
signedData = positionData;
signedData(signedData > signedThreshold) = signedData(signedData > signedThreshold) - 2^counterNBits;
positionDataDeg = signedData * 360/encoderCPR;
Degchange=positionDataDeg(end)-positionDataDeg(1);
% positionDataDeg=smooth(positionDataDeg);
% speedData=positionDataDeg-circshift(positionDataDeg,1);
% speedData(1)=speedData(2);
ed(:,end)=Degchange/20;

% Adjust the data
n=size(ed,2);
ed(:,1)=1-ed(:,1);
ed(:,1:2)=round(ed(:,1:2));
ed(:,4:n-1)=round(ed(:,4:n-1));
% ed(:,2:n-1)=round(ed(:,2:n-1));
% ed(:,1)=ed(:,1)>0.1;
ed=ed+repmat(2*fliplr(1:n),[size(ed,1),1]);

latestData = [et, ed];
dataBuffer = [dataBuffer; latestData];
numSamplesToDiscard = size(dataBuffer,1) - c.bufferSize;
if (numSamplesToDiscard > 0)
    dataBuffer(1:numSamplesToDiscard, :) = [];
end

% Update live data plot
% Plot latest plotTimeSpan seconds of data in dataBuffer
samplesToPlot = min([round(c.plotTimeSpan * src.Rate), size(dataBuffer,1)]);
firstPoint = size(dataBuffer, 1) - samplesToPlot + 1;
% Update x-axis limits
xlim(hGui.Axes1, [dataBuffer(firstPoint,1), dataBuffer(end,1)]);
% Live plot has one line for each acquisition channel
for ii = 1:numel(hGui.LivePlot)
    set(hGui.LivePlot(ii), 'XData', dataBuffer(firstPoint:end, 1), ...
                           'YData', dataBuffer(firstPoint:end, 1+ii))
end
ylim(hGui.Axes1,[0,2*size(ed,2)+2]);
drawnow;

end

%% Create a graphical user interface for live data capture
% Create a user interface programmatically, by creating a figure, one plot
% for live acquired data, one plot for captured data, buttons for starting 
% capture and stopping acquisition, and text fields for entering trigger 
% configuration parameters and status update.
% 
% For simplicity, the figure and all user interface components have a fixed
% size and position defined in pixels. For high DPI displays the position
% values might have to be adjusted for optimum dimensions and layout.
% Another option for creating a custom UI is to use GUIDE.

function hGui = createDataCaptureUI(s)
%CREATEDATACAPTUREUI Create a graphical user interface for data capture.
%   HGUI = CREATEDATACAPTUREUI(S) returns a structure of graphics
%   components handles (HGUI) and creates a graphical user interface, by 
%   programmatically creating a figure and adding required graphics 
%   components for visualization of data acquired from a DAQ session (S).   

% Create a figure and configure a callback function (executes on window close)
scr=get(0,'ScreenSize'); W=scr(3); H=scr(4);
hGui.Fig = figure('Name','Software-analog triggered data capture', ...
    'NumberTitle', 'off', 'Resize', 'off', 'Position', [5 700 W-10 H-780]);
set(hGui.Fig, 'DeleteFcn', {@endDAQ, s});
% uiBackgroundColor = get(hGui.Fig, 'Color');

% Create the continuous data plot axes with legend
% (one line per acquisition channel)
hGui.Axes1 = axes;
hGui.LivePlot = plot(0, zeros(1, numel(s.Channels)));
xlabel('Time (s)');
ylabel('Voltage (V)');
title('Continuous data');
% leg=get(s.Channels(1:end-1), 'ID');
% leg=vertcat(leg,s.Channels(end).ID);
leg={'Trial on','Stim 1','Cue 1','Reward','Lick','Frame','Punish','Trigger','Manual stim','Photostim','Running'};
legend(leg,'Position',[0.047 0.25 0.05 0.6]);
set(hGui.Axes1, 'Units', 'Pixels', 'Position',  [200 30 W-230 H-830]);

% Create a stop acquisition button and configure a callback function
hGui.DAQButton = uicontrol('style', 'pushbutton', 'string', 'Stop DAQ',...
    'units', 'pixels', 'position', [65 10 81 38]);
set(hGui.DAQButton, 'callback', {@endDAQ, s});
    
end

function endDAQ(~, ~, s)
if isvalid(s)
    if s.IsRunning
        stop(s);
        fclose('all');
        close;
    end
end
end

