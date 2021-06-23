# gauge_reader_app
A simple Matlab app to analyze analogue gauge measurements from video files. This is a rough initial version without error-checking or polishing. Made using Matlab 2019b.

Assumptions of the video:
1. includes a fully visible, analogue gauge meter with a distinguishable needle (e.g., different color than the background)
2. stable and static such that the needle center stays at the same place (no shaky camera!)
3. at least hundred frames or so, but the more the better
4. lightning conditions are relatively stable for the whole duration of the video (e.g., enough light during night and not burn-in during day)
5. "good-enough" resolution to distinguish the needle positions well (depends on needle shape)

How to use:

1. execute gauge_reader_app.m to launch GUI
2. set 'sec/frame' to interval between frames
4. type full path of a video file containing analogue gauge meter with 
5. set 'time [s]' to choose preview frame (>0 preferred to allow stabilization/focus of recording)
6. click 'load' to load video and show a frame at selected timepoint
7. fine-tune x_min/max and y_min/max parameters to focus gauge meter. After changing values, press 'load' to get a new frame
8. click the rotational center of the gauge meter to segment the pointer
9. in case segmenting was not good enough (too little of too much), fine-tune 'threshold' and repeat step 8 until its good
10. hit 'Analyze' to start analysis and wait (could takes minutes to hours depending on number of frames)
11. results are saved as .mat file into the same folder as the source video (snapshots are saved every 500 frames)

The program reads and segments each frame and uses alignment algorithm to estimate change of angle between each frame. Segmentation threshold is automatically adjusted to keep the total size of segment close to that created by the user.

The result file contains struct 'data' with following fields:

data.times  - timepoint in actual measurement time

data.angles  -  change of angle between consecutive frames between -180 and +180 degrees such that 0 is no change and positive values are clockwise rotations.

data.errors  -  error of alignment (if 0, two frames are identical)

data.pixels - number of pixels in the segmented needle mask

data.ratios  - ratio of non-overlapping pixels after alignment per mask size (similar to error)

data.thresholds  - segmentation threshold used for the current frame


For the segmentation, I used a modified version of the function by D. Kroon (University of Twente), see: https://www.mathworks.com/matlabcentral/fileexchange/19084-region-growing


Example of an original video frame (water meter):

![vlcsnap-2021-06-21-10h39m26s527](https://user-images.githubusercontent.com/17804946/122725067-4b3d8500-d27d-11eb-94fa-b5b846b84b34.png)

Example of the same video after focusing, choosing the center point and segmenting the red needle:

![image](https://user-images.githubusercontent.com/17804946/122724853-06b1e980-d27d-11eb-8d31-2cda3ea25bdf.png)

Plotted timeseries of detected needle rotations:

![image](https://user-images.githubusercontent.com/17804946/123050857-d0ee3b80-d409-11eb-9f30-e26f45055c96.png)



21.6.2021 Janne K
