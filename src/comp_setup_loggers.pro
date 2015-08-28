; docformat = 'rst'

;+
; Defines the loggers and their levels.
;
; :Private:
;
; :Returns:
;   `strarr`
;
; :Keywords:
;   levels : out, optional, type=lonarr
;     set to a named variable to retrieve the levels of the loggers in the
;     return value
;-
function comp_setup_loggers_loggers, levels=levels
  compile_opt strictarr
  @comp_paths_common

  loggers = ['comp', 'comp/l1_process', 'comp/circfit', 'comp/quick_invert', $
             'comp/average', 'comp/dark_interp', 'comp/fix_crosstalk', $
             'comp/find_image', 'comp/find_post']
  levels = [log_level, $
            l1_process_log_level, $
            circfit_log_level, $
            quick_invert_log_level, $
            average_log_level, $
            dark_interp_log_level, $
            fix_crosstalk_log_level, $
            find_image_log_level, $
            find_post_log_level]
  return, loggers
end


;+
; Sets up output filename for all the loggers defined in
; `comp_setup_loggers_loggers`.
;
; :Params:
;   date_dir : in, required, type=string
;     day of year to process, in YYYYMMDD format
;-
pro comp_setup_loggers_date, date_dir
  compile_opt strictarr
  @comp_paths_common

  loggers = comp_setup_loggers_loggers()
  for i = 0L, n_elements(loggers) - 1L do begin
    mg_log, name=loggers[i], logger=logger
    cidx_dir = filepath('', subdir='cidx', root=log_dir)
    if (~file_test(cidx_dir, /directory)) then file_mkdir, cidx_dir
    logger->setProperty, filename=filepath(date_dir + '.log', root=cidx_dir)
  endfor
end


;+
; Sets up format and level for all the loggers defined in
; `comp_setup_loggers_loggers`.
;-
pro comp_setup_loggers
  compile_opt strictarr
  @comp_paths_common

  log_fmt = '%(time)s %(levelshortname)s: %(routine)s: %(message)s'
  log_time_fmt = '(C(CYI4, "-", CMOI2.2, "-", CDI2.2, " " CHI2.2, ":", CMI2.2, ":", CSI2.2))'
  loggers = comp_setup_loggers_loggers(levels=levels)
  for i = 0L, n_elements(loggers) - 1L do begin
    mg_log, name=loggers[i], logger=logger
    logger->setProperty, format=log_fmt, $
                         time_format=log_time_fmt, $
                         level=levels[i]
   endfor
end