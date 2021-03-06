; docformat = 'rst'

;+
; Create a mask for CoMP images in the 620x620 spatial resolution. Include the
; occulting disk, field stop, occulter post and the overlap of the two
; sub-images in the 1024x1024 format.
;
; THIS ASSUMES THAT THE IMAGE HAS ALREADY BEEN CENTERED USING THE CENTER OF THE
; OCCULTER.
;
; :Params:
;   fits_header : in, required, type=strarr
;     the primary header of the CoMP FITS file
;   mask : out
;     the mask image 
;
; :Keywords:
;   occ_fac
;   fld_fac
;
; :Author: Sitongia
;-
pro comp_make_mask2, fits_header, mask, occ_fac=occ_fac, fld_fac=fld_fac
  compile_opt strictarr

  @comp_constants_common
  @comp_mask_constants_common

  if(n_elements(occ_fac) eq 0) then occ_fac = 1.0
  if(n_elements(fld_fac) eq 0) then fld_fac = 1.0

  ; get parameters from FITS header
  
  ; look for new keyword
  fradius = sxpar(fits_header, 'FRADIUS', count=count)
  
  if (count eq 0) then begin
    ; old keywords
    occulter = {x: sxpar(fits_header, 'CRPIX1'), $
                y: sxpar(fits_header, 'CRPIX2'), $
                r: ((sxpar(fits_header, 'OCRAD1') + sxpar(fits_header, 'OCRAD2')) / 2.0)}

    field = {x:((sxpar(fits_header, 'FCENX1') + sxpar(fits_header, 'FCENX2')) / 2.0), $
             y:((sxpar(fits_header, 'FCENY1') + sxpar(fits_header, 'FCENY2')) / 2.0), $
             r:((sxpar(fits_header, 'FCRAD1') + sxpar(fits_header, 'FCRAD2')) / 2.0)}
      
    ; create the mask from individual masks
    ; occulter mask
    dmask = comp_disk_mask(occulter.r * occ_fac + occulter_offset)

    ; field mask
    field_mask = comp_field_mask(field.r * fld_fac + field_offset, $
                                 dx=(occulter.x - field.x), $
                                 dy=(occulter.y - field.y))
    
    mask = dmask * field_mask
  endif else begin
    occulter = {x: sxpar(fits_header, 'CRPIX1'), $
                y: sxpar(fits_header, 'CRPIX2'), $
                r: sxpar(fits_header, 'ORADIUS')}
      
    field = {x: sxpar(fits_header, 'FRPIX1'), $
             y: sxpar(fits_header, 'FRPIX2'), $
             r: sxpar(fits_header, 'FRADIUS')}

    post_angle = sxpar(fits_header, 'POSTPANG')
    overlap_angle = sxpar(fits_header, 'OVRLPANG')
    p_angle = sxpar(fits_header, 'SOLAR_P0')
    
    ; create the mask from individual masks

    ; occulter mask
    dmask = comp_disk_mask(occulter.r * occ_fac + occulter_offset)

    ; field mask
    field_mask = comp_field_mask(field.r * fld_fac + field_offset, $
                                 dx=(occulter.x - field.x), $
                                 dy=(occulter.y - field.y))

    ; post mask
    pmask = comp_post_mask(post_angle + 180. - p_angle - post_rotation, 35.0)
    
    ; overlap mask
    omask = comp_overlap_mask(field.r, overlap_angle + p_angle, $
                              dx=(occulter.x - field.x), $
                              dy=(occulter.y - field.y))
    
    mask = dmask * field_mask * pmask * omask
  endelse
  
end

CD, '/hao/kaula1/Data/CoMP/process/20120512'
fits_read,'20120512.170310.comp.1074.fts.gz',d,primary_header,/header_only,exten_no=0
comp_make_mask, '20120512', primary_header, mask
fits_read,'20120512.170310.comp.1074.fts.gz',image,header,exten_no=11
tvwin,bytscl(image*mask,0,5)
end
