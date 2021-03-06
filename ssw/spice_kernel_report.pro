;+
; Project     :	STEREO - SSC
;
; Name        :	SPICE_KERNEL_REPORT
;
; Purpose     :	Reports which SPICE kernels are loaded.
;
; Category    :	STEREO, Orbit
;
; Explanation :	This procedure prints out the filename of each loaded SPICE
;               kernel, including those loaded by hand.  Mainly used for
;               debugging.
;
; Syntax      :	SPICE_KERNEL_REPORT
;
; Inputs      :	None.
;
; Opt. Inputs :	None.
;
; Outputs     :	None.
;
; Opt. Outputs:	None.
;
; Keywords    :	KERNELS = Returns the list of loaded kernels.
;
;               QUIET  = If set, don't print the kernel list to the screen.
;
;               ERRMSG = If defined and passed, then any error messages will be
;                        returned to the user in this parameter rather than
;                        depending on the MESSAGE routine in IDL.  If no errors
;                        are encountered, then a null string is returned.  In
;                        order to use this feature, ERRMSG must be defined
;                        first, e.g.
;
;                               ERRMSG = ''
;                               SPICE_KERNEL_REPORT, ERRMSG=ERRMSG
;                               IF ERRMSG NE '' THEN ...
;
; Calls       :	TEST_SPICE_ICY_DLM, CSPICE_KTOTAL, CSPICE_KDATA, DELVARX,
;               BOOST_ARRAY
;
; Common      :	None.
;
; Env. Vars.  : None.
;
; Restrictions:	This procedure works in conjunction with the Icy/CSPICE
;               package, which is implemented as an IDL Dynamically Loadable
;               Module (DLM).  The Icy source code can be downloaded from
;
;                       ftp://naif.jpl.nasa.gov/pub/naif/toolkit/IDL
;
;               Because this uses dynamic frames, it requires Icy/CSPICE
;               version N0058 or higher.
;
; Side effects:	None.
;
; Prev. Hist. :	None.
;
; History     :	Version 1, 27-Oct-2005, William Thompson, GSFC
;               Version 2, 20-Mar-2006, William Thompson, GSFC
;                       Added keyword QUIET
;
; Contact     :	WTHOMPSON
;-
;
pro spice_kernel_report, kernels=kernels, quiet=quiet, errmsg=errmsg
on_error, 2
;
;  Make sure that the SPICE/Icy DLM is available.
;
if not test_spice_icy_dlm() then begin
    message = 'SPICE/Icy DLM not available'
    goto, handle_error
endif
;
;  Use CSPICE_KTOTAL to get the total number of kernels.
;
cspice_ktotal, 'ALL', count
;
;  Step through the kernels, and get the filename of each.
;
delvarx, kernels
for i=0,count-1 do begin
    cspice_kdata, i, 'ALL', file, type, source, handle, found
    if found then begin
        if not keyword_set(quiet) then print, file
        boost_array, kernels, file
    end else print, 'No kernel found with index: ' + string(i)
endfor
if n_elements(kernels) ne 0 then kernels = reform(kernels,/overwrite)
;
return
;
;  Error handling point.
;
handle_error:
if n_elements(errmsg) eq 0 then message, message else $
  errmsg = 'spice_kernel_report: ' + message
;
end
