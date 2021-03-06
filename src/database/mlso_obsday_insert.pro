; docformat = 'rst'

;+
; IDL function that checks if the passed date (observation day as YYYYMMDD) is
; in the mlso_numfiles database table. If it is, the corresponding day_id is
; returned. If it is not, a new entry in the table is created (day_id and
; obs_day fields) and the new day_id is returned.
;
; :History:
;   2017-03-20 Don Kolinski
;
; :Returns:
;   integer
;
; :Params:
;   date : in, required, type=string
;
; :Keywords:
;   config_filename : in, required, type=string
;     filename of config file containing database info/credentials
;   config_section : in, required, type=string
;     section of `config_filename` for the database to use
;   database : out, optional, type=object
;     set to a named variable to retrieve the database object
;   status : out, optional, type=long
;     set to a named variable to retrieve the status of the database connection,
;     0 for success
;   log_name : in, required, type=string
;     name of log to send log messages to
;-
function mlso_obsday_insert, date, $
                             config_filename, $
                             config_section, $
                             database=db, $
                             status=status, $
                             log_name=log_name
  compile_opt strictarr

  ; Connect to MLSO database.

  ; Note: The connect procedure accesses DB connection information in the file
  ;       .mysqldb. The "config_section" parameter specifies
  ;       which group of data to use.

  db = compdbmysql()
  db->connect, config_filename=config_filename, $
               config_section=config_section, $
               status=status, error_message=error_message
  if (status ne 0L) then begin
    mg_log, 'failed to connect to database', name=log_name, /error
    mg_log, '%s', error_message, name=log_name, /error
    return, !null
  endif

  db->getProperty, host_name=host
  mg_log, 'connected to %s', host, name=log_name, /info

  obs_day = strmid(date, 0, 4) + '-' + strmid(date, 4, 2) + '-' + strmid(date, 6, 2)
  obs_day_index = 0
	
  ; check to see if passed observation day date is in mlso_numfiles table
  obs_day_results = db->query('SELECT count(obs_day) FROM mlso_numfiles WHERE obs_day=''%s''', $
                              obs_day, fields=fields)
  obs_day_count = obs_day_results.count_obs_day_

  if (obs_day_count eq 0) then begin
    ; if not already in table, create a new entry for the passed observation day
    db->execute, 'INSERT INTO mlso_numfiles (obs_day) VALUES (''%s'') ', $
                 obs_day, $
                 status=status, error_message=error_message, sql_statement=sql_cmd
    if (status ne 0L) then begin
      mg_log, 'error inserting into mlso_numfiles table', name=log_name, /error
      mg_log, 'status: %d, error message: %s', status, error_message, $
              name=log_name, /error
      mg_log, 'SQL command: %s', sql_cmd, name=log_name, /error
    endif
		
    obs_day_index = db->query('SELECT LAST_INSERT_ID()')	
  endif else begin
    ; if it is in the database, get the corresponding index, day_id
    obs_day_results = db->query('SELECT day_id FROM mlso_numfiles WHERE obs_day=''%s''', $
                                obs_day, fields=fields)	
    obs_day_index = obs_day_results.day_id

    ; remove multiple entries
    if (n_elements(obs_day_index) gt 1L) then begin
      for i = 2L, n_elements(obs_day_index) - 1L do begin
        mg_log, 'deleting redundant day_id=%d', obs_day_index[i], name=log_name, /warn
        db->execute, 'DELETE FROM mlso_numfiles WHERE day_id=%d', obs_day_index[i], $
                     status=status, error_message=error_message, sql_statement=sql_cmd
        if (status ne 0L) then begin
          mg_log, 'error deleting redundant mlso_numfiles entry', name=log_name, /error
          mg_log, 'status: %d, error message: %s', status, error_message, $
                  name=log_name, /error
          mg_log, 'SQL command: %s', sql_cmd, name=log_name, /error
        endif
      endfor

      ; keep just the first one
      mg_log, 'keeping day_id=%d', obs_day_index[0], name=log_name, /debug
      obs_day_index = obs_day_index[0]
    endif
  endelse

  if (~arg_present(db)) then obj_destroy, db

  return, obs_day_index
end
