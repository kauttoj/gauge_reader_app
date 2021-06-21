classdef gauge_reader_app < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure            matlab.ui.Figure
        UIAxes              matlab.ui.control.UIAxes
        LoadButton          matlab.ui.control.Button
        FileEditFieldLabel  matlab.ui.control.Label
        FileEditField       matlab.ui.control.EditField
        AnalyzeButton       matlab.ui.control.Button
        x_minEditFieldLabel     matlab.ui.control.Label
        x_minEditField          matlab.ui.control.NumericEditField
        x_maxEditFieldLabel     matlab.ui.control.Label
        x_maxEditField          matlab.ui.control.NumericEditField
        y_minEditFieldLabel     matlab.ui.control.Label
        y_minEditField          matlab.ui.control.NumericEditField
        y_maxEditFieldLabel     matlab.ui.control.Label
        y_maxEditField          matlab.ui.control.NumericEditField
        x_centerEditFieldLabel  matlab.ui.control.Label
        x_centerEditField       matlab.ui.control.NumericEditField
        y_centerEditFieldLabel  matlab.ui.control.Label
        y_centerEditField       matlab.ui.control.NumericEditField   
        dtEditFieldLabel  matlab.ui.control.Label
        dtEditField       matlab.ui.control.NumericEditField        
        thresholdEditFieldLabel     matlab.ui.control.Label        
        thresholdEditField      matlab.ui.control.NumericEditField                
        timeEditFieldLabel     matlab.ui.control.Label
        timeEditField      matlab.ui.control.NumericEditField         
        video_object
        init_frame
        mouse_position
        crop_area
        cropped_frame
        cropped_frame_orig
        flood_mask
        savefile
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Button pushed function: LoadButton
        function LoadButtonPushed(app, event)
            app.crop_area = [];
            if isempty(app.init_frame) || app.video_object.CurrentTime~=app.timeEditField.Value
                assert(exist(app.FileEditField.Value,'file')>0,sprintf('Input file ''%s'' not found!',app.FileEditField.Value));                
                app.video_object = VideoReader(app.FileEditField.Value);
                app.savefile = [app.FileEditField.Value(1:(end-4)),'_RESULTS.mat'];                
                app.video_object.CurrentTime = app.timeEditField.Value;
                app.init_frame = readFrame(app.video_object);
                real_time = app.video_object.CurrentTime*app.video_object.Framerate*app.dtEditField.Value;
                fprintf('%s: loaded frame at %.1fs (real time ~%.1fs)\n',app.FileEditField.Value,app.video_object.CurrentTime,real_time);
                try
                    load(app.savefile,'crop_area','threshold');
                    app.crop_area = crop_area;
                    app.thresholdEditField.Value = threshold;
                end                    
            end
            
            if isempty(app.crop_area)
                app.crop_area = [1,size(app.init_frame,2),1,size(app.init_frame,1)];
                if app.x_minEditField.Value>-1
                    app.crop_area(1) = app.x_minEditField.Value;
                end
                if app.x_maxEditField.Value>-1
                    app.crop_area(2) = app.x_maxEditField.Value;
                end
                if app.y_minEditField.Value>-1
                    app.crop_area(3) = app.y_minEditField.Value;
                end
                if app.y_maxEditField.Value>-1
                    app.crop_area(4) = app.y_maxEditField.Value;
                end
            else
                app.x_minEditField.Value = app.crop_area(1);
                app.y_minEditField.Value = app.crop_area(3);
                app.x_maxEditField.Value = app.crop_area(2);
                app.y_maxEditField.Value = app.crop_area(4);                
            end
            app.cropped_frame_orig = app.init_frame(app.crop_area(3):app.crop_area(4),app.crop_area(1):app.crop_area(2),:);            
            app.cropped_frame = app.cropped_frame_orig;            
            image(app.cropped_frame_orig,'parent',app.UIAxes);
            app.x_minEditField.Value=app.crop_area(1);
            app.y_minEditField.Value=app.crop_area(3);
            app.x_maxEditField.Value=app.crop_area(2);
            app.y_maxEditField.Value=app.crop_area(4);
        end

        % Button pushed function: AnalyzeButton
        function AnalyzeButtonPushed(app, event)           
            if isempty(app.video_object)
                error('No video loaded!');
            end                       
         
            [optimizer, metric] = imregconfig('monomodal');
            %optimizer.MaximumIterations = 400;
            %optimizer.GradientMagnitudeTolerance = 1e-4;
            %optimizer.RelaxationFactor = 0.60;           
            
            crop_area = app.crop_area;
            center_point = [app.x_centerEditField.Value,app.y_centerEditField.Value];
            threshold = app.thresholdEditField.Value;     
            info = struct(app.video_object);
            total_frames = info.NumberOfFrames;
            
            if exist(app.savefile,'file')
                save(app.savefile,'crop_area','threshold','center_point','info','total_frames','-append');            
            else
                save(app.savefile,'crop_area','threshold','center_point','info','total_frames');
            end             

            fig1 = figure('position',[10,10,200,200]);
            fig2 = figure('position',[300,10,200,200]);
            
            frame_delta = app.dtEditField.Value; % seconds per frame
            assert(frame_delta>0,'frame_delta must be positive!');
            fprintf('\nStarting analysis of file ''%s'' with %.1fsec/frame\n',app.FileEditField.Value,frame_delta);
            
            start=app.timeEditField.Value;
            time = 0;
            frame = 0;         
            analyzed_frame = 0;
            previous_J=nan;
            init_pixels = [];            
            errors = [];
            angles = [];
            thresholds=[];            
            ratios = [];
            difference_ratio=nan;
            pixels = [];                       
            app.video_object.CurrentTime = 0;   
            target_pixels = nan;
            tic;
            while hasFrame(app.video_object)
                frame = frame+1;              
                I = readFrame(app.video_object);                                                
                angle_change = nan;
                pixelcount=nan;
                err = nan;                
                if time>start
                    analyzed_frame = analyzed_frame + 1;
                    I = I(app.crop_area(3):app.crop_area(4),app.crop_area(1):app.crop_area(2),:);
                    flag = 1;
                    iteration = 0;
                    direction = 0;
                    while flag                        
                        J=getmask(app,I,threshold);
                        pixelcount = sum(J(:));
                        if isnan(target_pixels)
                            init_pixels(end+1)=pixelcount;
                            if length(init_pixels)==20
                                target_pixels = median(init_pixels);
                                save(app.savefile,'target_pixels','J','-append');
                            end
                            flag = 0;
                            fprintf('...initial frame %i (%f pixels)\n',length(init_pixels),pixelcount);
                            plot_figure(app,J,I);
                            pause(0.20);
                        else
                            iteration=iteration+1;
                            if iteration>15
                                flag = 0;
                            elseif pixelcount/target_pixels<0.90 && (direction==0 || direction==1)
                                direction = 1;
                                threshold = threshold*1.05;
                                fprintf('.....frame %i: increasing threshold to %f\n',frame,threshold)
                            elseif pixelcount/target_pixels>1.10 && (direction==0 || direction==-1)
                                direction = -1;
                                threshold = threshold*0.95;
                                fprintf('.....frame %i: reducing threshold to %f\n',frame,threshold)
                            else
                                flag = 0;
                            end
                        end
                    end
                                        
                    if ~isnan(previous_J)
                        
                        fixed = single(J);
                        moving = single(previous_J);
                        
                        fixedRef = imref2d(size(fixed));
                        fixedRef.XWorldLimits = fixedRef.XWorldLimits - center_point(1);
                        fixedRef.YWorldLimits = fixedRef.YWorldLimits - center_point(2);
                        
                        %clf;                        
                        min_error = inf;
                        all_err=[];
                        moving_registered_best = nan;
                        for theta=[0:4,5:10:355,356:359]
                            rot = [cosd(-theta) -sind(-theta) 0;...
                                sind(-theta) cosd(-theta) 0;...
                                0 0 1];
                            if theta==0
                                init_tform = affine2d(rot);
                            else
                                init_tform.T=rot;
                            end                        
                            tform = init_tform;
                            moving_registered = imwarp(moving,fixedRef,tform,'OutputView',fixedRef,'interp','linear','FillValues',0);

                            err = sum(sum((fixed - moving_registered).^2));
                            if err<min_error
                                min_error = err;
                                tform_final = tform;
                                moving_registered_best = moving_registered;
                            end
                            all_err(end+1)=err;
                        end
                        tform = imregtform(moving,fixedRef,fixed,fixedRef,'rigid',optimizer,metric,'InitialTransformation',tform_final);
                        moving_registered = imwarp(moving,fixedRef,tform,'OutputView',fixedRef,'interp','linear','FillValues',0);
                        err = sum(sum((fixed - moving_registered).^2));
                        if err<min_error
                            min_error = err;
                            tform_final = tform;
                            moving_registered_best = moving_registered;
                        end
                        angle_change = -atan2d(tform_final.T(2,1),tform_final.T(1,1));
                        difference_ratio = 2*sum(sum(abs(fixed - moving_registered)))/(sum(fixed(:)) + sum(moving_registered(:)));
                        
                        if 0
                            
                            clf(fig1);                 
                            imshowpair(fixed,moving_registered_best,'Scaling','joint','parent',gca(fig1));                          
                            plot(center_point(1),center_point(2),'co','parent',gca(fig1));                        
                            title(sprintf('frame %i (%.1fmin), anglediff. %.1fdeg\n',frame,time/60,angle_change),'parent',gca(fig1));

                            clf(fig2);
                            imshowpair(fixed,moving,'Scaling','joint','parent',gca(fig2));
                            plot(center_point(1),center_point(2),'co','parent',gca(fig2));
                            title(sprintf('frame %i (%.1fmin), anglediff. %.1fdeg\n',frame,time/60,angle_change),'parent',gca(fig2));
                            
                            pause(0.01);
                        end
                    end                    
                    previous_J=J;                                        
                end
                time = time + frame_delta;
                
                angles(frame)= angle_change;
                times(frame) = time;
                errors(frame) = err;
                pixels(frame) = pixelcount;
                ratios(frame) = difference_ratio;
                thresholds(frame) = threshold;
                
                if mod(analyzed_frame+1,500)==0
                    runtime = toc;
                    
                    fprintf('frame %i/%i, time %.1fmin (%.2f hours), %.1f frames/sec, runtime %.1fmin\n',frame,total_frames,time/60,time/60/60,analyzed_frame/runtime,runtime/60);
                    data.times = times;
                    data.angles = angles;
                    data.errors =errors;
                    data.pixels = pixels;
                    data.ratios = ratios;
                    save(app.savefile,'data','runtime','-append');                                      
                    
                    clf(fig1);                   
                    imshowpair(fixed,moving_registered_best,'Scaling','joint','parent',gca(fig1));
                    hold(gca(fig1));                    
                    plot(center_point(1),center_point(2),'co','parent',gca(fig1));                        
                    title(sprintf('frame %i (%.1fmin), anglediff. %.1fdeg\n',frame,time/60,angle_change),'parent',gca(fig1));
                    
                    clf(fig2);                    
                    imshowpair(fixed,moving,'Scaling','joint','parent',gca(fig2));
                    hold(gca(fig2));                          
                    plot(center_point(1),center_point(2),'co','parent',gca(fig2));
                    title(sprintf('frame %i (%.1fmin), anglediff. %.1fdeg\n',frame,time/60,angle_change),'parent',gca(fig2));
                                              
                    pause(0.01);
                end                
                
            end
            runtime = toc;
            
            fprintf('frame %i (LAST), time %.1fmin (%.2f hours), %.1f frames/sec\n',frame,time/60,time/60/60,frame/runtime);
            data.times = times;
            data.angles = angles;
            data.errors =errors;
            data.pixels = pixels;
            data.ratios = ratios;
            data.thresholds = threshold;
            save(app.savefile,'data','runtime','-append');               
                        
            close(fig2);
            close(fig1);
            
            fprintf('\nAnalysis finished!\n');
        end
        
        function J = getmask(app,frame,threshold)
            J = regiongrowing(frame,app.x_centerEditField.Value,app.y_centerEditField.Value,threshold);
            J = mean(J,3)>0;
            windowSize = 5;
            kernel = ones(windowSize)/windowSize^2;
            mask = conv2(1-J, kernel, 'same');
            J(mask>0.5)=0;
            return
        end
        
        function UIFigureWindowButtonDown(app, event)
            %Create if statement that determines if the user clicked on the
            %line of the top UIAxes. If they didn't, do nothing
            if ~isempty(app.cropped_frame)
                image_pos = round(app.UIAxes.CurrentPoint);
                image_pos = image_pos(1,1:2);
                if any(image_pos<0)
                    return
                end
                center_point=image_pos;                
                app.x_centerEditField.Value = center_point(1);
                app.y_centerEditField.Value = center_point(2);
                J=getmask(app,app.cropped_frame_orig,app.thresholdEditField.Value);
                plot_figure(app,J)                               
            end
        end
        
        function plot_figure(app,J,I)
            val = [255,182,193];
            app.flood_mask = J;
            if nargin<3
                III = app.cropped_frame_orig;
            else
                III = I;
            end                
            for i=1:3
                II = III(:,:,i);
                II(J)=0.5*II(J) + 0.5*val(i);
                III(:,:,i)=II;
            end            
            image(III,'parent',app.UIAxes);
            hold(app.UIAxes,'on');            
            plot(app.x_centerEditField.Value,app.y_centerEditField.Value,'co','parent',app.UIAxes);
            hold(app.UIAxes,'off');
        end
        
        function mouseMove(app,event)
           app.mouse_position = event.Source.CurrentPoint;
        end
        
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 640 550];
            app.UIFigure.Name = 'UI Figure';
            %app.UIFigure.ButtonDownFcn = createCallbackFcn(app, @UIFigureButtonDown, true);
            app.UIFigure.WindowButtonDownFcn = createCallbackFcn(app, @UIFigureWindowButtonDown, true);

            % Create LoadButton
            app.LoadButton = uibutton(app.UIFigure, 'push');
            app.LoadButton.ButtonPushedFcn = createCallbackFcn(app, @LoadButtonPushed, true);
            app.LoadButton.Position = [13 520 59 22];
            app.LoadButton.Text = 'Load';

            % Create FileEditFieldLabel
            app.FileEditFieldLabel = uilabel(app.UIFigure);
            app.FileEditFieldLabel.HorizontalAlignment = 'right';
            app.FileEditFieldLabel.Position = [90 520 25 22];
            app.FileEditFieldLabel.Text = 'File';
            
            app.UIAxes = uiaxes(app.UIFigure);
            title(app.UIAxes, 'Title')
            xlabel(app.UIAxes, 'X')
            ylabel(app.UIAxes, 'Y')
            app.UIAxes.Position = [90 20 530 430];
            xlabel('','parent',app.UIAxes)
            ylabel('','parent',app.UIAxes)
            title('','parent',app.UIAxes)
            app.UIAxes.DataAspectRatio=[1,1,1];
            app.UIAxes.Visible='off';            

            % Create FileEditField
            app.FileEditField = uieditfield(app.UIFigure, 'text');
            app.FileEditField.Position = [130 520 491 22];
            app.FileEditField.Value='';

            % Create AnalyzeButton
            app.AnalyzeButton = uibutton(app.UIFigure, 'push');
            app.AnalyzeButton.ButtonPushedFcn = createCallbackFcn(app, @AnalyzeButtonPushed, true);
            app.AnalyzeButton.Position = [13 391 59 37];
            app.AnalyzeButton.Text = 'Analyze';
            
            % Create x_minEditFieldLabel
            app.x_minEditFieldLabel = uilabel(app.UIFigure);
            app.x_minEditFieldLabel.HorizontalAlignment = 'right';
            app.x_minEditFieldLabel.Position = [170 490 38 22];
            app.x_minEditFieldLabel.Text = 'x_min';

            % Create x_minEditField
            app.x_minEditField = uieditfield(app.UIFigure, 'numeric');
            app.x_minEditField.Position = [223 490 44 22];

            % Create x_maxEditFieldLabel
            app.x_maxEditFieldLabel = uilabel(app.UIFigure);
            app.x_maxEditFieldLabel.HorizontalAlignment = 'right';
            app.x_maxEditFieldLabel.Position = [266 490 41 22];
            app.x_maxEditFieldLabel.Text = 'x_max';

            % Create x_maxEditField
            app.x_maxEditField = uieditfield(app.UIFigure, 'numeric');
            app.x_maxEditField.Position = [322 490 43 22];

            % Create y_minEditFieldLabel
            app.y_minEditFieldLabel = uilabel(app.UIFigure);
            app.y_minEditFieldLabel.HorizontalAlignment = 'right';
            app.y_minEditFieldLabel.Position = [364 490 38 22];
            app.y_minEditFieldLabel.Text = 'y_min';

            % Create y_minEditField
            app.y_minEditField = uieditfield(app.UIFigure, 'numeric');
            app.y_minEditField.Position = [417 490 43 22];

            % Create y_maxEditFieldLabel
            app.y_maxEditFieldLabel = uilabel(app.UIFigure);
            app.y_maxEditFieldLabel.HorizontalAlignment = 'right';
            app.y_maxEditFieldLabel.Position = [467 490 40 22];
            app.y_maxEditFieldLabel.Text = 'y_max';

            % Create y_maxEditField
            app.y_maxEditField = uieditfield(app.UIFigure, 'numeric');
            app.y_maxEditField.Position = [523 490 43 22];

            % Create x_centerEditFieldLabel
            app.x_centerEditFieldLabel = uilabel(app.UIFigure);
            app.x_centerEditFieldLabel.HorizontalAlignment = 'right';
            app.x_centerEditFieldLabel.Position = [130 460 52 22];
            app.x_centerEditFieldLabel.Text = 'x_center';

            % Create x_centerEditField
            app.x_centerEditField = uieditfield(app.UIFigure, 'numeric');
            app.x_centerEditField.Position = [193 460 49 22];

            % Create y_centerEditFieldLabel
            app.y_centerEditFieldLabel = uilabel(app.UIFigure);
            app.y_centerEditFieldLabel.HorizontalAlignment = 'right';
            app.y_centerEditFieldLabel.Position = [264 460 52 22];
            app.y_centerEditFieldLabel.Text = 'y_center';

            % Create y_centerEditField
            app.y_centerEditField = uieditfield(app.UIFigure, 'numeric');
            app.y_centerEditField.Position = [331 460 47 22];              

            % Create y_centerEditFieldLabel
            app.dtEditFieldLabel = uilabel(app.UIFigure);
            app.dtEditFieldLabel.HorizontalAlignment = 'left';
            app.dtEditFieldLabel.Position = [10 120 47 22]; 
            app.dtEditFieldLabel.Text = 'sec/frame';

            % Create y_centerEditField
            app.dtEditField = uieditfield(app.UIFigure, 'numeric');
            app.dtEditField.Position = [10 100 47 22];                                                 
            app.dtEditField.Value = 1.00;                        
            
            % Create y_centerEditFieldLabel
            app.thresholdEditFieldLabel = uilabel(app.UIFigure);
            app.thresholdEditFieldLabel.HorizontalAlignment = 'left';
            app.thresholdEditFieldLabel.Position = [10 200 55 22]; 
            app.thresholdEditFieldLabel.Text = 'threshold';

            % Create y_centerEditField
            app.thresholdEditField = uieditfield(app.UIFigure, 'numeric');
            app.thresholdEditField.Position = [10 180 47 22];                                                 
            app.thresholdEditField.Value = 0.17;
            
            % Create y_centerEditFieldLabel
            app.timeEditFieldLabel = uilabel(app.UIFigure);
            app.timeEditFieldLabel.HorizontalAlignment = 'left';
            app.timeEditFieldLabel.Position = [10 280 55 22]; 
            app.timeEditFieldLabel.Text = 'time [s]';

            % Create y_centerEditField
            app.timeEditField = uieditfield(app.UIFigure, 'numeric');
            app.timeEditField.Position = [10 260 47 22];                                                 
            app.timeEditField.Value = 10;            
            
            app.x_minEditField.Value=-1;
            app.y_minEditField.Value=-1;
            app.x_maxEditField.Value=-1;
            app.y_maxEditField.Value=-1;           

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';            
            app.video_object = [];            
            app.crop_area = nan;
            app.cropped_frame = [];
            app.cropped_frame_orig = [];
            app.init_frame=[];
            app.flood_mask=[];
            app.savefile = nan;
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = gauge_reader_app

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end