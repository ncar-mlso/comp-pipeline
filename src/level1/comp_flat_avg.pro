; docformat = 'rst'

;+
; :History:
;   used temporary and compound assignment operators to save memory
;     Oct 3 2014  GdT
;-
pro comp_flat_avg, date_dir, time, wave, uniq_waves, exposure, fcbin, flats
  compile_opt strictarr
  ; skip first image at each wavelength ('yes') or just first image in recipe ('no')
  skip_first = 'no'

  nwaves = n_elements(uniq_waves)

  ; do not use first image at each wavelength
  wave[0] = -1   ; do not use first image
  if (skip_first eq 'yes') then begin
    for i = 0L, nwaves - 1L do begin
      good = where(wave eq uniq_waves[i], count)
      if (count eq 0) then begin
        mg_log, 'no good wave in first loop', name='comp', /warn
        continue
      endif
      wave[good[0]] = -1
    endfor
  endif

  flats = fltarr(1024, 1024, nwaves)
  for i = 0L, nwaves - 1L do begin
    good = where(wave eq uniq_waves[i], count)
    if (count eq 0) then begin
      mg_log, 'no good wave in second loop', name='comp', /warn
      continue
    endif

    for j = 0L, count - 1L do begin
      fits_read, fcbin, dat, header, exten_no=good[j] + 1
      exposure = sxpar(header, 'EXPOSURE')

      if (sxpar(header, 'DEMULT') eq 0) then dat = comp_demultiplex(temporary(dat))
      dat = float(dat)
      dat -= comp_dark_interp(date_dir, time, exposure)
      dat = comp_fixrock(temporary(dat), 0.03)
      dat = comp_fix_image(temporary(dat))
      flats[*, *, i] += dat
    endfor
    flats[*, *, i] = temporary(flats[*, *, i]) / float(count)
  endfor
  fits_close, fcbin
end