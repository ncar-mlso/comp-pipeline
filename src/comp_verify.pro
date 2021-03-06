; docformat = 'rst'

;+
; Verify the integrity of the data for a given date.
;
; :Params:
;   date : in, required, type=string
;     date to process, in YYYYMMDD format
;
; :Keywords:
;   config_filename, in, optional, type=string
;     configuration filename to use, default is `comp.cfg` in the `src`
;     directory
;   status : out, optional, type=integer
;     set to a named variable to retrieve the status of the date: 0 for success,
;     anything else indicates a problem
;
; :Author:
;   MLSO Software Team
;-
pro comp_verify, date, config_filename=config_filename, status=status
  compile_opt strictarr
  @comp_config_common

  status = 0L

  _config_filename = file_expand_path(n_elements(config_filename) eq 0L $
                       ? filepath('comp.cfg', root=mg_src_root()) $
                       : config_filename)

  if (n_elements(date) eq 0L) then begin
    mg_log, 'date argument is missing', name='comp', /error
    status = 1L
    goto, done
  endif

  if (~file_test(_config_filename, /regular)) then begin
    mg_log, 'config file not found', name='comp', /error
    status = 1L
    goto, done
  endif

  comp_configuration, config_filename=_config_filename
  comp_setup_loggers
  comp_setup_loggers_date, date

  logger_name = 'comp/verify'

  ; list_file : listing of the tar file for that date 
  ; log_file  : original t1.log file 

  ; verify that the listing of the tar files includes all files and 
  ; only all the files that are in the original t1.log

  ; NOTE: the tar file includes the t1.log itself so the list_file 
  ;       has one extra line 

  mg_log, 'verifying %s', date, name=logger_name, /info
  mg_log, 'raw directory %s', filepath(date, root=raw_basedir), $
          name=logger_name, /info

  ; don't check days with no data
  tarball_filename = filepath(date + '.comp.l0.tgz', $
                              subdir=date, $
                              root=raw_basedir)

  fits_files = file_search(filepath('*.FTS', subdir=date, root=raw_basedir), $
                           count=n_fits_files)
  if (n_fits_files eq 0L && ~file_test(tarball_filename)) then begin
    mg_log, 'no FTS files or tarball, skipping', name=logger_name, /info
    goto, done
  endif

  log_filename = filepath(date + '.comp.t1.log', $
                          subdir=date, $
                          root=raw_basedir)
  list_filename = filepath(date + '.comp.l0.tarlist', $
                           subdir=date, $
                           root=raw_basedir)

  ; TEST: check if log/list files exist
  if (~file_exist(log_filename)) then begin 
     mg_log, 't1.log file not found', name=logger_name, /error
     status = 1L
     goto, done
  endif else begin 
    if (~file_exist(list_filename)) then begin 
      mg_log, 'tarlist file not found'
      status = 1L
      goto, done
    endif 
  endelse 

  ; TEST: if log file and list file exist, check number of lines:
  ;   list_file # of lines = log_file # of lines - 1
  ;   because the t1.log file is included in the tar

  n_log_lines  = file_lines(log_filename)
  n_list_lines = file_lines(list_filename)

  mg_log, 'log file: %s', file_basename(log_filename), name=logger_name, /info
  mg_log, 'log file # of lines: %d', n_log_lines, name=logger_name, /info
  mg_log, 'list file: %s', file_basename(list_filename), name=logger_name, /info
  mg_log, 'list file # of lines: %d', n_list_lines, name=logger_name, /info

  if ((n_log_lines ne n_list_lines - 1) || (n_list_lines eq 0)) then begin 
    mg_log, '# of lines does not match', name=logger_name, /error
    status = 1L
    goto, test1_done
  endif

  ; TEST: match sizes of files to log

  list_names = strarr(n_list_lines - 1L)
  list_sizes = lonarr(n_list_lines - 1L)

  line = ''
  openr, lun, list_filename, /get_lun
  for i = 0L, n_list_lines - 2L do begin 
    readf, lun, line
    tokens = strsplit(line, /extract)
    list_names[i] = tokens[5]
    list_sizes[i] = tokens[2]
  endfor
  free_lun, lun

  ; TEST: check that any file listed in the log is also in the list - no missing
  ; TEST: check that any file listed in the log is listed only one -- no double  
  ; TEST: check that all files have the correct size 
 
  log_name = '' 
  log_size = 0L

  openr, lun , log_filename, /get_lun
  for  j = 0, n_log_lines - 1L do begin 
    readf, lun, log_name, log_size, format='(a19, 2x, f12.0)'
    pick = where(list_names eq log_name, npick)

    if (npick eq 1) then begin
      if (log_size ne list_sizes[pick]) then begin
        mg_log, 'file lists don''t match for %s: log size %d, list size %d', $
                log_name, log_size, list_sizes[pick], $
                name=logger_name, /error

        status = 1L
        goto, test1_done
      endif
    endif else begin 
      if (npick lt 1L) then begin
        mg_log, 'log file %s missing in tar list', log_name, $
                name=logger_name, /error
      endif

      if (npick lt 1L) then begin
        mg_log, 'log file %s in tar list %d times', log_name, npick, $
                name=logger_name, /error
      endif

      status = 1L
      goto, test1_done
    endelse 
  endfor 
  free_lun, lun

  ; TEST: check range of file sizes
  testsize = ulong64(list_sizes)
  minsize  = min(testsize)
  maxsize  = max(testsize)

  ; changed to acount for larger 17-points files
  ; if (minsize ge 81996480 and maxsize le 254393280) then begin

  if ((minsize ge 81996480) and (maxsize le 430994880)) then begin 
    mg_log, 'L0 FITS file sizes (%sB - %sB) OK', $
            mg_float2str(minsize, places_sep=','), $
            mg_float2str(maxsize, places_sep=','), $
            name=logger_name, /info
  endif else begin
    mg_log, 'L0 FITS file sizes (%sB - %sB) out of expected range', $
            mg_float2str(minsize, places_sep=','), $
            mg_float2str(maxsize, places_sep=','), $
            name=logger_name, /error

    status = 1L
    goto, test1_done
  endelse

  test1_done:

  ; read log to find names and sizes 

  log_names = strarr(n_log_lines)
  log_sizes = lonarr(n_log_lines)

  openr, lun, log_filename, /get_lun
  readf, lun, log_names, format='(a19)'
  free_lun, lun

  openr, lun, log_filename, /get_lun
  readf, lun, log_sizes, format='(20x, f12.0)'
  free_lun, lun

  ; TEST: check that any file listed in the list is also in the t1.log
  ; (e.g. no extra FTS files were put in the directory from other days 
  ; and went into the tar file)

  ; TEST: check again that any file listed in the list has the correct size
  ; this should be no different from test above

  ; TEST: check that any file listed in the list has the correct protection

  protection = '-rw-rw-r--'

  tempf = ''
  openr, lun, list_filename, /get_lun
  for j = 0L, n_list_lines - 2L do begin 
    readf, lun, tempf

    ; read files and size in the tar list 
    tokens = strsplit(tempf, /extract)
    filename = tokens[5]
    filesize = ulong64(tokens[2])

    if (tokens[0] ne protection) then begin 
      mg_log, 'protection for %s is wrong: %s', filename, tokens[0], $
              name=logger_name, /error
      status = 1L
      goto, test2_done
    endif

    pick = where(log_names eq filename, npick)
    if (npick lt 1) then begin
      mg_log, 'extra file %s found in tar list', filename, $
              name=logger_name, /error
      status = 1L
      goto, test2_done
    endif else begin 
      if (filesize ne log_sizes[pick]) then begin 
        mg_log, '%s has size %sB in list file, %sB in log file', $
                mg_float2str(filesize, places_sep=','), $
                mg_float2str(log_sizes[pick], places_sep=','), $
                name=logger_name, /error

        status = 1L
        goto, test2_done
      endif
    endelse 
  endfor 

  if (n_log_lines eq n_list_lines - 1L) then begin
    mg_log, 'no extra files in tar listing and protection OK', $
            name=logger_name, /info
  endif

  test2_done:
  free_lun, lun

  ; TEST: tgz size

  tarball_size = mg_filesize(tarball_filename)

  if (~file_test(tarball_filename, /regular)) then begin
    mg_log, 'no tarball', name=logger_name, /error
    status = 1
    goto, compress_ratio_done
  endif

  test_tgz_compression_ratio = 1B
  if (test_tgz_compression_ratio) then begin 
    ; test the size of tgz vs. entire directory of raw files
    ; compression factor should be 15-16%

    du_cmd = string(filepath(date, root=raw_basedir), format='(%"du -sb %s")')
    spawn, du_cmd, du_output
    tokens = strsplit(du_output[0], /extract)
    dir_size = ulong64(tokens[0])

    compress_ratio = dir_size / 2.0 / tarball_size

    mg_log, 'tarball size: %s bytes', $
            mg_float2str(tarball_size, places_sep=','), $
            name=logger_name, /info
    mg_log, 'dir size: %s bytes', $
            mg_float2str(dir_size, places_sep=','), $
            name=logger_name, /info
    mg_log, 'compression ratio: %0.2f', compress_ratio, name=logger_name, /info

    if ((compress_ratio ge 1.18) or (compress_ratio le 1.14)) then begin 
      mg_log, 'unusual compression ratio %0.2f', compress_ratio, $
              name=logger_name, /warn
      status = 1L
      goto, compress_ratio_done
    endif
  endif else begin
    mg_log, 'skipping tarball compression ratio check', name=logger_name, /info
  endelse

  compress_ratio_done:

  ; TEST: check if there are files in the directory that should not be there 

  files = file_search(filepath('*', subdir=date, root=raw_basedir), count=n_files)
  if (n_log_lines lt n_files - 3L) then begin
    n_extra = n_files - 3L - n_log_files
    mg_log, 'extra %d file%s in raw dir: %d in log, %d in dir', $
            n_extra, n_extra eq 1 ? '' : 's', n_log_lines, n_files, $
            name=logger_name, /error
    status = 1B
    goto, extra_files_done
  endif else if (n_log_lines gt n_files - 3L) then begin
    n_missing = n_log_lines - n_files + 3L
    mg_log, 'missing %d file%s in raw dir: %d in log, %d in dir', $
            n_missing, n_missing eq 1 ? '' : 's', n_log_lines, n_files, $
            name=logger_name, /error
    status = 1B
    goto, extra_files_done
  endif else begin
    mg_log, 'number of files OK', name=logger_name, /info
  endelse

  extra_files_done:

  ; TEST: check HPSS for L0 tarball of correct size, ownership, and protections

  check_hpss = 1B
  if (check_hpss) then begin
    year = strmid(date, 0, 4)
    hsi_cmd = string(hsi_dir, hsi_dir eq '' ? '' : '/', year, date, $
                     format='(%"%s%shsi ls -l /CORDYN/COMP/%s/%s.comp.l0.tgz")')
    spawn, hsi_cmd, hsi_output, hsi_error_output, exit_status=exit_status
    if (exit_status ne 0L) then begin
      mg_log, 'problem connecting to HPSS with command: %s', hsi_cmd, $
              name=logger_name, /error
      mg_log, '%s', mg_strmerge(hsi_error_output), name=logger_name, /error
      status = 1
      goto, hpss_done
    endif

    ; for some reason, hsi puts its output in stderr
    matches = stregex(hsi_error_output, date + '\.comp\.l0\.tgz', /boolean)
    ind = where(matches, count)
    if (count eq 0L) then begin
      mg_log, 'L0 tarball for %s not found on HPSS', date, $
              name=logger_name, /error
      status = 1L
      goto, hpss_done
    endif else begin
      status_line = hsi_error_output[ind[0]]
      tokens = strsplit(status_line, /extract)

      ; check group ownership of tarball on HPSS
      if (tokens[3] ne 'cordyn') then begin
        mg_log, 'incorrect group owner %s for tarball on HPSS', $
                tokens[3], name=logger_name, /error
        status = 1L
        goto, hpss_done
      endif

      ; check protection of tarball on HPSS
      if (tokens[0] ne '-rw-rw-r--') then begin
        mg_log, 'incorrect permissions %s for tarball on HPSS', $
                tokens[0], name=logger_name, /error
        status = 1L
        goto, hpss_done
      endif

      ; check size of tarball on HPSS
      if (ulong64(tokens[4]) ne tarball_size) then begin
        mg_log, 'incorrect size %sB for tarball on HPSS', $
                mg_float2str(ulong64(tokens[4]), places_sep=','), $
                name=logger_name, /error
        status = 1L
        goto, hpss_done
      endif

      mg_log, 'verified tarball on HPSS', $
              name=logger_name, /info
    endelse
  endif else begin
    mg_log, 'skipping HPSS check', name=logger_name, /info
  endelse

  hpss_done:

  done:

  if (status eq 0L) then begin
    mg_log, 'verification succeeded', name=logger_name, /info
  endif else begin
    mg_log, 'verification failed', name=logger_name, /error
  endelse
end


; main-level example program

dir = '/hao/acos/sw/idl/comp-pipeline/config'
cfile = 'comp.mgalloy.kaula.production.cfg'
config_filename = filepath(cfile, root=dir)

comp_verify, '20170712', config_filename=config_filename

end
