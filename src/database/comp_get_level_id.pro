; docformat = 'rst'

;+
; Retrieve a level ID given a level name. Always returns a level ID, uses the
; 'unknown' level if the given level name is not found.
;
; :Returns:
;   long
;
; :Params:
;   level_name : in, required, type=string
;     name of a level
;
; :Keywords:
;   database : in, required, type=object
;     database object
;   count : out, optional, type=long
;     number of levels found matching given name; if 0, returns 'unknown' level
;-
function comp_get_level_id, level_name, database=db, count=count
  compile_opt strictarr

  q = 'select count(level_id) from comp_level where level=''%s'''
  count_result = db->query(q, level_name)
  count = count_result.count_level_id_

  _level_name = count eq 0 ? 'unk' : level_name

  level_results = db->query('select * from comp_level where level=''%s''', $
                            _level_name, fields=fields)
  return, level_results[0].level_id
end
