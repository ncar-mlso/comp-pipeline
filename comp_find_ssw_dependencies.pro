; docformat = 'rst'

;+
; The CoMP pipeline ssw directory must be in the IDL path before the full ssw
; library directories.
;-
pro comp_find_ssw_dependencies, src, ssw_loc
  compile_opt strictarr

  ; needs to be done early, otherwise LIST will get compiled and confuse it
  resolve_routine, 'get_suncenter', $
                   /compile_full_file, /either, /no_recompile

  routines = file_search(src, '.pro', count=n_routines)

  for r = 0L, n_routines - 1L do begin
    if (~strmatch(routines[r], '*_common')) then begin
      resolve_routine, routines[r], /either, /compile_full_file, /no_recompile
    endif
  endfor

  cd, 'ssw'
  exceptions = ['utcommon', 'get_suncenter']

  skip_routines = ['CSPICE_BODVAR', 'CSPICE_CKCOV', 'CSPICE_CKGP', $
                   'CSPICE_CKOBJ', 'CSPICE_CONICS', 'CSPICE_ET2UTC', $
                   'CSPICE_FURNSH', 'CSPICE_KDATA', 'CSPICE_KTOTAL', $
                   'CSPICE_M2EUL', 'CSPICE_OSCELT', 'CSPICE_PXFORM', $
                   'CSPICE_RECGEO', 'CSPICE_RECLAT', 'CSPICE_SCE2C', $
                   'CSPICE_SPKCOV', 'CSPICE_SPKEZR', 'CSPICE_SPKOBJ', $
                   'CSPICE_STR2ET', 'CSPICE_SXFORM', 'CSPICE_UNLOAD', $
                   'CSPICE_UTC2ET', 'COMP_FIND_CODE_VERSION']

  ssw_files = file_search(filepath('*.pro', root='.'), count=n_files)
  for f = 0L, n_files - 1L do begin
    routine = file_basename(ssw_files[f], '.pro')
    ind = where(routine eq exceptions, count)
    if (count eq 0L) then begin
      resolve_routine, routine, $
                       /compile_full_file, /either, /no_recompile
    endif
  endfor

  resolve_all, /continue_on_error, skip_routines=skip_routines
  help, /source, output=output

  continued_line = 0B

  for i = 0L, n_elements(output) - 1L do begin
    line = strtrim(output[i], 2)
    if (line eq '$MAIN$' $
          or line eq 'Compiled Functions:' $
          or line eq 'Compiled Procedures:' $
          or line eq '') then begin
      continue
    endif

    ; long filenames could be broken across two lines
    tokens = strsplit(line, /extract, count=n_tokens)
    if (n_tokens eq 1) then begin
      if (continued_line) then begin
        continued_line = 0B
        file = tokens[0]
      endif else begin
        continued_line = 1B
        continue
      endelse
    endif else begin
      file = tokens[1]
    endelse

    if (strpos(file, ssw_loc) eq 0) then begin
      if (file_test(file_basename(file))) then begin
        print, file_basename(file), format='(%"%s already in comp-pipeline/ssw")'
      endif else begin
        print, file, format='(%"copying %s to comp-pipeline/ssw")'
        file_copy, file, '.'
      endelse
    endif
  endfor
end
