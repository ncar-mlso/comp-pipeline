; docformat = 'rst'


;+
; Fitting function for `POWELL`.
;
; :Returns:
;   chi-squared
;
; :Params:
;   x : in, required, type=fltarr
;     parameters of fit, either 4 or 5 elements
;-
function comp_powfunc, x
  compile_opt strictarr
  common fit, wav, lambda, solar_spec, telluric_spec, $
              filter_trans_on, filter_trans_off, obs, back

  debug = 0B

  nwave   = n_elements(wav)
  nlambda = n_elements(lambda)
  nparam  = n_elements(x)

  ; shift solar and telluric spectra
  dlam = lambda[1] - lambda[0]   ; wavelength spacing of spectra
  shift_sol = interpolate(solar_spec, dindgen(nlambda) + x[0] / dlam, $
                          missing=1.0, /double)
  if (nparam eq 4) then begin
    shift_tell = interpolate(telluric_spec, dindgen(nlambda) + x[0] / dlam, $
                             missing=1.0, /double)
  endif else begin
    shift_tell = interpolate(telluric_spec, dindgen(nlambda) + x[4] / dlam, $
                             missing=1.0, /double)
  endelse

  ; apply h2o factor to telluric spectrum
  x[1] = abs(x[1])
  shift_tell = (1.0 - (1.0 - shift_tell) * x[1]) > 0.0

  spec_on  = dblarr(nwave)
  spec_off = dblarr(nwave)
  for i = 0L, nwave - 1L do begin
    spec_on[i]  = x[2] * total(filter_trans_on[*, i] * shift_sol * shift_tell)
    spec_off[i] = x[3] * total(filter_trans_off[*, i] * shift_sol * shift_tell)
  endfor

  if (keyword_set(debug)) then begin
    plot, lambda, shift_sol, charsize=2
    plot, lambda, shift_tell, charsize=2
    plot, wav, spec_on, psym=4, charsize=2
    oplot, wav, obs
  endif

  chisq = total((spec_on - obs)^2 + (spec_off - back)^2)
  ;chisq = total((spec_on - obs)^2)
  return, chisq
end


;+
; Procedure to calibrate the wavelength scale of the comp instrument by fitting
; the intensity vs. wavelength in 11 point flat files to a reference spectrum.
;
; :Params: 
;   date_dir : in
;   lam0 : in
;     central wavelength of region to fit (1074.7 or 1079.8 nm)
;
; :Keywords:
;   offset : out, optional, type="fltarr(n_flats, n_beams)"
;     wavelength offset (nm) True Wavelength = CoMP Wavelength + Offset
;   h2o : out, optional, type="fltarr(n_flats, n_beams)"
;     h2o factor
;   chisq : out, optional, type="fltarr(n_flats, n_beams)"
;     set to a named variable to retrieve the minimums of the function minimized
;     by `POWELL`
;   n_flats : out, optional, type=long
;     set to a named variable to retrieve the number of 11 pt flats for the
;     given central wavelength
;   flat_times : out, optional, type=fltarr(n_flats)
;     times flats were taken
;   wavelengths : out, optional, type="fltarr(n_flats, n_wavelengths)"
;     set to a named variable to retrieve the wavelengths for each 11 pt flat
;   correction_factors : out, optional, type="fltarr(n_flats, n_wavelengths)"
;     set to a named variable to retrieve the correction factors determined from
;     each 11 pt flat for each of the 11 wavelengths
;-
pro comp_calibrate_wavelength_2, date_dir, lam0, $
                                 offset=offset, $
                                 h2o=h2o, $
                                 chisq=powell_chisq, $
                                 n_flats=n_flats, $
                                 flat_times=flat_times, $
                                 wavelengths=wavelengths, $
                                 correction_factors=correction_factors
  compile_opt strictarr
  common fit, wav, lambda, solar_spec, telluric_spec, $
              filter_trans_on, filter_trans_off, obs, back

  @comp_config_common
  @comp_constants_common
  @comp_mask_constants_common

  debug = 1B     ; debug mode, 'yes' or 'no'

  ; open flat file for this day
  flat_filename = filepath(string(date_dir, format='(%"%s.comp.flat.fts")'), $
                           subdir=[date_dir, 'level1'], $
                           root=process_basedir)

  fits_open, flat_filename, fcb       ; open input file
  num = fcb.nextend                 ; get number of extensions

  ; define masks for each beam
  fits_read, fcb, d, flat_header, exten_no=1, /header_only   ; get header information

  mask1 = comp_mask_1024_1(flat_header)
  mask2 = comp_mask_1024_2(flat_header)
  good1 = where(mask1 eq 1.0)
  good2 = where(mask2 eq 1.0)

  ; find 11 wavelength flats in flat file
  nwave = 11        ; use only 11 wavelength data

  fits_read, fcb, waves, header, exten_no=num - 1   ; read times for flats
  fits_read, fcb, times, header, exten_no=num - 2   ; read times for flats

  u_time = times[uniq(times, sort(times))]   ; identify unique observation times

  mg_log, 'times: %s', strjoin(string(u_time, format='(F0.3)'), ', ' ), name='comp', /debug

  n_flats = 0
  f_index = intarr(10)   ; array to hold extension index of first flat in sequence
  for i = 0L, n_elements(u_time) - 1L do begin
    use = where(times eq u_time[i],count)
    ; just look for 11 wavelength flats near target wavelength
    if ((count eq 22) and (abs(lam0 - mean(abs(waves[use]))) lt 2.0)) then begin
      f_index[n_flats] = use[0] + 1
      n_flats += 1
    endif
  endfor
  f_index = f_index[0:n_flats - 1]
  mg_log, 'f_index: %s', strjoin(strtrim(f_index, 2), ', '), name='comp', /debug
  mg_log, '%d 11 wavelengths flats at %0.2f nm', n_flats, lam0, name='comp', /debug

  if (n_flats gt 0) then begin
    ; get solar and telluric spectra in this region from atlas
    comp_get_spectrum_solar_telluric, lam0, lambda, solar_spec, telluric_spec
    nlambda = n_elements(lambda)
    dlam = lambda[1] - lambda[0]   ; wavelength spacing of spectra

    solar_spec = solar_spec / max(solar_spec)
    telluric_spec = telluric_spec / max(telluric_spec)

    ; create arrays to hold results
    offset             = fltarr(n_flats, 2)
    h2o                = fltarr(n_flats, 2)
    off_tell           = fltarr(n_flats, 2)
    wavelengths        = fltarr(n_flats, 11)
    correction_factors = fltarr(n_flats, 11)
    powell_chisq       = fltarr(n_flats, 2)

    flat_times         = times[f_index]

    ; loop over nflats flats
    for iflat = 0, n_flats - 1 do begin
      wav   = dblarr(nwave)
      pol   = strarr(nwave)
      obs1  = dblarr(nwave)
      obs2  = dblarr(nwave)
      back1 = dblarr(nwave)
      back2 = dblarr(nwave)

      ; read in and average observations over annulus
      for i = 0, nwave - 1 do begin
        ; beam 1
        fits_read, fcb, d1, header, exten_no=i + f_index[iflat]
        wav[i]   = double(sxpar(header, 'WAVELENG'))
        wavelengths[iflat, i] = wav[i]

        pol[i]   = double(sxpar(header, 'POLSTATE'))
        datetime = sxpar(header, 'FILENAME')

        obs1[i]  = median(d1[good1])
        back2[i] = median(d1[good2])
    
        ; beam 2
        fits_read, fcb, d2, header, exten_no=2 * nwave - i + f_index[iflat] - 1
        obs2[i]  = median(d2[good2])
        back1[i] = median(d2[good1])
      endfor

      ; put data in order of increasing wavelength
      s     = sort(wav)
      wav   = wav[s]
      obs1  = obs1[s]
      obs2  = obs2[s]
      back1 = back1[s]
      back2 = back2[s]
      pol   = pol[s]

      ; fit continuum in order to detrend spectrum
      w = wav - lam0
  
      ; define continuum wavelength points
      if (lam0 eq 1074.7) then begin
        to_fit_obs = [0, 1, 6, 10]
      endif else begin
        to_fit_obs = [0, 2, 4, 8, 10]
      endelse
  
      ; fit observations with a 2nd order polynomial
      c = poly_fit(w[to_fit_obs], obs1[to_fit_obs], 2, chisq=chisq)
      ofit1 = poly(w, c)
  
      ; fit observations with a 2nd order polynomial
      c = poly_fit(w[to_fit_obs], obs2[to_fit_obs], 2, chisq=chisq)
      ofit2 = poly(w, c)
  
      ; fit background continuum
      if (lam0 eq 1074.7) then begin
        to_fit_back = [0, 5, 7, 10]
      endif else begin
        to_fit_back = [0, 3, 6, 9]
      endelse

      ; fit observations with a 2nd order polynomial
      c = poly_fit(w[to_fit_back], back1[to_fit_back], 2, chisq=chisq)
      bfit1 = poly(w, c)
  
      ; fit observations with a 2nd order polynomial
      c = poly_fit(w[to_fit_back], back2[to_fit_back], 2, chisq=chisq)
      bfit2 = poly(w, c)

      ; plot data and fit to continuum
      if (keyword_set(debug)) then begin
        window, xsize=900, ysize=1000, /free, $
                title=string(f_index[iflat], file_basename(datetime, '.FTS'), $
                             format='(%"ext: %d, datetime: %s")')
        !p.multi = [0, 2, 3, 0, 0]

        plot, wav, obs1, $
              psym=2, $
              title='Observations and Continuum Fit', $
              xtitle='CoMP Wavelength (nm)', $
              ytitle='Intensity (ppm)', $
              yrange=[0.0, 1.1 * (max(obs1) > max(obs2))], $
              charsize=1.75
        oplot, wav, ofit1
        oplot, wav, obs2, psym=4
        oplot, wav, ofit2, linesty=1
        oplot, wav[to_fit_obs], obs1[to_fit_obs], psym=5
        oplot, wav[to_fit_obs], obs2[to_fit_obs], psym=5

        plot, wav, back1, $
              psym=2, $
              title='Background and Continuum Fit', $
              xtitle='CoMP Wavelength (nm)', $
              ytitle='Intensity (ppm)',$
              yrange=[0.0, 1.1*(max(obs1) > max(obs2))], $
              charsize=1.75
        oplot, wav, bfit1
        oplot, wav, back2, psym=4
        oplot, wav, bfit2, linesty=1
        oplot, wav[to_fit_back], back1[to_fit_back], psym=5
        oplot, wav[to_fit_back], back2[to_fit_back], psym=5

        xyouts, 0.1, 0.72, datetime, /normal, charsize=1.25
      endif
  
      ; divide data by fit
      obs1 /= ofit1
      obs2 /= ofit2
      back1 /= bfit1
      back2 /= bfit2

      ; get comp transmission profiles
      filter_trans_on  = fltarr(nlambda, nwave)
      filter_trans_off = fltarr(nlambda, nwave)
      for ii = 0, nwave - 1 do begin
        ; get CoMP transmission profiles
        comp_trans, wav[ii], lambda, trans_on, trans_off

        ; normalize area under filters to 1
        trans_on  = trans_on / total(trans_on)
        trans_off = trans_off / total(trans_off)

        filter_trans_on[*, ii]  = trans_on
        filter_trans_off[*, ii] = trans_off
      endfor
  
      ; fit wavelength offset ,continuum factor and h2o strength with powell minimization
      ; h2o strength is in units of nominal strength (1 = nominal, 0 = continuum)  
      ftol = 1.0d-8

      nparam = 4      ; either 4 or 5
      if ((nparam eq 4) and (lam0 eq 1074.7)) then begin
        p1 = [0.036d0, 0.84d0, 1.0d0, 1.0d0]
      endif
      if ((nparam eq 5) and (lam0 eq 1074.7)) then begin
        p1 = [0.036d0, 0.84d0, 1.0d0, 1.0d0, 0.036d0]
      endif
      if ((nparam eq 4) and (lam0 eq 1079.8)) then begin
        p1 = [0.036d0, 0.4d0, 1.0d0, 1.0d0]
      endif
      if ((nparam eq 5) and (lam0 eq 1079.8)) then begin
        p1 = [0.036d0, 0.4d0, 1.0d0, 1.0d0, 0.1d0]
      endif

      p2 = p1
    
      xi = dblarr(nparam, nparam)
      for i = 0, nparam - 1 do xi[i, i] = 1.d0
      obs  = obs1
      back = back1
  
      powell, p1, xi, ftol, fmin, 'comp_powfunc', /double, iter=n_iterations
      p1[1] = abs(p1[1])
      powell_chisq[iflat, 0] = fmin
      mg_log, '%d iterations', n_iterations, name='comp', /debug
      mg_log, 'p1: %s', strjoin(string(p1, format='(F0.4)'), ', '), $
              name='comp', /debug
      mg_log, 'min: %0.5f', fmin, name='comp', /debug

      xi = dblarr(nparam, nparam)
      for i = 0, nparam - 1 do xi[i, i] = 1.d0
      obs  = obs2
      back = back2
      powell, p2, xi, ftol, fmin, 'comp_powfunc', /double, iter=n_iterations
      p2[1] = abs(p2[1])
      powell_chisq[iflat, 1] = fmin
      mg_log, '%d iterations', n_iterations, name='comp', /debug
      mg_log, 'p2: %s', strjoin(string(p2, format='(F0.4)'), ', '), $
              name='comp', /debug
      mg_log, 'min: %0.5f', fmin, name='comp', /debug

      shift_sol = interpolate(solar_spec, $
                              dindgen(nlambda) + p1[0] / dlam, $
                              missing=1.0, $
                              /double)
      if (nparam eq 4) then begin
        shift_tell = interpolate(telluric_spec, $
                                 dindgen(nlambda) + p1[0] / dlam, $
                                 missing=1.0, $
                                 /double)
      endif else begin
        shift_tell = interpolate(telluric_spec, $
                                 dindgen(nlambda) + p1[4] / dlam, $
                                 missing=1.0, $
                                 /double)
      endelse
  
      ; apply h2o factor to telluric spectrum
      shift_tell = (1.0 - (1.0 - shift_tell) * p1[1]) > 0.0
  
      spec_on  = dblarr(nwave)
      spec_off = dblarr(nwave)
      for i = 0, nwave - 1 do begin
        spec_on[i]  = p1[2] * total(filter_trans_on[*, i] * shift_sol * shift_tell)
        spec_off[i] = p1[3] * total(filter_trans_off[*, i] * shift_sol * shift_tell)
      endfor

      correction_factors[iflat, *] = spec_on

      if (keyword_set(debug)) then begin
        plot, wav, obs1, $
              yrange=[0.0, 1.2], $
              psym=2, $
              xtitle='CoMP Wavelength (nm)', $
              ytitle='Normalized Intensity', $
              title='Observations and Fit', $
              charsize=1.75
        oplot, wav, spec_on
        xyouts, 0.1, 0.42, string(p1[0], format='("Offset:",f9.5," (nm)")'), $
                /normal, charsize=1.25
        xyouts, 0.1, 0.39, string(p1[1], format='("H2O:",f7.3)'), $
                /normal, charsize=1.25

        plot, wav, back1, $
              yrange=[0.0, 1.2], $
              psym=2, $
              xtitle='CoMP Wavelength (nm)', $
              ytitle='Normalized Intensity', $
              title='Observations and Fit', $
              charsize=1.75
        oplot, wav, spec_off
      endif

      shift_sol = interpolate(solar_spec, $
                              dindgen(nlambda) + p2[0] / dlam, $
                              missing=1.0, $
                              /double)
      if (nparam eq 4) then begin
        shift_tell = interpolate(telluric_spec, $
                                 dindgen(nlambda) + p2[0] / dlam, $
                                 missing=1.0, $
                                 /double)
      endif else begin
        shift_tell = interpolate(telluric_spec, $
                                 dindgen(nlambda) + p2[4] / dlam, $
                                 missing=1.0, $
                                 /double)
      endelse
  
      ; apply h2o factor to telluric spectrum
      shift_tell = (1.0 - (1.0 - shift_tell) * p2[1]) > 0.0

      spec_on  = dblarr(nwave)
      spec_off = dblarr(nwave)
      for i = 0, nwave - 1 do begin
        spec_on[i]  = p2[2] * total(filter_trans_on[*, i] * shift_sol * shift_tell)
        spec_off[i] = p2[3] * total(filter_trans_off[*, i] * shift_sol * shift_tell)
      endfor

      if (keyword_set(debug)) then begin
        plot, wav, obs2, $
              yrange=[0.0, 1.2], $
              psym=4, $
              xtitle='CoMP Wavelength (nm)', $
              ytitle='Normalized Intensity', $
              title='Observations and Fit', $
              charsize=1.75
        oplot, wav, spec_on
        xyouts, 0.1, 0.13, string(p2[0], format='("Offset:",f9.5," (nm)")'), $
                /normal, $
                charsize=1.25
        xyouts, 0.1, 0.1, string(p2[1], format='("H2O:",f7.3)'), $
                /normal, $
                charsize=1.25
        xyouts, 0.1, 0.05, 'True Wavelength = CoMP Wavelength + Offset',$
                /normal, $
                charsize=1.25

        plot, wav, back2, $
              yrange=[0.0, 1.2],$
              psym=2, $
              xtitle='CoMP Wavelength (nm)', $
              ytitle='Normalized Intensity', $
              title='Observations and Fit', $
              charsize=1.75
        oplot, wav, spec_off
      endif

      ; store results in arrays
      offset[iflat, 0] = p1[0]
      h2o[iflat, 0]    = p1[1]

      offset[iflat, 1] = p2[0]
      h2o[iflat, 1]    = p2[1]

      if (nparam eq 5) then begin
        off_tell[iflat, 0] = p1[4]
        off_tell[iflat, 1] = p2[4]
      endif
    endfor
  endif else begin
    offset     = 0.0
    h2o        = 0.0
    flat_times = 0.0
    off_tell   = 0.0
  endelse

  fits_close, fcb

  mg_log, 'done', name='comp', /info
end


; main-level example program

; configure
date = '20130115'
comp_initialize, date

config_filename = filepath('comp.mgalloy.mahi.latest.cfg', $
                           subdir=['..', '..', 'config'], $
                           root=mg_src_root())
comp_configuration, config_filename=config_filename

lam0 = 1074.7
;lam0 = 1079.8

comp_calibrate_wavelength_2, date, lam0, $
                             offset=offset, $
                             h2o=h2o, $
                             n_flats=n_flats, $
                             flat_times=flat_times, $
                             wavelengths=wavelengths, $
                             correction_factors=correction_factors, $
                             chisq=chisq

help, offset
print, offset
help, h2o
print, h2o
help, n_flats
help, flat_times
print, flat_times
help, wavelengths
print, wavelengths
help, correction_factors
print, correction_factors
help, chisq
print, chisq

end