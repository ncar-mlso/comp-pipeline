; docformat = 'rst'

;+
; Finds the nearest Stokes Q and U raw file to a specified CoMP raw file.
;
; :Returns:
;   string with name of nearest Q and U raw file
;
; :Uses:
;   comp_read_inventory_file, comp_constants_common, comp_paths_common,
;   comp_mask_constants_common
;
; :Params:
;   date_dir : in, required, type=string
;     the date directory name
;   headers : in, required, type="fltarr(ntags, nimg)"
;     the headers corresponding to the input filename
;   filename: in, required, type=string
; 
; :Keywords:
;   line : in, optional, type=string
;     which line to look for. Currently defaults to '1074', but should probably
;     update the code to determine it from the headers and/or filename
;
; :Author:
;   Joseph Plowman
;-
function comp_nearest_qufile, date_dir, headers, filename, line=line
  compile_opt strictarr

  @comp_constants_common
  @comp_paths_common
  @comp_mask_constants_common

  ; should just find this from header
  if (n_elements(line) eq 0L) then line = '1074'

  ; find the inventory file and read it
  invenfile = filepath(line + '_files.txt', $
                       subdir=date_dir, $
                       root=process_basedir)
  comp_read_inventory_file, invenfile, datafiles, exptimes, $
                            ndata, ndark, nopal, open, waves, polstates

  ; get the days and times from the filenames
  nfiles = n_elements(datafiles)
  files_split = strarr(nfiles, 3)
  for i = 0L, nfiles - 1L do begin
    files_split[i, *] = strsplit(datafiles[i], '.', /extract) 
  endfor
  days = files_split[*, 0]
  times = files_split[*, 1]

  ; require a file which has all of I+Q, I-Q, I+U, and I-U
  qucheck = total(polstates eq 'I+Q', 2) $
              and total(polstates eq 'I-Q', 2) $
              and total(polstates eq 'I+U', 2) $
              and total(polstates eq 'I-U', 2)

  ; find where our input filename lies in the list of data files:
  vindex = where(datafiles eq file_basename(filename))
  vindex = vindex[0]

  ; we want a Q and U file that has all the same wavelengths as our input file
  wavecheck = intarr(nfiles)
  for i = 0L, nfiles - 1L do begin
    wavecheck[i] = product(waves[i, *] eq waves[vindex, *])
  endfor

  ; lastly, we want the file that's closest in time
  quindices = where(qucheck and days eq days[vindex] and wavecheck)
  qunearest = quindices[value_locate(times[quindices], times[vindex])]

  qufile = filepath(datafiles[qunearest], subdir=date_dir, root=raw_basedir)
  return, qufile
end