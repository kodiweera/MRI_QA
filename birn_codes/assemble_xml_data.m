%ASSEMBLE_XML_DATA  read multiple FBIRN XML files and create an output
%
%16 Dec 2015: attempt a speedup by assuming existing table can be used
%

%addpath('/home/kodiweera/Documents/MATLAB/toolboxes/xml_toolbox')

function assemble_xml_data
  
  use_cached = 1;

  %NOTE: this uses xml_parseany from the XML Toolbox, which only works on
  %older MATLAB.
%   v = version;
%   vdot = strfind(v, '.');
%   vnum = str2num(v(1:vdot(2)-1));
%   if vnum > 8
%     disp(['Sorry, this won''t work on this version of MATLAB' ...
%           ' (need older version, v8 or less)']);
%     return
%   end
  
%[mode, moden] = cquestdlg('Which scans?', 'Choose Scan Type', ...
%                          {'Scan 1 (200)', 'Scan 2 (100)', 'vvnbk', ...
%                    'Choose'});
  
  for moden = 1:3
    
    if moden == 1
      mode = 'Scan 1 (200)';
      files =  create_file_string(['-name summaryQA.xml ' ...
                          '-and -path \*scan1\* ' ...
                          '-and -not -path \*wrong\* ' ...
                          '-and -not -path \*html\*']);
    elseif moden == 2
      mode = 'Scan 2 (100)';      
      files =  create_file_string(['-name summaryQA.xml ' ...
                          '-and -path \*scan2\* ' ...
                          '-and -not -path \*wrong\* ' ...
                          '-and -not -path \*html\*']);
    elseif moden == 3
      mode = 'vvnbk';
      files =  create_file_string(['-name summaryQA.xml ' ...
                          '-and -path \*vvnbk\* ' ...
                          '-and -not -path \*wrong\* ' ...
                          '-and -not -path \*html\*']);
    else
      files = create_file_string(['-name summaryQA.xml ' ...
                          '-and -not -path \*wrong\* ' ...
                          '-and -not -path \*html\*']);
      
      viewfiles = cellfileparts(files);
      
      [sel,OK] = slistdlg('ListString', viewfiles);
    end

    outname = [ pwd '/html/' mode '.xls'];    

    if exist(outname, 'file') && use_cached
      R0 = read_tab_delim(outname);
      disp(['Reading existing ' filename_only(outname) ' as cache.']);
      disp(['  -- found ' num2str(length(R0.sourcefile)) ' entries total']);
      newold = ismember(files, R0.sourcefile);
      disp(['  -- ' num2str(length(find(newold))) ' of '...
            num2str(length(files)) ' files have entries'])
      files = files(find(newold==0));
      if length(files) == 0
        disp('No new files found?')
        if moden < 3
          continue
        else
          return
        end
      else
        disp(['  -- ' num2str(length(files)) ' files to process'])
      end
    end
      
    % as of latest update to dicom2bxh software, "acquisitionmatrix" no
    % longer appears?
    uninteresting_fields = {'sfnrimagefile', 'diffimagefile', ...
                        'mracquisitiontype', 'imagednucleus', ...
                        'meanimagefile', 'softwareversions', ...
                        'scanner', 'scannermodelname', 'examnumber', ...
                        'protocolname', 'psdname', 'stdimagefile', ...
                        'studyid', 'timepoints', 'seriesnumber', ...
                        'magneticfield', 'scanoptions', ...
                        'acquisitionmatrix'};
    
    % fields to convert to text strings 
    num2str_insert_fields = {'acquisitionmatrix'};
    num2str_insert_char = {' by '};
    
    % those that should be displayed first...
    initial_fields = {'institution', 'scannermanufacturer', 'scandate'};
    clear S
    
    for i = 1:length(files)
      
      disp(['Reading ' files{i} '...']);
      
      S{i} = read_fbirn_qa_xml(files{i});
      
      % we are only interested in fieldnames across all scanners
      if i == 1
        fnames = setdiff(fieldnames(S{i}), uninteresting_fields);
      else
        fnames = intersect(fnames, fieldnames(S{i}));
      end
      
      % now fix problematic fields
      for j = 1:length(num2str_insert_fields)
        broken = 0;
        fname = num2str_insert_fields{j};
        try
          dat = getfield(S{i}, fname);
          S{i} = rmfield(S{i}, fname);
          % dat should be numeric array
          if ~isnumeric(dat) || length(dat) < 2
            error
          end
        catch
          disp(['Failed to fix ' fname '; removing field instead']);
          broken = 1;
          continue
        end
        newdat = num2str(dat(1));
        for m = 2:length(dat)
          newdat = [newdat num2str_insert_char{j} ...
                    num2str(dat(m))];
        end
      end
      if ~broken
        S{i} = setfield(S{i}, fname, newdat);
      end
    end
    
    % now add initial fields and remaining fields to a new struct
    fnames = setdiff(fnames, initial_fields);

    for i = 1:length(initial_fields)
      
      fval = getfield(S{1}, initial_fields{i});
      if ~isnumeric(fval)
        % string needs to be cellified to assure proper concatenation of
        % values 
        fval = { fval };
      elseif length(fval) > 1
        % multiple entry numerics need cellification to keep them together
        fval = { fval };
      end
      
      for j = 2:length(files)
        fval = [fval getfield(S{j}, initial_fields{i})];
      end
      
      if i == 1
        % need cell protection only if cell
        if iscell(fval)
          R = struct(initial_fields{i}, {fval});
        else
          R = struct(initial_fields{i}, fval);
        end
      else
        R = setfield(R, initial_fields{i}, fval);  
      end
      
    end

    for i = 1:length(fnames)
      
      fval = getfield(S{1}, fnames{i});
      if ~isnumeric(fval)
        % string needs to be cellified to assure concatenation of values
        fval = { fval };
      elseif length(fval) > 1
        % multiple entry numerics need cellification to keep them together
        fval = { fval };      
      end
      
      for j = 2:length(files)
        fval = [fval getfield(S{j}, fnames{i})];
      end
      
      R = setfield(R, fnames{i}, fval);  
      
    end

    % now add to existing entries if any
    if exist('R0', 'var') && use_cached
      R = merge_structs(R0, R);
    end
    
    disp(['Writing to ' outname]);
    write_tab_delim(outname, R);
    
  end
  
