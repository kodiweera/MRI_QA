% plot the .xml files we generate
%
% spline options: 1 (splinefit w/monthly control points) 
%   2 (interp/spline w/biweekly control points)
%   3 (lowess)
%
% 1 has some trouble with 14 day control points and uses 30 instead

function plot_charts(do_spline)

  if ~exist('do_spline', 'var')
    do_spline = 3;
  end
  
  names = {'Scan 1 (200)', 'Scan 2 (100)', 'vvnbk'};
  sourcefiles = {};
  for i = 1:length(names)
    sourcefiles = [sourcefiles [pwd '/html/' names{i} '.xls']];
  end
  % now with 2 sites
  %siteplotmarks = {'gx', 'rx', 'bx'};
  %siteplotmarks2 = {'g--', 'r--', 'b--'};  
  siteplotmarks = {'gx', 'rx'};
  siteplotmarks2 = {'g--', 'r--'};  
  allplotvals = {'SNR', 'SFNR', 'drift', 'rdc', 'percentFluc'};  
  
  % now using fragments since IU's changed at one point; Colorado can
  % appear as "Brain Imaging Center UCHSC 3T" or "... UCDenver 3T".
  %sitenames = {'Dartmouth', 'Indiana', ...
  %             'Brain Imaging Center UC'};
  sitenames = {'Dartmouth', 'Indiana'};
  
  [sel, OK] = slistdlg('ListString', allplotvals);
  if ~OK, return, end
  plotvals = allplotvals(sel);
  
  for i = 1:length(sourcefiles)
    
    clear inst site
    D = read_tab_delim(sourcefiles{i});
    D = setfield(D, 'datenum', datenum(strcat(D.scandate, ...
                                              repmat({' '}, ...
                                                     length(D.scandate), ...
                                                     1), ...
                                              D.scantime)));
    % may need to sort in case filenames didn't do that?
    [~, idx] = sort(D.datenum);
    D = filter_struct(D, 'entry', idx);
    
    for j = 1:length(D.institution)
      for k = 1:length(sitenames)
        if strfind(upper(D.institution{j}), upper(sitenames{k}))
          inst(j) = k;
        end
      end
    end
    for j = 1:max(inst)
      site{j} = find(inst == j);
    end
    
    nplots = length(plotvals);
    % fig = figure('Position',[255 1 1450 600],'PaperPositionMode','auto','visible','off');
    figure('PaperPositionMode', 'auto'); scalefigure(2.5,0.5*nplots)
    
    for p = 1:nplots
      subplot(nplots, 1, p);
      hold on
      if p == 1
        title([names{i} ' (red=Indiana, green=Dartmouth)'], ...
              'FontWeight', 'Bold');
      end
      vals = getfield(D, plotvals{p});
      for j = 1:length(site)
        if do_spline == 1 | do_spline == 3 | do_spline == 0
          plot(D.datenum(site{j}), vals(site{j}), siteplotmarks{j});
        elseif do_spline == 2
          scatter(D.datenum(site{j}), vals(site{j}), siteplotmarks{j});
          plot( min(D.datenum(site{j})):14:max(D.datenum(site{j})), ...
                interp1(D.datenum(site{j}), vals(site{j}), ...
                        min(D.datenum(site{j})):25:max(D.datenum(site{j})), ...
                        'cubic'), siteplotmarks2{j})
        end
        % label outliers - note that if lowess is used, it may cause a
        % "baseline" deviation around an extreme point that causes
        % "normal" points in the vicinity to be labeled as outliers;
        % thus, this is using simple "y" detection mode.
        label_outliers(D.datenum(site{j}), vals(site{j}), ...
                       cellstr(datestr(floor(D.datenum(site{j})))), ...
                       'y', 3);
      end
      ylabel(plotvals{p});
      xlabel(['2010-present'])
      
      %datetick
      %datetick('x', 28)
      datetick('x', 12)
      
      if do_spline == 1
        for j = 1:length(site)
          if length(site{j}) > 10
            % the MATLAB "spline" always exactly fits points, which is bad for
            % noisy data
            %cs = spline(udnum, udtival, [min(udnum):max(udnum)]);
            %plot([min(udnum):max(udnum)], cs, '--')
            
            % 'splinefit' can reduce the number of breakpoints and make a best
            % fit. One must specify breakpoints (control points)
            breakint = 30;
            breaks = [min(D.datenum(site{j})):breakint:max(D.datenum(site{j}))];
            pp = splinefit(D.datenum(site{j}), vals(site{j}), breaks);
            plot([min(D.datenum(site{j})):max(D.datenum(site{j}))], ...
                 ppval(pp, [min(D.datenum(site{j})):max(D.datenum(site{j}))]), ...
                 [siteplotmarks{j}(1) ':']);
          end
        end
      elseif do_spline == 3
        for j = 1:length(site)
          % lowess
          try
            [L1,L2,L3,L4] = lowess([D.datenum(site{j}) vals(site{j})'], 0.05);
            plot(L4(:,1), L4(:,2), [siteplotmarks{j}(1) '--'], ...
                 'LineWidth', 2);
          end
        end
      end
    end


    % fix axis bounds
    for p = 1:nplots
      subplot(nplots, 1, p);
      a = axis;
      a(1:2) = [(min(D.datenum) - 5) (max(D.datenum)+5)];
      m1 = inf; m2 = 0;
      ch = get(gca, 'Children');
      for q = 1:length(ch)
        if strcmp('text', get(ch(q), 'Type'))
          continue
        end
        yvals = get(ch(q), 'YData');
        m1 = min(m1, min(yvals));
        m2 = max(m2, max(yvals));
      end
      diff = m2 - m1;
      a(3) = max(0, m1 - diff/10);
      a(4) = m2 + diff/10;
      axis(a);
      % expand to avoid huge margins
      pos = get(gca, 'Position');
      set(gca, 'Position', [0.055 pos(2) 0.9 pos(4)]);
      sigevents([0 0 0.9]);
    end
    
    saveas(gcf, [pwd '/html/' names{i} '.png'], 'png');
  end

  disp('Updating HTML...')
  pause(0.1)
  wsystem('source html_prep.sh');
  disp('Now use html_up.sh')
